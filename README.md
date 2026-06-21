# Linux DNS, DHCP and Time Sync Diagnostics

A Linux support toolkit for diagnosing and repairing resolver, DHCP, network-manager and time-synchronisation problems.

## Diagnostic script

```bash
chmod +x src/dns_dhcp_time_diagnostics.sh
sudo ./src/dns_dhcp_time_diagnostics.sh --dns-name example.com --target 1.1.1.1
```

## Repair script

```bash
chmod +x src/dns_dhcp_time_repair.sh
sudo ./src/dns_dhcp_time_repair.sh --flush-dns --dry-run
```

Supported repairs:

```bash
sudo ./src/dns_dhcp_time_repair.sh --flush-dns
sudo ./src/dns_dhcp_time_repair.sh --interface eth0 --renew-dhcp
sudo ./src/dns_dhcp_time_repair.sh --restart-network
sudo ./src/dns_dhcp_time_repair.sh --restart-time
sudo ./src/dns_dhcp_time_repair.sh --step-clock
```

## What the repair does

- Flushes resolver caches and restarts supported resolver services.
- Restarts NetworkManager, systemd-networkd or the traditional networking service.
- Renews DHCP using the active manager or `dhclient`.
- Restarts chrony, systemd-timesyncd or ntpd.
- Requests an immediate chrony correction when explicitly selected.
- Captures network, resolver and clock state before and after repair.
- Supports dry-run, confirmation prompts, logs and clear exit codes.

## Safety

Network and time-service changes can interrupt active sessions or applications. The script does not write persistent DNS servers, routes, interfaces or timezone settings.

## Author

Dewald Pretorius — L2 IT Support Engineer
