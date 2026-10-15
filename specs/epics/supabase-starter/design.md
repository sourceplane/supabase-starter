# supabase-starter — design

## 1. What the template is

Next.js App Router + Supabase Auth. `lib/supabase/{client,server}.ts` build
the browser and server clients from `NEXT_PUBLIC_SUPABASE_URL` and
`NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`; `proxy.ts` (Next 16's middleware)
calls `updateSession`, which refreshes the auth cookie on every request and
redirects a signed-out visitor of anything but `/`, `/login*` and `/auth*`
to `/auth/login`. Pages: home with a tutorial, sign-up, login, forgot and
update password, an email-confirm route handler, and `/protected`, which
prints the user's claims. shadcn/ui components, Tailwind 3, `next-themes`.
`cacheComponents: true` in `next.config.ts`.

## 2. The mapping (Vercel → Cloudflare + Supabase)

| Vercel primitive the template uses | Here |
|---|---|
| Next.js hosting (SSR, proxy, route handlers) | Cloudflare Workers + Static Assets; the Worker is `@opennextjs/cloudflare`'s output, assets bound as `ASSETS` |
| `proxy.ts` on the edge | Runs inside the same Worker (OpenNext bundles the proxy as the middleware function) |
| Project env vars set in the Vercel dashboard | Run time: wrangler `vars`, rendered per environment from the root's wiring document (`WIRING_SUPABASE`). Build time: `next.config.ts` reads the same two from that rendered `wrangler.jsonc`, so `next build` inlines what the Worker runs with (SS4; SS2 read them from two more published secrets) |
| A Supabase project created by hand, its redirect URLs set in the dashboard | `infra/terraform/supabase` (Lumen's root): one project per environment, keys read with `supabase_apikeys` into one wiring document; its Auth Site URL and redirect allow-list set to the Worker with `supabase_settings`, email confirmation off until the project has SMTP (SS4) |
| Deploy on push | Orun: `apps/web/component.yaml` (`cloudflare-workers-assets-turbo`) deploys `supabase-starter-web-{stage,prod}` on merge to `main` once the product is linked |

Alternative rejected: Hyperdrive + Postgres, as Lumen's workers use. The
template never opens a database connection; it talks to Supabase over
HTTPS (PostgREST + GoTrue) with the publishable key and the user's JWT.
Adding Hyperdrive would add a root the app cannot use. The `saas-starter`
and `ai-chatbot` ports, which use Drizzle over a Postgres socket, are where
the Hyperdrive root belongs.

## 3. The env and secret flow

```
infra/terraform/supabase  ──apply──►  orun secrets (project/<env> rung)
   outputs: wiring,                     WIRING_SUPABASE = {supabase_url, supabase_anon_key}
            project_ref,                SUPABASE_PROJECT_REF, SUPABASE_DB_PASSWORD,
            database_password,          SUPABASE_DB_URL   (Lumen's three; for the owner)
            connection_uri
   and the project's Auth: site_url = uri_allow_list = the Worker, mailer_autoconfirm
                                              │
apps/web/component.yaml optionalSecretEnv ◄───┘
   WIRING_SUPABASE_<ENV>  → tooling/wire/live.mjs → wrangler.jsonc vars
                                                   → next.config.ts → next build (inlined)
```

`wrangler.template.jsonc` carries `@@wiring(supabase/__ENV__:…)@@` tokens.
`pnpm run wire:fixture` renders it from `wiring.fixture.json` into the
COMMITTED `wrangler.jsonc` — the composition checks that file exists before
the build, in a fresh checkout — which `wrangler dev`, the dev verify lane
and `Checks` use; the stage and prod lanes re-render it from the live
document for `$ORUN_ENVIRONMENT` before they build (SS4; it was git-ignored
before).

On a push to main the two components converge in one run, per environment,
`supabase → web`, because the app declares `dependsOn` on the root with
`mode: enforced` (advisory on a pull request). A job resolves its secrets
when it starts, so the document the apply published is there for the
deploy.

## 4. The repository

```
apps/web                      the template (app/, components/, lib/, proxy.ts) + the Workers build
  component.yaml              build with turbo after rendering wrangler; deploy with wrangler; smoke /
  wrangler.template.jsonc     worker name, nodejs_compat, ASSETS, the two Supabase vars as wiring tokens
  wiring.fixture.json         offline values for the verify lane
  open-next.config.ts         static-assets incremental cache (pre-rendered shells), no R2/KV/D1
infra/terraform/supabase      the Supabase project per environment (Lumen's root + API keys + Auth URLs)
tests/web                     vitest: the proxy's redirect decisions, `cn`
```

## 5. Out of scope

Database tables and migrations (the template ships none — its tutorial's
`notes` table is the owner's to create, with RLS; Lumen's `packages/db` +
`db-migrate` is the shape when a port needs them), OAuth providers, custom
SMTP for auth emails (confirmation is off until the owner adds it), and a
custom domain. Since SS4 the Auth Site URL points at the deployed Worker
without anyone touching the dashboard.
