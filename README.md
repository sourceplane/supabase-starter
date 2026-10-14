# supabase-starter

Vercel's [Next.js and Supabase Starter](https://github.com/vercel/next.js/tree/canary/examples/with-supabase)
— Supabase Auth with cookie sessions through `@supabase/ssr`, a
session-refreshing proxy, sign-up / login / password flows and a protected
page — running on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with the
Supabase project itself provisioned by Terraform through
[Orun](https://github.com/sourceplane/orun), the way the
[Lumen baseline](https://github.com/sourceplane/lumen) does it.

The template's code is the code. What the port adds is the Workers build,
the monorepo wrapper, a test package for the session proxy, the Supabase
Terraform root, and the deploy contract that threads the project's URL and
publishable key into the build and the Worker per environment. See
[`specs/epics/supabase-starter`](specs/epics/supabase-starter/README.md)
for the design, the milestones and the as-built status.

## What is here

| Surface | Where |
|---|---|
| Home (tutorial), auth pages, `/protected` | `apps/web/app` |
| Supabase clients (browser, server) and the session proxy | `apps/web/lib/supabase`, `apps/web/proxy.ts` |
| Workers build and deploy contract | `apps/web/next.config.ts`, `apps/web/open-next.config.ts`, `apps/web/wrangler.template.jsonc`, `apps/web/component.yaml` |
| The Supabase project (stage, prod) | `infra/terraform/supabase` |
| Tests | `tests/web` (vitest) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

To run against a Supabase project, put its URL and publishable key in
`apps/web/.env.local` (see `apps/web/.env.example`), then:

```bash
pnpm --filter @app/web dev        # http://localhost:3000, Next's dev server
pnpm --filter @app/web preview    # wrangler dev over the built Worker; set the same two values in apps/web/.dev.vars
```

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting, `proxy.ts` on the edge | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets; the proxy runs in the Worker |
| Project env vars in the dashboard | Build time: `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` from orun secrets (inlined by `next build`). Run time: the same values as wrangler `vars`, rendered per environment from the Supabase root's wiring document |
| A Supabase project created by hand | `infra/terraform/supabase`: one project per environment, URL and API keys published as orun secrets |
| Deploy on push | Orun deploys `supabase-starter-web-{stage,prod}` on merge to `main` (`apps/web/component.yaml`) |

The publishable (anon) key is a wrangler var, not a secret: it is shipped to
every browser by design, and Row Level Security is the boundary.

## Deploying

`.github/workflows/checks.yml` runs install, wire, typecheck, lint, test and
build on every push and pull request. `ci.yml` is the Orun pipeline: set
`execution.state.workspace` in `intent.yaml` to this product's workspace
(`orun cloud link`), connect Cloudflare **and Supabase** to that workspace,
and set the `ORUN_CI` repository variable to `true`. A merge to `main` then
applies the Supabase root, builds the app with that environment's URL and
key, and deploys the Worker to `stage`, then `prod`.

After the first apply, set the project's auth **Site URL** and redirect
allow-list (Supabase dashboard → Authentication → URL Configuration) to the
deployed Worker's origin, e.g. `https://supabase-starter-web-prod.<subdomain>.workers.dev`,
so confirmation and recovery emails link back to the app.
