import { connection } from "next/server";

// Not upstream's: the deploy's smoke check and the bootstrap's probe read
// this. A home page that renders proves the Worker deployed; this proves what
// the home page never touches — the Supabase URL and publishable key this
// Worker was built with name a real project, and its Auth answers them. It
// also says how sign-up behaves there: open or closed, and whether a new user
// must confirm an email address first (the project's own Auth settings).
//
// Supabase's /auth/v1/settings is what supabase-js reads too: public data,
// answered only for a valid API key.
type Health = {
  ok: boolean;
  auth: string;
  signup?: "open" | "closed";
  emailConfirmation?: "required" | "off";
};

function answer(body: Health) {
  return Response.json(body, {
    status: body.ok ? 200 : 503,
    headers: { "cache-control": "no-store" },
  });
}

export async function GET() {
  await connection();
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) {
    return answer({ ok: false, auth: "not configured" });
  }
  try {
    const res = await fetch(`${url}/auth/v1/settings`, {
      headers: { apikey: key },
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) {
      return answer({
        ok: false,
        auth: res.status === 401 ? "key refused" : `answered ${res.status}`,
      });
    }
    const settings = (await res.json()) as {
      disable_signup?: boolean;
      mailer_autoconfirm?: boolean;
    };
    return answer({
      ok: true,
      auth: "reachable",
      signup: settings.disable_signup ? "closed" : "open",
      emailConfirmation: settings.mailer_autoconfirm ? "off" : "required",
    });
  } catch (error) {
    console.error("health: Supabase Auth did not answer", error);
    return answer({ ok: false, auth: "unreachable" });
  }
}
