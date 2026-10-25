# supabase-starter — where this repository stands

The entry page for anyone (or any agent) picking this repository up. It is
this repository's own state and does not ship to a product built from it; the
two pages that do are [operations.md](operations.md) and
[deployment.md](deployment.md).

## What it is

Vercel's Next.js and Supabase Starter on Cloudflare Workers + Static Assets
(`@opennextjs/cloudflare`), its Supabase project per environment provisioned
by Terraform through Orun, packaged as an Orun baseline: `orun new --blueprint
repo-blueprint.yaml` builds a new product in its own repository and takes it
to live on stage and prod in one landing (`01-product`: supabase → web per
environment), then records what went live (`02-docs`).

## Release

| | |
|---|---|
| Latest tag | `baseline-v4` (SS7 — the domain is set later: the console asks for no domain, and a product is born with the placeholder `<reponame>.example.com` in `BASE_DOMAIN` for an owner to replace); `baseline-v3` is SS6 (the cirrus standard), `baseline-v2` SS5, `baseline-v1` SS4 |
| In review | SS9 — the turso-starter v8 shape on the orun v2.88.0 floor: one `secrets` reconcile per provider, no `checks.yml`, every component's pages attached in the catalog and the app's domain `app`, the task set-up in the background, both landings checked in the box (`checks: local`), the watch at 5 s, no lockfile hook and no docs re-probe, and an await only of the three database credentials nothing reads (not `WIRING_SUPABASE`); the card's estimate 15 → 13 minutes. Untagged |
| Merged, untagged | SS8 (SS-10) — the build reads true in the console's build panel (saas-build-panel BV4): honest, short step lines, no authored await line (the engine says what a phase waits on), labelled landings, and an `AGENTS.md` in every product |
| Proven live | No. Nothing has been applied against a real Supabase organization: no Terraform apply, no live deploy, no live bootstrap (risk SS-I). Everything short of the platform is proven offline in Baseline CI, against a local Supabase stand-in |

## Where to read

| Question | Page |
|---|---|
| What shipped, and every departure from upstream | `specs/epics/supabase-starter/IMPLEMENTATION-STATUS.md` |
| Why it is built this way | [decisions.md](decisions.md), then `specs/epics/supabase-starter/design.md` |
| What could still go wrong | [open-risks.md](open-risks.md), then `specs/epics/supabase-starter/risks-and-open-questions.md` |
| How to instantiate it | `BOOTSTRAP.md`, `docs/phases/` |
| What each component is | `apps/web/docs/`, `infra/terraform/supabase/docs/`, `tests/web/docs/` (generated; `python3 tooling/catalog/gen-component-docs.py`) |

## Next

1. Cut `baseline-v5` once SS9 merges (it carries SS8 too), so the registry
   can pin a build on the v2.88.0 floor whose lines the panel reads true.
2. Bootstrap one product from the latest tag against a workspace with a
   Supabase connection, and record its timings — the apply, the brokered
   token's reach to the API-keys and Auth-config endpoints, a sign-up on the
   first deploy (closes SS-I).
