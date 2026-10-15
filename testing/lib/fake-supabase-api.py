#!/usr/bin/env python3
"""A stand-in for the Supabase endpoints this product touches, over a local
Postgres (testing/lib/local-postgres.sh).

    fake-supabase-api.py <port> <postgres-url> [--ref <project-ref>]
                         [--auth <superuser-url>] [--confirm-email]

Without `--auth` it is exactly the reference's stand-in: the ONE Management
API endpoint a migration runner (and the dashboard's SQL editor) uses,

    POST /v1/projects/<ref>/database/query   {"query": "<sql>"}

which hands the SQL to `psql` as the `postgres` role and answers the rows of
the last statement as a JSON array, an error as a non-2xx JSON `message`
carrying Postgres's own text. Only the bearer token's presence is checked.

`--auth <superuser-url>` adds what a PROJECT answers on its own URL, as far as
the app reaches it:

  /auth/v1/*   a GoTrue stand-in — settings, signup, token (password and
               refresh_token grants), user (GET, PUT), logout, recover,
               verify (token_hash), health. Users are rows in `auth.users` of
               the same database, created here through the superuser URL
               along with Supabase's `auth.uid()`, `auth.role()` and
               `auth.jwt()`, so a policy written for Supabase means here what
               it means there. Access tokens are HS256 JWTs with no `kid`,
               the shape a project on its legacy JWT secret issues, so
               supabase-js's getClaims() checks every one by calling GET
               /auth/v1/user — the server-side path the app's proxy takes.
               Every /auth/v1 call must carry the project's API key
               (`apikey` header), as Supabase's gateway requires.
  /rest/v1/<table>
               a PostgREST stand-in for the one call the tutorial makes,
               `select *`: the request's JWT (the user's, or the anon key)
               becomes `SET LOCAL ROLE` and `request.jwt.claims`, exactly what
               PostgREST does, so row-level security decides what comes back.

The anon key is printed on stdout at startup as `anon-key <jwt>`. Email is
never sent: what Supabase would mail (a confirmation, a recovery link) is
kept, and the e2e reads it back from GET /__fake/outbox. POST /__fake/config
with {"mailer_autoconfirm": bool, "email_allowed": [..] | null} switches
whether sign-up confirms at once (the default unless --confirm-email), and
models the built-in SMTP: with a list, only those addresses can be mailed
(Supabase's own email reaches only the organization's members), anyone else
gets 400 `email_address_not_authorized`.
"""
import base64
import hashlib
import hmac
import http.server
import json
import re
import secrets
import subprocess
import sys
import threading
import time
import urllib.parse
import uuid

PORT = int(sys.argv[1])
DB = sys.argv[2]
REF = sys.argv[sys.argv.index("--ref") + 1] if "--ref" in sys.argv else None
ADMIN = sys.argv[sys.argv.index("--auth") + 1] if "--auth" in sys.argv else None
ROUTE = re.compile(r"^/v1/projects/([a-z0-9]+)/database/query$")
JWT_SECRET = secrets.token_hex(32).encode()
BASE = f"http://127.0.0.1:{PORT}"
CONFIG = {"mailer_autoconfirm": "--confirm-email" not in sys.argv, "email_allowed": None}
OUTBOX: list = []
REFRESH: dict = {}
LOCK = threading.Lock()


