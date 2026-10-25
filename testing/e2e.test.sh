#!/usr/bin/env bash
# TIER 2 — the product a bootstrap produces builds, deploys (dry), serves, and
# signs a user up and in through Supabase Auth.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree,
# and that its own plan converges in the right order. This proves it WORKS,
# by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its PR merges), install with the
#      lockfile the product ships, render the wrangler fixture (which must
#      change nothing: the render is committed), typecheck, lint, test, build.
#      The landing itself is checked in the build box with `orun validate`
#      and `orun plan` alone (`checks: local`), its PR runs `plan` alone (an
#      `orun/BASE-*` branch), and a product's pull-request lanes run none of
#      these steps, so THIS is where a product those steps refuse is caught:
#      before the tag, not after a build has merged it;
#   2. a Supabase project of its own, stood in for: a Postgres on a random
#      port with Supabase's roles (testing/lib/local-postgres.sh) and the
#      endpoints this product and its tutorial call on a project — Auth
#      (GoTrue), the Data API's `select *` (PostgREST) and the SQL editor's
#      Management API query (testing/lib/fake-supabase-api.py), users in
#      the same database's `auth.users`;
#   3. the web lane's own steps for stage, rendered for a pull request (the
#      verify profile carries deploy-dry-run; the deploy profile does not) and
#      run in its staged job tree: install, `verify-app-structure` (the
#      committed wrangler.jsonc must exist BEFORE the build, in a tree with no
#      build output), `build-app` — which re-renders the config from the
#      stage wiring document it is handed, as the deploy does, and inlines
#      that project into the browser bundle — then `verify-build-output` and
#      `deploy-dry-run`;
#   4. the built Worker under `wrangler dev`, with NO .dev.vars, and the
#      component's OWN `smokeCommand` against it, verbatim; then every route
#      the product promises: the pages carry the product's name, the auth
#      pages render, `/protected` and every other guarded path send a
#      signed-out visitor to the login page, `/api/health` (answered only by
#      the Worker) says how sign-up behaves, the email-confirm route refuses
#      a bad link with the error page, not a 500, and the home page's
#      og:image and twitter:image name the product's own origin — with no
#      "Deploy to Vercel" anywhere;
#   5. the user flow: a visitor signs up and is signed in at once, the Worker
#      reads the session from the cookies @supabase/ssr wrote and renders the
#      protected page with their claims; a forged session is refused; a wrong
#      password is refused, the right one signs in. Then with email
#      confirmation ON: sign-up holds the session back, and the link Supabase
#      would email signs the user in through the Worker's /auth/confirm; with
#      the built-in SMTP's members-only rule, sign-up is refused with the code
#      the form explains;
#   6. the tutorial's table, run as the SQL editor runs it: row-level security
#      on from the first statement, nobody's notes readable before the
#      policies, then each user reads exactly their own through the Data API,
#      `anon` reads nothing, and no one can write a row as somebody else.
#
# WHAT IS ONLY OFFLINE HERE. The browser is not driven: the sign-up and login
# forms are client components, and what they call — supabase-js, from the
# product's own installed @supabase/ssr, with the same arguments, keeping the
# session in the same cookies — is called from Node (testing/lib/browser-auth.mjs).
# Supabase is a stand-in, faithful to the requests the app makes and no
# further. The platform's half — create the repository, mint the brokered
# tokens, create a real Supabase project, read its keys, set its Auth, deploy
# for real and probe workers.dev — is a bootstrap against a workspace
# (BOOTSTRAP.md); the Terraform root is validated below when terraform is on
# PATH, never applied.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, psql and a
# PostgreSQL server install (initdb, pg_ctl), and the network for
# `pnpm install` (or a warm store). A few minutes: two installs, two builds.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"
# shellcheck source=lib/local-postgres.sh
source "$here/lib/local-postgres.sh"

