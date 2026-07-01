# 02 — SSH Hardening

SSH is the front door. If it's weak, everything behind it is weak. This file configures key-only
authentication, disables the risky defaults, sets modern cryptography, and adds brute-force
mitigation — all without locking you out.

> **Follow the extra-care path in `AGENTS.md` §4 for every change here.** Keep your session open,
> validate with `sshd -t`, `reload` (don't `restart`), and confirm a second independent login before
> you trust the change.

## Apply checklist (anti-lockout)

Work this order every time. The gate at step 3 is the one that most often prevents a lockout — do not
skip it.

- [ ] **Keep the current session open** for the entire procedure; it's your lifeline if the new config
  is broken.
- [ ] **Back up first:** `cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d-%H%M%S)"`.
- [ ] **Gate before disabling passwords:** confirm the account you'll keep in `AllowUsers` actually has
  a usable key — `test -s "$(getent passwd <user> | cut -d: -f6)/.ssh/authorized_keys" && echo OK`.
  If it's missing or empty, **leave `PasswordAuthentication` on**, add the key first, and only then
  come back and disable passwords. Never emit `PasswordAuthentication no` for a user with no verified
  key.
- [ ] **Write settings as a drop-in**, not an edit to the shared file: `/etc/ssh/sshd_config.d/00-hardening.conf`
  (the baseline in *How* §1) and, if desired, `10-crypto.conf` (§2). Include `AllowUsers <you>` and
  make sure your own account is in it.
- [ ] **If you changed the port**, open the new port in the firewall *first* (`03-firewall-network.md`)
  — otherwise you can't reconnect.
- [ ] **Validate:** `sshd -t` must pass (revert the drop-in and stop if it fails); `sshd -T | grep -Ei
  'permitrootlogin|passwordauth|pubkeyauth|allowusers'` to confirm the values actually took.
- [ ] **Reload, don't restart:** `systemctl reload ssh` (RHEL: `sshd`) — a reload keeps your current
  connection alive even if the config is wrong.
- [ ] **Prove a second login** in a *new* terminal, exercising the new settings (new port, key-only,
  allowed user), **before** closing the first session.
- [ ] **Know the rollback** before you apply: `rm /etc/ssh/sshd_config.d/00-hardening.conf &&
  systemctl reload ssh` (or restore the timestamped backup).

## Why

The authoritative configuration sources are the Mozilla OpenSSH guidelines and sshaudit.com's
hardening guides; CIS Benchmarks codify the same settings as auditable controls. The goals:
eliminate password brute-forcing (keys only), deny direct root login, minimize the authentication
attack surface, and use only modern, non-broken cryptographic primitives.

## Keep your OpenSSH current — the cipher list is not permanently optimal

Crypto recommendations and CVEs move; a fixed algorithm list is correct only until it isn't.
**Re-verify against current advisories rather than trusting any static snapshot.**

- **Patch OpenSSH through your distro first.** Upstream OpenSSH 10.3 (April 2026) fixed several
  security bugs. One notable issue, CVE-2026-35414, affected a narrower SSH-certificate path: user
  CAs trusted through `authorized_keys` with `principals=""` restrictions, where a CA could issue
  comma-containing principals. If you use SSH CAs, verify your installed package includes the 10.3
  fix or a vendor backport, prefer `TrustedUserCAKeys`/`AuthorizedPrincipalsFile` for the main CA
  path, and disallow commas in principal names. Also review distro advisories for the other OpenSSH
  10.3-era fixes before deciding whether a scanner finding is real or already backported.
- Earlier advisories still worth knowing: **CVE-2025-26465** (VerifyHostKeyDNS server impersonation),
  **CVE-2025-26466** (pre-auth memory/CPU DoS via `SSH2_MSG_PING`, mitigated by `PerSourcePenalties`),
  and **Terrapin / CVE-2023-48795** (prefix-truncation; mitigated by strict-kex, which modern OpenSSH
  negotiates automatically).
- **Before finalizing any cipher/KEX/MAC list, verify it against the running version** with
  `ssh-audit` (below) and check `https://www.openssh.com/security.html` and your distro's security
  notices for anything newer than this document. Patch first, then configure.

```bash
ssh -V                                  # note the version
apt-cache policy openssh-server         # Debian/Ubuntu: confirm the patched package/backport
# RHEL family: rpm -q --changelog openssh-server | head -40
```

## How (Ubuntu/Debian primary)

### 1. Confirm key auth works, then write the hardening drop-in
Modern Ubuntu's `/etc/ssh/sshd_config` ends with `Include /etc/ssh/sshd_config.d/*.conf`, so drop a
file there rather than editing the main config.

Replace `deploy` with the account you have already proven can log in from a second session. Leave
`PasswordAuthentication yes` until that key-only login succeeds; disable password auth in the
separate step below.

```bash
ADMIN_USER=deploy   # replace with the account you already proved can log in and sudo
cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d-%H%M%S)"
cat >/etc/ssh/sshd_config.d/00-hardening.conf <<EOF
# --- Authentication ---
PermitRootLogin no
PasswordAuthentication yes        # temporary: turn off only after key-only second login is proven
PubkeyAuthentication yes
KbdInteractiveAuthentication no
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30
AllowUsers ${ADMIN_USER}

# --- Reduce surface ---
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no             # relax per-need if you rely on SSH tunnels
PermitEmptyPasswords no
PermitUserEnvironment no

# --- Hygiene / visibility ---
LogLevel VERBOSE                  # logs key fingerprints used to log in
ClientAliveInterval 300
ClientAliveCountMax 2

# --- DoS mitigation (OpenSSH >= 9.5) ---
PerSourceMaxStartups 4:30:20
EOF
```

After `sshd -t`, reload, and a second successful key-based login, disable password auth in a separate
drop-in so rollback is one file:

```bash
cat >/etc/ssh/sshd_config.d/20-key-only.conf <<'EOF'
PasswordAuthentication no
AuthenticationMethods publickey
EOF
sshd -t && systemctl reload ssh
```
Open a new SSH session again and prove it succeeds by key before closing the original session.

### 2. Set modern cryptography — verify against the installed version first
These lists reflect Mozilla "modern"/sshaudit guidance at time of writing. **Confirm with
`ssh-audit` after applying** and adjust to what your OpenSSH build actually supports.

```bash
cat >/etc/ssh/sshd_config.d/10-crypto.conf <<'EOF'
KexAlgorithms sntrup761x25519-sha512@openssh.com,mlkem768x25519-sha256,curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,umac-128-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256
PubkeyAcceptedAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256
EOF
```
(If `ssh-audit` reports an unsupported algorithm on an older build, remove it — e.g. the post-quantum
`mlkem768x25519-sha256` and `sntrup761x25519-sha512` KEX require newer OpenSSH.)

### 3. Prefer strong host keys; prune weak DH moduli
```bash
# Keep ed25519 + rsa (4096); remove small/legacy host keys if present.
awk '$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.safe && mv /etc/ssh/moduli.safe /etc/ssh/moduli
```

### 4. Validate, reload, and TEST FROM A SECOND SESSION
```bash
sshd -t && echo "config OK"            # never reload if this fails
sshd -T | grep -Ei 'permitrootlogin|passwordauth|pubkeyauth|allowusers'   # confirm effective values
systemctl reload ssh                    # reload keeps your current session alive
```
Now open a **new** terminal and `ssh deploy@host`. Only after that succeeds should you close the
original session.

### 5. Optional: change the SSH port
Security-by-obscurity. On a key-only host it adds no real protection and Lynis notes minimal benefit;
it does cut automated-bot log noise. If you do it, **open the new port in the firewall first**
(`03-firewall-network.md`), set `Port 2222` in the drop-in, and (on systemd-socket setups) adjust
`ssh.socket`.

### 6. Brute-force mitigation: fail2ban (default) or CrowdSec (busy/public hosts)
```bash
cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled  = true
backend  = systemd
maxretry = 4
findtime = 10m
bantime  = 1h
bantime.increment = true
EOF
systemctl enable --now fail2ban
fail2ban-client status sshd
```
For a public server taking thousands of attempts/hour, prefer **CrowdSec** (behavioral, crowd-sourced
blocklists, scales via nftables sets) — see `10-intrusion-detection.md`. fail2ban and CrowdSec can
coexist.

### 7. Optional: two-factor (TOTP) and SSH certificate authorities
- **TOTP 2FA:** `libpam-google-authenticator`, add to `/etc/pam.d/sshd`, set
  `AuthenticationMethods publickey,keyboard-interactive` and `KbdInteractiveAuthentication yes`.
  Adds a second factor on top of keys.
- **SSH certificate authority:** at fleet scale, sign short-lived user certificates instead of
  distributing `authorized_keys`. **Given CVE-2026-35414, only do this on OpenSSH ≥ 10.3**, and avoid
  commas inside certificate principal names.

## RHEL family differences
- Config lives in `/etc/ssh/sshd_config.d/` on modern releases too; service is `sshd`
  (`systemctl reload sshd`).
- Crypto policy is centrally managed: `update-crypto-policies --set FUTURE` (or `DEFAULT`) sets
  system-wide algorithm baselines that SSH inherits; per-service overrides go in the drop-in.
- Auth failures log to `/var/log/secure`. Use `firewalld` for the port (`03`).

## Pitfalls
- **Disabling `PasswordAuthentication` without a verified working key = lockout.** Verify the key in a
  second session first.
- **`AllowUsers`/`AllowGroups` that omits your account** silently blocks you at next login. Confirm
  before closing your session.
- **`restart` instead of `reload`** can drop your connection mid-change if the new config is bad.
- **A hardened `sshd_config.d/*.conf` that fails `sshd -t`** won't apply — always check `-t` output,
  not just the exit of `reload`.
- **Copy-pasting a cipher list without `ssh-audit`** can either break connectivity (unsupported algo)
  or silently leave weak algorithms enabled.

## Verify
```bash
sshd -T | grep -Ei 'permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries'
# From your workstation, audit the live server:
ssh-audit host                          # aim for all-green; heed its version/algorithm warnings
# Confirm password login is actually refused:
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no deploy@host   # should be denied
```

## How managed services handle it
The convergence here is near-total. SpinupWP disables SSH access for the **root** user on all servers
and disables SSH **password** authentication by default — key-only, non-root, exactly this file's
core. Forge keeps port 22 open, accepts key auth only, and warns operators to **never delete the SSH
rule**. Ploi, RunCloud, and GridPane all provision key-only, root-login-disabled SSH as their
baseline. The panels differ mainly in brute-force tooling (some ship fail2ban, GridPane leans on its
own blocking plus optional tooling), but the authentication posture is identical to the standard.
