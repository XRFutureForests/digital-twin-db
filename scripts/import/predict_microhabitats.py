#!/usr/bin/env python3
"""
Predict tree-related microhabitats for inventoried trees (XRFF-693).

Model: one logistic regression per microhabitat type, fitted to the open data
of Paillet et al. (2019, PLoS ONE 14(5):e0216500, S1 Dataset, CC BY 4.0):
22,306 trees > 17.5 cm DBH in French forest reserves, five genera (beech, fir,
oak, pine, spruce), living and dead, each scored present/absent for 19
microhabitat types. Paillet et al. found that DBH, genus and living status
explain microhabitat occurrence far better than the site context, so the model
uses only those:

    logit P(type) = logit(overall rate of the type) + a[cell] + b[cell] * (DBH - 40) / 20

with one cell per genus x living status, fitted by penalised maximum likelihood
(ridge, lambda = LAMBDA) so that cells with few trees are pulled toward the
type's overall rate instead of to 0 or 1. Plot and site random effects of the
paper are left out: a new site has no estimate for them, so the population-
level prediction is what applies.

Each tree is then drawn per type with a seeded generator keyed on (seed,
tree_id, type), so a rerun reproduces the same microhabitats. Rows land in
trees.microhabitats with provenance 'predicted', this script's process and the
probability; they decorate VR and never count as observations.

What gets no prediction, by design:
- trees of other genera (e.g. Pseudotsuga, Larix): no congener's model;
- trees <= 17.5 cm DBH: outside the fitted range;
- downed, harvested or missing trees.

Paillet's 19 types map to the WSL field-guide types (TYPE_MAP). Rot, CrownSq and
Fork are not predicted: the paper does not define them and the data do not make
the definition clear (Fork occurs on 14 % of living trees, far above the guide's
fork split). Small, medium and large dead branches are merged into type 26.

    python predict_microhabitats.py fetch                     # S1 -> data/input/paillet2019/
    python predict_microhabitats.py validate                  # predicted vs measured on the marteloscopes
    python predict_microhabitats.py apply --location ecosense mathisle [--dry-run]
"""

from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import get_db_connection  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
S1_PATH = REPO_ROOT / "data" / "input" / "paillet2019" / "S1_Dataset.csv"
S1_URL = "https://journals.plos.org/plosone/article/file?type=supplementary&id=10.1371/journal.pone.0216500.s001"
VERSION = "1.0"
SEED = 20261117
LAMBDA = 1.0
MIN_DBH = 17.5
# Managed Central European stands with field-guide thresholds; their measured rates set
# each type's overall level (the Paillet data come from unmanaged reserves with lower thresholds).
CALIB_PLOTS = ["klosterwald", "rosskopf", "mooswald"]

GENUS = {"Fagus": "Beech", "Abies": "Fir", "Quercus": "Oak", "Pinus": "Pine", "Picea": "Spruce"}
# Paillet type -> field-guide type number (trees.microhabitat_types). All approximate:
# the paper gives no size thresholds.
TYPE_MAP = {
    "BaseCav": 15,      # buttress-root concavity (its 9 % rate on living trees matches type 15 on the
                        # marteloscopes, 11 %, not the trunk-base rot-hole, 0.5 %)
    "TrunkCav": 6,      # trunk rot-hole
    "CanopyCav": 10,    # hollow branch
    "WoodpCav": 2,      # medium-sized woodpecker breeding cavity
    "Cracks": 22,       # crack
    "WoodpFeed": 13,    # large woodpecker foraging excavation
    "Injury": 16,       # bark loss
    "Conk": 34,         # perennial polypore
    "BarkCharact": 18,  # bark shelter
    "Moss": 40,         # bryophytes
    "Lichen": 41,       # foliose and fruticose lichens
    "Ivy": 42,          # ivy and lianas
    "DeadBr": 26,       # dead branches (SmallBr | MediumBr | LargeBr)
    "BrockStem": 20,    # stem breakage
}

PROCESS = {
    "process_name": "Tree Microhabitat Prediction",
    "algorithm_name": "Ridge logistic regression per type on genus x living status x DBH (Paillet et al. 2019 data)",
    "description": (
        "Predicted tree-related microhabitats for VR. One logistic regression per type, fitted to the "
        "S1 Dataset of Paillet et al. (2019): 22,306 trees > 17.5 cm DBH, beech, fir, oak, pine and spruce, "
        "living and dead, French forest reserves. Predictors: genus x living status and DBH within each "
        f"cell; ridge penalty {LAMBDA} toward the type's overall rate; no site effects. Trees are drawn per "
        "type with a generator seeded on (seed, tree_id, type). Other genera, trees <= 17.5 cm and downed, "
        "harvested or missing trees get no prediction. Paillet types map approximately to the WSL field-guide "
        "types; Rot, CrownSq and Fork are not predicted. Predicted rows are decoration, not observations."
    ),
    "author": "Paillet, Y.; Debaive, N.; Archaux, F.; Cateau, E.; Gilg, O.; Guilbert, E. (data)",
    "citation": (
        "Paillet Y, Debaive N, Archaux F, Cateau E, Gilg O, Guilbert E (2019) Nothing else matters? Tree "
        "diameter and living status have more effects than biogeoclimatic context on microhabitat number and "
        "occurrence: An analysis in French forest reserves. PLoS ONE 14(5): e0216500. "
        "doi:10.1371/journal.pone.0216500"
    ),
    "category": "analysis",
}


# --------------------------------------------------------------------------- model

def load_training() -> pd.DataFrame:
    if not S1_PATH.exists():
        raise SystemExit(f"{S1_PATH.relative_to(REPO_ROOT)} missing: run `predict_microhabitats.py fetch` first")
    d = pd.read_csv(S1_PATH, sep=";", encoding="latin-1")
    d = d[d.DBH > MIN_DBH].copy()
    d["DeadBr"] = ((d.SmallBr + d.MediumBr + d.LargeBr) > 0).astype(int)
    d["cell"] = d.TreeSp + "/" + d.LivingStatus
    return d


def design(cells: pd.Series, dbh: pd.Series, levels: list[str]) -> np.ndarray:
    onehot = (cells.to_numpy()[:, None] == np.array(levels)[None, :]).astype(float)
    x = ((dbh.to_numpy() - 40.0) / 20.0)[:, None]
    return np.hstack([onehot, onehot * x])


def fit_logistic(X: np.ndarray, y: np.ndarray, offset: float, lam: float) -> np.ndarray:
    """Newton-Raphson with step halving for ridge-penalised logistic regression with a fixed offset."""
    def objective(b):  # penalised log-likelihood, numerically stable
        eta = X @ b + offset
        return float(y @ eta - np.logaddexp(0, eta).sum() - 0.5 * lam * b @ b)

    b = np.zeros(X.shape[1])
    f = objective(b)
    for _ in range(200):
        p = 1.0 / (1.0 + np.exp(-np.clip(X @ b + offset, -30, 30)))
        grad = X.T @ (y - p) - lam * b
        hess = (X * (p * (1 - p))[:, None]).T @ X + lam * np.eye(X.shape[1])
        step = np.linalg.solve(hess, grad)
        t = 1.0
        while objective(b + t * step) < f - 1e-12 and t > 1e-6:
            t /= 2
        b, f_new = b + t * step, objective(b + t * step)
        if abs(f_new - f) < 1e-9:
            return b
        f = f_new
    raise RuntimeError("logistic fit did not converge")


def fit_all(d: pd.DataFrame) -> tuple[list[str], dict[str, tuple[np.ndarray, float]]]:
    levels = sorted(d.cell.unique())
    X = design(d.cell, d.DBH, levels)
    models = {}
    for t in TYPE_MAP:
        y = (d[t] > 0).astype(float).to_numpy()
        rate = y.mean()
        offset = float(np.log(rate / (1 - rate)))
        models[t] = (fit_logistic(X, y, offset, LAMBDA), offset)
    return levels, models


def predict(levels, models, genus: pd.Series, living: pd.Series, dbh: pd.Series) -> pd.DataFrame:
    cells = genus.map(GENUS) + "/" + np.where(living, "Living", "Dead")
    X = design(cells, dbh, levels)
    return pd.DataFrame({t: 1.0 / (1.0 + np.exp(-(X @ b + off))) for t, (b, off) in models.items()},
                        index=genus.index)


def logit(p):
    p = np.clip(p, 1e-9, 1 - 1e-9)
    return np.log(p / (1 - p))


