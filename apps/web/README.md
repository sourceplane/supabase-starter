# apps/web — the app

Vercel's [Next.js and Supabase Starter](https://github.com/vercel/next.js/tree/canary/examples/with-supabase)
(MIT), running on Cloudflare Workers + Static Assets:

- Supabase Auth with the session in cookies (`@supabase/ssr`), usable from
  Server Components, Client Components, Route Handlers and the proxy
- Sign-up, login, forgot and update password (`/auth/*`), an email-confirm
  route handler (`/auth/confirm`) and a protected page (`/protected`) that
  prints the signed-in user's claims
- A proxy (`proxy.ts`) that refreshes the session on every request and sends
  a signed-out visitor of anything but `/` and `/auth/*` to the login page
- A tutorial: sign up a first user, then create a table — with row-level
  security keyed on `auth.uid()` — and query it from Next.js
- `/api/health`, which answers 200 only when the Supabase project the build
  names answers its key, and says how sign-up behaves there
- Tailwind CSS and shadcn/ui

The product's name is `lib/site.ts`. The project's URL and publishable key
reach the browser bundle and the Worker from one place, `wrangler.jsonc`'s
vars (`next.config.ts`); what the auth forms say when Supabase refuses is
`lib/supabase/errors.ts`.

```bash
pnpm dev          # next dev on http://localhost:3000 (reads .env.local)
pnpm build        # next build + opennextjs-cloudflare build → .open-next/
pnpm preview      # wrangler dev over the built Worker (reads .dev.vars)
```

How it runs locally, how it deploys — per environment, after its Supabase
project, on merge to `main` — and how to turn email confirmation on are the
repository's README and `component.yaml` beside this file.
