-- =============================================================================
-- Say what `lod` means, so the empty columns cannot drift
-- =============================================================================
-- XRFF-404. `trees.QSMs.lod` and `trees.Roots.lod` exist, hold no rows, and carry
-- no column comment. "Level of detail" names three unrelated things across this
-- stack -- how completely a tree is described, which of its parts exist, and how
-- finely those parts are tessellated -- so an uncommented empty `lod` could be
-- filled with any of the three and nobody would notice until the values
-- disagreed.
--
-- docs/level-of-detail-vocabulary.md fixes one meaning per axis and reserves the
-- word LoD for the first: the CityGML ladder, already adopted in
-- docs/citygml-qsm-mapping.md §5 after Guerrero Iniguez 2024 and Tarsha Kurdi et
-- al. 2024. This migration writes that meaning onto the columns themselves,
-- where a schema reader will actually find it. Comments only -- no data, no
-- types, no constraints change.
--
-- No CHECK (lod BETWEEN 0 AND 4) here. XRFF-267 is still to decide the final
-- shape of these tables and add `trees.TreeAssets.lod` alongside; the constraint
-- belongs with that change, applied to all three columns at once, rather than to
-- two of them now.
--
-- Mirrored to init 36-document-lod-columns.sql.
-- =============================================================================

SET search_path TO trees, public;

COMMENT ON COLUMN trees.qsms.lod IS
    'CityGML representation level of detail, 0-4: 0 = 2D footprint, 1 = 2.5D '
    'height/root depth, 2 = crown + trunk as separable volumes, 3 = 3D '
    'morphological structure, 4 = internal detail plus structured semantics. '
    'This is the ONLY meaning of "LoD" in this database. It is not a rendering '
    'resolution and not a count of which parts exist -- for those see the '
    'render-resolution and structural-detail axes in '
    'docs/level-of-detail-vocabulary.md (XRFF-404).';

COMMENT ON COLUMN trees.roots.lod IS
    'CityGML representation level of detail, 0-4; same ladder as trees.QSMs.lod. '
    'Read together with geometry_class: implicit = a prototype instanced with a '
    'transform (a generic asset placed on this tree), explicit = this tree''s own '
    'geometry. The number alone cannot tell those apart. See '
    'docs/level-of-detail-vocabulary.md (XRFF-404).';

COMMENT ON COLUMN trees.roots.geometry_class IS
    'implicit = prototype instanced with a transform, so LoD2-LoD3 at best; '
    'explicit = this tree''s own measured geometry, which is what qualifies a row '
    'as LoD4. Always interpreted alongside lod, never on its own. See '
    'docs/citygml-qsm-mapping.md §5.';
