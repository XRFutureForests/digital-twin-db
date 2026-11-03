#!/usr/bin/env python3
"""
Import Pathfinder superplots (field inventory only) as new locations.

The PathFinder superplots (doi 10.5281/zenodo.20623034, CC BY 4.0) are 0.25 ha
census plots in six European countries with trees, deadwood and regeneration,
measured 2023-2024 beside mobile laser scans. Owner decision 2026-11-03: five of
them become database and Unreal sites, inventory only, never the point clouds.
Selection and mapping: knowledge hub 03-DATA-TIER/3dtrees-inventory-datasets and
03-DATA-TIER/3dtrees-db-adjustment-plan (XRFF-641).

Two steps:

    python import_pathfinder.py fetch          # field_data GeoPackages -> data/input/pathfinder/
    python import_pathfinder.py sql            # -> data/tmp/pathfinder_import.sql

`fetch` reads only the small `field_data/*.gpkg` members out of the country
ZIPs on Zenodo (1.7-15.7 GB each, mostly point clouds) by HTTP range requests.

`sql` writes one idempotent SQL file keyed on natural keys (location name,
campaign name, the producer's ids), so the same file loads the same rows into
any instance whatever its serial ids. Apply it as supabase_admin:

    docker cp data/tmp/pathfinder_import.sql dftdb-db:/tmp/pf.sql
    docker exec dftdb-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -f /tmp/pf.sql

(Git Bash: prefix both with MSYS_NO_PATHCONV=1.) Then fill the heights that
were not measured (fill_missing_heights.py) and biomass (fill_missing_biomass.py
--location <name>).

What lands where, per site:
  shared.locations        one row; crs_epsg = the GeoPackage's CRS; boundary = the plot
  shared.campaigns        pathfinder_<site>: field_inventory, CC-BY-4.0, DOI, public
  shared.sampling_designs pathfinder_superplot (census; minimum DBH not stated in the record)
  shared.plots            <site>_superplot (the plot polygon)
  shared.scenarios/variants natural_growth / baseline_<year> (type original)
  trees.trees + stems     source_tree_id = Pathfinder tree_id; codes in source_attributes
  forest_floor.deadwood   standing, stump, lying (line geometry, length, volume)
  forest_floor.regeneration saplings and seedlings, counts per species, on the superplot
                          with their survey area (survey_area_m2)
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sqlite3
import struct
import sys
import urllib.request
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
INPUT_DIR = REPO_ROOT / "data" / "input" / "pathfinder"
DEFAULT_SQL = REPO_ROOT / "data" / "tmp" / "pathfinder_import.sql"

ZENODO_RECORD = "20623034"
ZENODO_FILE = "https://zenodo.org/api/records/" + ZENODO_RECORD + "/files/{country}.zip/content"
DOI = "10.5281/zenodo.20623034"
LICENCE = "CC-BY-4.0"
CITATION = ("Pathfinder superplots (2026). Field inventory, deadwood, regeneration and mobile laser "
            "scanning of 27 European superplots, 2023-2024. Zenodo. https://doi.org/10.5281/zenodo.20623034")
CREATED_BY = "import_pathfinder"

LAYERS = ["trees", "plot_boundaries", "standingDeadwood", "lyingDeadwood", "deadwood_lines",
          "unclassifiedDeadwood", "saplings", "seedlings"]

# location_name -> how the site appears in the Pathfinder files and on 3Dtrees.earth.
# measurement_date: the scan date 3Dtrees.earth gives for the scene (estimated by the
# producer, see INGESTION_DATE_ESTIMATES.txt); the field visit is not dated in the tables.
SITES = {
    "tratice": dict(country="Slovenia", site="tratice", label="Tratice",
                    threedtrees_id=3604, date="2023-10-20"),
    "krucmanove": dict(country="Slovenia", site="krucmanove", label="Krucmanove",
                       threedtrees_id=3603, date="2023-09-29"),
    "goettingen2": dict(country="Germany", site="goettingen2", label="Göttingen 2",
                        threedtrees_id=3592, date="2024-08-15"),
    "valsain": dict(country="Spain", site="valsain", label="Valsaín",
                    threedtrees_id=3608, date="2024-03-06"),
    "vallombrosa_douglas": dict(country="Italy", site="VallombrosaDouglas",
                                label="Vallombrosa Douglasia", threedtrees_id=3595,
                                date="2024-02-14"),
}

DESIGN_NAME = "pathfinder_superplot"

WOOD_TYPE = {"standing": "standing", "stump": "stump", "lying": "fallen"}


# --------------------------------------------------------------------------- fetch

class _HttpRangeFile(io.RawIOBase):
    """A seekable read-only file over HTTP range requests (enough for zipfile)."""

    def __init__(self, url: str):
        self.url, self.pos = url, 0
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD")) as r:
            self.size = int(r.headers["Content-Length"])

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        if n == 0 or self.pos >= self.size:
            return b""
        end = min(self.pos + n, self.size) - 1
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
        with urllib.request.urlopen(req) as r:
            data = r.read()
        self.pos += len(data)
        return data

    def readinto(self, b):
        d = self.read(len(b))
        b[: len(d)] = d
        return len(d)


def fetch(countries: set[str]) -> None:
    for country in sorted(countries):
        target = INPUT_DIR / country
        target.mkdir(parents=True, exist_ok=True)
        url = ZENODO_FILE.format(country=country)
        z = zipfile.ZipFile(io.BufferedReader(_HttpRangeFile(url), buffer_size=1 << 20))
        got = 0
        for info in z.infolist():
            name = info.filename
            if not name.startswith("field_data/") or not name.endswith(".gpkg"):
                continue
            (target / Path(name).name).write_bytes(z.read(info))
            got += 1
        print(f"  {country}: {got} GeoPackages -> {target.relative_to(REPO_ROOT)}")


# ----------------------------------------------------------------------- read

def gpkg_wkb(blob: bytes) -> tuple[int, bytes] | None:
    """Split a GeoPackage geometry blob into (srs_id, WKB)."""
    if blob is None or blob[:2] != b"GP":
        return None
    flags = blob[3]
    endian = "<" if flags & 1 else ">"
    srs_id = struct.unpack(endian + "i", blob[4:8])[0]
    env_bytes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[(flags >> 1) & 7]
    if flags & 0x10:  # empty geometry
        return None
    return srs_id, blob[8 + env_bytes:]


def read_layer(country: str, layer: str) -> list[dict]:
    path = INPUT_DIR / country / f"{layer}_{country}.gpkg"
    if not path.exists():
        return []
    con = sqlite3.connect(path)
    con.row_factory = sqlite3.Row
    table = con.execute("SELECT table_name FROM gpkg_contents").fetchone()[0]
    geom_col = con.execute("SELECT column_name FROM gpkg_geometry_columns").fetchone()[0]
    rows = []
    for r in con.execute(f'SELECT * FROM "{table}"'):
        d = dict(r)
        g = gpkg_wkb(d.pop(geom_col, None))
        d["_srs"], d["_wkb"] = (g if g else (None, None))
        rows.append(d)
    con.close()
    return rows


def site_rows(rows: list[dict], site: str, key: str = "site") -> list[dict]:
    return [r for r in rows if str(r.get(key) or "").lower() == site.lower()]


# ------------------------------------------------------------------- cleaning

def norm_species(raw) -> str | None:
    """'26.004.001-PICEA ABIES ', 'Picea_abies', 'fagus sylvatica' -> 'Picea abies'."""
    if raw is None:
        return None
    s = str(raw).strip()
    if s in ("", "<NA>", "nan", "None"):
        return None
    s = re.sub(r"^[\d.]+-", "", s).replace("_", " ").strip()
    s = re.sub(r"\s+", " ", s)
    parts = s.split(" ")
    if len(parts) < 2:
        return None
    return parts[0].capitalize() + " " + " ".join(p.lower() for p in parts[1:])


def num(v) -> float | None:
    if v is None:
        return None
    try:
        f = float(str(v).strip())
    except ValueError:
        return None
    return f


def code(v) -> str | None:
    """Protocol codes as delivered, '1.0' -> '1'; '<NA>' -> None."""
    if v is None:
        return None
    s = str(v).strip()
    if s in ("", "<NA>", "nan", "None"):
        return None
    if re.fullmatch(r"-?\d+\.0", s):
        s = s[:-2]
    return s


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


def geom_sql(srs: int | None, wkb: bytes | None, to_4326: bool = True) -> str:
    if wkb is None or srs is None:
        return "NULL"
    g = f"ST_Force2D(ST_SetSRID(ST_GeomFromWKB(decode('{wkb.hex()}', 'hex')), {srs}))"
    return f"ST_Transform({g}, 4326)" if to_4326 else g


def build_sql(selected: list[str]) -> tuple[str, list[str]]:
    out: list[str] = []
    report: list[str] = []
    w = out.append

    w("-- Generated by scripts/import/import_pathfinder.py -- do not edit by hand.")
    w(f"-- Source: Pathfinder superplots, doi {DOI} ({LICENCE}); field_data GeoPackages only.")
    w("\\set ON_ERROR_STOP on")
    w("BEGIN;")
    w("SET LOCAL search_path TO shared, trees, forest_floor, extensions, public;")
    w("SET LOCAL client_min_messages TO warning;")
    w("")
    w("INSERT INTO shared.sampling_designs (design_name, strategy, protocol_name, protocol_version,")
    w("                                     dbh_measuring_height_m, min_dbh_cm, description)")
    w(f"VALUES ({lit(DESIGN_NAME)}, 'census', 'PathFinder superplot protocol', '2023-2024', 1.3, NULL,")
    w("        'PathFinder superplots: every tree of a 0.25 ha plot recorded (census). The minimum recorded DBH is "
      "not stated in the Zenodo record; the smallest DBH in _plot_metrics.csv is the smallest tree measured, not a "
      "threshold. Regeneration on subplots (saplings, seedlings).')")
    w("ON CONFLICT (design_name) DO UPDATE SET strategy = EXCLUDED.strategy, protocol_name = EXCLUDED.protocol_name,")
    w("    protocol_version = EXCLUDED.protocol_version, description = EXCLUDED.description;")

    layers: dict[str, dict[str, list[dict]]] = {}
    for loc in selected:
        s = SITES[loc]
        country = s["country"]
        if country not in layers:
            layers[country] = {layer: read_layer(country, layer) for layer in LAYERS}
        L = layers[country]
        site = s["site"]

        plot = site_rows(L["plot_boundaries"], site, key="plot_name")
        if len(plot) != 1:
            raise SystemExit(f"{loc}: expected one plot polygon for '{site}', found {len(plot)}")
        plot = plot[0]
        srs = plot["_srs"]
        # plot_boundaries holds single-part MULTIPOLYGONs; the boundary columns are Polygon.
        poly_local = f"ST_GeometryN(ST_Multi({geom_sql(srs, plot['_wkb'], to_4326=False)}), 1)"
        label, tdid = s["label"], s["threedtrees_id"]
        trees = site_rows(L["trees"], site)
        if not trees:
            raise SystemExit(f"{loc}: no trees for '{site}' in {country}")
        year = int(s["date"][:4])
        variant_name = f"baseline_{year}"
        campaign = f"pathfinder_{loc}"
        eu_cat = plot.get("EU_for_cat")

        w("")
        w(f"-- ===================================================== {loc} ({s['label']}, {country})")
        w("INSERT INTO shared.locations (location_name, description, boundary, center_point, crs_epsg)")
        w(f"SELECT {lit(loc)},")
        w(f"       {lit(f'PathFinder superplot {label} ({country}), European forest category {eu_cat}; 0.25 ha census plot measured with mobile laser scanning 2023-2024 (3Dtrees.earth dataset {tdid}). Field inventory only.')},")
        w(f"       ST_Transform({poly_local}, 4326),")
        w(f"       ST_Transform(ST_Centroid({poly_local}), 4326), {srs}")
        w("ON CONFLICT (location_name) DO UPDATE SET description = EXCLUDED.description, boundary = EXCLUDED.boundary,")
        w("    center_point = EXCLUDED.center_point, crs_epsg = EXCLUDED.crs_epsg;")

        w("INSERT INTO shared.campaigns (campaign_name, campaign_type, location_id, start_date, description, methodology,")
        w("                              equipment, licence, access_level, citation, doi, created_by)")
        w(f"SELECT {lit(campaign)}, 'field_inventory', l.location_id, {lit(s['date'])}::date,")
        w(f"       {lit(f'PathFinder superplot field inventory, site {site} ({country}). Date estimated by the producer (scan date).')},")
        w("       'Census of all trees on a 0.25 ha plot (species, DBH at 1.3 m, height on a subset, canopy layer, position); "
          "standing and lying deadwood on the whole plot; saplings and seedlings on subplots. PathFinder superplot protocol.',")
        w("       'Field instruments; GeoSLAM ZEB Horizon mobile laser scanner (scans not imported)',")
        w(f"       {lit(LICENCE)}, 'public', {lit(CITATION)}, {lit(DOI)}, {lit(CREATED_BY)}")
        w(f"  FROM shared.locations l WHERE l.location_name = {lit(loc)}")
        w("ON CONFLICT (campaign_name) DO UPDATE SET location_id = EXCLUDED.location_id, start_date = EXCLUDED.start_date,")
        w("    description = EXCLUDED.description, methodology = EXCLUDED.methodology, equipment = EXCLUDED.equipment,")
        w("    licence = EXCLUDED.licence, citation = EXCLUDED.citation, doi = EXCLUDED.doi;")

        # Plots: the superplot, and regeneration subplots under it.
        w("INSERT INTO shared.plots (location_id, plot_name, area_m2, boundary, center_point, sampling_design_id, area_source, description)")
        w(f"SELECT l.location_id, {lit(loc + '_superplot')}, round(ST_Area({poly_local})::numeric, 2),")
        w(f"       ST_Transform({poly_local}, 4326), ST_Transform(ST_Centroid({poly_local}), 4326),")
        w(f"       d.sampling_design_id, 'nominal', 'PathFinder superplot (0.25 ha census plot) as delivered in plot_boundaries.'")
        w(f"  FROM shared.locations l, shared.sampling_designs d")
        w(f" WHERE l.location_name = {lit(loc)} AND d.design_name = {lit(DESIGN_NAME)}")
        w("ON CONFLICT (location_id, plot_name) DO UPDATE SET area_m2 = EXCLUDED.area_m2, boundary = EXCLUDED.boundary,")
        w("    center_point = EXCLUDED.center_point, sampling_design_id = EXCLUDED.sampling_design_id,")
        w("    area_source = EXCLUDED.area_source, description = EXCLUDED.description;")

        saplings = site_rows(L["saplings"], site)
        seedlings = site_rows(L["seedlings"], site)
        plot_area = float(plot.get("area_m2") or 0)
        # Regeneration survey areas stay on the tallies (survey_area_m2), not as
        # subplots: a plot with an area of its own would be a tree sample unit.
        survey_area = {}
        if saplings:
            areas = {round(float(r["survey_area_ha"]) * 10000, 2) for r in saplings if num(r.get("survey_area_ha"))}
            if len(areas) != 1:
                raise SystemExit(f"{loc}: saplings survey areas {areas}")
            survey_area["sapling"] = areas.pop()
        if seedlings:
            areas = {round(float(r["site_survey_area_m2"]), 2) for r in seedlings if num(r.get("site_survey_area_m2"))}
            if len(areas) != 1:
                raise SystemExit(f"{loc}: seedlings survey areas {areas}")
            a = areas.pop()
            survey_area["seedling"] = None if abs(a - plot_area) < 50 else a

        # Scenario and baseline variant (as scripts/seed/*_baseline_variant.sql do per site).
        w("INSERT INTO shared.scenarios (location_id, scenario_name, description)")
        w("SELECT l.location_id, 'natural_growth', 'Baseline field inventory developing under no active management (growth only).'")
        w(f"  FROM shared.locations l WHERE l.location_name = {lit(loc)}")
        w("ON CONFLICT (location_id, scenario_name) DO NOTHING;")
        w("INSERT INTO shared.variants (location_id, scenario_id, variant_type_id, variant_name, simulation_year, time_delta_yrs, sort_order, description)")
        w(f"SELECT l.location_id, s.scenario_id, vt.variant_type_id, {lit(variant_name)}, {year}, 0, 0,")
        w(f"       {lit(f'{label} PathFinder field inventory, {year}')}")
        w("  FROM shared.locations l")
        w("  JOIN shared.scenarios s ON s.location_id = l.location_id AND s.scenario_name = 'natural_growth'")
        w("  JOIN shared.variant_types vt ON vt.variant_type_name = 'original'")
        w(f" WHERE l.location_name = {lit(loc)}")
        w("   AND NOT EXISTS (SELECT 1 FROM shared.variants v WHERE v.location_id = l.location_id")
        w(f"                                                  AND v.variant_name = {lit(variant_name)});")

        # Trees: stage, upsert on (campaign, variant, source_tree_id), then stems.
        w("CREATE TEMP TABLE IF NOT EXISTS pf_stage_trees (source_tree_id text, tree_number integer, species text,")
        w("    dbh_cm numeric, height_m numeric, geom_local geometry, source_crs integer, attrs jsonb) ON COMMIT DROP;")
        w("TRUNCATE pf_stage_trees;")
        n_h = 0
        values = []
        for r in trees:
            sid = code(r.get("tree_id"))
            if sid is None:
                raise SystemExit(f"{loc}: tree without tree_id")
            sp = norm_species(r.get("species"))
            h = num(r.get("height_m"))
            if h is not None and h <= 0:
                h = None
            n_h += h is not None
            dbh = num(r.get("dbh_cm"))
            if dbh is not None and dbh <= 0:
                dbh = None
            attrs = {"canopy_layer": code(r.get("canopy_layer")), "rs_visibility": code(r.get("rs_visibility")),
                     "live_dead_code": code(r.get("live_dead_code")), "species_raw": r.get("species"),
                     "protocol": "pathfinder_superplot"}
            values.append(f"({lit(sid)}, {int(sid) if sid.isdigit() else 'NULL'}, {lit(sp)}, {lit(dbh)}, {lit(h)}, "
                          f"{geom_sql(r['_srs'], r['_wkb'], to_4326=False)}, {r['_srs'] or 'NULL'}, {jlit(attrs)})")
        w("INSERT INTO pf_stage_trees VALUES\n  " + ",\n  ".join(values) + ";")
        w("INSERT INTO trees.trees (location_id, plot_id, tree_number, campaign_id, scenario_id, variant_id, variant_type_id,")
        w("    species_id, measurement_date, data_source_type_id, height_m, height_source, position, position_original,")
        w("    source_crs, source_tree_id, source_attributes, created_by)")
        w(f"SELECT l.location_id, p.plot_id, st.tree_number, c.campaign_id, v.scenario_id, v.variant_id, v.variant_type_id,")
        w(f"       sp.species_id, {lit(s['date'])}::date, ds.data_source_type_id, st.height_m,")
        w("       CASE WHEN st.height_m IS NOT NULL THEN 'measured' END,")
        w("       ST_Transform(st.geom_local, 4326), st.geom_local, st.source_crs, st.source_tree_id, st.attrs, " + lit(CREATED_BY))
        w("  FROM pf_stage_trees st")
        w(f"  JOIN shared.locations l ON l.location_name = {lit(loc)}")
        w(f"  JOIN shared.plots p ON p.location_id = l.location_id AND p.plot_name = {lit(loc + '_superplot')}")
        w(f"  JOIN shared.campaigns c ON c.campaign_name = {lit(campaign)}")
        w(f"  JOIN shared.variants v ON v.location_id = l.location_id AND v.variant_name = {lit(variant_name)}")
        w("  JOIN trees.data_source_types ds ON ds.data_source_type_name = 'field'")
        w("  LEFT JOIN shared.species sp ON sp.scientific_name = st.species")
        w("ON CONFLICT (campaign_id, variant_id, source_tree_id) WHERE source_tree_id IS NOT NULL DO UPDATE SET")
        w("    plot_id = EXCLUDED.plot_id, tree_number = EXCLUDED.tree_number, species_id = EXCLUDED.species_id,")
        w("    measurement_date = EXCLUDED.measurement_date, position = EXCLUDED.position,")
        w("    position_original = EXCLUDED.position_original, source_crs = EXCLUDED.source_crs,")
        w("    source_attributes = EXCLUDED.source_attributes,")
        w("    height_m = coalesce(EXCLUDED.height_m, trees.trees.height_m),")
        w("    height_source = CASE WHEN EXCLUDED.height_m IS NOT NULL THEN 'measured' ELSE trees.trees.height_source END;")
        w("INSERT INTO trees.stems (tree_id, stem_number, dbh_cm)")
        w("SELECT t.tree_id, 1, st.dbh_cm")
        w("  FROM pf_stage_trees st")
        w(f"  JOIN shared.campaigns c ON c.campaign_name = {lit(campaign)}")
        w("  JOIN trees.trees t ON t.campaign_id = c.campaign_id AND t.source_tree_id = st.source_tree_id")
        w(" WHERE st.dbh_cm IS NOT NULL")
        w("ON CONFLICT (tree_id, stem_number) DO UPDATE SET dbh_cm = EXCLUDED.dbh_cm;")
        species_in = {norm_species(r.get("species")) for r in trees}
        report.append(f"{loc}: {len(trees)} trees ({n_h} with height), species {sorted(x for x in species_in if x)}")

        # Deadwood.
        lines_by_id = {r["deadwood_id"]: r for r in site_rows(L["deadwood_lines"], site)}
        pieces = []
        for layer in ("standingDeadwood", "lyingDeadwood"):
            for r in site_rows(L[layer], site):
                wt = WOOD_TYPE.get(str(r.get("typology_std") or "").lower())
                if wt is None:
                    continue
                pieces.append((layer, wt, r))
        skipped_uncl = len(site_rows(L["unclassifiedDeadwood"], site))
        ids = [str(r["deadwood_id"]) for _, _, r in pieces]
        if len(ids) != len(set(ids)):
            raise SystemExit(f"{loc}: deadwood_id not unique across standing and lying pieces")
        dvals = []
        no_diam = 0
        for layer, wt, r in pieces:
            d = num(r.get("diam_base_cm"))
            if d is not None and d <= 0:
                d = None
            no_diam += d is None
            dt = num(r.get("diam_top_cm"))
            if dt is not None and dt <= 0:
                dt = None
            dc = num(r.get("decay_class"))
            dc = int(dc) if dc is not None and 1 <= dc <= 5 else None
            line = lines_by_id.get(r["deadwood_id"]) if wt == "fallen" else None
            length = num(line.get("length_m")) if line else None
            vol = num(line.get("volume_m3")) if line else None
            geom = geom_sql(line["_srs"], line["_wkb"]) if line else geom_sql(r["_srs"], r["_wkb"])
            attrs = {"typology_raw": r.get("typology_raw"), "species_raw": r.get("species"), "layer": layer}
            dvals.append(f"({lit(str(r['deadwood_id']))}, {lit(wt)}, {lit(norm_species(r.get('species')))}, {lit(d)}, "
                         f"{lit(dt)}, {lit(dc)}, {lit(length if length and length > 0 else None)}, "
                         f"{lit(vol if vol is not None and vol >= 0 else None)}, {geom_sql(r['_srs'], r['_wkb'])}, {geom}, {jlit(attrs)})")
        if dvals:
            w("CREATE TEMP TABLE IF NOT EXISTS pf_stage_deadwood (source_id text, wood_type text, species text, diameter_cm numeric,")
            w("    diameter_top_cm numeric, decay_class integer, length_m numeric, volume_m3 numeric, pos geometry, geom geometry,")
            w("    attrs jsonb) ON COMMIT DROP;")
            w("TRUNCATE pf_stage_deadwood;")
            w("INSERT INTO pf_stage_deadwood VALUES\n  " + ",\n  ".join(dvals) + ";")
            w("INSERT INTO forest_floor.deadwood (location_id, plot_id, campaign_id, species_id, wood_type, length_m, diameter_cm,")
            w("    diameter_top_cm, decay_class, volume_m3, position, geom, measurement_date, source_deadwood_id, source_attributes, created_by)")
            w(f"SELECT l.location_id, p.plot_id, c.campaign_id, sp.species_id, sd.wood_type, sd.length_m, sd.diameter_cm,")
            w(f"       sd.diameter_top_cm, sd.decay_class, sd.volume_m3, ST_PointOnSurface(sd.pos), sd.geom, {lit(s['date'])}::date,")
            w(f"       sd.source_id, sd.attrs, {lit(CREATED_BY)}")
            w("  FROM pf_stage_deadwood sd")
            w(f"  JOIN shared.locations l ON l.location_name = {lit(loc)}")
            w(f"  JOIN shared.plots p ON p.location_id = l.location_id AND p.plot_name = {lit(loc + '_superplot')}")
            w(f"  JOIN shared.campaigns c ON c.campaign_name = {lit(campaign)}")
            w("  LEFT JOIN shared.species sp ON sp.scientific_name = sd.species")
            w("ON CONFLICT (campaign_id, source_deadwood_id) WHERE source_deadwood_id IS NOT NULL DO UPDATE SET")
            w("    species_id = EXCLUDED.species_id, wood_type = EXCLUDED.wood_type, length_m = EXCLUDED.length_m,")
            w("    diameter_cm = EXCLUDED.diameter_cm, diameter_top_cm = EXCLUDED.diameter_top_cm,")
            w("    decay_class = EXCLUDED.decay_class, volume_m3 = EXCLUDED.volume_m3, position = EXCLUDED.position,")
            w("    geom = EXCLUDED.geom, measurement_date = EXCLUDED.measurement_date, source_attributes = EXCLUDED.source_attributes;")
        counts = {wt: sum(1 for _, x, _ in pieces if x == wt) for wt in ("standing", "stump", "fallen")}
        report.append(f"{loc}: deadwood {counts} ({no_diam} without diameter); {skipped_uncl} unclassified pieces skipped")

        # Regeneration.
        rvals = []
        for size_class, rows in (("sapling", saplings), ("seedling", seedlings)):
            for r in rows:
                fid = r["fid"]
                cnt = num(r.get("count"))
                if cnt is None or cnt < 0:
                    continue
                pos = geom_sql(r["_srs"], r["_wkb"]) if r.get("geometry_source") == "measured_point" else "NULL"
                attrs = {"species_raw": r.get("species"), "geometry_source": r.get("geometry_source"),
                         "plot_size": r.get("plot_size")}
                rvals.append(f"({lit(f'{size_class}:{fid}')}, {lit(survey_area[size_class])}, {lit(size_class)}, "
                             f"{lit(norm_species(r.get('species')))}, {int(round(cnt))}, {lit(num(r.get('mean_height_m')))}, "
                             f"{pos}, {jlit(attrs)})")
        if rvals:
            w("CREATE TEMP TABLE IF NOT EXISTS pf_stage_regen (source_id text, survey_area_m2 numeric, size_class text, species text,")
            w("    live_count integer, mean_height_m numeric, pos geometry, attrs jsonb) ON COMMIT DROP;")
            w("TRUNCATE pf_stage_regen;")
            w("INSERT INTO pf_stage_regen VALUES\n  " + ",\n  ".join(rvals) + ";")
            w("INSERT INTO forest_floor.regeneration (location_id, plot_id, campaign_id, species_id, size_class, live_count,")
            w("    mean_height_m, survey_area_m2, position, measurement_date, source_regeneration_id, source_attributes, created_by)")
            w(f"SELECT l.location_id, p.plot_id, c.campaign_id, sp.species_id, sr.size_class, sr.live_count, sr.mean_height_m,")
            w(f"       sr.survey_area_m2, sr.pos, {lit(s['date'])}::date, sr.source_id, sr.attrs, {lit(CREATED_BY)}")
            w("  FROM pf_stage_regen sr")
            w(f"  JOIN shared.locations l ON l.location_name = {lit(loc)}")
            w(f"  JOIN shared.plots p ON p.location_id = l.location_id AND p.plot_name = {lit(loc + '_superplot')}")
            w(f"  JOIN shared.campaigns c ON c.campaign_name = {lit(campaign)}")
            w("  LEFT JOIN shared.species sp ON sp.scientific_name = sr.species")
            w("ON CONFLICT (campaign_id, source_regeneration_id) WHERE source_regeneration_id IS NOT NULL DO UPDATE SET")
            w("    plot_id = EXCLUDED.plot_id, species_id = EXCLUDED.species_id, size_class = EXCLUDED.size_class,")
            w("    live_count = EXCLUDED.live_count, mean_height_m = EXCLUDED.mean_height_m,")
            w("    survey_area_m2 = EXCLUDED.survey_area_m2, position = EXCLUDED.position,")
            w("    source_attributes = EXCLUDED.source_attributes;")
        report.append(f"{loc}: regeneration {len(saplings)} sapling and {len(seedlings)} seedling tallies")

        unmatched = {x for x in species_in if x} | {norm_species(r.get("species")) for _, _, r in pieces} \
            | {norm_species(r.get("species")) for r in saplings + seedlings}
        w("DO $$ DECLARE missing text; BEGIN")
        w("  SELECT string_agg(n, ', ') INTO missing FROM unnest(ARRAY[" +
          ", ".join(lit(x) for x in sorted(x for x in unmatched if x)) + "]::text[]) n")
        w("   WHERE NOT EXISTS (SELECT 1 FROM shared.species s WHERE s.scientific_name = n);")
        w(f"  IF missing IS NOT NULL THEN RAISE WARNING '{loc}: species not in shared.species (species_id NULL, raw name kept): %', missing; END IF;")
        w("END $$;")

    w("")
    w("-- Report")
    w("SELECT l.location_name, count(t.tree_id) AS trees, count(t.height_m) AS with_height, count(s.stem_id) AS stems,")
    w("       count(t.species_id) AS with_species")
    w("  FROM shared.locations l JOIN trees.trees t ON t.location_id = l.location_id")
    w("  LEFT JOIN trees.stems s ON s.tree_id = t.tree_id AND s.stem_number = 1")
    w(" WHERE l.location_name IN (" + ", ".join(lit(x) for x in selected) + ")")
    w(" GROUP BY 1 ORDER BY 1;")
    w("COMMIT;")
    return "\n".join(out) + "\n", report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("command", choices=["fetch", "sql"])
    ap.add_argument("--sites", nargs="*", default=list(SITES), choices=list(SITES),
                    help="location names to process (default: all five)")
    ap.add_argument("--out", type=Path, default=DEFAULT_SQL, help="SQL file to write (sql)")
    args = ap.parse_args()

    if args.command == "fetch":
        fetch({SITES[s]["country"] for s in args.sites})
        return 0

    sql, report = build_sql(args.sites)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(sql, encoding="utf-8")
    for line in report:
        print("  " + line)
    print(f"  wrote {args.out.relative_to(REPO_ROOT) if args.out.is_relative_to(REPO_ROOT) else args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
