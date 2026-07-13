-- Calibration walks #2/#3 (2026-07-13): S9-class hardware cannot separate
-- 10/20/30 ft by RSSI. Product tiers are now 10 ft (median RSSI gate),
-- 30 ft (heard on medium-power advert slots), 60 ft (presence).
-- feet_20 stays in the enum for old rows; new clients no longer send it.
--
-- The range-map functions that reference 'feet_60' live in 0021 — Postgres
-- forbids using a new enum value in the transaction that adds it.
ALTER TYPE public.range_type ADD VALUE IF NOT EXISTS 'feet_60';
