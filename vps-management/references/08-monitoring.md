# 08 — Monitoring & Observability

You can't fix what you can't see, and you want to catch trends (disk filling, memory creeping,
inodes exhausting) *before* they cause an outage. This file covers metrics, logs-as-signals, health
checks, and alerting.

## Why

Monitoring is both an operational and a security control: resource graphs catch capacity problems
early, and anomalies (a CPU spike at 3 a.m., unexpected outbound traffic, a flood of auth failures)
are often the first sign of compromise. The goal is a small, reliable signal set with alerting that
reaches a human/agent, not a wall of dashboards nobody watches.

## How

### 1. Quick single-node option — Netdata
Fastest path to per-second metrics with almost no config; good for one box or a first look.
```bash
# Official kickstart (review the script first per AGENTS.md):
wget -qO /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
less /tmp/netdata-kickstart.sh && sh /tmp/netdata-kickstart.sh --stable-channel --disable-telemetry
# Dashboard on 127.0.0.1:19999 — keep it behind the firewall / reverse proxy + auth, don't expose it.
```

### 2. Fleet-standard stack — Prometheus + node_exporter + Grafana + Alertmanager (+ Loki for logs)
The 2026 open-source default. Run the **server** components (Prometheus, Grafana, Alertmanager, Loki)
on a **separate** small observability VPS (≈4 GB) so your graphs and alerts survive an outage of the
monitored fleet. Each monitored node runs only the lightweight exporters/shippers.

On each monitored node:
```bash
# node_exporter for system metrics (CPU/RAM/disk/inodes/network) on :9100
useradd -rs /bin/false node_exporter
# install the binary to /usr/local/bin, create a systemd unit, enable it
# Restrict :9100 to the Prometheus server's IP in the firewall (03) — don't expose metrics publicly.
```
On the observability server: scrape targets in `prometheus.yml`, visualize in Grafana (import
dashboard 1860 "Node Exporter Full"), and route alerts via Alertmanager. Grafana **Alloy** is the
current agent for shipping logs to **Loki** (it supersedes Promtail).

### 3. What to watch (the signal set)
- **Disk space and inodes** (`node_filesystem_avail_bytes`, `node_filesystem_files_free`) — full disk
  or inode exhaustion breaks everything; alert at 80% and 90%.
- **Memory / swap** — sustained swap use or approaching OOM.
- **CPU load** relative to core count; sustained saturation.
- **Service up/down** (blackbox probes / systemd unit state).
- **TLS cert expiry** (blackbox exporter) — catch renewals that failed.
- **Auth failures / fail2ban bans** trending up (security signal; see `10`).
- **HTTP error rate and latency** for web apps.

### 4. Health checks and external uptime
Internal monitoring can't tell you the box is unreachable — if it's down, so is its monitoring. Add an
**external** check (a hosted uptime service or a second host) hitting a `/health` endpoint or the TLS
port, alerting on failure. A `/health` route should verify the app *and* its dependencies (DB, cache)
return OK.

### 5. Alerting that actually reaches someone
Route Alertmanager (or Netdata/health-check alerts) to a channel a human/agent monitors — email,
Slack/Teams webhook, PagerDuty/Opsgenie for on-call. Tune thresholds to avoid alert fatigue: page on
symptoms that need action, notify (don't page) on trends.

## RHEL family differences
Packages/exporters are identical (Go binaries). Install exporters from upstream releases; SELinux may
require a context/port label for non-standard exporter ports (`semanage port -a -t
node_exporter_port_t -p tcp 9100` if a policy exists, else run under a permissive custom port).
Netdata provides RPM repos.

## Pitfalls
- **Exposing dashboards/metrics publicly** — Netdata (19999), Prometheus (9090), Grafana (3000),
  node_exporter (9100) must sit behind the firewall/reverse proxy with auth. Metrics endpoints leak
  useful recon.
- **Monitoring server co-located with what it monitors** — an outage takes the monitoring down too.
- **No external check** — you learn the site is down from customers.
- **Alert fatigue** — too many noisy alerts train everyone to ignore them, including the real one.
- **Ignoring inodes** — a disk with free bytes but zero free inodes still fails to write; monitor both.

## Verify
```bash
curl -s localhost:9100/metrics | head          # node_exporter responding
systemctl is-active node_exporter
# On the Prometheus server: Status > Targets should show every node UP.
# Fire a test alert and confirm it lands in the destination channel.
df -h && df -i                                  # sanity: disk AND inode headroom
```

## How managed services handle it
The panels bundle basic resource monitoring and alerting: RunCloud, Ploi, Forge, and GridPane show
CPU/RAM/disk graphs and send threshold alerts (e.g., disk > 80%) by email/Slack; several offer uptime
monitoring for the sites they manage. They favor a simple, opinionated signal set (the same one in
step 3) over a full Prometheus/Grafana build, on the theory that most operators need reliable
"something's wrong" alerts rather than deep observability. For anything beyond a couple of servers,
the self-hosted Prometheus/Grafana/Loki stack gives you history and flexibility the panels don't.
