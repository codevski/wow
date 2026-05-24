#!/usr/bin/env bash
# setup-all.sh — master runner. Sequences steps 01→10 with checkpoint state
# so a re-run skips already-completed steps.
# Optional steps prompt for confirmation every time unless --yes or --no is set.
#
# Usage:
#   scripts/setup-all.sh                # run remaining steps, prompt for optional
#   scripts/setup-all.sh --from 04      # force start at step 04
#   scripts/setup-all.sh --only 10      # run a single step (still prompts if optional)
#   scripts/setup-all.sh --reset        # clear checkpoint state
#   scripts/setup-all.sh --dry-run      # print what would run
#   scripts/setup-all.sh --yes          # auto-yes all optional steps
#   scripts/setup-all.sh --no           # auto-skip all optional steps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

STATE_DIR="$REPO_ROOT/.omc/state"
STATE_FILE="$STATE_DIR/setup.json"
mkdir -p "$STATE_DIR"
[[ -f "$STATE_FILE" ]] || echo '{"completed":[]}' > "$STATE_FILE"

# id:script:desc:optional(0/1)
STEPS=(
    "01:01-init-workspace.sh:create workspace dirs:0"
    "02:02-clone-source.sh:clone AC fork + modules:0"
    "03:03-patch-dockerfile.sh:apply Dockerfile patch:0"
    "04:04-build-images.sh:build images (30–60 min):0"
    "05:05-populate-configs.sh:populate configs + tune playerbots:0"
    "06:06-init-db.sh:download map data + init MySQL + db-import:0"
    "07:07-start-stack.sh:start auth + world + db:0"
    "08:08-create-account.sh:create GM account:0"
    "09:09-pin-realmlist.sh:pin realmlist address in DB:0"
    "10:10-apply-rates.sh:apply x5 XP / x3 talents / boosted drops:1"
)

DRY=0; RESET=0; FROM=""; ONLY=""
AUTO=""   # "" = prompt, "yes" = auto-run optional, "no" = auto-skip optional

ACCT_USER="${ACCT_USER:-admin}"
ACCT_PASS="${ACCT_PASS:-changeme}"
ACCT_GM="${ACCT_GM:-3}"

while (($#)); do
    case "$1" in
        --from)    FROM="$2"; shift 2 ;;
        --only)    ONLY="$2"; shift 2 ;;
        --reset)   RESET=1; shift ;;
        --dry-run) DRY=1; shift ;;
        --yes)     AUTO="yes"; shift ;;
        --no)      AUTO="no"; shift ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done

if (( RESET )); then
    echo '{"completed":[]}' > "$STATE_FILE"
    log "State cleared: $STATE_FILE"
    exit 0
fi

# Pre-authenticate sudo so it doesn't expire mid-run
log "Caching sudo credentials..."
sudo -v

is_done() { grep -q "\"$1\"" "$STATE_FILE"; }

mark_done() {
    python3 - "$STATE_FILE" "$1" << 'PY'
import json, sys
p, step = sys.argv[1], sys.argv[2]
d = json.load(open(p))
if step not in d["completed"]:
    d["completed"].append(step)
json.dump(d, open(p, "w"), indent=2)
PY
}

confirm_optional() {
    local desc="$1"
    if [[ "$AUTO" == "yes" ]]; then return 0; fi
    if [[ "$AUTO" == "no"  ]]; then return 1; fi
    echo ""
    read -rp "  [optional] $desc — run this step? (y/N) " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

run_step() {
    local id="$1" script="$2" desc="$3" optional="$4"

    if [[ -n "$FROM" && "$id" < "$FROM" ]]; then
        log "[skip $id] before --from $FROM"
        return
    fi
    if [[ -n "$ONLY" && "$id" != "$ONLY" ]]; then
        return
    fi
    if is_done "$id" && [[ -z "$ONLY" && -z "$FROM" ]]; then
        log "[skip $id] $desc — already completed (use --from $id to redo)"
        return
    fi

    if (( DRY )); then
        local tag=""; (( optional )) && tag=" [optional]"
        log "[DRY $id] $script — $desc$tag"
        return
    fi

    # Optional steps always prompt (unless --yes/--no)
    if (( optional )); then
        if ! confirm_optional "$desc"; then
            log "[skip $id] $desc — skipped (will ask again next run)"
            return
        fi
    fi

    log "===== step $id: $desc ====="
    if [[ "$id" == "08" ]]; then
        "$SCRIPT_DIR/$script" "$ACCT_USER" "$ACCT_PASS" "$ACCT_GM"
    else
        "$SCRIPT_DIR/$script"
    fi
    mark_done "$id"
    log "===== step $id done ====="
}

for entry in "${STEPS[@]}"; do
    IFS=":" read -r id script desc optional <<< "$entry"
    run_step "$id" "$script" "$desc" "$optional"
done

log "All done. Stack status:"
"$SCRIPT_DIR/status.sh"
