# supabase-starter (SS) — Implementation status

As-built ≠ intent. This file records what actually shipped, and every place
the code departed from `design.md` or from the upstream template.

| Milestone | State | PR |
|---|---|---|
| SS0 — the spec | ✅ Shipped | [#1](https://github.com/sourceplane/supabase-starter/pull/1) |
| SS1 — the starter on Workers | ✅ Shipped | [#2](https://github.com/sourceplane/supabase-starter/pull/2) |
| SS2 — the Supabase project from Terraform | ✅ Shipped (validated; apply gated on a linked workspace) | [#3](https://github.com/sourceplane/supabase-starter/pull/3) |
| SS3 — ready to instantiate | ✅ Shipped | [#4](https://github.com/sourceplane/supabase-starter/pull/4) |

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
