"""Assert the naming conventions in docs/database-schema.md §7.2 against a live DB.

XRFF-484. The written convention had drifted so far from the database that it
described neither the case (it claimed PascalCase; every identifier is lowercase
snake_case) nor the number (it claimed singular tables; they are plural), and its
own examples contradicted its own rules. Prose alone clearly does not hold a
convention in place, so this script is the register that can be checked.

CI has been off workspace-wide since 2026-09-01, so nothing runs this for you.
Run it by hand before opening a migration PR:

    python scripts/utils/check_naming.py

Exit code is 0 when no new deviation appeared, 1 otherwise. The deviations that
already exist are listed in KNOWN below, each against the issue that tracks it --
so the script fails on a *newly introduced* break, not on the backlog. Delete an
entry from KNOWN when its issue lands.
"""

import re
import sys
from collections import defaultdict

from db import get_db_connection

DOMAIN_SCHEMAS = (
    "shared",
    "trees",
    "sensor",
    "pointclouds",
    "environments",
    "imagery",
    "forest_floor",
)

# Deviations that predate the convention being written down, each with the issue
# that tracks it. Not every deviation in an issue appears here -- only the ones a
# rule below can actually detect. `ue_scenarios.climate_label` is a real XRFF-485
# finding that no rule catches, because its source column (label) carries no
# suffix to drop. A finding listed here is reported as a known exception rather
# than a failure. Keys are "schema.table.column" or "schema.table".
KNOWN = {
    "public.variants.management_regime": "XRFF-485",
    "public.variants.climate_pathway": "XRFF-485",
    "sensor.sensor_tree_view.sensor_type": "XRFF-485",
    "sensor.sensor_tree_view.tree_species": "XRFF-485",
    "sensor.sensor_tree_view.tree_location": "XRFF-485",
    "public.simulation_runs.base_variant": "XRFF-485",
    "sensor.sensors.accuracy": "XRFF-490",
    "environments.location_environment_summary.avg_temperature": "XRFF-485",
    "environments.location_environment_summary.avg_humidity": "XRFF-485",
    "sensor.sensor_tree_view.sensor_active": "XRFF-490",
    # Rule 13. Two of these are computed and will never have a base-table
    # counterpart -- they are carve-outs, not debt:
    #   ue_scenarios.baseline_variant_id  COALESCE(parent_variant_id, variant_id)
    #   recent_changes.record_id          COALESCE over five different PKs
    # The other three are deliberate view-layer renames, and are debt in the
    # same sense as the rest of XRFF-485: a client reading `linked_tree_id`
    # cannot tell it joins `trees.trees.tree_id`.
    "public.ue_scenarios.baseline_variant_id": "XRFF-485",
    "shared.recent_changes.record_id": "XRFF-485",
    "public.job_status.job_id": "XRFF-485",
    "public.ue_sensors.linked_tree_id": "XRFF-485",
    "public.ue_sensors.linked_tree_entity_id": "XRFF-485",
}

# FK edges where the local column deliberately qualifies the parent's PK name --
# a self-reference or a named role. Each is a decision, not drift.
ROLE_QUALIFIED_FKS = {
    "environments.environments.parent_environment_id",
    "pointclouds.point_clouds.parent_point_cloud_id",
    "shared.variants.parent_variant_id",
    "trees.trees.parent_tree_id",
    # A natural-key FK with a role qualifier: the *typical* unit for a sensor
    # type, as opposed to the unit a given sensor actually reports.
    "sensor.sensor_types.typical_unit",
    "shared.scenarios.climate_pathway_id",
    "shared.scenarios.management_regime_id",
    "trees.growth_simulations.base_tree_id",
    "trees.simulation_runs.base_variant_id",
        }

# Provenance columns are deliberately not CHECK-guarded: a new writer with a new
# legitimate source should not need a migration to record it (XRFF-400).
UNCONSTRAINED_BY_DESIGN = {
    "trees.trees.height_source",
    "sensor.sensors.source",
    "shared.process_metrics.source",
}

