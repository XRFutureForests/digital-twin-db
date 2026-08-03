# CityGML / QSM Column Mapping

> **XRFF-264** — Step 0: column-by-column mapping from `trees.*` to the Ambarwari et al. (2024)
> CityGML UML, done before any migration so disagreements surface as edits to this doc instead
> of as schema churn. Feeds XRFF-265 (QSMs/QSMCylinders), XRFF-266 (TreePartTypes/TreeGraphEdges),
> XRFF-267 (LoD/3D geometry/TreeAssets).
>
> Source: Ambarwari, Suwardhi, Rani, Husni, Junaidy, Agirachman, Murtiyoso, Griess (2024),
> *Conceptual Model of Graph-based Individual Tree and Its Utilization in Digital Twin and
> Metaverse of Urban Forest*, ISPRS Archives XLVIII-4-2024:7-12,
> doi:10.5194/isprs-archives-xlviii-4-2024-7-2024. Figures 2 and 4 (UML diagrams) read directly
> from the PDF for this mapping; §3.1–3.4 (LoD, semantics, geometry, topology) for the prose
> definitions.

---

## 1. `SolitaryVegetationObject` base attributes → `trees.trees`

CityGML's base class (Figure 2) carries seven attributes plus geometry. The paper's own model
(Figure 4) does not change this base set — it only adds the Root/Trunk/Crown decomposition
underneath it.

