-- =============================================================================
-- Scenario = management regime x climate pathway, encoded in number and text
-- =============================================================================
-- Unreal selects a forest state by scenario and variant. Variants were already
-- sortable -- shared.Variants carries simulation_year, time_delta_yrs and
-- sort_order -- but a scenario was a bare name. `natural_growth` sat beside
-- `ssp126`/`ssp370`/`ssp585` in the same table with nothing saying that the
-- first holds trees and the others hold acquired climate, nor how a managed
-- projection under a climate pathway would be named or ordered.
--
-- This migration makes a scenario a point on two axes, each a lookup table
-- with a small integer id and a name:
--
--   shared.ManagementRegimes   0 none | 1 natural_growth | 2 crop_tree_thinning | 3 target_diameter_harvest
--   shared.ClimatePathways     0 historical | 1 ssp126 | 2 ssp370 | 3 ssp585
--
-- and adds to shared.Scenarios:
--
--   management_regime_id, climate_pathway_id   the two axes (FKs, NOT NULL)
--   scenario_code                              regime*10 + pathway, generated
--
-- so `natural_growth` is 10, `natural_growth_ssp370` is 12 and
-- `crop_tree_thinning_ssp585` is 23. Unreal sorts on the code and reads the
-- names; the tens digit groups by regime, the units digit by pathway. The
-- ssp* climate buckets the open-data connector creates are regime 0 -- they
-- hold environments, never trees -- and code 1..3.
--
-- ## The name is derived from the axes, and the axes from the name
--
-- Three code paths insert scenarios today: the seed scripts (`natural_growth`),
-- the open-data connector (`ssp126`, ...) and, from now on, silva-connector.
-- Rather than teach all three the new columns, a BEFORE INSERT trigger fills
-- the axes from the name when the inserter did not set them, using the one
-- naming grammar:
--
--   <pathway>                 ->  regime none,     that pathway      (ssp370)
--   <regime>                  ->  that regime,     pathway historical (natural_growth)
--   <regime>_<pathway>        ->  both             (crop_tree_thinning_ssp370)
--
-- A name that fits none of these is refused, which is deliberate: a scenario
-- whose axes cannot be read from its name would be one Unreal cannot place.
-- The inverse -- silva-connector composing the name from the axes -- uses the
-- same grammar, so the two stay consistent by construction.
--
-- ## Management regimes carry their SILVA rule set
--
-- XRFF-436 asked how a thinning regime is expressed and settled on presets
-- seeded in the database, reviewable by a forester, rather than nested JSON on
-- the job request. `silva_rules` is that preset: silvaR's `add_thinning_rule()`
-- arguments, species named by scientific name so the row is readable without
-- knowing silvaR's species coding. silva-connector maps the names the same way
-- it maps the trees. The rules seeded here are textbook Baden-Wuerttemberg
-- crop-tree (Z-Baum) thinning with target-diameter harvest, and are
-- PROVISIONAL until a forester has signed them off -- the description says so.
--
-- ## Views
--
-- public.scenarios stays single-table (it is inserted through), gaining only
-- the three new scalar columns. public.variants and public.ue_trees gain the
-- scenario axes at the end so CREATE OR REPLACE keeps their existing columns
-- in place; ue_trees additionally gains sort_order, time_delta_yrs,
-- variant_type_id and the tree status -- the last one because a harvested
-- tree must disappear in Unreal while a standing dead one stays. Two new flat
-- views, public.ue_scenarios and public.ue_variants, are what a scenario and
-- time-step picker actually needs: one GET each, every id beside its name.
--
-- Consumer grep per AGENTS.md: silva-connector reads shared.scenarios by
-- scenario_name only (R/db.R resolve_variant) and inserts none until the
-- change that accompanies this migration; digital-twin-dashboard joins
-- shared.scenarios on scenario_id/scenario_name only. Neither breaks.
--
-- Idempotent: safe to re-run.
-- =============================================================================


-- =============================================================================
-- PART 1 -- the two axes
-- =============================================================================

