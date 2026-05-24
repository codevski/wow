#!/usr/bin/env bash
# update.sh — pull AC fork + 3 modules, rebuild images, run db-import
# (handles schema migrations idempotently), restart stack.
#
# Usage:
#   scripts/update.sh                    # full update
#   scripts/update.sh --no-build         # skip rebuild (configs/sql only)
#   scripts/update.sh --no-restart       # leave stack stopped after migrate
#
# Takes a DB snapshot before touching anything.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CORE_DIR="$WOW_ROOT/server/ac"
DBPASS="${DOCKER_DB_ROOT_PASSWORD:-acorewotlk}"

DO_BUILD=1; DO_RESTART=1
while (($#)); do
    case "$1" in
        --no-build)   DO_BUILD=0; shift ;;
        --no-restart) DO_RESTART=0; shift ;;
        -h|--help)    sed -n '2,10p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done

log "Pre-update DB backup..."
"$SCRIPT_DIR/backup.sh" || die "backup failed — refusing to update"

log "Stopping worldserver + authserver (DB stays up for migrations)..."
for c in ac-worldserver ac-authserver; do
    sudo podman ps --format '{{.Names}}' | grep -q "^${c}$" \
        && sudo podman stop -t 30 "$c" > /dev/null || true
done

log "Pulling AC core (fork)..."
cd "$CORE_DIR" && git pull --ff-only || die "core pull failed — bailing"

log "Pulling modules..."
cd "$CORE_DIR/modules"
for m in mod-playerbots mod-ah-bot mod-individual-progression; do
    [[ -d "$m/.git" ]] || die "$m missing — run scripts/02-clone-source.sh"
    echo "--- $m"
    (cd "$m" && git pull --ff-only)
done

if (( DO_BUILD )); then
    log "Rebuilding images (tail $WOW_ROOT/logs/build.log)..."
    "$SCRIPT_DIR/04-build-images.sh"
else
    log "[skip] rebuild (--no-build)"
fi

log "Running db-import for migrations..."
sudo podman rm -f ac-db-import 2>/dev/null || true
sudo podman run --rm --name ac-db-import --network ac-net \
    -e "AC_LOGIN_DATABASE_INFO=ac-database;3306;root;$DBPASS;acore_auth" \
    -e "AC_WORLD_DATABASE_INFO=ac-database;3306;root;$DBPASS;acore_world" \
    -e "AC_CHARACTER_DATABASE_INFO=ac-database;3306;root;$DBPASS;acore_characters" \
    -e AC_DATA_DIR=/azerothcore/env/dist/data \
    -e AC_LOGS_DIR=/azerothcore/env/dist/logs \
    -v "$WOW_ROOT/configs:/azerothcore/env/dist/etc:Z" \
    -v "$WOW_ROOT/logs:/azerothcore/env/dist/logs:Z" \
    acore/ac-wotlk-db-import:local 2>&1 | grep -E 'Applied|Halting|Error' | tail -10

if (( DO_RESTART )); then
    log "Removing old container shells (image likely rebuilt)..."
    for c in ac-worldserver ac-authserver; do
        sudo podman ps -a --format '{{.Names}}' | grep -q "^${c}$" \
            && sudo podman rm -f "$c" > /dev/null || true
    done
    log "Starting fresh stack..."
    "$SCRIPT_DIR/07-start-stack.sh"
else
    log "[skip] restart (--no-restart)"
fi

log "Update complete. Tail: tail -f $WOW_ROOT/logs/Server.log"