def psql(sql: str, url: str = DB, **params) -> subprocess.CompletedProcess:
    argv = ["psql", url, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1"]
    for k, v in params.items():
        argv += ["-v", f"{k}={v}"]
    return subprocess.run(argv, input=sql, capture_output=True, text=True)


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def jwt_encode(claims: dict) -> str:
    head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    body = b64(json.dumps(claims, separators=(",", ":")).encode())
    sig = hmac.new(JWT_SECRET, f"{head}.{body}".encode(), hashlib.sha256).digest()
    return f"{head}.{body}.{b64(sig)}"


def jwt_decode(token: str):
    try:
        head, body, sig = token.split(".")
        want = hmac.new(JWT_SECRET, f"{head}.{body}".encode(), hashlib.sha256).digest()
        if not hmac.compare_digest(b64(want), sig):
            return None
        claims = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
        return claims if claims.get("exp", 0) > time.time() else None
    except Exception:
        return None


ANON_KEY = jwt_encode({"iss": "supabase-demo", "role": "anon", "iat": int(time.time()),
                       "exp": int(time.time()) + 10 * 365 * 86400})

AUTH_SCHEMA = """
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  email text UNIQUE NOT NULL,
  encrypted_password text NOT NULL,
  email_confirmed_at timestamptz,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}',
  last_sign_in_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('request.jwt.claim.role', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))::text
$$;
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
GRANT USAGE ON SCHEMA auth TO postgres, anon, authenticated;
GRANT SELECT, REFERENCES ON auth.users TO postgres;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA auth TO PUBLIC;
"""

USER_JSON = """
SELECT json_build_object(
  'id', id, 'aud', 'authenticated', 'role', 'authenticated', 'email', email, 'phone', '',
  'email_confirmed_at', email_confirmed_at, 'confirmed_at', email_confirmed_at,
  'last_sign_in_at', last_sign_in_at,
  'app_metadata', json_build_object('provider', 'email', 'providers', json_build_array('email')),
  'user_metadata', raw_user_meta_data,
  'identities', json_build_array(json_build_object(
     'identity_id', id, 'id', id, 'user_id', id, 'provider', 'email',
     'identity_data', json_build_object('sub', id, 'email', email, 'email_verified', email_confirmed_at IS NOT NULL),
     'created_at', created_at, 'updated_at', updated_at, 'last_sign_in_at', last_sign_in_at)),
  'created_at', created_at, 'updated_at', updated_at, 'is_anonymous', false)
FROM auth.users"""


def hash_password(password: str) -> str:
    salt = secrets.token_hex(8)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 10000).hex()
    return f"pbkdf2${salt}${digest}"


def check_password(password: str, stored: str) -> bool:
    try:
        _, salt, digest = stored.split("$")
    except ValueError:
        return False
    got = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), 10000).hex()
    return hmac.compare_digest(got, digest)


def user_by(where: str, **params):
    run = psql(f"{USER_JSON} WHERE {where};", ADMIN, **params)
    out = run.stdout.strip()
    return json.loads(out) if run.returncode == 0 and out else None


def session_for(user: dict) -> dict:
    now = int(time.time())
    claims = {"aud": "authenticated", "exp": now + 3600, "iat": now, "iss": f"{BASE}/auth/v1",
              "sub": user["id"], "email": user["email"], "phone": "", "role": "authenticated",
              "aal": "aal1", "amr": [{"method": "password", "timestamp": now}],
              "app_metadata": user["app_metadata"], "user_metadata": user["user_metadata"],
              "session_id": str(uuid.uuid4()), "is_anonymous": False}
    refresh = secrets.token_urlsafe(24)
    with LOCK:
        REFRESH[refresh] = user["id"]
    psql("UPDATE auth.users SET last_sign_in_at = now() WHERE id = :'id';", ADMIN, id=user["id"])
    return {"access_token": jwt_encode(claims), "token_type": "bearer", "expires_in": 3600,
            "expires_at": now + 3600, "refresh_token": refresh, "user": user}


def may_email(email: str) -> bool:
    allowed = CONFIG["email_allowed"]
    return allowed is None or email in allowed


def mail(email: str, kind: str, redirect_to):
    token_hash = secrets.token_hex(28)
    with LOCK:
        OUTBOX.append({"email": email, "type": kind, "token_hash": token_hash, "redirect_to": redirect_to})