CREATE TABLE IF NOT EXISTS shared.ManagementRegimes (
    regime_id     smallint PRIMARY KEY,
    regime_name   character varying(100) NOT NULL UNIQUE,
    description   text,
    -- silvaR thinning preset, or NULL when the regime does no management.
    silva_rules   jsonb,
    created_at    timestamp with time zone DEFAULT now(),
    CONSTRAINT managementregimes_regime_id_check CHECK (regime_id BETWEEN 0 AND 99),
    CONSTRAINT managementregimes_regime_name_check
        CHECK (regime_name ~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$')
);

COMMENT ON TABLE shared.ManagementRegimes IS
    'Management axis of a scenario. Small integer id + snake_case name, so Unreal can sort on the number and label with the text. Regime 0 (none) marks scenarios that hold acquired data only, never trees.';
COMMENT ON COLUMN shared.ManagementRegimes.silva_rules IS
    'silvaR thinning preset: {"removal_method","max_removal_fraction","rules":[{species, thinning_type, guide_curve, metric, intervention, crop_trees_per_ha, n_competitors, target_dbh_cm, target_probability}]}. Species by scientific name or "all". NULL = no management. silva-connector turns this into silva_thinning_regime().';

CREATE TABLE IF NOT EXISTS shared.ClimatePathways (
    pathway_id    smallint PRIMARY KEY,
    pathway_name  character varying(50) NOT NULL UNIQUE,
    -- The label a reader expects, e.g. SSP3-7.0; the name is the machine key.
    label         character varying(50),
    description   text,
    created_at    timestamp with time zone DEFAULT now(),
    -- One decimal digit: the pathway is the units digit of scenario_code.
    CONSTRAINT climatepathways_pathway_id_check CHECK (pathway_id BETWEEN 0 AND 9),
    CONSTRAINT climatepathways_pathway_name_check
        CHECK (pathway_name ~ '^[a-z][a-z0-9]*$')
);

COMMENT ON TABLE shared.ClimatePathways IS
    'Climate axis of a scenario. Pathway 0 (historical) is the observed 1981-2010 climatology held constant; the others are the CMIP6 SSPs the open-data connector acquires (CHELSA temperature/precipitation, SSP CO2). Names are single tokens because they are the suffix of a scenario name.';

INSERT INTO shared.ManagementRegimes (regime_id, regime_name, description, silva_rules) VALUES
    (0, 'none',
     'No forest state. Scenarios with this regime are landing zones for acquired data (climate pathways) and hold no tree variants.',
     NULL),
    (1, 'natural_growth',
     'Unmanaged natural development: growth, competition and natural mortality only. No intervention.',
     NULL),
    (2, 'crop_tree_thinning',
     'Crop-tree (Z-Baum) thinning with target-diameter harvest: the standard Baden-Wuerttemberg regime for EVEN-AGED beech-conifer stands (ecosense: 47-year beech with admixed Douglas fir, fir, spruce, larch, oak). Every second 5-year period the two strongest same-species competitors of each crop tree are removed (beech 80, Douglas fir 100, spruce and fir 150 crop trees per ha; a species with fewer stems per ha than crop trees is left alone); trees above target diameter (beech and Douglas fir 60 cm, fir 55 cm, spruce 45 cm) are harvested with probability 0.5 per period. Minor admixed species are retained. Removal is capped at 25 percent of a species per intervention. Not for two-storied stands: grid-based crop-tree selection there picks the overstory and cuts it. PROVISIONAL -- textbook defaults, not yet reviewed by a forester (2026-09-14).',
     '{
        "removal_method": "simplified",
        "max_removal_fraction": 0.25,
        "rules": [
          {"species": "Fagus sylvatica",       "thinning_type": "crop_tree", "guide_curve": "schober",       "metric": "G", "intervention": {"type": "every_n_periods", "value": 2}, "crop_trees_per_ha": 80,  "n_competitors": 2},
          {"species": "Pseudotsuga menziesii", "thinning_type": "crop_tree", "guide_curve": "assmann_franz", "metric": "G", "intervention": {"type": "every_n_periods", "value": 2}, "crop_trees_per_ha": 100, "n_competitors": 2},
          {"species": "Picea abies",           "thinning_type": "crop_tree", "guide_curve": "assmann_franz", "metric": "G", "intervention": {"type": "every_n_periods", "value": 2}, "crop_trees_per_ha": 150, "n_competitors": 2},
          {"species": "Abies alba",            "thinning_type": "crop_tree", "guide_curve": "assmann_franz", "metric": "G", "intervention": {"type": "every_n_periods", "value": 2}, "crop_trees_per_ha": 150, "n_competitors": 2},
          {"species": "Fagus sylvatica",       "thinning_type": "target_diameter", "guide_curve": "schober",       "metric": "G", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 60, "target_probability": 0.5},
          {"species": "Pseudotsuga menziesii", "thinning_type": "target_diameter", "guide_curve": "assmann_franz", "metric": "G", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 60, "target_probability": 0.5},
          {"species": "Picea abies",           "thinning_type": "target_diameter", "guide_curve": "assmann_franz", "metric": "G", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 45, "target_probability": 0.5},
          {"species": "Abies alba",            "thinning_type": "target_diameter", "guide_curve": "assmann_franz", "metric": "G", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 55, "target_probability": 0.5}
        ]
      }'::jsonb),
    (3, 'target_diameter_harvest',
     'Single-tree selection by target diameter (Zielstaerkennutzung / Plenterung): the regime for UNEVEN-AGED, two-storied spruce-fir-beech mountain mixed stands of the southern Black Forest (mathisle: a young spruce-fir-beech layer under ~120 old spruce and fir of 40-90 cm). Each 5-year period, trees above target diameter (spruce 45 cm, fir 55 cm, beech and Douglas fir 60 cm) are harvested with probability 0.3, so the overstory is removed gradually as the understorey grows into it; no crop-tree selection, no thinning of the young layer. Removal is capped at 25 percent of a species per period. PROVISIONAL -- textbook defaults, not yet reviewed by a forester (2026-09-14).',
     '{
        "removal_method": "simplified",
        "max_removal_fraction": 0.25,
        "rules": [
          {"species": "Picea abies",           "thinning_type": "target_diameter", "guide_curve": "assmann_franz", "metric": "G", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 45, "target_probability": 0.3},
          {"species": "Abies alba",            "thinning_type": "target_diameter", "guide_curve": "assmann_franz", "metric": "G", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 55, "target_probability": 0.3},
          {"species": "Fagus sylvatica",       "thinning_type": "target_diameter", "guide_curve": "schober",       "metric": "G", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 60, "target_probability": 0.3},
          {"species": "Pseudotsuga menziesii", "thinning_type": "target_diameter", "guide_curve": "assmann_franz", "metric": "G", "intervention": {"type": "every_n_periods", "value": 1}, "target_dbh_cm": 60, "target_probability": 0.3}
        ]
      }'::jsonb)
ON CONFLICT (regime_id) DO NOTHING;

INSERT INTO shared.ClimatePathways (pathway_id, pathway_name, label, description) VALUES
    (0, 'historical', 'historical', 'Observed 1981-2010 climatology (CHELSA), held constant. What every projection before 2026-09-14 used implicitly through silvaR''s growth-region table.'),
    (1, 'ssp126',     'SSP1-2.6',   'CMIP6 SSP1-2.6, sustainability / low emissions. CHELSA 30-year windows 2011-2040, 2041-2070, 2071-2100 plus SSP CO2.'),
    (2, 'ssp370',     'SSP3-7.0',   'CMIP6 SSP3-7.0, regional rivalry / high emissions.'),
    (3, 'ssp585',     'SSP5-8.5',   'CMIP6 SSP5-8.5, fossil-fuelled development / very high emissions.')
ON CONFLICT (pathway_id) DO NOTHING;

GRANT SELECT ON TABLE shared.ManagementRegimes TO anon, authenticated;
GRANT ALL    ON TABLE shared.ManagementRegimes TO service_role;
GRANT SELECT ON TABLE shared.ClimatePathways   TO anon, authenticated;
GRANT ALL    ON TABLE shared.ClimatePathways   TO service_role;

ALTER TABLE shared.ManagementRegimes ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.ClimatePathways   ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'shared' AND tablename = 'managementregimes'
                     AND policyname = 'Management regimes are viewable by everyone') THEN
        CREATE POLICY "Management regimes are viewable by everyone"
            ON shared.ManagementRegimes FOR SELECT USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'shared' AND tablename = 'managementregimes'
                     AND policyname = 'Curators can manage management regimes') THEN
        CREATE POLICY "Curators can manage management regimes"
            ON shared.ManagementRegimes FOR ALL TO authenticated
            USING (shared.is_curator()) WITH CHECK (shared.is_curator());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'shared' AND tablename = 'managementregimes'
                     AND policyname = 'Service role can manage all management regimes') THEN
        CREATE POLICY "Service role can manage all management regimes"
            ON shared.ManagementRegimes TO service_role USING (true) WITH CHECK (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'shared' AND tablename = 'climatepathways'
                     AND policyname = 'Climate pathways are viewable by everyone') THEN
        CREATE POLICY "Climate pathways are viewable by everyone"
            ON shared.ClimatePathways FOR SELECT USING (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'shared' AND tablename = 'climatepathways'
                     AND policyname = 'Curators can manage climate pathways') THEN
        CREATE POLICY "Curators can manage climate pathways"
            ON shared.ClimatePathways FOR ALL TO authenticated
            USING (shared.is_curator()) WITH CHECK (shared.is_curator());
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'shared' AND tablename = 'climatepathways'
                     AND policyname = 'Service role can manage all climate pathways') THEN
        CREATE POLICY "Service role can manage all climate pathways"
            ON shared.ClimatePathways TO service_role USING (true) WITH CHECK (true);
    END IF;
