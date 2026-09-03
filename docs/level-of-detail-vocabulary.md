# Level-of-Detail Vocabulary

**Issues:** XRFF-404 (this vocabulary), XRFF-267 (the `lod` fields it constrains),
XRFF-249 (position paper this feeds)
**Status:** Defined 2026-09-03. Normative for `digital-twin-db` and `growpy`.

"Level of detail" currently names at least three unrelated things across this stack,
and the ambiguity is already load-bearing: `trees.qsms.lod` and `trees.roots.lod`
exist, hold no rows, and carry no column comment, so either meaning could be written
into them without anyone noticing. This page fixes one meaning per axis and gives
each a distinct name.

Murtiyoso et al. 2023 identify exactly this as an unsolved cross-disciplinary
problem — forestry, geomatics and computer science each use "level of detail"
differently — and call for a formal definition so stakeholders can communicate. The
three axes below are that definition for our stack.

---

## The three axes

The axes are **orthogonal**. A tree can be rich on one and poor on another, and any
statement about "detail" that does not name an axis is ambiguous.

| Axis | Question it answers | Ladder | Where it lives |
|---|---|---|---|
| **Representation LoD** | How completely is the tree *described*? | CityGML LoD0–LoD4 | `digital-twin-db` |
| **Structural detail** | Which parts of the tree *exist* in the model? | pipeline-specific | `growpy` |
| **Render resolution** | How finely is existing geometry *tessellated*? | pipeline-specific | `growpy` → Unreal |

### 1. Representation LoD — the only axis that may be called "LoD"

The CityGML ladder, adopted in [citygml-qsm-mapping.md](citygml-qsm-mapping.md) §5
after Guerrero Iñiguez 2024 and Tarsha Kurdi et al. 2024:

* **LoD0** — 2D footprint
* **LoD1** — 2.5D height / root depth
* **LoD2** — crown + trunk as separable volumes
* **LoD3** — 3D morphological structure (branching architecture)
* **LoD4** — internal detail (cavities) plus structured semantics

Paired with `geometry_class`, which is not optional:

* `implicit` — a prototype instanced with a transform. A growpy catalog assembly
  picked by species and height class is implicit: it is a generic asset placed on
  this tree, not this tree's geometry. **LoD2–LoD3 at best.**
* `explicit` — this tree's own measured geometry. A QSM-derived mesh qualifies as
  **LoD4**.

The number alone cannot distinguish "generic asset chosen for this species" from
"this tree's actual shape", which is why both columns travel together.

**This is the meaning of every `lod` column in the database** — `trees.qsms.lod`,
`trees.roots.lod`, and `trees.treeassets.lod` when XRFF-267 lands. It is a
`SMALLINT` in 0..4. Nothing else may be written there.

### 2. Structural detail — which parts exist

Whether a branch, twig or leaf is *present in the model at all*. Not a rendering
concern: a structurally reduced tree has genuinely fewer parts, and its measured
crown metrics change accordingly.

Levers, all in growpy `quality.toml` / `forest.toml`:

* `build_cutoff_age`, `build_cutoff_thickness` — branches below the threshold are
  never built
* `skeleton_length`, `skeleton_reduce`, `skeleton_connected` — skeleton simplification
* twig cutoff and cutoff-recovery
* crown-density variants (the density ratchet)

Call this **structural detail**. Never "structural LOD", because it does not
subdivide the Representation LoD ladder — a structurally sparse tree is still LoD3
if its branching architecture is described.

### 3. Render resolution — how finely geometry is tessellated

Triangle budget for parts that already exist. Levers: `resolution`,
`resolution_reduce`, Nanite cluster LOD, USD LOD stages, static vs skeletal export.

Call this **render resolution**. Reserve the bare word "LOD" here only when talking
about Nanite's or USD's own mechanism, where it is that vendor's term — and write it
`Nanite LOD` / `USD LOD` so it is never mistaken for axis 1.

---

## Two conflations this vocabulary resolves

**`quality.toml` presets mix axes 2 and 3.** A single preset name sets both:

```toml
[quality.high]
resolution = 16              # axis 3 — tessellation
resolution_reduce = 0.5      # axis 3
build_cutoff_thickness = 0.0025   # axis 2 — which branches exist
skeleton_length = 1.0             # axis 2
```

So "quality = high" is not one statement, it is two, and they can be wanted
independently — a structurally complete tree at low tessellation is a perfectly
reasonable ask that the preset names cannot express. The presets are not renamed
here (they are a stable public interface), but any doc or issue describing them must
say which axis it means. A future split would put the two groups behind separate
keys.

**"Height-LOD ladder" (XRFF-324) is not an LOD on any axis.** It concerns which
*height classes* exist in the species catalog — whether a 35–45 m conifer can be
generated at all. That is a **catalog dimension** (species × height class × density
variant), constrained by triangle budget but not itself a detail level. Prefer
**height-class ladder**. The current name invites the reading that a 45 m tree is a
more detailed version of a 15 m tree, which it is not: it is a different tree.

---

## Naming rules

1. `LoD` (capital D), unqualified, means **Representation LoD** and nothing else.
   Every database `lod` column carries it, always paired with `geometry_class`.
2. Say **structural detail** for which parts exist. Never "structural LOD".
3. Say **render resolution** for tessellation. Write `Nanite LOD` / `USD LOD` when
   naming those specific mechanisms.
4. Say **height class** and **density variant** for catalog dimensions. Never
   "height LOD".
5. Any sentence containing "level of detail" without one of these qualifiers is a
   defect. Fix it rather than inferring the axis.

---

## Consequences

* **XRFF-267** — `trees.treeassets.lod` is `SMALLINT` 0..4 with the axis-1 meaning,
  plus `geometry_class`. Add `COMMENT ON COLUMN` to `trees.qsms.lod` and
  `trees.roots.lod` stating the same, so the currently empty columns cannot drift.
* **growpy** — [docs/architecture/](../../growpy/docs/architecture/) adopts the
  axis-2/axis-3 terms; a pointer to this page goes in the quality-preset docs.
* **XRFF-249** — the position paper can cite a worked three-axis scheme as a
  response to Murtiyoso et al.'s open call. That is a small citable contribution in
  its own right.

---

## References

* Murtiyoso et al. 2023 — the call for a formal forest-3D LoD definition. See
  `08-LITERATURE/virtual-forests-3d-data-review.md` in the vault.
* Guerrero Iñiguez 2024; Tarsha Kurdi et al. 2024 — the CityGML tree LoD ladder, via
  [citygml-qsm-mapping.md](citygml-qsm-mapping.md) §5.
