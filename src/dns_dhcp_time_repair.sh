#!/usr/bin/env bash
set -u

FLUSH_DNS=false
INTERFACE=""
RENEW_DHCP=false
RESTART_NETWORK=false
RESTART_TIME=false
STEP_CLOCK=false
DRY_RUN=false
ASSUME_YES=false
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage(){ cat <<'EOF'
Usage: dns_dhcp_time_repair.sh [options]

  --flush-dns              Flush resolver caches and restart the resolver.
  --interface IFACE        Interface used by --renew-dhcp.
  --renew-dhcp             Renew DHCP on the selected interface.
  --restart-network        Restart the active network-management service.
  --restart-time           Restart the active time-synchronisation service.
  --step-clock             Request an immediate chrony clock correction.
  --dry-run                Show commands without changing the host.
  --yes                    Skip confirmation prompts.
  --output DIR             Save logs and before/after verification in DIR.
EOF
}
while [ "$#" -gt 0 ]; do case "$1" in
  --flush-dns) FLUSH_DNS=true; shift;; --interface) INTERFACE="${2:-}"; shift 2;;
  --renew-dhcp) RENEW_DHCP=true; shift;; --restart-network) RESTART_NETWORK=true; shift;;
  --restart-time) RESTART_TIME=true; shift;; --step-clock) STEP_CLOCK=true; shift;;
  --dry-run) DRY_RUN=true; shift;; --yes) ASSUME_YES=true; shift;;
  --output) OUTPUT_DIR="${2:-}"; shift 2;; -h|--help) usage; exit 0;;
  *) echo "Unknown argument: $1" >&2; usage; exit 2;; esac; done
if ! $FLUSH_DNS && ! $RENEW_DHCP && ! $RESTART_NETWORK && ! $RESTART_TIME && ! $STEP_CLOCK; then echo "Choose at least one repair action." >&2; exit 2; fi
if $RENEW_DHCP; then [ -n "$INTERFACE" ] || { echo "--interface is required." >&2; exit 2; }; ip link show "$INTERFACE" >/dev/null 2>&1 || { echo "Interface not found: $INTERFACE" >&2; exit 2; }; fi
STAMP=$(date +%Y%m%d_%H%M%S); OUTPUT_DIR="${OUTPUT_DIR:-./dns-dhcp-time-repair-$STAMP}"; mkdir -p "$OUTPUT_DIR"; LOG="$OUTPUT_DIR/repair.log"; BEFORE="$OUTPUT_DIR/before.txt"; AFTER="$OUTPUT_DIR/after.txt"; : >"$LOG"
log(){ printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
confirm(){ $ASSUME_YES && return 0; read -r -p "$1 [y/N]: " a; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac; }
run(){ local d="$1"; shift; ACTIONS=$((ACTIONS+1)); log "$d"; if $DRY_RUN; then printf 'DRY-RUN:' >>"$LOG"; printf ' %q' "$@" >>"$LOG"; printf '\n' >>"$LOG"; return 0; fi; if "$@" >>"$LOG" 2>&1; then log "SUCCESS: $d"; else FAILURES=$((FAILURES+1)); log "WARNING: $d failed"; return 1; fi; }
root(){ local d="$1"; shift; if [ "$(id -u)" -eq 0 ]; then run "$d" "$@"; else run "$d" sudo "$@"; fi; }
network_manager(){ systemctl is-active --quiet NetworkManager 2>/dev/null && { echo NetworkManager; return; }; systemctl is-active --quiet systemd-networkd 2>/dev/null && { echo systemd-networkd; return; }; systemctl is-active --quiet networking 2>/dev/null && { echo networking; return; }; echo none; }
time_service(){ for u in chronyd.service chrony.service systemd-timesyncd.service ntpd.service; do systemctl is-active --quiet "$u" 2>/dev/null && { echo "$u"; return; }; done; echo none; }
collect(){ local f="$1"; { echo "Collected: $(date -Is)"; ip -br addr; ip route; echo; resolvectl status 2>/dev/null || cat /etc/resolv.conf; echo; timedatectl status 2>/dev/null || true; chronyc tracking 2>/dev/null || true; ntpq -pn 2>/dev/null || true; [ -n "$INTERFACE" ] && { echo; ip -s link show "$INTERFACE"; }; } >"$f"; }
collect "$BEFORE"
confirm "Apply the selected DNS, DHCP and time repairs? Network sessions may be interrupted." || { log "Repair cancelled."; exit 10; }
NM=$(network_manager); TS=$(time_service)
if $RESTART_NETWORK; then case "$NM" in NetworkManager|systemd-networkd|networking) root "Restarting $NM" systemctl restart "$NM" || true;; *) FAILURES=$((FAILURES+1)); log "WARNING: network manager not detected.";; esac; fi
if $FLUSH_DNS; then command -v resolvectl >/dev/null 2>&1 && root "Flushing resolver caches" resolvectl flush-caches || true; systemctl is-active --quiet systemd-resolved 2>/dev/null && root "Restarting systemd-resolved" systemctl restart systemd-resolved || true; systemctl is-active --quiet dnsmasq 2>/dev/null && root "Restarting dnsmasq" systemctl restart dnsmasq || true; fi
if $RENEW_DHCP; then case "$NM" in NetworkManager) root "Reapplying NetworkManager configuration" nmcli device reapply "$INTERFACE" || true;; systemd-networkd) root "Renewing DHCP on $INTERFACE" networkctl renew "$INTERFACE" || true;; *) if command -v dhclient >/dev/null 2>&1; then root "Releasing DHCP on $INTERFACE" dhclient -r "$INTERFACE" || true; root "Renewing DHCP on $INTERFACE" dhclient "$INTERFACE" || true; else FAILURES=$((FAILURES+1)); log "WARNING: DHCP renewal tool not found."; fi;; esac; fi
if $RESTART_TIME; then [ "$TS" != none ] && root "Restarting $TS" systemctl restart "$TS" || { FAILURES=$((FAILURES+1)); log "WARNING: time service not detected."; }; fi
if $STEP_CLOCK; then if command -v chronyc >/dev/null 2>&1; then root "Requesting immediate chrony correction" chronyc makestep || true; else FAILURES=$((FAILURES+1)); log "WARNING: chronyc is required for --step-clock."; fi; fi
$DRY_RUN || sleep 3; collect "$AFTER"; [ "$FAILURES" -eq 0 ] || exit 20; log "Repair completed successfully. Actions performed: $ACTIONS"