def table_rows(table: str, claims: dict) -> subprocess.CompletedProcess:
    role = claims.get("role")
    if role not in ("anon", "authenticated"):
        role = "anon"
    sql = (f"BEGIN; SET LOCAL ROLE {role}; "
           f"SELECT set_config('request.jwt.claims', :'claims', true) \\g /dev/null\n"
           f"SELECT coalesce(json_agg(t), '[]'::json)::jsonb::text FROM public.\"{table}\" t; COMMIT;")
    return psql(sql, DB, claims=json.dumps(claims))


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quiet: the e2e prints what matters
        pass

    def answer(self, status: int, body=None, headers=None) -> None:
        data = b"" if body is None else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.send_header("x-supabase-api-version", "2024-01-01")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def fail(self, status: int, code: str, msg: str) -> None:
        self.answer(status, {"code": code, "error_code": code, "msg": msg})

    def body(self) -> dict:
        return json.loads(self.raw or b"{}")

    def bearer(self):
        auth = self.headers.get("authorization") or ""
        return auth[7:] if auth.lower().startswith("bearer ") else None

    # ── routing ──────────────────────────────────────────────────────────
    def route(self, method: str) -> None:
        # The body is read before anything answers: the connection is kept
        # alive, and an unread body would be the next request's first bytes.
        self.raw = self.rfile.read(int(self.headers.get("content-length") or 0))
        url = urllib.parse.urlsplit(self.path)
        path, query = url.path, dict(urllib.parse.parse_qsl(url.query))
        if method == "POST" and ROUTE.match(path):
            return self.management_query(path)
        if ADMIN and path.startswith("/__fake/"):
            return self.fake_admin(method, path)
        if ADMIN and path.startswith("/auth/v1/"):
            if self.headers.get("apikey") != ANON_KEY:
                return self.answer(401, {"message": "Invalid API key"})
            return self.auth(method, path[len("/auth/v1"):], query)
        if ADMIN and path.startswith("/rest/v1/") and method == "GET":
            return self.rest(path[len("/rest/v1/"):])
        return self.answer(404, {"message": f"no such endpoint {method} {path}"})

    def handle_route(self, method: str) -> None:
        try:
            self.route(method)
        except Exception as e:  # a stand-in that drops the connection hides what broke
            self.answer(500, {"message": f"fake-supabase-api: {e.__class__.__name__}: {e}"})

    def do_GET(self):
        self.handle_route("GET")

    def do_POST(self):
        self.handle_route("POST")

    def do_PUT(self):
        self.handle_route("PUT")

    # ── the Management API's query endpoint (unchanged) ─────────────────
    def management_query(self, path: str) -> None:
        m = ROUTE.match(path)
        if REF and m.group(1) != REF:
            return self.answer(404, {"message": f"no such project {m.group(1)}"})
        if not self.bearer():
            return self.answer(401, {"message": "missing bearer token"})
        query = self.body()["query"]
        # A read returns its rows; anything else runs as written and returns
        # none, as the real endpoint does for DDL.
        if re.match(r"^\s*select\b", query, re.I):
            run = psql(f"select coalesce(json_agg(t), '[]'::json) from ({query.rstrip().rstrip(';')}) t;")
        else:
            run = psql(query)
        if run.returncode != 0:
            return self.answer(400, {"message": run.stderr.strip()})
        out = run.stdout.strip()
        return self.answer(201, json.loads(out) if out.startswith("[") else [])

    # ── what the e2e reads back and switches ─────────────────────────────
    def fake_admin(self, method: str, path: str) -> None:
        if path == "/__fake/outbox" and method == "GET":
            with LOCK:
                return self.answer(200, list(OUTBOX))
        if path == "/__fake/config" and method == "POST":
            CONFIG.update({k: v for k, v in self.body().items() if k in CONFIG})
            return self.answer(200, CONFIG)
        return self.answer(404, {"message": "no such fake endpoint"})

    # ── GoTrue ───────────────────────────────────────────────────────────
    def auth(self, method: str, path: str, query: dict) -> None:
        if path == "/health" and method == "GET":
            return self.answer(200, {"version": "fake", "name": "GoTrue", "description": "stand-in"})
        if path == "/settings" and method == "GET":
            return self.answer(200, {
                "external": {"email": True, "phone": False, "anonymous_users": False},
                "disable_signup": False, "mailer_autoconfirm": CONFIG["mailer_autoconfirm"],
                "phone_autoconfirm": False, "sms_provider": "", "saml_enabled": False})
        if path == "/.well-known/jwks.json" and method == "GET":
            return self.answer(200, {"keys": []})
        if path == "/signup" and method == "POST":
            return self.signup(self.body(), query.get("redirect_to"))
        if path == "/token" and method == "POST":
            return self.token(query.get("grant_type"), self.body())
        if path == "/user":
            claims = jwt_decode(self.bearer() or "")
            if not claims or claims.get("role") != "authenticated":
                return self.fail(403, "bad_jwt", "invalid JWT: unable to parse or verify signature")
            user = user_by("id = :'id'", id=claims["sub"])
            if not user:
                return self.fail(403, "user_not_found", "User from sub claim in JWT does not exist")
            if method == "GET":
                return self.answer(200, user)
            if method == "PUT":
                body = self.body()
                if body.get("password"):
                    psql("UPDATE auth.users SET encrypted_password = :'pw', updated_at = now() WHERE id = :'id';",
                         ADMIN, pw=hash_password(body["password"]), id=user["id"])
                return self.answer(200, user_by("id = :'id'", id=user["id"]))
        if path == "/logout" and method == "POST":
            return self.answer(204)
        if path == "/recover" and method == "POST":
            email = (self.body().get("email") or "").lower()
            if not may_email(email):
                return self.fail(400, "email_address_not_authorized",
                                 f'Email address "{email}" cannot be used as it is not authorized')
            if user_by("email = :'email'", email=email):
                mail(email, "recovery", query.get("redirect_to"))
            return self.answer(200, {})
        if path == "/verify" and method == "POST":
            body = self.body()
            with LOCK:
                hit = next((m for m in OUTBOX if m["token_hash"] == body.get("token_hash")
                            and not m.get("used")), None)
                if hit:
                    hit["used"] = True
            if not hit:
                return self.fail(403, "otp_expired", "Email link is invalid or has expired")
            psql("UPDATE auth.users SET email_confirmed_at = coalesce(email_confirmed_at, now()) "
                 "WHERE email = :'email';", ADMIN, email=hit["email"])
            return self.answer(200, session_for(user_by("email = :'email'", email=hit["email"])))
        return self.answer(404, {"message": f"no such auth endpoint {method} {path}"})

    def signup(self, body: dict, redirect_to) -> None:
        email, password = (body.get("email") or "").lower(), body.get("password") or ""
        if not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email):
            return self.fail(400, "validation_failed", "Unable to validate email address: invalid format")
        if len(password) < 6:
            return self.answer(422, {"code": "weak_password", "msg": "Password should be at least 6 characters.",
                                     "weak_password": {"reasons": ["length"]}})
        if user_by("email = :'email'", email=email):
            return self.fail(422, "user_already_exists", "User already registered")
        confirm = not CONFIG["mailer_autoconfirm"]
        if confirm and not may_email(email):
            return self.fail(400, "email_address_not_authorized",
                             f'Email address "{email}" cannot be used as it is not authorized')
        uid = str(uuid.uuid4())
        run = psql("INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data) "
                   "VALUES (:'id', :'email', :'pw', " + ("NULL" if confirm else "now()") + ", :'meta');",
                   ADMIN, id=uid, email=email, pw=hash_password(password), meta=json.dumps(body.get("data") or {}))
        if run.returncode != 0:
            return self.answer(500, {"message": run.stderr.strip()})
        user = user_by("id = :'id'", id=uid)
        if confirm:
            mail(email, "signup", redirect_to)
            return self.answer(200, user)
        return self.answer(200, session_for(user))

    def token(self, grant: str, body: dict) -> None:
        if grant == "password":
            email = (body.get("email") or "").lower()
            run = psql("SELECT encrypted_password, email_confirmed_at IS NOT NULL FROM auth.users "
                       "WHERE email = :'email';", ADMIN, email=email)
            row = run.stdout.strip().split("|") if run.stdout.strip() else None
            if not row or not check_password(body.get("password") or "", row[0]):
                return self.fail(400, "invalid_credentials", "Invalid login credentials")
            if row[1] != "t":
                return self.fail(400, "email_not_confirmed", "Email not confirmed")
            return self.answer(200, session_for(user_by("email = :'email'", email=email)))
        if grant == "refresh_token":
            with LOCK:
                uid = REFRESH.pop(body.get("refresh_token") or "", None)
            user = uid and user_by("id = :'id'", id=uid)
            if not user:
                return self.fail(400, "refresh_token_not_found", "Invalid Refresh Token: Refresh Token Not Found")
            return self.answer(200, session_for(user))
        return self.fail(400, "unsupported_grant_type", f"unsupported grant_type {grant!r}")

    # ── PostgREST: `select *` from one table, as the request's role ──────
    def rest(self, table: str) -> None:
        if not re.match(r"^[a-z_][a-z0-9_]*$", table):
            return self.answer(400, {"message": "bad table name"})
        token = self.bearer() or self.headers.get("apikey") or ""
        claims = jwt_decode(token)
        if not claims:
            return self.answer(401, {"code": "PGRST301", "message": "JWT invalid"})
        run = table_rows(table, claims)
        if run.returncode != 0:
            return self.answer(400, {"code": "42501", "message": run.stderr.strip()})
        out = run.stdout.strip().splitlines()
        return self.answer(200, json.loads(out[-1]) if out else [])


if ADMIN:
    run = psql(AUTH_SCHEMA, ADMIN)
    if run.returncode != 0:
        sys.exit(f"fake-supabase-api: could not create the auth schema: {run.stderr.strip()}")
    print(f"anon-key {ANON_KEY}", flush=True)
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
