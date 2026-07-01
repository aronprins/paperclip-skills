# 14 — Automation & Infrastructure-as-Code

Repeatable, idempotent, auditable configuration beats hand-editing — especially across more than one
server. cloud-init for first-boot provisioning, Ansible (with a battle-tested hardening collection)
for ongoing config, hardened golden images, and disciplined secrets handling. This is also where an
autonomous agent's work becomes reviewable and reversible.

## Why

Manual, one-off server changes drift, can't be reviewed, and can't be reliably reproduced or rolled
back. IaC makes the desired state explicit, version-controlled, and idempotent (safe to re-run). For
an agent, that's not just tidiness — declarative, idempotent changes are the safest kind, because they
describe an end state rather than assuming a starting point, and they can be diffed and reverted.

## How

### 1. cloud-init — provision correctly at first boot
Most cloud images run cloud-init on first boot; feed it user-data to create the admin user, install
keys, and do the base setup from `01` before you ever log in.
```yaml
#cloud-config
users:
  - name: deploy
    groups: [sudo]                 # wheel on RHEL
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL" # tighten later; or require password
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... you@workstation
ssh_pwauth: false                  # key-only from the start
package_update: true
package_upgrade: true
packages: [ufw, fail2ban, unattended-upgrades, auditd, chrony]
runcmd:
  - ufw default deny incoming
  - ufw allow OpenSSH
  # Enable the firewall in a later, verified step unless this exact user-data has already been
  # tested on the target provider and you have out-of-band console recovery.
```
Do not add `ufw --force enable` to first-draft cloud-init. First boot is unattended, so a bad SSH key,
wrong default user, custom SSH port, or provider image quirk can lock you out before you ever get a
lifeline session. For fleets, test the full user-data on a disposable server with provider-console
recovery, then promote the exact known-good definition.

**Security (cloud-init's own hardening guidance):** never put plaintext passwords or secrets in
`user-data`, `runcmd`, or `bootcmd` — user-data is readable via the cloud metadata service and may be
logged in `/var/log/cloud-init*.log`. Use `hashed_passwd` (never plaintext), `ssh_authorized_keys` /
`ssh_import_id`, and pull real secrets at runtime from a secrets manager, not from user-data.

### 2. Ansible — repeatable ongoing configuration
Ansible is agentless (works over SSH), idempotent, and readable. Use it for everything past first boot
so every server's state is described in version control.
```bash
pipx install ansible-core || pip install --user ansible
ansible-galaxy collection install devsec.hardening   # battle-tested CIS-aligned hardening
```
Use the **`devsec.hardening`** collection rather than reinventing controls — it provides
`os_hardening`, `ssh_hardening`, plus nginx/mysql roles implementing CIS recommendations for Linux and
SSH. A minimal playbook:
```yaml
- hosts: servers
  become: true
  roles:
    - devsec.hardening.os_hardening
    - devsec.hardening.ssh_hardening
  # layer your app roles after the hardening baseline
```
Run with `--check` (dry run) first, then `--diff` to see exactly what changes. Prefer Ansible modules
and `blockinfile`/`template` (idempotent, marked) over `lineinfile`/`shell` hacks.

### 3. Golden images — bake hardening in, deploy fast
For fleets, don't harden each box at boot — build a **hardened image once** and launch from it.
**Packer** runs your Ansible hardening role against a base image and produces a reusable machine
image; new servers come up already at your baseline (and already scoring well on Lynis). This also
makes rebuild-after-compromise (`11`) fast.

### 4. Secrets management
- **Never hardcode** secrets in playbooks, scripts, cloud-init, or command lines.
- **Ansible Vault** encrypts variable files at rest (`ansible-vault encrypt group_vars/secrets.yml`).
- For dynamic/short-lived secrets use a secrets manager (HashiCorp Vault, cloud KMS/Secrets Manager,
  SOPS + age). Generate strong values, deliver them to humans over a secure channel, and rotate them.
- Keep the git repo clean: a secret committed once is compromised forever — use pre-commit secret
  scanning.

### 5. How an agent should apply changes safely (ties back to AGENTS.md)
- **Dry-run first** (`ansible-playbook --check --diff`, `unattended-upgrade --dry-run`, `nft -c`,
  `sshd -t`).
- **Idempotent + declarative** (drop-in files, Ansible managed blocks) so re-runs are safe and diffs
  are meaningful.
- **Back up / snapshot before applying**; know the rollback (revert the commit, remove the drop-in,
  restore the file).
- **Verify after** (re-read state, run the validator, re-score with Lynis).
- **Never** run a full destructive change set unattended on production without staging it first.

## RHEL family differences
cloud-init uses `wheel` for the admin group and `dnf` packages. Ansible and `devsec.hardening` are
distro-aware and support RHEL-family targets. Packer builds RHEL/Alma/Rocky images the same way.
`update-crypto-policies` and SELinux are managed as Ansible tasks rather than AppArmor.

## Pitfalls
- **Secrets in cloud-init user-data** — exposed via metadata service and logs. Use hashed values /
  secrets manager.
- **Non-idempotent shell steps** (`echo >>` that appends every run) — use `blockinfile`/drop-ins.
- **Applying a hardening role to production without `--check`/staging** — can break running services
  in one pass (see `05`).
- **Committing Vault-unencrypted secrets** — rotate immediately; scan history.
- **`NOPASSWD:ALL` from the cloud-init example left in place** — tighten it post-provision.
- **Drift** — hand-edits on top of IaC-managed config get overwritten or cause confusion; make changes
  in the IaC, not on the box.

## Verify
```bash
cloud-init status --long                         # provisioning completed cleanly
ansible-playbook site.yml --check --diff         # no unexpected changes on a converged host (idempotent)
ansible all -m command -a 'lynis audit system --quick' -b   # score across the fleet
git secrets --scan 2>/dev/null || true            # no secrets committed
```

## How managed services handle it
The panels are essentially hosted IaC engines: you declare "a WordPress site with these settings" and
they idempotently render Nginx/PHP-FPM/DB/TLS/firewall config, storing the desired state server-side
and re-applying it consistently. SpinupWP explicitly drives everything over SSH with no on-server
agent — the same agentless model as Ansible. The takeaway for an autonomous agent building its own
automation: adopt the panels' discipline (declare desired state, apply idempotently, keep secrets out
of the templates, rebuild from clean definitions) using open tools — cloud-init + Ansible +
`devsec.hardening` + Packer — so the whole server lifecycle is reproducible and reversible.
