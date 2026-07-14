-- GPS is a coarse plausibility VETO, never a proximity signal.
--
-- Research (docs/research/gps-fused-location.md):
--   * Android's reported location accuracy is a 68%-CONFIDENCE radius, so
--     roughly 1 fix in 3 has true error LARGER than the circle it claims.
--   * Indoors, median reported accuracy is 29-48 m on current flagships
--     (Galaxy S22 41.7 m, S24 28.8 m, Pixel 10 47.9 m) versus <5 m outdoors.
--
-- Our feet-tier correlation gate was clamped to 50-100 m. Two people standing
-- together inside a bar can each legitimately report a 40 m accuracy circle,
-- so a fixed 100 m gate SILENTLY REJECTS GENUINE ENCOUNTERS — precisely the
-- venue where this app is supposed to work.
--
-- Fix: widen the gate with the uncertainty the phones actually reported.
--   radius = clamp( 2 * (acc_a + acc_b), 100 m, 400 m )
-- The factor 2 converts each 68% circle toward ~95%. A generous veto still
-- blocks cross-city replay/relay, which is the only thing the veto is FOR.
-- Tight geometry is BLE's job, and BLE is the only radio that can do it.

ALTER TABLE public.token_claims
  ADD COLUMN IF NOT EXISTS accuracy_m DOUBLE PRECISION;

ALTER TABLE public.sightings
  ADD COLUMN IF NOT EXISTS observer_accuracy_m DOUBLE PRECISION;

CREATE OR REPLACE FUNCTION public.gps_veto_radius_meters(
  p_acc_a DOUBLE PRECISION,
  p_acc_b DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
AS $$
  -- Unknown accuracy on either side => fall back to the widest sane veto
  -- rather than inventing precision we do not have.
  SELECT LEAST(400.0, GREATEST(100.0,
    2.0 * (COALESCE(p_acc_a, 100.0) + COALESCE(p_acc_b, 100.0))
  ));
$$;

COMMENT ON FUNCTION public.gps_veto_radius_meters IS
  'Accuracy-aware plausibility radius. GPS may only VETO implausible pairs; '
  'it may never assert proximity (consumer GPS ~10 m at best, 29-48 m indoors).';
