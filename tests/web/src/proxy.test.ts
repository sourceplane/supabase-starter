import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

// The session proxy (`lib/supabase/proxy.ts`) is the template's one piece of
// server logic that decides something: it refreshes the Supabase session
// cookie and sends signed-out visitors of any page but `/`, `/login*` and
// `/auth*` to the login form.

const getClaims = vi.fn();
vi.mock("@supabase/ssr", () => ({
  createServerClient: () => ({ auth: { getClaims } }),
}));

function request(pathname: string) {
  return new NextRequest(new URL(pathname, "https://app.example.com"));
}

describe("updateSession (lib/supabase/proxy.ts)", () => {
  beforeEach(() => {
    vi.resetModules();
    getClaims.mockReset();
    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://ref.supabase.co";
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = "sb_publishable_test";
  });

  it("redirects a signed-out visitor of a protected page to /auth/login", async () => {
    getClaims.mockResolvedValue({ data: { claims: null } });
    const { updateSession } = await import("@/lib/supabase/proxy");
    const res = await updateSession(request("/protected"));
    expect(res.status).toBe(307);
    expect(new URL(res.headers.get("location")!).pathname).toBe("/auth/login");
  });

  it("lets a signed-out visitor see the home page and the auth pages", async () => {
    getClaims.mockResolvedValue({ data: { claims: null } });
    const { updateSession } = await import("@/lib/supabase/proxy");
    for (const p of ["/", "/auth/login", "/auth/sign-up", "/login"]) {
      const res = await updateSession(request(p));
      expect(res.status, p).toBe(200);
    }
  });

  it("lets a signed-in user through", async () => {
    getClaims.mockResolvedValue({ data: { claims: { sub: "user-1" } } });
    const { updateSession } = await import("@/lib/supabase/proxy");
    const res = await updateSession(request("/protected"));
    expect(res.status).toBe(200);
  });

  it("skips the check entirely when the Supabase env vars are missing", async () => {
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    delete process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    const { updateSession } = await import("@/lib/supabase/proxy");
    const res = await updateSession(request("/protected"));
    expect(res.status).toBe(200);
    expect(getClaims).not.toHaveBeenCalled();
  });
});