END $$;


-- =============================================================================
-- PART 2 -- shared.Scenarios gets the axes and the code
-- =============================================================================

ALTER TABLE shared.Scenarios
    ADD COLUMN IF NOT EXISTS management_regime_id smallint,
    ADD COLUMN IF NOT EXISTS climate_pathway_id   smallint;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scenarios_management_regime_id_fkey') THEN
        ALTER TABLE shared.Scenarios
            ADD CONSTRAINT scenarios_management_regime_id_fkey
            FOREIGN KEY (management_regime_id) REFERENCES shared.ManagementRegimes(regime_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scenarios_climate_pathway_id_fkey') THEN
        ALTER TABLE shared.Scenarios
            ADD CONSTRAINT scenarios_climate_pathway_id_fkey
            FOREIGN KEY (climate_pathway_id) REFERENCES shared.ClimatePathways(pathway_id);
    END IF;
END $$;

-- Derive the axes from a scenario name. Returns NULL when the name fits none
-- of the three grammar forms, so the caller can decide whether that is an
-- error (the trigger) or a miss (a lookup).
CREATE OR REPLACE FUNCTION shared.scenario_axes_from_name(p_name text)
RETURNS TABLE (management_regime_id smallint, climate_pathway_id smallint)
LANGUAGE sql STABLE AS $$
    -- <pathway> alone: a climate-data bucket, regime none.
    SELECT 0::smallint, cp.pathway_id
    FROM shared.ClimatePathways cp
    WHERE cp.pathway_name = p_name
    UNION ALL
    -- <regime> alone: that regime under the historical climate.
    SELECT mr.regime_id, 0::smallint
    FROM shared.ManagementRegimes mr
    WHERE mr.regime_name = p_name AND mr.regime_id <> 0
    UNION ALL
    -- <regime>_<pathway>.
    SELECT mr.regime_id, cp.pathway_id
    FROM shared.ManagementRegimes mr
    JOIN shared.ClimatePathways cp ON p_name = mr.regime_name || '_' || cp.pathway_name
    WHERE mr.regime_id <> 0 AND cp.pathway_id <> 0
    LIMIT 1;
$$;

COMMENT ON FUNCTION shared.scenario_axes_from_name(text) IS
    'The scenario naming grammar: <pathway> | <regime> | <regime>_<pathway>. Returns the two axis ids, or no row when the name fits none of the forms.';

-- Back-fill what exists before the columns become NOT NULL. Every scenario in
-- the twin today fits the grammar (natural_growth, ssp126, ssp370, ssp585);
-- one that does not would stop this migration with a readable message.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT scenario_id, scenario_name FROM shared.Scenarios
             WHERE management_regime_id IS NULL OR climate_pathway_id IS NULL
    LOOP
        UPDATE shared.Scenarios s
        SET management_regime_id = coalesce(s.management_regime_id, a.management_regime_id),
            climate_pathway_id   = coalesce(s.climate_pathway_id,   a.climate_pathway_id)
        FROM shared.scenario_axes_from_name(r.scenario_name) a
        WHERE s.scenario_id = r.scenario_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'shared.Scenarios % (''%'') does not fit the naming grammar <pathway> | <regime> | <regime>_<pathway>; set management_regime_id and climate_pathway_id by hand before re-running.',
                r.scenario_id, r.scenario_name;
        END IF;
    END LOOP;
END $$;

ALTER TABLE shared.Scenarios
    ALTER COLUMN management_regime_id SET NOT NULL,
    ALTER COLUMN climate_pathway_id   SET NOT NULL;

-- regime*10 + pathway. Generated, so it can never disagree with the axes.
ALTER TABLE shared.Scenarios
    ADD COLUMN IF NOT EXISTS scenario_code integer
        GENERATED ALWAYS AS (management_regime_id * 10 + climate_pathway_id) STORED;

-- One scenario per (site, regime, pathway): the code is what Unreal keys on,
-- so two scenarios claiming the same code at one site would be ambiguous.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scenarios_location_axes_key') THEN
        ALTER TABLE shared.Scenarios
            ADD CONSTRAINT scenarios_location_axes_key
            UNIQUE (location_id, management_regime_id, climate_pathway_id);
    END IF;
END $$;

COMMENT ON COLUMN shared.Scenarios.management_regime_id IS
    'Management axis -> shared.ManagementRegimes. Filled from scenario_name by trigger when omitted (grammar: <pathway> | <regime> | <regime>_<pathway>).';
COMMENT ON COLUMN shared.Scenarios.climate_pathway_id IS
    'Climate axis -> shared.ClimatePathways. 0 = historical. Filled from scenario_name by trigger when omitted.';
COMMENT ON COLUMN shared.Scenarios.scenario_code IS
    'management_regime_id * 10 + climate_pathway_id, generated. The sort key Unreal uses: tens digit = regime, units digit = pathway. natural_growth = 10, crop_tree_thinning_ssp585 = 23, a bare ssp370 climate bucket = 2.';

-- The trigger: fill missing axes from the name, refuse a name that fits no form.
CREATE OR REPLACE FUNCTION shared.scenarios_derive_axes()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    a record;
BEGIN
    IF NEW.management_regime_id IS NULL OR NEW.climate_pathway_id IS NULL THEN
        SELECT * INTO a FROM shared.scenario_axes_from_name(NEW.scenario_name);
        IF NOT FOUND THEN
            RAISE EXCEPTION 'scenario name ''%'' does not fit <pathway> | <regime> | <regime>_<pathway> (see shared.ManagementRegimes / shared.ClimatePathways); pass management_regime_id and climate_pathway_id explicitly or use a conforming name',
                NEW.scenario_name USING ERRCODE = '22023';
        END IF;
        NEW.management_regime_id := coalesce(NEW.management_regime_id, a.management_regime_id);
        NEW.climate_pathway_id   := coalesce(NEW.climate_pathway_id,   a.climate_pathway_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_scenarios_derive_axes ON shared.Scenarios;
CREATE TRIGGER trg_scenarios_derive_axes
    BEFORE INSERT OR UPDATE OF scenario_name, management_regime_id, climate_pathway_id
    ON shared.Scenarios
    FOR EACH ROW EXECUTE FUNCTION shared.scenarios_derive_axes();

COMMENT ON TABLE shared.Scenarios IS
    'One scenario per (location, management regime, climate pathway). scenario_code = regime*10 + pathway is the numeric key, scenario_name the text one; the name follows <pathway> | <regime> | <regime>_<pathway> and the axes are derived from it on insert when not given. Regime 0 scenarios hold acquired data only; the rest own a baseline and a variant timeline (Location -> Scenario -> Variant).';


-- =============================================================================
-- PART 3 -- views
-- =============================================================================

-- Lookups, flat, for pickers and for the /jobs/ page.
CREATE OR REPLACE VIEW public.management_regimes
WITH (security_invoker = on) AS
SELECT regime_id, regime_name, description, silva_rules, created_at
FROM shared.ManagementRegimes;

COMMENT ON VIEW public.management_regimes IS
    'Management axis of scenarios: id + name + description + the silvaR thinning preset (silva_rules). Regime 0 holds no trees.';

CREATE OR REPLACE VIEW public.climate_pathways
WITH (security_invoker = on) AS
SELECT pathway_id, pathway_name, label, description, created_at
FROM shared.ClimatePathways;

COMMENT ON VIEW public.climate_pathways IS
    'Climate axis of scenarios: id + name + label. 0 = historical (observed climatology held constant), 1..3 = CMIP6 SSPs.';

GRANT SELECT ON public.management_regimes TO anon, authenticated, service_role;
GRANT SELECT ON public.climate_pathways   TO anon, authenticated, service_role;

-- public.scenarios: still single-table so it stays insertable through
-- PostgREST; the three new scalars are appended.
CREATE OR REPLACE VIEW public.scenarios
WITH (security_invoker = on) AS
SELECT scenarios.scenario_id,
       scenarios.scenario_name,
       scenarios.description,
       scenarios.created_at,
       scenarios.updated_at,
       scenarios.location_id,
       -- appended 2026-09-14
       scenarios.management_regime_id,
       scenarios.climate_pathway_id,
       scenarios.scenario_code
FROM shared.scenarios;

COMMENT ON VIEW public.scenarios IS
    'Public API view: location-scoped scenarios (Location -> Scenario -> Variant), each a (management regime, climate pathway) pair with scenario_code = regime*10 + pathway. Insertable; omit the axis ids and they are derived from a conforming scenario_name. For names alongside ids use ue_scenarios.';

-- public.variants: append the scenario axes.
CREATE OR REPLACE VIEW public.variants
WITH (security_invoker = on) AS
SELECT v.variant_id,
       v.location_id,
       v.scenario_id,
       v.variant_type_id,
       v.variant_name,
       v.simulation_year,
       v.time_delta_yrs,
       v.sort_order,
       v.description,
       v.created_at,
       v.parent_variant_id,
       l.location_name,
       s.scenario_name,
       vt.variant_type_name,
       -- appended 2026-09-14
       s.scenario_code,
       s.management_regime_id,
       mr.regime_name  AS management_regime,
       s.climate_pathway_id,
       cp.pathway_name AS climate_pathway
FROM shared.variants v
    LEFT JOIN shared.locations         l  ON v.location_id = l.location_id
    LEFT JOIN shared.scenarios         s  ON v.scenario_id = s.scenario_id
    LEFT JOIN shared.varianttypes      vt ON v.variant_type_id = vt.variant_type_id
    LEFT JOIN shared.managementregimes mr ON mr.regime_id = s.management_regime_id
    LEFT JOIN shared.climatepathways   cp ON cp.pathway_id = s.climate_pathway_id;

COMMENT ON VIEW public.variants IS
    'Forest-state variants with location/scenario/type names, parent_variant_id lineage and the scenario axes (scenario_code, management_regime, climate_pathway) joined. Filter by location_id+scenario_id and order by sort_order for a site+scenario timeline.';

-- public.ue_trees: append what the Unreal picker and renderer were missing.
-- No security_invoker here: the view predates that convention (F14) and its
-- readers reach it as anon; unchanged, like simulation_runs on 2026-09-02.
CREATE OR REPLACE VIEW public.ue_trees AS
SELECT t.tree_id,
       t.tree_entity_id,
       t.location_id,
       l.location_name,
       s.scenario_id,
       s.scenario_name,
       t.variant_id,
       v.variant_name,
       v.simulation_year,
       vt.variant_type_name,
       sp.common_name AS species_name,
       sp.scientific_name,
       t.height_m,
       t.crown_width_m,
       t.crown_base_height_m,
       st.dbh_cm,
       t.age_years,
       t.health_score,
       COALESCE((t.crown_base_height_m / NULLIF(t.height_m, 0::numeric)) > 0.6, false) AS competition,
       t.sensor_ref,
       (EXISTS (SELECT 1 FROM sensor.sensor_tree_links stl WHERE stl.tree_id = t.tree_id)) AS has_sensors,
       extensions.st_x(t.position_original) AS original_x,
       extensions.st_y(t.position_original) AS original_y,
       t.source_crs,
       extensions.st_y(t."position") AS latitude,
       extensions.st_x(t."position") AS longitude,
       -- appended 2026-09-14: numeric order for the pickers, the scenario
       -- axes, and the tree status so a harvested tree can be hidden while a
       -- standing dead one is rendered.
       v.sort_order,
       v.time_delta_yrs,
       v.variant_type_id,
       s.scenario_code,
       s.management_regime_id,
       mr.regime_name  AS management_regime,
       s.climate_pathway_id,
       cp.pathway_name AS climate_pathway,
       t.tree_status_id,
       ts.tree_status_name
FROM trees.trees t
    LEFT JOIN shared.locations         l  ON t.location_id = l.location_id
    LEFT JOIN shared.variants          v  ON t.variant_id = v.variant_id
    LEFT JOIN shared.scenarios         s  ON v.scenario_id = s.scenario_id
    LEFT JOIN shared.varianttypes      vt ON v.variant_type_id = vt.variant_type_id
    LEFT JOIN shared.species           sp ON t.species_id = sp.species_id
    LEFT JOIN trees.stems              st ON st.tree_id = t.tree_id AND st.stem_number = 1
    LEFT JOIN shared.managementregimes mr ON mr.regime_id = s.management_regime_id
    LEFT JOIN shared.climatepathways   cp ON cp.pathway_id = s.climate_pathway_id
    LEFT JOIN trees.treestatus         ts ON ts.tree_status_id = t.tree_status_id;

COMMENT ON VIEW public.ue_trees IS
    'Flat tree catalogue for UE Blueprint import. One row per tree with the location/scenario/variant hierarchy (id + name at each level), the scenario axes (scenario_code = regime*10 + pathway, management_regime, climate_pathway), the variant''s simulation_year / sort_order / time_delta_yrs, species, main-stem DBH, competition flag, tree_status (healthy | dead = standing snag, render it | harvested = gone, hide it), sensor cross-reference and projected source coordinates (original_x/original_y in source_crs, EPSG:32632 -- preferred for UE placement) plus flattened latitude/longitude. Filter by variant_id to load one time step. Pickers: ue_scenarios, ue_variants.';

-- The scenario picker: one row per scenario that holds trees, ordered by code.
CREATE OR REPLACE VIEW public.ue_scenarios
WITH (security_invoker = on) AS
SELECT s.scenario_id,
       s.location_id,
       l.location_name,
       s.scenario_name,
       s.scenario_code,
       s.management_regime_id,
       mr.regime_name  AS management_regime,
       s.climate_pathway_id,
       cp.pathway_name AS climate_pathway,
       cp.label        AS climate_label,
       s.description,
       agg.variant_count,
       agg.first_year,
       agg.last_year,
       coalesce(agg.variant_count, 0) > 0 AS has_trees,
       -- The measured state this scenario's chain hangs off. Every projection
       -- starts from the baseline in natural_growth, so a managed scenario's
       -- own variants begin one period later; a picker that offers the base
       -- year in every scenario loads this variant for it.
       bl.baseline_variant_id,
       bv.simulation_year AS baseline_year
FROM shared.scenarios s
    JOIN      shared.locations         l  ON l.location_id = s.location_id
    LEFT JOIN shared.managementregimes mr ON mr.regime_id  = s.management_regime_id
    LEFT JOIN shared.climatepathways   cp ON cp.pathway_id = s.climate_pathway_id
    LEFT JOIN LATERAL (
        SELECT count(*)::integer      AS variant_count,
               min(v.simulation_year) AS first_year,
               max(v.simulation_year) AS last_year
        FROM shared.variants v
        WHERE v.scenario_id = s.scenario_id
          AND EXISTS (SELECT 1 FROM trees.trees t WHERE t.variant_id = v.variant_id)
    ) agg ON true
    LEFT JOIN LATERAL (
        -- The chain's first variant, and what it was projected from: its own
        -- parent, or itself when it is the measured baseline.
        SELECT coalesce(v.parent_variant_id, v.variant_id) AS baseline_variant_id
        FROM shared.variants v
        WHERE v.scenario_id = s.scenario_id
        ORDER BY v.sort_order, v.simulation_year
        LIMIT 1
    ) bl ON true
    LEFT JOIN shared.variants bv ON bv.variant_id = bl.baseline_variant_id;

COMMENT ON VIEW public.ue_scenarios IS
    'Scenario picker for Unreal: every scenario with its numeric code and text axes, how many tree-holding variants it has and the years they span, and baseline_variant_id -- the measured state (in natural_growth) its chain was projected from, so a picker can offer the base year in every scenario. has_trees=false rows are climate-data buckets. GET /rest/v1/ue_scenarios?location_id=eq.1&has_trees=eq.true&order=scenario_code';

-- The time-step picker: one row per variant, with its scenario axes.
CREATE OR REPLACE VIEW public.ue_variants
WITH (security_invoker = on) AS
SELECT v.variant_id,
       v.location_id,
       l.location_name,
       v.scenario_id,
       s.scenario_name,
       s.scenario_code,
       mr.regime_name  AS management_regime,
       cp.pathway_name AS climate_pathway,
       v.variant_name,
       v.variant_type_id,
       vt.variant_type_name,
       v.simulation_year,
       v.time_delta_yrs,
       v.sort_order,
       v.parent_variant_id,
       v.description,
       (SELECT count(*)::integer FROM trees.trees t WHERE t.variant_id = v.variant_id) AS tree_count
FROM shared.variants v
    JOIN      shared.locations         l  ON l.location_id = v.location_id
    JOIN      shared.scenarios         s  ON s.scenario_id = v.scenario_id
    LEFT JOIN shared.varianttypes      vt ON vt.variant_type_id = v.variant_type_id
    LEFT JOIN shared.managementregimes mr ON mr.regime_id  = s.management_regime_id
    LEFT JOIN shared.climatepathways   cp ON cp.pathway_id = s.climate_pathway_id;

COMMENT ON VIEW public.ue_variants IS
    'Time-step picker for Unreal: one row per variant with simulation_year (the number), variant_name (the text), sort_order, lineage and the scenario axes. GET /rest/v1/ue_variants?location_id=eq.1&scenario_code=eq.23&order=sort_order then GET /rest/v1/ue_trees?variant_id=eq.<id>';

GRANT SELECT ON public.ue_scenarios TO anon, authenticated, service_role;
GRANT SELECT ON public.ue_variants  TO anon, authenticated, service_role;