for bin in orun node pnpm python3 git curl psql; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done
pg_bin >/dev/null || { echo "e2e.test.sh needs a PostgreSQL server install (initdb, pg_ctl)" >&2; exit 1; }

scratch="$(mktemp -d)"
pgdir="$(mktemp -d)"
dev_pid=""
api_pid=""
# wrangler dev runs under pnpm, node and two workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So each
# server is started as its own process group (setsid) and the group stopped.
stop_group() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$pid" 2>/dev/null || break; sleep 0.5; done
  kill -KILL -- "-$pid" 2>/dev/null || true
}
cleanup() {
  stop_group "$dev_pid"
  stop_group "$api_pid"
  pg_down "$pgdir"
  [ -n "$pgdir" ] && [ -d "$pgdir" ] && rm -rf "$pgdir"
  [ -n "$scratch" ] && [ -d "$scratch" ] && rm -rf "$scratch"
}
trap cleanup EXIT
free_port() { python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()"; }
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false NEXT_TELEMETRY_DISABLED=1 TURBO_TELEMETRY_DISABLED=1

# The landing's own checks, step for step — what the product's Checks
# workflow ran on a pull request before the product carried ci.yml alone —
# run here at once on the whole tree.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

# One job of a plan, written out as the runner would run it: each `run:` step
# (the `use:` actions are setup-node and setup-pnpm, which this machine has)
# as a numbered script, the job's env, and the component path the steps run
# in. Steps are picked BY ID when given, else every `run:` step in order.
extract_job() { # PLAN JOB-ID OUT-DIR [STEP-ID…]
  python3 - "$@" <<'PY'
import json, pathlib, sys
plan, jid, out, *want = sys.argv[1:]
job = next((j for j in json.load(open(plan))["jobs"] if j["id"] == jid), None)
if job is None:
    sys.exit(f"the plan has no job {jid}")
out = pathlib.Path(out); out.mkdir(parents=True)
steps = [s for s in job["steps"] if s.get("run")]
if want:
    by = {s["id"]: s for s in steps}
    missing = [w for w in want if w not in by]
    if missing:
        sys.exit(f"{jid} has no step(s) {missing}")
    steps = [by[w] for w in want]
for i, s in enumerate(steps):
    (out / f"{i:02d}.sh").write_text(s["run"])
    (out / f"{i:02d}.id").write_text(s["id"])
(out / "path").write_text(job.get("path") or ".")
with (out / "env").open("w") as f:
    for k, v in (job.get("env") or {}).items():
        f.write(f"export {k}={json.dumps(v)}\n")
PY
}
run_job() { # STEPS-DIR WORK-TREE ENV LOG-PREFIX
  local steps="$1" work="$2" envname="$3" logp="$4" s id
  for s in "$steps"/[0-9][0-9].sh; do
    id="$(cat "${s%.sh}.id")"
    echo "   ▸ $id"
    if ! (cd "$work/$(cat "$steps/path")" && source "$steps/env" && export ORUN_ENVIRONMENT="$envname" \
          && bash -e "$s") > "$logp-$id.log" 2>&1; then
      echo "FAIL: the lane's $id step" >&2; tail -40 "$logp-$id.log" >&2; return 1
    fi
  done
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
echo "   2 phases placed and landed"

# ── 1. the product's own pull request ──────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
s01="$(git -C "$tree" rev-parse HEAD~1)"
at01="$scratch/at-01/$repo"
git -C "$tree" worktree add -q "$at01" "$s01"
checks "$at01" "$scratch/checks.log"
dirty="$(git -C "$at01" status --porcelain)"
[ -z "$dirty" ] || { echo "FAIL: the checks changed tracked files — the committed wrangler.jsonc is not the fixture render:" >&2; echo "$dirty" >&2; exit 1; }
echo "   the checks left the tree as committed (wire:fixture rendered the committed wrangler.jsonc)"
git -C "$tree" worktree remove --force "$at01"

# The Supabase root, as far as it goes without a cloud: formatted, and valid
# against the pinned providers its lock file names.
if command -v terraform >/dev/null; then
  echo "── the product's supabase root: terraform fmt, init -backend=false, validate"
  tfdir="$scratch/tf"
  cp -r "$tree/infra/terraform/supabase/terraform" "$tfdir"
  (cd "$tfdir" && terraform fmt -check -diff . && terraform init -backend=false -input=false \
     && terraform validate) > "$scratch/terraform.log" 2>&1 \
    || { echo "FAIL: the product's supabase root" >&2; tail -30 "$scratch/terraform.log" >&2; exit 1; }
  cmp -s "$tfdir/.terraform.lock.hcl" "$tree/infra/terraform/supabase/terraform/.terraform.lock.hcl" \
    || { echo "FAIL: terraform init changed the committed lock file" >&2; exit 1; }
  echo "   formatted and valid; the committed lock file is what init resolves"
else
  echo "── the product's supabase root: SKIPPED (no terraform on PATH)"
fi

# ── 2. a Supabase project, stood in for ────────────────────────────────────
echo "── a local Postgres with Supabase's roles, and the Supabase stand-in"
pgport="$(free_port)"
pgurl="$(pg_up "$pgdir" "$pgport")" || { echo "FAIL: Postgres did not start" >&2; exit 1; }
admin="postgres://supabase_admin@127.0.0.1:$pgport/postgres"
api_port="$(free_port)"
ref="localproject"
setsid python3 "$here/lib/fake-supabase-api.py" "$api_port" "$pgurl" --ref "$ref" --auth "$admin" \
  > "$scratch/api.log" 2>&1 < /dev/null &
api_pid=$!
for _ in $(seq 1 30); do grep -q '^anon-key ' "$scratch/api.log" 2>/dev/null && curl -s -o /dev/null "http://127.0.0.1:$api_port/" && break; sleep 0.3; done
anon="$(sed -n 's/^anon-key //p' "$scratch/api.log")"
[ -n "$anon" ] || { echo "FAIL: the Supabase stand-in did not start" >&2; cat "$scratch/api.log" >&2; exit 1; }
supabase_url="http://127.0.0.1:$api_port"
echo "   $pgurl; the project on $supabase_url"

# The plan the web lane runs from: a pull request over the finished product
# against an empty base (the verify profile carries deploy-dry-run), in a
# fresh clone — a CI checkout, no build output, no node_modules.
mkdir -p "$scratch/pr"
git clone -q "$tree" "$scratch/pr/$repo"
prtree="$scratch/pr/$repo"
git -C "$prtree" checkout -q --orphan empty
git -C "$prtree" rm -rqf .
git -C "$prtree" -c user.email=t@example.invalid -c user.name=t commit -qm empty --allow-empty
git -C "$prtree" checkout -q main
(cd "$prtree" && orun plan --intent intent.yaml --trigger github-pull-request --base empty --head HEAD --env stage \
   --output "$scratch/plan-pr.json") > "$scratch/plan-pr.log" 2>&1 \
  || { echo "FAIL: orun plan (pull request)" >&2; tail -15 "$scratch/plan-pr.log" >&2; exit 1; }
# This tier runs the bootstrap floor, newer than the orun the product's CI
# pins, and both read the per-edge `modeRules`: on a pull request — which
# applies and deploys nothing — the edge that orders a push to main is
# advisory, so no lane waits on another. (placement.test.sh checks the push
# to main's order.)
python3 - "$scratch/plan-pr.json" <<'PY'
import json, sys
jobs = {j["component"]: j for j in json.load(open(sys.argv[1]))["jobs"] if j["environment"] == "stage"}
chain = ["supabase", "web"]
for a, b in zip(chain, chain[1:]):
    ja, jb = jobs[a], jobs[b]
    if ja["id"] in (jb.get("dependsOn") or []) or ja["id"] not in (jb.get("advisoryDependsOn") or []):
        sys.exit(f"FAIL: on a pull request {b}@stage must name {a}@stage as advisory, not wait on it")
print("   pull request: " + " → ".join(chain) + ", the edge advisory")
PY

# ── 3. the web lane's steps, for stage ─────────────────────────────────────
echo "── the stage web lane: install, verify-app-structure, build-app, verify-build-output, deploy-dry-run"
extract_job "$scratch/plan-pr.json" web.stage.verify-deploy "$scratch/steps-web" \
  install-workspace-dependencies verify-app-structure build-app verify-build-output deploy-dry-run
work="$prtree/.orun/runs/e2e/web.stage.verify-deploy/work"
# The job's private tree, staged as orun stages it — no build output, no
# node_modules: under stack-tectonic 0.19.0 the job installs inside it.
python3 "$here/lib/stage-job.py" "$prtree" "$work"
[ ! -e "$work/apps/web/.open-next" ] && [ -f "$work/apps/web/wrangler.jsonc" ] \
  || { echo "FAIL: the staged tree is not a fresh checkout with the committed wrangler.jsonc" >&2; exit 1; }
echo "   staged: $(realpath --relative-to="$prtree" "$work") — no build output, the committed wrangler.jsonc"
# The stage wiring document, as the supabase apply publishes it and the lane
# resolves it (optionalSecretEnv WIRING_SUPABASE_STAGE): the stand-in's URL
# and its anon key.
export WIRING_SUPABASE_STAGE="{\"supabase_url\":\"$supabase_url\",\"supabase_anon_key\":\"$anon\"}"
run_job "$scratch/steps-web" "$work" stage "$scratch/web"
unset WIRING_SUPABASE_STAGE
grep -q '(Turbopack)' "$scratch/web-build-app.log" \
  || { echo "FAIL: the staged build did not run on Turbopack" >&2; grep -m3 'Next.js' "$scratch/web-build-app.log" >&2; exit 1; }
grep -q "\"NEXT_PUBLIC_SUPABASE_URL\": \"$supabase_url\"" "$work/apps/web/wrangler.jsonc" \
  || { echo "FAIL: build-app did not re-render wrangler.jsonc from the stage wiring document" >&2; exit 1; }
[ "$(node -e 'const fs=require("fs");process.stdout.write(String(fs.readdirSync(process.argv[1]).length))' "$work/node_modules")" -gt 0 ] && [ ! -L "$work/node_modules" ] \
  || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
# `next build` inlined the SAME project into the browser bundle — not the
# committed fixture's.
grep -rqF "$supabase_url" "$work/apps/web/.open-next/assets/_next/static" \
  && ! grep -rqF "stage-project-ref.supabase.co" "$work/apps/web/.open-next/assets/_next/static" \
  || { echo "FAIL: the browser bundle does not carry the project the stage wiring names" >&2; exit 1; }
echo "   the staged build ran on Turbopack, inside its own tree; the Worker's vars and the browser bundle name the stage project it was handed"

# ── 4. serve it ────────────────────────────────────────────────────────────
echo "── wrangler dev over the built Worker"
[ ! -e "$work/apps/web/.dev.vars" ] || { echo "FAIL: the staged tree carries a .dev.vars" >&2; exit 1; }
port="$(free_port)"
(cd "$work/apps/web" && exec setsid pnpm exec wrangler dev --config wrangler.jsonc --ip 127.0.0.1 --port "$port" \
   --name "$repo-web-stage" --show-interactive-dev-session=false) > "$scratch/dev.log" 2>&1 < /dev/null &
dev_pid=$!
url="http://127.0.0.1:$port"
for _ in $(seq 1 90); do
  curl -s -o /dev/null "$url/" && break
  kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }
  sleep 1
done
curl -s -o /dev/null "$url/" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ the component's own smokeCommand, DEPLOYED_URL=$url"
smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/web/component.yaml")"
DEPLOYED_URL="$url" bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the product" >&2; tail -20 "$scratch/dev.log" >&2; exit 1; }

echo "   ▸ every route the product promises; a user signing up, in, and through the confirm link"
python3 - "$url" "$values" "$supabase_url" "$anon" "$work/apps/web" "$here/lib/browser-auth.mjs" <<'PY' \
  || { echo "FAIL: the routes; wrangler dev said:" >&2; tail -40 "$scratch/dev.log" >&2; exit 1; }
import html, http.client, json, re, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
base, values, supabase, anon, app, browser = sys.argv[1], json.load(open(sys.argv[2])), *sys.argv[3:]
name = values["productname"]
problems = []
def bad(m): problems.append(m)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k): return None
opener = urllib.request.build_opener(NoRedirect)
def req(path, data=None, headers=None, method=None, at=None):
    # A GET whose CONNECTION drops (not one that answers an error) is asked
    # again, twice at most, and says so: `wrangler dev` on a loaded machine
    # has dropped one. A POST is never repeated — it would submit twice.
    for attempt in range(3):
        r = urllib.request.Request((at or base) + path, data=data, headers=headers or {}, method=method)
        try:
            with opener.open(r, timeout=60) as resp:
                return resp.status, resp.headers, resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            return e.code, e.headers, e.read().decode("utf-8", "replace")
        except (http.client.RemoteDisconnected, ConnectionResetError) as e:
            if data is not None or attempt == 2:
                raise
            print(f"   (GET {path}: the connection dropped ({e.__class__.__name__}) — asking again)")
            time.sleep(1)
