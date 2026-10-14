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
| Project env vars set in the Vercel dashboard | Build time: `component.yaml` `secretEnv` maps the `supabase` root's `SUPABASE_URL` and `SUPABASE_ANON_KEY` secrets to `NEXT_PUBLIC_*`, so `next build` inlines them. Run time: the same two values are wrangler `vars`, rendered per environment from the root's wiring document |
| A Supabase project created by hand | `infra/terraform/supabase` (Lumen's root): one project per environment, keys read with `supabase_apikeys`, published as orun secrets and a wiring document |
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
   outputs: project_url, anon_key,      SUPABASE_URL, SUPABASE_ANON_KEY,
            service_role_key, wiring    SUPABASE_SERVICE_ROLE_KEY, WIRING_SUPABASE
                                              │
apps/web/component.yaml secretEnv ◄───────────┘
   NEXT_PUBLIC_SUPABASE_URL / _PUBLISHABLE_KEY  → next build (inlined into client + server bundles)
   WIRING_SUPABASE_<ENV>                        → tooling/wire/live.mjs → wrangler.jsonc vars
```

`wrangler.template.jsonc` carries `@@wiring(supabase/__ENV__:…)@@` tokens.
The verify lane (and `pnpm run wire:fixture`) renders it from
`wiring.fixture.json`; the deploy lane renders it from the live document for
`$ORUN_ENVIRONMENT`. The rendered `wrangler.jsonc` is git-ignored.

## 4. The repository

```
apps/web                      the template (app/, components/, lib/, proxy.ts) + the Workers build
  component.yaml              build with turbo after rendering wrangler; deploy with wrangler; smoke /
  wrangler.template.jsonc     worker name, nodejs_compat, ASSETS, the two Supabase vars as wiring tokens
  wiring.fixture.json         offline values for the verify lane
  open-next.config.ts         static-assets incremental cache (pre-rendered shells), no R2/KV/D1
infra/terraform/supabase      the Supabase project per environment (Lumen's root + API keys)
tests/web                     vitest: the proxy's redirect decisions, `cn`
```

## 5. Out of scope

Database tables and migrations (the template ships none; Lumen's
`packages/db` + `db-migrate` is the shape when a port needs them), OAuth
providers, custom SMTP for auth emails, and a custom domain. Supabase's
auth email redirect URL (`Site URL`) must point at the deployed Worker; the
README says where.
