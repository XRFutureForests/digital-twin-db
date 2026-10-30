#!/usr/bin/env python3
"""Generate the data dictionary and the DBML ERD from the live database.

    python scripts/utils/generate_schema_docs.py            # writes both files
    python scripts/utils/generate_schema_docs.py --check    # exit 1 if either is stale

Writes `docs/database-dictionary.md` (every table of the seven domain schemas:
columns, types, nullability, defaults, references, constraints and the
COMMENTs stored in the database) and `docs/database-erd.dbml`.

Both used to be maintained by hand and drifted badly: by 2026-10-30 the DBML
was missing 27 of the 72 tables and still used the pre-2026-09-23 CamelCase
names. Generated from `pg_catalog` rather than `information_schema`, because
the latter hides tables the connecting role has no grant on.

Run it after every migration, against a database that has the migration
applied (the local stack, normally). The output names the newest migration in
`supabase/migrations/` so a reader can tell which state it describes; it
carries no timestamp, so an unchanged schema regenerates byte-identical files.
"""
import argparse
import sys
from collections import defaultdict
from pathlib import Path

from db import get_db_connection

REPO_ROOT = Path(__file__).parent.parent.parent
DICT_PATH = REPO_ROOT / "docs" / "database-dictionary.md"
DBML_PATH = REPO_ROOT / "docs" / "database-erd.dbml"

# Keep in sync with the CREATE SCHEMA statements in docker/volumes/db/init/.
SCHEMAS = ["shared", "trees", "sensor", "environments", "pointclouds", "imagery", "forest_floor"]

SCHEMA_NOTES = {
    "shared": "Sites, scenarios and forest states, species, campaigns, events, processes, jobs, audit",
    "trees": "Trees per forest state, stems, observations, SILVA output, tree structure, morphology lookups",
    "sensor": "Sensors, their time series, units, sensor-tree links",
    "environments": "Climate and soil per location, scenario and period",
    "pointclouds": "Point clouds and scanners",
    "imagery": "Images",
    "forest_floor": "Plot-level dead wood and ground vegetation surveys",
}


def fetch(cur, sql, params=None):
    cur.execute(sql, params or ())
    return cur.fetchall()


def load(cur):
    tables = fetch(cur, """
        SELECT n.nspname, c.relname, coalesce(obj_description(c.oid, 'pg_class'), ''), c.oid
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = ANY(%s) AND c.relkind IN ('r', 'p')
         ORDER BY array_position(%s::text[], n.nspname::text), c.relname""", (SCHEMAS, SCHEMAS))

    columns = defaultdict(list)
    for oid, name, typ, notnull, default, generated, identity, comment in fetch(cur, """
        SELECT a.attrelid, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull,
               pg_get_expr(d.adbin, d.adrelid), a.attgenerated, a.attidentity,
               coalesce(col_description(a.attrelid, a.attnum), '')
          FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
          LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
         WHERE n.nspname = ANY(%s) AND c.relkind IN ('r', 'p') AND a.attnum > 0 AND NOT a.attisdropped
         ORDER BY a.attrelid, a.attnum""", (SCHEMAS,)):
        columns[oid].append(dict(name=name, type=typ, notnull=notnull, default=default,
                                 generated=generated, identity=identity, comment=comment))

    constraints = defaultdict(list)
    fks = defaultdict(dict)        # oid -> {column: (target, on_delete)}  (single-column FKs)
    fk_list = []                   # (schema.table, [cols], schema.table, [cols], on_delete)
    for oid, contype, definition, cols, tschema, ttable, tcols, deltype in fetch(cur, """
        SELECT con.conrelid, con.contype, pg_get_constraintdef(con.oid),
               ARRAY(SELECT a.attname FROM unnest(con.conkey) WITH ORDINALITY k(n, i)
                       JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k.n ORDER BY k.i),
               tn.nspname, tc.relname,
               ARRAY(SELECT a.attname FROM unnest(con.confkey) WITH ORDINALITY k(n, i)
                       JOIN pg_attribute a ON a.attrelid = con.confrelid AND a.attnum = k.n ORDER BY k.i),
               con.confdeltype
          FROM pg_constraint con
          JOIN pg_class c ON c.oid = con.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
          LEFT JOIN pg_class tc ON tc.oid = con.confrelid
          LEFT JOIN pg_namespace tn ON tn.oid = tc.relnamespace
         WHERE n.nspname = ANY(%s) AND con.contype IN ('p', 'u', 'c', 'f')
         ORDER BY con.conrelid, con.contype, pg_get_constraintdef(con.oid)""", (SCHEMAS,)):
        on_delete = {"c": "cascade", "n": "set null", "d": "set default", "r": "restrict"}.get(deltype, "")
        if contype == "f":
            if len(cols) == 1:
                fks[oid][cols[0]] = (f"{tschema}.{ttable}.{tcols[0]}", on_delete)
            fk_list.append((oid, cols, f"{tschema}.{ttable}", tcols, on_delete))
        else:
            constraints[oid].append((contype, cols, definition))

    domain_views = fetch(cur, """
        SELECT n.nspname || '.' || c.relname, coalesce(obj_description(c.oid, 'pg_class'), '')
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = ANY(%s) AND c.relkind IN ('v', 'm') ORDER BY 1""", (SCHEMAS,))
    public_views = fetch(cur, """
        SELECT c.relname, coalesce(obj_description(c.oid, 'pg_class'), '')
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relkind IN ('v', 'm')
           AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.deptype = 'e')
         ORDER BY 1""")
    return tables, columns, constraints, fks, fk_list, domain_views, public_views


