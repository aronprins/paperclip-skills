# 12 — Log Management & Auditing

Logs are how you reconstruct what happened — for troubleshooting, for security forensics (`11`), and
for compliance. This file covers persistent journald, rotation, remote/central logging, and auditd
rule sets. The recurring principle: **an attacker with root can erase local logs, so security-relevant
logs must also leave the box.**

## Why

CIS requires configured logging, log rotation, and (for higher levels) remote log storage; compliance
regimes (PCI-DSS, HIPAA, SOC 2) mandate retention and integrity of audit logs. auditd provides the
kernel-level "who did what" trail that ordinary syslog can't, and its `auid` (audit user ID) survives
`sudo`/`su`, so you can attribute root actions to the human who escalated.

## How

### 1. Make journald persistent
By default some systems keep journals only in memory (lost on reboot). Persist them:
```bash
mkdir -p /var/log/journal
# /etc/systemd/journald.conf
cat >/etc/systemd/journald.conf.d/persistent.conf <<'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=1G
SystemKeepFree=1G
MaxRetentionSec=1month
ForwardToSyslog=no
EOF
systemctl restart systemd-journald
journalctl --disk-usage
```

### 2. Rotation for file-based logs (logrotate)
Nginx, app, and other file logs need rotation so they don't fill the disk.
```bash
cat >/etc/logrotate.d/app <<'EOF'
/var/log/app/*.log {
  daily
  rotate 30
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
}
EOF
logrotate --debug /etc/logrotate.conf     # dry-run: confirm rules parse and would rotate
```

### 3. Central / remote logging (ship logs off-box)
Two common paths:
- **rsyslog forwarding** to a central syslog/SIEM (TCP+TLS preferred over plain UDP):
  ```bash
  # /etc/rsyslog.d/60-remote.conf  ->  *.* @@logserver.example.com:6514   (@@ = TCP)
  systemctl restart rsyslog
  ```
- **Loki + Grafana Alloy** (modern, pairs with the monitoring stack in `08`): Alloy tails
  journald/files and ships to Loki; query in Grafana. Alloy supersedes Promtail.

Ship at minimum: auth/sudo, auditd, sshd, firewall drops, and web access/error logs. Off-box copies
mean a root-level attacker who wipes local logs can't erase the record.

### 4. auditd rules (the "who did what" trail)
Baseline rules were introduced in `05`; a fuller CIS/STIG-aligned set lives in `/etc/audit/rules.d/`
as numbered files (10-→90-), ending with `-e 2` to make the rule set immutable until reboot.
```bash
# Key categories to cover (add to /etc/audit/rules.d/70-cis.rules):
#  - identity files: /etc/passwd /etc/group /etc/shadow /etc/gshadow  (-p wa)
#  - sudoers + scope: /etc/sudoers, /etc/sudoers.d  (-p wa)
#  - login records: /var/log/lastlog, /var/run/faillock  (-p wa)
#  - time changes: adjtimex, settimeofday, clock_settime
#  - network config: /etc/hosts, /etc/network, sethostname/setdomainname
#  - MAC policy: /etc/apparmor.d or /etc/selinux
#  - privileged command execution (setuid/setgid binaries)
#  - kernel module load/unload: init_module, delete_module, /sbin/insmod, /sbin/modprobe
#  - unauthorized file-access attempts (EACCES/EPERM on open/openat)
augenrules --load
auditctl -s        # 'enabled 2' = immutable; reboot required to change rules
```
Curated, harmonized CIS+STIG rule sets (with living-off-the-land detection) exist as open-source
starting points — adapt one rather than writing every rule by hand. Review with `aureport` /
`ausearch` (e.g. `aureport -au` for auth, `ausearch -k scope` for sudoers changes).

### 5. Retention
Match retention to policy: many compliance regimes expect **1 year** of audit logs (with ~90 days
readily accessible). Enforce via journald `MaxRetentionSec`, logrotate `rotate` counts, and — for the
authoritative copy — retention on the central log store, which is harder for an attacker to tamper
with than local files.

## RHEL family differences
auditd ships enabled and is the primary audit source; `/var/log/secure` holds auth events;
`/var/log/audit/audit.log` holds the audit trail. `authselect`/SELinux integrate with auditing.
rsyslog is present by default. Rule-file mechanics (`/etc/audit/rules.d/`, `augenrules`) are identical.

## Pitfalls
- **Journald non-persistent** → logs vanish on reboot, right when you need post-incident history.
- **Only local logs** → root-level attacker wipes them; no off-box copy = no forensics (`11`).
- **auditd rules not immutable (`-e 2` missing)** → an attacker disables auditing on the fly.
- **Logs filling the disk** (no rotation / no `SystemMaxUse`) → cascading outage.
- **Plain-UDP remote logging** → logs lost on congestion and readable in transit; use TCP+TLS.
- **auditd so verbose it drowns signal / hurts performance** → scope rules to security-relevant events.

## Verify
```bash
journalctl --disk-usage; ls /var/log/journal    # persistence in effect
auditctl -s | grep -E 'enabled|backlog'         # enabled (2 = immutable)
auditctl -l | wc -l                             # rules loaded
logrotate --debug /etc/logrotate.conf | tail    # rotation rules valid
# Confirm remote delivery: generate an event and see it arrive on the log server/Loki.
logger -p auth.warning "vps-skill log pipeline test"
```

## How managed services handle it
The panels expose per-site access/error logs and system logs in their dashboards and rotate them
automatically, but deep audit logging and off-box/SIEM shipping are generally left to the operator —
they're compliance concerns beyond the panels' remit. For regulated workloads, the agent should layer
auditd + centralized logging on top of whatever the panel provides, since the panel's local, rotating
logs alone won't satisfy retention-and-integrity requirements or survive a root-level attacker.
