# Species Naming Audit: DB ↔ growpy ↔ UE

**Issue:** XRFF-236  
**Audited:** 2026-06-18  
**Files compared:**
- `data/lookups/species.csv` — DB canonical species list
- `d:\Git\growpy\config\tree_asset_lookup.csv` — growpy species registry

---

## How names flow through the pipeline

```
DB shared.species.common_name
  → HTTPS Blueprint query: species(common_name)
    → ST_TreeRow.species_name (string)
      → UE DataTable / PCG lookup key
        → growpy asset folder name (snake_case of growpy "Standardized Name")
```

UE resolves assets by converting `species_name` to snake_case via `standardize_species_name()`.  
growpy exports assets under its `Standardized Name` column (already snake_case).  
**A mismatch at any step causes wrong trees to spawn or a silent no-spawn.**

---

## Audit results

### ✅ Matching species (8/12)

| DB common_name | growpy Standardized Name | Scientific Name |
|---|---|---|
| European Beech | `european_beech` | Fagus sylvatica |
| Norway Spruce | `norway_spruce` | Picea abies |
| Silver Fir | `silver_fir` | Abies alba |
| Scots Pine | `scots_pine` | Pinus sylvestris |
| Douglas Fir | `douglas_fir` | Pseudotsuga menziesii |
| European Larch | `european_larch` | Larix decidua |
| Sycamore Maple | `sycamore_maple` | Acer pseudoplatanus |
| Wild Cherry | `wild_cherry` | Prunus avium |

---

### ❌ Mismatches and gaps (4 issues)

#### Issue 1 — Name collision: "Pedunculate Oak" vs "European Oak"
**Severity: Critical (Sept demo blocker)**

| Layer | Name | Standardized |
|---|---|---|
| DB | Pedunculate Oak | `pedunculate_oak` |
| growpy | European oak | `european_oak` |

Same species (Quercus robur, GBIF 2878688) but different common names. UE lookup fails.

**Fix:** Rename DB entry to **"European Oak"** to match growpy. SQL migration required for existing DB; CSV already updated in this PR.

---

#### Issue 2 — Ambiguous genus-level entry: "Birch"
**Severity: Medium**

| Layer | Name | Notes |
|---|---|---|
| DB | Birch | Betula spp. — genus level, no GBIF key |
| growpy | silver_birch | Betula pendula (GBIF 5334357) |
| growpy | downy_birch | Betula pubescens (also available) |

The Ecosense dataset uses `silver_birch` by species name convention. Genus-level "Birch" will not map.

**Fix:** Rename DB entry to **"Silver Birch"**, set scientific name to *Betula pendula*, add GBIF key 5334357. Any Ecosense trees currently recorded as "Birch" should be re-checked — most Ecosense birches are *Betula pendula*.

---

#### Issue 3 — Species in Ecosense dataset missing from DB: Common Ash + Small-leaved Linden
**Severity: High**

Both appear in growpy yield-table dataset files (`common_ash_merged.csv`, `small_leaved_linden_merged.csv`) and have UE assets, but are absent from `data/lookups/species.csv`.

| Species | Scientific Name | GBIF Key |
|---|---|---|
| Common Ash | Fraxinus excelsior | 5385657 |
| Small-leaved Linden | Tilia cordata | 2436527 |

**Fix:** Add both to `species.csv` (done in this update). Run `python src/growpy/utils/gbif_species.py --validate` to confirm GBIF keys after adding.

---

#### Issue 4 — DB species with no growpy model
**Severity: Low (not in Ecosense dataset)**

| DB common_name | GBIF Key | Notes |
|---|---|---|
| Norway Maple | 3189846 | No growpy model. Fallback: `field_maple` |
| Wild Service Tree | 3012567 (synonym) | No growpy model. Fallback: `rowan_mountain_ash` |

These species are not present in the current Ecosense tree inventory, so they do not block the Sept demo. A fallback must be defined in UE before adding inventory data that includes them.

---

## Fallback assignment convention

For DB species that have no matching growpy asset, UE should:
1. Log a `UE_LOG` warning: `"No asset for species '%s' — using fallback '%s'"`.
2. Use the fallback below:

| DB common_name | Fallback Asset |
|---|---|
| Norway Maple | `field_maple` |
| Wild Service Tree | `rowan_mountain_ash` |
| (any unknown) | `european_beech` (generic broadleaf placeholder) |

---

## Canonical naming convention (for future additions)

When adding a new species to the pipeline:

1. **DB `species.csv`**: Use the same English common name as the growpy `tree_asset_lookup.csv` `Common Name` column. Sentence-case: "European Beech", not "european beech" or "EUROPEAN BEECH".
2. **growpy `Standardized Name`**: snake_case of the common name — auto-derived by `standardize_species_name()`.
3. **UE asset folders**: Must match the growpy standardized name exactly.
4. **Anchor**: GBIF taxon key is the species identity anchor — use it for any cross-system joins.

---

## Required DB migration

After updating `species.csv`, apply this migration to any populated DB instance:

```sql
-- Fix: Pedunculate Oak → European Oak
UPDATE shared.species
SET common_name = 'European Oak'
WHERE common_name = 'Pedunculate Oak' AND scientific_name = 'Quercus robur';

-- Fix: Birch → Silver Birch
UPDATE shared.species
SET common_name   = 'Silver Birch',
    scientific_name = 'Betula pendula',
    gbif_key      = 5334357,
    gbif_accepted_name = 'Betula pendula'
WHERE common_name = 'Birch';

-- Add: Common Ash (run import_trees.py or insert directly)
-- Add: Small-leaved Linden (run import_trees.py or insert directly)
```

> Run `python scripts/import/import_species.py` (or equivalent) after resetting the DB — the updated `species.csv` handles fresh deployments automatically.

---

## Files changed

- `data/lookups/species.csv` — renamed entries, added Common Ash and Small-leaved Linden
- `data/lookups/species_gbif_validation.csv` — re-run `gbif_species.py --validate` to regenerate
