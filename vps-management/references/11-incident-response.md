# 11 — Incident Response

When a server is (or might be) compromised. **The order of operations here is the opposite of your
instinct.** Do not reboot, do not "clean up," do not start reinstalling — first preserve evidence and
understand scope, then contain, then recover. Rebooting or deleting destroys the volatile data
(running processes, network connections, memory, open files) that tells you what happened.

> **Agent rule:** on any suspicion of compromise, read this whole file before running anything. Prefer
> **read-only investigation** commands first. Get explicit human confirmation before containment
> actions that change state (killing processes, cutting network, rebuilding).

## Why

Incident response follows a standard lifecycle (NIST SP 800-61: prepare, detect/analyze, contain,
eradicate, recover, learn). Volatile evidence has the shortest lifespan and the highest forensic
value, so it's collected first. For most production compromises, **rebuild from a known-clean image +
verified backup beats in-place cleanup** — you can rarely prove you removed every persistence
mechanism.

## How

### 1. Detect / confirm — is this real?
Signs: unexpected outbound traffic or CPU (cryptominers), unknown processes, new users/keys,
modified system binaries (AIDE alert), fail2ban/auth-log anomalies, defaced content, disk filling with
unknown data, logins from unexpected geographies/times.

### 2. Preserve evidence FIRST (read-only; capture output off-box)
Capture to a file and copy it to another host before you change anything.
```bash
# Volatile state — collect before any containment:
date -u; uptime; w; who -a
ps auxfww                                  # full process tree; look for odd parents, /tmp, /dev/shm
ss -tulpanew                               # every connection + listening socket + owning process
lsof -i -n -P                              # network files; lsof +L1 (deleted-but-open = classic malware)
ls -la /proc/<pid>/exe /proc/<pid>/cwd     # for suspicious PIDs: where the binary really lives
cat /proc/<pid>/environ | tr '\0' '\n'     # env of a suspicious process
```

### 3. Investigate persistence and accounts (this is where attackers hide)
```bash
# New or password-less users, UID 0 duplicates:
awk -F: '($3==0){print}' /etc/passwd                     # anything other than root = backdoor
getent passwd | grep -vE 'nologin|false'                 # accounts with real shells
# Unauthorized SSH keys anywhere on the system:
find / -name authorized_keys -not -path '*/snap/*' 2>/dev/null -exec ls -la {} \; -exec cat {} \;
# CRON is the #1 persistence spot — check ALL of it:
for u in $(cut -f1 -d: /etc/passwd); do crontab -l -u "$u" 2>/dev/null | sed "s/^/$u: /"; done
ls -la /etc/cron.* /etc/crontab /var/spool/cron/ 2>/dev/null; cat /etc/cron.d/* 2>/dev/null
# systemd persistence:
systemctl list-units --type=service --state=running; systemctl list-timers --all
ls -la /etc/systemd/system /run/systemd/system ~/.config/systemd/user 2>/dev/null
# Recently modified system binaries / suspicious executables in world-writable dirs:
find /tmp /dev/shm /var/tmp -type f -executable 2>/dev/null
find /usr/bin /usr/sbin /bin /sbin -mtime -7 -type f 2>/dev/null
# Login history (and failed):
last -Faiw | head -40; lastb -Faiw | head -40
# Who did what as root — auditd's auid survives privilege escalation:
ausearch -m execve -ts recent 2>/dev/null | aureport -i --summary 2>/dev/null | head
```

### 4. Contain (after evidence capture, with confirmation)
Choose based on whether you need to keep investigating:
- **Network isolation** preserves the box for forensics while cutting the attacker: tighten the
  firewall to your management IP only, or detach it from the network at the provider level (a
  snapshot first preserves disk state). Prefer provider-level network isolation over `poweroff`
  (which destroys memory evidence) unless active damage requires an immediate stop.
- **Do not** simply `kill` and move on — that tips the attacker and loses state; capture first.
- Take a **provider snapshot / disk image now** for later forensics regardless of path chosen.

### 5. Eradicate & recover — rebuild is usually right
- **Preferred: rebuild.** Provision a fresh, fully-patched server from a clean image, restore
  application data from a **known-clean** backup (verify it predates the compromise — check your FIM
  history and backup timestamps against the intrusion timeline), harden it (`01`–`06`), and cut over.
- **Remediate in place only** for well-understood, contained incidents where you can positively
  identify and remove the entry vector and all persistence — and even then, trust it less.
- **Rotate every credential**: SSH keys, all user/DB/app passwords, API tokens, and any secret that
  touched the box. Assume all were captured.
- Patch the entry vector (the vulnerable app/service/credential that let them in) — otherwise you'll
  be reinfected.

### 6. Learn (post-incident)
Write a timeline and root-cause: how they got in, what they touched, what data was exposed, how it was
detected, how long they were present. Feed fixes back into hardening (`05`), detection (`10`), and
patching (`06`). Preserve the disk image and logs per any legal/compliance retention needs, and notify
per breach-disclosure obligations if data was exposed.

## RHEL family differences
Auth history is in `/var/log/secure`. SELinux AVC denials (`ausearch -m avc -ts recent`) can reveal
what the attacker's process tried to do. Otherwise the process/cron/systemd/key hunt is identical.

## Pitfalls
- **Rebooting or powering off first** — destroys memory, running processes, and network state, the
  most valuable evidence. (An attacker may also have set persistence that *survives* reboot anyway.)
- **"Cleaning up" before understanding scope** — you tip the attacker, lose evidence, and usually miss
  a persistence mechanism.
- **Restoring from a backup taken *after* the compromise** — you reinstate the backdoor. Verify the
  backup predates the intrusion.
- **Trusting in-place cleanup** for a root-level compromise — you can rarely prove eradication;
  rebuild.
- **Not rotating credentials** — they come straight back in.
- **Investigating with the compromised box's own binaries** (which may be trojaned) — where possible,
  cross-check with known-good static tools or off-box analysis of the disk image.

## Verify (after recovery)
```bash
# On the rebuilt host: baseline is clean and hardened.
lynis audit system | grep -i 'hardening index'
aideinit && cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db     # fresh clean FIM baseline
ss -tulpanew | grep LISTEN         # only expected services listening
last -Faiw | head                  # only your logins
# Confirm the entry vector is closed (patched app / rotated cred / removed exposure).
```

## How managed services handle it
Managed platforms lean hard on **prevention + rebuild-ability** rather than forensic cleanup: brute-
force blocking, WAF/malware scanning (GridPane's Maldet+ClamAV, Cloudways' Imunify360), and easy
re-provisioning from clean images plus offsite backups (`09`) so a compromised site can be rebuilt and
restored quickly. That operational stance — *assume you'll rebuild, so keep clean images and verified
offsite backups ready* — is the most important takeaway for an autonomous agent: the fastest safe path
out of a serious compromise is almost always rebuild-and-restore, not clean-in-place.
