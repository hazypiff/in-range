-- Fix PostgREST PGRST203: multiple record_sighting overloads
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'record_sighting'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.record_sighting(
  p_observed_token TEXT,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_rssi INTEGER DEFAULT NULL,
  p_observed_at TIMESTAMPTZ DEFAULT NOW(),
  p_range public.range_type DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_sighting_id BIGINT;
  v_radius DOUBLE PRECISION;
  v_window INT;
  v_range public.range_type;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_range := COALESCE(p_range, 'feet_10');

  INSERT INTO public.sightings (
    observer_user_id, observed_token, rssi, observed_at,
    observer_lat, observer_lon, range_type
  )
  VALUES (
    v_user_id, p_observed_token, p_rssi, p_observed_at,
    COALESCE(p_lat, 0), COALESCE(p_lon, 0), v_range
  )
  RETURNING id INTO v_sighting_id;

  IF p_lat IS NOT NULL AND p_lon IS NOT NULL THEN
    v_radius := public.range_radius_meters(v_range);
    IF v_range::text LIKE 'feet_%' THEN
      v_radius := GREATEST(v_radius, 50.0);
    END IF;
    v_window := public.range_time_window_minutes(v_range);
    PERFORM public.correlate_encounter(
      p_observed_token, p_lat, p_lon, v_radius, v_window
    );
  END IF;

  RETURN v_sighting_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_sighting(
  TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INTEGER, TIMESTAMPTZ, public.range_type
) TO authenticated;
