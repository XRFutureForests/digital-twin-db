# XR Future Forests Lab - Implementation Plan

**Version:** 1.0  
**Date:** February 2026  
**Status:** Planning Phase

---

## Executive Summary

This document outlines the implementation roadmap for enhancing the XR Future Forests Lab digital twin platform based on forest digital twin standards and best practices identified through literature review. The plan focuses on practical enhancements that add immediate value while maintaining compatibility with existing infrastructure.

### Scope

**In Scope:**

- Core calculation functions (height, biomass, carbon, wood quality)
- External growth/management model integration (plugin architecture)
- 3D Tiles export for Unreal Engine
- Climate data integration
- GBIF species taxonomy alignment

**Out of Scope (deferred):**

- Semantic layer (RDF/OWL ontologies)
- OGC SensorThings API implementation

---

## Current State Assessment

### Strengths of Existing Database

| Feature | Status | Notes |
|---------|--------|-------|
| TreeEntityID (persistent UUID) | ✅ Complete | Enables entity continuity across time |
| Variant-based temporal lineage | ✅ Complete | Tracks tree state changes over time |
| Multi-stem tree support | ✅ Complete | Handles complex tree structures |
| Field-level audit trail | ✅ Complete | Comprehensive change tracking |
| PostGIS spatial data | ✅ Complete | Full spatial analysis capabilities |
| Point cloud integration | ✅ Complete | LiDAR data support |
| Sensor data management | ✅ Complete | Real-time environmental monitoring |

### Identified Gaps

| Gap | Priority | Effort | Impact |
|-----|----------|--------|--------|
| Height imputation from DBH | High | Medium | Enables biomass/carbon calculations |
| Biomass calculation | High | Low | Core forestry metric |
| Carbon stock estimation | High | Low | Climate reporting requirement |
| Wood quality assessment | High | Medium | Timber management |
| External model interface | High | Medium | Enables growth simulation |
| 3D Tiles export | Medium | Medium | Visualization in Unreal/Cesium |
| Climate zone attribution | Medium | Low | Environmental context |
| GBIF species alignment | Low | Low | Taxonomy standardization |

---

## Implementation Phases

### Phase 1: Core Calculation Functions (Weeks 1-2)

#### 1.1 Species Parameters Extension

Add allometric parameters to the species lookup table:

```sql
-- Add columns to shared.species table
ALTER TABLE shared.species ADD COLUMN IF NOT EXISTS
    height_equation_type TEXT DEFAULT 'power' 
    CHECK (height_equation_type IN ('power', 'michaelis', 'curtis'));

ALTER TABLE shared.species ADD COLUMN IF NOT EXISTS height_param_a NUMERIC;
ALTER TABLE shared.species ADD COLUMN IF NOT EXISTS height_param_b NUMERIC;
ALTER TABLE shared.species ADD COLUMN IF NOT EXISTS height_param_c NUMERIC;

ALTER TABLE shared.species ADD COLUMN IF NOT EXISTS biomass_param_a NUMERIC;
ALTER TABLE shared.species ADD COLUMN IF NOT EXISTS biomass_param_b NUMERIC;
ALTER TABLE shared.species ADD COLUMN IF NOT EXISTS biomass_param_c NUMERIC;

ALTER TABLE shared.species ADD COLUMN IF NOT EXISTS carbon_fraction NUMERIC DEFAULT 0.47;
ALTER TABLE shared.species ADD COLUMN IF NOT EXISTS wood_density NUMERIC; -- kg/m³

COMMENT ON COLUMN shared.species.height_equation_type IS 
    'Allometric equation type: power (H = a * DBH^b), michaelis (H = a * DBH / (b + DBH)), curtis (H = 1.3 + a * exp(-b/DBH))';
COMMENT ON COLUMN shared.species.carbon_fraction IS 
    'Carbon fraction of dry biomass (default 0.47 per IPCC guidelines)';
```

**Default Parameters (Common European Species):**

| Species | height_a | height_b | biomass_a | biomass_b | biomass_c | carbon_fraction |
|---------|----------|----------|-----------|-----------|-----------|-----------------|
| Picea abies | 1.3 | 0.85 | 0.0523 | 2.1392 | 0.9435 | 0.47 |
| Fagus sylvatica | 1.5 | 0.78 | 0.0892 | 2.0312 | 0.8831 | 0.48 |
| Quercus robur | 1.2 | 0.82 | 0.1102 | 1.9834 | 0.8456 | 0.49 |
| Pinus sylvestris | 1.4 | 0.80 | 0.0412 | 2.2156 | 0.9612 | 0.47 |

#### 1.2 Height Imputation Function

