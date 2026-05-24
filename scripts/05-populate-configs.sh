#!/usr/bin/env bash
# Step 5 — populate $WOW_ROOT/configs/ with default *.conf files and tune
# playerbots for server hardware (manual bots only — no random world bots).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

log "Running worldserver entrypoint to populate $WOW_ROOT/configs/ ..."
sudo podman run --rm --userns=keep-id \
    -v "$WOW_ROOT/configs:/azerothcore/env/dist/etc:Z" \
    acore/ac-wotlk-worldserver:local true 2>&1 | tail -5

log "Copying remaining *.conf.dist → *.conf..."
cd "$WOW_ROOT/configs"
for f in authserver dbimport; do
    [[ -f "${f}.conf" ]] || cp "${f}.conf.dist" "${f}.conf"
done
mkdir -p modules
for f in mod_ahbot playerbots individualProgression; do
    [[ -f "modules/${f}.conf" ]] || cp "modules/${f}.conf.dist" "modules/${f}.conf"
done

log "Tuning playerbots.conf — manual bots only, no random world bots..."
sed -i \
    -e 's/^AiPlayerbot.MinRandomBots = .*/AiPlayerbot.MinRandomBots = 0/' \
    -e 's/^AiPlayerbot.MaxRandomBots = .*/AiPlayerbot.MaxRandomBots = 0/' \
    -e 's/^AiPlayerbot.RandomBotsPerInterval = .*/AiPlayerbot.RandomBotsPerInterval = 0/' \
    -e 's/^AiPlayerbot.RandomBotAutologin = .*/AiPlayerbot.RandomBotAutologin = 0/' \
    "$WOW_ROOT/configs/modules/playerbots.conf"

grep -E '^AiPlayerbot\.(Enabled|MinRandomBots|MaxRandomBots|RandomBotsPerInterval|RandomBotAutologin) ' \
    "$WOW_ROOT/configs/modules/playerbots.conf"

log "Step 5 complete."
