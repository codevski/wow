#!/usr/bin/env bash
# backup.sh — dump 4 AC schemas to $WOW_ROOT/backups/wow-TAG-YYYYmmdd-HHMM.tar.zst
#
# Schemas: acore_auth, acore_characters, acore_world, acore_playerbots
# Also stores configs/ so a full restore is one tarball.
#
# Retention: keeps last $KEEP_DAILY daily + $KEEP_WEEKLY weekly archives.
#
# Usage:
#   scripts/backup.sh                # full snapshot
#   scripts/backup.sh --quick        # characters + auth only (fast, ~30 s)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

DBPASS="${DOCKER_DB_ROOT_PASSWORD:-acorewotlk}"
KEEP_DAILY="${KEEP_DAILY:-14}"
KEEP_WEEKLY="${KEEP_WEEKLY:-8}"

QUICK=0
[[ "${1:-}" == "--quick" ]] && QUICK=1

if (( QUICK )); then
    SCHEMAS="acore_auth acore_characters"
    TAG="quick"
else
    SCHEMAS="acore_auth acore_characters acore_world acore_playerbots"
    TAG="full"
fi

STAMP="$(date +%Y%m%d-%H%M)"
BACKUP_DIR="$WOW_ROOT/backups"
STAGING="$BACKUP_DIR/staging-$STAMP"
ARCHIVE="$BACKUP_DIR/wow-$TAG-$STAMP.tar.zst"
mkdir -p "$STAGING"

log "Ensuring DB is reachable..."
sudo podman exec ac-database mysqladmin -uroot -p"$DBPASS" ping >/dev/null \
    || die "DB not reachable — start it first (scripts/07-init-db.sh)"

log "Dumping schemas: $SCHEMAS"
cd "$STAGING"
for s in $SCHEMAS; do
    echo "--- dumping $s"
    sudo podman exec ac-database mysqldump -uroot -p"$DBPASS" \
        --single-transaction --routines --triggers --events \
        "$s" > "${s}.sql"
done
[[ -d "$WOW_ROOT/configs" ]] && cp -r "$WOW_ROOT/configs" configs || true
echo "tag=$TAG stamp=$STAMP host=$(hostname)" > MANIFEST
ls -lh

log "Compressing → $ARCHIVE ..."
cd "$BACKUP_DIR"
tar --zstd -cf "$(basename "$ARCHIVE")" "staging-$STAMP"
rm -rf "$STAGING"
ls -lh "$(basename "$ARCHIVE")"

log "Pruning old backups (keep $KEEP_DAILY daily, $KEEP_WEEKLY weekly)..."
cd "$BACKUP_DIR"
ls -1t wow-full-*.tar.zst  2>/dev/null | tail -n +$(( KEEP_DAILY  + 1 )) | xargs -r rm -v || true
ls -1t wow-quick-*.tar.zst 2>/dev/null | tail -n +$(( KEEP_WEEKLY + 1 )) | xargs -r rm -v || true

log "Backup ok: $ARCHIVE"
log "Restore: scripts/restore.sh $ARCHIVE"