def newest_migration():
    files = sorted((REPO_ROOT / "supabase" / "migrations").glob("*.sql"))
    return files[-1].stem if files else "unknown"


def one_line(text):
    return " ".join(text.split())


def md_cell(text):
    return one_line(text).replace("|", "\\|")


def default_text(col):
    if col["generated"] == "s":
        return f"generated: `{one_line(col['default'] or '')}`"
    if col["identity"]:
        return "identity"
    d = col["default"]
    if not d:
        return ""
    if d.startswith("nextval("):
        return "serial"
    return f"`{one_line(d)}`"


def render_dictionary(data, migration):
    tables, columns, constraints, fks, _, domain_views, public_views = data
    out = [
        "# Data Dictionary",
        "",
        "> **Generated** by `scripts/utils/generate_schema_docs.py` from the database, as of migration",
        f"> `{migration}`. Do not edit by hand: change the schema (and its `COMMENT ON`s) with a",
        "> migration, then regenerate. The descriptions are the comments stored in the database.",
        "> How the schemas fit together, conventions and design notes: [database-schema.md](database-schema.md).",
        "",
        "Every table of the seven domain schemas. The REST API exposes most of them as a view of the",
        "same name in `public` (listed at the end); write and read through those.",
        "",
        "| Schema | Tables | Holds |",
        "|---|---:|---|",
    ]
    per_schema = defaultdict(list)
    for schema, name, comment, oid in tables:
        per_schema[schema].append((name, comment, oid))
    for s in SCHEMAS:
        out.append(f"| [`{s}`](#{s}) | {len(per_schema[s])} | {SCHEMA_NOTES.get(s, '')} |")
    out.append("")

    for s in SCHEMAS:
        out += [f"## {s}", "", SCHEMA_NOTES.get(s, ""), ""]
        out.append(" · ".join(f"[`{n}`](#{s}{n})" for n, _, _ in per_schema[s]))
        out.append("")
        for name, comment, oid in per_schema[s]:
            out += [f"### {s}.{name}", ""]
            if comment:
                out += [one_line(comment), ""]
            out += ["| Column | Type | Null | Default | References | Description |",
                    "|---|---|---|---|---|---|"]
            for c in columns[oid]:
                ref = ""
                if c["name"] in fks[oid]:
                    target, on_delete = fks[oid][c["name"]]
                    ref = f"`{target}`" + (f" ({on_delete})" if on_delete and on_delete != "restrict" else "")
                out.append(f"| `{c['name']}` | {c['type']} | {'' if c['notnull'] else 'yes'} | "
                           f"{md_cell(default_text(c))} | {ref} | {md_cell(c['comment'])} |")
            notes = []
            for contype, cols, definition in constraints[oid]:
                if contype == "p":
                    notes.append(f"primary key ({', '.join(cols)})")
                elif contype == "u":
                    notes.append(f"unique ({', '.join(cols)})")
                elif contype == "c":
                    notes.append(f"`{one_line(definition)}`")
            if notes:
                out += ["", "Constraints: " + "; ".join(notes) + "."]
            out.append("")

    out += ["## Views", "",
            "### Views in the domain schemas", "",
            "| View | Description |", "|---|---|"]
    out += [f"| `{v}` | {md_cell(c)} |" for v, c in domain_views]
    out += ["", "### Public API views", "",
            "The REST API (`/rest/v1/<name>`). Their columns, live: `GET /rest/v1/` (OpenAPI), or the",
            "portal's API page.", "",
            "| View | Description |", "|---|---|"]
    out += [f"| `{v}` | {md_cell(c)} |" for v, c in public_views]
    out.append("")
    return "\n".join(out)


