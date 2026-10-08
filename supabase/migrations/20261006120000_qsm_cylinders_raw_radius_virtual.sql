-- =============================================================================
-- trees.qsm_cylinders: keep what the published QSMs carry, accept what they contain
-- =============================================================================
-- Found by standardising about 7,000 real QSMs (Kew, Belgium, Ghent, TreeML, BioDiv graphs;
-- growpy.structure, 2026-10-06) against the table that XRFF-265 created. Three gaps,
-- all additive or relaxing, none touching a column the public views or the UE client read
-- (trees.qsm_cylinders has no public view and no consumer yet; silva-connector and the
-- dashboard do not reference any qsm table).
--
-- 1. raw_radius_m. rTwig's standardised dictionary has `raw_radius` (the BioDiv-3DTrees
--    corrected CSVs carry it) and TreeQSM keeps `UnmodRadius`. XRFF-265 stored one radius
--    plus a per-QSM `is_corrected` flag, so the unmodified fit was lost on import and the
--    correction could not be audited or redone per cylinder. radius_m stays what the
--    source delivered; raw_radius_m is the fit before any correction, NULL when the
--    source does not keep it (older TreeQSM layout, point graphs).
--
-- 2. is_virtual. TreeQSM flags cylinders it added to bridge gaps in the cloud (`added`),
--    TreeML calls it `addedVirtual`. 10-24 % of cylinders in the datasets checked are
--    virtual (Belgium 12 %, Kew 14 %, TreeML 10 %, Ghent 24 %), so any volume or topology
--    statistic needs to be able to separate measured from bridged wood.
--
-- 3. length_m >= 0. XRFF-265 required length_m > 0. Real TreeQSM output contains
--    zero-length cylinders (Belgium 1 in 345,480, Kew 17 in 4.1 M, Ghent 6 in 323 k,
--    BioDiv graphs 17 in 230 k), so import_qsm.py would abort on published data. They carry
--    topology (children hang off them); dropping them would break parent links.
--
-- Also documented, no DDL: branch_index / branch_order / branch_position hold the lab's
-- single axis rule (growpy.structure: the child with the longer supported subtree length
-- continues the axis), not each tool's own branch ids, so QSMs from different tools
-- compare. The source's ids are not stored. In the datasets checked the rule agrees with
-- TreeQSM's own continuation at about 94 % of forks.
-- =============================================================================

ALTER TABLE trees.qsm_cylinders
    ADD COLUMN IF NOT EXISTS raw_radius_m numeric(8,5),
    ADD COLUMN IF NOT EXISTS is_virtual boolean NOT NULL DEFAULT false;

ALTER TABLE trees.qsm_cylinders
    DROP CONSTRAINT IF EXISTS qsm_cylinders_raw_radius_m_check;
ALTER TABLE trees.qsm_cylinders
    ADD CONSTRAINT qsm_cylinders_raw_radius_m_check
    CHECK (raw_radius_m IS NULL OR raw_radius_m >= 0);

ALTER TABLE trees.qsm_cylinders
    DROP CONSTRAINT IF EXISTS qsm_cylinders_length_m_check;
ALTER TABLE trees.qsm_cylinders
    ADD CONSTRAINT qsm_cylinders_length_m_check
    CHECK (length_m >= 0);

COMMENT ON COLUMN trees.qsm_cylinders.radius_m IS 'Radius as the source delivered it: radius-corrected where the source corrects (see trees.qsms.is_corrected), raw otherwise';
COMMENT ON COLUMN trees.qsm_cylinders.raw_radius_m IS 'Radius of the fitted cylinder before any correction (rTwig raw_radius, TreeQSM UnmodRadius); NULL when the source does not keep it';
COMMENT ON COLUMN trees.qsm_cylinders.is_virtual IS 'Cylinder added to bridge a gap in the point cloud (TreeQSM added, TreeML addedVirtual), not fitted to points';
COMMENT ON COLUMN trees.qsm_cylinders.length_m IS 'Cylinder length; 0 is allowed because TreeQSM output contains zero-length cylinders that other cylinders hang off';
COMMENT ON COLUMN trees.qsm_cylinders.branch_index IS 'Axis (branch) id from 1, by the lab''s single axis rule (the child with the longer supported subtree continues the axis), not the producing tool''s own id';
COMMENT ON COLUMN trees.qsm_cylinders.branch_order IS 'Axis order, 0 = trunk, by the same single axis rule';
COMMENT ON COLUMN trees.qsm_cylinders.branch_position IS 'Position along the axis, from 1 at its base';
