-- =============================================================================
-- Migration 0010: Realtime tables, grants, encounter insert notifications, cron
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 1. Realtime for encounters + outbox drain optional
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'encounters'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.encounters;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'encounter_actions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.encounter_actions;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Notify on new encounter insert (BLE correlate path)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_new_encounter()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Avoid duplicate if miles path already queued
  IF NOT EXISTS (
    SELECT 1 FROM public.notification_outbox o
    WHERE o.kind = 'new_encounter'
      AND o.payload->>'encounter_id' = NEW.id::text
      AND o.created_at > NOW() - INTERVAL '1 hour'
  ) THEN
    INSERT INTO public.notification_outbox (user_id, kind, title, body, payload)
    VALUES
      (
        NEW.user_a,
        'new_encounter',
        'New encounter',
        'You crossed paths near ' || COALESCE(NEW.neighborhood, 'you'),
        jsonb_build_object(
          'encounter_id', NEW.id,
          'other_user_id', NEW.user_b,
          'range_type', NEW.range_type
        )
      ),
      (
        NEW.user_b,
        'new_encounter',
        'New encounter',
        'You crossed paths near ' || COALESCE(NEW.neighborhood, 'you'),
        jsonb_build_object(
          'encounter_id', NEW.id,
          'other_user_id', NEW.user_a,
          'range_type', NEW.range_type
        )
      );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS encounters_notify_insert ON public.encounters;
CREATE TRIGGER encounters_notify_insert
  AFTER INSERT ON public.encounters
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_new_encounter();

-- ----------------------------------------------------------------------------
-- 3. Scheduled maintenance (pg_cron if available)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_maintenance()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired INT;
  v_alerts INT;
BEGIN
  PERFORM public.cleanup_ephemeral_data();
  v_expired := public.expire_feet_encounters();
  v_alerts := public.queue_expiring_encounter_alerts();
  PERFORM public.batch_correlate_recent_pings(45);
  RETURN jsonb_build_object(
    'expired_feet', v_expired,
    'expiring_alerts', v_alerts,
    'ran_at', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.run_maintenance TO service_role;

-- Uncomment when pg_cron extension is enabled in the project:
-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule('in-range-maintenance', '*/15 * * * *', $$ SELECT public.run_maintenance(); $$);

-- ----------------------------------------------------------------------------
-- 4. Grant execute on core RPCs (idempotent)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'claim_token',
        'record_sighting',
        'correlate_encounter',
        'get_my_encounters',
        'nearby_location_pings',
        'record_location_ping',
        'get_locals_feed',
        'swipe_encounter',
        'get_my_matches',
        'send_message',
        'upsert_my_profile',
        'register_push_token'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 5. Messages update policy (read receipts)
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users update messages in their matches" ON public.messages;
CREATE POLICY "Users update messages in their matches"
  ON public.messages FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id = messages.match_id
        AND (m.user_a = auth.uid() OR m.user_b = auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id = messages.match_id
        AND (m.user_a = auth.uid() OR m.user_b = auth.uid())
    )
  );

-- ----------------------------------------------------------------------------
-- 6. Encounter actions insert policy (swipe_encounter is DEFINER; keep client path)
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users manage own actions" ON public.encounter_actions;
CREATE POLICY "Users manage own actions"
  ON public.encounter_actions FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 7. Matches insert via service/definer only — still allow select
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users see their matches" ON public.matches;
CREATE POLICY "Users see their matches"
  ON public.matches FOR SELECT
  TO authenticated
  USING (user_a = auth.uid() OR user_b = auth.uid());

-- ----------------------------------------------------------------------------
-- 8. Helpful views for ops (service role)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_pending_photo_reviews AS
SELECT
  pv.*,
  p.display_name,
  p.email_hint
FROM public.photo_verifications pv
JOIN public.profiles p ON p.id = pv.user_id
WHERE pv.state IN ('manual_review', 'ai_review')
ORDER BY pv.submitted_at ASC;

COMMENT ON VIEW public.v_pending_photo_reviews IS
  'Moderation queue — query with service_role.';

COMMENT ON FUNCTION public.run_maintenance IS
  'Cleanup + expire feet + expiring alerts + batch miles. Call from Edge cron every 15m.';
