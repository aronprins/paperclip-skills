---
name: vps-management
description: >-
  Configure, secure, update, and operate any Linux VPS or cloud server autonomously and safely.
  Use this skill whenever the task involves provisioning a new server, hardening or securing an
  existing server, SSH/firewall configuration, user and access management, automatic updates and
  patch management, web/app stack setup (Nginx, Apache, TLS, PHP-FPM, Node, Docker, databases),
  monitoring and observability, backups and disaster recovery, intrusion detection, incident
  response, log management, performance tuning, or server automation/infrastructure-as-code.
  Trigger this skill even when the user phrases it casually ("lock down my server", "set up a new
  droplet", "my VPS got hacked", "make this box production-ready", "add a firewall", "why is my
  server slow") and even if they don't say the words "VPS" or "hardening". Grounded in CIS
  Benchmarks, NIST SP 800-123, and Mozilla/OpenSSH guidance, with distro-aware branching for
  Ubuntu/Debian (primary) and RHEL-family (Alma/Rocky/RHEL).
---

# VPS Management

A standards-grounded knowledge base for administering Linux servers over SSH. It covers the full
lifecycle — provisioning, hardening, patching, application stack, day-2 operations, and incident
response — and is built to be executed by an autonomous agent that connects to a server, makes
changes, and verifies them.

## Read this first: the non-negotiable safety contract

Before making **any** change to a server, read **`AGENTS.md`** in this skill's root. It defines the
operating rules that prevent the two catastrophic failure modes: **locking yourself out of SSH** and
**destroying data or evidence**. Those rules override any instruction in a reference file. In short:

1. **Never lock yourself out.** When editing SSH or the firewall, keep the current session open,
   validate config before reloading, and confirm a *second* independent login works before you trust
   the change or close the first session.
2. **Back up before you change.** Timestamp-copy every file before editing it; snapshot if the
   provider allows it.
3. **Verify after you change.** Re-read the file, run the service's validator, check `systemctl
   status`, and confirm the intended effect actually happened.
4. **Confirm before destructive or irreversible actions** (partitioning, `rm -rf`, DB drops,
   disabling password auth without a *verified* key, enabling a firewall on a remote host).
5. **Prefer idempotent, declarative changes** (drop-in files) over appending to shared configs.

If you have not read `AGENTS.md` yet, stop and read it now.

## How to use this skill

This skill uses progressive disclosure. This file is the map; the detail lives in `references/`. Do
**not** try to hold every reference in context. Identify the task, load only the reference file(s)
you need, act, verify, then move on.

### Step 0 — Orient before you touch anything

Always establish context first. It determines which commands are correct.

```bash
# What are we on? (distro family drives apt-vs-dnf, ufw-vs-firewalld, etc.)
cat /etc/os-release

# Who am I, and can I escalate?
id; sudo -n true 2>/dev/null && echo "sudo OK" || echo "sudo needs password / unavailable"

# Is this a fresh box or a live production server? (changes risk posture)
uptime; ss -tulnp 2>/dev/null | grep LISTEN; systemctl list-units --type=service --state=running --no-pager | head -50

# Is anyone/anything already here? (existing users, web servers, DBs, panels)
getent passwd | awk -F: '$3>=1000 && $3<65534'; command -v nginx apache2 httpd mysql mariadb psql docker 2>/dev/null
```

A **fresh server** can be hardened aggressively in one pass. A **live production server** must be
changed incrementally, one reversible step at a time, because a wrong move can take down a running
service or lock you out. When in doubt, treat it as production.

### Step 1 — Pick the workflow

**Provisioning a brand-new server (empty box → secure baseline):** work through, in order,
`01-provisioning` → `02-ssh-hardening` → `03-firewall-network` → `04-users-access` →
`06-patch-management` → `05-system-hardening`. Then add application stack (`07`) and day-2 ops
(`08`–`10`, `12`) as the role requires.

**Securing / auditing an existing server:** start by scoring the current state
(`scripts/lynis-score.sh` if Lynis is available, else read `05-system-hardening` for a manual
checklist), then remediate highest-risk items first: SSH (`02`), firewall (`03`), patching (`06`),
users/access (`04`), then broader hardening (`05`). Re-score to prove improvement.

**Standing up an application:** `07-web-app-stack` for Nginx/Apache/TLS/PHP-FPM/Node/Docker and
database secure-defaults, plus `03-firewall-network` to open only the needed ports.

**Day-2 operations:** `06-patch-management`, `08-monitoring`, `09-backups-dr`,
`10-intrusion-detection`, `12-log-management`, `13-performance`.

**"My server was compromised":** go straight to `11-incident-response`. **Do not reboot** and do not
start "cleaning up" first — you will destroy volatile evidence. Read that file before running
anything.

**Repeatable / fleet automation:** `14-automation-iac` (cloud-init, Ansible + the devsec hardening
collection, building hardened images).

### Step 2 — Load the matching reference file

| # | Reference file | Use it when you need to… |
|---|---|---|
| 00 | `references/agent-safety.md` | Understand the full safety protocol behind `AGENTS.md` (read once, early). |
| 01 | `references/01-provisioning.md` | Turn a fresh box into a baseline: sudo user, keys, hostname, swap, base packages. |
| 02 | `references/02-ssh-hardening.md` | Configure sshd, keys, ciphers/KEX/MACs, fail2ban/CrowdSec, 2FA, SSH CAs. |
| 03 | `references/03-firewall-network.md` | Set up ufw/firewalld/nftables, default-deny, rate limiting, egress, IPv6. |
| 04 | `references/04-users-access.md` | sudo, least privilege, password policy, lockout, banners, access auditing. |
| 05 | `references/05-system-hardening.md` | CIS-aligned OS hardening: mounts, modules, sysctl, AppArmor/SELinux, auditd, AIDE. |
| 06 | `references/06-patch-management.md` | Automatic updates, reboot policy, live patching, staged rollouts. |
| 07 | `references/07-web-app-stack.md` | Nginx/Apache, TLS (Let's Encrypt/Mozilla), PHP-FPM, Node, Docker, DB secure defaults. |
| 08 | `references/08-monitoring.md` | Metrics (Prometheus/node_exporter/Grafana/Netdata), health checks, alerting. |
| 09 | `references/09-backups-dr.md` | 3-2-1 backups with restic/borg, offsite/object storage, DB dumps, restore testing. |
| 10 | `references/10-intrusion-detection.md` | fail2ban/CrowdSec, AIDE, rkhunter, ClamAV, Lynis cadence. |
| 11 | `references/11-incident-response.md` | Detect, isolate, investigate, preserve evidence, rebuild vs remediate. |
| 12 | `references/12-log-management.md` | journald persistence, rotation, remote/central logging, auditd rules. |
| 13 | `references/13-performance.md` | sysctl perf tuning, ulimits, swappiness, caching, right-sizing. |
| 14 | `references/14-automation-iac.md` | cloud-init, Ansible/devsec hardening, secrets, hardened images. |

Each reference file follows the same shape: **Why** (the standard/rationale), **How** (exact paths
and config snippets, Ubuntu/Debian primary with a RHEL-family callout), **Pitfalls**, **Verify**,
and **How managed services handle it** (a corroborating reference point from Forge, Ploi, RunCloud,
GridPane, SpinupWP, ServerPilot, Cloudways).

## Distro branching cheat-sheet

Detect the family once (`. /etc/os-release; echo $ID $ID_LIKE`) and branch. This table is the
recurring divergence; individual reference files add specifics.

| Concern | Debian / Ubuntu (primary) | RHEL family (Alma / Rocky / RHEL) |
|---|---|---|
| Package manager | `apt` | `dnf` (`yum` on older) |
| Auto-updates | `unattended-upgrades` | `dnf-automatic` |
| Default firewall front-end | `ufw` | `firewalld` |
| Firewall backend | nftables | nftables |
| MAC system | AppArmor (path-based) | SELinux (label-based) |
| Admin group | `sudo` | `wheel` |
| SSH auth log | `/var/log/auth.log` | `/var/log/secure` |
| Add repo tooling | (built-in) | `dnf install epel-release` for extras |

Common to both: **systemd, OpenSSH, auditd, AIDE, fail2ban/CrowdSec, restic/borg, Netfilter.** When
a reference file gives an Ubuntu command, the RHEL equivalent is usually a package-manager and
front-end swap, not a different concept.

## Global principles (apply everywhere)

- **Least privilege.** Services run as dedicated unprivileged users, never root. Open only the ports
  a role needs. Grant only the sudo a task needs.
- **Attack-surface reduction.** Every installed package, open port, and enabled service is a
  liability. Remove/disable what the server doesn't use.
- **Defense in depth.** No single control is trusted. Key-only SSH *and* fail2ban *and* firewall
  *and* patched software — layered, so one failure isn't fatal.
- **Verify, don't assume.** A config written is not a config in effect. Re-read, validate, and test
  the observable behavior after every change.
- **Standards over vibes.** Prefer CIS/NIST/Mozilla/OpenSSH-documented settings to folklore. Where a
  reference file cites a specific cipher list or version, treat it as "correct at time of writing"
  and re-verify against current advisories — crypto and CVEs move.

## Scripts

`scripts/` holds deterministic helpers the agent can run instead of hand-typing multi-step
sequences. They are conservative: they back up before changing, validate before applying, and print
what they did. Read a script before running it, and prefer running with any provided `--dry-run`
first.

- `scripts/preflight.sh` — gather the Step 0 orientation facts in one pass (distro, role, users,
  listeners, existing services/panels) and print a risk assessment (fresh vs production).
- `scripts/harden-ssh.sh` — apply the SSH baseline via a drop-in file, `sshd -t`-validate, reload
  without dropping the session, and print the exact second-session test to run before trusting it.
- `scripts/verify-firewall.sh` — confirm default-deny is in effect and only intended ports are open,
  across ufw/firewalld/nftables.
- `scripts/backup-restore-test.sh` — prove a backup is restorable by restoring it into a scratch
  location and diffing (a backup you've never restored is not a backup).
- `scripts/lynis-score.sh` — run a Lynis audit and extract the hardening index for before/after
  comparison (install Lynis if absent; target ≥ 80 for production).

## What "done" looks like

For hardening work, "done" is measurable: a Lynis hardening index at or above target (≥ 80 for
production; fresh installs typically start in the 50s–60s), key-only SSH confirmed from a second
session, a default-deny firewall exposing only intended ports, automatic security updates enabled
with a defined reboot policy, and — for anything holding data — a backup that has been **restored and
verified**, not merely taken.