def calibration_shifts(probs: pd.DataFrame, measured: pd.DataFrame) -> dict[str, float]:
    """Per type, the logit shift that makes the mean predicted rate equal the measured rate
    (calibration-in-the-large; +0.5 pseudo-count so an unseen type becomes rare, not impossible)."""
    shifts = {}
    for t in probs.columns:
        target = (measured[t].sum() + 0.5) / (len(measured) + 1)
        eta = logit(probs[t].to_numpy())
        lo, hi = -20.0, 20.0
        for _ in range(100):
            mid = (lo + hi) / 2
            if (1 / (1 + np.exp(-(eta + mid)))).mean() < target:
                lo = mid
            else:
                hi = mid
        shifts[t] = (lo + hi) / 2
    return shifts


def shifted(probs: pd.DataFrame, shifts: dict[str, float]) -> pd.DataFrame:
    return pd.DataFrame({t: 1 / (1 + np.exp(-(logit(probs[t].to_numpy()) + shifts[t]))) for t in probs.columns},
                        index=probs.index)


def calibration_data(cur, levels, models):
    """Raw predictions and measured presence (0/1 per mapped type) for the marteloscope trees."""
    trees = eligible(load_trees(cur, CALIB_PLOTS))
    cur.execute("""SELECT DISTINCT tree_id, type_number FROM public.tree_microhabitats
                    WHERE provenance = 'reference' AND tree_id = ANY(%s)""", (trees.tree_id.tolist(),))
    found = pd.DataFrame(cur.fetchall(), columns=["tree_id", "type_number"])
    measured = pd.DataFrame({t: trees.tree_id.isin(found.tree_id[found.type_number == num]).astype(int)
                             for t, num in TYPE_MAP.items()}, index=trees.index)
    return trees, predict(levels, models, trees.genus, trees.living, trees.dbh_cm), measured


def draw(tree_ids: pd.Series, probs: pd.DataFrame, seed: int) -> pd.DataFrame:
    """1 where the seeded draw for (seed, tree, type) falls below the probability."""
    u = pd.DataFrame({t: [np.random.default_rng([seed, int(tid), TYPE_MAP[t]]).random() for tid in tree_ids]
                      for t in probs.columns}, index=probs.index)
    return (u < probs).astype(int)


# --------------------------------------------------------------------------- data

TREE_SQL = """
SELECT t.tree_id, l.location_name, split_part(sp.scientific_name, ' ', 1) AS genus,
       coalesce(ts.tree_status_name, '') AS status, s.dbh_cm
  FROM trees.trees t
  JOIN shared.locations l ON l.location_id = t.location_id
  JOIN shared.variants v ON v.variant_id = t.variant_id
  JOIN shared.variant_types vt ON vt.variant_type_id = v.variant_type_id AND vt.variant_type_name = 'original'
  LEFT JOIN shared.species sp ON sp.species_id = t.species_id
  LEFT JOIN trees.tree_status ts ON ts.tree_status_id = t.tree_status_id
  LEFT JOIN trees.stems s ON s.tree_id = t.tree_id AND s.stem_number = 1
 WHERE l.location_name = ANY(%s)
"""


def eligible(trees: pd.DataFrame) -> pd.DataFrame:
    keep = (trees.genus.isin(GENUS) & (trees.dbh_cm.astype(float) > MIN_DBH)
            & ~trees.status.isin(["downed", "harvested", "missing"]))
    out = trees[keep].copy()
    out["living"] = out.status != "dead"
    out["dbh_cm"] = out.dbh_cm.astype(float)
    return out


def load_trees(cur, locations: list[str]) -> pd.DataFrame:
    cur.execute(TREE_SQL, (locations,))
    return pd.DataFrame(cur.fetchall(), columns=["tree_id", "location", "genus", "status", "dbh_cm"])


# --------------------------------------------------------------------------- commands

def cmd_fetch() -> None:
    S1_PATH.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(S1_URL, timeout=120) as r:
        S1_PATH.write_bytes(r.read())
    print(f"wrote {S1_PATH.relative_to(REPO_ROOT)} ({S1_PATH.stat().st_size:,} bytes)")


def cmd_validate(cur) -> None:
    """Per marteloscope: raw model, model recalibrated on the other plots only, and measured rates."""
    levels, models = fit_all(load_training())
    trees, raw, measured = calibration_data(cur, levels, models)
    rows = []
    for loc in CALIB_PLOTS:
        sel = trees.location == loc
        if not sel.any():
            continue
        loo = shifted(raw[sel], calibration_shifts(raw[~sel], measured[~sel]))
        for t, num in TYPE_MAP.items():
            rows.append(dict(plot=loc, trees=int(sel.sum()), type=f"{num} {t}", raw=raw[t][sel].mean(),
                             recalibrated_loo=loo[t].mean(), measured=measured[t][sel].mean()))
    table = pd.DataFrame(rows)
    print(table.round(3).to_string(index=False))
    print("\nmicrohabitat types per tree (sum over the mapped types):")
    print(table.groupby("plot")[["raw", "recalibrated_loo", "measured"]].sum().round(2).to_string())
    print("\nshifts fitted on all plots (logit):",
          {t: round(s, 2) for t, s in calibration_shifts(raw, measured).items()})


