# supabase-starter

Vercel's [Next.js and Supabase Starter](https://github.com/vercel/next.js/tree/canary/examples/with-supabase)
— Supabase Auth with cookie sessions through `@supabase/ssr`, a
session-refreshing proxy, sign-up / login / password flows and a protected
page — running on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with the
Supabase project itself provisioned by Terraform through
[Orun](https://github.com/sourceplane/orun), the way the
[Lumen baseline](https://github.com/sourceplane/lumen) does it — and
packaged as an **Orun baseline**: one command takes a new product from
nothing to live on stage and prod, in its own repository, under its own
name, in ONE landing.

The template's code is the code. What the port changes is what the Workers
runtime and a fresh, unattended deployment force: the build inlines the
project's URL and publishable key from the same wrangler config the Worker
runs with (`next.config.ts`), each project is created with its Auth pointed at
the Worker and email confirmation off (so anyone can sign up on the first
deploy, with no SMTP server), the auth forms explain what a fresh project
refuses instead of echoing it, and the tutorial's table gets row-level
security keyed on `auth.uid()`. What the baseline adds is everything needed to
make a copy of it somebody else's — built the way
[cirrus-baseline](https://github.com/sourceplane/cirrus-baseline) builds a
product, in one landing. See [`specs/epics/supabase-starter`](specs/epics/supabase-starter/README.md)
for the design, the milestones and the as-built status, including every
departure.

## Instantiating a product

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/supabase-starter
cd supabase-starter
orun new --blueprint repo-blueprint.yaml --out ~/products/acme-notes --run-hooks --resume \
  --set reponame=acme-notes --set productname="Acme Notes" \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`supabase-starter` → Build). Two phases: **`01-product`** creates the
repository, mints the four brokered credentials (Cloudflare and Supabase) and
lands the whole product as one pull request, whose convergence on `main`
provisions and deploys it per environment in a fixed order —

```
supabase ──▶ web
```

— the edge `mode: enforced` on a push to main and advisory on a pull
request; then **`02-docs`** records the live deployment from probed facts.
**[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator guide;
[docs/phases/](docs/phases/README.md) has a page per phase. The Supabase
organization needs room for **two** projects (stage and prod) — the free
plan's limit.

The new repository receives the **product only** — the app, the Terraform
root, the tests, its CI, its tooling, a README of its own and its operating
contract — renamed throughout to the product's name, repository, Worker and
Supabase projects. None of this repository's machinery ships.

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, the product's README and the bootstrap's task contracts | `.baseline/` |
| The rename engine (product-name seam: `apps/web/lib/site.ts`) | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The product's context pack | `ai/context/` |
| The baseline's tests: contract, leak, offline bootstrap and plans, end to end | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

## What is here (the product)

| Surface | Where |
|---|---|
| The product's name | `apps/web/lib/site.ts` |
| Home (tutorial), auth pages, `/protected`, `/api/health` | `apps/web/app` |
| Supabase clients (browser, server), the session proxy, the auth forms' error wording | `apps/web/lib/supabase`, `apps/web/proxy.ts` |
| Workers build and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` → `wrangler.jsonc` (committed), `component.yaml` |
| The Supabase project (stage, prod), its Auth settings | `infra/terraform/supabase` |
| Tests | `tests/web` (vitest) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # re-render apps/web/wrangler.jsonc from its template (committed; this changes nothing)
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

The build needs no Supabase project. Running it against one — `.env.local`
for `next dev` and the build, `.dev.vars` for `wrangler dev` — is in the
product's README (`.baseline/product/README.md`), which is what a product
built from here carries.

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting, `proxy.ts` on the edge | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets; the proxy runs in the Worker |
| Project env vars in the dashboard | `NEXT_PUBLIC_SUPABASE_URL` / `_PUBLISHABLE_KEY` are wrangler vars rendered per environment from the supabase root's `WIRING_SUPABASE`; `next build` inlines the same two from that config (`next.config.ts`) |
| A Supabase project created by hand, its redirect URLs set in the dashboard | `infra/terraform/supabase`: one project per environment, its Auth Site URL and redirect allow-list set to the Worker, its URL and keys published as orun secrets |
| Email confirmation through Supabase's built-in email | Off until the project has SMTP of its own (`authEmailConfirmation`), because the built-in email reaches only the organization's members |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, provisioned, deployed |

The publishable (anon) key is a wrangler var, not a secret: it is shipped to
every browser by design, and Row Level Security is the boundary.

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `checks.yml` | install, wire fixture, typecheck, lint, test, build — every PR (not pushes: on main, `ci.yml` must be the only run a commit has, because the bootstrap's convergence watch takes the newest one) | yes |
| `ci.yml` | the Orun pipeline: `orun plan --changed`, then one job per lane; applies and deploys stage → prod on merge. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does | yes |
| `baseline.yml` | the baseline's own tiers: contract tests; the blueprint read by the pinned orun, the leak gate, the offline bootstrap and the product's own plans; the product built in the job tree orun stages, dry-deployed, and served against a local Supabase stand-in — a sign-up, a sign-in, the protected page, the confirm route, the tutorial's table under RLS | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |
