# supabase-starter — risks and open questions

## SS-A — `cacheComponents` on OpenNext (RISK, mitigated)

The template enables Next 16's `cacheComponents`. OpenNext Cloudflare 1.20
builds it, but the pre-rendered shells it produces are served from the
static-assets incremental cache, which is read-only; nothing in this
template revalidates, so that is enough. If a later Next or OpenNext breaks
the combination, dropping `cacheComponents` is a one-line change the
template tolerates (it was added for tutorial purposes).

## SS-B — Where the publishable key lives (RESOLVED)

A wrangler `var`, rendered from the wiring document, not a Worker secret.
The key is shipped to every browser by design; Row Level Security is the
boundary. The service-role key was published as an orun secret for server
use that this template never made; since SS4 it is neither published nor an
output of the root.

## SS-C — Auth emails redirect to the right host (RESOLVED, SS4)

Supabase sends confirmation and recovery links to the project's `Site URL`
and allow-listed redirect URLs, which default to `http://localhost:3000`.
Since SS4 the root sets both with `supabase_settings` to the environment's
Worker (`https://<repo>-web-<env>.<subdomain>.workers.dev`, the subdomain a
component parameter the rename rewrites), so nobody touches the dashboard.
The apply owns them: a dashboard edit is undone by the next apply.

## SS-D — Node ≥ 25 stub `localStorage` at prerender (SETTLED)

Same as blog-starter: `next-themes` guards correctly, and nothing in this
template reads `localStorage` at prerender. CI builds on Node 22.

## SS-E — The verify lane needs values it cannot have (RESOLVED, revised SS4)

`next build` inlines `NEXT_PUBLIC_*`. The verify lane (and `Checks`) has no
Supabase project. Until SS4 it built with none (the template's "environment
variables required" banner). Since SS4 every production build reads the two
values from `wrangler.jsonc` (next.config.ts): the verify lane and `Checks`
inline the committed fixture's placeholder project, which nothing calls; the
deploy lanes inline the real one they rendered. `next dev` without
`.env.local` still shows the template's "connect Supabase" steps.

## SS-F — `wrangler.jsonc` must exist before the build (RESOLVED, SS4)

The workers-assets composition's `verify-app-structure` step runs
`test -f wrangler.jsonc` before `build-app`, in the job's fresh tree. SS1
rendered the file in the build and git-ignored it — every web lane would
have stopped there. It is now committed as the fixture render (tests/web
holds it equal to the template), and the stage and prod lanes re-render it
from their wiring document before the build. The SS1 build command also
rendered on `dev`, which has no wiring document; dev now verifies with the
committed fixture render.

## SS-G — A fresh project emails only its own organization (RESOLVED, SS4)

Without an SMTP server of its own, a Supabase project delivers email only to
the members of its organization, a few messages an hour. With email
confirmation on — a new project's default — nobody else could finish a
sign-up. The root turns it off (`mailer_autoconfirm`, unless the component's
`authEmailConfirmation` is `"true"`), the sign-up form sends a user who got a
session straight to `/protected`, and the forms say what
`email_address_not_authorized` and the rate limit mean. Password recovery
still emails: until the project has SMTP, the form explains the refusal. The
README's "Email" section is how an owner turns confirmation on.

## SS-H — Stage's deploy and prod's wiring document (RESOLVED, SS4)

The app reads `WIRING_SUPABASE_STAGE` and `_PROD`. During a bootstrap both
environments converge side by side, and stage's deploy waits only on stage's
apply; a REQUIRED reference to prod's document would fail stage's job
whenever prod's project came up second. Both are `optionalSecretEnv`, and
`tooling/wire/live.mjs` refuses a deploy whose own environment's document is
missing — the failure that matters, named.

## SS-I — Unproven against a real organization (OPEN)

Nothing here has been applied. Three things only a live apply settles:
whether the platform's brokered Management-API token (the Supabase OAuth
grant) reaches `GET /v1/projects/{ref}/api-keys` (`supabase_apikeys`) and
`PATCH /v1/projects/{ref}/config/auth` (`supabase_settings`) — a personal
access token does; whether a new project still has a legacy anon key for
`supabase_apikeys` to return (an empty one fails the deploy's render loudly,
not silently); and the wall-clock (the card's fifteen minutes is summed from
the phases' estimates). The e2e tier proves everything after the apply
against a local stand-in for the project (testing/lib/fake-supabase-api.py),
never the stand-in's fidelity.

## SS-J — Tables under row-level security (RESOLVED, SS4)

The template creates no table; its users live in Supabase's `auth` schema,
which the Data API does not expose. Its tutorial, which owners follow, now
creates `notes` with RLS enabled in the same statement and policies keyed on
`auth.uid()` — upstream created it without RLS and then suggested a
public-read policy. The e2e tier runs the tutorial's SQL as the SQL editor
does and proves each user reads only their own notes and `anon` none.

## SS-K — The bootstrap floor plans `modeRules` as enforced (ACCEPTED)

orun v2.58.11, the floor a bootstrap runs on, ignores per-edge `modeRules`,
so a pull-request plan it makes holds the infra edge enforced rather than
advisory. The product's own CI plans with its lane pin (v2.78.4), which
reads them; the placement tier says when it cannot check them and the e2e
tier, pinned at the lane version, does.
