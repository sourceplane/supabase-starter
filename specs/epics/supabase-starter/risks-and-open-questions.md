# supabase-starter — risks and open questions

## SS-A — `cacheComponents` on OpenNext (RISK, mitigated)

The template enables Next 16's `cacheComponents`. OpenNext Cloudflare 1.20
builds it, but the pre-rendered shells it produces are served from the
static-assets incremental cache, which is read-only; nothing in this
template revalidates, so that is enough. If a later Next or OpenNext breaks
the combination, dropping `cacheComponents` is a one-line change the
template tolerates (it was added for tutorial purposes).

## SS-B — Where the publishable key lives (RESOLVED)

A wrangler `var`, rendered from the wiring document, not a Worker secret.
The key is shipped to every browser by design; Row Level Security is the
boundary. The service-role key is published as an orun secret for server
use but this template never reads it.

## SS-C — Auth emails redirect to the right host (ACCEPTED, documented)

Supabase sends confirmation and recovery links to the project's `Site URL`
and allow-listed redirect URLs. Terraform's `supabase_project` does not set
them; they are set once per environment in the Supabase dashboard (or with
`supabase_settings` in a follow-up). The README names the values.

## SS-D — Node ≥ 25 stub `localStorage` at prerender (SETTLED)

Same as blog-starter: `next-themes` guards correctly, and nothing in this
template reads `localStorage` at prerender. CI builds on Node 22.

## SS-E — The verify lane needs values it cannot have (RESOLVED)

`next build` inlines `NEXT_PUBLIC_*`. The verify lane (and `Checks`) has
no Supabase project; the template already handles missing values
(`hasEnvVars` renders the "environment variables required" banner and
`updateSession` passes through), so an unset build is a valid build of
the un-configured starter — exactly what Vercel's one-click deploy shows
before the integration is connected.