def location(h):
    loc = urllib.parse.urlparse(h.get("location", ""))
    return loc.path, urllib.parse.parse_qs(loc.query)
def text(page):
    # React separates adjacent text with `<!-- -->`: drop those, then tags.
    return html.unescape(re.sub(r"<[^>]+>", " ", re.sub(r"<!--.*?-->", "", page, flags=re.S)))
def title(page):
    m = re.search(r"<title>(.*?)</title>", page, re.S)
    return m and html.unescape(m.group(1))
def browser_call(*args):
    out = subprocess.run(["node", browser, app, supabase, anon, *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"browser-auth {args[0]} failed: {out.stderr.strip()[-400:]}")
    return json.loads(out.stdout)
def fake(path, body=None):
    data = None if body is None else json.dumps(body).encode()
    s, _, b = req(path, data, {"content-type": "application/json"}, "POST" if data else "GET", at=supabase)
    return json.loads(b)

# ── the public pages, under the product's own name ────────────────────────
s, _, home = req("/")
if s != 200:
    bad(f"/ answered {s}")
if title(home) != name:
    bad(f"the home page's <title> is {title(home)!r}, not {name!r}")
if name not in [html.unescape(m) for m in re.findall(r'<a href="/">(.*?)</a>', home)]:
    bad(f"the header's home link does not read {name!r}")
if "Next.js Supabase Starter" in home:
    bad("the home page still carries the baseline's name")
for want in ('href="/auth/login"', 'href="/auth/sign-up"', "Sign up your first user"):
    if want not in home:
        bad(f"the signed-out home page has no {want}")
if "Supabase environment variables required" in home:
    bad("the home page says the Supabase variables are missing — the build did not inline them")
if "Deploy to Vercel" in text(home) or "vercel.com/new/clone" in html.unescape(home):
    bad("the home page still offers to deploy the upstream example to Vercel")
# The image links are absolute, and on the product's OWN origin — the stage
# Worker this build was made for (SITE_URL unset), the one the Supabase
# project's Auth is given — not localhost, not Vercel's.
origin = f"https://{values['reponame']}-web-stage.{values['subdomain']}.workers.dev"
for attr, key, image in (("property", "og:image", "opengraph-image.png"), ("name", "twitter:image", "twitter-image.png")):
    tags = re.findall(r'<meta ' + attr + r'="' + re.escape(key) + r'" content="([^"]+)"', home)
    if not tags or not all(html.unescape(t).startswith(f"{origin}/{image}") for t in tags):
        bad(f"the home page's {key} is {tags}, not {origin}/{image}")
    else:
        s, _, _ = req("/" + image)
        if s != 200:
            bad(f"/{image}, which {key} names, answered {s}")

PAGES = {
    "/auth/login": "Enter your email below to login to your account",
    "/auth/sign-up": "Create a new account",
    "/auth/forgot-password": "send you a link to reset your",
    "/auth/update-password": "Please enter your new password below.",
    "/auth/sign-up-success": "Thank you for signing up!",
    "/auth/error?error=boom": "Code error: boom",
}
for path, marker in PAGES.items():
    s, _, page = req(path)
    if s != 200 or marker not in text(page):
        bad(f"{path} answered {s} without {marker!r}")
    elif title(page) != name:
        bad(f"{path}'s <title> is {title(page)!r}, not {name!r}")
for path in ("/protected", "/no-such-page"):
    s, h, _ = req(path)
    if s != 307 or location(h)[0] != "/auth/login":
        bad(f"{path} signed out answered {s} → {h.get('location')}, not 307 → /auth/login")

# ── what only the Worker answers ──────────────────────────────────────────
def health():
    s, h, body = req("/api/health")
    return s, json.loads(body), h.get("cache-control")
s, body, cache = health()
if s != 200 or body != {"ok": True, "auth": "reachable", "signup": "open", "emailConfirmation": "off"} or cache != "no-store":
    bad(f"/api/health answered {s} {body} ({cache})")
s, h, _ = req("/auth/confirm")
path, q = location(h)
if s != 307 or path != "/auth/error" or q.get("error") != ["No token hash or type"]:
    bad(f"/auth/confirm with no token answered {s} → {h.get('location')}")
s, h, _ = req("/auth/confirm?token_hash=not-a-real-link&type=email&next=/protected")
path, q = location(h)
if s != 307 or path != "/auth/error" or "expired" not in (q.get("error") or [""])[0]:
    bad(f"/auth/confirm with a bad link answered {s} → {h.get('location')}, not the error page")

# ── a visitor signs up — and is signed in at once ─────────────────────────
email, password = "sam@notes.example", "correct horse battery"
up = browser_call("signup", email, password, base)
if not up["ok"] or not up["session"] or "sb-127-auth-token=" not in up["cookie"]:
    bad(f"sign-up with confirmation off did not sign the user in: {up}")
cookie = up["cookie"]
s, _, page = req("/protected", headers={"cookie": cookie})
claims_text = text(page)
if s != 200 or "Your user details" not in claims_text or f'"email": "{email}"' not in claims_text \
        or '"role": "authenticated"' not in claims_text:
    bad(f"/protected with the session answered {s} without the user's claims")
if "alter table notes enable row level security;" not in claims_text:
    bad("/protected's tutorial does not create the table with row-level security on")
s, _, page = req("/", headers={"cookie": cookie})
if f"Hey, {email}!" not in text(page):
    bad("the signed-in home page does not greet the user")
s, _, _ = req("/no-such-page", headers={"cookie": cookie})
if s != 404:
    bad(f"/no-such-page signed in answered {s}, not 404")
# A session whose access token was signed by somebody else: the cookie
# decodes, the claims read well, and the Worker must still refuse it — the
# proxy's getClaims() asks Supabase about every token it cannot verify itself.
import base64
def b64url_decode(v): return base64.urlsafe_b64decode(v + "=" * (-len(v) % 4))
def b64url_encode(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
m = re.search(r"(?:^|; )sb-127-auth-token=base64-([A-Za-z0-9_-]+)", cookie)
if not m:
    bad(f"the session cookie is not one unchunked sb-127-auth-token: {[c.split('=')[0] for c in cookie.split('; ')]}")
else:
    session = json.loads(b64url_decode(m.group(1)))
    head, body, _sig = session["access_token"].split(".")
    session["access_token"] = f"{head}.{body}.{b64url_encode(b'not the project key signature')}"
    forged = f"sb-127-auth-token=base64-{b64url_encode(json.dumps(session).encode())}"
    s, h, _ = req("/protected", headers={"cookie": forged})
    if s != 307 or location(h)[0] != "/auth/login":
        bad(f"/protected with a forged session answered {s} → {h.get('location')}")

# ── and signs in again ────────────────────────────────────────────────────
wrong = browser_call("signin", email, "not the password")
if wrong["ok"] or wrong["code"] != "invalid_credentials":
    bad(f"a wrong password was not refused: {wrong}")
again = browser_call("signin", email, password)
s, _, page = req("/protected", headers={"cookie": again["cookie"]})
if not again["session"] or s != 200 or f'"email": "{email}"' not in text(page):
    bad(f"sign-in answered {again['code']} and /protected {s}")

# ── email confirmation ON: the link Supabase would mail signs the user in ─
fake("/__fake/config", {"mailer_autoconfirm": False})
s, body, _ = health()
if s != 200 or body.get("emailConfirmation") != "required":
    bad(f"/api/health does not say confirmation is required: {body}")
kim = "kim@notes.example"
up = browser_call("signup", kim, password, base)
if not up["ok"] or up["session"]:
    bad(f"sign-up with confirmation on signed the user in, or failed: {up}")
mail = [m for m in fake("/__fake/outbox") if m["email"] == kim and m["type"] == "signup"]
if not mail or not (mail[0]["redirect_to"] or "").startswith(f"{base}/protected"):
    bad(f"no confirmation was sent for {kim}, or it does not lead back to /protected: {mail}")
else:
    s, h, _ = req(f"/auth/confirm?token_hash={mail[0]['token_hash']}&type=email&next=/protected")
    set_cookie = h.get_all("set-cookie") or []
    jar = "; ".join(c.split(";", 1)[0] for c in set_cookie if c.startswith("sb-127-auth-token"))
    if s != 307 or location(h)[0] != "/protected" or not jar:
        bad(f"/auth/confirm with the emailed link answered {s} → {h.get('location')}, cookies {len(set_cookie)}")
    else:
        s, _, page = req("/protected", headers={"cookie": jar})
        if s != 200 or f'"email": "{kim}"' not in text(page):
            bad(f"the session /auth/confirm set does not open /protected ({s})")
# The built-in email reaches only the organization's members.
fake("/__fake/config", {"email_allowed": ["owner@notes.example"]})
refused = browser_call("signup", "lee@notes.example", password, base)
if refused["ok"] or refused["code"] != "email_address_not_authorized":
    bad(f"sign-up the project cannot email was not refused with email_address_not_authorized: {refused}")
fake("/__fake/config", {"mailer_autoconfirm": True, "email_allowed": None})

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   /, the six auth pages, the guard on /protected and every other path, /api/health, "
      f"/auth/confirm's refusals; og:image and twitter:image on {origin}, no Deploy to Vercel; "
      f"a sign-up signed straight in, the protected page from the session cookies, a forged session "
      f"refused, a sign-in; with confirmation on, the emailed link through /auth/confirm; "
      f"members-only email refused with its code — as {name!r}")
PY

# ── 6. the tutorial's table, as the SQL editor runs it ─────────────────────
echo "── the tutorial's table: row-level security from the first statement, then per-user policies"
python3 - "$supabase_url" "$ref" "$anon" "$work/apps/web" "$here/lib/browser-auth.mjs" \
  "$work/apps/web/components/tutorial/fetch-data-steps.tsx" "$pgurl" <<'PY' \
  || { echo "FAIL: the tutorial's row-level security" >&2; exit 1; }
import json, re, subprocess, sys, urllib.error, urllib.request
supabase, ref, anon, app, browser, tutorial, pgurl = sys.argv[1:]
problems = []
def bad(m): problems.append(m)
src = open(tutorial).read()
def block(var):
    m = re.search(r"const " + var + r" = `(.*?)`\.trim\(\);", src, re.S)
    if not m:
        raise SystemExit(f"the tutorial has no `{var}` SQL block")
    return m.group(1).strip()
def sql_editor(query):
    r = urllib.request.Request(f"{supabase}/v1/projects/{ref}/database/query",
                               json.dumps({"query": query}).encode(),
                               {"authorization": "Bearer e2e", "content-type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"the SQL editor refused: {e.read().decode()[:300]}")
def notes(*creds):
    out = subprocess.run(["node", browser, app, supabase, anon, "notes", *creds], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(out.stderr[-300:])
    return json.loads(out.stdout)
def psql(sql):
    return subprocess.run(["psql", pgurl, "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                          capture_output=True, text=True)
password = "correct horse battery"
users = {r["email"]: r["id"] for r in sql_editor("select email, id from auth.users")}
sam, kim = users.get("sam@notes.example"), users.get("kim@notes.example")
if not sam or not kim:
    raise SystemExit(f"the users the flow signed up are not in auth.users: {sorted(users)}")

sql_editor(block("create"))
rows = sql_editor("select c.relname, c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace "
                  "where n.nspname = 'public' and c.relkind in ('r', 'p')")
if [r["relname"] for r in rows] != ["notes"] or not all(r["relrowsecurity"] for r in rows):
    bad(f"after the tutorial's first step, public holds {rows} — every table must have RLS")
owners = {r["user_id"]: r["n"] for r in sql_editor("select user_id, count(*)::int as n from notes group by 1")}
if owners != {sam: 3, kim: 3}:
    bad(f"the tutorial's seed gave {owners}, not three notes to each signed-up user")
before = notes("sam@notes.example", password)
if not before["ok"] or before["rows"] != []:
    bad(f"before any policy, the Data API showed sam {before['rows']}")

sql_editor(block("rls"))
mine = notes("sam@notes.example", password)
if not mine["ok"] or len(mine["rows"] or []) != 3 or {r["user_id"] for r in mine["rows"]} != {sam}:
    bad(f"sam reads {mine['rows']} through the Data API, not his own three notes")
theirs = notes("kim@notes.example", password)
if {r["user_id"] for r in theirs["rows"] or []} != {kim} or len(theirs["rows"]) != 3:
    bad(f"kim reads {theirs['rows']}, not her own three notes")
nobody = notes()
if not nobody["ok"] or nobody["rows"] != []:
    bad(f"anon reads {nobody['rows']} through the Data API")
as_sam = f"SET ROLE authenticated; SELECT set_config('request.jwt.claims', '{{\"sub\":\"{sam}\",\"role\":\"authenticated\"}}', false);"
w = psql(f"{as_sam} INSERT INTO notes (user_id, title) VALUES ('{kim}', 'written as kim')")
if w.returncode == 0 or "row-level security" not in w.stderr:
    bad(f"sam wrote a note as kim: {w.stderr.strip()[:120]}")
w = psql(f"{as_sam} INSERT INTO notes (title) VALUES ('mine')")
if w.returncode != 0:
    bad(f"sam could not add his own note: {w.stderr.strip()[:120]}")
w = psql(f"SET ROLE anon; INSERT INTO notes (user_id, title) VALUES ('{sam}', 'written as anon')")
if w.returncode == 0 or "row-level security" not in w.stderr:
    bad(f"anon wrote a note, or was refused for another reason: {w.stderr.strip()[:120]}")
if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print("   public holds one table, `notes`, with RLS on from its first statement; nobody read it before the "
      "policies; after them sam and kim each read exactly their own three notes through the Data API, "
      "anon none, and no one writes a row as somebody else")
PY

echo "e2e.test.sh: ok"
