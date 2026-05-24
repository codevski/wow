# wow-server

Self-hosted WoW 3.3.5a (WotLK) server with Playerbots on NixOS via rootless Podman.

Adapted from [sasha-sup/wow-steam-deck](https://github.com/sasha-sup/wow-steam-deck) — all Steam Deck / SteamOS specifics removed, server-tuned for LAN play.

**Stack:** AzerothCore ([liyunfan1223 Playerbot fork](https://github.com/liyunfan1223/azerothcore-wotlk)) + mod-playerbots + mod-ah-bot + mod-individual-progression, containerised with rootless Podman.

---

## Prerequisites

- NixOS with Podman enabled (`virtualisation.podman.enable = true`)
- ~60 GB free disk space (images + extracted data + DB)
- WoW 3.3.5a client data (build 12340) — `Data/` folder only, for map extraction
- Your Mac/client machine's `realmlist.wtf` pointing at the server LAN IP

---

## First-time setup

### 1. Clone and configure

```bash
git clone <your-repo-url> ~/homelab/wow-server
cd ~/homelab/wow-server
cp .env.example .env
nano .env   # set WOW_ROOT, REALM_ADDRESS, DOCKER_DB_ROOT_PASSWORD
```

The three values that matter:

```bash
WOW_ROOT=/data/wow          # where all server data lives
REALM_ADDRESS=192.168.1.6   # your server's LAN IP
DOCKER_DB_ROOT_PASSWORD=... # anything, internal only
```

### 2. Copy WoW client data

The map extractor needs the `Data/` folder from a WoW 3.3.5a (build 12340) client. rsync it from your Mac before running step 06:

```bash
rsync -ah --progress /path/to/WoW-3.3.5a/Data/ nixos:/data/wow/client/Data/
```

### 3. Run setup

```bash
bash scripts/setup-all.sh
```

Steps run in order with checkpoints — a re-run skips already-completed steps.

| Step | What it does | Time |
|------|-------------|------|
| 01 | Create workspace dirs | <1 min |
| 02 | Clone AzerothCore fork + 3 modules | 5–15 min |
| 03 | Apply Dockerfile patch (ARG fix) | <1 min |
| 04 | Build Podman images | **30–60 min** |
| 05 | Populate config files, tune playerbots | <1 min |
| 06 | Download map data (~4 GB), start MySQL, run db-import | 15–30 min |
| 07 | Start auth + worldserver | 1–2 min |
| 08 | Create GM account | <1 min |
| 09 | Pin realmlist address in DB | <1 min |
| 10 | Apply x5 XP / x3 talent rate preset (optional) | <1 min |

> **Note:** Step 06 is gated — it will stop and ask you to rsync the client data if `$WOW_ROOT/client/Data/` is missing.

### 4. Connect from your Mac

Edit your WoW client's `Data/enUS/realmlist.wtf` (adjust locale folder as needed):

```
set realmlist 192.168.1.6
```

Launch the client, log in with the account created in step 09.

---

## Day-to-day

```bash
# Check stack health
bash scripts/status.sh

# Stop the stack
bash scripts/stop.sh

# Start the stack (idempotent)
bash scripts/08-start-stack.sh

# Follow worldserver logs
tail -f $WOW_ROOT/logs/Server.log

# Follow authserver logs
tail -f $WOW_ROOT/logs/Auth.log

# Tail the image build log (step 04 — open a second terminal while it runs)
tail -f $WOW_ROOT/logs/build.log

# Worldserver console (GM commands etc.)
sudo podman exec -it ac-worldserver bash -c 'cat > /proc/1/fd/0'
```

> **Step 11 (XP/drop rate changes) is optional.** To skip it, pre-mark it done before running setup:
> ```bash
> python3 - << 'PY'
> import json, os
> p = os.path.expanduser('~/homelab/wow/.omc/state/setup.json')
> d = json.load(open(p))
> if '11' not in d['completed']:
>     d['completed'].append('11')
> json.dump(d, open(p, 'w'), indent=2)
> print('step 11 will be skipped')
> PY
> ```
> Or apply it any time later manually: `bash scripts/11-apply-rates.sh`

---

## Updating

```bash
# Full update: git pull + rebuild + db migrations + restart (~45-60 min)
bash scripts/update.sh

# Skip rebuild (config/SQL changes only, ~5 min)
bash scripts/update.sh --no-build
```

Takes a DB backup automatically before touching anything.

If the Dockerfile patch conflicts after an upstream update:

```bash
# See what broke
git -C /data/wow/server/ac apply --reject patches/dockerfile-args.patch

# Fix the .rej files, then regenerate the patch
git -C /data/wow/server/ac diff apps/docker/Dockerfile > patches/dockerfile-args.patch
```

---

## Backup / restore

```bash
# Full snapshot (all 4 schemas + configs → tar.zst)
bash scripts/backup.sh

# Characters + auth only (faster)
bash scripts/backup.sh --quick

# Restore latest snapshot
bash scripts/restore.sh --latest

# Restore specific archive
bash scripts/restore.sh /data/wow/backups/wow-full-20250523-0400.tar.zst
```

Backups live in `$WOW_ROOT/backups/`. Retention: 14 daily, 8 weekly (configurable in `.env`).

---

## NixOS autostart (optional)

The stack uses `--restart unless-stopped` so Podman restores containers on reboot automatically. If you want systemd-managed boot ordering, watchdog timer, and logrotate, copy the NixOS module:

```bash
sudo cp nixos/wow-server.nix /etc/nixos/modules/
# Add ./modules/wow-server.nix to your flake imports
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

---

## Folder structure

```
wow-server/
├── .env.example           # copy to .env and edit
├── patches/
│   └── dockerfile-args.patch   # ARG propagation fix for upstream Dockerfile
├── scripts/
│   ├── lib/common.sh      # shared helpers
│   ├── 01–11-*.sh         # numbered setup steps
│   ├── setup-all.sh       # master runner (sequences 01→11)
│   ├── status.sh          # stack health check
│   ├── stop.sh            # graceful shutdown
│   ├── backup.sh          # DB snapshot
│   ├── restore.sh         # restore from snapshot
│   └── update.sh          # pull + rebuild + migrate
└── nixos/
    └── wow-server.nix     # optional: systemd services + timers + logrotate
```
