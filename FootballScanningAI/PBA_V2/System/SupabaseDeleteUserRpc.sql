-- Run in Supabase SQL Editor (Dashboard → SQL).
-- In-app account deletion via rpc('delete_user').
-- Deletes the caller's players, related training history, then the auth user.
-- Apple Sign in with Apple token revocation is handled separately by the
-- `delete-account` Edge Function (see supabase/functions/delete-account).

CREATE OR REPLACE FUNCTION public.delete_user()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Training history keyed by this account's players (sessions cascade to
  -- session_activities / decisions / session_summary where FKs exist).
  DELETE FROM public.sessions
  WHERE player_id IN (
    SELECT id FROM public.players WHERE user_id = uid
  );

  DELETE FROM public.session_summary
  WHERE player_id IN (
    SELECT id FROM public.players WHERE user_id = uid
  );

  -- Player profiles for this account
  DELETE FROM public.players WHERE user_id = uid;

  -- Analytics / events tied to the auth user (if present)
  BEGIN
    DELETE FROM public.events WHERE user_id = uid;
  EXCEPTION
    WHEN undefined_table THEN NULL;
    WHEN undefined_column THEN NULL;
  END;

  DELETE FROM auth.users WHERE id = uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_user() TO authenticated;
