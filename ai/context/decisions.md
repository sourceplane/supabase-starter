# supabase-starter — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | OpenNext on Workers + Static Assets (`cloudflare-workers-assets-turbo`), no Hyperdrive | The template's SSR, `proxy.ts` and route handlers run in one Worker; it never opens a Postgres connection — it speaks PostgREST and GoTrue over HTTPS | `specs/epics/supabase-starter/design.md` §2, risk SS-A |
| 2 | The publishable key is a wrangler var, not a secret | It ships to every browser by design; row-level security is the boundary | risk SS-B |
| 3 | `wrangler.jsonc` committed as the fixture render; stage and prod re-render it from `WIRING_SUPABASE_<ENV>`, and `next build` reads the project from it | The composition checks the file exists before the build, and the browser bundle and the Worker must name one project (SS4; SS1 git-ignored it, SS2 fed the build two more secrets) | risks SS-E, SS-F |
| 4 | Terraform points each project's Auth at its Worker, email confirmation off until the project has SMTP | A fresh project emails only its organization, so nobody else could sign up | risks SS-C, SS-G |
| 5 | supabase → web, enforced on a push to `main`, advisory on a pull request; the wiring documents are `optionalSecretEnv` | One convergence provisions then deploys per environment; stage must not wait on prod's document | IMPLEMENTATION-STATUS (SS4), risk SS-H |
| 6 | The tutorial's `notes` table under row-level security keyed on `auth.uid()` | Upstream created it open and then suggested a public-read policy | risk SS-J |
| 7 | One landing (`01-product`) then the record (`02-docs`) | A landing has a fixed cost; the plan, not the phases, carries deploy order (cirrus-baseline since baseline-v22) | `repo-blueprint.yaml`, IMPLEMENTATION-STATUS (SS4) |
| 8 | The origin is baked in at build (`NEXT_PUBLIC_SITE_URL`), and `SITE_URL` is the one setting for the app's links and Auth's Site URL | The pages are prerendered; upstream's `VERCEL_URL` gave `localhost:3000` image links on Cloudflare | IMPLEMENTATION-STATUS (SS5), risk SS-L |
| 9 | `ci.yml` plans nothing while `intent.yaml` names `ws_CHANGE_ME` (its `linked` step), not an `ORUN_CI` repository variable | A bootstrap cannot set a repository variable | IMPLEMENTATION-STATUS (SS4), `.github/workflows/ci.yml` |
| 10 | stack-tectonic 0.19.0, not 0.20.0 | 0.20.0's lane-scoped install is refused by Turbopack | IMPLEMENTATION-STATUS (SS4) |
| 11 | orun is pinned only where it runs (the `orun-action` `version:` in each workflow); no kiox | `kiox.yaml` pinned a version nothing ran | IMPLEMENTATION-STATUS (SS6) |
| 12 | Component docs are generated from the manifests and checked in CI | A hand-written copy of the dependency graph, bindings and published outputs drifts silently | `tooling/catalog/gen-component-docs.py` |
| 13 | The console card reads `subdomain` from the Cloudflare connection (`from: connection.cloudflare.workersSubdomain`); only a hand-run build passes it | It belongs to the account like its id and has one right answer; a typed one could only be wrong, and wrong showed up after deploy (cirrus-baseline since baseline-v23) | `blueprint.yaml`, IMPLEMENTATION-STATUS (SS-8) |
| 14 | The console asks for no domain; an empty `productdomain` brands the placeholder `<reponame>.example.com` | The app goes live on workers.dev and nothing in the build needs a domain (the origin is `SITE_URL`, else workers.dev); attaching one is an owner's step, and the placeholder keeps the place the domain goes in the repository, ready to replace | `repo-blueprint.yaml`, `tooling/rebrand/rebrand.mjs`, IMPLEMENTATION-STATUS (SS-9) |
