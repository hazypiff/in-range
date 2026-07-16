-- #6 step 4: relay-abuse response surface + explicit ops policy.
--
-- Migration 0032 records useful telemetry, but two operational pieces were
-- still missing:
--
--   1. The 15-minute cron scans a 30-minute lookback. A five-minute, reason-only
--      de-dupe can record the same underlying incident on two successive runs.
--      Stable evidence fingerprints make the counts represent incidents rather
--      than cron executions while preserving separate incidents in one window.
--   2. Ops needs a service-role-only queue/digest with a conservative response
--      policy. relay_geo identifies the owner of a relayed token (normally a
--      victim), so it must never trigger an automatic user restriction. Repeated
--      claim_teleport incidents escalate to review / step-up verification, but
--      telemetry alone still does not auto-punish an account.

ALTER TABLE public.beacon_abuse_flags
  ADD COLUMN IF NOT EXISTS evidence_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_beacon_abuse_flags_evidence
  ON public.beacon_abuse_flags (user_id, reason, evidence_key)
  WHERE evidence_key IS NOT NULL;

COMMENT ON COLUMN public.beacon_abuse_flags.evidence_key IS
  'Stable SHA-256 fingerprint of scanner evidence; prevents overlap from duplicating one incident.';

-- Internal writer. Known scanner reasons include stable token evidence in
-- p_detail, so the same incident remains de-duplicated across overlapping cron
-- runs. The JSONB text fallback is deterministic for future reasons.
CREATE OR REPLACE FUNCTION public.note_abuse_flag(
  p_user UUID,
  p_reason TEXT,
  p_detail JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_evidence_key TEXT;
  v_inserted INT;
BEGIN
  IF p_user IS NULL OR NULLIF(trim(p_reason), '') IS NULL THEN
    RETURN FALSE;
  END IF;

  v_evidence_key := encode(
    sha256(convert_to(
      p_reason || ':' ||
        CASE p_reason
          WHEN 'claim_teleport' THEN concat_ws(
            ':',
            COALESCE(p_detail->>'previous_token', ''),
            COALESCE(p_detail->>'token', '')
          )
          WHEN 'relay_geo' THEN COALESCE(p_detail->>'token', '')
          ELSE COALESCE(p_detail, '{}'::jsonb)::TEXT
        END,
      'UTF8'
    )),
    'hex'
  );

  INSERT INTO public.beacon_abuse_flags
    (user_id, reason, detail, evidence_key)
  VALUES
    (p_user, p_reason, p_detail, v_evidence_key)
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted = 1;
END;
$$;
REVOKE ALL ON FUNCTION public.note_abuse_flag(UUID, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;

-- Replace the scanner so claim_teleport includes both endpoint tokens in its
-- evidence fingerprint. relay_geo already includes the claimed token.
CREATE OR REPLACE FUNCTION public.scan_relay_abuse(
  p_since INTERVAL DEFAULT INTERVAL '1 hour'
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_count INT := 0;
  r RECORD;
  c_max_mps CONSTANT DOUBLE PRECISION := 300.0;
  c_min_meters CONSTANT DOUBLE PRECISION := 2000.0;
BEGIN
  -- 1) claim_teleport: consecutive claims by one user that imply impossible
  -- speed. The token pair uniquely identifies this piece of evidence.
  FOR r IN
    WITH c AS (
      SELECT
        user_id,
        token,
        valid_from,
        approx_lat,
        approx_lon,
        LAG(token)      OVER w AS previous_token,
        LAG(valid_from) OVER w AS prev_from,
        LAG(approx_lat) OVER w AS prev_lat,
        LAG(approx_lon) OVER w AS prev_lon
      FROM public.token_claim_history
      WHERE valid_from > NOW() - p_since
        AND approx_lat IS NOT NULL
        AND approx_lon IS NOT NULL
      WINDOW w AS (PARTITION BY user_id ORDER BY valid_from, token)
    )
    SELECT
      user_id,
      token,
      previous_token,
      ST_Distance(
        ST_SetSRID(ST_MakePoint(prev_lon, prev_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(approx_lon, approx_lat), 4326)::geography
      ) AS meters,
      EXTRACT(EPOCH FROM (valid_from - prev_from)) AS secs
    FROM c
    WHERE prev_from IS NOT NULL
      AND prev_lat IS NOT NULL
      AND prev_lon IS NOT NULL
  LOOP
    IF r.secs > 1
       AND r.meters > c_min_meters
       AND (r.meters / r.secs) > c_max_mps THEN
      IF public.note_abuse_flag(
        r.user_id,
        'claim_teleport',
        jsonb_build_object(
          'previous_token', r.previous_token,
          'token', r.token,
          'meters', round(r.meters),
          'seconds', round(r.secs),
          'mps', round(r.meters / r.secs)
        )
      ) THEN
        v_count := v_count + 1;
      END IF;
    END IF;
  END LOOP;

  -- 2) relay_geo: a token observed implausibly far from its owner's claim.
  FOR r IN
    SELECT
      h.user_id,
      h.token,
      max(ST_Distance(
        ST_SetSRID(ST_MakePoint(h.approx_lon, h.approx_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(s.observer_lon, s.observer_lat), 4326)::geography
      )) AS max_m,
      count(DISTINCT s.observer_user_id) AS observers
    FROM public.token_claim_history h
    JOIN public.sightings s ON s.observed_token = h.token
    WHERE h.valid_from > NOW() - p_since
      AND h.approx_lat IS NOT NULL
      AND h.approx_lon IS NOT NULL
      AND s.observer_lat IS NOT NULL
      AND s.observer_lon IS NOT NULL
    GROUP BY h.user_id, h.token
  LOOP
    IF r.max_m > c_min_meters THEN
      IF public.note_abuse_flag(
        r.user_id,
        'relay_geo',
        jsonb_build_object(
          'token', r.token,
          'max_meters', round(r.max_m),
          'observers', r.observers
        )
      ) THEN
        v_count := v_count + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.scan_relay_abuse(INTERVAL)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.scan_relay_abuse(INTERVAL) TO service_role;

-- Per-account, per-reason admin queue. Thresholds are intentionally advisory:
--   claim_teleport: 1 monitor, 2 review, 3+ step-up + manual review.
--   relay_geo:      1-2 monitor, 3+ investigate the relay pattern; never
--                   restrict the flagged token owner on this signal alone.
CREATE OR REPLACE VIEW public.v_beacon_abuse_triage_24h
WITH (security_invoker = true, security_barrier = true)
AS
WITH grouped AS (
  SELECT
    user_id,
    reason,
    count(*)::INT AS incident_count,
    min(created_at) AS first_flag_at,
    max(created_at) AS latest_flag_at,
    (array_agg(detail ORDER BY created_at DESC, id DESC))[1] AS latest_detail
  FROM public.beacon_abuse_flags
  WHERE created_at > NOW() - INTERVAL '24 hours'
  GROUP BY user_id, reason
)
SELECT
  user_id,
  reason,
  incident_count,
  first_flag_at,
  latest_flag_at,
  latest_detail,
  CASE
    WHEN reason = 'claim_teleport' AND incident_count >= 3 THEN 1
    WHEN reason = 'claim_teleport' AND incident_count >= 2 THEN 2
    WHEN reason = 'relay_geo' AND incident_count >= 3 THEN 2
    WHEN reason NOT IN ('claim_teleport', 'relay_geo') THEN 2
    ELSE 3
  END AS attention_rank,
  CASE
    WHEN reason = 'claim_teleport' AND incident_count >= 3 THEN 'high'
    WHEN reason = 'claim_teleport' AND incident_count >= 2 THEN 'review'
    WHEN reason = 'relay_geo' AND incident_count >= 3 THEN 'investigate'
    WHEN reason NOT IN ('claim_teleport', 'relay_geo') THEN 'review'
    ELSE 'monitor'
  END AS priority,
  CASE
    WHEN reason = 'claim_teleport' AND incident_count >= 3
      THEN 'step_up_verification_and_manual_review'
    WHEN reason = 'claim_teleport' AND incident_count >= 2
      THEN 'manual_review'
    WHEN reason = 'claim_teleport'
      THEN 'monitor'
    WHEN reason = 'relay_geo' AND incident_count >= 3
      THEN 'investigate_relay_pattern_no_user_restriction'
    WHEN reason = 'relay_geo'
      THEN 'telemetry_only_no_user_restriction'
    ELSE 'manual_review'
  END AS recommended_response,
  FALSE AS automatic_restriction
FROM grouped;

COMMENT ON VIEW public.v_beacon_abuse_triage_24h IS
  'Service-role relay-abuse queue. Policy is advisory; relay_geo never restricts the flagged user.';

CREATE OR REPLACE VIEW public.v_beacon_abuse_digest_24h
WITH (security_invoker = true, security_barrier = true)
AS
SELECT
  reason,
  sum(incident_count)::BIGINT AS incident_count,
  count(*)::INT AS affected_users,
  max(latest_flag_at) AS latest_flag_at,
  min(attention_rank) AS highest_attention_rank
FROM public.v_beacon_abuse_triage_24h
GROUP BY reason;

COMMENT ON VIEW public.v_beacon_abuse_digest_24h IS
  'Service-role 24-hour relay-abuse digest, sourced from distinct scanner evidence.';

-- Views use invoker security, so service_role needs the base-table grant too.
GRANT SELECT ON TABLE public.beacon_abuse_flags TO service_role;
REVOKE ALL ON TABLE
  public.v_beacon_abuse_triage_24h,
  public.v_beacon_abuse_digest_24h
FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE
  public.v_beacon_abuse_triage_24h,
  public.v_beacon_abuse_digest_24h
TO service_role;
