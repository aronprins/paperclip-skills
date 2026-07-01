# 13 — Performance & Optimization

Make the server use its resources well before spending money on a bigger one. Kernel/network tuning,
resource limits, swap behavior, caching layers, and right-sizing. Measure first — tune the actual
bottleneck, not a guessed one.

## Why

Right-sizing (matching instance size to real load) is the cheapest optimization; tuning removes
artificial ceilings (default file-descriptor and connection limits are conservative and often
throttle busy servers well below hardware capacity). But premature or cargo-cult tuning can *hurt* —
always measure the bottleneck (CPU? memory? disk I/O? network? a single slow query?) before changing
kernel knobs.

## How

### 1. Measure first
```bash
# Where is the time going?
top -o %CPU ; htop
vmstat 1 5                 # r (run queue), si/so (swapping), wa (I/O wait)
iostat -xz 1 5             # per-disk %util, await — high = disk-bound (needs sysstat)
free -h ; cat /proc/pressure/{cpu,memory,io}   # PSI: modern "is this resource the bottleneck?" signal
ss -s                      # socket summary
# App-level: slow query logs (DB), request latency (web) usually matter more than kernel knobs.
```

### 2. File descriptors and connection limits (the usual real ceiling)
Busy web/DB servers exhaust default limits long before CPU/RAM.
```bash
# System-wide max open files:
echo 'fs.file-max = 2097152' >/etc/sysctl.d/70-perf.conf
# Per-service (systemd) — the right place for daemons:
mkdir -p /etc/systemd/system/nginx.service.d
printf '[Service]\nLimitNOFILE=65535\n' >/etc/systemd/system/nginx.service.d/limits.conf
systemctl daemon-reload && systemctl restart nginx
# Per-user (interactive/login) via /etc/security/limits.d/90-nofile.conf:
#   *  soft nofile 65535
#   *  hard nofile 65535
```

### 3. Network performance sysctls (for high-connection servers)
Apply thoughtfully; defaults are fine for low traffic.
```bash
cat >>/etc/sysctl.d/70-perf.conf <<'EOF'
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl --system
```
BBR congestion control + `fq` often improves throughput/latency on modern kernels; verify the module
is available (`sysctl net.ipv4.tcp_available_congestion_control`).

### 4. Swap behavior
Keep swap as a safety net but discourage routine use on servers: `vm.swappiness = 10` (set in `01`).
On memory-heavy DB hosts some tune to `1`. Never set `swappiness=0` on a box with no other OOM
mitigation — it can trigger the OOM killer under pressure.

### 5. Caching layers
- **Redis / Memcached** for app object/session cache and DB query offload. Bind to `127.0.0.1`,
  require auth (`requirepass` / ACLs for Redis), and set `maxmemory` + an eviction policy so the cache
  can't consume all RAM. Never expose these to the internet — unauthenticated Redis is a classic
  breach.
- **Web caching** (Nginx `fastcgi_cache`/`proxy_cache`, Varnish) for dynamic content that tolerates
  short TTLs.
- **OS page cache** already caches file reads — don't fight it; leave RAM for it rather than
  over-allocating app heaps.

### 6. Disk I/O
- Use the provider's SSD/NVMe tier for databases; watch `iostat` `%util`/`await`.
- Scheduler: `mq-deadline` or `none` (for NVMe) usually beats `bfq` on server workloads;
  `cat /sys/block/<dev>/queue/scheduler`.
- Mount with `noatime` (or `relatime`, the default) to cut write amplification from access-time
  updates.

### 7. CDN and offload
Put a CDN (Cloudflare, Fastly, CloudFront) in front for static assets and edge caching — it removes
load and latency and adds DDoS absorption (`03`). Offloading images/JS/CSS to the edge is often a
bigger win than any server-side tuning.

### 8. Right-size
After tuning and caching, use the monitoring history (`08`) to size the instance to real
p95/p99 load with headroom — scale up (bigger box) for CPU/RAM-bound single services, scale out
(more boxes + load balancer) for stateless web tiers.

## RHEL family differences
sysctl keys and systemd limit mechanics are identical. `tuned` is RHEL's built-in tuning-profile
daemon: `tuned-adm profile throughput-performance` (or `network-latency`) applies a curated set of
knobs — often preferable to hand-tuning on RHEL. Redis/Memcached via EPEL/modules.

## Pitfalls
- **Tuning before measuring** — changing kernel knobs that aren't the bottleneck wastes effort and can
  regress stability.
- **Exposed, unauthenticated Redis/Memcached** — remote code execution / data theft. Localhost + auth
  + firewall.
- **`swappiness=0` with no OOM plan** — surprise OOM kills.
- **Raising `LimitNOFILE` in the wrong place** — for a systemd service, `limits.conf` (PAM) doesn't
  apply; use a service drop-in.
- **BBR/`fq` assumed present** — verify kernel support before relying on it.
- **Over-allocating app memory** and starving the OS page cache, hurting overall throughput.

## Verify
```bash
sysctl fs.file-max net.core.somaxconn net.ipv4.tcp_congestion_control vm.swappiness
cat /proc/$(pgrep -o nginx)/limits | grep 'Max open files'    # service actually got the new limit
redis-cli CONFIG GET maxmemory ; redis-cli CONFIG GET requirepass    # cache bounded + authed
# Re-measure the original bottleneck and confirm it improved (vmstat/iostat/PSI, or app latency).
```

## How managed services handle it
The panels ship opinionated performance defaults rather than exposing every knob: sensible PHP-FPM
pool sizing per plan, OPcache enabled, Nginx FastCGI/page caching (RunCloud, SpinupWP, GridPane all
offer built-in full-page caching), and Redis/Memcached as one-click add-ons bound locally. SpinupWP
and GridPane are explicitly WordPress-tuned (object cache + page cache + sane FPM). The lesson for an
agent: enable the caching layer and set correct per-service file-descriptor limits first — those
deliver most of the real-world win — then tune kernel networking only for genuinely high-connection
workloads.