```sql
CREATE OR REPLACE FUNCTION trees.calculate_height(
    p_tree_variant_id UUID,
    p_force_recalculate BOOLEAN DEFAULT FALSE
) RETURNS NUMERIC AS $$
DECLARE
    v_dbh NUMERIC;
    v_existing_height NUMERIC;
    v_species_id INTEGER;
    v_equation_type TEXT;
    v_param_a NUMERIC;
    v_param_b NUMERIC;
    v_param_c NUMERIC;
    v_calculated_height NUMERIC;
BEGIN
    -- Get tree measurements and species
    SELECT 
        tv.dbh_cm,
        tv.height_m,
        tv.species_id
    INTO v_dbh, v_existing_height, v_species_id
    FROM trees.tree_variants tv
    WHERE tv.tree_variant_id = p_tree_variant_id;
    
    -- Return existing height if available and not forcing recalculation
    IF v_existing_height IS NOT NULL AND NOT p_force_recalculate THEN
        RETURN v_existing_height;
    END IF;
    
    -- Cannot calculate without DBH
    IF v_dbh IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Get species parameters
    SELECT 
        height_equation_type,
        height_param_a,
        height_param_b,
        height_param_c
    INTO v_equation_type, v_param_a, v_param_b, v_param_c
    FROM shared.species
    WHERE species_id = v_species_id;
    
    -- Use default parameters if species not configured
    IF v_param_a IS NULL THEN
        v_equation_type := 'power';
        v_param_a := 1.3;
        v_param_b := 0.8;
    END IF;
    
    -- Calculate height based on equation type
    v_calculated_height := CASE v_equation_type
        WHEN 'power' THEN 
            -- H = a * DBH^b (most common)
            v_param_a * POWER(v_dbh, v_param_b)
        WHEN 'michaelis' THEN 
            -- H = a * DBH / (b + DBH) (asymptotic)
            (v_param_a * v_dbh) / (v_param_b + v_dbh)
        WHEN 'curtis' THEN 
            -- H = 1.3 + a * exp(-b/DBH)
            1.3 + v_param_a * EXP(-v_param_b / v_dbh)
        ELSE
            v_param_a * POWER(v_dbh, v_param_b)
    END;
    
    RETURN ROUND(v_calculated_height, 2);
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION trees.calculate_height IS 
    'Calculates tree height from DBH using species-specific allometric equations. 
     Returns existing height if measured, otherwise uses DBH-height relationship.';
```

#### 1.3 Biomass Calculation Function

```sql
CREATE OR REPLACE FUNCTION trees.calculate_biomass(
    p_tree_variant_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_dbh NUMERIC;
    v_height NUMERIC;
    v_species_id INTEGER;
    v_param_a NUMERIC;
    v_param_b NUMERIC;
    v_param_c NUMERIC;
    v_wood_density NUMERIC;
    v_stem_biomass NUMERIC;
    v_branch_biomass NUMERIC;
    v_foliage_biomass NUMERIC;
    v_root_biomass NUMERIC;
    v_total_agb NUMERIC;
    v_total_biomass NUMERIC;
BEGIN
    -- Get tree measurements
    SELECT 
        tv.dbh_cm,
        COALESCE(tv.height_m, trees.calculate_height(p_tree_variant_id)),
        tv.species_id
    INTO v_dbh, v_height, v_species_id
    FROM trees.tree_variants tv
    WHERE tv.tree_variant_id = p_tree_variant_id;
    
    IF v_dbh IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Get species parameters
    SELECT 
        COALESCE(biomass_param_a, 0.0523),
        COALESCE(biomass_param_b, 2.1392),
        COALESCE(biomass_param_c, 0.9435),
        COALESCE(wood_density, 450)
    INTO v_param_a, v_param_b, v_param_c, v_wood_density
    FROM shared.species
    WHERE species_id = v_species_id;
    
    -- Calculate above-ground biomass (AGB) using allometric equation
    -- AGB = a * DBH^b * H^c (kg)
    v_total_agb := v_param_a * POWER(v_dbh, v_param_b) * POWER(COALESCE(v_height, 20), v_param_c);
    
    -- Component breakdown (typical ratios)
    v_stem_biomass := v_total_agb * 0.65;      -- 65% stem
    v_branch_biomass := v_total_agb * 0.25;    -- 25% branches
    v_foliage_biomass := v_total_agb * 0.10;   -- 10% foliage
    
    -- Below-ground biomass (root:shoot ratio typically 0.2-0.3)
    v_root_biomass := v_total_agb * 0.25;
    
    v_total_biomass := v_total_agb + v_root_biomass;
    
    RETURN jsonb_build_object(
        'tree_variant_id', p_tree_variant_id,
        'dbh_cm', v_dbh,
        'height_m', v_height,
        'biomass_kg', jsonb_build_object(
            'total', ROUND(v_total_biomass, 2),
            'above_ground', ROUND(v_total_agb, 2),
            'below_ground', ROUND(v_root_biomass, 2),
            'stem', ROUND(v_stem_biomass, 2),
            'branches', ROUND(v_branch_biomass, 2),
            'foliage', ROUND(v_foliage_biomass, 2)
        ),
        'method', 'allometric',
        'calculated_at', NOW()
    );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION trees.calculate_biomass IS 
    'Calculates tree biomass components using species-specific allometric equations.
     Returns JSON with total, above-ground, below-ground, and component breakdown.';
```

#### 1.4 Carbon Stock Calculation

