# 10 — Intrusion Detection & Security Monitoring

Layered detection so that if prevention fails, you find out. Network-level blocking (fail2ban /
CrowdSec), file-integrity monitoring (AIDE), rootkit/malware scanning, and a regular audit cadence
(Lynis). File-integrity monitoring is frequently the *first* indicator of an otherwise-hidden
compromise.

## Why

No prevention is perfect (defense in depth), so you need detection. CIS and NIST both call for file
integrity monitoring, log review, and periodic security auditing. The layers catch different things:
brute-force blockers stop the noisy attacks, FIM catches quiet post-exploitation changes to system
files, rootkit/malware scanners catch known-bad artifacts, and Lynis measures configuration drift over
time.

## How

### 1. Brute-force / behavioral blocking
- **fail2ban** — log-driven jails that ban IPs after N failures. Covers SSH (configured in `02`) and
  can cover Nginx/Apache auth, WordPress login, mail, etc. Add jails in `/etc/fail2ban/jail.d/`.
- **CrowdSec** — behavioral IPS for busy/public hosts: an agent parses logs into "scenarios," bouncers
  enforce decisions (nftables, nginx, Cloudflare), and it pulls **community blocklists** of known-bad
  IPs. Scales to large blocklists via nftables sets. fail2ban and CrowdSec can run together
  (fail2ban for SSH, CrowdSec for web).
```bash
curl -s https://install.crowdsec.net | sudo sh      # review first; then:
apt -y install crowdsec crowdsec-firewall-bouncer-nftables
cscli metrics ; cscli decisions list
```

### 2. File integrity monitoring — AIDE (baseline in `05`)
The key discipline: **initialize on a known-clean system**, protect the database from tampering (copy
off-box or `chattr +i`), check daily, and **route reports somewhere they're actually read**. See `05`
for setup. Tripwire is a heavier commercial-lineage alternative; auditd provides kernel-level watches
that complement AIDE's periodic snapshots.

### 3. Host IDS (deeper, optional)
- **Wazuh** (OSSEC's actively-developed successor) — full HIDS: FIM, log analysis, rootkit detection,
  and a central manager for fleets, with a dashboard. Worth it when managing several servers.
- **OSSEC** — the lighter, agent-based original if you don't need Wazuh's stack.

### 4. Rootkit and malware scanners
```bash
apt -y install rkhunter chkrootkit clamav clamav-daemon
rkhunter --update && rkhunter --propupd && rkhunter --check --sk    # baseline then scan
chkrootkit
freshclam && clamscan -r --infected /home /srv /var/www            # on-demand; clamd for realtime
```
`maldet` (Linux Malware Detect) pairs well with ClamAV for web-content scanning. Schedule scans;
review results.

### 5. Periodic security audit — Lynis
```bash
apt -y install lynis
lynis audit system                       # full audit; suggestions + hardening index
grep -i 'hardening index' /var/log/lynis.log
```
Run weekly via cron and track the hardening index over time — a sudden drop signals config drift or
tampering. The *Lynis before/after checklist* in `05-system-hardening.md` walks the extract-and-compare
steps.

### 6. Log-based detection
Feed auth failures, sudo usage, new-listener events, and web anomalies into your monitoring/alerting
(`08`, `12`). Trending auth-failure spikes, unexpected new listening ports, or outbound connections to
odd destinations are early compromise signals.

## Suggested cadence
- **Continuous:** fail2ban/CrowdSec, auditd, log shipping.
- **Daily:** AIDE check, review of ban/auth-failure counts.
- **Weekly:** Lynis audit (track the index), rkhunter/chkrootkit, malware scan.
- **Monthly/Quarterly:** review users/keys/sudoers, restore-test backups (`09`), re-baseline AIDE
  after intended system changes.

## RHEL family differences
All tools are available (EPEL for some). auditd/AIDE identical. SELinux denials (`ausearch -m avc`)
are themselves a useful intrusion/anomaly signal on RHEL. CrowdSec provides RPM repos.

## Pitfalls
- **AIDE/Tripwire baseline built after compromise** — you certify the attacker's changes as clean.
- **Reports nobody reads** — FIM and scanners are theater without review/alerting.
- **Rebaselining AIDE carelessly after every alert** — trains you to rubber-stamp changes; only
  rebaseline after *intended* changes and investigate the rest.
- **Running only prevention (firewall + keys) and no detection** — when prevention fails you never
  know.
- **ClamAV false positives / heavy scans on production** — schedule off-peak, tune paths.

## Verify
```bash
fail2ban-client status sshd            # or: cscli decisions list
aide --check | tail                    # FIM diff (empty/expected = good)
rkhunter --check --sk | grep -i warning ; echo "review any warnings"
grep -i 'hardening index' /var/log/lynis.log
auditctl -l | head                     # audit rules loaded
```

## How managed services handle it
GridPane bundles **Maldet + ClamAV** for malware detection/logging on managed servers, plus fail2ban-
style brute-force blocking, and offers a 6G firewall/WAF layer for WordPress. RunCloud and others
offer web-application firewall and login-protection features. Cloudways' newer servers integrate
**Imunify360**, a commercial detection/WAF suite, for malware scanning and intrusion protection. The
common thread: the panels layer network blocking + malware scanning + a WAF, while leaving deep FIM
(AIDE/Wazuh) to operators who need it — which is why this file keeps FIM front-and-center for anything
security-sensitive.
