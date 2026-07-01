# 01 — Provisioning a New VPS

Turning a freshly created, root-accessible box into a secure, updated, standard baseline. Do this
**before** installing any application. Order matters: create and verify your own access *before* you
remove root's, or you can lock yourself out.

## Why

Default images optimize for "it boots and you can log in," not security. NIST SP 800-123 (*Guide to
General Server Security*) frames the foundational task plainly: manufacturers set defaults to
emphasize features and ease of use at the expense of security, so the administrator must plan the
server's role, secure the OS, remove unnecessary services, and establish secure administration.
Everything in this file is that first pass.

## How (Ubuntu/Debian primary)

Work top to bottom. Each block is safe to re-run.

### 1. Update the system first
```bash
export DEBIAN_FRONTEND=noninteractive
apt update && apt -y upgrade
# If the kernel or libc was upgraded, plan a reboot at a safe time:
[ -f /var/run/reboot-required ] && echo "Reboot required"
```

### 2. Create a non-root administrative user
Never operate day-to-day as root. Create a user and grant sudo via group membership.
```bash
adduser --gecos "" deploy            # prompts for a password; set a strong one
usermod -aG sudo deploy              # RHEL family: usermod -aG wheel deploy
```

### 3. Give that user your SSH key and confirm sudo — BEFORE touching sshd
```bash
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
# Copy the key you used for root, or paste the intended public key:
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys 2>/dev/null || true
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
```
**Now open a second terminal, log in as `deploy`, and run `sudo whoami` (expect `root`).** Do not
proceed to disable root login (see `02-ssh-hardening.md`) until this succeeds. This is the single
most important gate in provisioning.

### 4. Hostname, timezone, locale
```bash
hostnamectl set-hostname web01.example.com
timedatectl set-timezone UTC          # UTC on servers keeps logs sane across regions
# Locale (Debian/Ubuntu):
localectl set-locale LANG=en_US.UTF-8
```
Add a matching line to `/etc/hosts` (`127.0.1.1 web01.example.com web01`) so `sudo` and mail tools
resolve the hostname without delay.

### 5. Swap (many cloud images ship with none)
No swap means the kernel OOM-kills processes under memory pressure instead of paging. A modest
swapfile is cheap insurance for small VPSes.
```bash
if ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
findmnt --verify --verbose            # sanity-check /etc/fstab before you ever reboot
sysctl -w vm.swappiness=10            # persist in /etc/sysctl.d/ — prefer RAM, use swap as a safety net
```
Skip swap only where the workload explicitly forbids it (some database vendors) or the provider
disallows swapfiles on their storage.

### 6. Essential base packages
```bash
apt -y install \
  unattended-upgrades apt-listchanges \   # automatic security updates (see 06)
  ufw \                                    # firewall front-end (see 03)
  fail2ban \                               # brute-force mitigation (see 02/10)
  auditd audispd-plugins \                 # auditing (see 05/12)
  chrony \                                 # accurate time (security + logs depend on it)
  curl wget git rsync ca-certificates gnupg lsb-release \
  htop ncdu       # human troubleshooting comfort
```

### 7. Baseline sysctl (network + process hygiene)
Full detail is in `05-system-hardening.md`; the minimal provisioning baseline:
```bash
cat >/etc/sysctl.d/60-baseline.conf <<'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
kernel.randomize_va_space = 2
EOF
sysctl --system
```

## RHEL family differences (Alma / Rocky / RHEL)
- `dnf -y upgrade` instead of `apt`; add extras with `dnf install epel-release`.
- Admin group is `wheel`, not `sudo`.
- Automatic updates come from `dnf-automatic`, not `unattended-upgrades` (see `06`).
- Firewall front-end is `firewalld` (see `03`).
- `chrony` is typically preinstalled; SELinux is enforcing by default — keep it that way.

## Pitfalls
- **Disabling root SSH before verifying the new user's key + sudo.** The classic lockout. Gate on
  step 3's second-session test.
- **`fallocate` swapfiles on some filesystems (older Btrfs/ZFS) are unsupported or unsafe.** Fall
  back to `dd`, or use a swap partition.
- **A typo in `/etc/fstab`** can make the box fail to boot. Always run `findmnt --verify` after
  editing it.
- **Skipping the reboot after a kernel upgrade** leaves you running the old, possibly-vulnerable
  kernel in memory even though the new one is installed.

## Verify
```bash
id deploy && groups deploy                     # deploy is in sudo/wheel
sudo -u deploy sudo -n whoami                   # -> root (sudo works)
swapon --show && free -h                        # swap active
timedatectl && hostnamectl                      # tz/hostname correct
apt list --upgradable 2>/dev/null | head        # nothing critical pending
```

## How managed services handle it
The panels reduce this to "spin up a clean supported OS, then paste one command." SpinupWP connects
purely over SSH (no on-server control panel) and recommends a minimum of 2 GB RAM for a WordPress
stack; notably it does **not** configure swap and explicitly suggests the operator add it to mitigate
out-of-memory errors — which is exactly why step 5 exists. Forge, Ploi, RunCloud, and GridPane all
follow the same "provision a supported Ubuntu LTS, then run the provisioning script" model, and all
create a dedicated non-root user with sudo as their first act — the direct analog of steps 2–3.