```sql
CREATE OR REPLACE FUNCTION trees.calculate_carbon(
    p_tree_variant_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_biomass JSONB;
    v_carbon_fraction NUMERIC;
    v_species_id INTEGER;
    v_total_carbon NUMERIC;
    v_agb_carbon NUMERIC;
    v_bgb_carbon NUMERIC;
    v_co2_equivalent NUMERIC;
BEGIN
    -- Get biomass
    v_biomass := trees.calculate_biomass(p_tree_variant_id);
    
    IF v_biomass IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Get species carbon fraction
    SELECT 
        tv.species_id,
        COALESCE(s.carbon_fraction, 0.47)
    INTO v_species_id, v_carbon_fraction
    FROM trees.tree_variants tv
    LEFT JOIN shared.species s ON s.species_id = tv.species_id
    WHERE tv.tree_variant_id = p_tree_variant_id;
    
    -- Calculate carbon stocks
    v_agb_carbon := (v_biomass->'biomass_kg'->>'above_ground')::NUMERIC * v_carbon_fraction;
    v_bgb_carbon := (v_biomass->'biomass_kg'->>'below_ground')::NUMERIC * v_carbon_fraction;
    v_total_carbon := v_agb_carbon + v_bgb_carbon;
    
    -- CO2 equivalent (C * 44/12 = C * 3.67)
    v_co2_equivalent := v_total_carbon * 3.67;
    
    RETURN jsonb_build_object(
        'tree_variant_id', p_tree_variant_id,
        'carbon_kg', jsonb_build_object(
            'total', ROUND(v_total_carbon, 2),
            'above_ground', ROUND(v_agb_carbon, 2),
            'below_ground', ROUND(v_bgb_carbon, 2)
        ),
        'co2_equivalent_kg', ROUND(v_co2_equivalent, 2),
        'carbon_fraction', v_carbon_fraction,
        'method', 'biomass_expansion',
        'calculated_at', NOW()
    );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION trees.calculate_carbon IS 
    'Calculates carbon stock and CO2 equivalent for a tree.
     Uses IPCC default carbon fraction of 0.47 if species-specific value unavailable.';
```

#### 1.5 Wood Quality Assessment Function

```sql
CREATE OR REPLACE FUNCTION trees.assess_wood_quality(
    p_tree_variant_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_tree RECORD;
    v_straightness_score INTEGER;
    v_taper_score INTEGER;
    v_branching_score INTEGER;
    v_size_score INTEGER;
    v_total_score INTEGER;
    v_grade TEXT;
    v_timber_potential TEXT;
BEGIN
    -- Get tree attributes
    SELECT 
        tv.dbh_cm,
        tv.height_m,
        st.straightness_name,
        tt.taper_name,
        bp.pattern_name as branching_pattern
    INTO v_tree
    FROM trees.tree_variants tv
    LEFT JOIN shared.straightness_types st ON st.straightness_id = tv.straightness_id
    LEFT JOIN shared.taper_types tt ON tt.taper_id = tv.taper_id
    LEFT JOIN shared.branching_patterns bp ON bp.pattern_id = tv.branching_pattern_id
    WHERE tv.tree_variant_id = p_tree_variant_id;
    
    IF v_tree IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Score straightness (0-25 points)
    v_straightness_score := CASE LOWER(v_tree.straightness_name)
        WHEN 'straight' THEN 25
        WHEN 'slightly curved' THEN 20
        WHEN 'moderately curved' THEN 12
        WHEN 'curved' THEN 6
        WHEN 'crooked' THEN 0
        ELSE 15 -- unknown
    END;
    
    -- Score taper (0-25 points)
    v_taper_score := CASE LOWER(v_tree.taper_name)
        WHEN 'cylindrical' THEN 25
        WHEN 'slight taper' THEN 22
        WHEN 'moderate taper' THEN 15
        WHEN 'strong taper' THEN 8
        WHEN 'extreme taper' THEN 0
        ELSE 15 -- unknown
    END;
    
    -- Score branching (0-25 points)
    v_branching_score := CASE LOWER(v_tree.branching_pattern)
        WHEN 'clear bole' THEN 25
        WHEN 'sparse' THEN 20
        WHEN 'regular' THEN 15
        WHEN 'dense' THEN 8
        WHEN 'heavy' THEN 3
        ELSE 12 -- unknown
    END;
    
    -- Score size (0-25 points based on DBH)
    v_size_score := CASE
        WHEN v_tree.dbh_cm >= 50 THEN 25  -- Large sawlog
        WHEN v_tree.dbh_cm >= 40 THEN 22  -- Medium sawlog
        WHEN v_tree.dbh_cm >= 30 THEN 18  -- Small sawlog
        WHEN v_tree.dbh_cm >= 20 THEN 12  -- Pulpwood
        WHEN v_tree.dbh_cm >= 10 THEN 6   -- Small
        ELSE 0                             -- Undersized
    END;
    
    -- Calculate total score
    v_total_score := v_straightness_score + v_taper_score + v_branching_score + v_size_score;
    
    -- Determine grade
    v_grade := CASE
        WHEN v_total_score >= 90 THEN 'A'  -- Premium quality
        WHEN v_total_score >= 75 THEN 'B'  -- High quality
        WHEN v_total_score >= 60 THEN 'C'  -- Standard quality
        WHEN v_total_score >= 45 THEN 'D'  -- Low quality
        WHEN v_total_score >= 30 THEN 'E'  -- Marginal
        ELSE 'F'                           -- Not suitable
    END;
    
    -- Timber potential
    v_timber_potential := CASE
        WHEN v_grade IN ('A', 'B') AND v_tree.dbh_cm >= 40 THEN 'veneer_quality'
        WHEN v_grade IN ('A', 'B', 'C') AND v_tree.dbh_cm >= 30 THEN 'sawlog'
        WHEN v_grade IN ('C', 'D') AND v_tree.dbh_cm >= 20 THEN 'industrial_roundwood'
        WHEN v_tree.dbh_cm >= 10 THEN 'pulpwood'
        ELSE 'energy_wood'
    END;
    
    RETURN jsonb_build_object(
        'tree_variant_id', p_tree_variant_id,
        'grade', v_grade,
        'total_score', v_total_score,
        'max_score', 100,
        'timber_potential', v_timber_potential,
        'scores', jsonb_build_object(
            'straightness', v_straightness_score,
            'taper', v_taper_score,
            'branching', v_branching_score,
            'size', v_size_score
        ),
        'attributes', jsonb_build_object(
            'dbh_cm', v_tree.dbh_cm,
            'height_m', v_tree.height_m,
            'straightness', v_tree.straightness_name,
            'taper', v_tree.taper_name,
            'branching', v_tree.branching_pattern
        ),
        'assessed_at', NOW()
    );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION trees.assess_wood_quality IS 
    'Assesses timber quality based on straightness, taper, branching, and size.
     Returns grade (A-F), score breakdown, and timber potential classification.';
```

---

### Phase 2: External Model Interface (Weeks 3-4)

#### 2.1 External Models Registry

```sql
-- Table to register external growth/management models
CREATE TABLE IF NOT EXISTS trees.external_models (
    model_id SERIAL PRIMARY KEY,
    model_name TEXT NOT NULL UNIQUE,
    model_type TEXT NOT NULL CHECK (model_type IN ('growth', 'management', 'mortality', 'regeneration')),
    version TEXT,
    description TEXT,
    api_endpoint TEXT,
    input_format JSONB, -- Expected input schema
    output_format JSONB, -- Expected output schema
    supported_species INTEGER[], -- species_ids this model supports
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE trees.external_models IS 
    'Registry of external forest simulation models (SILVA, iLand, BWINPro, etc.)';

-- Insert known models
INSERT INTO trees.external_models (model_name, model_type, description) VALUES
    ('SILVA', 'growth', 'Distance-dependent individual tree growth model'),
    ('iLand', 'growth', 'Landscape model for forest ecosystem dynamics'),
    ('FORMIND', 'growth', 'Individual-based forest gap model'),
    ('BWINPro', 'growth', 'Single-tree growth model for German forests'),
    ('WaldPlaner', 'management', 'Forest planning and management optimization'),
    ('TreeMort', 'mortality', 'Tree mortality prediction model')
ON CONFLICT (model_name) DO NOTHING;
```

#### 2.2 Simulation Request Queue

```sql
-- Queue for simulation requests
CREATE TABLE IF NOT EXISTS trees.simulation_requests (
    request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id INTEGER REFERENCES trees.external_models(model_id),
    request_type TEXT NOT NULL CHECK (request_type IN ('growth', 'scenario', 'optimization')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    
    -- Input parameters
    location_id INTEGER REFERENCES shared.locations(location_id),
    tree_filter JSONB, -- Filter criteria for trees to include
    simulation_years INTEGER DEFAULT 10,
    climate_scenario TEXT DEFAULT 'baseline',
    management_scenario TEXT,
    
    -- Results
    input_data JSONB,
    output_data JSONB,
    error_message TEXT,
    
    -- Metadata
    requested_by TEXT,
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE INDEX idx_simulation_requests_status ON trees.simulation_requests(status);
CREATE INDEX idx_simulation_requests_model ON trees.simulation_requests(model_id);

COMMENT ON TABLE trees.simulation_requests IS 
    'Queue for growth simulation requests to external models';
```

#### 2.3 Management Scenario Requests

```sql
-- Queue for management planning requests
CREATE TABLE IF NOT EXISTS trees.management_requests (
    request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id INTEGER REFERENCES trees.external_models(model_id),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    
    -- Input parameters
    location_id INTEGER REFERENCES shared.locations(location_id),
    planning_horizon_years INTEGER DEFAULT 30,
    optimization_objective TEXT CHECK (optimization_objective IN (
        'maximize_volume', 'maximize_carbon', 'maximize_revenue', 
        'minimize_risk', 'biodiversity', 'multi_objective'
    )),
    constraints JSONB, -- Harvest limits, protected areas, etc.
    
    -- Results
    recommended_actions JSONB,
    projected_outcomes JSONB,
    
    -- Metadata
    requested_by TEXT,
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

COMMENT ON TABLE trees.management_requests IS 
    'Queue for forest management optimization requests';
```

