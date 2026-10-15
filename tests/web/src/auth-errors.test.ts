import { describe, expect, it } from "vitest";
import { AuthApiError, AuthRetryableFetchError } from "@supabase/supabase-js";
import { authErrorMessage } from "@/lib/supabase/errors";

// What the auth forms say when Supabase refuses. A fresh project emails only
// its organization's members and only a few times an hour; without these the
// form showed Supabase's terse text, which reads like a bug in the app.
describe("authErrorMessage (lib/supabase/errors.ts)", () => {
  it("explains a project that cannot email the address yet", () => {
    const error = new AuthApiError("Email address not authorized", 400, "email_address_not_authorized");
    expect(authErrorMessage(error)).toMatch(/SMTP server of its own/);
  });

  it("explains the built-in email's rate limit", () => {
    const error = new AuthApiError("email rate limit exceeded", 429, "over_email_send_rate_limit");
    expect(authErrorMessage(error)).toMatch(/as many emails as Supabase allows/);
  });

  it("says the service did not answer, rather than 'Failed to fetch'", () => {
    expect(authErrorMessage(new AuthRetryableFetchError("Failed to fetch", 0))).toBe(
      "The sign-in service did not answer. Try again in a moment.",
    );
  });

  it("passes every other error through as Supabase worded it", () => {
    const error = new AuthApiError("Invalid login credentials", 400, "invalid_credentials");
    expect(authErrorMessage(error)).toBe("Invalid login credentials");
    expect(authErrorMessage(new Error("boom"))).toBe("boom");
    expect(authErrorMessage("??")).toBe("An error occurred");
  });
});
