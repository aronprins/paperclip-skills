# 06 — Automatic Updates & Patch Management

The gap between a vulnerability's disclosure and its patch is when attackers strike. Automate security
updates, define a reboot policy (a patched-but-not-rebooted kernel still runs the vulnerable code in
memory), and stage risky updates.

## Why

Unattended security patching is a baseline control (CIS, NIST). Ubuntu enables automatic security
updates by default precisely because the risk of *not* patching outweighs the small risk of an
automatic update causing trouble. The nuance is scope (security-only vs everything), reboots, and
protecting stateful services from surprise restarts.

## How (Ubuntu/Debian primary)

### 1. unattended-upgrades (installed by default on Ubuntu)
```bash
apt -y install unattended-upgrades apt-listchanges update-notifier-common
dpkg-reconfigure -plow unattended-upgrades          # creates /etc/apt/apt.conf.d/20auto-upgrades
```
`/etc/apt/apt.conf.d/20auto-upgrades` should contain:
```
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
```

### 2. Tune what gets upgraded — `/etc/apt/apt.conf.d/50unattended-upgrades`
Keep **security** origins on for all production. Adding `-updates` pulls stable-release updates
(occasional behavior changes); leave `-proposed` and `-backports` **off**.
```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
//  "${distro_id}:${distro_codename}-updates";   // enable only if you want non-security updates too
};
// Protect stateful services from auto-upgrade (restart risk):
Unattended-Upgrade::Package-Blacklist {
//  "mysql-server";
//  "mariadb-server";
//  "postgresql";
//  "docker-ce";
};
Unattended-Upgrade::Mail "admin@example.com";
Unattended-Upgrade::MailReport "on-change";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
```

### 3. Reboot policy
A kernel or glibc update requires a reboot to take effect. Decide explicitly:
```
Unattended-Upgrade::Automatic-Reboot "false";              // safest default for stateful/single hosts
// If this host is stateless or has an approved maintenance window, switch to:
// Unattended-Upgrade::Automatic-Reboot "true";
// Unattended-Upgrade::Automatic-Reboot-Time "02:00";
// Unattended-Upgrade::Automatic-Reboot-WithUsers "false"; // don't reboot with logged-in users
```
Auto-reboot needs `update-notifier-common` installed or it silently won't reboot. On uptime-critical
single hosts, prefer **live patching** (below) and manual reboots during maintenance windows over
auto-reboot.

### 4. Test and observe
```bash
unattended-upgrade --dry-run --debug        # see exactly what would be upgraded, no changes made
cat /var/log/unattended-upgrades/unattended-upgrades.log
systemctl status unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer
```

### 5. Kernel live patching (avoid reboots on critical hosts)
- **Canonical Livepatch** (Ubuntu, free tier via Ubuntu Pro for a few machines): patches the running
  kernel for high/critical CVEs without reboot. `pro attach <token>; pro enable livepatch;
  canonical-livepatch status`.
- **KernelCare** (commercial, distro-agnostic) is the equivalent for RHEL-family and others.
- Live patching defers but does not eliminate reboots — you still reboot periodically to move onto a
  fully updated on-disk kernel.

## RHEL family differences
```bash
dnf -y install dnf-automatic
# /etc/dnf/automatic.conf:  apply_updates = yes ; upgrade_type = security
systemctl enable --now dnf-automatic.timer
# Or the on-demand timer variants: dnf-automatic-install.timer
needs-restarting -r ; echo $?     # 1 = reboot needed (from dnf-utils)
```
`upgrade_type = security` mirrors Ubuntu's security-only default. Live patching via KernelCare or (on
RHEL) `kpatch`.

## Patch-testing / staged rollout strategy
- **Blacklist** databases and other stateful services from auto-upgrade; patch them manually in a
  window after a backup.
- **Stage**: apply to a canary/staging host that mirrors production, watch for regressions, then roll
  to the fleet (Ansible makes this repeatable — see `14`).
- **Snapshot before** major upgrades (distribution release upgrades especially) so you can roll back.
- Keep `/var` from filling with old kernels/packages: `Remove-Unused-Kernel-Packages` + periodic
  `apt autoremove --purge`.

## Pitfalls
- **Auto-reboot on a host running a database or long job** at 02:00 can interrupt work — blacklist the
  service and/or disable auto-reboot on stateful hosts.
- **Auto-reboot configured but `update-notifier-common` missing** → it never actually reboots, and you
  run patched-on-disk-but-vulnerable-in-memory kernels indefinitely.
- **Enabling `-updates`/`-proposed`** and getting behavior changes you didn't want on production.
- **`/boot` filling up** from accumulated kernels, causing the *next* update to fail. Prune old
  kernels.
- **No notifications** → silent failures. Set `Mail` + `MailReport "on-change"` and actually monitor
  it.

## Verify
```bash
grep -r Unattended-Upgrade /etc/apt/apt.conf.d/     # settings present
unattended-upgrade --dry-run | tail                 # would-upgrade list is sane
systemctl is-active apt-daily-upgrade.timer         # timer active
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required*   # pending reboot visible
```

## How managed services handle it
Automatic **security** updates are a near-universal panel default. SpinupWP, Forge, Ploi, RunCloud,
and GridPane all enable unattended security upgrades out of the box, and most surface an OS-update or
"needs reboot" indicator in their dashboards while deliberately **not** auto-rebooting production web
servers (they prompt the operator to reboot in a window instead) — precisely the stateful-host
caution above. GridPane and others integrate the update cadence with their backup system so a
snapshot exists before larger changes.
