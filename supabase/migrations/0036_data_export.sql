-- 0036_data_export.sql
--
-- Right of access / data portability: export_my_data().
--
-- WHY: every privacy regime we could plausibly fall under grants a right of
-- access, and most also require a portable machine-readable format. The app
-- had a deletion path (0035) but no export path at all, so an access request
-- could only have been served by hand out of the database.
--
-- SCOPE RULE: this returns the caller's own data. Where a record is inherently
-- shared -- an encounter, a match, a conversation -- the counterpart appears
-- only as an opaque user id, never as profile details. Two reasons:
--   1. The counterpart's profile is their personal data, not the caller's, and
--      an access request is not a licence to bulk-extract it.
--   2. An export endpoint that dumped counterpart profiles would be a far more
--      attractive target than the app's own screens.
-- Message bodies ARE included for conversations the caller took part in: they
-- were already disclosed to the caller in-app, so this discloses nothing new.

BEGIN;

CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_out JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'export_format', 'in_range.export.v1',
    'generated_at', NOW(),
    'user_id', v_uid,

    -- Everything we hold on the profile itself.
    'profile', (
      SELECT to_jsonb(p) - 'id'
        FROM public.profiles p WHERE p.id = v_uid
    ),

    'account', (
      SELECT jsonb_build_object(
               'email', u.email,
               'created_at', u.created_at,
               'last_sign_in_at', u.last_sign_in_at)
        FROM auth.users u WHERE u.id = v_uid
    ),

    -- Proximity records. Counterpart stays an opaque id by design.
    'encounters', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'encounter_id', e.id,
               'counterpart_user_id', CASE WHEN e.user_a = v_uid THEN e.user_b ELSE e.user_a END,
               'encounter_time', e.encounter_time,
               'neighborhood', e.neighborhood,
               'range_type', e.range_type,
               'confidence', e.confidence,
               'trust_level', e.trust_level,
               'status', e.status,
               'session_count', e.session_count,
               'distinct_day_count', e.distinct_day_count,
               'first_seen_at', e.first_seen_at,
               'last_seen_at', e.last_seen_at)
             ORDER BY e.encounter_time DESC)
        FROM public.encounters e
       WHERE e.user_a = v_uid OR e.user_b = v_uid
    ), '[]'::jsonb),

    'encounter_actions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'encounter_id', a.encounter_id, 'action', a.action, 'acted_at', a.acted_at)
             ORDER BY a.acted_at DESC)
        FROM public.encounter_actions a WHERE a.user_id = v_uid
    ), '[]'::jsonb),

    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'match_id', m.id,
               'counterpart_user_id', CASE WHEN m.user_a = v_uid THEN m.user_b ELSE m.user_a END,
               'matched_at', m.matched_at, 'status', m.status,
               'expires_at', m.expires_at, 'ended_at', m.ended_at)
             ORDER BY m.matched_at DESC)
        FROM public.matches m WHERE m.user_a = v_uid OR m.user_b = v_uid
    ), '[]'::jsonb),

    -- Conversations the caller participated in. Bodies included (already
    -- visible to them in-app); sender marked as self/counterpart.
    'messages', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'match_id', msg.match_id,
               'sent_by_me', (msg.sender_id = v_uid),
               'content', msg.content,
               'message_type', msg.message_type,
               'created_at', msg.created_at,
               'read_at', msg.read_at)
             ORDER BY msg.created_at)
        FROM public.messages msg
        JOIN public.matches mt ON mt.id = msg.match_id
       WHERE mt.user_a = v_uid OR mt.user_b = v_uid
    ), '[]'::jsonb),

    -- Precise location. Purged after 24h, so this is normally near-empty --
    -- which is itself a useful thing for a requester to be able to see.
    'location_pings', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'latitude', ST_Y(lp.geo::geometry),
               'longitude', ST_X(lp.geo::geometry),
               'range_type', lp.range_type,
               'neighborhood', lp.neighborhood,
               'created_at', lp.created_at)
             ORDER BY lp.created_at DESC)
        FROM public.location_pings lp WHERE lp.user_id = v_uid
    ), '[]'::jsonb),

    'blocks', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'blocked_user_id', b.blocked_id, 'created_at', b.created_at)
             ORDER BY b.created_at DESC)
        FROM public.blocks b WHERE b.blocker_id = v_uid
    ), '[]'::jsonb),

    -- Reports the caller FILED. Reports filed ABOUT them are deliberately
    -- excluded: disclosing those would expose the reporter and defeat the
    -- safety mechanism.
    'reports_filed', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'reason', r.reason, 'details', r.details,
               'status', r.status, 'created_at', r.created_at)
             ORDER BY r.created_at DESC)
        FROM public.reports r WHERE r.reporter_id = v_uid
    ), '[]'::jsonb),

    -- Billing. raw_receipt is excluded: it is the store's payload, contains
    -- no data the user gave us, and can carry provider-side identifiers.
    'subscriptions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'tier', s.tier, 'status', s.status, 'provider', s.provider,
               'product_id', s.product_id, 'starts_at', s.starts_at,
               'expires_at', s.expires_at, 'canceled_at', s.canceled_at)
             ORDER BY s.created_at DESC)
        FROM public.subscriptions s WHERE s.user_id = v_uid
    ), '[]'::jsonb),

    'boosts', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'product_id', bo.product_id, 'provider', bo.provider,
               'starts_at', bo.starts_at, 'ends_at', bo.ends_at)
             ORDER BY bo.created_at DESC)
        FROM public.boosts bo WHERE bo.user_id = v_uid
    ), '[]'::jsonb),

    -- Registered push destinations, by platform only -- the token itself is a
    -- device credential, not user-facing data.
    'push_devices', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'platform', d.platform, 'created_at', d.created_at))
        FROM public.device_push_tokens d WHERE d.user_id = v_uid
    ), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END;
$$;

COMMENT ON FUNCTION public.export_my_data IS
  'Right-of-access export of the calling user''s own data. Counterparts appear only as opaque user ids; reports filed about the caller are excluded to protect reporters.';

REVOKE ALL ON FUNCTION public.export_my_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;

COMMIT;
