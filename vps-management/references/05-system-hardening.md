# 05 — System Hardening (CIS-aligned)

Attack-surface reduction at the OS level: mount options, disabled kernel modules, network sysctls,
mandatory access control, auditing, and file-integrity monitoring. This is the broad "make the box
resistant" pass, mapped to CIS Benchmark controls.

## Why

CIS Benchmarks are the backbone standard. CIS defines the profiles precisely: **Level 1** is a base
recommendation implementable promptly without extensive performance impact; **Level 2** is
defense-in-depth for environments where security is paramount and *can* adversely affect operations
if applied without care; the **STIG profile** now replaces the former Level 3. Target **Level 1 for
general production**, and escalate specific controls toward Level 2 / STIG for regulated workloads.
Quantitatively: fresh installs commonly score in the 50s–60s on Lynis; CIS Level 1-equivalent
hardening lifts that into the 70s–80s. Treat ≥ 80 as the production goal.

> On a **live production** server, apply these incrementally and verify between changes — some (noexec
> mounts, module blacklists, strict sysctls) can break running software. Never run a full hardening
> script blindly on an established host.

## How (Ubuntu/Debian primary)

### 1. Filesystem: separate partitions + safe mount options
Ideally set at install time. Separate `/tmp`, `/var`, `/var/log`, `/var/log/audit`, `/home`; mount
with restrictive options where the content allows.
```bash
# If /tmp is its own mount (or use a tmpfs entry in /etc/fstab):
# tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0
mount -o remount,nosuid,nodev,noexec /tmp 2>/dev/null || true
# /dev/shm hardening:
grep -q '/dev/shm' /etc/fstab || echo 'tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0' >> /etc/fstab
```
`nodev` (no device files), `nosuid` (ignore setuid bits), `noexec` (no execution) — apply to data-only
mounts. **`noexec` on `/tmp` breaks some package installers and app builds**; verify nothing you run
needs to execute from `/tmp` first.

### 2. Disable unused filesystems and kernel modules
```bash
cat >/etc/modprobe.d/cis-blacklist.conf <<'EOF'
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true
install usb-storage /bin/true      # blocks USB mass storage; skip if you need USB disks
EOF
```

### 3. Network sysctl hardening
Extends the provisioning baseline. In `/etc/sysctl.d/60-hardening.conf`:
```bash
cat >/etc/sysctl.d/60-hardening.conf <<'EOF'
# Routing / redirects / source routing
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
# Spoofing / flooding
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1
# Process hardening
kernel.randomize_va_space = 2
kernel.yama.ptrace_scope = 1
fs.suid_dumpable = 0
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
EOF
sysctl --system
```
Set `net.ipv4.ip_forward = 1` **only** on hosts that route (Docker, VPN, NAT gateways) — Docker sets
it itself.

### 4. Mandatory Access Control — keep it enforcing
```bash
aa-status                      # AppArmor is Ubuntu's default; confirm profiles are in enforce mode
apt -y install apparmor-utils
# Put a complaining profile into enforce: aa-enforce /etc/apparmor.d/<profile>
```
Do **not** disable AppArmor (Ubuntu) or SELinux (RHEL) as a troubleshooting shortcut — fix the
profile/context instead.

### 5. Restrict core dumps, disable unneeded services, remove packages
```bash
echo '* hard core 0' >> /etc/security/limits.d/99-coredump.conf   # complements fs.suid_dumpable=0
systemctl list-unit-files --type=service --state=enabled          # audit; disable what the role doesn't need
apt -y purge telnet rsh-client rsh-redone-client talk 2>/dev/null || true   # remove legacy cleartext tools
apt -y autoremove --purge
```

### 6. auditd — record security-relevant events
```bash
apt -y install auditd audispd-plugins
cat >/etc/audit/rules.d/50-hardening.rules <<'EOF'
-D
-b 8192
--backlog_wait_time 60000
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d -p wa -k scope
-w /var/log/lastlog -p wa -k logins
-w /etc/ssh/sshd_config -p wa -k sshd
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k rootcmd
-w /sbin/insmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-e 2
EOF
augenrules --load
auditctl -s                    # enabled 2 = rules immutable until reboot
```
More detail and CIS/STIG rule sets in `12-log-management.md`.

