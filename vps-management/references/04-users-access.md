# 04 — User & Access Management

Least privilege in practice: the right people have exactly the access they need, unused accounts are
locked, privilege escalation is controlled and logged. Misconfigured sudo and stale accounts are the
most common privilege-escalation findings in production audits.

## Why

The principle of least privilege (NIST, CIS) says every account and process should have the minimum
rights to do its job — no standing root, no shared logins, no `NOPASSWD: ALL` unless truly required.
Password policy and account lockout (CIS) blunt credential-guessing; login banners and access
auditing support both deterrence and forensics.

## How (Ubuntu/Debian primary)

### 1. sudo via group + drop-in policy
Grant admin rights by group membership (`sudo` on Debian/Ubuntu, `wheel` on RHEL), and add any
narrower rules as drop-in files edited with `visudo`.
```bash
usermod -aG sudo deploy
# Narrow, auditable rule example (edit via visudo so a syntax error can't lock out sudo):
visudo -f /etc/sudoers.d/deploy-restart
# deploy ALL=(root) /usr/bin/systemctl restart nginx, /usr/bin/systemctl reload nginx
visudo -c                       # validate all sudoers files
```
Avoid blanket `NOPASSWD: ALL`. If automation needs passwordless sudo, scope it to specific commands.

### 2. Lock down root and unused accounts
```bash
passwd -l root                  # lock root's password (key/console recovery still possible)
# Lock and shell-disable service or ex-employee accounts:
usermod -L -e 1 -s /usr/sbin/nologin olduser
# Audit for surprises:
awk -F: '($3<1000)&&($7!~/nologin|false/){print $1" has login shell "$7}' /etc/passwd
awk -F: '($2==""){print $1" HAS NO PASSWORD"}' /etc/shadow
```

### 3. Password quality policy (pam_pwquality)
```bash
apt -y install libpam-pwquality
# /etc/security/pwquality.conf  (CIS-aligned)
cat >/etc/security/pwquality.conf <<'EOF'
minlen = 14
minclass = 4
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
maxrepeat = 3
enforce_for_root
EOF
```

### 4. Account lockout (pam_faillock)
Lock accounts after repeated failures to slow interactive brute-forcing.
```bash
# /etc/security/faillock.conf
cat >/etc/security/faillock.conf <<'EOF'
deny = 5
unlock_time = 900
fail_interval = 900
EOF
# On Debian/Ubuntu, enable via: pam-auth-update  (select faillock), or add pam_faillock lines to
# /etc/pam.d/common-auth. On RHEL: authselect enable-feature with-faillock.
```
Check/reset with `faillock --user deploy` / `faillock --user deploy --reset`.

### 5. Default umask and login banners
```bash
# Restrictive default file perms for new files (027 = group r-x, others none):
sed -i 's/^UMASK.*/UMASK 027/' /etc/login.defs 2>/dev/null || echo 'UMASK 027' >> /etc/login.defs
# Legal/deterrent banner shown pre- and post-login:
printf 'Authorized access only. Activity is monitored and logged.\n' | tee /etc/issue /etc/issue.net
# Point sshd at it: add `Banner /etc/issue.net` to /etc/ssh/sshd_config.d/00-hardening.conf
```

### 6. Audit who has access and what they did
```bash
getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1}'   # real login users
last -20                     # recent logins
lastb -20                    # recent FAILED logins (needs /var/log/btmp)
w                            # who is on now
grep -Po '^sudo.+:\K.*' /etc/group          # who's in the sudo group
# auditd watches on privilege files (see 05/12):
auditctl -w /etc/sudoers -p wa -k scope
auditctl -w /etc/sudoers.d -p wa -k scope
```

## RHEL family differences
- Admin group is `wheel`. PAM stack is managed with `authselect` (e.g.
  `authselect enable-feature with-faillock`) rather than hand-editing `common-auth`.
- pam_pwquality config path is the same (`/etc/security/pwquality.conf`).
- Auth events log to `/var/log/secure`.

## Pitfalls
- **Editing `/etc/sudoers` or files in `/etc/sudoers.d/` without `visudo`.** A syntax error can make
  `sudo` refuse to run for *everyone*, and if root's password is locked you may have no way back in.
  Always `visudo -c`.
- **`NOPASSWD: ALL` for a service account** effectively hands out root to anything that compromises
  that account.
- **Locking accounts you still need** — verify you're not locking the only admin.
- **Password policy that's so strict users write passwords down** — balance; keys > passwords anyway.

## Verify
```bash
sudo -l -U deploy                 # exactly the sudo rights you intended
visudo -c                         # all sudoers files valid
awk -F: '($2==""){print}' /etc/shadow    # no empty-password accounts (empty output = good)
faillock --user deploy            # lockout tracking works
grep -E 'minlen|minclass' /etc/security/pwquality.conf
```

## How managed services handle it
The panels enforce isolation more than interactive-user policy: RunCloud, Forge, Ploi, and GridPane
create a **separate system user per site/application**, so a compromise of one app can't read another
app's files — a least-privilege pattern at the workload level. ServerPilot similarly isolates each
app under its own system user with its own PHP-FPM pool. Human administrators authenticate to the
panel (often with 2FA) and the panel executes changes as the appropriate scoped user, rather than
everyone sharing root — the same "no standing shared root" goal this file pursues at the OS level.
