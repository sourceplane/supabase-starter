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
| Latest tag | `baseline-v2` (SS5 — the product's own origin); `baseline-v1` is SS4 |
| On `main` since | SS6 — the cirrus standard (no kiox, generated component docs, this context pack) |
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

1. Bootstrap one product from the next tag against a workspace with a
   Supabase connection, and record its timings — the apply, the brokered
   token's reach to the API-keys and Auth-config endpoints, a sign-up on the
   first deploy (closes SS-I).
2. Cut the next `baseline-vN` with `tag.yml` so the registry can pin SS6.
