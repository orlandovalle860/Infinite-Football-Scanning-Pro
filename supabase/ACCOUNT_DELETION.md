# Account deletion (Sign in with Apple)

VisionPlay account deletion must:

1. Delete the Supabase auth user  
2. Delete `public.players` for that user  
3. Delete related session / training-history rows  
4. Revoke Sign in with Apple tokens via Apple’s `/auth/revoke` API (TN3194)

## Deploy

### 1. Update SQL RPC (players + history + auth user)

Run `FootballScanningAI/PBA_V2/System/SupabaseDeleteUserRpc.sql` in the Supabase SQL Editor.

### 2. Deploy Edge Functions (Apple revoke)

```bash
supabase functions deploy store-apple-token --project-ref <ref>
supabase functions deploy delete-account --project-ref <ref>

supabase secrets set \
  APPLE_CLIENT_ID=com.infinitefootball.scanningpro \
  APPLE_TEAM_ID=<your_team_id> \
  APPLE_KEY_ID=<siwa_key_id> \
  APPLE_PRIVATE_KEY="$(cat AuthKey_XXXXX.p8 | sed 's/$/\\n/' | tr -d '\n')"
```

`APPLE_PRIVATE_KEY` is the Sign in with Apple `.p8` key from Apple Developer → Keys.

### 3. App behavior

- On Sign in with Apple, the app sends the authorization code to `store-apple-token` (best-effort) to persist `apple_refresh_token` on user metadata.
- On Delete Account, the app calls `delete-account` (revoke + delete players/history + auth user), then falls back to `rpc('delete_user')` if the function is unavailable.
