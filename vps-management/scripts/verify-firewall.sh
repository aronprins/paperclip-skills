#!/usr/bin/env bash
# verify-firewall.sh — Confirm a default-deny inbound policy is in effect and report which ports
# are actually open, across ufw / firewalld / nftables. Read-only; makes NO changes.
# See references/03-firewall-network.md.
set -uo pipefail

echo "## Listening sockets (what the OS is actually serving)"
if command -v ss >/dev/null; then ss -tulnp 2>/dev/null | awk 'NR==1 || /LISTEN/'; fi
echo

found=0
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  found=1
  echo "## ufw is ACTIVE"
  ufw status verbose 2>/dev/null
  if ufw status verbose 2>/dev/null | grep -qi 'Default: deny (incoming)'; then
    echo "[ok] default-deny incoming is in effect."
  else
    echo "[WARN] incoming default is NOT deny — tighten with: ufw default deny incoming"
  fi
  ufw status 2>/dev/null | grep -qiE '22/tcp|OpenSSH' && echo "[ok] SSH rule present." || echo "[WARN] no SSH allow rule visible — do not disable current access."
fi

if command -v firewall-cmd >/dev/null && [ "$(firewall-cmd --state 2>/dev/null)" = "running" ]; then
  found=1
  echo "## firewalld is RUNNING"
  echo "default zone: $(firewall-cmd --get-default-zone 2>/dev/null)"
  firewall-cmd --list-all 2>/dev/null
  firewall-cmd --list-all 2>/dev/null | grep -qE 'services:.*\bssh\b' && echo "[ok] ssh service allowed." || echo "[WARN] ssh not in allowed services."
fi

if command -v nft >/dev/null && nft list ruleset 2>/dev/null | grep -q 'hook input'; then
  found=1
  echo "## nftables ruleset present"
  if nft list ruleset 2>/dev/null | grep -A2 'hook input' | grep -q 'policy drop'; then
    echo "[ok] input chain policy is drop (default-deny)."
  else
    echo "[WARN] input chain policy is not drop — verify default-deny."
  fi
  nft list ruleset 2>/dev/null | grep -qE 'dport (22|ssh)' && echo "[ok] SSH port allowed in nftables." || echo "[WARN] no explicit SSH allow seen in nftables."
fi

if [ "$found" -eq 0 ]; then
  echo "## NO ACTIVE HOST FIREWALL DETECTED (ufw inactive, firewalld not running, no nft input policy)."
  echo "[WARN] The host is relying on provider security groups only (if any). Consider enabling one —"
  echo "       but ALLOW SSH FIRST, then enable (see 03-firewall-network.md / AGENTS.md §4)."
fi

echo
echo "Cross-check: every LISTEN address above that is 0.0.0.0/[::] should be a port you INTEND to expose."
echo "Databases/caches (3306/5432/6379/11211) should listen on 127.0.0.1 only, not 0.0.0.0."
