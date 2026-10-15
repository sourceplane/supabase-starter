# supabase-starter — operating contract (for humans and agents)

This is the standing guide to how this product is deployed and operated.
Instance facts (live URLs, workspace, how sign-up behaves on each
environment, the secrets inventory) live in [deployment.md](deployment.md),
rendered from probed reality by the bootstrap's `02-docs` phase; this file is
the contract that stays true between deployments. It is written to give an
agent with repository read access enough context to reason about and operate
the product without any other source.

## What this system is

Vercel's Next.js and Supabase Starter — email and password sign-up, sign-in
and password reset through Supabase Auth, the session in cookies refreshed by
a proxy, a protected page — on Cloudflare Workers, its Auth (and its
Postgres) a Supabase project per environment, expressed as an Orun
component-native desired-state repo. Three components:

- **`infra/terraform/supabase`** (`supabase`) — one Supabase project per
  environment, its Auth's Site URL and redirect allow-list pointed at the
  app's Worker, and sign-up confirming at once unless `authEmailConfirmation`
  is on (below). Its apply publishes `WIRING_SUPABASE` (the project URL and
  publishable key) and `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`,
  `SUPABASE_DB_URL` onto the environment's secret rung.
- **`apps/web`** (`web`) — the app: Next.js built by `@opennextjs/cloudflare`
  into one Worker plus Static Assets. It talks to Supabase over HTTPS with
  supabase-js (`@supabase/ssr`): the browser directly, the Worker on the
  server — never a Postgres connection.
- **`tests/web`** — the vitest suite, verified on the `dev` rung.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and test, nothing deploys.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. Per environment, in this order — the edge `mode: enforced` on a push to
   main, advisory on a pull request (which deploys nothing):
   **`supabase` → `web`.** A job resolves its secrets when it starts, so the
   app's deploy reads the `WIRING_SUPABASE` the apply before it published.
   It re-renders `apps/web/wrangler.jsonc` from that document, builds —
   `next build` inlines the same URL and key into the browser bundle
   (`next.config.ts`) — deploys `supabase-starter-web-<env>`, and smoke-tests
   it: the home page, and `/api/health`, which answers 200 only when the
   project's Auth answers the key the build inlined.
4. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
5. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "product
  converged"; probe the URLs instead.
- `apps/web/wrangler.jsonc` is committed as the render of
  `wrangler.template.jsonc` from `wiring.fixture.json` (a placeholder
  project): edit the template and run `pnpm run wire:fixture`. The deploy
  lanes render the real one in their own job tree; never commit a real
  project's URL or key.
- The product's origin is ONE setting. Unset, it is the environment's
  workers.dev URL (`<repo>-web-<env>.<subdomain>.workers.dev`); with a custom
  domain, `SITE_URL` under the environment's `env:` in `intent.yaml`. The
  app's build bakes it into its absolute links (the Open Graph and Twitter
  images), and the supabase apply makes it Auth's Site URL and redirect
  allow-list, where Supabase sends its links (password recovery, and
  confirmation when it is on). The apply owns those Auth settings: an edit in
  the dashboard is undone by the next apply.

## Auth and email

A Supabase project without an SMTP server of its own delivers email only to
the members of its organization, a few messages an hour. So the supabase
root turns email confirmation OFF (`authEmailConfirmation: "false"` in its
component.yaml): sign-up signs a new user straight in, and works for anyone
on the first deploy. Password recovery still sends an email; until the
project has SMTP, the form says the address cannot be mailed yet (Supabase's
`email_address_not_authorized`) instead of failing.

To require confirmation:

1. Give each project SMTP of its own (Supabase dashboard → Authentication →
   Emails → SMTP Settings).
2. Optionally point the confirmation email at the app's own route, as the
   template's authors recommend — template body
   `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email&next=/protected`.
3. Set `authEmailConfirmation: "true"` in `infra/terraform/supabase/component.yaml`
   and merge. The apply turns confirmation on; `/api/health` and the
   deployment record then say `emailConfirmation: required`.

The terraform manages only `site_url`, `uri_allow_list` and
`mailer_autoconfirm`; every other Auth setting is the project's own.

## Data and row-level security

The app ships no tables: its users live in Supabase's `auth` schema, which
the Data API does not expose. The protected page's tutorial creates a
`notes` table with row-level security ON in the same statement, and policies
that let each signed-in user read and add only their own rows
(`auth.uid() = user_id`). Keep that rule for every table you add to
`public`: the publishable key is public by design, so a table without RLS is
readable by anyone who loads the site. Check with:

```sql
select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r','p') and not c.relrowsecurity;
```

## Secrets model

- **Brokered provider secrets**, minted per run from the workspace's
  connections — no long-lived values at rest, nothing to rotate by hand:
  `CLOUDFLARE_API_TOKEN` (Workers deploy), `CLOUDFLARE_ACCOUNT_ID`,
  `SUPABASE_ACCESS_TOKEN` (project create, API keys, Auth settings) and
  `SUPABASE_ORG_ID`.
- **Published by the apply** onto the stage and prod rungs:
  `WIRING_SUPABASE` (URL and publishable key — what the app reads),
  `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL` (the
  database, for you and for any migration step you add). The service-role
  key is never published.
- **No Worker secrets.** The publishable key is a wrangler var: it ships to
  every browser by design, and row-level security is the boundary.
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`. No tooling in this repository prints a secret value,
  and no document in `ai/context/` may contain one.

## Verifying the system

```bash
# the app and its Supabase Auth path on each environment (also recorded, probed, in deployment.md)
curl -s -o /dev/null -w '%{http_code}\n' https://supabase-starter-web-stage.your-workers-subdomain.workers.dev/
curl -s https://supabase-starter-web-prod.your-workers-subdomain.workers.dev/api/health

# workspace readiness (integrations + repository link)
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

## Common operations

| task | how |
|---|---|
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| require email confirmation | SMTP first, then `authEmailConfirmation: "true"` (above) |
| add a table | create it with `enable row level security` and `auth.uid()` policies (above); the day the product has migrations, Lumen's `packages/db` + `db-migrate` is the shape, reading `SUPABASE_DB_URL` |
| redeploy without a change | edit the last line of the component's `component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| serve a custom domain | attach it to the Worker in Cloudflare, set `SITE_URL` under `environments.prod.env` in `intent.yaml`, and touch the redeploy line of both `apps/web/component.yaml` and `infra/terraform/supabase/component.yaml` in the same PR (an `intent.yaml` change alone plans nothing) |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

Structural changes (a second Worker, a queue, migrations) follow the same
contract that deployed the product: add a component under `apps/`, `infra/`
or `packages/` with a `component.yaml` — declaring `dependsOn` on any
infrastructure whose published secrets it reads, enforced on main — land it
as a pull request, and the convergence run applies it.
