import { isAuthError } from "@supabase/supabase-js";

// Not upstream's. The auth forms showed Supabase's own message for any
// failure, and the ones a freshly provisioned project gives read like a bug in
// the app: its built-in email reaches only the organization's own members, it
// sends a handful of emails an hour, and an unreachable project is a bare
// "Failed to fetch". Those three say what is going on and what fixes it;
// every other error is Supabase's own message, as before.
export function authErrorMessage(error: unknown): string {
  if (isAuthError(error)) {
    switch (error.code) {
      case "email_address_not_authorized":
        return "This project cannot email that address yet: until it has an SMTP server of its own, Supabase delivers its email only to the members of the project's organization.";
      case "over_email_send_rate_limit":
        return "This project has sent as many emails as Supabase allows for now. Try again later — or give the project an SMTP server of its own.";
    }
    if (error.name === "AuthRetryableFetchError" && error.status === 0) {
      return "The sign-in service did not answer. Try again in a moment.";
    }
    return error.message;
  }
  return error instanceof Error ? error.message : "An error occurred";
}
