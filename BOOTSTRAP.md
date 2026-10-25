# BOOTSTRAP — a new product from this baseline, in one landing

How to go from **nothing** to **a Next.js + Supabase Auth app live on stage
and prod — its own Supabase project per environment, Auth pointed at the
app, sign-up open — documented**, with two provider consents.

There is one artifact: **`repo-blueprint.yaml`**. It declares what to place,
in what order, what each phase needs first, and what to say while it runs.
`orun new` is the whole runtime — the phases below are its `--phase` names,
not separate workflows. The console card the platform renders is
**`blueprint.yaml`**; it names the build document and states the inputs, the
brokered secrets and the programme, and `testing/manifest.test.sh` holds it
to what the build document does.

Target wall-clock: **about thirteen minutes** — an estimate summed from the
phases (12 + 1) until a bootstrap measures it. The shape: the task set-up in
the background while ONE landing is placed, branded and checked in the box
(`orun validate` and `orun plan`, no runner waited for), then one convergence
per environment (stage and prod side by side until `02-docs` restores the
promotion gate) that creates the Supabase project (five to seven minutes),
sets its Auth, and builds and deploys the app, in that order, then a short
docs landing.

## 0. What you need

- GitHub org access (repository creation) and a machine with `git`, `node`
  (≥ 22), `pnpm` (10.12.1), `python3` with PyYAML, `curl`, and the `orun`
  CLI **≥ v2.88.0** — the floor for RUNNING the bootstrap (the phase overlay,
  `githubOwner` on the doctor probe, `environments` on the secrets probe,
  `from: workspace`, a landing's `label`, the deploy credentials minted in
  one `secrets` reconcile per provider, the task set-up run in the
  background (`background: true`), and landings checked in the box before
  they merge (`checks: local`)). The product's own `ci.yml` pins its
  lanes separately (v2.78.4), and that pin — or anything newer, as the floor
  is — is what reads the per-edge `mode` rules the convergence order relies
  on.
- A **Cloudflare** account (the free plan is enough for one Worker with
  static assets) and its Account API token with the permission groups the
  console's Connect recipe lists — Workers Scripts among them.
- **A Supabase organization with room for two more projects** —
  `<reponame>-stage` and `<reponame>-prod`. Supabase's free plan allows two
  active projects per organization, so on the free plan that is the whole
  allowance: pause or delete what else is there first, or use a paid
  organization. It is connected to the workspace by OAuth consent (console →
  Integrations → Supabase) — or by a pasted personal access token. The
  connection is anchored on ONE organization, and that is where both
  projects are created.
- An Orun Cloud workspace for the product — `orunWorkspace`, or the workspace
  the build runs in (ORUN_WORKSPACE) when that is unset — with an
  **admin-role API key** for headless runs (secret writes below admin are
  masked as `not_found`).
- **The repository allow-listed in the workspace** (console → Settings → Git
  repos), unless the credential can write links. `01-product`'s `link` step
  stops and names the fix if it is not.
- **Not an SMTP server.** Each project is created with email confirmation
  off, so sign-up works on the first deploy without one; the owner adds SMTP
  and turns confirmation on later (§3).

## 1. One command: `--resume`

The whole bootstrap, unattended. `--resume` places every phase not already
derived as done, in order, honouring each phase's barrier:

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/supabase-starter
cd supabase-starter

orun new --blueprint repo-blueprint.yaml \
  --out ~/products/acme-notes --run-hooks --resume \
  --set reponame=acme-notes --set productname="Acme Notes" \
  --set githuborg=acme-inc \
  --set orunWorkspace=ws_XXXXXXXX \
  --set subdomain=<workers-dev-subdomain>
