#!/usr/bin/env python3
"""Check database column names."""
import os
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / "docker/.env")

user = os.getenv("POSTGRES_USER", "postgres")
tenant = os.getenv("POOLER_TENANT_ID", "")
if tenant:
    user = f"{user}.{tenant}"

conn = psycopg2.connect(
    host="localhost",
    user=user,
    password=os.getenv("POSTGRES_PASSWORD"),
    database=os.getenv("POSTGRES_DB", "postgres"),
    port=os.getenv("POSTGRES_PORT", "5432"),
)
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
