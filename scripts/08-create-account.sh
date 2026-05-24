#!/usr/bin/env bash
# Step 9 — create a game account via the running worldserver console.
#
# Usage:
#   scripts/09-create-account.sh <username> <password> [gmlevel]
#
# gmlevel: 0 = player (default), 3 = full GM.
# Default is 3 — this is a private server, you want GM access.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

USER="${1:-${ACCT_USER:-admin}}"
PASS="${2:-${ACCT_PASS:-changeme}}"
GM_LEVEL="${3:-${ACCT_GM:-3}}"

if [[ ${#PASS} -gt 16 ]]; then
    die "WoW 3.3.5 max password length is 16 characters."
fi

log "Waiting for worldserver to be ready (port 8085)..."
for i in $(seq 1 30); do
    if sudo podman exec ac-worldserver bash -c 'exec 3<>/dev/tcp/127.0.0.1/8085' 2>/dev/null; then
        log "worldserver ready."
        break
    fi
    sleep 5
done

log "Creating account $USER (GM level $GM_LEVEL) via worldserver console..."
sudo podman exec ac-worldserver bash -c "echo 'account create $USER $PASS' > /proc/1/fd/0"
sleep 2
sudo podman exec ac-worldserver bash -c "echo 'account set gmlevel $USER $GM_LEVEL -1' > /proc/1/fd/0"
sleep 2

log "Verifying via DB:"
sudo podman exec ac-database mysql -uroot -p"${DOCKER_DB_ROOT_PASSWORD:-acorewotlk}" acore_auth \
    -e "SELECT a.id, a.username, aa.gmlevel FROM account a LEFT JOIN account_access aa ON aa.id=a.id WHERE a.username=UPPER('$USER');"

log "Account ready."
log "Set your client's realmlist.wtf → set realmlist ${REALM_ADDRESS:-192.168.1.6}"
log "Step 9 complete."
