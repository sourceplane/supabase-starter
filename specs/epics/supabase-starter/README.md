# Epic: supabase-starter (SS)

**Vercel's `with-supabase` starter is the template that already speaks the second provider the Lumen baseline brokers. Its auth is Supabase Auth, its session is a cookie refreshed by a Next.js proxy, its data lives behind Row Level Security — none of which cares whether the server is a Vercel function or a Cloudflare Worker. The port keeps the code and moves the two things that are Vercel's: where the app runs (an OpenNext Worker + Static Assets) and where the Supabase project comes from (Terraform through Orun, with the project URL and publishable key published as secrets the build and the Worker read per environment).**

The upstream code stays the code: the `@supabase/ssr` server/browser clients, the `proxy.ts` session refresh and redirect, the auth pages, the protected page and the tutorial components. The port adds the Workers build, the monorepo wrapper, a test package that exercises the proxy's decisions, the Terraform root for the Supabase project, and the deploy contract that threads the project's URL and key into `next build` (for `NEXT_PUBLIC_*` inlining) and into wrangler vars (for the Worker).

## Status

| Field | Value |
|-------|-------|
| Status | ✅ Shipped — SS0–SS3 landed (#1–#4); Supabase apply and live deploy gated on a linked workspace |
| Cluster | **SS** (SS0–SS3) |
| Owner(s) | `apps/web` (the app) · `tests/web` (proxy tests) · `infra/terraform/supabase` (the project) |
| Builds on | `lumen` conventions — the `supabase` Terraform root and the orun-secrets wiring; `cirrus-baseline` conventions for the repository shape |
| Upstream | [vercel/next.js `examples/with-supabase`](https://github.com/vercel/next.js/tree/canary/examples/with-supabase) |
| Changes | Adds the Workers build, the monorepo wrapper, tests, the Supabase root and the deploy contract; the template's app code is untouched |
| Decisions locked | (1) OpenNext on Workers + Static Assets. (2) The publishable key is a wrangler var, not a secret: RLS protects the data. (3) `wrangler.jsonc` is rendered per environment from the wiring document; never committed. (4) No Hyperdrive: the template never opens a Postgres connection, it speaks PostgREST over HTTPS. |
| Gate | SS1 is the first user-visible rung. SS2 needs a workspace with a Supabase connection to apply; it is verified by `plan`. |
| Shipped as | `main` after [#4](https://github.com/sourceplane/supabase-starter/pull/4); verified locally under `wrangler dev` with fixture vars |

## Read order

1. `design.md` — what maps to what, the env/secret flow, what is out of scope
2. `implementation-plan.md` — the milestones and what "done" means for each
3. `risks-and-open-questions.md` — what could go wrong and what was decided
4. `IMPLEMENTATION-STATUS.md` — what actually shipped (kept distinct from intent)

## Milestones at a glance

| Milestone | What it lands | Done when |
|---|---|---|
| SS0 — the spec | this doc set and the task contracts | merged on `main` |
| SS1 — the starter on Workers | `apps/web` built by OpenNext, rendered wrangler config, `tests/web` | `wrangler dev` serves `/` and redirects `/protected`; Checks green |
| SS2 — the Supabase project from Terraform | `infra/terraform/supabase`, the app's `secretEnv` and `dependsOn` | the root plans; the wiring keys match the template |
| SS3 — ready to instantiate | README, as-built status | a reader can run, test, preview and deploy it |
