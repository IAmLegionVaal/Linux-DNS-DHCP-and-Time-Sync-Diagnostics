# Linux DNS, DHCP and Time Sync Diagnostics

A read-only Bash toolkit for diagnosing resolver configuration, DHCP leases, routes, DNS queries, chrony, NTP, systemd-timesyncd, and clock synchronisation.

## Usage

```bash
chmod +x src/dns_dhcp_time_diagnostics.sh
sudo ./src/dns_dhcp_time_diagnostics.sh --dns-name example.com --target 1.1.1.1
```

## Checks performed

- Interfaces, addresses, routes, neighbours, and resolver configuration
- DHCP lease files and NetworkManager/systemd-networkd state
- DNS resolution and server reachability
- chrony, ntpd, and systemd-timesyncd status
- Clock, timezone, NTP synchronisation, and offset indicators
- Text, CSV, and JSON reports

## Safety

The script never renews leases, changes DNS, adjusts time, restarts services, or modifies networking.

## Author

Dewald Pretorius — L2 IT Support Engineer
