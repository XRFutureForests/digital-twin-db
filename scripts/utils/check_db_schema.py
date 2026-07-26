#!/usr/bin/env python3
"""Check database column names."""
# Uses the shared connection helper. The previous inline copy resolved
# `docker/.env` from `scripts/` instead of the repo root, so it never actually
# loaded the file and depended on credentials already being in the ambient
# environment. It also hardcoded host=localhost.
from db import get_db_connection

conn = get_db_connection()
cur = conn.cursor()

# Check Species columns
cur.execute(
    "SELECT column_name FROM information_schema.columns WHERE table_schema='shared' AND table_name='species'"
)
print("Species columns:", [r[0] for r in cur.fetchall()])

# Sample data
cur.execute("SELECT * FROM shared.Species LIMIT 3")
cols = [desc[0] for desc in cur.description]
print("Species query columns:", cols)
for row in cur.fetchall():
    print("  ", row)

# Check Locations columns
cur.execute(
    "SELECT column_name FROM information_schema.columns WHERE table_schema='shared' AND table_name='locations'"
)
print("\nLocations columns:", [r[0] for r in cur.fetchall()])

cur.execute("SELECT * FROM shared.Locations LIMIT 3")
cols = [desc[0] for desc in cur.description]
print("Locations query columns:", cols)

# Check TreeStatus columns
cur.execute(
    "SELECT column_name FROM information_schema.columns WHERE table_schema='trees' AND table_name='treestatus'"
)
print("\nTreeStatus columns:", [r[0] for r in cur.fetchall()])

conn.close()
conn.close()
