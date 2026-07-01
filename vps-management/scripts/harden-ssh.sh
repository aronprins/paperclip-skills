#!/usr/bin/env bash
# harden-ssh.sh — Apply a safe SSH hardening baseline via a drop-in, validate, and reload
# WITHOUT dropping your current session. Then it prints the exact second-session test you MUST
# run before trusting the change. See references/02-ssh-hardening.md and AGENTS.md §4.
#
# Usage:  sudo ./harden-ssh.sh --user <login> [--port 22] [--dry-run]
# Safety: does NOT disable password auth unless it can see an authorized_keys for --user.
set -euo pipefail

USER_ALLOW=""; PORT="22"; DRYRUN=0
while [ $# -gt 0 ]; do case "$1" in
  --user) USER_ALLOW="${2:-}"; shift 2;;
  --port) PORT="${2:-22}"; shift 2;;
  --dry-run) DRYRUN=1; shift;;
  *) echo "unknown arg: $1"; exit 2;;
esac; done

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)."; exit 1; }
[ -n "$USER_ALLOW" ] || { echo "Provide --user <login> (the account that must keep access)."; exit 2; }
id "$USER_ALLOW" >/dev/null 2>&1 || { echo "User '$USER_ALLOW' does not exist. Create it first (see 01-provisioning)."; exit 1; }

# Verify a key exists for the user BEFORE we consider disabling passwords (anti-lockout).
KEYFILE="$(getent passwd "$USER_ALLOW" | cut -d: -f6)/.ssh/authorized_keys"
HAVE_KEY=0
if [ -s "$KEYFILE" ]; then HAVE_KEY=1; echo "[ok] Found authorized_keys for $USER_ALLOW: $KEYFILE"; else
  echo "[WARN] No authorized_keys for $USER_ALLOW at $KEYFILE."
  echo "       Password auth will be LEFT ENABLED to avoid locking you out. Add a key, then re-run."
fi

DROPIN_DIR="/etc/ssh/sshd_config.d"
mkdir -p "$DROPIN_DIR"
TARGET="$DROPIN_DIR/00-hardening.conf"
TMP="$(mktemp)"

{
  echo "# Managed by vps-management/harden-ssh.sh on $(date -u +%FT%TZ)"
  echo "PermitRootLogin no"
  echo "PubkeyAuthentication yes"
  echo "KbdInteractiveAuthentication no"
  echo "MaxAuthTries 3"
  echo "MaxSessions 5"
  echo "LoginGraceTime 30"
  echo "X11Forwarding no"
  echo "AllowAgentForwarding no"
  echo "PermitEmptyPasswords no"
  echo "PermitUserEnvironment no"
  echo "LogLevel VERBOSE"
  echo "ClientAliveInterval 300"
  echo "ClientAliveCountMax 2"
  echo "AllowUsers $USER_ALLOW"
  [ "$PORT" != "22" ] && echo "Port $PORT"
  if [ "$HAVE_KEY" -eq 1 ]; then echo "PasswordAuthentication no"; else echo "PasswordAuthentication yes  # left on: no key found for $USER_ALLOW"; fi
} > "$TMP"

echo; echo "----- proposed $TARGET -----"; cat "$TMP"; echo "----------------------------"

if [ "$PORT" != "22" ]; then
  echo "[!] You set --port $PORT. OPEN THAT PORT IN THE FIREWALL FIRST (see 03-firewall-network.md),"
  echo "    or you will be unable to reconnect."
fi

if [ "$DRYRUN" -eq 1 ]; then echo "[dry-run] Not writing. Remove --dry-run to apply."; rm -f "$TMP"; exit 0; fi

# Back up any existing drop-in, then install and validate.
[ -f "$TARGET" ] && cp -a "$TARGET" "$TARGET.bak.$(date +%Y%m%d-%H%M%S)"
install -m 0644 "$TMP" "$TARGET"; rm -f "$TMP"

echo "[*] Validating with 'sshd -t' ..."
if ! sshd -t; then
  echo "[FAIL] sshd -t rejected the config. Reverting drop-in; NOT reloading."
  rm -f "$TARGET"
  exit 1
fi
echo "[ok] sshd -t passed."

echo "[*] Reloading sshd (reload keeps your current session alive) ..."
systemctl reload ssh 2>/dev/null || systemctl reload sshd

echo
echo "=================  DO NOT CLOSE THIS SESSION YET  ================="
echo "Open a SECOND terminal and confirm you can log in with the new settings:"
if [ "$PORT" != "22" ]; then
  echo "    ssh -p $PORT $USER_ALLOW@<this-host>"
else
  echo "    ssh $USER_ALLOW@<this-host>"
fi
if [ "$HAVE_KEY" -eq 1 ]; then
  echo "Password auth is DISABLED — the second login must succeed via your KEY."
fi
echo "Only after that second login works should you trust this change and release this session."
echo "Rollback if needed:  rm $TARGET ; systemctl reload ssh"
echo "=================================================================="
