#!/usr/bin/env bash
# Step 4 — build all five podman images locally.
#
# - ac-wotlk-db-import    (~1.2 GB)
# - ac-wotlk-authserver   (~180 MB)
# - ac-wotlk-worldserver  (~680 MB) — links mod-playerbots, mod-ah-bot, mod-individual-progression
# - ac-wotlk-tools        (~700 MB) — for client data extraction
# - ac-wotlk-client-data  (~500 MB) — downloads pre-extracted map data on first run
#
# First build is 30–60 min, mostly compiling the worldserver.
# Logs go to $WOW_ROOT/logs/build.log — tail it in another terminal.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CORE_DIR="$WOW_ROOT/server/ac"
BUILD_LOG="$WOW_ROOT/logs/build.log"
mkdir -p "$WOW_ROOT/logs"

BUILD_ARGS=(
    --build-arg "USER_ID=${DOCKER_USER_ID:-1000}"
    --build-arg "GROUP_ID=${DOCKER_GROUP_ID:-1000}"
    --build-arg "DOCKER_USER=${DOCKER_USER:-acore}"
    -f "$CORE_DIR/apps/docker/Dockerfile"
)

build_target() {
    local target="$1" tag="$2"
    log "Building $tag (target=$target) — logging to $BUILD_LOG"
    sudo podman build \
        "${BUILD_ARGS[@]}" \
        --target "$target" \
        -t "acore/$tag:local" \
        "$CORE_DIR" >> "$BUILD_LOG" 2>&1
    log "$tag built ok."
}

log "Starting builds. Tail progress: tail -f $BUILD_LOG"
log "This will take 30–60 min on first run."

build_target db-import    ac-wotlk-db-import
build_target authserver   ac-wotlk-authserver
build_target worldserver  ac-wotlk-worldserver
build_target tools        ac-wotlk-tools
build_target client-data  ac-wotlk-client-data

log "Built images:"
sudo podman images | grep acore

log "Step 4 complete."
