# supabase-starter — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/supabase-starter/risks-and-open-questions.md`; this page lists
only what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| SS-I | Unproven against a real organization: no Terraform apply, live deploy or live bootstrap yet — so whether the brokered Supabase token reaches the API-keys and Auth-config endpoints, whether a new project still returns a legacy anon key, and the wall-clock are all unknown | OPEN | One bootstrap from a tag against a workspace with a Supabase connection |
| SS-A | `cacheComponents` on OpenNext: the prerendered shells are served from the read-only static-assets cache; a later Next or OpenNext could break the combination | WATCH (mitigated) | Holds while nothing revalidates; dropping `cacheComponents` is the one-line fallback |

Settled: SS-K (the bootstrap floor, once orun v2.58.11, planned `modeRules`
as enforced; it is v2.88.0 now, newer than the product's lane pin, and reads
them as the pin does), SS-D (Node ≥ 25 `localStorage` stub; CI builds on
Node 22).
