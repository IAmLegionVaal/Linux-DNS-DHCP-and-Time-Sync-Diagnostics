#!/usr/bin/env bash
set -u
DNS_NAME="example.com"
TARGET="1.1.1.1"
HOURS=24
OUTPUT_DIR=""
usage(){ echo "Usage: dns_dhcp_time_diagnostics.sh [--dns-name NAME] [--target HOST] [--hours N] [--output DIR]"; }
while [[ $# -gt 0 ]]; do case "$1" in --dns-name) DNS_NAME="${2:-example.com}"; shift 2;; --target) TARGET="${2:-1.1.1.1}"; shift 2;; --hours) HOURS="${2:-24}"; shift 2;; --output) OUTPUT_DIR="${2:-}"; shift 2;; -h|--help) usage; exit 0;; *) echo "Unknown argument: $1" >&2; exit 2;; esac; done
[[ "$HOURS" =~ ^[0-9]+$ ]] || { echo "--hours must be numeric" >&2; exit 2; }
STAMP=$(date +%Y%m%d_%H%M%S); OUTPUT_DIR="${OUTPUT_DIR:-./dns-dhcp-time-$STAMP}"; mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/diagnostics.txt"; CSV="$OUTPUT_DIR/interfaces.csv"; JSON="$OUTPUT_DIR/summary.json"; ERRORS="$OUTPUT_DIR/command-errors.log"; :>"$REPORT"; :>"$ERRORS"
echo 'interface,state,ipv4,ipv6' > "$CSV"
section(){ t="$1"; shift; { printf '\n===== %s =====\n' "$t"; "$@"; } >>"$REPORT" 2>>"$ERRORS" || true; }
section "Metadata" bash -c 'date -Is; hostname -f 2>/dev/null || hostname; cat /etc/os-release 2>/dev/null || true; timedatectl 2>/dev/null || true'
section "Interfaces" ip -brief address
section "Routes" ip route show table all
section "Neighbours" ip neigh show
section "Resolver configuration" bash -c 'cat /etc/resolv.conf; resolvectl status 2>/dev/null || systemd-resolve --status 2>/dev/null || true'
section "NetworkManager" bash -c 'nmcli general status 2>/dev/null || true; nmcli device show 2>/dev/null || true'
section "DHCP leases" bash -c 'find /var/lib/NetworkManager /var/lib/dhcp /run/systemd/netif/leases -type f -maxdepth 2 -print -exec sed -n "1,160p" {} \; 2>/dev/null || true'
section "DNS lookup" bash -c "getent ahosts '$DNS_NAME'; dig '$DNS_NAME' 2>/dev/null || host '$DNS_NAME' 2>/dev/null || true"
section "Connectivity" ping -c 4 "$TARGET"
section "Time status" timedatectl status
section "Chrony" bash -c 'chronyc tracking 2>/dev/null || true; chronyc sources -v 2>/dev/null || true'
section "NTP" bash -c 'ntpq -pn 2>/dev/null || true'
section "Time services" bash -c 'systemctl status chronyd chrony ntpd systemd-timesyncd --no-pager -l 2>/dev/null || true'
section "Recent events" bash -c "journalctl --since '$HOURS hours ago' --no-pager 2>/dev/null | grep -Ei 'dhcp|dns|resolved|chrony|ntp|timesync|clock.*jump|no route|link is down' | tail -n 2000 || true"
while read -r iface state; do ipv4=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | paste -sd';' -); ipv6=$(ip -6 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | paste -sd';' -); printf '"%s","%s","%s","%s"\n' "$iface" "$state" "$ipv4" "$ipv6" >> "$CSV"; done < <(ip -brief link | awk '{print $1,$2}')
DNS_OK=false; getent hosts "$DNS_NAME" >/dev/null 2>&1 && DNS_OK=true
PING_OK=false; ping -c 1 -W 3 "$TARGET" >/dev/null 2>&1 && PING_OK=true
TIME_SYNC=false; timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -qi true && TIME_SYNC=true
OVERALL="Healthy"; { ! $DNS_OK || ! $PING_OK || ! $TIME_SYNC; } && OVERALL="Attention required"
cat > "$JSON" <<EOF
{"collected_at":"$(date -Is)","hostname":"$(hostname -f 2>/dev/null || hostname)","dns_name":"$DNS_NAME","target":"$TARGET","dns_ok":$DNS_OK,"ping_ok":$PING_OK,"time_synchronized":$TIME_SYNC,"overall_status":"$OVERALL"}
EOF
printf '\nDiagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
