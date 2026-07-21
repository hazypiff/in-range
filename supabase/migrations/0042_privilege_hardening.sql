-- 0042_privilege_hardening.sql
--
-- Two least-privilege fixes surfaced by the 2026-07-21 regression audit.
-- Neither is exploitable for data exfiltration; both are defense-in-depth /
-- information-leak closures. No behavior change for legitimate callers.

BEGIN;

-- 1. has_consent / require_consent were SECURITY DEFINER (RLS-bypassing) and
--    GRANTed to `authenticated` with an arbitrary p_uid, so any signed-in user
--    could probe another user's consent state
--    (has_consent('<someone-else>','sensitive_profile')). A minor cross-user
--    information leak.
--
--    App users never need these directly -- the client reads its own state via
--    my_consents() (auth.uid()-scoped). They are only called (a) by service_role
--    tooling and (b) internally by the SECURITY DEFINER hot-path RPCs, which run
--    as the function owner and so keep EXECUTE regardless of this revoke. So
--    the consent gates in 0040 are unaffected.
REVOKE EXECUTE ON FUNCTION public.has_consent(UUID, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.require_consent(UUID, TEXT) FROM authenticated;

-- 2. The self-service RPCs granted EXECUTE to `authenticated` but never revoked
--    the default PUBLIC grant, so `anon` retained EXECUTE. Not exploitable --
--    each guards on auth.uid() and errors/no-ops for anon -- but inconsistent
--    with the stricter functions (export_my_data etc.) that revoke explicitly.
REVOKE EXECUTE ON FUNCTION public.request_account_deletion()     FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.grant_consent(TEXT,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.withdraw_consent(TEXT)         FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.my_consents()                 FROM PUBLIC, anon;

COMMIT;
