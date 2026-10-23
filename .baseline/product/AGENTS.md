# supabase-starter — notes for coding agents

You are in the repository of a live product. Read this before you change
anything; `README.md` is the same product told for the person who runs it.

## What this is

A Next.js app with Supabase Auth — email and password sign-up, sign-in,
password reset, sessions in cookies refreshed by a proxy, a protected page —
built by OpenNext into one Cloudflare Worker, with a Supabase project per
environment (`stage`, `prod`) created by Terraform. Orun deploys it: a merge
to `main` converges what it changed, the Supabase project before the app and
stage before prod. `dev` only verifies.

| component | path | what it is |
|---|---|---|
| `web` | `apps/web` | the app and its Worker build (`component.yaml`, `next.config.ts`, `wrangler.template.jsonc`) |
| `supabase` | `infra/terraform/supabase` | the Supabase project per environment and its Auth settings |
| `web-tests` | `tests/web` | the vitest suite |

`intent.yaml` declares the environments, the workspace and how CI plans; each
`component.yaml` declares one component and what it depends on.

## Read first

1. `README.md` — what is where, running it locally, "Email", "Your first
   table", "Custom domain".
2. `ai/context/operations.md` — how a deploy works, the secrets model,
   row-level security, the common operations.
3. `ai/context/deployment.md` — the live URLs, the workspace and the secrets,
   by name, as last probed.
4. `apps/web/lib/supabase` — the browser and server clients, the session
   proxy, and what the auth forms say when Supabase refuses.
5. `infra/terraform/supabase` — `component.yaml` (its parameters and what it
   publishes) and `terraform/main.tf`.

## How a change lands

- Work is tracked as tasks on the Orun workspace (`orun task list`). One task,
  one branch, one pull request against `main` — `orun pr open` names the
  branch after the task and records it in the pull request.
- Before you push: `pnpm install`, `pnpm run wire:fixture`, `pnpm typecheck`,
  `pnpm lint`, `pnpm test`, `pnpm build`. `checks.yml` runs the same on the
  pull request; `orun validate` and `orun plan` show what `ci.yml` will plan.
- Merging is deploying. Watch the run on `main`, then probe the URLs in
  `ai/context/deployment.md`: a run that planned nothing deployed nothing.
- A table in `public` gets row-level security and `auth.uid()` policies in the
  statement that creates it — the publishable key is public by design.
- A new component is a directory under `apps/`, `infra/` or `packages/` with a
  `component.yaml`, declaring `dependsOn` on any infrastructure whose
  published secrets it reads.

## Do not touch

- `execution.state.workspace` in `intent.yaml`: every remote operation and
  every CI credential is scoped to it.
- `apps/web/wrangler.jsonc` by hand: edit `wrangler.template.jsonc` and run
  `pnpm run wire:fixture`. Never commit a real project's URL or key.
- `ai/context/deployment.md`, and the README between `<!-- 02-docs:begin -->`
  and `<!-- 02-docs:end -->`: both are rendered from probes.
- The Auth URLs in the Supabase dashboard: the apply owns the Site URL, the
  redirect allow-list and `mailer_autoconfirm`, and undoes a dashboard edit.
- Secret values, anywhere — the repository, `ai/context/`, a log, GitHub.
  Provider credentials are brokered per run; secrets are inspected by name.
- `checks.yml` on pull requests only: on `main`, `ci.yml` is the one run a
  commit has.
- The last line of a `component.yaml` (`# orun: redeploy …`) is a deploy
  trigger; change it only to redeploy that component.