def ensure_process(cur) -> int:
    cur.execute("SELECT process_id FROM shared.processes WHERE process_name = %s AND version = %s",
                (PROCESS["process_name"], VERSION))
    row = cur.fetchone()
    if row:
        cur.execute("""UPDATE shared.processes SET algorithm_name = %s, description = %s, author = %s,
                              citation = %s, category = %s, updated_at = now() WHERE process_id = %s""",
                    (PROCESS["algorithm_name"], PROCESS["description"], PROCESS["author"],
                     PROCESS["citation"], PROCESS["category"], row[0]))
        return row[0]
    cur.execute("""INSERT INTO shared.processes (process_name, algorithm_name, version, description, author,
                                                 citation, category)
                   VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING process_id""",
                (PROCESS["process_name"], PROCESS["algorithm_name"], VERSION, PROCESS["description"],
                 PROCESS["author"], PROCESS["citation"], PROCESS["category"]))
    return cur.fetchone()[0]


def cmd_apply(conn, cur, locations: list[str], seed: int, dry_run: bool) -> None:
    levels, models = fit_all(load_training())
    all_trees = load_trees(cur, locations)
    trees = eligible(all_trees)
    skipped = all_trees[~all_trees.tree_id.isin(trees.tree_id)]
    print(f"{len(all_trees)} baseline trees at {locations}; {len(trees)} eligible")
    print("no prediction (other genus, DBH <= 17.5 cm, or downed/harvested/missing), by genus:",
          skipped.genus.fillna("unknown").value_counts().to_dict())
    _, calib_raw, calib_measured = calibration_data(cur, levels, models)
    shifts = calibration_shifts(calib_raw, calib_measured)
    print(f"recalibrated on {len(calib_raw)} marteloscope trees; logit shifts:",
          {t: round(s, 2) for t, s in shifts.items()})
    probs = shifted(predict(levels, models, trees.genus, trees.living, trees.dbh_cm), shifts)
    hits = draw(trees.tree_id, probs, seed)
    print("drawn per type:", {f"{TYPE_MAP[t]} {t}": int(hits[t].sum()) for t in TYPE_MAP})
    print("per location:", hits.sum(axis=1).groupby(trees.location).sum().to_dict())
    if dry_run:
        print("[dry-run] nothing written")
        return

    process_id = ensure_process(cur)
    cur.execute("SELECT type_number, microhabitat_type_id FROM trees.microhabitat_types")
    type_id = dict(cur.fetchall())
    rows = []
    for idx, tid in trees.tree_id.items():
        for t, num in TYPE_MAP.items():
            if hits.at[idx, t]:
                rows.append((int(tid), type_id[num], round(float(probs.at[idx, t]), 4), process_id,
                             f'{{"paillet_type": "{t}", "seed": {seed}, "model_version": "{VERSION}"}}'))
    from psycopg2.extras import execute_values
    # Reruns replace this process's rows on these trees; other provenances are untouched.
    cur.execute("DELETE FROM trees.microhabitats WHERE provenance = 'predicted' AND process_id = %s "
                "AND tree_id = ANY(%s)", (process_id, trees.tree_id.astype(int).tolist()))
    deleted = cur.rowcount
    execute_values(cur, """INSERT INTO trees.microhabitats (tree_id, microhabitat_type_id, count, provenance,
                                                            probability, process_id, source_attributes, created_by)
                           VALUES %s""",
                   rows, template="(%s, %s, 1, 'predicted', %s, %s, %s::jsonb, 'predict_microhabitats')",
                   page_size=1000)
    conn.commit()
    print(f"process {process_id}: replaced {deleted} predicted rows with {len(rows)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("command", choices=["fetch", "validate", "apply"])
    ap.add_argument("--location", nargs="+", default=["ecosense", "mathisle"])
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if args.command == "fetch":
        cmd_fetch()
        return 0
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            if args.command == "validate":
                cmd_validate(cur)
            else:
                cmd_apply(conn, cur, args.location, args.seed, args.dry_run)
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
