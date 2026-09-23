-- Mirrored from supabase/migrations/20260923130000_boolean_prefixes_and_unit_suffixes.sql.
-- Keep the two identical.
-- =============================================================================
-- Tier 4: boolean prefixes and the last two unit suffixes
-- =============================================================================
-- XRFF-490, part of XRFF-494.
--
-- On 2026-09-22 these three booleans were deliberately grandfathered, argued on
-- consumer cost: four repos, a job-menu parameter and a smoke test. The owner
-- reset that on 2026-09-23 -- the database should be well structured and clean,
-- period -- so they move.
--
-- The RO-Crate objection from that decision died on facts rather than priority.
-- Zero crates exist on disk, /crates/ is gitignored, none was ever committed,
-- there is no DOI, and the emitter is a manual CLI that is not wired into the job
-- runner. Nothing published is retro-invalidated; emit_ro_crate.py needed four
-- lines.
--
-- mortality and competition read as quantities -- sum(mortality) returns a
-- plausible-looking wrong answer -- which is why the prefix is worth having
-- rather than merely tidier.
--
-- NOT HERE: public.ue_trees.competition. It is a derived view column
-- (crown_base_height_m / height_m > 0.6) and it is a field in ST_Tree.uasset, so
-- it belongs to the Unreal-facing set that is deferred until the UE structs move
-- (XRFF-492). A renamed column the struct does not expect imports as null,
-- silently, with no error -- which is exactly why that set waits.
--
-- sensor.Sensors.accuracy still has no unit suffix. It needs a decision on what
-- it measures before it can get one.
--
-- Mirror of the migration of the same name.
-- =============================================================================

-- 1. Booleans take the is_ prefix. These two read as quantities -- sum(mortality)
--    returns a plausible-looking wrong answer -- which is why the prefix is worth
--    having rather than merely tidier.
ALTER TABLE trees.growth_simulations RENAME COLUMN mortality TO is_mortality;
ALTER TABLE trees.simulation_runs RENAME COLUMN promoted TO is_promoted;
ALTER TABLE trees.simulation_runs RENAME COLUMN mortality_enabled TO is_mortality_enabled;

-- 2. A measure carries its unit.
ALTER TABLE sensor.sensor_readings RENAME COLUMN battery_voltage TO battery_voltage_v;

-- 3. View output columns, renamed in place so triggers, grants, owner and
--    security_invoker survive.
ALTER VIEW public.growth_simulations RENAME COLUMN mortality TO is_mortality;
ALTER VIEW public.simulation_runs RENAME COLUMN promoted TO is_promoted;
ALTER VIEW public.simulation_runs RENAME COLUMN mortality_enabled TO is_mortality_enabled;
ALTER VIEW public.sensor_readings RENAME COLUMN battery_voltage TO battery_voltage_v;
CREATE OR REPLACE FUNCTION public.sensor_readings_insert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO sensor.sensor_readings (sensor_id, timestamp, value, quality, scenario_id, battery_voltage_v, signal_strength, notes)
    VALUES (NEW.sensor_id, NEW.timestamp, NEW.value, NEW.quality, NEW.scenario_id, NEW.battery_voltage_v, NEW.signal_strength, NEW.notes);
    RETURN NEW;
END;
$function$;
