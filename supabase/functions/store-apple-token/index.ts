// Supabase Edge Function: store-apple-token
// Exchanges a Sign in with Apple authorization code for tokens and stores the
// Apple refresh_token on the authenticated user (user_metadata.apple_refresh_token).
//
// Required secrets:
//   APPLE_CLIENT_ID   — bundle id, e.g. com.infinitefootball.scanningpro
//   APPLE_TEAM_ID     — Apple Developer Team ID
//   APPLE_KEY_ID      — Sign in with Apple key ID
//   APPLE_PRIVATE_KEY — contents of the .p8 key (PEM), newlines as \n
//
// Deploy:
//   supabase functions deploy store-apple-token --project-ref <ref>
//   supabase secrets set APPLE_CLIENT_ID=... APPLE_TEAM_ID=... APPLE_KEY_ID=... APPLE_PRIVATE_KEY=...

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const APPLE_CLIENT_ID = Deno.env.get("APPLE_CLIENT_ID") ?? "";
const APPLE_TEAM_ID = Deno.env.get("APPLE_TEAM_ID") ?? "";
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID") ?? "";
const APPLE_PRIVATE_KEY = (Deno.env.get("APPLE_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

async function makeAppleClientSecret(): Promise<string> {
  const pem = APPLE_PRIVATE_KEY;
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  return await create(
    { alg: "ES256", kid: APPLE_KEY_ID },
    {
      iss: APPLE_TEAM_ID,
      iat: getNumericDate(0),
      exp: getNumericDate(60 * 60 * 24 * 150),
      aud: "https://appleid.apple.com",
      sub: APPLE_CLIENT_ID,
    },
    key,
  );
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    if (!APPLE_CLIENT_ID || !APPLE_TEAM_ID || !APPLE_KEY_ID || !APPLE_PRIVATE_KEY) {
      return new Response(JSON.stringify({ error: "Apple secrets not configured" }), {
        status: 503,
        headers: { "Content-Type": "application/json" },
      });
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    // Verify the caller with their JWT (getUser works with Authorization header alone).
    const userClient = createClient(
      SUPABASE_URL,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }
    const user = userData.user;

    const body = await req.json() as { authorizationCode?: string };
    const authorizationCode = body.authorizationCode?.trim();
    if (!authorizationCode) {
      return new Response(JSON.stringify({ error: "authorizationCode required" }), { status: 400 });
    }

    const clientSecret = await makeAppleClientSecret();
    const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: APPLE_CLIENT_ID,
        client_secret: clientSecret,
        code: authorizationCode,
        grant_type: "authorization_code",
      }),
    });
    const tokenJson = await tokenRes.json();
    if (!tokenRes.ok) {
      console.error("Apple token exchange failed", tokenJson);
      return new Response(JSON.stringify({ error: "Apple token exchange failed", details: tokenJson }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const refreshToken = tokenJson.refresh_token as string | undefined;
    const accessToken = tokenJson.access_token as string | undefined;
    if (!refreshToken && !accessToken) {
      return new Response(JSON.stringify({ error: "No Apple tokens returned" }), { status: 400 });
    }

    // updateUser() requires a full local auth session; Edge Functions only have the JWT header.
    // Persist via service-role admin after verifying the caller above.
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);
    const existingMeta = (user.user_metadata ?? {}) as Record<string, unknown>;
    const { error: updateError } = await admin.auth.admin.updateUserById(user.id, {
      user_metadata: {
        ...existingMeta,
        apple_refresh_token: refreshToken ?? null,
        apple_access_token: accessToken ?? null,
      },
    });
    if (updateError) {
      console.error("Failed to store Apple tokens", updateError);
      return new Response(JSON.stringify({ error: "Failed to store Apple tokens" }), { status: 500 });
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("store-apple-token error", e);
    return new Response(JSON.stringify({ error: "Server error" }), { status: 500 });
  }
});