| CityGML `SolitaryVegetationObject` | Type (paper's UML) | `trees.trees` column | Verdict |
|---|---|---|---|
| `class` | `gml::CodeType [0..1]` | — | **Gap**, see §2 |
| `function` | `gml::CodeType [0..*]` | — | **Gap**, see §2 |
| `usage` | `gml::CodeType [0..*]` | — | **Gap**, see §2 |
| `species` | `gml::CodeType [0..1]` | `species_id` → `shared.species` | Richer — normalised, GBIF-linked |
| `height` | `gml::LengthType [0..1]` | `height_m` | Direct |
| `trunkDiameter` | `gml::LengthType [0..1]` | `trees.stems.dbh_cm` (per stem) | Richer — CityGML has one trunk diameter per tree; multi-stem aggregation rule resolved in §7 |
| `crownDiameter` | `gml::LengthType [0..1]` | `crown_width_m` | Direct |
| `lod4Geometry` | `gml::Geometry [0..1]` | — | **Gap** — closed by XRFF-266/267 (cylinders) |
| `lod1-3ImplicitRepresentation` | `core::ImplicitGeometry [0..1]` | — | **Gap** — closed by XRFF-267 (`trees.treeassets`) |

## 2. `class` / `function` / `usage` — what these actually are

These are **not enumerated by the paper**. In the base CityGML `_VegetationObject` /
`SolitaryVegetationObject` class they are generic, open `gml::CodeType` attributes — CityGML's
standard mechanism for "a coded value from some dictionary," where the dictionary itself is left
to the implementer or a profile/ADE to define. Figure 2 and Figure 4 show them with identical,
unfilled-in type signatures at every level (`SolitaryVegetationObject`, `Root`, `Trunk`, `Crown`,
`Branch`, `Twig`, `Leaf` all repeat the same three attributes) — the paper explicitly says most
per-part attribute detail "is a work in progress" and defers the actual semantics to a future ADE.

So there is no fixed code list to adopt verbatim. What we need to decide is which of our existing
columns plays which role, and where the honest answer is "we don't have an equivalent yet":

| CityGML attribute | Intent (per CityGML 2.0 base spec) | Closest existing column | Fit |
|---|---|---|---|
| `class` | Broad category of the vegetation object (e.g. "deciduous tree", "conifer") | *none* — `species_id` is far more specific than `class` is meant to be | No good fit; leave unmapped rather than force it onto species |
| `function` | Purpose the object serves (e.g. "shade", "screening", "windbreak") | *none* | **True gap** — we don't record intended function anywhere |
| `usage` | Current actual use, may differ from `function` | *none* | **True gap** |

Two columns that look related but are **not** the same concept and should not be mapped here:

- `trees.trees.tree_status_id` (`shared.tree_status` lookup — alive/dead/etc.) describes
  *condition*, not class/function/usage.
- `trees.trees.crown_class_id` (`trees.crownclasses` — dominant/co-dominant/etc.) describes
  *competitive position*, not class/function/usage.

**Decision for this pass:** do not invent `class`/`function`/`usage` columns speculatively — CityGML
leaves them open-ended and we have no current consumer for them. The one place a code list is
concretely needed is the **part-level semantic label** (root/trunk/branch/twig/leaf/crown), which
is exactly what `trees.treeparttypes` (XRFF-266) is for — that is the CityGML *feature class*
distinction (`Root` vs `Trunk` vs `Branch`...), separate from the `class`/`function`/`usage`
attributes each feature class carries. If/when we publish a CityGML ADE (XRFF-270), `class` /
`function` / `usage` are where we'd register our own code lists; until then, note the gap and
move on.

## 3. Root / Trunk / Crown / Branch / Twig / Leaf → our schema

From Figure 4: `SolitaryVegetationObject` aggregates `Root`, `Trunk` and `Crown`. `Crown`
aggregates `Branch`; `Branch` aggregates `Twig`; `Twig` aggregates `Leaf`. Every part carries
`class`/`function`/`usage` (§2, unmapped); `Trunk` additionally carries `trunkLength`; `Branch`
additionally carries `branchLength`.

| CityGML feature | Paper's extra attributes | Our representation | Note |
|---|---|---|---|
| `Root` | — | **In scope** — `trees.roots` (proposed, §3.1) | No root geometry exists in our pipeline today, but that is a data-availability gap, not a scope decision — the schema should be classifiable now and geometrizable later (§3.1) |
| `Trunk` | `trunkLength` | `trees.stems` (`stem_height_m` ≈ `trunkLength`) **+** `trees.qsmcylinders` rows where `branch_order = 0` (XRFF-265) | Two representations at different resolutions: `trees.stems` is the per-tree allometric summary, `trees.qsmcylinders` is the measured geometry. Both are legitimate; they answer different questions |
| `Crown` | — | `trees.trees.crown_width_m`, `crown_base_height_m`, `crown_boundary` (aggregate); no dedicated Crown row; foliage density via `trees.crownfoliageprofiles` (proposed, §3.2) | Crown is implicit in our schema as "everything on the tree above `crown_base_height_m`," not a materialised entity. QSM cylinders with `branch_order >= 1` are the crown's measured woody content; §3.2 covers its foliage |
| `Branch` | `branchLength` | `trees.qsmcylinders` rows with `part_type_id = 'branch'`, `branch_order >= 1`; length is `sum(length_m)` along a `branch_index` run, not a stored column | Matches the paper's own construction (§3.3): trunk and branches are built from chained cylinders, not a single length attribute |
| `Twig` | — | `trees.qsmcylinders` rows with `part_type_id = 'twig'` | Distinguished from `Branch` by the `branch_order` + radius threshold rule, defined in XRFF-266: `branch_order = 0` → trunk; `branch_order >= 1 AND radius_m <= twig_radius` → twig; `branch_order >= 1 AND radius_m > twig_radius` → branch. `twig_radius` is the species-specific value from rTwig's own `twigs`/`twigs_index` reference database (the same value `run_rtwig(twig_radius = ...)` already used to correct that QSM), passed as `--twig-radius-mm` to `scripts/import/import_qsm.py` at ingest time -- not a stored/computed column, since the threshold is an import-time parameter rather than schema. Root/leaf/crown are never assigned from cylinder geometry. |
| `Leaf` | — | *none* (per-leaf geometry); density/distribution via `trees.crownfoliageprofiles` (§3.2) | QSM does not produce leaf geometry (Raumonen et al. 2013 QSM is a wood-only skeleton), and per-leaf storage stays out of scope — but the crown's foliage *density and distribution* is a well-studied, storable quantity distinct from per-leaf position (§3.2) |

### 3.1 Root — in scope, via Guerrero Iñiguez (2017)

Ambarwari et al. name this explicitly as open follow-on work (§5 of the paper, "Conclusions"):
*"further development, including coupling with the root model in Guerrero Iñiguez (2017)."*
That paper — Guerrero Iñiguez, J.I. (2017), *Geometric Modelling of Tree Roots with Different
Levels of Detail*, ISPRS Annals IV-4/W3:29–35, doi:10.5194/isprs-annals-iv-4-w3-29-2017 — is
open access and gives us a ready-made, CityGML-LoD-matched root model instead of an unscoped
gap:

- Three root system types, chosen to cover most species without going per-species: **tap root**,
  **heart-shaped root**, and **lateral (surface) roots**.
- Each type is modelled at multiple levels of geometric detail, from a coarse **simplified block
  model** (compatible with 2D/2.5D systems) up to a detailed **planar/surface-projected** 3D
  version — and the paper explicitly matches these detail levels to CityGML's own LoD ladder, the
  same one XRFF-267 already adopts (§5 of this doc).
- The paper is upfront that real root systems are "dynamic and almost opaque to direct
  observation," so it works with **generalized geometric approximations** by type, not
  per-tree measured geometry. That is exactly the situation we are in until a root data source
  exists (ground-penetrating radar, excavation — neither is in our pipeline today).

**Proposed `trees.roots`** (feeds XRFF-266, alongside `trees.treeparttypes` — `root` is already
one of its six values):

| Column | Type | Note |
|---|---|---|
| `root_id` | BIGSERIAL PK | |
| `tree_entity_id` | UUID | |
| `tree_id` | INTEGER FK → `trees.trees` | |
| `root_system_type_id` | SMALLINT FK → new lookup `trees.rootsystemtypes` | `tap_root` / `heart_root` / `lateral_root`, same lookup pattern as `trees.treeparttypes` — CSV in `data/lookups/` |
| `lod` | SMALLINT | Which of Guerrero's detail levels this row represents |
| `geometry_class` | TEXT | `implicit` (block model, LoD1–3) or `explicit` (surface-projected, LoD4) — mirrors the `trees.treeassets.geometry_class` decision in §5 |
| `root_depth_m`, `root_spread_radius_m` | NUMERIC | The block-model parameters; populated from the appropriate case whether classified or measured |
| `process_id` | INTEGER FK → `shared.processes` | How `root_system_type_id` was determined — see below |
| `source` | TEXT | `species_default` \| `field_observed` \| `measured` |

**What unblocks this today, with no new data collection:** root system type correlates
strongly with species and is documented in standard silvics references (root morphology is a
routine part of species silvics descriptions) — so `trees.rootsystemtypes` can be populated
per-`species_id` as a documented default (`source = 'species_default'`) now, geometry columns
left null until we have anything to measure. This is what turns Root from "no path" into
"classifiable now, geometrized later," which is the scope this section commits to.

### 3.2 Crown foliage density — vertical/horizontal distribution, not per-leaf position

QSM cannot see leaves, so per-leaf storage stays correctly out of scope (§3 table). But *how much
foliage, and where in the crown* is a separate, well-established forestry quantity — leaf area
density (LAD) as a function of relative position in the crown — with a real literature and real
parametric models, independent of per-leaf geometry:

- Le Port, Bosc, Champion & Loustau (2000), *Estimating the foliage area of Maritime pine (Pinus
  pinaster Aït.) branches and crowns with application to modelling the foliage area distribution
  in the crown*, Annals of Forest Science 57:11–22, doi:10.1051/forest:2000110. Fits **Beta
  probability density functions** to the vertical and horizontal foliage-area distribution inside
  the crown; parameters vary with tree/stand age, with foliage concentrated in the upper/outer
  crown for mature trees and lower/inner crown for young trees.
- Jeréz, Dean, Cao & Roberts (2005), *Describing Leaf Area Distribution in Loblolly Pine Trees
  with Johnson's SB Function*, Forest Science 51(2):93, doi:10.1093/forestscience/51.2.93. An
  alternative parametric distribution (Johnson's SB) for the same problem, for a different species.

Both fit the same shape of problem: a small number of distribution parameters (2–4 numbers)
describing where leaf area concentrates vertically and horizontally in the crown, driven by
species, age and competition — not a geometry table. This is directly usable by growpy/PVE's
existing procedural leaf-instancing path (the alignment doc §5 already notes leaves are
instanced on terminal twigs, not measured) — the difference is that instancing density becomes
**parameterised from a real fitted or literature distribution**, not an arbitrary default.

**Proposed `trees.crownfoliageprofiles`** (feeds XRFF-266):

| Column | Type | Note |
|---|---|---|
| `profile_id` | BIGSERIAL PK | |
| `tree_id` | INTEGER FK → `trees.trees` | |
| `process_id` | INTEGER FK → `shared.processes` | Which method/paper the distribution came from (register Le Port 2000 / Jeréz 2005 / a future in-house fit as processes, same pattern as TreeQSM) |
| `distribution_type` | TEXT | `beta` \| `johnson_sb` \| `uniform` (fallback default) |
| `vertical_params`, `horizontal_params` | NUMERIC[] | Distribution shape parameters (e.g. Beta's two shape parameters) |
| `total_leaf_area_m2` | NUMERIC | Whole-crown leaf area (LAI × crown projection area, or destructively/allometrically derived) |
| `source` | TEXT | `species_literature_default` \| `fitted` \| `measured` |

Same "classifiable now" argument as §3.1: species-level Beta or Johnson-SB parameters from the
literature are a legitimate `source = 'species_literature_default'` row today; nothing here
requires new field data collection before the table is useful.

## 4. Topology: `Node` / `Edge` → `trees.treegraphedges`

Figure 4 shows `Node`/`Edge` as a separate graph structure connected into the Root/Trunk/Crown/
Branch/Twig/Leaf hierarchy, with the diagram marking an `Edge` as relating exactly **2** `Node`s.
Per §3.4, each tree part is a node and relationships between parts are edges, "often generated
from point cloud data... using point and line geometry."

We get nodes for free — a QSM cylinder endpoint *is* a node — so only edges need a table
(`trees.treegraphedges`, XRFF-266). No separate `trees.nodes` table: materialising every cylinder
endpoint as its own row would duplicate `trees.qsmcylinders` for no query benefit PostgreSQL
doesn't already give us via the `cylinder_index`/`parent_cylinder_index` chain.

## 5. LoD ladder

Directly from §3.1 (Figure 5, after Tarsha Kurdi et al. 2024) — already captured verbatim in the
alignment doc and in XRFF-267's description. No new information from a closer read; confirms the
ladder as: LoD0 = 2D footprint · LoD1 = 2.5D height/root depth · LoD2 = crown + trunk ·
LoD3 = 3D morphological structure · LoD4 = internal detail (e.g. cavities) + structured semantics.

One clarification from §3.3 worth carrying into XRFF-267: the paper splits geometry by this same
boundary — **LoD1–LoD3 use implicit geometry** (a prototype instanced with a transform),
**LoD4 uses explicit geometry** (actual `gml::Geometry`, built from cylinders/cones per part).
Our procedural Nanite assemblies (growpy catalog, selected by species/height class) are implicit
in this sense — they're a prototype instanced per tree, not tree-specific geometry — so a
species-catalog-rendered tree is LoD2–LoD3 at best. A QSM-derived mesh, because it is that one
tree's actual measured geometry, is explicit and qualifies as LoD4.

**Decided:** `trees.treeassets` (XRFF-267) records a `geometry_class` column (`implicit` |
`explicit`) alongside `lod`, not just the LoD number — the number alone doesn't distinguish
"generic asset picked for this species" from "this tree's own geometry." The same `geometry_class`
column is reused on `trees.roots` (§3.1) for the identical implicit-block-model vs.
explicit-surface-projected distinction Guerrero Iñiguez's root model makes at the same LoD
boundary.

## 6. Geometry: cylinders and cones

§3.3 confirms the approach XRFF-265 already assumes: trunk and branches as chained cylinders with
differing start/end radii, twigs as a cylinder plus a terminal truncated cone, leaves as flat
polygons distributed on branches from point-cloud-derived placement. `trees.qsmcylinders`
(radius-only, no separate start/end radius pair) covers trunk/branch/twig directly; the paper's
"truncated cone" detail for twig tips is a rendering nicety our cylinder table doesn't need to
special-case — a very-short, tapering final cylinder segment already approximates it, and going
further is downstream (growpy/PVE) work, not a storage concern.

## 7. Open questions carried into XRFF-265–267

Most of what this mapping originally flagged as gaps are now resolved into proposed schema
(§3.1 `trees.roots`, §3.2 `trees.crownfoliageprofiles`, §5 `geometry_class`) — these three feed
into XRFF-266/267's acceptance criteria as new items, not just documentation. What remains open:

- **Multi-stem `trunkDiameter` aggregation — resolved, with a caveat.** CityGML's
  `trunkDiameter` is one value per tree; our `trees.stems.dbh_cm` is one value per stem. For any
  future CityGML export from a multi-stem tree, use the **quadratic aggregation**
  (`sqrt(sum(dbh_i^2))`) — this is the basal-area-preserving convention documented across
  USFS/ISA/FEMA-aligned urban forestry practice (NYSDEC Urban and Community Forestry Grant
  Program, *Tree Diameter Measurement* guidelines, lists it as "Method 1" of three accepted
  methods, alongside a straight average and a discouraged simple sum that double-counts trunk
  area). It is *not*, however, settled science: Magarik, Roman & Henning (2020), *How should we
  measure the DBH of multi-stemmed urban trees?*, Urban Forestry & Urban Greening 47:126481,
  doi:10.1016/j.ufug.2019.126481, found empirically that which aggregation convention is used
  barely affects predictive power for height/crown width, and argue for measuring at a single
  lower height instead of aggregating multiple stem diameters at all. **Decision:** adopt
  quadratic aggregation as our documented default for any exporter that needs a single
  `trunkDiameter`, cite both sources next to that code when it's written, and do not treat the
  choice as beyond dispute. No DB schema change — `trees.stems.dbh_cm` already holds what's
  needed; this only matters for a future CityGML exporter.
- `class` / `function` / `usage` (§2) are confirmed gaps with no proposed columns. Do not add
  speculative columns for them in XRFF-265–267; revisit only if XRFF-270 outreach or an actual
  ADE draft gives us a concrete code list to target.

---

## Related

- [`../../xr-future-forests-lab/obsidian/xr-future-forests-lab/03-DATA-TIER/citygml-qsm-alignment.md`](../../xr-future-forests-lab/obsidian/xr-future-forests-lab/03-DATA-TIER/citygml-qsm-alignment.md) — full design note (XRFF-264 parent)
- [database-schema.md](database-schema.md) — current schema data dictionary
- XRFF-265 — `trees.qsms` / `trees.qsmcylinders`
- XRFF-266 — `trees.treeparttypes` / `trees.treegraphedges`
- XRFF-267 — LoD field, `position_3d`, `trees.treeassets`
