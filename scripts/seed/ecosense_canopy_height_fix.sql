-- XR Future Forests Lab — Ecosense baseline: canopy heights replaced by yield-table heights
--
-- OPTIONAL — not part of docker/volumes/db/init/. Applied manually after the ecosense tree
-- import and ecosense_baseline_variant.sql, before the derived-value fills and silva-connector:
--
--   docker exec -i dftdb-db psql -U supabase_admin -d postgres < scripts/seed/ecosense_canopy_height_fix.sql
--
-- What this does
-- ==============
-- A plausibility check of the 2025 inventory (2026-10-26) against every yield table in
-- growpy's store (pylometree store format; band = envelope of mean-stem height for the DBH,
-- x/: 1.3) flagged 396 of the 1,198 measured ecosense heights as far too tall for their
-- DBH (beech 376, silver fir 13, spruce 3, Douglas fir 3, larch 1); none too short. The
-- DBH is right (plot basal area 32-48 m2/ha; DBH x pi would give 315-470). The heights are
-- canopy heights: beech stays at 27-29 m from 5 to 80 cm DBH and stems within 1 m differ by
-- a median 0.24 m, i.e. the TLS height is the canopy surface sampled at each stem. No row is
-- a single obvious typo, decimal slip or radius/diameter mix-up (each has 3-5 competing
-- one-value fixes), so the height is replaced as a whole (owner decision 2026-10-26).
--
-- Per tree (keyed on location + plot + tree number, or on the surveyed position for the four stems the
-- inventory gives no number; tree_id changes on every rebuild):
-- * height_m       := growpy's yield-table height for the stem's DBH (the store fit,
--                     data/assets/allometry), height_source := 'allometric_yield_table'
-- * field_notes    += 'tls_canopy_height_m: <old>' (the value is kept, not lost)
-- * crown_width_m, crown_base_height_m, volume_m3, age_years, biomass_kg,
--   carbon_content_kg and the stems' stem_volume_m3 := NULL — all derived from the old
--   height; refill them afterwards (silva-connector scripts/fill_allometry.R,
--   scripts/import/fill_missing_ages.py, scripts/import/fill_missing_biomass.py), then re-run
--   the silva-connector chains (--replace), which project from this baseline.
--
-- Idempotent: each row is guarded on its current height being the TLS value, so a re-run,
-- or a tree that has changed since, is a no-op.

SET search_path TO shared, trees, extensions, public;

BEGIN;