### 7. AIDE — file integrity monitoring
Initialize on a **known-clean** system (a compromised baseline is worthless), store the DB
off-server or make it immutable, and check on a schedule.
```bash
apt -y install aide aide-common
aideinit                       # builds the baseline; can take a while
cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
chattr +i /var/lib/aide/aide.db    # or copy the DB off-box; prevents tampering
# Daily check via cron/systemd timer:
echo '0 5 * * * root /usr/bin/aide.wrapper --check | mail -s "AIDE report $(hostname)" root' \
  > /etc/cron.d/aide-check
```
An AIDE database no one reviews is theater — route reports somewhere a human/agent actually reads.

## RHEL family differences
- **SELinux** instead of AppArmor: keep `getenforce` = `Enforcing`; fix contexts with `semanage`
  /`restorecon`, never `setenforce 0` as a fix. Booleans via `setsebool -P`.
- Modules blacklist path and sysctl keys are identical.
- auditd ships enabled; rules in `/etc/audit/rules.d/`. `dnf` for package removal.
- CIS content is delivered via **OpenSCAP** (`oscap`) with SCAP Security Guide (`scap-security-guide`);
  Ubuntu's equivalent is Canonical's **USG** tool (gated behind Ubuntu Pro).

## Pitfalls
- **`noexec` on `/tmp` or `/var`** breaking installers, builds, or apps that execute from there.
- **Blacklisting `usb-storage`** on a box where you later need a USB disk (console recovery pain).
- **Aggressive sysctl on a routing host** (`ip_forward=0` kills Docker networking / VPN forwarding).
- **Initializing AIDE after compromise**, baking the attacker's changes into "known good."
- **Disabling SELinux/AppArmor** to make an app work — you've removed a whole defensive layer.
- **Running a one-shot hardening script on production** without staging — several sources warn this
  breaks running services; stage, back up, verify.

## Verify
```bash
sysctl net.ipv4.tcp_syncookies kernel.randomize_va_space fs.suid_dumpable
findmnt /tmp /dev/shm -o TARGET,OPTIONS
aa-status || getenforce
auditctl -s && auditctl -l | head
aide --check | tail             # after baseline
# Objective score before/after (see the Lynis before/after checklist below):
lynis audit system --quick && grep -i 'hardening index' /var/log/lynis.log
```

## Lynis before/after checklist

Where the job is "secure this server," measure it — capture a score *before* you remediate and again
*after*, and report the delta. This is a read-only audit; it makes no changes.

- [ ] **Install Lynis if absent** (distro-aware): Debian/Ubuntu `apt-get install -y lynis`; RHEL family
  `dnf install -y epel-release && dnf install -y lynis`. Root gives the most complete result — without
  it, some tests are skipped and the score is understated.
- [ ] **Run the audit:** `lynis audit system --quick` (the `--quick` flag skips interactive pauses;
  still read-only).
- [ ] **Read the hardening index:** from `/var/log/lynis-report.dat`, `awk -F= '/hardening_index=/{print
  $2}' | tail -1` (or `grep -i 'hardening index' /var/log/lynis.log`). Interpret it: **≥ 80** =
  production target met; **65–79** = partially hardened, keep pushing (apply `02`/`03`/`05`/`06`);
  **< 65** = near a fresh-install baseline.
- [ ] **Label before vs after.** Record the score with a label (e.g. append `"$(date -u +%FT%TZ)
  before <n>"` to a notes file) so the before/after comparison is unambiguous after remediation.
- [ ] **Work the top suggestions:** the `suggestion[]=` lines in `/var/log/lynis-report.dat` are your
  highest-impact next actions — address those, then re-run and confirm the index rose.
- [ ] **Read the score as relative, not absolute** (`AGENTS.md` §8): it measures configuration
  conformance, not real-world security, and a minimal server scores higher partly by running less.

## How managed services handle it
The panels apply a pragmatic subset of this — automatic security updates, MAC left enforcing, sane
sysctls, per-app isolation — rather than full CIS Level 2, because aggressive hardening can break
customer web apps. Canonical productizes the full benchmark: the **Ubuntu Security Guide (USG)** audits
and remediates against CIS and DISA-STIG profiles and ships OpenSCAP content, but the one-command
automated remediation is gated behind **Ubuntu Pro / CIS SecureSuite**. The free path is Lynis plus
manual CIS mapping — which is exactly what this file encodes.