SNAKE_CASE = re.compile(r"^[a-z][a-z0-9_]*$")
UNIT_SUFFIX = re.compile(
    r"_(m|cm|mm|km|m2|m3|ha|m2ha|m3ha|tha|kg|g|t|kg_m3|mg_kg|w_m2|deg|percent"
    r"|ppm|c|v|ms|px|mb|s|seconds|yrs|years)$"
)
# Names that read as a measure but are dimensionless, so take no unit.
DIMENSIONLESS = re.compile(r"(_ratio|_score|_index|_count|_confidence|^relative_)")
MEASURE_HINT = re.compile(
    r"(height|diam|dbh|length|width|radius|area|volume|mass|weight|density|_depth"
    r"|distance|temperature|precip|humid|angle|elev|thickness|speed|voltage"
    r"|biomass|carbon|accuracy)"
)


def fetch(cur, sql):
    cur.execute(sql)
    return cur.fetchall()


def main():
    conn = get_db_connection()
    cur = conn.cursor()
    schemas = "','".join(DOMAIN_SCHEMAS)

    columns = fetch(
        cur,
        f"""
        SELECT c.table_schema, c.table_name, c.column_name, c.data_type,
               t.table_type
        FROM information_schema.columns c
        JOIN information_schema.tables t
          ON t.table_schema = c.table_schema AND t.table_name = c.table_name
        WHERE c.table_schema IN ('{schemas}', 'public')
        ORDER BY 1, 2, c.ordinal_position
        """,
    )
    constraints = fetch(
        cur,
        f"""
        SELECT ns.nspname, cl.relname, c.contype::text, pg_get_constraintdef(c.oid)
        FROM pg_constraint c
        JOIN pg_class cl ON cl.oid = c.conrelid
        JOIN pg_namespace ns ON ns.oid = cl.relnamespace
        WHERE ns.nspname IN ('{schemas}')
        """,
    )
    routines = fetch(
        cur,
        f"""
        SELECT n.nspname, p.proname, p.prosrc
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname IN ('{schemas}', 'public') AND p.prolang <> 12
        """,
    )
    # Every name a function body could legitimately reference, so a miss is real.
    known_names = {
        (r[0], r[1])
        for r in fetch(
            cur,
            f"""
            SELECT n.nspname, c.relname FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname IN ('{schemas}', 'public', 'extensions', 'auth', 'storage')
            UNION
            SELECT n.nspname, p.proname FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname IN ('{schemas}', 'public', 'extensions', 'auth', 'storage')
            UNION
            SELECT n.nspname, t.typname FROM pg_type t
            JOIN pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname IN ('{schemas}', 'public', 'extensions')
            """,
        )
    }
    identifiers = fetch(
        cur,
        f"""
        SELECT n.nspname, c.relname, c.relkind::text FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('{schemas}')
        UNION ALL
        SELECT n.nspname, c.conname, 'constraint' FROM pg_constraint c
        JOIN pg_class cl ON cl.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = cl.relnamespace
        WHERE n.nspname IN ('{schemas}')
        """,
    )
    reserved = {r[0] for r in fetch(
        cur, "SELECT word FROM pg_get_keywords() WHERE catcode = 'R'")}
    viewdefs = fetch(
        cur,
        f"""
        SELECT ns.nspname, cl.relname, pg_get_viewdef(cl.oid, true)
        FROM pg_class cl
        JOIN pg_namespace ns ON ns.oid = cl.relnamespace
        WHERE cl.relkind = 'v' AND ns.nspname IN ('{schemas}', 'public')
        """,
    )
    conn.close()

    base = {
        (s, t) for s, t, _c, _d, ttype in columns if ttype == "BASE TABLE"
    }
    cols_by_table = defaultdict(list)
    for s, t, c, dtype, ttype in columns:
        cols_by_table[(s, t)].append((c, dtype))

    pk, fk, checks, uniq = {}, {}, defaultdict(list), set()
    fk_re = re.compile(r"FOREIGN KEY \(([^)]+)\) REFERENCES ([^\s(]+)\(([^)]+)\)")
    for s, t, contype, definition in constraints:
        if contype == "p":
            cols = re.search(r"PRIMARY KEY \(([^)]+)\)", definition).group(1)
            pk[(s, t)] = [x.strip().strip('"') for x in cols.split(",")]
        elif contype == "f":
            m = fk_re.search(definition)
            if m:
                local = [x.strip().strip('"') for x in m.group(1).split(",")]
                parent = [x.strip().strip('"') for x in m.group(3).split(",")]
                for lc, pc in zip(local, parent):
                    fk[(s, t, lc)] = (m.group(2), pc)
        elif contype == "c":
            checks[(s, t)].append(definition)
        elif contype == "u":
            cols = re.search(r"UNIQUE \(([^)]+)\)", definition).group(1)
            parts = [x.strip().strip('"') for x in cols.split(",")]
            if len(parts) == 1:
                uniq.add((s, t, parts[0]))

    failures, known_hits = [], []
    excused = set()

    def report(key, message):
        if key in KNOWN:
            excused.add(key)
            known_hits.append(f"{key}: {message}  [{KNOWN[key]}]")
        else:
            failures.append(f"{key}: {message}")

    # 1. Every identifier is lowercase snake_case.
    for s, t, c, _dtype, _ttype in columns:
        if not SNAKE_CASE.match(c):
            report(f"{s}.{t}.{c}", "not lowercase snake_case")
    for s, t in sorted({(s, t) for s, t, *_ in columns}):
        if not SNAKE_CASE.match(t):
            report(f"{s}.{t}", "table name not lowercase snake_case")

    # 2. Every foreign-key column ends in _id -- unless it references a natural
    #    key rather than a surrogate one. sensor.Sensors.unit references
    #    sensor.Units.unit_name, which is the whole point of that lookup: the
    #    stored value is the unit, not an opaque id.
    for (s, t, c), (_parent, pcol) in fk.items():
        if not c.endswith("_id") and pcol.endswith("_id"):
            report(f"{s}.{t}.{c}", "foreign key does not end in _id")

    # 3. A foreign key carries the parent's PK name, unless it names a role.
    for (s, t, c), (parent, pc) in fk.items():
        if c == pc or f"{s}.{t}.{c}" in ROLE_QUALIFIED_FKS:
            continue
        # A natural-key FK carries the parent column's stem, not its full name:
        # sensors.unit -> units.unit_name. Requiring an exact match would force
        # the column to be called unit_name, which reads wrong on a sensor.
        if not pc.endswith("_id") and pc.rsplit("_", 1)[0] == c:
            continue
        report(f"{s}.{t}.{c}", f"differs from parent {parent}({pc})")

    # 4. A single-column PK is <table stem>_id -- unless it is a natural key.
    #    A text PK stores the identifier itself (shared.lookup_registry's
    #    logical_key is the string callers pass), and _id would imply a
    #    surrogate that is not there.
    coltype = {(s, t, c): d for s, t, c, d, _ttype in columns}
    for (s, t), cols in pk.items():
        if len(cols) != 1 or cols[0].endswith("_id"):
            continue
        if coltype.get((s, t, cols[0])) in ("text", "character varying"):
            continue
        report(f"{s}.{t}", f"primary key {cols[0]} does not end in _id")

    # 5. A lookup's _name stem matches its own _id stem.
    for (s, t), cols in cols_by_table.items():
        key = pk.get((s, t), [])
        if (s, t) not in base or len(key) != 1 or not key[0].endswith("_id"):
            continue
        stem = key[0][:-3]
        for c, _dtype in cols:
            # A lookup's label is the column carrying its natural key, on a table
            # that is little more than id + label + description. Columns that
            # merely end in _name -- attribute_provenance.column_name,
            # process_parameters.parameter_name -- name a thing being described
            # rather than the row. shared.species (13 columns) is an entity whose
            # scientific_name is a natural key, not a lookup label.
            if (
                c.endswith("_name")
                and c[:-5] != stem
                and (s, t, c) in uniq
                and len(cols) <= 6
            ):
                report(f"{s}.{t}.{c}", f"label stem differs from PK {key[0]}")

    # 6. Booleans are prefixed is_ / has_. Base tables and the columns a public
    #    view introduces itself; a view column inherited unchanged from its base
    #    would otherwise be reported twice.
    base_cols = {(c, d) for (s, t), v in cols_by_table.items() if (s, t) in base
                 for c, d in v}
    for s, t, c, dtype, _ttype in columns:
        if (s, t) not in base and (c, dtype) in base_cols:
            continue
        if dtype == "boolean" and not c.startswith(("is_", "has_")):
            report(f"{s}.{t}.{c}", "boolean without is_/has_ prefix")

    # 7. A numeric column naming a physical quantity carries a unit.
    numeric = ("integer", "numeric", "double precision", "real", "bigint", "smallint")
    for s, t, c, dtype, _ttype in columns:
        if dtype not in numeric or c.endswith("_id"):
            continue
        if (s, t) not in base and (c, dtype) in base_cols:
            continue
        if not MEASURE_HINT.search(c) or DIMENSIONLESS.search(c):
            continue
        if not UNIT_SUFFIX.search(c):
            report(f"{s}.{t}.{c}", "measure without a unit suffix")

    # 8. Enumerated text columns are CHECK-guarded, provenance columns excepted.
    enum_like = re.compile(r"(_type|_status|_class|_category|^unit$|_unit)$")
    for s, t, c, dtype, _ttype in columns:
        if (s, t) not in base or dtype not in ("text", "character varying"):
            continue
        if not enum_like.search(c) or f"{s}.{t}.{c}" in UNCONSTRAINED_BY_DESIGN:
            continue
        # A foreign key to a lookup is a stronger guarantee than a CHECK, and
        # unlike a CHECK it cannot drift from a second copy of the same list.
        if (s, t, c) in fk:
            continue
        if not any(re.search(rf"\b{re.escape(c)}\b", d) for d in checks[(s, t)]):
            report(f"{s}.{t}.{c}", "enumerated text without a CHECK constraint")


    # 9. A view must not alias away a _name or unit suffix. The suffix is the
    #    whole contract -- `mr.regime_name AS management_regime` hands a client a
    #    column it cannot tell from an id, and `avg_temperature_c AS
    #    avg_temperature` hands it a number with no unit. Catches the one thing
    #    the snake_case regex cannot see: a *missing* separator, as in
    #    `sp.scientific_name AS linked_tree_scientificname`.
    alias_re = re.compile(r"(\w+)\.(\w+)\s+AS\s+(\w+)", re.IGNORECASE)
    for s, t, definition in viewdefs:
        for _tbl, src_col, alias in alias_re.findall(definition):
            if src_col == alias:
                continue
            dropped = None
            if src_col.endswith("_name") and not alias.endswith("_name"):
                dropped = "_name"
            else:
                m = UNIT_SUFFIX.search(src_col)
                if m and not UNIT_SUFFIX.search(alias):
                    dropped = m.group(0)
            if dropped:
                report(
                    f"{s}.{t}.{alias}",
                    f"view alias drops '{dropped}' from {src_col}",
                )


    # 10. No function body may reference a relation that does not exist.
    #     ALTER TABLE ... RENAME does not rewrite plpgsql bodies at all -- not
    #     even static SQL, since bodies are stored as text and re-parsed at call
    #     time. A renamed table therefore breaks every function that names it,
    #     at call time rather than at migration time, and with CI off nothing
    #     else will say so. This is the gate the rename plan depends on
    #     (XRFF-495); it must report zero after every migration.
    qualified = re.compile(
        "(?<![A-Za-z0-9_])(" + "|".join(DOMAIN_SCHEMAS) + "|public)[.]([a-z_][a-z0-9_]*)",
        re.IGNORECASE,
    )
    for s, fname, src in routines:
        if not src:
            continue
        for sch, name in {(m[0].lower(), m[1].lower()) for m in qualified.findall(src)}:
            if (sch, name) not in known_names:
                report(
                    f"{s}.{fname}",
                    f"function body references {sch}.{name}, which does not exist",
                )

    # 11. Identifier length. PostgreSQL truncates at 63 bytes SILENTLY, in the
    #     middle of the name, so a collision or a broken reference is the first
    #     symptom. Warn well before the cliff: auto-generated names grow from
    #     the table name, so a table comfortably under the limit can still
    #     produce a constraint over it.
    for s, ident, kind in identifiers:
        n = len(ident.encode("utf-8"))
        if n >= 63:
            report(f"{s}.{ident}", f"identifier is {n} bytes -- at the 63-byte limit, so it "
                                   "may already be a silent truncation")
        elif n >= 60:
            report(f"{s}.{ident}", f"identifier is {n} bytes, within 3 of the 63-byte limit")

    # 12. No identifier may collide with a reserved word.
    for s, ident, kind in identifiers:
        if ident.lower() in reserved:
            report(f"{s}.{ident}", f"identifier is a reserved word ({kind})")

    # 13. Every `_id` column a view publishes must exist on some base table.
    #     Renaming a base COLUMN rewrites a dependent view's stored definition,
    #     so the view keeps working -- but it does NOT rename the view's output
    #     column when an explicit AS pinned that name. (A TABLE rename updates
    #     both, which is why this only bites column renames.) The view then
    #     advertises a key that exists nowhere, and nothing fails until a client
    #     tries to join on it. XRFF-487 left exactly two behind
    #     (`branch_elongation_habit_id`, `phanerophyte_height_class_id`) and
    #     rule 9 could not see them: no suffix was dropped, the whole stem moved.
    #     Scoped to `_id` because that is where a wrong name silently becomes a
    #     wrong join; a computed or aggregated view column legitimately has no
    #     base-table counterpart.
    base_cols = {c for (s, t, c, _d, ttype) in columns if ttype == "BASE TABLE"}
    for s, t, c, _d, ttype in columns:
        if ttype == "BASE TABLE" or not c.endswith("_id"):
            continue
        if c not in base_cols:
            report(
                f"{s}.{t}.{c}",
                "view publishes an _id column that exists on no base table",
            )

    # 14. Every KNOWN entry must still correspond to a live deviation. A KNOWN
    #     entry is a standing excuse: once the deviation it names is fixed, the
    #     entry stops being a record of debt and becomes a blind spot, because
    #     re-introducing that exact deviation would be silently excused. So a
    #     fixed deviation must have its entry deleted, and this is what makes
    #     that non-optional. (XRFF-497's grandfathered 62-byte constraint name
    #     was the first to go stale: the rename shortened it to
    #     `audit_log_phenology_observations_observation_fkey` and the entry
    #     would have sat there excusing a name that can no longer occur.)
    for key in sorted(set(KNOWN) - excused):
        failures.append(
            f"{key}: listed in KNOWN [{KNOWN[key]}] but no longer deviates -- "
            "delete the entry, it is now a silent excuse"
        )

    for line in known_hits:
        print(f"known   {line}")
    for line in failures:
        print(f"FAIL    {line}")

    print(
        f"\n{len(base)} base tables, {len(columns)} columns, {len(fk)} foreign keys — "
        f"{len(failures)} new deviation(s), {len(known_hits)} known."
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
