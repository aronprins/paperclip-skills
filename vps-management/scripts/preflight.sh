#!/usr/bin/env bash
# preflight.sh — Orient before making any change. Read-only; makes NO modifications.
# Gathers the facts an agent needs (distro, role, users, listeners, services, panels)
# and prints a fresh-vs-production risk assessment. See references/agent-safety.md.
set -uo pipefail

line() { printf '%s\n' "----------------------------------------------------------------"; }
hdr()  { line; printf '## %s\n' "$1"; line; }

hdr "Identity & privilege"
echo "user: $(id -un)  uid: $(id -u)"
id
if sudo -n true 2>/dev/null; then echo "sudo: available (passwordless in this context)"; \
elif command -v sudo >/dev/null; then echo "sudo: present (will prompt for password)"; \
else echo "sudo: NOT present"; fi

hdr "Distro family (drives apt/dnf, ufw/firewalld, AppArmor/SELinux, sudo/wheel)"
if [ -r /etc/os-release ]; then . /etc/os-release; echo "ID=$ID  ID_LIKE=${ID_LIKE:-}  VERSION=${VERSION_ID:-}  PRETTY=${PRETTY_NAME:-}"; else echo "no /etc/os-release"; fi
case "${ID_LIKE:-$ID}" in
  *debian*|debian|ubuntu) echo "family: DEBIAN  -> apt, ufw, AppArmor, group 'sudo', /var/log/auth.log";;
  *rhel*|*fedora*|rhel|centos|almalinux|rocky|fedora) echo "family: RHEL  -> dnf, firewalld, SELinux, group 'wheel', /var/log/secure";;
  *) echo "family: UNKNOWN — verify commands manually";;
esac

hdr "Uptime, kernel, pending reboot"
uptime
echo "kernel: $(uname -r)"
[ -f /var/run/reboot-required ] && echo "REBOOT REQUIRED (kernel/libc updated)" || echo "no pending reboot flag"

hdr "Human login users (uid 1000-59999)"
getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1"  (uid "$3", shell "$7")"}'

hdr "Listening sockets (attack surface)"
if command -v ss >/dev/null; then ss -tulnp 2>/dev/null | awk 'NR==1 || /LISTEN/'; else netstat -tulnp 2>/dev/null; fi

hdr "Running services (top 40)"
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -40

hdr "Detected stacks / control panels"
for b in nginx apache2 httpd php-fpm mysql mariadb mysqld psql postgres docker containerd redis-server memcached; do
  command -v "$b" >/dev/null 2>&1 && echo "found: $b"
done
for p in /usr/local/rvm /opt/RunCloud /etc/gridpane /usr/local/cwp /usr/local/cpanel /usr/local/psa /opt/cyberpanel /www/server; do
  [ -e "$p" ] && echo "panel/marker: $p"
done

hdr "Security posture snapshot"
if command -v sshd >/dev/null; then
  echo "sshd effective (root/password/pubkey):"
  sshd -T 2>/dev/null | grep -Ei '^(permitrootlogin|passwordauthentication|pubkeyauthentication) ' || echo "  (could not read; need root)"
fi
if command -v ufw >/dev/null; then echo "ufw: $(ufw status 2>/dev/null | head -1)"; fi
if command -v firewall-cmd >/dev/null; then echo "firewalld: $(firewall-cmd --state 2>/dev/null)"; fi
if command -v getenforce >/dev/null; then echo "SELinux: $(getenforce 2>/dev/null)"; fi
if command -v aa-status >/dev/null; then echo "AppArmor: $(aa-status --enabled 2>/dev/null && echo enabled || echo 'check')"; fi

hdr "RISK ASSESSMENT"
listeners=$(ss -tulnp 2>/dev/null | grep -c LISTEN)
running=$(systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -c '\.service')
if [ "${listeners:-0}" -gt 3 ] || [ "${running:-0}" -gt 25 ]; then
  echo ">>> Treat as PRODUCTION: real services appear to be running."
  echo ">>> Change ONE reversible thing at a time, verify between steps, avoid one-shot hardening."
else
  echo ">>> Looks like a FRESH / lightly-used box: aggressive one-pass hardening is lower risk,"
  echo ">>> but still keep an SSH session open and back up before every change."
fi
echo
echo "Next: read AGENTS.md, then pick the workflow in SKILL.md. Nothing was modified by this script."