def dbml_type(t):
    return f'"{t}"' if any(ch in t for ch in " []") else t


def dbml_str(text):
    return "'" + one_line(text).replace("\\", "\\\\").replace("'", "\\'") + "'"


def render_dbml(data, migration):
    tables, columns, constraints, fks, fk_list, _, _ = data
    oid_name = {oid: f"{s}.{n}" for s, n, _, oid in tables}
    out = [
        f"// Generated by scripts/utils/generate_schema_docs.py from the database, as of migration {migration}.",
        "// Do not edit by hand -- change the schema with a migration, then regenerate.",
        "// Render at https://dbdiagram.io or with @dbml/cli.",
        "",
        "Project digital_forest_twin {",
        "  database_type: 'PostgreSQL'",
        "  Note: 'Forest digital twin: seven domain schemas, PostgreSQL 15 + PostGIS. Data dictionary: docs/database-dictionary.md'",
        "}",
        "",
    ]
    for schema, name, comment, oid in tables:
        pk_cols = next((cols for t, cols, _ in constraints[oid] if t == "p"), [])
        out.append(f"Table {schema}.{name} {{")
        for c in columns[oid]:
            attrs = []
            if c["name"] in pk_cols and len(pk_cols) == 1:
                attrs.append("pk")
            if c["notnull"] and c["name"] not in pk_cols:
                attrs.append("not null")
            d = c["default"]
            if d and c["generated"] != "s" and not d.startswith("nextval("):
                attrs.append(f"default: `{one_line(d)}`")
            if c["generated"] == "s":
                attrs.append(f"note: {dbml_str('generated: ' + (d or ''))}")
            elif c["comment"]:
                attrs.append(f"note: {dbml_str(c['comment'])}")
            if d and d.startswith("nextval("):
                attrs.insert(0, "increment")
            out.append(f"  {c['name']} {dbml_type(c['type'])}" + (f" [{', '.join(attrs)}]" if attrs else ""))
        idx = []
        if len(pk_cols) > 1:
            idx.append(f"    ({', '.join(pk_cols)}) [pk]")
        for t, cols, _ in constraints[oid]:
            if t == "u":
                idx.append(f"    ({', '.join(cols)}) [unique]" if len(cols) > 1 else f"    {cols[0]} [unique]")
        if idx:
            out += ["", "  indexes {"] + idx + ["  }"]
        if comment:
            out += ["", f"  Note: {dbml_str(comment)}"]
        out += ["}", ""]

    for oid, cols, target, tcols, on_delete in fk_list:
        src = oid_name[oid]
        left = f"{src}.{cols[0]}" if len(cols) == 1 else f"{src}.({', '.join(cols)})"
        right = f"{target}.{tcols[0]}" if len(tcols) == 1 else f"{target}.({', '.join(tcols)})"
        setting = f" [delete: {on_delete}]" if on_delete and on_delete != "restrict" else ""
        out.append(f"Ref: {left} > {right}{setting}")
    out.append("")

    per_schema = defaultdict(list)
    for schema, name, _, _ in tables:
        per_schema[schema].append(f"{schema}.{name}")
    for s in SCHEMAS:
        out.append(f"TableGroup {s} {{")
        out += [f"  {t}" for t in per_schema[s]]
        out += ["}", ""]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="exit 1 if a generated file differs from the database")
    args = ap.parse_args()

    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            data = load(cur)
    finally:
        conn.close()

    migration = newest_migration()
    outputs = {DICT_PATH: render_dictionary(data, migration), DBML_PATH: render_dbml(data, migration)}
    stale = []
    for path, text in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else ""
        if current != text:
            stale.append(path)
            if not args.check:
                path.write_text(text, encoding="utf-8", newline="\n")
    for path in stale:
        print(("stale: " if args.check else "wrote: ") + str(path.relative_to(REPO_ROOT)))
    if not stale:
        print("up to date")
    sys.exit(1 if args.check and stale else 0)


if __name__ == "__main__":
    main()