#### 2.4 Export Function for External Models

```sql
CREATE OR REPLACE FUNCTION trees.export_trees_for_simulation(
    p_location_id INTEGER,
    p_model_name TEXT DEFAULT 'SILVA',
    p_include_calculated_fields BOOLEAN DEFAULT TRUE
) RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
    v_trees JSONB;
    v_site_info JSONB;
BEGIN
    -- Get site information
    SELECT jsonb_build_object(
        'location_id', l.location_id,
        'location_name', l.location_name,
        'coordinates', jsonb_build_object(
            'lat', ST_Y(l.centroid::geometry),
            'lon', ST_X(l.centroid::geometry)
        ),
        'area_ha', l.area_ha,
        'elevation_m', l.elevation_m,
        'climate_zone', cz.climate_name,
        'soil_type', st.soil_name
    )
    INTO v_site_info
    FROM shared.locations l
    LEFT JOIN shared.climate_zones cz ON cz.climate_id = l.climate_zone_id
    LEFT JOIN shared.soil_types st ON st.soil_id = l.soil_type_id
    WHERE l.location_id = p_location_id;
    
    -- Get tree data
    SELECT jsonb_agg(
        jsonb_build_object(
            'tree_entity_id', te.tree_entity_id,
            'tree_variant_id', tv.tree_variant_id,
            'species_code', s.species_code,
            'species_name', s.scientific_name,
            'dbh_cm', tv.dbh_cm,
            'height_m', CASE 
                WHEN p_include_calculated_fields THEN 
                    COALESCE(tv.height_m, trees.calculate_height(tv.tree_variant_id))
                ELSE tv.height_m
            END,
            'crown_diameter_m', tv.crown_diameter_m,
            'coordinates', jsonb_build_object(
                'x', ST_X(tv.position::geometry),
                'y', ST_Y(tv.position::geometry)
            ),
            'age_years', tv.age_years,
            'status', ts.status_name,
            'biomass', CASE 
                WHEN p_include_calculated_fields THEN 
                    trees.calculate_biomass(tv.tree_variant_id)
                ELSE NULL
            END,
            'carbon', CASE 
                WHEN p_include_calculated_fields THEN 
                    trees.calculate_carbon(tv.tree_variant_id)
                ELSE NULL
            END
        )
    )
    INTO v_trees
    FROM trees.tree_entities te
    JOIN trees.tree_variants tv ON tv.tree_entity_id = te.tree_entity_id 
        AND tv.is_current = TRUE
    LEFT JOIN shared.species s ON s.species_id = tv.species_id
    LEFT JOIN shared.tree_status ts ON ts.status_id = tv.status_id
    WHERE te.location_id = p_location_id
    AND (ts.status_name IS NULL OR ts.status_name != 'removed');
    
    -- Build result
    v_result := jsonb_build_object(
        'export_format', 'xr_future_forests_v1',
        'target_model', p_model_name,
        'exported_at', NOW(),
        'site', v_site_info,
        'tree_count', jsonb_array_length(COALESCE(v_trees, '[]'::jsonb)),
        'trees', COALESCE(v_trees, '[]'::jsonb)
    );
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION trees.export_trees_for_simulation IS 
    'Exports tree data in a format suitable for external growth models.
     Optionally includes calculated height, biomass, and carbon values.';
```

#### 2.5 Import Function for Simulation Results

```sql
CREATE OR REPLACE FUNCTION trees.import_simulation_results(
    p_request_id UUID,
    p_results JSONB
) RETURNS JSONB AS $$
DECLARE
    v_request RECORD;
    v_tree JSONB;
    v_imported_count INTEGER := 0;
    v_errors JSONB := '[]'::jsonb;
BEGIN
    -- Get request details
    SELECT * INTO v_request
    FROM trees.simulation_requests
    WHERE request_id = p_request_id;
    
    IF v_request IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', 'Request not found'
        );
    END IF;
    
    -- Process each projected tree state
    FOR v_tree IN SELECT * FROM jsonb_array_elements(p_results->'projected_trees')
    LOOP
        BEGIN
            -- Create new tree variant with projected values
            INSERT INTO trees.tree_variants (
                tree_entity_id,
                species_id,
                dbh_cm,
                height_m,
                crown_diameter_m,
                measurement_date,
                data_source,
                notes,
                is_current
            )
            SELECT 
                te.tree_entity_id,
                tv.species_id,
                (v_tree->>'projected_dbh_cm')::NUMERIC,
                (v_tree->>'projected_height_m')::NUMERIC,
                (v_tree->>'projected_crown_m')::NUMERIC,
                (p_results->>'projection_date')::DATE,
                format('Simulation: %s (request %s)', v_request.model_id, p_request_id),
                format('Projected %s years from %s', 
                    v_request.simulation_years, 
                    p_results->>'base_date'),
                FALSE  -- Projected data is not current measurement
            FROM trees.tree_entities te
            JOIN trees.tree_variants tv ON tv.tree_entity_id = te.tree_entity_id 
                AND tv.is_current = TRUE
            WHERE te.tree_entity_id = (v_tree->>'tree_entity_id')::UUID;
            
            v_imported_count := v_imported_count + 1;
            
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors || jsonb_build_object(
                'tree_entity_id', v_tree->>'tree_entity_id',
                'error', SQLERRM
            );
        END;
    END LOOP;
    
    -- Update request status
    UPDATE trees.simulation_requests
    SET 
        status = 'completed',
        output_data = p_results,
        completed_at = NOW()
    WHERE request_id = p_request_id;
    
    RETURN jsonb_build_object(
        'success', TRUE,
        'imported_count', v_imported_count,
        'errors', v_errors
    );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION trees.import_simulation_results IS 
    'Imports simulation results from external growth models.
     Creates new tree variants with projected measurements.';
```

