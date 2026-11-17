#!/usr/bin/env python3
"""
Import Integrate+ marteloscopes from GBIF: trees and their microhabitats (XRFF-692).

Source: Spatially explicit database of tree related microhabitats (TreMs),
GBIF dataset 2e102194-f384-4712-89a4-5db7a3fc409a, doi 10.15468/ocof3v, CC BY 4.0.
Every tree of a marteloscope (about 1 ha, census) is one occurrence with
measurements: DBH, height, living/dead and the microhabitats it carries, as
Integrate+ 2016 codes (Kraus et al. 2016) with a count. Selection and mapping:
knowledge hub 03-DATA-TIER/open-data-microhabitats-soil-biodiversity.

Two steps, like import_pathfinder.py:

    python import_marteloscopes.py fetch     # GBIF API -> data/input/marteloscopes/gbif/<plot>.json
    python import_marteloscopes.py sql       # -> data/tmp/marteloscopes_import.sql

Apply the SQL as supabase_admin (Git Bash: prefix with MSYS_NO_PATHCONV=1):

    docker cp data/tmp/marteloscopes_import.sql dftdb-db:/tmp/mt.sql
    docker exec dftdb-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -f /tmp/mt.sql

The trees.microhabitat_types and microhabitat_source_codes lookups must be
loaded first (migration 20261117150000 + shared.refresh_all_lookups()).

Positions: GBIF gives each plot one centroid rounded to 0.001 degrees
(coordinateUncertaintyInMeters 500) and each tree local x/y in metres in
verbatimCoordinates, with a plot-specific origin. The trees are placed by
centring their local frame on the GBIF centroid in UTM 32N, x to the east and
y to the north. Distances between trees are exact; the absolute position is
off by up to about 500 m and the axis orientation is an assumption. Both are
recorded on the location and in every tree's source_attributes.

What lands where, per plot:
  shared.locations        one row; boundary = convex hull of the placed trees
  shared.campaigns        marteloscope_<plot>: field_inventory, CC-BY-4.0, GBIF DOI, public
  shared.sampling_designs integrateplus_marteloscope (census)
  shared.plots            <plot>_marteloscope (nominal 1 ha)
  shared.scenarios/variants natural_growth / baseline_<year> (type original)
  trees.trees + stems     source_tree_id = the producer's tree number
  trees.microhabitats     provenance 'reference', one row per tree x code
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
INPUT_DIR = REPO_ROOT / "data" / "input" / "marteloscopes" / "gbif"
DEFAULT_SQL = REPO_ROOT / "data" / "tmp" / "marteloscopes_import.sql"

DATASET_KEY = "2e102194-f384-4712-89a4-5db7a3fc409a"
DOI = "10.15468/ocof3v"
LICENCE = "CC-BY-4.0"
CREATED_BY = "import_marteloscopes"
DESIGN_NAME = "integrateplus_marteloscope"
UTM_EPSG = 32632  # WGS 84 / UTM 32N, as the other Black Forest sites
API = "https://api.gbif.org/v1"
MOF = "http://rs.tdwg.org/dwc/terms/MeasurementOrFact"
DWC = "http://rs.tdwg.org/dwc/terms/"

# location_name -> how the plot appears in the GBIF occurrenceID (<n>_IPlus_DE-<Plot>).
PLOTS = {
    "klosterwald": dict(gbif="Klosterwald", label="Klosterwald"),
    "rosskopf": dict(gbif="Rosskopf", label="Rosskopf"),
    "mooswald": dict(gbif="Mooswald", label="Mooswald"),
}


# --------------------------------------------------------------------------- fetch

def get(url: str) -> dict:
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                return json.load(r)
        except OSError:
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def fetch(plots: list[str]) -> None:
    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    citation = get(f"{API}/dataset/{DATASET_KEY}")["citation"]["text"]
    for loc in plots:
        name = PLOTS[loc]["gbif"]
        suffix = f"_IPlus_DE-{name}"
        rows, offset = [], 0
        while True:
            q = urllib.parse.urlencode(dict(datasetKey=DATASET_KEY, q=name, limit=300, offset=offset))
            page = get(f"{API}/occurrence/search?{q}")
            rows += [r for r in page["results"] if str(r.get("occurrenceID", "")).endswith(suffix)]
            offset += 300
            if page["endOfRecords"]:
                break
        trees = []
        for i, r in enumerate(rows, 1):
            v = get(f"{API}/occurrence/{r['key']}/verbatim")
            mof = [{k.split("/")[-1]: val for k, val in m.items()}
                   for m in (r.get("extensions") or {}).get(MOF, [])]
            trees.append(dict(
                gbif_key=r["key"], occurrence_id=r["occurrenceID"],
                tree_number=r["occurrenceID"].split("_")[0],
                scientific_name=r.get("species") or r.get("scientificName"),
                event_date=r.get("eventDate"), habitat=r.get("habitat"),
                latitude=r.get("decimalLatitude"), longitude=r.get("decimalLongitude"),
                coordinate_uncertainty_m=r.get("coordinateUncertaintyInMeters"),
                verbatim_coordinates=v.get(DWC + "verbatimCoordinates") or v.get("verbatimCoordinates"),
                verbatim_elevation=v.get(DWC + "verbatimElevation") or v.get("verbatimElevation"),
                measurements=mof))
            if i % 100 == 0:
                print(f"  {loc}: {i}/{len(rows)}")
        out = INPUT_DIR / f"{loc}.json"
        out.write_text(json.dumps(dict(dataset_key=DATASET_KEY, doi=DOI, citation=citation,
                                       fetched=time.strftime("%Y-%m-%d"), trees=trees),
                                  ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"  {loc}: {len(trees)} trees -> {out.relative_to(REPO_ROOT)}")


# ---------------------------------------------------------------------- parse

def num(v) -> float | None:
    try:
        return float(str(v).strip())
    except (TypeError, ValueError):
        return None


def parse_tree(t: dict) -> dict:
    """Measurements of one occurrence -> dbh, height, living, microhabitat codes."""
    out = dict(dbh=None, height=None, living=None, codes={})
    for m in t["measurements"]:
        kind, value = m.get("measurementType"), m.get("measurementValue")
        if kind == "Tree diameter":
            out["dbh"] = num(value)
        elif kind == "tree height":
            out["height"] = num(value)
        elif kind == "Tree status (dead or living)":
            out["living"] = {"1": True, "0": False}.get(str(value).strip())
        elif kind == "Tree related micro-habitat":
            code, n = str(m.get("measurementRemarks") or "").strip(), num(value)
            if not code or n is None or n < 1:
                raise SystemExit(f"{t['occurrence_id']}: bad microhabitat record {m}")
            out["codes"][code] = out["codes"].get(code, 0) + int(n)
    xy = (t.get("verbatim_coordinates") or "").split(",")
    if len(xy) != 2 or num(xy[0]) is None or num(xy[1]) is None:
        raise SystemExit(f"{t['occurrence_id']}: no local coordinates ({t.get('verbatim_coordinates')!r})")
    out["x"], out["y"] = num(xy[0]), num(xy[1])
    return out


# ---------------------------------------------------------------------- SQL

def lit(v) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return "'" + str(v).replace("'", "''") + "'"


def jlit(d: dict) -> str:
    d = {k: v for k, v in d.items() if v is not None}
    return "NULL" if not d else lit(json.dumps(d, ensure_ascii=False)) + "::jsonb"


def build_sql(plots: list[str]) -> tuple[str, list[str]]:
    out: list[str] = []
    report: list[str] = []
    w = out.append
    w("-- Generated by scripts/import/import_marteloscopes.py -- do not edit by hand.")
    w(f"-- Source: GBIF dataset {DATASET_KEY}, doi {DOI} ({LICENCE}).")
    w("\\set ON_ERROR_STOP on")
    w("BEGIN;")
    w("SET LOCAL search_path TO shared, trees, extensions, public;")
    w("SET LOCAL client_min_messages TO warning;")
    w("INSERT INTO shared.sampling_designs (design_name, strategy, protocol_name, protocol_version,")
    w("                                     dbh_measuring_height_m, min_dbh_cm, description)")
    w(f"VALUES ({lit(DESIGN_NAME)}, 'census', 'Integrate+ marteloscope', '2014-2016', 1.3, NULL,")
    w("        'Integrate+ marteloscope: every tree of an about 1 ha plot recorded with species, DBH, height, "
      "living/dead and tree-related microhabitats (Kraus et al. 2016 reference field list). The data paper "
      "states a 7.5 cm DBH threshold, but smaller trees occur in the records, so no minimum is set here.')")
    w("ON CONFLICT (design_name) DO UPDATE SET strategy = EXCLUDED.strategy, protocol_name = EXCLUDED.protocol_name,")
    w("    protocol_version = EXCLUDED.protocol_version, description = EXCLUDED.description;")

    # Every code must be in the lookup before anything is written; an unknown
    # code would otherwise drop out of the join silently.
    all_codes = {code for loc in plots
                 for t in json.loads((INPUT_DIR / f"{loc}.json").read_text(encoding="utf-8"))["trees"]
                 for code in parse_tree(t)["codes"]}
    w("DO $$ DECLARE missing text; BEGIN")
    w("  SELECT string_agg(u.c, ', ') INTO missing FROM unnest(ARRAY[" + ", ".join(lit(c) for c in sorted(all_codes)) +
      "]::text[]) AS u(c) WHERE NOT EXISTS (SELECT 1 FROM trees.microhabitat_source_codes s WHERE s.code = u.c);")
    w("  IF missing IS NOT NULL THEN RAISE EXCEPTION 'codes not in trees.microhabitat_source_codes: %', missing; END IF;")
    w("END $$;")

    for loc in plots:
        src = json.loads((INPUT_DIR / f"{loc}.json").read_text(encoding="utf-8"))
        trees = src["trees"]
        if not trees:
            raise SystemExit(f"{loc}: no trees in the input file")
        label = PLOTS[loc]["label"]
        parsed = [(t, parse_tree(t)) for t in trees]
        years = {str(t["event_date"])[:4] for t in trees}
        centroids = {(t["latitude"], t["longitude"]) for t in trees}
        if len(years) != 1 or len(centroids) != 1:
            raise SystemExit(f"{loc}: expected one survey year and one centroid, got {years} / {centroids}")
        year = int(years.pop())
        lat, lon = centroids.pop()
        habitat = trees[0].get("habitat")
        elevation = trees[0].get("verbatim_elevation")
        mx = sum(p["x"] for _, p in parsed) / len(parsed)
        my = sum(p["y"] for _, p in parsed) / len(parsed)
        ext_x = max(p["x"] for _, p in parsed) - min(p["x"] for _, p in parsed)
        ext_y = max(p["y"] for _, p in parsed) - min(p["y"] for _, p in parsed)
        campaign, variant, plot_name = f"marteloscope_{loc}", f"baseline_{year}", f"{loc}_marteloscope"
        date = f"{year}-01-01"
        georef = (f"Tree positions are the producer's local x/y in metres, centred on the GBIF plot centroid "
                  f"({lat}, {lon}; coordinate uncertainty 500 m) in UTM 32N with x east and y north. "
                  f"Distances between trees are exact; the absolute position and the axis orientation are assumptions.")
        # The centroid of the local frame goes to the GBIF centroid, in UTM.
        centre = f"ST_Transform(ST_SetSRID(ST_MakePoint({lon}, {lat}), 4326), {UTM_EPSG})"

        w("")
        w(f"-- ===================================================== {loc} ({label})")
        w("CREATE TEMP TABLE IF NOT EXISTS mt_stage_trees (source_tree_id text, tree_number integer, species text,")
        w("    dbh_cm numeric, height_m numeric, living boolean, x numeric, y numeric, attrs jsonb) ON COMMIT DROP;")
        w("TRUNCATE mt_stage_trees;")
        values = []
        for t, p in parsed:
            attrs = {"gbif_key": t["gbif_key"], "occurrence_id": t["occurrence_id"], "local_x_m": p["x"],
                     "local_y_m": p["y"], "living_raw": None if p["living"] is None else int(p["living"]),
                     "georeferencing": "local frame centred on the GBIF plot centroid (±500 m), x east, y north",
                     "protocol": DESIGN_NAME}
            values.append(f"({lit(t['tree_number'])}, {int(t['tree_number']) if t['tree_number'].isdigit() else 'NULL'}, "
                          f"{lit(t['scientific_name'])}, {lit(p['dbh'] if p['dbh'] and p['dbh'] > 0 else None)}, "
                          f"{lit(p['height'] if p['height'] and p['height'] > 0 else None)}, {lit(p['living'])}, "
                          f"{p['x'] - mx!r}, {p['y'] - my!r}, {jlit(attrs)})")
        w("INSERT INTO mt_stage_trees VALUES\n  " + ",\n  ".join(values) + ";")
        pts = f"(SELECT ST_Collect(ST_Translate({centre}, x, y)) FROM mt_stage_trees)"
        hull = f"ST_ConvexHull({pts})"

        w("INSERT INTO shared.locations (location_name, description, boundary, center_point, elevation_m, crs_epsg)")
        w(f"SELECT {lit(loc)},")
        w(f"       {lit(f'Integrate+ marteloscope {label} ({habitat}), surveyed {year}; census of about 1 ha with tree-related microhabitats per tree, GBIF doi {DOI}. Boundary is the convex hull of the trees. {georef}')},")
        w(f"       ST_Transform({hull}, 4326), ST_SetSRID(ST_MakePoint({lon}, {lat}), 4326),")
        w(f"       {lit(num(elevation))}, {UTM_EPSG}")
        w("ON CONFLICT (location_name) DO UPDATE SET description = EXCLUDED.description, boundary = EXCLUDED.boundary,")
        w("    center_point = EXCLUDED.center_point, elevation_m = EXCLUDED.elevation_m, crs_epsg = EXCLUDED.crs_epsg;")

        w("INSERT INTO shared.campaigns (campaign_name, campaign_type, location_id, start_date, description, methodology,")
        w("                              equipment, licence, access_level, citation, doi, created_by)")
        w(f"SELECT {lit(campaign)}, 'field_inventory', l.location_id, {lit(date)}::date,")
        w(f"       {lit(f'Integrate+ marteloscope {label}: tree inventory with microhabitats, {year}. The source gives the year only; the date is set to 1 January.')},")
        w("       'Census of all trees on an about 1 ha marteloscope: species, DBH (caliper), height (Vertex), living/dead, "
          "tree-related microhabitats after the Integrate+ reference field list (Kraus et al. 2016) with counts.',")
        w("       'Tree caliper; Vertex clinometer',")
        w(f"       {lit(LICENCE)}, 'public', {lit(src['citation'])}, {lit(DOI)}, {lit(CREATED_BY)}")
        w(f"  FROM shared.locations l WHERE l.location_name = {lit(loc)}")
        w("ON CONFLICT (campaign_name) DO UPDATE SET location_id = EXCLUDED.location_id, start_date = EXCLUDED.start_date,")
        w("    description = EXCLUDED.description, methodology = EXCLUDED.methodology, equipment = EXCLUDED.equipment,")
        w("    licence = EXCLUDED.licence, citation = EXCLUDED.citation, doi = EXCLUDED.doi;")

        fits_1ha = ext_x <= 110 and ext_y <= 110  # 1 ha plots; border trees stand a few metres out
        w("INSERT INTO shared.plots (location_id, plot_name, area_m2, boundary, center_point, sampling_design_id, area_source, description)")
        w(f"SELECT l.location_id, {lit(plot_name)}, {10000 if fits_1ha else 'NULL'},")
        w(f"       ST_Transform({hull}, 4326), ST_SetSRID(ST_MakePoint({lon}, {lat}), 4326),")
        w(f"       d.sampling_design_id, {lit('nominal' if fits_1ha else None)},")
        w(f"       {lit(f'Integrate+ marteloscope (nominal 1 ha); trees span {ext_x:.1f} x {ext_y:.1f} m. Boundary is the convex hull of the trees.')}")
        w(f"  FROM shared.locations l, shared.sampling_designs d")
        w(f" WHERE l.location_name = {lit(loc)} AND d.design_name = {lit(DESIGN_NAME)}")
        w("ON CONFLICT (location_id, plot_name) DO UPDATE SET area_m2 = EXCLUDED.area_m2, boundary = EXCLUDED.boundary,")
        w("    center_point = EXCLUDED.center_point, sampling_design_id = EXCLUDED.sampling_design_id,")
        w("    area_source = EXCLUDED.area_source, description = EXCLUDED.description;")

        w("INSERT INTO shared.scenarios (location_id, scenario_name, description)")
        w("SELECT l.location_id, 'natural_growth', 'Baseline field inventory developing under no active management (growth only).'")
        w(f"  FROM shared.locations l WHERE l.location_name = {lit(loc)}")
        w("ON CONFLICT (location_id, scenario_name) DO NOTHING;")
        w("INSERT INTO shared.variants (location_id, scenario_id, variant_type_id, variant_name, simulation_year, time_delta_yrs, sort_order, description)")
        w(f"SELECT l.location_id, s.scenario_id, vt.variant_type_id, {lit(variant)}, {year}, 0, 0,")
        w(f"       {lit(f'{label} marteloscope inventory, {year}')}")
        w("  FROM shared.locations l")
        w("  JOIN shared.scenarios s ON s.location_id = l.location_id AND s.scenario_name = 'natural_growth'")
        w("  JOIN shared.variant_types vt ON vt.variant_type_name = 'original'")
        w(f" WHERE l.location_name = {lit(loc)}")
        w("   AND NOT EXISTS (SELECT 1 FROM shared.variants v WHERE v.location_id = l.location_id")
        w(f"                                                  AND v.variant_name = {lit(variant)});")

        w("INSERT INTO trees.trees (location_id, plot_id, tree_number, campaign_id, scenario_id, variant_id, variant_type_id,")
        w("    species_id, tree_status_id, measurement_date, data_source_type_id, height_m, height_source, position,")
        w("    position_original, source_tree_id, source_attributes, created_by)")
        w("SELECT l.location_id, p.plot_id, st.tree_number, c.campaign_id, v.scenario_id, v.variant_id, v.variant_type_id,")
        w(f"       sp.species_id, CASE WHEN st.living = false THEN ts.tree_status_id END, {lit(date)}::date,")
        w("       ds.data_source_type_id, st.height_m, CASE WHEN st.height_m IS NOT NULL THEN 'measured' END,")
        w(f"       ST_Transform(ST_Translate({centre}, st.x, st.y), 4326), ST_MakePoint(st.x + {mx!r}, st.y + {my!r}),")
        w(f"       st.source_tree_id, st.attrs, {lit(CREATED_BY)}")
        w("  FROM mt_stage_trees st")
        w(f"  JOIN shared.locations l ON l.location_name = {lit(loc)}")
        w(f"  JOIN shared.plots p ON p.location_id = l.location_id AND p.plot_name = {lit(plot_name)}")
        w(f"  JOIN shared.campaigns c ON c.campaign_name = {lit(campaign)}")
        w(f"  JOIN shared.variants v ON v.location_id = l.location_id AND v.variant_name = {lit(variant)}")
        w("  JOIN trees.data_source_types ds ON ds.data_source_type_name = 'field'")
        w("  JOIN trees.tree_status ts ON ts.tree_status_name = 'dead'")
        w("  LEFT JOIN shared.species sp ON sp.scientific_name = st.species")
        w("ON CONFLICT (campaign_id, variant_id, source_tree_id) WHERE source_tree_id IS NOT NULL DO UPDATE SET")
        w("    plot_id = EXCLUDED.plot_id, tree_number = EXCLUDED.tree_number, species_id = EXCLUDED.species_id,")
        w("    tree_status_id = EXCLUDED.tree_status_id, measurement_date = EXCLUDED.measurement_date,")
        w("    position = EXCLUDED.position, position_original = EXCLUDED.position_original,")
        w("    source_attributes = EXCLUDED.source_attributes, height_m = EXCLUDED.height_m,")
        w("    height_source = EXCLUDED.height_source;")
        w("INSERT INTO trees.stems (tree_id, stem_number, dbh_cm)")
        w("SELECT t.tree_id, 1, st.dbh_cm")
        w("  FROM mt_stage_trees st")
        w(f"  JOIN shared.campaigns c ON c.campaign_name = {lit(campaign)}")
        w("  JOIN trees.trees t ON t.campaign_id = c.campaign_id AND t.source_tree_id = st.source_tree_id")
        w(" WHERE st.dbh_cm IS NOT NULL")
        w("ON CONFLICT (tree_id, stem_number) DO UPDATE SET dbh_cm = EXCLUDED.dbh_cm;")

        mvals = []
        for t, p in parsed:
            for code, n in sorted(p["codes"].items()):
                mvals.append(f"({lit(t['tree_number'])}, {lit(code)}, {n}, "
                             f"{jlit({'gbif_key': t['gbif_key'], 'code_raw': code, 'count_raw': n})})")
        if mvals:
            w("CREATE TEMP TABLE IF NOT EXISTS mt_stage_mh (source_tree_id text, code text, n integer, attrs jsonb) ON COMMIT DROP;")
            w("TRUNCATE mt_stage_mh;")
            w("INSERT INTO mt_stage_mh VALUES\n  " + ",\n  ".join(mvals) + ";")
            w("INSERT INTO trees.microhabitats (tree_id, microhabitat_type_id, source_code_id, count, provenance,")
            w("    campaign_id, observation_date, source_attributes, created_by)")
            w("SELECT t.tree_id, mt.microhabitat_type_id, sc.source_code_id, sm.n, 'reference', c.campaign_id,")
            w(f"       {lit(date)}::date, sm.attrs, {lit(CREATED_BY)}")
            w("  FROM mt_stage_mh sm")
            w(f"  JOIN shared.campaigns c ON c.campaign_name = {lit(campaign)}")
            w("  JOIN trees.trees t ON t.campaign_id = c.campaign_id AND t.source_tree_id = sm.source_tree_id")
            w("  JOIN trees.microhabitat_source_codes sc ON sc.code = sm.code")
            w("  LEFT JOIN trees.microhabitat_types mt ON mt.type_number = sc.type_number")
            w("ON CONFLICT (tree_id, provenance, source_code_id) DO UPDATE SET")
            w("    microhabitat_type_id = EXCLUDED.microhabitat_type_id, count = EXCLUDED.count,")
            w("    campaign_id = EXCLUDED.campaign_id, observation_date = EXCLUDED.observation_date,")
            w("    source_attributes = EXCLUDED.source_attributes;")

        n_mh = sum(len(p["codes"]) for _, p in parsed)
        n_dead = sum(1 for _, p in parsed if p["living"] is False)
        species = sorted({t["scientific_name"] for t in trees})
        report.append(f"{loc}: {len(trees)} trees ({n_dead} dead), {n_mh} tree x microhabitat rows, "
                      f"{sum(sum(p['codes'].values()) for _, p in parsed)} microhabitats; extent {ext_x:.1f} x {ext_y:.1f} m; "
                      f"species {species}")
        w("DO $$ DECLARE n integer; m integer; BEGIN")
        w(f"  SELECT count(*) INTO n FROM trees.trees t JOIN shared.campaigns c ON c.campaign_id = t.campaign_id WHERE c.campaign_name = {lit(campaign)};")
        w(f"  IF n <> {len(trees)} THEN RAISE EXCEPTION '{loc}: % trees in the database, {len(trees)} in GBIF', n; END IF;")
        w(f"  SELECT count(*) INTO m FROM trees.microhabitats mh JOIN shared.campaigns c ON c.campaign_id = mh.campaign_id WHERE c.campaign_name = {lit(campaign)};")
        w(f"  IF m <> {n_mh} THEN RAISE EXCEPTION '{loc}: % microhabitat rows in the database, {n_mh} in GBIF', m; END IF;")
        w(f"  SELECT count(*) INTO n FROM trees.trees t JOIN shared.campaigns c ON c.campaign_id = t.campaign_id WHERE c.campaign_name = {lit(campaign)} AND t.species_id IS NULL;")
        w(f"  IF n > 0 THEN RAISE EXCEPTION '{loc}: % trees without a species_id (add the species to data/lookups/species.csv)', n; END IF;")
        w("END $$;")

    w("")
    w("SELECT l.location_name, count(DISTINCT t.tree_id) AS trees, count(DISTINCT m.microhabitat_id) AS microhabitat_rows,")
    w("       coalesce(sum(m.count), 0) AS microhabitats")
    w("  FROM shared.locations l JOIN trees.trees t ON t.location_id = l.location_id")
    w("  LEFT JOIN trees.microhabitats m ON m.tree_id = t.tree_id")
    w(" WHERE l.location_name IN (" + ", ".join(lit(x) for x in plots) + ")")
    w(" GROUP BY 1 ORDER BY 1;")
    w("COMMIT;")
    return "\n".join(out) + "\n", report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("command", choices=["fetch", "sql"])
    ap.add_argument("--plots", nargs="*", default=list(PLOTS), choices=list(PLOTS),
                    help="location names to process (default: all three)")
    ap.add_argument("--out", type=Path, default=DEFAULT_SQL, help="SQL file to write (sql)")
    args = ap.parse_args()

    if args.command == "fetch":
        fetch(args.plots)
        return 0

    sql, report = build_sql(args.plots)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(sql, encoding="utf-8")
    for line in report:
        print("  " + line)
    print(f"  wrote {args.out.relative_to(REPO_ROOT) if args.out.is_relative_to(REPO_ROOT) else args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
