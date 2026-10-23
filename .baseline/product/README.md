# supabase-starter

Vercel's [Next.js and Supabase Starter](https://github.com/vercel/next.js/tree/canary/examples/with-supabase)
— Supabase Auth with cookie sessions through `@supabase/ssr`, a
session-refreshing proxy, sign-up / login / password flows and a protected
page — on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with a
**Supabase** project per environment provisioned by Terraform, its Auth
pointed at the app, on every merge to `main`.

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace, how sign-up behaves on each environment and the secrets inventory
into [ai/context/deployment.md](ai/context/deployment.md); how the product
deploys and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

## What is here

| Surface | Where |
|---|---|
| The product's name | `apps/web/lib/site.ts` |
| Home (tutorial), auth pages, `/protected`, `/api/health` | `apps/web/app` |
| Supabase clients (browser, server), the session proxy, what the auth forms say when Supabase refuses | `apps/web/lib/supabase`, `apps/web/proxy.ts` |
| Workers build and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` → `wrangler.jsonc`, `component.yaml` |
| The Supabase project (stage, prod) and its Auth settings | `infra/terraform/supabase` |
| Tests | `tests/web` (vitest) |

A coding agent starts at [AGENTS.md](AGENTS.md): what to read first, how a
change lands, and what not to touch.

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # re-render apps/web/wrangler.jsonc from its template (it is committed)
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

The build needs no Supabase project: without one it inlines the committed
`wrangler.jsonc`'s placeholder values, and nothing calls them.

## Running it locally

Against one of the product's own projects (stage is the natural one — its
URL and publishable key are in the Supabase dashboard → Project Settings →
API), or any Supabase project:

1. Copy `apps/web/.env.example` to `apps/web/.env.local` and fill in the two
   values. `next dev` and `pnpm build` read it.
2. Run Next's dev server —

   ```bash
   pnpm --filter @app/web dev          # http://localhost:3000
   ```

   — or the built Worker under `wrangler dev`, with the same two values in
   `apps/web/.dev.vars` (copy `.dev.vars.example`):

   ```bash
   pnpm build
   pnpm --filter @app/web preview      # http://localhost:8787
   ```

Sign-up and sign-in work locally as they do deployed. Links Supabase emails
(password recovery) point at the deployed Worker, which is the project's
Site URL.

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. Per environment the order is
enforced — **the Supabase project, then the Worker** — because the app's
build reads what the project's apply published: its URL and publishable key
(`WIRING_SUPABASE`), rendered into the Worker's vars and inlined into the
browser bundle. `stage` deploys first and `prod` once stage has converged on
the same commit; `dev` only verifies. Every deploy is smoke-tested over
HTTP, `/api/health` included, which answers only when the project's Auth
answers the key the build inlined.

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The
Cloudflare token and account id and the Supabase access token and org id are
brokered per run from the workspace's connections; the project's URL, keys
and database credentials are published by the Terraform apply as orun
secrets. Nothing provider-shaped is stored in the repository or in GitHub.

## Email

A Supabase project without an SMTP server of its own emails only the members
of its organization, a few times an hour. So each project is created with
email confirmation **off**: a new user is signed in the moment they sign up,
and anyone can. Password recovery still sends email — until the project has
SMTP, the form says the address cannot be mailed yet.

To require confirmation, give each project SMTP of its own (Supabase
dashboard → Authentication → Emails → SMTP Settings), then set
`authEmailConfirmation: "true"` in `infra/terraform/supabase/component.yaml`
and merge. The confirmation link lands on `/auth/confirm` when the project's
"Confirm signup" template is
`{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email&next=/protected`.

## Your first table

The protected page's tutorial creates a `notes` table with **row-level
security on** and policies that let each signed-in user read and add only
their own notes. Keep that rule for every table in `public`: the publishable
key is public by design, and RLS is what protects the data.

## Custom domain

The app answers on workers.dev from its first deploy. To serve it on your
own domain:

1. Attach the domain to the Worker in Cloudflare (Workers & Pages →
   `supabase-starter-web-prod` → Settings → Domains & Routes).
2. Set `SITE_URL: https://<your-domain>` under `environments.prod.env` in
   `intent.yaml`. It is the one setting for the product's origin: the app's
   build bakes it into its absolute links (the Open Graph and Twitter
   images), and the supabase apply makes it the project's Auth Site URL and
   redirect allow-list.
3. Redeploy both: change the last line of `apps/web/component.yaml` and of
   `infra/terraform/supabase/component.yaml` (`# orun: redeploy …`) in the
   same pull request — a change to `intent.yaml` alone plans nothing.

The apply owns the project's Auth URLs: an edit in the Supabase dashboard is
undone by the next apply.

The repository also names the domain in one place, `BASE_DOMAIN` under each
environment's `env:` in `intent.yaml`, which the product was born with as the
reserved placeholder `supabase-starter.example.com`. Nothing builds a URL from
it — the origin is `SITE_URL` — so replacing it moves nothing by itself; it
records the domain. Replace it with yours in the same pull request as
`SITE_URL`.

## CI

| Workflow | What it runs |
|---|---|
| `checks.yml` | install, wire fixture, typecheck, lint, test, build — every pull request (not pushes: on `main`, `ci.yml` must be the only run a commit has) |
| `ci.yml` | the Orun pipeline: `orun plan --changed`, then one job per lane; applies and deploys stage → prod on merge |
