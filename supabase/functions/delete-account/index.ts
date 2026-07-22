// Supabase Edge Function: delete-account
// 1) Revokes Sign in with Apple tokens (Apple /auth/revoke) when available
// 2) Deletes public.players for the user and related session history
// 3) Deletes the Supabase auth user
//
// Required secrets: APPLE_CLIENT_ID, APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY
// Optional body: { authorizationCode?: string } — fresh SIWA code to exchange+revoke if no stored refresh token
//
// Deploy:
//   supabase functions deploy delete-account --project-ref <ref>

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const APPLE_CLIENT_ID = Deno.env.get("APPLE_CLIENT_ID") ?? "";
const APPLE_TEAM_ID = Deno.env.get("APPLE_TEAM_ID") ?? "";
const APPLE_KEY_ID = Deno.env.get("APPLE_KEY_ID") ?? "";
const APPLE_PRIVATE_KEY = (Deno.env.get("APPLE_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

async function makeAppleClientSecret(): Promise<string> {
  const pemContents = APPLE_PRIVATE_KEY
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

async function revokeAppleToken(token: string, hint: "refresh_token" | "access_token", clientSecret: string) {
  const res = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: APPLE_CLIENT_ID,
      client_secret: clientSecret,
      token,
      token_type_hint: hint,
    }),
  });
  return res.ok || res.status === 200;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    const userClient = createClient(
      SUPABASE_URL,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }
    const user = userData.user;
    const uid = user.id;

    const body = await req.json().catch(() => ({})) as { authorizationCode?: string };
    const meta = user.user_metadata ?? {};
    let refreshToken = typeof meta.apple_refresh_token === "string" ? meta.apple_refresh_token : null;
    let accessToken = typeof meta.apple_access_token === "string" ? meta.apple_access_token : null;

    const appleConfigured = !!(APPLE_CLIENT_ID && APPLE_TEAM_ID && APPLE_KEY_ID && APPLE_PRIVATE_KEY);
    let appleRevoked = false;

    if (appleConfigured) {
      const clientSecret = await makeAppleClientSecret();

      // Prefer a fresh authorization code from the client (most reliable at delete time).
      const code = body.authorizationCode?.trim();
      if (code) {
        const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: APPLE_CLIENT_ID,
            client_secret: clientSecret,
            code,
            grant_type: "authorization_code",
          }),
        });
        const tokenJson = await tokenRes.json();
        if (tokenRes.ok) {
          refreshToken = tokenJson.refresh_token ?? refreshToken;
          accessToken = tokenJson.access_token ?? accessToken;
        } else {
          console.error("Apple code exchange at delete failed", tokenJson);
        }
      }

      if (refreshToken) {
        appleRevoked = await revokeAppleToken(refreshToken, "refresh_token", clientSecret);
        console.log("Apple refresh_token revoke ok=", appleRevoked);
      }
      if (accessToken) {
        const accessOk = await revokeAppleToken(accessToken, "access_token", clientSecret);
        appleRevoked = appleRevoked || accessOk;
        console.log("Apple access_token revoke ok=", accessOk);
      }
    } else {
      console.warn("Apple secrets not configured — skipping token revocation");
    }

    // Delete training history + players for this account
    const { data: players } = await admin.from("players").select("id").eq("user_id", uid);
    const playerIds = (players ?? []).map((p: { id: string }) => p.id);
    if (playerIds.length > 0) {
      await admin.from("sessions").delete().in("player_id", playerIds);
      await admin.from("session_summary").delete().in("player_id", playerIds);
      await admin.from("players").delete().eq("user_id", uid);
    } else {
      await admin.from("players").delete().eq("user_id", uid);
    }

    try {
      await admin.from("events").delete().eq("user_id", uid);
    } catch (_) {
      // table/column may not exist
    }

    const { error: deleteUserError } = await admin.auth.admin.deleteUser(uid);
    if (deleteUserError) {
      console.error("admin.deleteUser failed", deleteUserError);
      return new Response(JSON.stringify({ error: "Failed to delete auth user", details: deleteUserError.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        ok: true,
        appleRevoked,
        appleConfigured,
        playersDeleted: playerIds.length,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("delete-account error", e);
    return new Response(JSON.stringify({ error: "Server error" }), { status: 500 });
  }
});
