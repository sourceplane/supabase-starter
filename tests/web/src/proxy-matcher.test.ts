import { describe, expect, it } from "vitest";
import { unstable_doesMiddlewareMatch } from "next/experimental/testing/server";
import { config } from "@/proxy";

// Which requests the session proxy (proxy.ts) runs for. It sends a
// signed-out visitor of anything but `/` and `/auth/*` to the login page, so
// a path it matches is a path a probe without a session cannot reach.
describe("proxy.ts matcher", () => {
  it("guards the pages", () => {
    for (const url of ["/", "/protected", "/auth/login", "/no-such-page", "/api/other"]) {
      expect(unstable_doesMiddlewareMatch({ config, url }), url).toBe(true);
    }
  });

  it("leaves /api/health to the deploy's smoke and the uptime probe", () => {
    expect(unstable_doesMiddlewareMatch({ config, url: "/api/health" })).toBe(false);
    expect(unstable_doesMiddlewareMatch({ config, url: "/api/healthz" })).toBe(true);
  });

  it("leaves static files alone, as upstream did", () => {
    for (const url of ["/_next/static/chunks/a.js", "/favicon.ico", "/logo.png"]) {
      expect(unstable_doesMiddlewareMatch({ config, url }), url).toBe(false);
    }
  });
});
