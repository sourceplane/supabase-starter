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

## Sequencing note

SS1 and SS2 are independent files but SS1's component already names the
root's secrets, so SS2 is the half that makes those names true. Applying
SS2 needs a workspace with a Supabase connection; until then the Orun lane
is gated and `Checks` is the merge gate. SS3 is documentation over both.