---

### Phase 3: 3D Tiles Export (Weeks 5-6)

#### 3.1 Overview

Export tree data as 3D Tiles for visualization in Cesium/Unreal Engine. This is preferred over CityGML for direct integration with game engines.

#### 3.2 Tree Tile Export Function

```sql
CREATE OR REPLACE FUNCTION trees.export_3d_tiles_json(
    p_location_id INTEGER,
    p_lod INTEGER DEFAULT 1  -- Level of detail: 0=billboard, 1=simple, 2=detailed
) RETURNS JSONB AS $$
DECLARE
    v_trees JSONB;
    v_bounds JSONB;
    v_location RECORD;
BEGIN
    -- Get location bounds
    SELECT 
        l.location_name,
        ST_XMin(l.boundary::geometry) as min_x,
        ST_YMin(l.boundary::geometry) as min_y,
        ST_XMax(l.boundary::geometry) as max_x,
        ST_YMax(l.boundary::geometry) as max_y,
        COALESCE(l.elevation_m, 0) as elevation
    INTO v_location
    FROM shared.locations l
    WHERE l.location_id = p_location_id;
    
    -- Build tree instances for 3D Tiles
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', te.tree_entity_id,
            'position', ARRAY[
                ST_X(tv.position::geometry),
                ST_Y(tv.position::geometry),
                COALESCE(tv.elevation_m, v_location.elevation)
            ],
            'properties', jsonb_build_object(
                'species', s.common_name,
                'scientific_name', s.scientific_name,
                'dbh_cm', tv.dbh_cm,
                'height_m', COALESCE(tv.height_m, trees.calculate_height(tv.tree_variant_id)),
                'crown_diameter_m', tv.crown_diameter_m,
                'age_years', tv.age_years,
                'health_status', tv.health_status
            ),
            'model', CASE p_lod
                WHEN 0 THEN 'billboard'
                WHEN 1 THEN LOWER(REPLACE(s.common_name, ' ', '_')) || '_lod1'
                ELSE LOWER(REPLACE(s.common_name, ' ', '_')) || '_lod2'
            END,
            'scale', ARRAY[
                COALESCE(tv.crown_diameter_m, tv.dbh_cm * 0.15) / 10.0,
                COALESCE(tv.crown_diameter_m, tv.dbh_cm * 0.15) / 10.0,
                COALESCE(tv.height_m, trees.calculate_height(tv.tree_variant_id)) / 20.0
            ]
        )
    )
    INTO v_trees
    FROM trees.tree_entities te
    JOIN trees.tree_variants tv ON tv.tree_entity_id = te.tree_entity_id AND tv.is_current = TRUE
    LEFT JOIN shared.species s ON s.species_id = tv.species_id
    LEFT JOIN shared.tree_status ts ON ts.status_id = tv.status_id
    WHERE te.location_id = p_location_id
    AND (ts.status_name IS NULL OR ts.status_name != 'removed');
    
    -- Build 3D Tiles tileset structure
    RETURN jsonb_build_object(
        'asset', jsonb_build_object(
            'version', '1.1',
            'generator', 'XR Future Forests Lab'
        ),
        'geometricError', 500,
        'root', jsonb_build_object(
            'boundingVolume', jsonb_build_object(
                'region', ARRAY[
                    radians(v_location.min_x),
                    radians(v_location.min_y),
                    radians(v_location.max_x),
                    radians(v_location.max_y),
                    v_location.elevation,
                    v_location.elevation + 50
                ]
            ),
            'geometricError', 100,
            'refine', 'ADD',
            'content', jsonb_build_object(
                'uri', 'trees.glb'
            )
        ),
        'instances', v_trees,
        'metadata', jsonb_build_object(
            'location', v_location.location_name,
            'tree_count', jsonb_array_length(COALESCE(v_trees, '[]'::jsonb)),
            'lod', p_lod,
            'exported_at', NOW()
        )
    );
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION trees.export_3d_tiles_json IS 
    'Exports tree data as 3D Tiles JSON for Cesium/Unreal Engine visualization.
     LOD 0=billboard, 1=simple geometry, 2=detailed models.';
```

#### 3.3 Python Export Script

Create a Python script to generate actual 3D Tiles files:

```python
# scripts/export/generate_3d_tiles.py
"""
Generates 3D Tiles tileset from database tree data.
Requires: py3dtiles, numpy, psycopg2
"""

import json
import os
from pathlib import Path
import psycopg2
from psycopg2.extras import RealDictCursor

def export_3d_tiles(location_id: int, output_dir: str):
    """Export trees as 3D Tiles for a given location."""
    
    conn = psycopg2.connect(os.environ['DATABASE_URL'])
    
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT trees.export_3d_tiles_json(%s, 1) as tileset",
            (location_id,)
        )
        result = cur.fetchone()
        tileset = result['tileset']
    
    # Write tileset.json
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    with open(output_path / 'tileset.json', 'w') as f:
        json.dump(tileset, f, indent=2)
    
    print(f"Exported {tileset['metadata']['tree_count']} trees to {output_path}")
    
    # TODO: Generate actual GLB files using py3dtiles
    # This requires 3D tree models for each species
    
    conn.close()

if __name__ == '__main__':
    import sys
    location_id = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    output_dir = sys.argv[2] if len(sys.argv) > 2 else './output/3dtiles'
    export_3d_tiles(location_id, output_dir)
```

---

### Phase 4: Climate Data Integration (Weeks 7-8)

#### 4.1 Climate Data Schema Extension

```sql
-- Add climate data table to environments schema
CREATE TABLE IF NOT EXISTS environments.climate_data (
    climate_data_id SERIAL PRIMARY KEY,
    location_id INTEGER REFERENCES shared.locations(location_id),
    
    -- Time period
    data_year INTEGER,
    data_month INTEGER,
    
    -- Temperature (°C)
    temp_mean NUMERIC,
    temp_min NUMERIC,
    temp_max NUMERIC,
    
    -- Precipitation (mm)
    precipitation_mm NUMERIC,
    precipitation_days INTEGER,
    
    -- Growing conditions
    growing_degree_days NUMERIC,  -- GDD base 5°C
    frost_days INTEGER,
    
    -- Solar radiation
    solar_radiation_kwh_m2 NUMERIC,
    
    -- Water balance
    potential_evapotranspiration_mm NUMERIC,
    water_balance_mm NUMERIC,  -- precipitation - PET
    
    -- Data source
    data_source TEXT,  -- 'measured', 'interpolated', 'modeled'
    scenario TEXT DEFAULT 'historical',  -- 'historical', 'rcp45', 'rcp85'
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_climate_data_location_time 
    ON environments.climate_data(location_id, data_year, data_month);

COMMENT ON TABLE environments.climate_data IS 
    'Monthly climate data for locations, including historical and projected scenarios.';
```

#### 4.2 Climate Attribution Function

```sql
CREATE OR REPLACE FUNCTION environments.get_climate_summary(
    p_location_id INTEGER,
    p_year_start INTEGER DEFAULT NULL,
    p_year_end INTEGER DEFAULT NULL
) RETURNS JSONB AS $$
BEGIN
    RETURN (
        SELECT jsonb_build_object(
            'location_id', p_location_id,
            'period', jsonb_build_object(
                'start', COALESCE(p_year_start, MIN(data_year)),
                'end', COALESCE(p_year_end, MAX(data_year))
            ),
            'annual_means', jsonb_build_object(
                'temperature_c', ROUND(AVG(temp_mean)::NUMERIC, 1),
                'precipitation_mm', ROUND(SUM(precipitation_mm) / 
                    NULLIF(COUNT(DISTINCT data_year), 0), 0),
                'growing_degree_days', ROUND(SUM(growing_degree_days) / 
                    NULLIF(COUNT(DISTINCT data_year), 0), 0),
                'frost_days', ROUND(SUM(frost_days)::NUMERIC / 
                    NULLIF(COUNT(DISTINCT data_year), 0), 0)
            ),
            'extremes', jsonb_build_object(
                'temp_max', MAX(temp_max),
                'temp_min', MIN(temp_min),
                'driest_month_mm', MIN(precipitation_mm),
                'wettest_month_mm', MAX(precipitation_mm)
            )
        )
        FROM environments.climate_data
        WHERE location_id = p_location_id
        AND (p_year_start IS NULL OR data_year >= p_year_start)
        AND (p_year_end IS NULL OR data_year <= p_year_end)
        AND scenario = 'historical'
    );
END;
$$ LANGUAGE plpgsql STABLE;
```

---

### Phase 5: GBIF Species Alignment (Week 9)

#### 5.1 Species Table Updates

The existing `shared.species` table already has GBIF columns. Ensure they're populated:

```sql
-- Add GBIF validation status if not exists
ALTER TABLE shared.species 
    ADD COLUMN IF NOT EXISTS gbif_validated_at TIMESTAMPTZ;

-- View for GBIF alignment status
CREATE OR REPLACE VIEW shared.species_gbif_status AS
SELECT 
    s.species_id,
    s.species_code,
    s.scientific_name,
    s.gbif_taxon_key,
    s.gbif_accepted_name,
    s.gbif_status,
    s.gbif_validated_at,
    CASE 
        WHEN s.gbif_taxon_key IS NOT NULL THEN 'aligned'
        WHEN s.gbif_status = 'not_found' THEN 'not_found'
        ELSE 'pending'
    END as alignment_status
FROM shared.species s;
```

