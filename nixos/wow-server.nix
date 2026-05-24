{ config, pkgs, lib, ... }:

# NixOS module for the AzerothCore WoW server stack.
#
# Replaces the Deck's install-autostart.sh + install-watchdog.sh + install-logrotate.sh.
# Provides:
#   - systemd services for ac-database, ac-authserver, ac-worldserver
#   - wow-watchdog timer (1 min port check, restarts dead containers)
#   - wow-backup timer (daily at 04:00, zstd-compressed mysqldump)
#   - logrotate for Server.log / Auth.log
#   - firewall rules for ports 3724 + 8085
#
# Add to your flake imports:
#   ./modules/wow-server.nix
#
# Then: sudo nixos-rebuild switch --flake /etc/nixos#nixos

let
  wowRoot  = "/data/wow";
  dbPass   = "acorewotlk";  # keep in sync with .env DOCKER_DB_ROOT_PASSWORD
  scripts  = "/home/codevski/homelab/wow/scripts";

  # Helper: check if a podman container is running by name.
  containerRunning = name:
    "${pkgs.podman}/bin/podman ps --format '{{.Names}}' | ${pkgs.gnugrep}/bin/grep -q '^${name}$'";

in {

  # ── Firewall ────────────────────────────────────────────────────────────────
  networking.firewall.allowedTCPPorts = [
    3724   # authserver (login)
    8085   # worldserver (game)
  ];

  # ── Logrotate ───────────────────────────────────────────────────────────────
  services.logrotate = {
    enable = true;
    settings."${wowRoot}/logs" = {
      files        = "${wowRoot}/logs/*.log";
      rotate       = 7;
      frequency    = "daily";
      compress     = true;
      delaycompress = true;
      missingok    = true;
      notifempty   = true;
      copytruncate = true;
    };
  };

  # ── Systemd services ────────────────────────────────────────────────────────
  systemd.services = {

    # Database — just restart the existing named container.
    # The container itself is created by 07-init-db.sh; this service keeps it up.
    ac-database = {
      description = "AzerothCore MySQL database container";
      after       = [ "network.target" "podman.service" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig = {
        Type      = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "ac-database-start" ''
          set -euo pipefail
          ${pkgs.podman}/bin/podman network exists ac-net \
            || ${pkgs.podman}/bin/podman network create ac-net
          if ${pkgs.podman}/bin/podman ps -a --format '{{.Names}}' \
              | ${pkgs.gnugrep}/bin/grep -q '^ac-database$'; then
            ${pkgs.podman}/bin/podman start ac-database
          else
            echo "ac-database container missing — run scripts/07-init-db.sh first" >&2
            exit 1
          fi
          # Wait for healthy
          for i in $(seq 1 30); do
            ${pkgs.podman}/bin/podman exec ac-database mysqladmin \
              -uroot -p${dbPass} ping >/dev/null 2>&1 && exit 0
            sleep 2
          done
          echo "ac-database did not become healthy in time" >&2
          exit 1
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop -t 30 ac-database";
      };
    };

    ac-authserver = {
      description = "AzerothCore auth server container";
      after       = [ "ac-database.service" ];
      requires    = [ "ac-database.service" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig = {
        Type      = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "ac-authserver-start" ''
          set -euo pipefail
          if ${pkgs.podman}/bin/podman ps -a --format '{{.Names}}' \
              | ${pkgs.gnugrep}/bin/grep -q '^ac-authserver$'; then
            ${pkgs.podman}/bin/podman start ac-authserver
          else
            echo "ac-authserver container missing — run scripts/08-start-stack.sh first" >&2
            exit 1
          fi
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop -t 30 ac-authserver";
      };
    };

    ac-worldserver = {
      description = "AzerothCore world server container";
      after       = [ "ac-database.service" "ac-authserver.service" ];
      requires    = [ "ac-database.service" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig = {
        Type      = "oneshot";
        RemainAfterExit = true;
        RestartSec = "10s";
        ExecStart = pkgs.writeShellScript "ac-worldserver-start" ''
          set -euo pipefail
          if ${pkgs.podman}/bin/podman ps -a --format '{{.Names}}' \
              | ${pkgs.gnugrep}/bin/grep -q '^ac-worldserver$'; then
            ${pkgs.podman}/bin/podman start ac-worldserver
          else
            echo "ac-worldserver container missing — run scripts/08-start-stack.sh first" >&2
            exit 1
          fi
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop -t 60 ac-worldserver";
      };
    };

    # Watchdog oneshot — called by timer every minute.
    wow-watchdog = {
      description = "AzerothCore stack port watchdog";
      after       = [ "ac-worldserver.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "wow-watchdog" ''
          set -euo pipefail
          # Only watchdog if the container is supposed to be running
          ${pkgs.podman}/bin/podman ps --format '{{.Names}}' \
            | ${pkgs.gnugrep}/bin/grep -q '^ac-worldserver$' || exit 0

          if ${pkgs.podman}/bin/podman exec ac-worldserver \
              bash -c 'exec 3<>/dev/tcp/127.0.0.1/8085' 2>/dev/null; then
            exit 0
          fi
          echo "[$(date -Is)] worldserver port 8085 dead — restarting" >&2
          ${pkgs.podman}/bin/podman restart ac-worldserver
        '';
      };
    };

    # Daily backup oneshot — called by timer at 04:00.
    wow-backup = {
      description = "AzerothCore daily DB backup";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${scripts}/backup.sh";
      };
    };

  };

  # ── Systemd timers ──────────────────────────────────────────────────────────
  systemd.timers = {

    wow-watchdog = {
      wantedBy    = [ "timers.target" ];
      timerConfig = {
        OnBootSec       = "5min";
        OnUnitActiveSec = "1min";
        Unit            = "wow-watchdog.service";
      };
    };

    wow-backup = {
      wantedBy    = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:00:00";
        Persistent = true;
        Unit       = "wow-backup.service";
      };
    };

  };
}
