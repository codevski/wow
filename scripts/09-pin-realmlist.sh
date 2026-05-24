#!/usr/bin/env bash
# Step 10 — pin the realmlist address in the database.
#
# Replaces the Deck's 10-install-lutris.sh. On the server there's no client
# to configure — point your Mac client's realmlist.wtf at REALM_ADDRESS.
#
# Your Mac client: Data/enUS/realmlist.wtf (or your locale folder)
#   set realmlist 192.168.1.6
#
# This script updates the DB in case you changed REALM_ADDRESS in .env
# or ran 07-init-db.sh before setting the correct IP.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

DBPASS="${DOCKER_DB_ROOT_PASSWORD:-acorewotlk}"
REALM_ADDR="${REALM_ADDRESS:-192.168.1.6}"

log "Updating realmlist in DB to $REALM_ADDR ..."
sudo podman exec ac-database mysql -uroot -p"$DBPASS" acore_auth \
    -e "UPDATE realmlist SET address='$REALM_ADDR', localAddress='$REALM_ADDR' WHERE id=1;"

log "Current realmlist:"
sudo podman exec ac-database mysql -uroot -p"$DBPASS" acore_auth \
    -e 'SELECT id,name,address,localAddress,port FROM realmlist;'

log "Step 10 complete."
log "Mac client: set Data/enUS/realmlist.wtf → 'set realmlist $REALM_ADDR'"
