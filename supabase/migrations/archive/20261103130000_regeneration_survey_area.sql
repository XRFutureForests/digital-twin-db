-- =============================================================================
-- Regeneration: the survey area on the tally, not a subplot
-- =============================================================================
-- XRFF-640 follow-up. Regeneration was first meant to sit on child plots that
-- carry the survey area (e.g. Pathfinder saplings on 0.01 ha). But a plot with
-- an area of its own is a sample unit for the tree estimator: a census with a
-- regeneration subplot became two census units, the second without trees, and
-- stems per hectare dropped (Goettingen 2: 276.9 instead of 284). A
-- regeneration survey area is not a tree sample unit.
--
-- So the tally carries its survey area itself: survey_area_m2. It hangs on the
-- plot it was made in (the superplot); regeneration_per_ha divides by
-- survey_area_m2, else by the plot's resolved area as before.
--
-- Mirrored to init 83-regeneration-survey-area.sql.
-- =============================================================================

ALTER TABLE forest_floor.regeneration
    ADD COLUMN IF NOT EXISTS survey_area_m2 numeric(10,2);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'forest_floor.regeneration'::regclass
                      AND conname = 'regeneration_survey_area_m2_check') THEN
        ALTER TABLE forest_floor.regeneration ADD CONSTRAINT regeneration_survey_area_m2_check
            CHECK (survey_area_m2 > 0);
    END IF;
END;
$$;

COMMENT ON COLUMN forest_floor.regeneration.survey_area_m2 IS
    'Area the tally was counted on, in m2 (e.g. Pathfinder saplings: 100 m2 within the 0.25 ha plot). NULL = the whole plot''s resolved area. Not a plot of its own: a plot with its own area would count as a tree sample unit.';
COMMENT ON COLUMN forest_floor.regeneration.plot_id IS
    'The plot the tally was made in. The survey area is survey_area_m2, else the plot''s area_m2 (or the nearest enclosing plot''s).';
COMMENT ON TABLE forest_floor.regeneration IS
    'Regeneration tallies: live and dead counts per species and size class on a survey area within a plot (survey_area_m2, else the plot''s area). See public.regeneration_per_ha. Size classes follow the protocol of the plot''s sampling design.';

CREATE OR REPLACE VIEW public.regeneration WITH (security_invoker = on) AS
SELECT regeneration_id, location_id, plot_id, campaign_id, species_id, size_class, live_count,
       dead_count, mean_height_m, "position", measurement_date, source_regeneration_id,
       source_attributes, notes, created_at, updated_at, created_by, updated_by,
       survey_area_m2
  FROM forest_floor.regeneration;

-- survey_area_m2 replaces the plot's area in the per-hectare values. Columns
-- keep their names and order; survey_area_m2 now reports the area used.
CREATE OR REPLACE VIEW public.regeneration_per_ha WITH (security_invoker = on) AS
SELECT r.regeneration_id, r.location_id, r.plot_id, r.campaign_id, r.species_id,
       sp.scientific_name, r.size_class, r.live_count, r.dead_count, r.mean_height_m,
       coalesce(r.survey_area_m2, pi.area_m2) AS survey_area_m2,
       round(r.live_count * 10000.0 / coalesce(r.survey_area_m2, pi.area_m2), 2) AS live_per_ha,
       round(r.dead_count * 10000.0 / coalesce(r.survey_area_m2, pi.area_m2), 2) AS dead_per_ha,
       r.measurement_date
  FROM forest_floor.regeneration r
  LEFT JOIN shared.species sp ON sp.species_id = r.species_id
  LEFT JOIN shared.plot_inclusion pi ON pi.plot_id = r.plot_id;

COMMENT ON VIEW public.regeneration_per_ha IS
    'Regeneration per hectare: each tally''s counts divided by its survey area (survey_area_m2, else the plot''s area_m2 or the nearest enclosing plot''s). NULL per-hectare values where no area is known.';

NOTIFY pgrst, 'reload schema';
