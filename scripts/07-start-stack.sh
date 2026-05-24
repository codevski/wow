#!/usr/bin/env bash
# Step 8 — start authserver + worldserver as standalone rootless containers
# on the ac-net network.
#
# Server differences from Deck version:
#   - Ports bind to 0.0.0.0 so LAN clients (Mac, etc.) can connect
#   - No memory caps (32 GB available)
#   - No --userns=keep-id quirks
#   - sudo podman throughout
#
# Exposed ports:
#   3724 — authserver (login)
#   8085 — worldserver (game)
#   7878 — soap (admin RPC; localhost only)
#
# Idempotent: running again starts any stopped containers without clobbering
# a running stack.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

DBPASS="${DOCKER_DB_ROOT_PASSWORD:-acorewotlk}"
BIND="${SERVER_BIND:-0.0.0.0}"

log "Ensuring network exists..."
sudo podman network exists ac-net || sudo podman network create ac-net

log "Ensuring MySQL is up..."
if ! sudo podman ps --format '{{.Names}}' | grep -q '^ac-database$'; then
    if sudo podman ps -a --format '{{.Names}}' | grep -q '^ac-database$'; then
        sudo podman start ac-database
    else
        die "MySQL container missing — run scripts/07-init-db.sh first"
    fi
fi

for i in $(seq 1 30); do
    sudo podman exec ac-database mysqladmin -uroot -p"$DBPASS" ping >/dev/null 2>&1 && break
    sleep 2
done

start_or_run() {
    local name="$1"; shift
    if sudo podman ps --format '{{.Names}}' | grep -q "^${name}$"; then
        log "${name}: already running"
    elif sudo podman ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        sudo podman start "$name" > /dev/null && log "${name}: started existing"
    else
        "$@" > /dev/null && log "${name}: created"
    fi
}

log "Starting ac-authserver..."
start_or_run ac-authserver sudo podman run -d \
    --name ac-authserver \
    --network ac-net \
    -e "AC_LOGIN_DATABASE_INFO=ac-database;3306;root;$DBPASS;acore_auth" \
    -e AC_LOGS_DIR=/azerothcore/env/dist/logs \
    -p "$BIND:${DOCKER_AUTH_EXTERNAL_PORT:-3724}:3724" \
    -v "$WOW_ROOT/configs:/azerothcore/env/dist/etc:Z" \
    -v "$WOW_ROOT/logs:/azerothcore/env/dist/logs:Z" \
    --restart unless-stopped \
    acore/ac-wotlk-authserver:local

log "Starting ac-worldserver..."
start_or_run ac-worldserver sudo podman run -d \
    --name ac-worldserver \
    --network ac-net \
    -e "AC_LOGIN_DATABASE_INFO=ac-database;3306;root;$DBPASS;acore_auth" \
    -e "AC_WORLD_DATABASE_INFO=ac-database;3306;root;$DBPASS;acore_world" \
    -e "AC_CHARACTER_DATABASE_INFO=ac-database;3306;root;$DBPASS;acore_characters" \
    -e "AC_PLAYERBOTS_DATABASE_INFO=ac-database;3306;root;$DBPASS;acore_playerbots" \
    -e AC_DATA_DIR=/azerothcore/env/dist/data \
    -e AC_LOGS_DIR=/azerothcore/env/dist/logs \
    -p "$BIND:${DOCKER_WORLD_EXTERNAL_PORT:-8085}:8085" \
    -p "127.0.0.1:${DOCKER_SOAP_EXTERNAL_PORT:-7878}:7878" \
    -v "$WOW_ROOT/configs:/azerothcore/env/dist/etc:Z" \
    -v "$WOW_ROOT/logs:/azerothcore/env/dist/logs:Z" \
    -v "$WOW_ROOT/data:/azerothcore/env/dist/data:ro,Z" \
    -v "$WOW_ROOT/server/ac/modules:/azerothcore/modules:ro,Z" \
    --restart unless-stopped \
    -i \
    acore/ac-wotlk-worldserver:local

log "Stack:"
sudo podman ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

log "Worldserver startup takes ~1–2 min. Tail logs with:"
log "  tail -f $WOW_ROOT/logs/Server.log"
log "Step 8 complete."
