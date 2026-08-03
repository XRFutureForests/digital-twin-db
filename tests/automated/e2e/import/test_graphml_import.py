"""
Round-trip test for XRFF-266 (trees.TreeGraphEdges).

Imports a QSM (reusing the XRFF-265 fixture/importer) and its companion
GraphML topology graph, then confirms the full edge set -- reconstructed from
trees.qsmcylinders' parent chain overridden by trees.TreeGraphEdges -- matches
the original graph exactly, including the observed/synthetic distinction.

fixtures/sample_qsm_graph.graphml is a synthetic networkx-generated fixture
matching sample_qsm_cylinders.csv's topology (trunk 1-2-3, branch 3-4-5), with
edge (3,4) -- the branching point -- flagged 'synthetic'. Not an actual
downloaded BioDiv-3DTrees graph (see test_qsm_import.py's docstring for why:
the real dataset is only distributed as ~100 GB archives).
"""

import sys
from pathlib import Path

import networkx as nx
import pandas as pd
import pytest

REPO_ROOT = Path(__file__).parents[4]
sys.path.insert(0, str(REPO_ROOT / "scripts"))
sys.path.insert(0, str(REPO_ROOT / "scripts" / "import"))
from import_graphml import insert_graph_edges
from import_qsm import insert_qsm
from utils.db import get_db_connection

CSV_FIXTURE = Path(__file__).parent / "fixtures" / "sample_qsm_cylinders.csv"
GRAPHML_FIXTURE = Path(__file__).parent / "fixtures" / "sample_qsm_graph.graphml"


class Args:
    point_cloud_id = None
    process_id = None
    local_crs = "local"
    is_corrected = True
    twig_radius_mm = None


@pytest.fixture
def conn():
    connection = get_db_connection()
    yield connection
    connection.rollback()
    connection.close()


@pytest.fixture
def existing_tree_id(conn):
    cur = conn.cursor()
    cur.execute("SELECT tree_id FROM trees.trees LIMIT 1")
    row = cur.fetchone()
    assert row is not None, "no rows in trees.trees to attach a test QSM to"
    return row[0]


def test_graphml_edge_round_trip(conn, existing_tree_id):
    df = pd.read_csv(CSV_FIXTURE)
    qsm_id, _, _ = insert_qsm(conn, existing_tree_id, df, Args())

    source_graph = nx.read_graphml(GRAPHML_FIXTURE)
    expected_edges = {
        (int(source_graph.nodes[u]["cylinder_index"]), int(source_graph.nodes[v]["cylinder_index"])): data["edge_type"]
        for u, v, data in source_graph.edges(data=True)
    }

    inserted = insert_graph_edges(conn, qsm_id, source_graph)
    # Only the one deviating ('synthetic') edge should be materialised.
    assert inserted == 1

    cur = conn.cursor()
    cur.execute(
        "SELECT from_cylinder_index, to_cylinder_index, edge_type FROM trees.treegraphedges WHERE qsm_id = %s",
        (qsm_id,),
    )
    override_rows = cur.fetchall()
    assert override_rows == [(3, 4, "synthetic")]

    # Reconstruct the full edge set from qsmcylinders' parent chain, with
    # trees.TreeGraphEdges overriding the 'observed' default where present.
    cur.execute(
        "SELECT cylinder_index, parent_cylinder_index FROM trees.qsmcylinders WHERE qsm_id = %s AND parent_cylinder_index != 0",
        (qsm_id,),
    )
    overrides = {(f, t): et for f, t, et in override_rows}
    reconstructed_edges = {}
    for cylinder_index, parent_index in cur.fetchall():
        edge = (parent_index, cylinder_index)
        reconstructed_edges[edge] = overrides.get(edge, "observed")

    assert reconstructed_edges == expected_edges
