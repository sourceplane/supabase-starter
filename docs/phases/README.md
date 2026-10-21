# The phases — one blueprint, two selections, one landing that deploys

`repo-blueprint.yaml` declares two phases that take a product from
**nothing** to **live on stage and prod, documented**. Run them one at a time
with `--phase <name>`, or both unattended with `--resume`. There is no
umbrella workflow and no per-phase document: a phase is a selection on one
artifact, which is what makes running one alone, months later, from a fresh
container the same operation as running them all.

Each phase follows the same contract:

> **place its modules → brand them → land them as one pull request → watch
> the convergence that merge triggers (auto-resumed) → verify the outcome.**

Run from the baseline checkout (the blueprint's source is `path: .`); the
product's repository is wherever `--out` points.

## Execution order

| phase | lands | verified by |
|---|---|---|
| [`01-product`](01-product.md) | **the GitHub repo created**, then the WHOLE product in one PR: intent, CI, tooling, the Supabase Terraform root, the app and its tests — one convergence provisions and deploys it in dependency order | convergence green; `WIRING_SUPABASE` and the project's three database credentials published on stage and prod; `/` and `/api/health` answer on both |
| [`02-docs`](02-docs.md) | the live-deployment record; the promotion gate and dev's lanes put back | committed manifest matches probed reality |

**One landing builds the product.** The order the app needs — the Supabase
project before the app that talks to it — is not a sequence of landings. It
is the app component's own `dependsOn`, `mode: enforced` on a push to `main`
and advisory on a pull request:

```
supabase ──▶ web        (per environment)
```

A job resolves its secrets when it starts, so the app's deploy reads the
wiring document the apply published: the project's URL and publishable key,
rendered into the Worker's vars and inlined into the browser bundle.
`testing/placement.test.sh` reads that order off the product's own
`orun plan --trigger github-push-main`.

Every landing is a pull request on a branch named for its task
(`orun/BASE-<n>-<phase>`). On those branches `ci.yml` runs `plan` only — the
intent, every component and every composition resolve — and skips the lanes,
because the merge runs them on main a minute later, for real, and that
convergence is what the phase watches. `checks.yml` (install, typecheck,
lint, test, build) runs on every pull request regardless.

There is no custom-domain phase: the app answers on workers.dev. Attaching a
domain needs zone permissions the brokered `workers-deploy` token does not
carry, so it is an owner's step after the bootstrap (the product's README,
"Custom domain").

## Inputs

`01-product` takes the product's identity once and writes it into the repo
(`.rebrand/values.json`); `02-docs` reads it back from the placed tree. But
the blueprint's **required** inputs — `reponame`, `productname`,
`productdomain`, `githuborg` — are validated before any phase runs, so they
must be supplied on every invocation, single-phase ones included. A
`--values` file is easier than repeating `--set`.

- `subdomain` — the workers.dev subdomain of the Cloudflare account you
  deploy into. It is in every URL the phases probe, and it is the origin the
  Supabase project's Auth sends its links to. A console or `--from bst_…`
  build reads it from the Cloudflare connection; pass it only for a hand-run
  build.
- `orunWorkspace` — workspace id (`ws_…`). Unset, it is the workspace the
  build runs in (`from: workspace`); with none anywhere, a placeholder that
  fails loudly rather than silently claiming another tenant's workspace.
- `epicSlug` (default `supabase-auth-baselining`) — the epic every phase
  clubs its task under. Found by slug, so a fresh run and a resumed run find
  the same work.
- `repoPrivate` (default `true`) — the repository's visibility at creation.

```bash
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/products/acme-notes --run-hooks --phase 01-product \
  --values ~/acme-notes.values.yaml
```

Drop `--run-hooks` (or add `--status`) to preview. Without it a phase places
files and stops: no repo, no landing, no convergence watch, and no probe —
which is exactly what makes a dry instantiation of this baseline possible in
CI with no workspace and no provider (`testing/placement.test.sh`,
`testing/e2e.test.sh`).

## Email is not a phase

A fresh Supabase project emails only its organization's own members, so the
bootstrap creates each project with email confirmation off — sign-up signs a
user straight in, for anyone, from the first deploy — and asks for no SMTP
server. The owner turns confirmation on once a project has SMTP of its own
(the product's README, "Email"), and re-running `02-docs` records it.

## When a phase fails

- **Before it lands** (a probe that timed out, a rebrand residue, a refused
  link): nothing was merged. Fix what the message names and re-run the phase.
- **After it lands** (the convergence went red): the files are on main.
  `orun.run/watch@v1` has already resumed the run up to three times. Re-run
  the phase (`--phase 01-product`, `--redo 01-product` under `--resume`, or
  the console's Retry): its `retouch` hook gives the landing a diff and the
  components it names re-plan. The Supabase project is adopted rather than
  recreated (`adopt.tf`).
