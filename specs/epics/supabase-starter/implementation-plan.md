# supabase-starter — implementation plan

Milestones land in order; each task is one pull request on an
`orun/SS-n-<slug>` branch with an `Orun-Task: SS-n` trailer.

## SS0 — the spec ✅

This doc set, `epic.yaml` and the task contracts, merged to `main`.

**Done when**
- the five documents and `epic.yaml` are on `main`
- `tasks/SS-1..SS-4.TaskContract.yaml` exist

## SS1 — the starter on Workers ✅

`apps/web` is the upstream template with the Workers build around it;
`wrangler.template.jsonc` + `wiring.fixture.json` render the config;
`tests/web` exercises `updateSession`.

**Done when**
- `pnpm install && pnpm run wire:fixture && pnpm typecheck && pnpm lint && pnpm test && pnpm build` is green locally and in `Checks`
- `wrangler dev` answers `/` with the starter's home page and `/protected` with a 307 to `/auth/login` when signed out
- the auth pages render (`/auth/login`, `/auth/sign-up`)

## SS2 — the Supabase project from Terraform ✅

`infra/terraform/supabase` provisions a project per environment and
publishes URL, keys and the wiring document; `apps/web/component.yaml`
depends on it and declares the `secretEnv` the build and the deploy read.

**Done when**
- `terraform validate` passes on the root
- the component's `secretEnv` keys match the root's `secretOutputs`
- the fixture's wiring keys match the template's tokens (`wire:fixture` renders)

## SS3 — ready to instantiate ✅

README (run, test, preview, deploy, the Supabase auth redirect URL),
`IMPLEMENTATION-STATUS.md` with PRs and departures, epic `completed`.

**Done when**
- the README quick start works from a fresh clone with a `.env.local`
- the status file lists every PR and departure

## SS4 — a baseline ✅

The repository becomes an Orun baseline on the Lumen conventions, built the
way cirrus-baseline v22 builds a product — in ONE landing:

- `blueprint.yaml` (the card: `requires [github, cloudflare, supabase]`, the
  four brokered secrets as a preview, the programme `01-product`, `02-docs`,
  the two Supabase projects stated as a prerequisite) and
  `repo-blueprint.yaml` (every module placed by `01-product` and landed as
  one pull request; `02-docs` hook-only);
- the app's edge on the root `mode: enforced` on a push to main, advisory on
  a pull request, so one convergence runs supabase → web per environment;
- the root publishing `WIRING_SUPABASE` beside Lumen's three and pointing
  each project's Auth at its Worker with confirmation off, so a fresh product
  signs users up with no SMTP server;
- `wrangler.jsonc` committed as the fixture render, and `next build` reading
  the project from it;
- the tutorial's table under row-level security keyed on `auth.uid()`;
- `.baseline/`, the rename engine, the bootstrap helpers, the deployment
  record, `ai/context/`, `testing/` and the `baseline.yml` / `tag.yml` lanes.

**Done when**
- orun reads the build document at the bootstrap floor (v2.58.11), the lane
  pin (v2.78.4) and 2.79.0, and the card agrees with it
- the product's own `orun plan --trigger github-push-main` shows the order,
  enforced; a pull request's plan holds the same edge advisory
- the e2e tier builds in the job tree orun stages with the stage wiring
  inlined, and signs a user up and in against a local Supabase stand-in; the
  tutorial's table admits each user to their own rows only

## SS5 — the product's own origin ✅

Two defects `baseline-v1` shipped in every product, fixed:

- `metadataBase` from `NEXT_PUBLIC_SITE_URL`, which the component's
  buildCommand bakes in — the environment's `SITE_URL` when `intent.yaml`
  sets one, else its workers.dev URL — instead of `VERCEL_URL`, which no
  Cloudflare build has (every page's `og:image` and `twitter:image` named
  `localhost:3000`);
- the supabase root reads the same `SITE_URL` for Auth's Site URL and
  redirect allow-list, so one setting moves both;
- the Deploy to Vercel button (`components/deploy-button.tsx`) and its uses
  in the home page and the protected layout are gone.

**Done when**
- the e2e tier asserts the served home page's `og:image` and `twitter:image`
  start with the stage Worker's own origin, and that no page offers a Deploy
  to Vercel button
- `SITE_URL` under an environment's `env` is the single setting for the
  app's absolute links and Auth's Site URL

## SS6 — the cirrus standard ✅

Bring the baseline to cirrus-baseline's standard, with nothing about the
product itself changing.

- **No kiox.** `kiox.yaml`/`kiox.lock` pinned an orun (v2.15.0) that nothing
  ran: every workflow installs orun itself through `orun-action` with its own
  `version:`. The files, their two modules and the rebrand's skip entry go.
- **Component docs.** `tooling/catalog/gen-component-docs.py` writes each
  component's `docs/overview.md`, `docs/architecture.md` and `docs/runbook.md`
  from what the component declares, as cirrus-baseline's do; the pages ship
  with the component. Baseline CI runs it with `--check`.
- **The context pack.** `ai/context/current.md`, `decisions.md` and
  `open-risks.md` beside the two pages a product ships with — this
  repository's own, so no module places them.
- **Status that agrees with the tags.** SS4 (`baseline-v1`) and SS5
  (`baseline-v2`) are shipped and tagged.

**Done when**
- nothing outside this milestone's own record names kiox (`git grep -i
  kiox`), and the leak gate and the offline bootstrap pass without the two
  modules
- the docs check is green in Baseline CI
- this file, the status file and `epic.yaml` agree

## Sequencing note

SS1 and SS2 are independent files but SS1's component already names the
root's secrets, so SS2 is the half that makes those names true. Applying
SS2 needs a workspace with a Supabase connection; until then the Orun lane
is gated and `Checks` is the merge gate. SS3 is documentation over both.