CREATE TEMP TABLE canopy_fix (plot_name text, tree_number int, h_tls numeric, h_new numeric) ON COMMIT DROP;
INSERT INTO canopy_fix VALUES
    ('ecosense_plot_1', 2, 30.39, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_1', 4, 27.98, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_1', 7, 20.18, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_1', 8, 20.18, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_1', 10, 25.75, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_1', 12, 26.46, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_1', 14, 28.89, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_1', 16, 29.26, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_1', 18, 28.32, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_1', 27, 26.05, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_1', 42, 27.27, 12.10),  -- Fagus sylvatica, DBH 11.62 cm
    ('ecosense_plot_1', 53, 26.71, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_1', 55, 26.25, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_1', 62, 26.13, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_1', 64, 25.98, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_1', 67, 25.98, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_1', 76, 25.22, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_1', 77, 25.22, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_1', 79, 26.15, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_1', 80, 26.67, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_10', 7, 27.04, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_10', 12, 26.89, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_10', 13, 26.89, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_10', 17, 29.74, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_10', 20, 27.15, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_10', 28, 29.40, 12.90),  -- Fagus sylvatica, DBH 12.73 cm
    ('ecosense_plot_10', 43, 27.92, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_10', 44, 28.93, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_10', 49, 27.65, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_10', 54, 27.78, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_10', 56, 29.12, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_10', 61, 28.93, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_10', 63, 29.10, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_10', 64, 28.81, 12.90),  -- Fagus sylvatica, DBH 12.73 cm
    ('ecosense_plot_10', 70, 29.64, 12.90),  -- Fagus sylvatica, DBH 12.73 cm
    ('ecosense_plot_10', 78, 28.38, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_10', 80, 27.75, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_11', 4, 26.01, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_11', 13, 29.86, 12.60),  -- Fagus sylvatica, DBH 12.41 cm
    ('ecosense_plot_11', 23, 29.21, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_11', 27, 28.37, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_11', 31, 27.60, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_11', 38, 27.33, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_11', 45, 26.75, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_11', 46, 25.66, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_11', 63, 26.99, 11.80),  -- Picea abies, DBH 18.46 cm
    ('ecosense_plot_11', 67, 27.89, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_11', 69, 25.97, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_11', 75, 25.59, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_11', 79, 25.69, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_11', 84, 27.45, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_11', 85, 27.71, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_11', 89, 26.44, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_11', 91, 25.12, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_11', 92, 24.46, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_11', 98, 25.12, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_11', 109, 29.21, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_11', 112, 29.08, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_11', 114, 31.26, 13.30),  -- Fagus sylvatica, DBH 13.37 cm
    ('ecosense_plot_11', 115, 29.33, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_11', 116, 28.17, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_11', 117, 28.65, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_11', 121, 28.94, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_11', 123, 28.41, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_11', 127, 27.92, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_11', 129, 27.92, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_11', 131, 26.71, 7.40),  -- Fagus sylvatica, DBH 5.73 cm
    ('ecosense_plot_12', 7, 30.53, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_12', 8, 28.30, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_12', 13, 34.17, 13.00),  -- Abies alba, DBH 14.01 cm
    ('ecosense_plot_12', 29, 33.06, 15.40),  -- Abies alba, DBH 17.51 cm
    ('ecosense_plot_12', 35, 29.48, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_12', 44, 29.54, 12.20),  -- Fagus sylvatica, DBH 11.78 cm
    ('ecosense_plot_12', 51, 28.91, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_12', 61, 28.35, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_12', 64, 27.87, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_12', 67, 27.64, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_12', 68, 27.63, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_12', 70, 28.55, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_12', 72, 29.68, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_12', 75, 32.08, 19.50),  -- Abies alba, DBH 23.87 cm
    ('ecosense_plot_13', 17, 30.25, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_13', 19, 28.82, 11.50),  -- Fagus sylvatica, DBH 10.82 cm
    ('ecosense_plot_13', 20, 28.82, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_13', 21, 29.49, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_13', 22, 29.21, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_13', 24, 28.81, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_13', 26, 28.70, 7.40),  -- Fagus sylvatica, DBH 5.73 cm
    ('ecosense_plot_13', 30, 30.67, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_13', 34, 27.29, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_13', 38, 31.90, 13.90),  -- Abies alba, DBH 15.28 cm
    ('ecosense_plot_13', 41, 26.42, 9.70),  -- Abies alba, DBH 9.55 cm
    ('ecosense_plot_13', 43, 32.58, 10.90),  -- Abies alba, DBH 11.14 cm
    ('ecosense_plot_13', 49, 29.51, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_13', 51, 31.11, 13.80),  -- Fagus sylvatica, DBH 14.01 cm
    ('ecosense_plot_13', 52, 30.56, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_13', 54, 31.27, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_13', 56, 30.66, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_13', 61, 29.95, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_13', 62, 29.95, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_13', 64, 31.69, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_13', 67, 29.08, 12.60),  -- Fagus sylvatica, DBH 12.41 cm
    ('ecosense_plot_13', 70, 28.09, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_13', 71, 28.40, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_13', 73, 28.28, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_13', 75, 31.78, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_13', 82, 28.40, 7.70),  -- Abies alba, DBH 7.00 cm
    ('ecosense_plot_13', 84, 28.91, 13.00),  -- Abies alba, DBH 14.01 cm
    ('ecosense_plot_13', 91, 28.50, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_13', 92, 28.50, 6.80),  -- Fagus sylvatica, DBH 5.09 cm
    ('ecosense_plot_13', 98, 28.52, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_13', 103, 30.71, 12.90),  -- Fagus sylvatica, DBH 12.73 cm
    ('ecosense_plot_13', 107, 28.24, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_13', 109, 27.15, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_13', 118, 29.95, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_14', 8, 29.88, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_14', 11, 30.95, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_14', 12, 30.28, 9.90),  -- Fagus sylvatica, DBH 8.75 cm
    ('ecosense_plot_14', 14, 29.80, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_14', 19, 29.04, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_14', 21, 31.23, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_14', 23, 29.49, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_14', 26, 29.69, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_14', 28, 29.05, 12.20),  -- Fagus sylvatica, DBH 11.78 cm
    ('ecosense_plot_14', 37, 28.30, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_14', 39, 29.38, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_14', 43, 26.85, 10.00),  -- Picea abies, DBH 15.92 cm
    ('ecosense_plot_14', 50, 28.91, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_14', 51, 27.91, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_14', 56, 27.04, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_14', 62, 28.90, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_14', 69, 27.57, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_14', 73, 30.26, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_14', 88, 31.31, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_14', 89, 29.94, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_14', 91, 29.37, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_14', 93, 28.40, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_14', 97, 30.71, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_14', 100, 30.91, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_15', 2, 27.98, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_15', 4, 27.53, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_15', 7, 25.86, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_15', 9, 26.63, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_15', 10, 27.30, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_15', 11, 27.30, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_15', 15, 25.09, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_15', 16, 26.03, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_15', 18, 25.13, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_15', 21, 23.39, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_15', 23, 23.39, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_15', 29, 26.79, 8.10),  -- Picea abies, DBH 13.05 cm
    ('ecosense_plot_15', 35, 29.05, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_15', 37, 27.73, 11.50),  -- Fagus sylvatica, DBH 10.82 cm
    ('ecosense_plot_15', 41, 26.41, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_15', 45, 25.70, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_15', 46, 25.70, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_15', 57, 26.82, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_15', 58, 28.50, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_16', 4, 27.57, 11.10),  -- Fagus sylvatica, DBH 10.35 cm
    ('ecosense_plot_16', 12, 26.92, 9.90),  -- Fagus sylvatica, DBH 8.75 cm
    ('ecosense_plot_16', 13, 27.71, 7.50),  -- Fagus sylvatica, DBH 5.89 cm
    ('ecosense_plot_16', 15, 29.34, 9.70),  -- Fagus sylvatica, DBH 8.44 cm
    ('ecosense_plot_16', 16, 28.88, 11.40),  -- Fagus sylvatica, DBH 10.66 cm
    ('ecosense_plot_16', 17, 27.75, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_16', 27, 27.29, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_16', 39, 30.12, 11.50),  -- Fagus sylvatica, DBH 10.82 cm
    ('ecosense_plot_16', 41, 28.52, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_16', 42, 31.01, 14.00),  -- Fagus sylvatica, DBH 14.32 cm
    ('ecosense_plot_16', 44, 30.40, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_16', 45, 31.55, 13.80),  -- Fagus sylvatica, DBH 14.01 cm
    ('ecosense_plot_16', 46, 31.55, 13.80),  -- Fagus sylvatica, DBH 14.01 cm
    ('ecosense_plot_16', 53, 31.60, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_16', 60, 28.77, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_17', 2, 29.06, 11.50),  -- Fagus sylvatica, DBH 10.82 cm
    ('ecosense_plot_17', 6, 28.06, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_17', 7, 28.06, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_17', 8, 28.84, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_17', 10, 29.26, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_17', 12, 29.10, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_17', 13, 29.32, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_17', 16, 28.44, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_17', 25, 30.48, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_17', 27, 30.87, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_17', 29, 30.61, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_17', 33, 31.67, 14.20),  -- Fagus sylvatica, DBH 14.64 cm
    ('ecosense_plot_17', 34, 29.60, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_17', 39, 29.25, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_17', 40, 29.25, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_17', 42, 30.55, 12.60),  -- Fagus sylvatica, DBH 12.41 cm
    ('ecosense_plot_17', 44, 29.33, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_17', 46, 30.35, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_17', 51, 29.42, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_18', 5, 31.57, 12.90),  -- Fagus sylvatica, DBH 12.73 cm
    ('ecosense_plot_18', 9, 30.31, 10.90),  -- Fagus sylvatica, DBH 10.03 cm
    ('ecosense_plot_18', 10, 29.00, 12.90),  -- Fagus sylvatica, DBH 12.73 cm
    ('ecosense_plot_18', 19, 29.26, 10.60),  -- Fagus sylvatica, DBH 9.71 cm
    ('ecosense_plot_18', 20, 28.93, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_18', 24, 26.92, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_18', 26, 29.42, 9.10),  -- Fagus sylvatica, DBH 7.80 cm
    ('ecosense_plot_18', 27, 29.66, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_18', 31, 30.05, 8.90),  -- Fagus sylvatica, DBH 7.48 cm
    ('ecosense_plot_18', 32, 30.50, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_18', 34, 29.58, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_18', 41, 29.56, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_18', 43, 27.83, 7.80),  -- Fagus sylvatica, DBH 6.21 cm
    ('ecosense_plot_18', 47, 29.22, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_18', 48, 32.60, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_18', 49, 32.60, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_18', 53, 27.03, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_18', 56, 28.27, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_2', 3, 27.90, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_2', 9, 24.76, 7.40),  -- Fagus sylvatica, DBH 5.73 cm
    ('ecosense_plot_2', 11, 25.18, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_2', 14, 26.71, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_2', 16, 25.85, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_2', 21, 22.06, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_2', 22, 26.08, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_2', 24, 23.60, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_2', 26, 27.31, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_2', 28, 27.91, 7.40),  -- Fagus sylvatica, DBH 5.73 cm
    ('ecosense_plot_2', 30, 26.87, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_2', 31, 27.31, 7.40),  -- Fagus sylvatica, DBH 5.73 cm
    ('ecosense_plot_2', 35, 27.80, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_2', 48, 31.63, 15.80),  -- Abies alba, DBH 18.14 cm
    ('ecosense_plot_2', 52, 26.29, 13.00),  -- Pseudotsuga menziesii, DBH 13.05 cm
    ('ecosense_plot_2', 55, 26.02, 18.10),  -- Larix decidua, DBH 18.78 cm
    ('ecosense_plot_2', 59, 27.31, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_3', 1, 26.87, 10.20),  -- Fagus sylvatica, DBH 9.07 cm
    ('ecosense_plot_3', 3, 27.37, 10.60),  -- Fagus sylvatica, DBH 9.71 cm
    ('ecosense_plot_3', 4, 26.33, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_3', 6, 25.90, 9.40),  -- Fagus sylvatica, DBH 8.12 cm
    ('ecosense_plot_3', 8, 27.17, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_3', 9, 24.99, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_3', 15, 24.44, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_3', 23, 20.93, 7.20),  -- Fagus sylvatica, DBH 5.57 cm
    ('ecosense_plot_3', 24, 20.93, 7.40),  -- Fagus sylvatica, DBH 5.73 cm
    ('ecosense_plot_3', 30, 24.16, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_3', 31, 27.39, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_3', 33, 28.58, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_3', 34, 29.22, 11.40),  -- Fagus sylvatica, DBH 10.66 cm
    ('ecosense_plot_3', 36, 29.22, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_3', 37, 26.06, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_3', 39, 26.03, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_3', 45, 27.62, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_3', 49, 28.07, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_3', 54, 28.01, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_3', 55, 28.25, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_3', 57, 28.01, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_3', 64, 26.98, 6.80),  -- Fagus sylvatica, DBH 5.09 cm
    ('ecosense_plot_3', 73, 27.12, 9.40),  -- Fagus sylvatica, DBH 8.12 cm
    ('ecosense_plot_3', 77, 27.62, 11.40),  -- Fagus sylvatica, DBH 10.66 cm
    ('ecosense_plot_3', 79, 27.77, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_3', 105, 19.83, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_4', 1, 28.51, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_4', 6, 32.41, 7.90),  -- Fagus sylvatica, DBH 6.37 cm
    ('ecosense_plot_4', 7, 32.41, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_4', 8, 27.65, 13.00),  -- Pseudotsuga menziesii, DBH 13.05 cm
    ('ecosense_plot_4', 11, 26.62, 11.40),  -- Fagus sylvatica, DBH 10.66 cm
    ('ecosense_plot_4', 17, 25.41, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_4', 21, 25.41, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_4', 23, 21.29, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_4', 26, 30.99, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_4', 27, 34.65, 16.10),  -- Pseudotsuga menziesii, DBH 17.51 cm
    ('ecosense_plot_4', 29, 28.24, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_4', 43, 28.75, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_4', 48, 29.93, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_4', 54, 28.43, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_4', 63, 30.01, 13.00),  -- Fagus sylvatica, DBH 12.89 cm
    ('ecosense_plot_5', 8, 25.60, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_5', 18, 27.13, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_5', 19, 27.16, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_5', 20, 27.51, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_5', 23, 27.50, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_5', 26, 26.99, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_5', 29, 28.00, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_5', 30, 27.86, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_5', 32, 27.58, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_5', 33, 27.86, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_5', 34, 28.17, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_5', 35, 28.17, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_5', 39, 30.68, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_5', 41, 29.70, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_5', 43, 30.14, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_5', 51, 28.43, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_5', 52, 27.93, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_5', 53, 27.75, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_5', 54, 28.18, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_5', 56, 27.78, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_5', 57, 26.04, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_5', 58, 26.30, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_5', 59, 26.30, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_5', 62, 27.41, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_5', 65, 27.18, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_5', 67, 25.73, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_5', 68, 28.31, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_5', 70, 27.35, 12.20),  -- Fagus sylvatica, DBH 11.78 cm
    ('ecosense_plot_6', 5, 27.81, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_6', 6, 27.49, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_6', 8, 26.99, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_6', 9, 27.55, 11.50),  -- Fagus sylvatica, DBH 10.82 cm
    ('ecosense_plot_6', 12, 28.84, 12.90),  -- Fagus sylvatica, DBH 12.73 cm
    ('ecosense_plot_6', 13, 28.50, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_6', 14, 28.11, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_6', 15, 28.11, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_6', 19, 28.01, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_6', 21, 27.65, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_6', 22, 27.29, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_6', 40, 28.38, 12.20),  -- Fagus sylvatica, DBH 11.78 cm
    ('ecosense_plot_6', 44, 29.87, 13.50),  -- Fagus sylvatica, DBH 13.69 cm
    ('ecosense_plot_6', 48, 28.60, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_6', 49, 29.02, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_6', 53, 32.42, 15.20),  -- Fagus sylvatica, DBH 16.23 cm
    ('ecosense_plot_6', 64, 29.09, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_6', 67, 29.24, 10.90),  -- Fagus sylvatica, DBH 10.03 cm
    ('ecosense_plot_6', 68, 27.19, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_6', 69, 26.62, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_6', 70, 26.62, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_6', 71, 27.19, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_6', 74, 28.70, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_6', 77, 28.88, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_6', 89, 29.13, 8.50),  -- Fagus sylvatica, DBH 7.00 cm
    ('ecosense_plot_6', 90, 29.13, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_7', 5, 26.41, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_7', 7, 25.57, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_7', 12, 24.98, 7.70),  -- Fagus sylvatica, DBH 6.05 cm
    ('ecosense_plot_7', 17, 25.32, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_7', 21, 26.67, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_7', 27, 26.81, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_7', 32, 29.00, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_7', 35, 29.80, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_7', 40, 27.86, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_7', 44, 26.52, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_7', 48, 26.32, 7.40),  -- Fagus sylvatica, DBH 5.73 cm
    ('ecosense_plot_7', 51, 27.16, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_7', 52, 27.16, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_7', 56, 27.64, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_7', 63, 29.00, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_7', 65, 27.14, 9.00),  -- Fagus sylvatica, DBH 7.64 cm
    ('ecosense_plot_7', 66, 29.35, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_7', 70, 23.29, 9.30),  -- Fagus sylvatica, DBH 7.96 cm
    ('ecosense_plot_7', 74, 28.65, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    ('ecosense_plot_7', 77, 27.21, 11.50),  -- Fagus sylvatica, DBH 10.82 cm
    ('ecosense_plot_7', 84, 26.54, 11.00),  -- Fagus sylvatica, DBH 10.19 cm
    ('ecosense_plot_7', 86, 27.97, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_7', 90, 28.76, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_7', 94, 28.28, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_7', 95, 28.61, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_7', 104, 28.72, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_7', 108, 28.40, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_8', 5, 26.25, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_8', 19, 24.46, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_8', 21, 25.96, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_8', 31, 25.54, 11.70),  -- Abies alba, DBH 12.10 cm
    ('ecosense_plot_8', 37, 27.16, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_8', 39, 27.20, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_8', 51, 24.84, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_8', 52, 26.05, 8.20),  -- Abies alba, DBH 7.64 cm
    ('ecosense_plot_8', 53, 27.75, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_8', 54, 29.63, 14.80),  -- Abies alba, DBH 16.55 cm
    ('ecosense_plot_8', 65, 28.34, 10.00),  -- Abies alba, DBH 9.87 cm
    ('ecosense_plot_8', 68, 27.05, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_8', 70, 26.37, 11.20),  -- Fagus sylvatica, DBH 10.50 cm
    ('ecosense_plot_8', 71, 27.36, 12.20),  -- Fagus sylvatica, DBH 11.78 cm
    ('ecosense_plot_8', 72, 33.34, 14.60),  -- Fagus sylvatica, DBH 15.28 cm
    ('ecosense_plot_8', 76, 28.40, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_8', 79, 29.23, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_9', 9, 26.81, 11.50),  -- Fagus sylvatica, DBH 10.82 cm
    ('ecosense_plot_9', 11, 29.66, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_9', 17, 28.93, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_9', 20, 27.12, 12.00),  -- Fagus sylvatica, DBH 11.46 cm
    ('ecosense_plot_9', 33, 27.27, 9.50),  -- Fagus sylvatica, DBH 8.28 cm
    ('ecosense_plot_9', 38, 28.79, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_9', 40, 28.12, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_9', 43, 28.13, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_9', 49, 29.93, 10.50),  -- Fagus sylvatica, DBH 9.55 cm
    ('ecosense_plot_9', 51, 30.27, 10.80),  -- Fagus sylvatica, DBH 9.87 cm
    ('ecosense_plot_9', 52, 29.31, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_9', 55, 28.76, 12.20),  -- Fagus sylvatica, DBH 11.78 cm
    ('ecosense_plot_9', 56, 30.25, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_9', 58, 29.21, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_9', 60, 29.15, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_9', 61, 28.68, 9.80),  -- Fagus sylvatica, DBH 8.59 cm
    ('ecosense_plot_9', 64, 29.16, 10.30),  -- Fagus sylvatica, DBH 9.23 cm
    ('ecosense_plot_9', 65, 29.16, 8.20),  -- Fagus sylvatica, DBH 6.68 cm
    ('ecosense_plot_9', 67, 29.34, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    ('ecosense_plot_9', 71, 27.94, 12.20),  -- Fagus sylvatica, DBH 11.78 cm
    ('ecosense_plot_9', 74, 29.81, 10.00),  -- Fagus sylvatica, DBH 8.91 cm
    ('ecosense_plot_9', 78, 29.53, 13.10),  -- Fagus sylvatica, DBH 13.05 cm
    ('ecosense_plot_9', 80, 29.39, 11.70),  -- Fagus sylvatica, DBH 11.14 cm
    ('ecosense_plot_9', 81, 31.31, 14.40),  -- Fagus sylvatica, DBH 14.96 cm
    ('ecosense_plot_9', 84, 29.93, 11.50),  -- Fagus sylvatica, DBH 10.82 cm
    ('ecosense_plot_9', 87, 28.57, 7.90)   -- Fagus sylvatica, DBH 6.37 cm
;

CREATE TEMP TABLE canopy_fix_pos (x numeric, y numeric, h_tls numeric, h_new numeric) ON COMMIT DROP;
INSERT INTO canopy_fix_pos VALUES
    (416738.427, 5346723.247, 31.49, 12.40),  -- Fagus sylvatica, DBH 12.10 cm
    (416773.569, 5346745.980, 26.81, 8.70),  -- Fagus sylvatica, DBH 7.32 cm
    (416774.587, 5346618.186, 30.79, 9.90),  -- Fagus sylvatica, DBH 8.75 cm
    (416752.519, 5346798.797, 31.86, 10.60)   -- Fagus sylvatica, DBH 9.71 cm
;

CREATE TEMP TABLE canopy_hit ON COMMIT DROP AS
SELECT t.tree_id, f.h_tls, f.h_new
FROM canopy_fix f
JOIN shared.Locations l ON l.location_name = 'ecosense'
JOIN shared.Plots p ON p.plot_name = f.plot_name
JOIN shared.Variants v ON v.location_id = l.location_id AND v.variant_name = 'baseline_2025'
JOIN trees.Trees t ON t.location_id = l.location_id AND t.plot_id = p.plot_id
                  AND t.tree_number = f.tree_number AND t.variant_id = v.variant_id
WHERE t.height_m = f.h_tls AND t.height_source = 'measured'
UNION ALL
SELECT t.tree_id, f.h_tls, f.h_new
FROM canopy_fix_pos f
JOIN shared.Locations l ON l.location_name = 'ecosense'
JOIN shared.Variants v ON v.location_id = l.location_id AND v.variant_name = 'baseline_2025'
JOIN trees.Trees t ON t.location_id = l.location_id AND t.variant_id = v.variant_id AND t.tree_number IS NULL
                  AND abs(ST_X(t.position_original) - f.x) < 0.01 AND abs(ST_Y(t.position_original) - f.y) < 0.01
WHERE t.height_m = f.h_tls AND t.height_source = 'measured';

UPDATE trees.Trees t
SET height_m = h.h_new,
    height_source = 'allometric_yield_table',
    field_notes = coalesce(t.field_notes || ' | ', '') || 'tls_canopy_height_m: ' || h.h_tls,
    crown_width_m = NULL, crown_base_height_m = NULL, volume_m3 = NULL,
    age_years = NULL, biomass_kg = NULL, carbon_content_kg = NULL
FROM canopy_hit h
WHERE t.tree_id = h.tree_id;

UPDATE trees.Stems s SET stem_volume_m3 = NULL
FROM canopy_hit h WHERE s.tree_id = h.tree_id;

SELECT count(*) AS heights_replaced FROM canopy_hit;

COMMIT;
