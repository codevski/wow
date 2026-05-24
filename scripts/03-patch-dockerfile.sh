#!/usr/bin/env bash
# Step 3 — apply patches/ to the cloned AC fork.
#
# patches/dockerfile-args.patch — re-declares ARG USER_ID / GROUP_ID /
# DOCKER_USER at the top of every child stage (authserver, worldserver,
# db-import, client-data, tools). Without this, Buildah/Podman treats them
# as empty strings and the COPY --chown step fails with:
#   Error: looking up UID/GID for ":": can't find uid for user :
#
# Idempotent:
#   - patch: skipped if already applied (ARG count check)
#
# Updating after an upstream Dockerfile change:
#   git -C $WOW_ROOT/server/ac apply --reject $REPO_ROOT/patches/dockerfile-args.patch
#   # fix the .rej hunks manually, then:
#   git -C $WOW_ROOT/server/ac diff apps/docker/Dockerfile > $REPO_ROOT/patches/dockerfile-args.patch

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CORE_DIR="$WOW_ROOT/server/ac"
PATCH="$REPO_ROOT/patches/dockerfile-args.patch"
DOCKERFILE="$CORE_DIR/apps/docker/Dockerfile"

[[ -f "$PATCH" ]] || die "patch file missing: $PATCH"

log "Applying $PATCH ..."

ARG_COUNT=$(grep -c 'ARG DOCKER_USER=acore' "$DOCKERFILE" 2>/dev/null || true)
if [[ "$ARG_COUNT" -ge 6 ]]; then
    log "Patch already applied — skipping."
else
    if patch -d "$CORE_DIR" -p1 --dry-run < "$PATCH" >/dev/null 2>&1; then
        patch -d "$CORE_DIR" -p1 < "$PATCH"
        log "Patch applied successfully."
    else
        log "Patch does not apply cleanly:"
        patch -d "$CORE_DIR" -p1 --dry-run < "$PATCH" 2>&1 || true
        log ""
        log "Reset and regenerate the patch:"
        log "  git -C $CORE_DIR checkout apps/docker/Dockerfile"
        log "  # manually apply fixes, then:"
        log "  git -C $CORE_DIR diff apps/docker/Dockerfile > $PATCH"
        die "patch failed — resolve manually"
    fi
fi

log "Verifying Dockerfile ARG counts:"
grep -n '^ARG DOCKER_USER' "$DOCKERFILE"

log "Step 3 complete."
