#!/usr/bin/env node
// The browser's half of the app's auth flow, for the e2e.
//
//   browser-auth.mjs <app-dir> <supabase-url> <anon-key> <action> [args…]
//
//   signup <email> <password> <origin>   what components/sign-up-form.tsx calls
//   signin <email> <password>            what components/login-form.tsx calls
//   recover <email> <origin>             what components/forgot-password-form.tsx calls
//   notes [<email> <password>]           the tutorial's `supabase.from('notes').select()`,
//                                        signed in first when given credentials
//
// The forms are client components: their JavaScript runs in a browser, which
// this suite does not drive. What they call is supabase-js — so this calls
// the same functions, with the same arguments, from the product's OWN
// installed @supabase/ssr (resolved from <app-dir>, the staged job tree), and
// keeps the session the way @supabase/ssr's browser client keeps it: as
// `sb-<ref>-auth-token` cookies, through the same cookie codec. The cookies it
// prints are what a browser would send the Worker on its next request.
//
// Prints one JSON object: { ok, session, user, code, message, cookie, rows }.
import { createRequire } from "node:module";
import * as path from "node:path";

const [appDir, url, key, action, ...args] = process.argv.slice(2);
const require = createRequire(path.join(path.resolve(appDir), "package.json"));
const { createServerClient } = require("@supabase/ssr");

const jar = new Map();
const supabase = createServerClient(url, key, {
  cookies: {
    getAll: () => [...jar].map(([name, value]) => ({ name, value })),
    setAll: (cookies) => {
      for (const { name, value, options } of cookies) {
        if (!value || options?.maxAge === 0) jar.delete(name);
        else jar.set(name, value);
      }
    },
  },
});

function report(result, extra = {}) {
  const error = result?.error ?? null;
  const out = {
    ok: !error,
    session: Boolean(result?.data?.session),
    user: result?.data?.user?.email ?? result?.data?.session?.user?.email ?? null,
    code: error?.code ?? null,
    message: error?.message ?? null,
    cookie: [...jar].map(([n, v]) => `${n}=${v}`).join("; "),
    ...extra,
  };
  process.stdout.write(JSON.stringify(out) + "\n");
}

switch (action) {
  case "signup": {
    const [email, password, origin] = args;
    report(await supabase.auth.signUp({
      email,
      password,
      options: { emailRedirectTo: `${origin}/protected` },
    }));
    break;
  }
  case "signin": {
    const [email, password] = args;
    report(await supabase.auth.signInWithPassword({ email, password }));
    break;
  }
  case "recover": {
    const [email, origin] = args;
    report(await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${origin}/auth/update-password`,
    }));
    break;
  }
  case "notes": {
    const [email, password] = args;
    if (email) {
      const signin = await supabase.auth.signInWithPassword({ email, password });
      if (signin.error) {
        report(signin);
        break;
      }
    }
    const { data, error } = await supabase.from("notes").select();
    report({ error }, { rows: data ?? null });
    break;
  }
  default:
    process.stderr.write(`browser-auth: unknown action ${action}\n`);
    process.exit(2);
}
