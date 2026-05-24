#!/usr/bin/env bash
# Shared helpers for wow-server setup scripts.
#
# Server adaptation of wow-steam-deck/scripts/lib/common.sh.
# All commands run locally — the `deck` function is just a local bash executor.
# No SSH, no DECK_HOST, no SteamOS assumptions.

set -euo pipefail

# Resolve repo root (parent of scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load .env if it exists; .env.example otherwise.
if [[ -f "$REPO_ROOT/.env" ]]; then
    set -a; source "$REPO_ROOT/.env"; set +a
elif [[ -f "$REPO_ROOT/.env.example" ]]; then
    echo "[common.sh] .env not found, using .env.example. Copy and edit it." >&2
    set -a; source "$REPO_ROOT/.env.example"; set +a
else
    echo "[common.sh] missing .env and .env.example" >&2
    exit 1
fi

: "${WOW_ROOT:=/data/wow}"

# On the server we always run locally.
# This shim means every script using deck "..." works without modification.
deck() {
    bash -c "$*"
}

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '[%s] FATAL: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }
