# 03 — Firewall & Network Security

Default-deny inbound is the first line of network defense; egress filtering limits what a compromised
process can reach. Pick one front-end and stick with it: **ufw** (Ubuntu default), **firewalld**
(RHEL default), or raw **nftables** (both distros' modern backend). Do not run two conflicting
firewall managers at once.

> **Enabling a firewall on a remote host can lock you out.** Allow SSH *first*, then enable. Consider
> a time-delayed safety net (below). Follow `AGENTS.md` §4.

## Why

CIS and NIST both treat host-based, default-deny filtering as baseline. The rule of thumb: inbound is
denied except the handful of ports a role needs; established/related return traffic is allowed;
loopback is trusted; everything else is dropped (drop, not reject, to avoid confirming the host to
scanners). Egress filtering is the under-used other half — it blocks data exfiltration and
call-home from compromised software.

## How — ufw (Ubuntu/Debian primary)

Stage the rules first, then stop for the `AGENTS.md` §4 confirmation gate before enabling the
firewall on a remote host.

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH                 # do this BEFORE enabling; opens 22 (or your custom port)
ufw allow 80/tcp
ufw allow 443/tcp
ufw limit 22/tcp                  # rate-limit SSH: throttles repeated connections from one IP
ufw show added                    # pre-enable review: SSH must be present
```

Before you run `ufw enable`, confirm all of this out loud: current SSH session stays open, SSH allow
rule is visible, provider console/recovery is available or a timed recovery job is armed, and the
human has approved enabling the firewall on this host. Then enable, immediately open a second SSH
session, and only then trust the rule set.

```bash
# Optional timed recovery net; cancel with atrm after second-session SSH succeeds.
echo 'ufw allow OpenSSH' | at now + 15 minutes
ufw enable
ufw status verbose
```
Add services as needed (`ufw allow 5432/tcp` only if the DB must be remote — usually it shouldn't be;
bind it to localhost instead, see `07`).

## How — firewalld (RHEL primary)

Add permanent rules first, then reload only after the same SSH/console confirmation gate.

```bash
firewall-cmd --set-default-zone=public
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --list-all
```
Confirm `ssh` is present in the permanent rules, keep the current session open, then reload and test
a second SSH session:

```bash
firewall-cmd --reload
firewall-cmd --list-all
```
Avoid `firewall-cmd --panic-on` during normal hardening; it blocks all network traffic, including
your own SSH session.
firewalld is zone-based: assign interfaces to zones and attach rules to zones. Rich rules add
source-based allow/deny and rate limits.

## How — raw nftables (either distro, maximum control)

nftables' `inet` family handles IPv4 and IPv6 together, so you filter both in one ruleset.

```bash
cat >/etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    ct state invalid drop
    iif "lo" accept
    ip protocol icmp accept
    ip6 nexthdr ipv6-icmp accept
    tcp dport 22 ct state new limit rate 10/minute accept   # SSH with rate limit
    tcp dport { 80, 443 } accept
  }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output  { type filter hook output priority 0; policy accept; }
}
EOF
nft -c -f /etc/nftables.conf     # CHECK the ruleset (dry run) before applying
nft list ruleset
```
Only after `nft -c` passes and the SSH accept rule is visibly present should you enable/reload
nftables on a remote host. Keep the current SSH session open and prove a second login immediately
after applying:

```bash
systemctl enable --now nftables
nft list ruleset
```

## Egress filtering (higher-security hosts)
Default-accept output is normal; for sensitive hosts, restrict it. Set the `output` chain policy to
`drop` and allow only what the server legitimately needs outbound — DNS (53), HTTPS (443) for
updates, NTP (123), and mail (587/465) if it sends mail. Test carefully: over-tight egress breaks
package updates and ACME renewals.

## IPv6
If the host has a public IPv6 address, it is reachable over IPv6 regardless of your IPv4 rules.
**Filter both.** ufw and firewalld handle v6 automatically when `IPV6=yes` (ufw) / by default
(firewalld); nftables' `inet` family covers both. Never lock down v4 and leave v6 wide open — a
common and dangerous oversight.

## DDoS basics and CrowdSec
Host firewalls can't absorb a volumetric DDoS (that needs upstream/provider scrubbing or a CDN like
Cloudflare in front), but they mitigate application-layer floods and scanning:
- SYN flood: `net.ipv4.tcp_syncookies=1` (already in the baseline), plus connection rate limits above.
- **CrowdSec** is a behavioral IPS: an agent detects patterns from logs, and "bouncers" enforce
  blocks (firewall, nginx, Cloudflare). It uses nftables sets to hold very large blocklists
  efficiently and pulls community-sourced malicious-IP lists. For a busy public server it scales far
  better than per-log fail2ban jails. See `10-intrusion-detection.md`.

## Cloud provider security groups
Provider-level firewalls (AWS security groups, DO Cloud Firewalls, Hetzner firewalls) are a
complementary **outer** layer that filters before traffic reaches the host. Use them *and* the host
firewall (defense in depth), but keep the rules consistent — conflicting cloud-SG and host-ufw rules
cause confusing "it's allowed but not reachable" failures. If the provider SG already restricts SSH
to your IP, that's a strong extra safeguard against lockout during host-firewall changes.

## Pitfalls
- **`ufw enable` / nft apply without an SSH allow rule** on a remote box = immediate lockout. Allow
  SSH first; verify with `ufw status` before enabling.
- **IPv6 left open** while IPv4 is locked down.
- **Two firewall managers fighting** (e.g., ufw + firewalld + Docker's own iptables rules). Docker in
  particular inserts rules that can bypass ufw — bind containers to `127.0.0.1` or use
  `ufw-docker`/explicit rules; see `07`.
- **`reject` instead of `drop`** on the default policy tells scanners the host is alive.

## Verify
```bash
ufw status verbose            # or: firewall-cmd --list-all   /   nft list ruleset
ss -tulnp | grep LISTEN       # cross-check: which ports are actually listening?
# From outside the host:
nmap -Pn -p22,80,443,3306,5432 host    # only intended ports should be open; DBs should be filtered/closed
```
**Verify checklist** — confirm "default-deny in effect + only intended ports open" against whichever
front-end is active:

- [ ] **ufw:** `ufw status verbose` shows `Status: active` and `Default: deny (incoming)`, and an SSH
  allow rule (`22/tcp` or `OpenSSH`) is present. No default-deny ⇒ tighten with `ufw default deny
  incoming`.
- [ ] **firewalld:** `firewall-cmd --state` is `running`; `firewall-cmd --list-all` shows the intended
  zone and `ssh` in its services list.
- [ ] **nftables:** `nft list ruleset` shows the `input` chain with `policy drop` and an explicit
  `dport 22`/`ssh` accept.
- [ ] **No active host firewall found** (ufw inactive, firewalld stopped, no nft input policy)? The
  host is relying on provider security groups only. Consider enabling one — but **allow SSH first**,
  then enable (`AGENTS.md` §4).
- [ ] **Cross-check the listeners:** every `0.0.0.0`/`[::]` entry in `ss -tulnp` should be a port you
  *intend* to expose. Databases/caches (3306/5432/6379/11211) should listen on `127.0.0.1` only, not
  `0.0.0.0` — bind them to localhost rather than opening a firewall port (`07`).

## How managed services handle it
Forge configures a firewall that allows 22/80/443 by default and explicitly warns against removing
the SSH rule — the exact default-deny-plus-three posture above. Ploi and RunCloud expose a managed
firewall UI over the same underlying host firewall. Cloudways' newer "Flexible" servers moved their
built-in protection toward Imunify360 (from an earlier Shorewall-based setup), illustrating that the
front-end tooling changes over time while the principle — default-deny, open only what's needed —
does not.
