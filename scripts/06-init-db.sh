#!/usr/bin/env bash
# Step 6 — download client map data, start MySQL, run db-import.
#
# ac-client-data-init downloads pre-extracted DBC/maps/vmaps/mmaps (~4 GB)
# from AzerothCore's CDN — no WoW client needed on the server.
# This only runs on first setup; subsequent starts use the cached data volume.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

DBPASS="${DOCKER_DB_ROOT_PASSWORD:-acorewotlk}"
REALM_ADDR="${REALM_ADDRESS:-192.168.1.6}"

log "Creating podman network ac-net (if missing)..."
sudo podman network exists ac-net || sudo podman network create ac-net

log "Starting MySQL (mysql:8.4)..."
if sudo podman ps -a --format '{{.Names}}' | grep -q '^ac-database$'; then
    sudo podman start ac-database > /dev/null
else
    sudo podman run -d --name ac-database --network ac-net \
        -e MYSQL_ROOT_PASSWORD="$DBPASS" \
        -p "127.0.0.1:${DOCKER_DB_EXTERNAL_PORT:-3306}:3306" \
        -v ac-database:/var/lib/mysql \
        --restart unless-stopped \
        docker.io/library/mysql:8.4 \
        --innodb-buffer-pool-size=1G --max-connections=200 > /dev/null
fi

log "Waiting for MySQL to become healthy..."
for i in $(seq 1 30); do
    if sudo podman exec ac-database mysqladmin -uroot -p"$DBPASS" ping >/dev/null 2>&1; then
        log "MySQL ok"
        break
    fi
    sleep 2
done

log "Downloading client map data via ac-client-data-init (~4 GB — may take a while)..."
sudo podman rm -f ac-client-data-init 2>/dev/null || true
sudo podman run --rm --name ac-client-data-init \
    -v "$WOW_ROOT/data:/azerothcore/env/dist/data:Z" \
    acore/ac-wotlk-client-data:local
log "Client data ready."

log "Pre-creating acore_playerbots database..."
sudo podman exec ac-database mysql -uroot -p"$DBPASS" \
    -e 'CREATE DATABASE IF NOT EXISTS acore_playerbots CHARACTER SET utf8mb4;' 2>/dev/null

log "Running ac-db-import (creates schemas, imports world data — ~5–10 min)..."
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

log "Pinning realmlist to $REALM_ADDR ..."
sudo podman exec ac-database mysql -uroot -p"$DBPASS" acore_auth \
    -e "UPDATE realmlist SET address='$REALM_ADDR', localAddress='$REALM_ADDR' WHERE id=1;"
sudo podman exec ac-database mysql -uroot -p"$DBPASS" acore_auth \
    -e 'SELECT id,name,address,localAddress FROM realmlist;'

log "Step 6 complete."
