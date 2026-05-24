#!/usr/bin/env bash
# Step 1 — create the workspace tree on the server.
#
# Layout (under $WOW_ROOT):
#   server/    AC source clone
#   client/    WoW 3.3.5a client Data/ for extraction (rsync from Mac/NAS)
#   data/      extracted DBC/maps/vmaps/mmaps (~4 GB)
#   db/        reserved (named volume holds the actual mysql data)
#   logs/      authserver / worldserver logs
#   configs/   *.conf files mounted into containers
#   backups/   DB snapshots from backup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

log "Creating workspace dirs under $WOW_ROOT ..."
mkdir -p "$WOW_ROOT"/{server,data,db,logs,configs,backups}

log "Setting ownership to $DOCKER_USER_ID:$DOCKER_GROUP_ID ..."
chown -R "${DOCKER_USER_ID}:${DOCKER_GROUP_ID}" "$WOW_ROOT"

log "Probing write access ..."
touch "$WOW_ROOT/.write_test" && rm "$WOW_ROOT/.write_test"

log "Workspace tree:"
ls -la "$WOW_ROOT"

log "Step 1 complete."