```

`subdomain` is the workers.dev subdomain of the Cloudflare account you deploy
into (Workers & Pages → your subdomain). A build started from the console, or
with `orun baseline new --from bst_…`, never asks for it: the platform reads
it from the workspace's Cloudflare connection, the same one the deploy tokens
mint from. Only a hand-run build like this one passes it.

**`--run-hooks` is the difference between placing files and bootstrapping a
product.** Without it `orun new` writes the tree and stops: no repository, no
landing, no convergence watch, no probe. That is deliberate — it is what
makes the offline bootstrap in `testing/` possible with no workspace and no
provider.

`--resume` is safe to re-run from anywhere, a fresh container with a fresh
`--out` included: **phase state is derived from the tree, never stored.** A
phase whose files are present but branded derives as `drifted`, and
`--resume` leaves it placed rather than reverting the product's identity.

## 1b. Or phase by phase

| phase | what it lands | verified by |
|---|---|---|
| `01-product` | the repository, created and linked; the four brokered credentials; then the whole product in one PR — intent, CI, tooling, identity, the Supabase Terraform root, the app and its tests | its commit validated and planned in the box (as the PR and as the merge), then merged; the convergence green (supabase → web, per environment — the app's deploy resolving the `WIRING_SUPABASE` the apply before it published); the project's three database credentials, which nothing in the convergence reads, on stage and prod; `/` and `/api/health` answering on both workers.dev URLs |
| `02-docs` | `ai/context/deployment.md` from probed facts (how sign-up behaves included); prod's promotion gate and dev's push lanes restored | the render's own probes, recorded; the commit checked in the box and merged |

```bash
orun new --blueprint repo-blueprint.yaml --out ~/products/acme-notes --run-hooks \
  --phase 01-product --values ~/acme-notes.values.yaml
# … then 02-docs
```

`02-docs` reads the identity back from `.rebrand/values.json` in the placed
tree, but the blueprint's **required** inputs — `reponame`, `productname`,
`githuborg` — are validated before anything runs, so pass them every time (a
`--values` file is easier). The domain is not one of them: the app goes live
on workers.dev, and `productdomain` defaults to empty, which brands the
reserved placeholder `<reponame>.example.com` into `BASE_DOMAIN` for an owner
to replace when they attach a domain (README, "Custom domain"). Pass
`--set productdomain=` only for a product that already has its domain.
The full guide, one page per phase: [docs/phases/README.md](docs/phases/README.md).

| flag | what it does |
|---|---|
| `--status` | derives and prints every phase's state and writes nothing. It parses the document, validates each hook against the action registry and compiles every template; it needs no credential and no network |
| `--phase <name>` | places exactly that phase; its `requires.phases` still gates |
| `--until <name>` | places every phase through that one and stops |

What lands in the product is PRODUCT-ONLY: the app, the Terraform root, the
tests, its CI, its tooling, its README and its two context pages. None of
this repository's machinery (`.baseline/`, the blueprints, `tooling/rebrand`,
`tooling/bootstrap`, `hooks/`, `testing/`, `docs/phases/`, `specs/`,
`tasks/`, this file) ships, and no shipped file names any of it. That
promise is a test: `testing/leak.test.sh` derives what every phase would
place and gates the set and every file's text, and
`testing/placement.test.sh` gates the same rules over a placed, branded tree.

## 2. Headless / container mode

The blueprint's source is this repository (`sources: [{kind: dir, path: .}]`),
so the container contract is a shallow clone at a pinned tag plus two
tokens:

```bash
export ORUN_TOKEN=…          # orun auth, headless
export GITHUB_TOKEN=…        # fine-grained PAT (below)

git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/supabase-starter
cd supabase-starter
orun new --blueprint repo-blueprint.yaml \
  --out /work/acme-notes --run-hooks --resume --progress json \
  --values /work/acme-notes.values.yaml