#### 5.2 GBIF Validation Script Update

Update existing script `scripts/admin/validate_species_gbif.py`:

```python
# Enhancement to existing script
async def validate_all_species():
    """Validate all species against GBIF backbone taxonomy."""
    
    # Get species without GBIF validation
    species_list = await db.fetch("""
        SELECT species_id, scientific_name 
        FROM shared.species 
        WHERE gbif_taxon_key IS NULL 
        AND (gbif_validated_at IS NULL OR gbif_status != 'not_found')
    """)
    
    for species in species_list:
        result = await lookup_gbif(species['scientific_name'])
        
        await db.execute("""
            UPDATE shared.species SET
                gbif_taxon_key = $1,
                gbif_accepted_name = $2,
                gbif_status = $3,
                gbif_rank = $4,
                gbif_validated_at = NOW()
            WHERE species_id = $5
        """, 
            result.get('usageKey'),
            result.get('acceptedUsageKey') and result.get('canonicalName'),
            result.get('status', 'not_found'),
            result.get('rank'),
            species['species_id']
        )
```

---

## API Endpoints

### New REST Endpoints for Edge Functions

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/trees/{id}/calculate` | GET | Returns calculated height, biomass, carbon |
| `/trees/{id}/quality` | GET | Returns wood quality assessment |
| `/locations/{id}/export/simulation` | GET | Export trees for external models |
| `/locations/{id}/export/3dtiles` | GET | Export as 3D Tiles JSON |
| `/simulations` | POST | Create simulation request |
| `/simulations/{id}/results` | POST | Import simulation results |
| `/locations/{id}/climate` | GET | Get climate summary |

---

## Deployment Checklist

### Prerequisites

- [ ] PostgreSQL 15+ with PostGIS
- [ ] Existing XR Future Forests Lab database
- [ ] Backup of production data

### Phase 1 Deployment

- [ ] Run species parameters migration
- [ ] Deploy calculate_height function
- [ ] Deploy calculate_biomass function
- [ ] Deploy calculate_carbon function
- [ ] Deploy assess_wood_quality function
- [ ] Populate species allometric parameters
- [ ] Test calculations with sample trees

### Phase 2 Deployment

- [ ] Create external_models table
- [ ] Create simulation_requests table
- [ ] Create management_requests table
- [ ] Deploy export_trees_for_simulation function
- [ ] Deploy import_simulation_results function
- [ ] Register available external models
- [ ] Test export/import cycle

### Phase 3 Deployment

- [ ] Deploy export_3d_tiles_json function
- [ ] Install py3dtiles and dependencies
- [ ] Deploy Python export script
- [ ] Test with Cesium viewer
- [ ] Document model requirements for each species

### Phase 4 Deployment

- [ ] Create climate_data table
- [ ] Deploy climate functions
- [ ] Load historical climate data
- [ ] Test climate summaries

### Phase 5 Deployment

- [ ] Update species with GBIF columns
- [ ] Run GBIF validation script
- [ ] Verify alignment status
- [ ] Document unmatched species

---

## Testing Strategy

### Unit Tests

```sql
-- Test height calculation
DO $$
DECLARE
    v_height NUMERIC;
BEGIN
    -- Create test tree variant
    -- Test that height is calculated correctly
    -- Assert expected range
END $$;
```

### Integration Tests

1. **Export-Import Cycle**: Export trees, simulate changes, import results
2. **3D Tiles Generation**: Verify output is valid 3D Tiles JSON
3. **Climate Integration**: Verify climate data attribution

### Performance Benchmarks

| Operation | Target | Notes |
|-----------|--------|-------|
| calculate_height (single) | < 10ms | |
| calculate_biomass (single) | < 50ms | Includes height calculation |
| export_trees_for_simulation (1000 trees) | < 2s | |
| export_3d_tiles_json (1000 trees) | < 5s | |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Allometric equations inaccurate for local conditions | Medium | Medium | Validate against measured height data, calibrate parameters |
| External model integration complexity | Medium | High | Start with one model (SILVA), abstract interface |
| 3D Tiles performance with large forests | Low | Medium | Implement LOD, spatial tiling |
| Climate data availability | Low | Low | Use interpolated data, document sources |

---

## References

### Literature

- Sasaki, K. & Abe, Y. (2025). 4-layer Forest Digital Twin Architecture
- Ambarwari, A. (2024). CityGML for Individual Trees
- IPCC Guidelines for National Greenhouse Gas Inventories

### Standards

- ISO 23247: Digital Twin Framework
- OGC 3D Tiles 1.1 Specification
- Darwin Core Terms

### External Models

- [SILVA](https://www.ufz.de/silva) - UFZ Leipzig
- [iLand](https://iland-model.org) - BOKU Vienna
- [BWINPro](https://www.nw-fva.de) - NW-FVA

---

*Document maintained by: XR Future Forests Lab Team*  
*Last updated: February 2026*
