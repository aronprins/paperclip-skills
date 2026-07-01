#!/usr/bin/env bash
# lynis-score.sh — Run a Lynis audit and extract the hardening index for before/after comparison.
# Installs Lynis if absent (with confirmation). Target >= 80 for production. See references/
# 05-system-hardening.md and 10-intrusion-detection.md.
#
# Usage:  sudo ./lynis-score.sh [--save <label>]   e.g. --save before  /  --save after
set -uo pipefail

LABEL=""
[ "${1:-}" = "--save" ] && LABEL="${2:-run}"

if ! command -v lynis >/dev/null 2>&1; then
  echo "[*] Lynis is not installed."
  if [ "$(id -u)" -ne 0 ]; then echo "Re-run with sudo to auto-install, or install lynis manually."; exit 1; fi
  if [ -r /etc/os-release ]; then . /etc/os-release; fi
  case "${ID_LIKE:-$ID}" in
    *debian*|debian|ubuntu) echo "[*] Installing via apt..."; apt-get update -qq && apt-get install -y lynis ;;
    *rhel*|*fedora*|rhel|centos|almalinux|rocky|fedora) echo "[*] Installing via dnf (needs EPEL)..."; dnf install -y epel-release 2>/dev/null; dnf install -y lynis ;;
    *) echo "Unknown distro — install Lynis manually (https://cisofy.com/lynis/)."; exit 1 ;;
  esac
fi

echo "[*] Running: lynis audit system --quick  (read-only assessment; makes no changes)"
# --quick skips the interactive pauses. Lynis writes details to /var/log/lynis.log and a report file.
if [ "$(id -u)" -eq 0 ]; then
  lynis audit system --quick --no-colors >/dev/null 2>&1 || true
else
  sudo lynis audit system --quick --no-colors >/dev/null 2>&1 || \
    { echo "[warn] running without root — some tests skipped, score will be less complete."; lynis audit system --quick --no-colors >/dev/null 2>&1 || true; }
fi

REPORT="/var/log/lynis-report.dat"
LOG="/var/log/lynis.log"
INDEX=""
[ -r "$REPORT" ] && INDEX="$(awk -F= '/hardening_index=/{print $2}' "$REPORT" | tail -1)"
[ -z "$INDEX" ] && [ -r "$LOG" ] && INDEX="$(grep -i 'Hardening index' "$LOG" | tail -1 | grep -oE '[0-9]+' | head -1)"

echo
if [ -n "$INDEX" ]; then
  echo "=================================================="
  echo " Lynis hardening index: $INDEX / 100"
  if   [ "$INDEX" -ge 80 ]; then echo " Status: PRODUCTION TARGET MET (>= 80)."
  elif [ "$INDEX" -ge 65 ]; then echo " Status: partially hardened — push toward >= 80 (see 05)."
  else echo " Status: LOW — likely near a fresh-install baseline. Apply 02/03/05/06 and re-run."
  fi
  echo "=================================================="
  if [ -n "$LABEL" ]; then
    mkdir -p /var/log/vps-management
    echo "$(date -u +%FT%TZ) $LABEL $INDEX" >> /var/log/vps-management/lynis-scores.tsv
    echo "[*] Saved as '$LABEL' in /var/log/vps-management/lynis-scores.tsv:"
    column -t /var/log/vps-management/lynis-scores.tsv 2>/dev/null || cat /var/log/vps-management/lynis-scores.tsv
  fi
else
  echo "[warn] Could not parse a hardening index. Inspect $LOG and $REPORT directly."
fi

echo
echo "Top suggestions (address highest-impact first):"
[ -r "$REPORT" ] && awk -F'|' '/^suggestion\[\]=/{sub(/^suggestion\[\]=/,""); print " - "$0}' "$REPORT" | head -15
echo
echo "Note: the index measures configuration conformance, not absolute security. A minimal server"
echo "scores higher partly by running less. Use it as a relative before/after signal (AGENTS.md §8)."
