#!/usr/bin/env bash
#
# Nightly logical backup of the digital twin database.
#
# WHAT IS AND IS NOT IN HERE, AND WHY
# -----------------------------------
# `sensor.sensor_readings` is excluded -- its DATA, not its definition, via
# --exclude-table-data, so a restore still has the table and its indexes and
# lands empty rather than missing.
#
# Measured 2026-09-10: the database is 8,455 MB and that one table is 8,391 MB
# of it -- 99.2%. Everything that cannot be regenerated (trees, variants,
# growthsimulations, provenance, locations, accounts, the audit log) is about
# 64 MB. Including the readings would cost 2-3 GB compressed per run, so even a
# week of retention would not fit the NFS export, and it would buy nothing that
# is not already recoverable: aquarius-connector re-fetches any window
# idempotently, keyed (sensor_id, timestamp), and the four seasonal windows the
# server holds are recorded in the handover.
#
# So: this backs up the irreplaceable 64 MB every night and treats the 8.4 GB
# as a cache. Restoring a cluster means this dump plus an aquarius re-sync.
#
# WHERE IT WRITES
# ---------------
# /media/data/dftdb/backups -- the 100 GB NFS export, NOT the 28 GB root LV.
# Writing backups to root is how this host has taken itself offline before.
#
# RUNNING IT
# ----------
#   scripts/server/backup-db.sh            # once, by hand
#   systemctl status dt-db-backup          # what the timer last did
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/media/data/dftdb/backups}"
CONTAINER="${DB_CONTAINER:-dftdb-db}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
# supabase_admin, not postgres: the app tables are owned by it and `postgres`
# is not a superuser in this image, so a dump as `postgres` silently misses
# tables it cannot read.
DB_USER="${DB_USER:-supabase_admin}"
DB_NAME="${DB_NAME:-postgres}"

log() { printf '[%s] %s\n' "$(date -u '+%H:%M:%S')" "$*"; }

[ -d "$BACKUP_DIR" ] || { log "FATAL: $BACKUP_DIR does not exist"; exit 1; }
[ -w "$BACKUP_DIR" ] || { log "FATAL: $BACKUP_DIR is not writable by $(id -un)"; exit 1; }

docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true \
    || { log "FATAL: container $CONTAINER is not running"; exit 1; }

STAMP="$(date -u '+%Y%m%d_%H%M%S')"
TARGET="$BACKUP_DIR/dftdb_${STAMP}.sql.gz"
# Write to a temp name and rename only on success, so a dump killed halfway
# never leaves something that looks like a usable backup.
TMP="$TARGET.partial"

log "dumping $DB_NAME from $CONTAINER (excluding sensorreadings data)"
if ! docker exec "$CONTAINER" pg_dump \
        -U "$DB_USER" -d "$DB_NAME" \
        --exclude-table-data='sensor.sensor_readings' \
     | gzip -6 > "$TMP"; then
    log "FATAL: pg_dump failed"
    rm -f -- "$TMP"
    exit 1
fi

# A pg_dump that fails mid-stream can still exit 0 through the pipe, so check
# the artefact rather than trusting the exit code: gzip integrity, and the
# trailer pg_dump writes only when it ran to completion.
if ! gzip -t "$TMP" 2>/dev/null; then
    log "FATAL: dump is not a valid gzip stream"
    rm -f -- "$TMP"
    exit 1
fi
if ! gzip -dc "$TMP" | tail -5 | grep -q 'PostgreSQL database dump complete'; then
    log "FATAL: dump has no completion trailer -- it was truncated"
    rm -f -- "$TMP"
    exit 1
fi

mv -- "$TMP" "$TARGET"
log "wrote $(basename "$TARGET") ($(du -h "$TARGET" | cut -f1))"

# Retention. -mtime +N is strictly older than N days, so 30 keeps ~31 files.
DELETED=$(find "$BACKUP_DIR" -maxdepth 1 -name 'dftdb_*.sql.gz' \
    -type f -mtime +"$RETENTION_DAYS" -print -delete | wc -l)
[ "$DELETED" -gt 0 ] && log "pruned $DELETED backup(s) older than $RETENTION_DAYS days"

# Clean up any .partial left by a previous kill -9.
find "$BACKUP_DIR" -maxdepth 1 -name '*.partial' -type f -mtime +1 -delete

log "held: $(find "$BACKUP_DIR" -maxdepth 1 -name 'dftdb_*.sql.gz' | wc -l) backup(s), $(du -sh "$BACKUP_DIR" | cut -f1) total"
