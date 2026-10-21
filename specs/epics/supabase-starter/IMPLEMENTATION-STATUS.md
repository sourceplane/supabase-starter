# supabase-starter (SS) — Implementation status

As-built ≠ intent. This file records what actually shipped, and every place
the code departed from `design.md` or from the upstream template.

| Milestone | State | PR |
|---|---|---|
| SS0 — the spec | ✅ Shipped | [#1](https://github.com/sourceplane/supabase-starter/pull/1) |
| SS1 — the starter on Workers | ✅ Shipped | [#2](https://github.com/sourceplane/supabase-starter/pull/2) |
| SS2 — the Supabase project from Terraform | ✅ Shipped (validated; apply gated on a linked workspace) | [#3](https://github.com/sourceplane/supabase-starter/pull/3) |
| SS3 — ready to instantiate | ✅ Shipped | [#4](https://github.com/sourceplane/supabase-starter/pull/4) |
| SS4 — a baseline | ✅ Shipped | [#5](https://github.com/sourceplane/supabase-starter/pull/5) (SS-5), tagged `baseline-v1` |
| SS5 — the product's own origin | ✅ Shipped | [#6](https://github.com/sourceplane/supabase-starter/pull/6) (SS-6), tagged `baseline-v2` |
| SS6 — the cirrus standard | ✅ Shipped | SS-7 — on `main` after `baseline-v2`, not yet tagged |

## Departures from the upstream template

### eslint-config-next 16 flat config

The template's `eslint.config.mjs` bridged `next/core-web-vitals` through
`@eslint/eslintrc`'s FlatCompat; eslint-config-next 16 ships flat configs
and the bridge dies on them (circular structure). The config is what
`create-next-app` writes for Next 16, with `react-hooks/set-state-in-effect`
off: the rule is new in 16 and flags the template's `useEffect(() =>
setMounted(true))` mount pattern, which is kept as written.

### `tailwindcss-animate` imported, not required

`tailwind.config.ts` used `require("tailwindcss-animate")`, which the
TypeScript ESLint rules reject; it is an `import` now.

### Versions

| Package | Version | Why |
|---|---|---|
| next | 16.3.8 | newest inside `@opennextjs/cloudflare` 1.20.11's peer range |
| @supabase/ssr, @supabase/supabase-js | ^0.12.7, ^2.117 | the template pinned `latest` |
| @opennextjs/cloudflare | ^1.20.11 | static-assets incremental cache + `populateCache local`; Next 16 `proxy.ts` as Node.js middleware |

## Verified

- Local: `pnpm run wire:fixture`, `pnpm typecheck`, `pnpm lint`, `pnpm test`
  (5 tests), `pnpm build` green; `wrangler dev` with the fixture vars: `/`
  200 ("Next.js and Supabase Starter Kit"), `/protected` signed out 307 →
  `/auth/login`, `/auth/login` and `/auth/sign-up` 200.
- `terraform validate` green on `infra/terraform/supabase`.
- CI: `Checks` green on #2 and #3.
- Not verified: an apply of the Supabase root and a live deploy — both need
  the product linked to an Orun workspace with Supabase and Cloudflare
  connections (`ORUN_CI` variable). Supabase's auth Site URL must then be
  set to the Worker's origin (README).

## SS4 — a baseline (SS-5)

The repository is an Orun baseline on the Lumen conventions, built the way
cirrus-baseline v22 builds a product: ONE landing. `blueprint.yaml` is the
card (`requires: [github, cloudflare, supabase]`; the four brokered keys —
`CLOUDFLARE_API_TOKEN` workers-deploy, `CLOUDFLARE_ACCOUNT_ID` account-id,
`SUPABASE_ACCESS_TOKEN` management-access, `SUPABASE_ORG_ID` org-id — as a
preview; programme `01-product`, `02-docs`; the two Supabase projects the
free plan allows stated as a prerequisite); `repo-blueprint.yaml` places every
module in `01-product`, brands it, links the repository, reconciles the four
keys and lands it as one pull request, then awaits the convergence, the four
published secrets on stage and prod and `/` + `/api/health`; `02-docs`
restores the promotion gate and dev's lanes and renders the record. The
machinery is the saas-starter port's (SA5, itself portfolio-starter-kit's
`baseline-v2` adapted to two phases) — `.baseline/`, the rename engine, the
bootstrap helpers, the deployment-record hook, `ai/context/`, `testing/`,
`baseline.yml`, `tag.yml`, `ci.yml`'s `linked` gate — without Hyperdrive and
without db-migrate.

### Departures, in the product

- **The build reads the project from the wrangler config**
  (`next.config.ts`). SS2 fed `next build` the URL and key through two more
  published secrets (`SUPABASE_URL`, `SUPABASE_ANON_KEY` as `NEXT_PUBLIC_*`
  secretEnv, resolved for `{{ .environment }}` — which `dev` has none of, so
  its verify lane could not have resolved them). Now a production build takes
  them from `wrangler.jsonc`'s vars — the committed fixture render, or the one
  the stage/prod lane re-rendered from `WIRING_SUPABASE_<ENV>` just before it
  built — so the browser bundle and the Worker name one project, from one
  document. `.env.local` still wins; `next dev` is unchanged.
- **`apps/web/wrangler.jsonc` is committed** — the fixture render of the
  template — because the composition checks for it before the build. The
  stage and prod lanes re-render it; dev verifies with the fixture (SS-F).
  `tests/web` holds it equal to the template.
- **The supabase root** keeps Lumen's three outputs (`SUPABASE_PROJECT_REF`,
  `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`, published for the owner and for
  a migration step a later change may add) and publishes `WIRING_SUPABASE`
  (URL and publishable key), nothing else: `SUPABASE_URL`,
  `SUPABASE_ANON_KEY` and the service-role key are no longer published (the
  last is not even an output any more). It carries the provider lock file.
- **The project's Auth is Terraform's** (`supabase_settings`): Site URL and
  redirect allow-list `https://<repo>-web-<env>.<subdomain>.workers.dev`
  (the component's new `workersDevSubdomain` parameter), and
  `mailer_autoconfirm` on unless `authEmailConfirmation: "true"`. A fresh
  project sends email only to its organization's members, so with
  confirmation on nobody else could sign up, and its links went to
  `localhost:3000`. A `terraform_data` waits for `ACTIVE_HEALTHY` before the
  API keys are read and the settings written (the provider returns from a
  create at once).
- **The app depends on the project, enforced on main** (`dependsOn` with
  `mode: enforced` and an advisory `modeRules` entry for pull requests). Its
  wiring documents are `optionalSecretEnv`: stage's deploy waits on stage's
  apply only, and while the bootstrap runs both environments side by side
  prod's document may not exist yet when stage's deploy starts; `live.mjs`
  refuses a deploy whose own document is missing (SS-H).
- **Sign-up routes on the session it gets** (`components/sign-up-form.tsx`):
  to `/protected` when the project signed the user straight in, to
  `/auth/sign-up-success` ("check your email") only when it did not.
  Upstream always said "check your email".
- **The auth forms explain a fresh project's refusals**
  (`lib/supabase/errors.ts`): `email_address_not_authorized`,
  `over_email_send_rate_limit` and an unreachable service get a sentence
  saying what is going on; every other error is Supabase's message, as
  before.
- **The tutorial's table has row-level security keyed on `auth.uid()`**
  (`components/tutorial/fetch-data-steps.tsx`): `notes` gets a `user_id`
  (default `auth.uid()`, referencing `auth.users`), RLS is enabled in the
  same statement that creates it, the seed gives each signed-up user three
  notes, and the policies let each signed-in user read and add only their
  own. Upstream created the table without RLS and then suggested a
  public-read policy.
- **`/api/health`** (new): 200 only when the project's Auth answers the URL
  and key the build inlined (`/auth/v1/settings`), and it reports whether
  sign-up is open and whether it asks for confirmation. The deploy's smoke,
  both phases' probes and the deployment record read it, without a session —
  so `proxy.ts`'s matcher leaves `/api/health` out (upstream's proxy sends a
  signed-out request for any path but `/` and `/auth/*` to the login page).
- **The product's name is one seam** (`lib/site.ts`, `SITE_NAME`): the
  header's home link (upstream: "Next.js Supabase Starter") and the
  `<title>` (upstream: "Next.js and Supabase Starter Kit"). The deploy
  smoke now looks for the sign-up link instead of the title.
- **`packages/.gitkeep`**: `intent.yaml` discovers `packages/`, and orun
  refuses an intent whose discovery root is missing — `orun validate` failed
  on SS3's tree.
- **stack-tectonic 0.19.0** (was 0.18.2; not 0.20.0, whose lane-scoped install
  Turbopack refuses), **`checks.yml` on pull requests only**, `ci.yml`'s
  `linked` gate in place of the `ORUN_CI` variable and its lanes on v2.78.4.
- `apps/web/README.md` describes the app as it runs here (upstream's text is
  upstream's repository); `intent.yaml`'s docs pages are the product's
  `ai/context/` pages.

### Verified (SS4)

See the pull request for the run log. In short: the repository's checks
(`pnpm install --frozen-lockfile`, `wire:fixture`, typecheck, lint, test —
25 tests in `tests/web` — build); every `testing/*.test.sh`; `orun new
--status` at v2.58.11, v2.78.4 and 2.79.0; `orun validate`; `orun work
check`; `terraform fmt`, `init -backend=false` and `validate` on the root.
Not verified: a Terraform apply (so neither the brokered OAuth token's reach
to the API-keys and Auth-config endpoints nor `ACTIVE_HEALTHY` polling), a
live deploy, a live bootstrap, and real email delivery (SS-I).

## SS5 — the product's own origin (SS-6)

Two defects `baseline-v1` shipped in every product:

- **The image links named localhost.** `app/layout.tsx` built `metadataBase`
  from `VERCEL_URL`, which no Cloudflare build has, so `og:image` and
  `twitter:image` on every deployed page were `http://localhost:3000/…`.
  `metadataBase` is now `NEXT_PUBLIC_SITE_URL`, which `component.yaml`'s
  buildCommand bakes in: the environment's `SITE_URL` when `intent.yaml` sets
  one, else `https://<repo>-web-<env>.<subdomain>.workers.dev` — written out
  in the command (the rename rewrites the worker name and the subdomain),
  because the composition exports `WORKERS_DEV_SUBDOMAIN` to the smoke step
  only. Baked at build rather than read from the request (`headers()` in
  `generateMetadata`), because the pages are prerendered (`cacheComponents`):
  a request-time origin would have made every static page dynamic.
- **The header offered "Deploy to Vercel"**, cloning upstream's example to
  Vercel. `components/deploy-button.tsx` is gone, and so is its use in the
  home page and the protected layout. The tutorial's Vercel-only step
  (`sign-up-user-steps.tsx`, shown only when `VERCEL_ENV` is set) never
  renders on Cloudflare and is left as upstream wrote it.

One origin, one setting: the supabase root reads the same `SITE_URL` (the
runner exports an environment's `env:` to every job of it) and makes it
Auth's Site URL and redirect allow-list, falling back to the same workers.dev
URL — so a custom domain is `SITE_URL` plus a redeploy of both components.
The rename's upstream list drops the deploy link and the demo URL, which
nothing in the tree carries any more.

### Verified (SS5)

The repository's checks; `testing/rebrand.test.sh`, `leak.test.sh` and
`placement.test.sh` (the product's build bakes its own origin, Auth's Site
URL follows SITE_URL, no Vercel clone link in the app); `e2e.test.sh` at
v2.78.4, which now asserts the served home page's `og:image` and
`twitter:image` start with the stage Worker's origin, that both images are
served, and that no "Deploy to Vercel" appears; `terraform validate` on the
root, and the origin it computes with and without `SITE_URL`.

## The cirrus standard (SS6)

Nothing about the product changed. What changed is the baseline around it:

| What | Before | After | Why |
|---|---|---|---|
| orun pin | `kiox.yaml` (v2.15.0) + `kiox.lock`, shipped to every product | gone; orun is pinned where it runs, the `orun-action` `version:` in each workflow | nothing ran the kiox pin, and it disagreed with the lanes (v2.78.4) |
| `root-kiox`, `root-kiox-lock` modules | in `01-product` | removed (`testing/phases.test.sh` and the rebrand's skip list follow) | a product is placed with 105 − 2 + 9 = 112 files: no kiox, plus the docs below |
| component docs | none | `apps/web/docs/`, `infra/terraform/supabase/docs/`, `tests/web/docs/` — `overview.md`, `architecture.md`, `runbook.md` | cirrus-baseline documents every component; the workspace Docs library renders `docs/` beside each `component.yaml` |
| how the docs stay true | — | `tooling/catalog/gen-component-docs.py` derives them from the manifest, the Worker config, Terraform, migrations and package scripts; Baseline CI runs it with `--check` | a hand-written copy of a manifest drifts silently |
| context pack | `operations.md`, `deployment.md` | plus `current.md`, `decisions.md`, `open-risks.md` | cirrus-baseline's shape; the three new pages are this repository's own and no module places them (the leak gate still allows exactly two) |
| status | SS5 "in review"; SS4 without its ✅ in the plan, SS5 without a section | SS4 shipped and tagged `baseline-v1`, SS5 shipped and tagged `baseline-v2`, both in the plan | the tags existed; the documents had not caught up |

## Verified (SS6)

- `testing/{manifest,phases,coverage,rebrand,retouch,bootstrap-defer}.test.sh`
  green; `gen-component-docs.py --check` green (3 components, 9 pages).
- `testing/leak.test.sh` (v2.58.11): 112 files derived (105 − 2 kiox + 9
  docs pages), 104 text files read; ai/context still exactly the two
  declared pages; the generated pages name no factory path.
- `testing/placement.test.sh` (v2.58.11): 112 files placed, both landings,
  branded, re-tenanted; the product's own `orun plan` for the 01-product
  merge holds supabase → web enforced on stage and prod; `--resume` changes
  nothing.
- `pnpm install --frozen-lockfile`, `wire:fixture`, `typecheck`, `lint`,
  `test` (25 tests, 7 files), `build` green.
- `testing/e2e.test.sh` (v2.78.4) green: the Checks sequence on the
  01-product landing, the stage lane's planned steps in a staged job tree,
  `wrangler dev` over the built Worker against the local Supabase stand-in —
  the smoke, every route, sign-up and sign-in, the origin assertions, and
  the tutorial's table under row-level security. Its Terraform step was
  skipped (no terraform on PATH); `terraform fmt -check`, `init
  -backend=false` and `validate` (1.15.3) on the root are green on their
  own, the lock file unchanged.
- `orun task check SS-7` complete.
