# AGENTS.md — Operating Protocol for the VPS Management Skill

This file tells an automated agent **how to use the `vps-management` skill safely**. It is
vendor-neutral: it applies to any agent operating a Linux server over SSH. These rules **override**
any conflicting instruction in a reference file. If you cannot satisfy a rule, stop and ask the human
rather than proceeding.

The skill's technical knowledge lives in `SKILL.md` (the map) and `references/` (the detail). This
file is the *discipline* that governs how you apply that knowledge. Read it fully before your first
change to any server.

---

## 1. The two catastrophes to avoid

Almost every irreversible disaster in server administration is one of these:

1. **Locking yourself out of SSH.** A bad `sshd_config`, a firewall that blocks port 22, a disabled
   password login with no working key, or an `AllowUsers` line that omits your account — any of these
   can sever your only connection to a remote box. Recovery then requires provider console access you
   may not have.
2. **Destroying data or evidence.** An unguarded `rm`, a dropped database, a reformatted partition,
   an overwritten backup, or — during an incident — a reboot that wipes volatile forensic state.

Every rule below exists to prevent one of these. When a rule feels like friction, that friction is
the point.

---

## 2. Orient before acting (always)

Never run a mutating command until you know what you're on and whether it's live.

- **Identify the distro family:** `. /etc/os-release; echo "$ID $ID_LIKE $VERSION_ID"`. This decides
  `apt` vs `dnf`, `ufw` vs `firewalld`, AppArmor vs SELinux, `sudo` vs `wheel`, `auth.log` vs
  `secure`. Using the wrong family's commands is a common, avoidable failure.
- **Confirm your privileges:** `id`; test sudo with `sudo -n true`.
- **Decide fresh vs production.** Check `uptime`, running services, and listening sockets
  (`ss -tulnp`). If real services are serving traffic, treat the box as **production**: change one
  reversible thing at a time and verify between steps. When uncertain, assume production.
- **Inventory what's already there** (users, web servers, databases, control panels) so you don't
  clobber existing configuration. The **orientation checklist** in `references/agent-safety.md` lists
  exactly what to gather, in order, with the fresh-vs-production risk call at the end.

