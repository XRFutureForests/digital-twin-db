-- Mirrored from supabase/migrations/20261104120000_height_source_register.sql.
-- =============================================================================
-- height_source register: the values actually written today
-- =============================================================================
-- The column comment is the register of height_source values (no CHECK, by
-- design: 20260903150000). It still named 'allometric_pylometree', the old fill
-- that used one unfitted curve for every species, and missed three values in
-- use. fill_missing_heights.py now fits a Naslund curve per species (or per leaf
-- type) to the measured trees and replaced every 'allometric_pylometree' row.
--
-- Mirrored to init 84-height-source-register.sql.
-- =============================================================================

COMMENT ON COLUMN trees.trees.height_source IS
    'How height_m was arrived at. NULL means unrecorded -- it is not a claim '
    'that the height was measured. Values in use: ''measured'' (field '
    'instrument), ''measured_tls'' (terrestrial laser scan, '
    'scripts/import/import_tls_heights.py), ''allometric_fitted_species'' / '
    '''allometric_fitted_leaf_type'' (Naslund H-D curve fitted to this '
    'database''s measured trees, per species or pooled per leaf type, see '
    'scripts/import/fill_missing_heights.py), ''allometric_yield_table'' '
    '(yield-table height, scripts/seed/ecosense_canopy_height_fix.sql), '
    '''simulated_silva'' (SILVA projection, see silva-connector). Pair with '
    'data_source_type_id, which records how the tree record as a whole was '
    'produced, and process_id, which identifies the run.';
