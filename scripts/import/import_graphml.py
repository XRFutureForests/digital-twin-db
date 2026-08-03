#!/usr/bin/env python3
"""
QSM topology GraphML import for Forest Digital Twin Database (XRFF-266)

Imports a networkx-compatible GraphML tree graph (BioDiv-3DTrees publishes
per-tree graphs in this format) into trees.TreeGraphEdges. Nodes carry a
`cylinder_index` attribute matching trees.QSMCylinders.cylinder_index; edges
carry an `edge_type` attribute ('observed' | 'synthetic').

Only non-'observed' edges are inserted: trees.qsmcylinders' own
cylinder_index/parent_cylinder_index chain already IS the full edge set (a
QSM cylinder tree has exactly one parent per cylinder), so an edge absent
from trees.TreeGraphEdges is assumed 'observed' by default. See the XRFF-266
migration's header comment for the full rationale and the edge_type values.

Usage:
    python import_graphml.py <graphml_file> --qsm-id <id>
"""

import argparse
import sys
from pathlib import Path

import networkx as nx
from psycopg2.extras import execute_values

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.db import get_db_connection


def insert_graph_edges(conn, qsm_id, graph):
    """Insert only the edges whose type deviates from the 'observed' default."""
    rows = [
        (
            qsm_id,
            int(graph.nodes[u]["cylinder_index"]),
            int(graph.nodes[v]["cylinder_index"]),
            data["edge_type"],
        )
        for u, v, data in graph.edges(data=True)
        if data.get("edge_type", "observed") != "observed"
    ]
    if not rows:
        return 0

    cur = conn.cursor()
    execute_values(
        cur,
        """
        INSERT INTO trees.treegraphedges (qsm_id, from_cylinder_index, to_cylinder_index, edge_type)
        VALUES %s
        ON CONFLICT (qsm_id, from_cylinder_index, to_cylinder_index) DO NOTHING
        """,
        rows,
    )
    return len(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("graphml_file", help="networkx-compatible GraphML tree graph")
    parser.add_argument("--qsm-id", type=int, required=True, help="trees.qsms.qsm_id this graph belongs to")
    args = parser.parse_args()

    graph = nx.read_graphml(args.graphml_file)

    conn = get_db_connection()
    try:
        inserted = insert_graph_edges(conn, args.qsm_id, graph)
        conn.commit()
        print(f"Imported {inserted} non-observed edges for QSM {args.qsm_id} ({graph.number_of_edges()} edges in source graph)")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