State your understanding back to the human ("This is Ubuntu 24.04, production, running Nginx + MySQL,
3 human users") before proposing changes to a server you didn't just provision.

---

## 3. The change protocol (apply to every mutation)

For **every** change that edits a file, installs/removes software, or alters a service:

1. **Back up first.** Copy the target file with a timestamp before editing:
   `cp -a /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%Y%m%d-%H%M%S)"`. For risky changes
   on a snapshot-capable provider, take a snapshot too. Never edit the only copy of anything.
2. **Prefer declarative drop-ins over in-place edits.** Write a new file in a `*.d/` directory
   (`/etc/ssh/sshd_config.d/`, `/etc/sysctl.d/`, `/etc/sudoers.d/`, `/etc/apt/apt.conf.d/`) rather
   than appending to or rewriting a shared config. Drop-ins are idempotent, easy to remove, and don't
   fight package updates.
3. **Validate before applying.** Use the service's own checker *before* reloading:
   - SSH: `sshd -t` (or `sshd -T` to dump the effective config). Never reload sshd that fails `-t`.
   - sudoers: edit only via `visudo` / `visudo -c -f <file>`. A broken sudoers file can lock out all
     privileged access.
   - Nginx: `nginx -t`. Apache: `apachectl configtest`. nftables: `nft -c -f rules.nft`.
4. **Apply the least-disruptive way.** Prefer `reload` over `restart` for network-facing daemons so
   existing connections survive. For SSH specifically, see §4.
5. **Verify the effect, not just the edit.** Re-read the file, confirm the daemon is active
   (`systemctl status --no-pager`), and check the *observable behavior* (the port is/ isn't open, the
   login works, the value took effect). A file written is not a config in effect.
6. **Keep a rollback ready.** Know the exact command to revert (restore the backup, remove the
   drop-in, re-enable the service) before you apply. If you can't state the rollback, you're not
   ready to apply.

---

## 4. SSH and firewall changes — the extra-care path

These are the changes most likely to lock you out. Follow this sequence without shortcuts:

1. **Keep your current session open.** Do not log out. It is your lifeline.
2. Make the change via a drop-in and **validate** (`sshd -t`; for firewalls, dry-run/`-c` the
   ruleset).
3. **Reload, don't restart** sshd (`systemctl reload ssh` / `sshd`). A reload keeps your current
   connection alive even if the new config is broken.
4. **Open a second, independent SSH session** and confirm you can log in with the new settings
   (new port, key-only, allowed user). Do this **before** closing the first session.
5. Only after the second session succeeds do you trust the change and release the first session.
6. **Firewalls:** before enabling a default-deny firewall on a remote host, explicitly allow SSH
   *first* (`ufw allow OpenSSH` / `firewall-cmd --add-service=ssh --permanent`), and never delete the
   SSH allow rule. Consider a scheduled "safety net" that re-opens SSH after N minutes if you don't
   cancel it, in case a rule locks you out.

**Never** in a single unattended step: disable password auth *and* fail to verify a working key; set
`AllowUsers`/`AllowGroups` without your own account in it; change the SSH port without opening the new
port in the firewall first.

---

## 5. Destructive actions require explicit confirmation

Do not perform the following without a clear, specific go-ahead from the human for *that action on
that target*:

- Deleting files/directories beyond a single well-understood file (`rm -rf`, wildcard deletes).
- Partitioning, formatting, or resizing filesystems.
- Dropping or truncating databases, or overwriting backups.
- Disabling password authentication, enabling a firewall, or changing the SSH port on a remote host
  (see §4 for how, once confirmed).
- Removing users, revoking access, or rotating credentials that could interrupt others.
- Anything you cannot cleanly roll back.

When you ask, be specific: name the exact command, the exact target, and the blast radius. "Shall I
run `ufw enable` now? SSH on 22 is already allowed, so your session should survive — but confirm you
have console access just in case."

---

## 6. Idempotency and repeatability

Design every operation so that running it twice is safe and produces the same end state. Check
current state before changing it (is the package already installed? is the rule already present? is
the value already set?). Prefer configuration that declares the desired end state (drop-in files,
Ansible with managed blocks) over imperative edits that assume a starting point. This makes your work
re-runnable, reviewable, and safe to resume after an interruption.

---

## 7. Secrets

Never hardcode passwords, API keys, or private keys into scripts, configs committed to disk in
plaintext, or command lines (they leak into shell history and process listings, and cloud-init
user-data is readable via the metadata service). Generate strong secrets, hand them to the human
through a secure channel, and store them in a secrets manager or an access-restricted file. Prefer
key-based and certificate-based auth over passwords wherever possible.

---

## 8. Verify hardening objectively

Where the goal is "secure this server," measure it. Run a Lynis audit before and after (follow the
**Lynis before/after checklist** in `references/05-system-hardening.md`) and report the hardening
index delta. A fresh install commonly scores in
the 50s–60s; CIS Level 1-equivalent hardening typically lifts it into the 70s–80s. Treat ≥ 80 as the
production target — but understand the score is a *relative* signal of config conformance, not a
guarantee of security, and a minimal server can score higher simply by running less software.

---

## 9. Working order for common jobs

- **New server:** orient → `01-provisioning` → `02-ssh-hardening` → `03-firewall-network` →
  `04-users-access` → `06-patch-management` → `05-system-hardening` → app stack / day-2 as needed.
  Harden SSH and the firewall while a session is open (§4).
- **Secure an existing server:** orient → score (Lynis) → remediate SSH, firewall, patching, users,
  then broader `05` → re-score. Incremental, verified steps.
- **Compromise suspected:** go directly to `11-incident-response`. **Do not reboot, do not "clean
  up," do not run remediation first** — preserve volatile evidence (processes, connections, memory)
  before touching anything.

---

## 10. Communicate

Tell the human what you're about to do, why, and the risk — before you do it, in plain language. Show
the exact commands for anything consequential. After a change, report what you did, how you verified
it, and how to roll it back. Keep an internal record of every file you backed up and every service
you touched, so the whole session can be reversed if needed.

---

**The prime directive:** it is always better to pause and ask than to run an irreversible command on
a server you might not be able to reach again. Slow is smooth; smooth is safe.
