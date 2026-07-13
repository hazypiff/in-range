-- feet_60 branches for the correlation range maps (enum value added in 0020).
-- Without these, feet_60 fell to the miles ELSE arms (1609 m / 90 min,
-- clamped to 100 m / 30 min by record_sighting) — 5x the radius the feet
-- tiers are designed around.
CREATE OR REPLACE FUNCTION public.range_radius_meters(p_range public.range_type)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_range
    WHEN 'feet_10'   THEN 5.0
    WHEN 'feet_20'   THEN 8.0
    WHEN 'feet_30'   THEN 12.0
    WHEN 'feet_60'   THEN 25.0
    WHEN 'miles_1'   THEN 1609.0
    WHEN 'miles_5'   THEN 8047.0
    WHEN 'miles_10'  THEN 16093.0
    WHEN 'miles_25'  THEN 40234.0
    WHEN 'miles_50'  THEN 80467.0
    WHEN 'miles_100' THEN 160934.0
    WHEN 'miles_200' THEN 321869.0
    ELSE 1609.0
  END;
$$;

CREATE OR REPLACE FUNCTION public.range_time_window_minutes(p_range public.range_type)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_range
    WHEN 'feet_10'   THEN 15
    WHEN 'feet_20'   THEN 20
    WHEN 'feet_30'   THEN 30
    WHEN 'feet_60'   THEN 30
    WHEN 'miles_1'   THEN 90
    WHEN 'miles_5'   THEN 120
    WHEN 'miles_10'  THEN 180
    WHEN 'miles_25'  THEN 240
    WHEN 'miles_50'  THEN 360
    WHEN 'miles_100' THEN 720
    WHEN 'miles_200' THEN 1440
    ELSE 90
  END;
$$;
