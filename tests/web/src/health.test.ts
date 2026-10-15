import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// /api/health is what the deploy's smoke and the bootstrap's probes read: 200
// only when the Supabase project this Worker was built for answers its key,
// and it says how sign-up behaves there.
const fetchMock = vi.fn();
// `connection()` (which keeps the route out of the build's prerender) needs a
// request scope that only Next provides; here it is a no-op.
vi.mock("next/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("next/server")>()),
  connection: async () => {},
}));

beforeEach(() => {
  vi.resetModules();
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://ref.supabase.co");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test");
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

async function health() {
  const { GET } = await import("@/app/api/health/route");
  const res = await GET();
  return { status: res.status, body: await res.json(), cache: res.headers.get("cache-control") };
}

describe("GET /api/health (app/api/health/route.ts)", () => {
  it("is ok when Auth answers the key, and reports how sign-up behaves", async () => {
    fetchMock.mockResolvedValue(
      Response.json({ disable_signup: false, mailer_autoconfirm: true, external: { email: true } }),
    );
    expect(await health()).toEqual({
      status: 200,
      body: { ok: true, auth: "reachable", signup: "open", emailConfirmation: "off" },
      cache: "no-store",
    });
    const [url, init] = fetchMock.mock.calls[0] ?? [];
    expect(url).toBe("https://ref.supabase.co/auth/v1/settings");
    expect(init?.headers).toEqual({ apikey: "sb_publishable_test" });
  });

  it("says when new users must confirm their email first", async () => {
    fetchMock.mockResolvedValue(Response.json({ disable_signup: true, mailer_autoconfirm: false }));
    const { body } = await health();
    expect(body).toMatchObject({ ok: true, signup: "closed", emailConfirmation: "required" });
  });

  it("is 503 when the key is refused", async () => {
    fetchMock.mockResolvedValue(new Response('{"message":"Invalid API key"}', { status: 401 }));
    expect(await health()).toMatchObject({ status: 503, body: { ok: false, auth: "key refused" } });
  });

  it("is 503 when Supabase does not answer", async () => {
    fetchMock.mockRejectedValue(new TypeError("fetch failed"));
    vi.spyOn(console, "error").mockImplementation(() => {});
    expect(await health()).toMatchObject({ status: 503, body: { ok: false, auth: "unreachable" } });
  });

  it("is 503, without calling anything, when the build named no project", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
    expect(await health()).toMatchObject({ status: 503, body: { ok: false, auth: "not configured" } });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
