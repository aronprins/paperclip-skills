# 00 — Agent Safety (the reasoning behind AGENTS.md)

`AGENTS.md` in the skill root is the operating protocol — the rules. This file is the *why* and the
detailed playbooks behind them. Read `AGENTS.md` first; consult this when you want the reasoning, the
lockout-recovery procedures, or the fuller checklists.

## The mental model

You are operating a machine you may only be able to reach through one fragile channel (SSH), and some
actions on it are irreversible. Treat every session like operating on something live and remote:
optimize for *never creating an unrecoverable situation*, even at the cost of speed. The two failure
modes that matter — **lockout** and **data/evidence destruction** — are both prevented by the same
habits: keep a lifeline, back up before changing, validate before applying, verify after, and confirm
before anything irreversible.

## Playbook A — Never lock yourself out of SSH

This is the failure mode most unique to remote server work. The sequence:

1. **Keep the current session open the entire time.** It bypasses the change you're testing, so even a
   broken config leaves you a way in.
2. **Change via a drop-in and validate:** `sshd -t` must pass; `sshd -T` dumps the *effective* config
   so you can confirm the values actually took (`sshd -T | grep -i passwordauthentication`).
3. **`reload`, never `restart`:** a reload re-reads config without dropping established connections.
4. **Prove a second, independent login works** — new terminal, new SSH connection, exercising the new
   settings (new port, key-only, allowed user) — *before* closing the first session.
5. **For firewalls:** allow SSH before enabling default-deny; never delete the SSH allow rule. On a
   host where you're unsure of console access, arm a self-healing net first, e.g.
   `echo 'ufw allow OpenSSH && systemctl reload ssh' | at now + 15 minutes`, do the risky change,
   confirm access, then `atrm` the job. If you get locked out, the timer restores access.

### If you *are* locked out
- Use the **provider's web console / VNC / serial console** to log in out-of-band and revert (restore
  the `sshd_config` backup / remove the firewall rule / `ufw disable`).
- If a provider "recovery mode" or rescue system is the only option, mount the disk and edit the
  offending file directly.
- This is exactly why you took a timestamped backup and (ideally) a snapshot before the change.

## Playbook B — The universal change protocol

For every mutation (file edit, package change, service change):

- **Back up:** `cp -a <file> <file>.bak.$(date +%Y%m%d-%H%M%S)`; snapshot for risky changes.
- **Prefer drop-ins:** write to a `*.d/` directory instead of editing shared files — idempotent,
  removable, update-safe.
- **Validate before apply:** `sshd -t`, `visudo -c`, `nginx -t`, `apachectl configtest`, `nft -c -f`,
  `ansible-playbook --check`, `unattended-upgrade --dry-run`.
- **Apply least-disruptively:** `reload` over `restart` for network daemons.
- **Verify the effect:** re-read the file, `systemctl status`, and check observable behavior (port
  open? login works? value set?). *A file written is not a config in effect.*
- **Hold a rollback:** if you can't state the exact revert command, you're not ready to apply.

## Playbook C — Destructive-action gate

Do not, without explicit confirmation of the specific action on the specific target: delete beyond one
well-understood file; partition/format/resize; drop/truncate databases or overwrite backups; disable
password auth / enable a firewall / change the SSH port on a remote host (use Playbook A once
confirmed); remove users or rotate shared credentials; or anything you can't cleanly roll back. When
asking, name the exact command, target, and blast radius.

## Playbook D — Suspected compromise

Reverse your instincts: **do not reboot, do not clean up, do not remediate first.** Preserve volatile
evidence (processes, connections, memory) and understand scope before changing state. Then contain
(prefer provider-level network isolation + snapshot over `poweroff`), then recover (usually
rebuild-from-clean + restore a backup that predates the intrusion + rotate all credentials). Full
procedure in `11-incident-response.md`. Get human confirmation before any state-changing containment.

## Orientation checklist (read-only — run before any change)

Gather these facts *first*, every session, before you touch anything. Every command here only reads
state; none of it modifies the box. Work top to bottom and state your understanding back to the human
before proposing changes.

- [ ] **Identity & privilege.** `id`; then test escalation with `sudo -n true` (passwordless),
  falling back to "sudo present but will prompt" or "no sudo." You cannot plan changes until you know
  what you can do.
- [ ] **Distro family** (decides every later command). `. /etc/os-release; echo "$ID $ID_LIKE $VERSION_ID"`,
  then map it:
  - *Debian/Ubuntu* → `apt`, `ufw`, AppArmor, admin group `sudo`, auth log `/var/log/auth.log`.
  - *RHEL family* (Alma/Rocky/RHEL/Fedora/CentOS) → `dnf`, `firewalld`, SELinux, admin group `wheel`,
    auth log `/var/log/secure`.
  - *Unknown* → verify each command manually before running it.
- [ ] **Uptime, kernel, pending reboot.** `uptime`; `uname -r`; check `/var/run/reboot-required`
  (Debian) — a pending kernel/libc reboot changes your patch/reboot plan.
- [ ] **Human login users.** `getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1,$3,$7}'` — who
  else has an account, and with which shell.
- [ ] **Listening sockets (attack surface).** `ss -tulnp` — every `0.0.0.0`/`[::]` listener is
  something the box exposes; each should be one you *intend* to expose.
- [ ] **Running services.** `systemctl list-units --type=service --state=running --no-pager` — what is
  actually live.
- [ ] **Detected stacks / control panels.** Probe for `nginx apache2 httpd php-fpm mysql mariadb
  postgres docker containerd redis-server memcached` on `PATH`, and for panel markers
  (`/opt/RunCloud`, `/etc/gridpane`, `/usr/local/cpanel`, `/usr/local/psa`, `/opt/cyberpanel`,
  `/www/server`, …). A managed panel means config is owned by *its* tooling — don't clobber it.
- [ ] **Security posture snapshot.** `sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|pubkeyauthentication) '`
  (effective SSH auth); `ufw status` / `firewall-cmd --state`; `getenforce` / `aa-status` (MAC).
- [ ] **Make the fresh-vs-production call.** Heuristic: **more than ~3 public listeners or ~25 running
  services ⇒ treat as production** — change one reversible thing at a time and verify between steps.
  Fewer ⇒ likely fresh/lightly-used and safe to harden in one pass, but *still* keep a session open
  and back up before each change. When in doubt, assume production.

## Fresh vs production risk posture

- **Fresh box (just provisioned, nothing serving traffic):** you can harden aggressively in one pass;
  the blast radius of a mistake is a rebuild.
- **Live production (real services, real users):** change one reversible thing at a time, verify
  between steps, and avoid one-shot hardening scripts (`noexec` mounts, module blacklists, strict
  sysctls can break running software). When uncertain which you're on, assume production.

## Idempotency, in practice

Check state before changing it (is the package installed? the rule present? the value already set?).
Prefer configuration that declares the end state (drop-ins, Ansible managed blocks) over imperative
appends that assume a starting point and double-apply on re-run. This makes your work resumable after
an interruption and safe to run twice — a property an autonomous agent needs, because it may retry.

## Objective verification

Where the goal is "secure this," measure it: Lynis hardening index before and after (the *Lynis
before/after checklist* in `05-system-hardening.md`), key-only SSH confirmed from a second session,
default-deny firewall
exposing only intended ports, auto-updates on with a reboot policy, and — for data — a **restored**
backup, not merely a taken one. Report the deltas. Remember Lynis measures config conformance, not
absolute security, and a minimal server scores higher partly by running less.

## The prime directive

It is always better to pause and ask than to run an irreversible command on a server you might not be
able to reach again. Slow is smooth; smooth is safe.
