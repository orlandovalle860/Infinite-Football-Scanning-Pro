-- Run once in Supabase SQL Editor (Dashboard → SQL).
-- Enables in-app account deletion from the iOS app via rpc('delete_user').
-- Pattern matches supabase-swift AuthClientIntegrationTests.testDeleteAccountAndSignOut.

CREATE OR REPLACE FUNCTION public.delete_user()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  DELETE FROM auth.users WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.delete_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_user() TO authenticated;