```

| requirement | detail |
|---|---|
| `GITHUB_TOKEN` | fine-grained PAT: **read** on this repository; on the PRODUCT's repository **contents write**, **pull-requests write**, **actions read+write** (`orun.run/watch@v1` resumes runs with `gh run rerun`), **checks read**; **repository create** on the owner if `01-product` creates it (or pre-create it — supported) |
| classic token caveat | a classic PAT or gh OAuth token also needs the `workflow` scope to push `.github/workflows/` |
| pinning | the clone's `--branch <tag>` pins everything: the blueprint, its modules and its hooks' scripts all come from that one commit |

## 3. After the product is live

- **Sign-up works** on both environments: confirmation is off, so a new user
  is signed in the moment they sign up. Password recovery sends email —
  until a project has an SMTP server of its own, Supabase delivers only to
  its organization's members, and the form says so for anyone else.
- **Email confirmation** (per environment, optional): give the project SMTP
  of its own (Supabase dashboard → Authentication → Emails → SMTP Settings),
  set `authEmailConfirmation: "true"` in the product's
  `infra/terraform/supabase/component.yaml` and merge. The product's README,
  "Email", is the owner's copy of this, including the confirmation template
  that lands on the app's `/auth/confirm`.
- **Tables**: the protected page's tutorial creates `notes` with row-level
  security on and per-user policies. Every table in `public` needs RLS —
  the publishable key is public by design.
- **Custom domain**: attach it to the Worker in Cloudflare, then set
  `SITE_URL` under the environment's `env:` in the product's `intent.yaml` —
  the app's absolute links and the project's Auth Site URL both follow it —
  and redeploy web and supabase (the product's README, "Custom domain").
  There is no domain phase: attaching a domain needs zone permissions the
  brokered `workers-deploy` token does not carry.
- **Refresh the record**: re-run `--phase 02-docs`; it is idempotent, and it
  records whether sign-up asks for confirmation.

## 4. Testing this baseline

`.github/workflows/baseline.yml` runs three tiers on every pull request, and
each runs locally the same way:

```bash
for t in manifest phases coverage rebrand retouch bootstrap-defer; do bash testing/$t.test.sh; done
bash testing/leak.test.sh        # needs orun
bash testing/placement.test.sh   # needs orun, node, pnpm: the offline bootstrap and the product's own plans
bash testing/e2e.test.sh         # + network for pnpm, psql and a PostgreSQL server install
```

The offline bootstrap (`testing/lib/bootstrap.sh`) places both phases in
order and finishes each with the blueprint's OWN `run:` hooks — read out of
`repo-blueprint.yaml`, not transcribed — so the retouch marker, the rebrand,
the re-tenant, the deferrals and their restore and the deployment record
all run exactly as a real bootstrap runs them. Only the
platform's typed actions (task, repo, reconcile, land, watch, secrets,
probe) and the `link` step are stood in for, a landing becoming a commit.

What no test here can do is the clouds' half: create a Supabase project, read
its API keys, set its Auth, mint a token, deploy for real. The Terraform root
is held to `fmt`, `init -backend=false` and `validate` (a real `plan` reads
Supabase's API and the platform's state backend); the convergence ORDER is
proven on the product's own `orun plan`; and the app's Supabase is a local
stand-in — a Postgres with Supabase's roles and `auth` schema, and the Auth,
Data API and SQL-editor endpoints the app and its tutorial call
(`testing/lib/fake-supabase-api.py`) — against which the built Worker serves
a sign-up, a sign-in, the protected page and the email-confirmation route,
and the tutorial's table is checked closed to every other user.

## 5. Cutting a baseline tag (maintainers)

Every product built from this repository resolves a `baseline-vN` tag, so the
tag is cut by a workflow rather than by hand:

```bash
gh workflow run tag.yml -f version=baseline-v1          # from main
gh workflow run tag.yml -f version=baseline-v1 -f ref=<sha>
```

It refuses a version that is not `baseline-v<N>` and a tag that already
exists: a baseline tag is never moved. Then add (or move) the registry row in
orun-cloud's `infra/baselines-registry/baselines.yaml` by pull request —
after the tag exists, because the registry's sync fetches `blueprint.yaml`
at the tag and refuses the whole catalogue if it 404s.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `01-product` parks: `waiting for github for <org>` | the workspace's GitHub connection is to another account. Connect the App installation on `<org>` (console → Integrations → GitHub), then `--resume` |
| `01-product` parks on the `providers` probe for cloudflare or supabase | that connection is missing. Connect it (console → Integrations); the probe is a wait, not a failure |
| `01-product` stops at `link` | the repository is not linked to the workspace and the credential cannot link it. Allow-list it (console → Settings → Git repos) and re-run the phase |
| Secret WRITE fails `not_found` while listings work | the API key's role is below admin; re-mint it with the admin role |
| supabase apply: project limit reached | the organization has no room for the two projects stage and prod need (the free plan allows two active projects per organization). Pause or delete one, or upgrade, then re-run `01-product` |
| supabase apply: `does not support oauth access` | a supabase provider ≥ 1.6 reads billing endpoints the brokered OAuth token cannot; the root pins `~> 1.5.1` — keep it |
| supabase apply: `Unable to read API keys` / `Unable to update auth settings` | the Supabase connection's grant does not cover the project's API keys or its Auth configuration (not yet exercised live with the platform's OAuth app). Reconnect Supabase with a personal access token and re-run `01-product`; the reconcile re-mints only what is missing |
| web: `wire: missing wiring documents … WIRING_SUPABASE_<ENV>` | the supabase apply for that environment did not publish; its lane's log says why. web waits on it, enforced — and this is the check that the wiring is there: nothing awaits it separately |
| `land` stops: `the landing's own check failed — orun plan for …` | the product's tree does not plan — the line after it is orun's own error (an unknown component type, a composition that does not resolve). Nothing was pushed. Fix the tree (or the baseline) and re-run the phase |
| `land` waits on CI after all | the product's repository requires a status check on `main` (branch protection or a ruleset), so GitHub refused the early merge; the landing waits for the check as a `checks: ci` landing would, then merges |
| web smoke: `/api/health` 503 | `auth: key refused` — the inlined key is not the project's; `auth: unreachable` — the project is paused or still coming up |
| `build-app` fails: `Symlink apps/web/node_modules/next is invalid, it points out of the filesystem root` | the product's intent pins stack-tectonic ≥ 0.20.0, whose lane-scoped install links each job's node_modules out of its tree, which Next 16's Turbopack refuses. Pin 0.19.0 (`intent.yaml` says why) |
| `verify-app-structure` fails: `test -f "wrangler.jsonc"` | the product's `apps/web/wrangler.jsonc` is not committed. It must be — the check runs before the build in a fresh checkout (`pnpm run wire:fixture` renders it) |
| Sign-up says the address cannot be mailed | confirmation was turned on without SMTP: Supabase's own email reaches only the organization's members. Add SMTP, or set `authEmailConfirmation` back to `"false"` |
| Convergence failed AFTER the PR merged; re-running lands nothing | expected on its own — the files are on main. Re-run the phase (`--phase 01-product`, `--redo 01-product`, or the console's Retry): its `retouch` hook gives the landing a diff and the components re-plan; the project is adopted, not recreated |
| The convergence reported green, then `verify` got 404 | a second workflow ran on the push to main and the watch took its run. Only `ci.yml` may run on a push to main |
| The product's `intent.yaml` says `workspace: ws_SET_ME` | `orunWorkspace` was empty and the build ran outside a workspace; set it and re-run `01-product` |
| A bootstrap stopped before `02-docs`; prod no longer waits on stage | the gate is deferred, not dropped: run `02-docs`, or `node tooling/bootstrap/promotion.mjs --restore --file <product>/intent.yaml` |
| `✕ input "productname" is required` | all three required inputs (`reponame`, `productname`, `githuborg`) must be set on every invocation, single-phase ones included |
| `unknown flag: --phase`, `has no parameter "checks"`, `has no parameter "secrets"` or another parse error in the blueprint | the CLI is below the v2.88.0 floor |
