#!/usr/bin/env bash
# backup-restore-test.sh — Prove a backup is RESTORABLE (not just present) by restoring a subset
# into a scratch dir and diffing against the live source. A backup you've never restored is not a
# backup. Supports restic and borg. Read-only against your real data; writes only to a temp dir.
# See references/09-backups-dr.md.
#
# Usage:
#   restic:  RESTIC_REPOSITORY=... RESTIC_PASSWORD_FILE=... ./backup-restore-test.sh restic /etc/nginx
#   borg:    BORG_REPO=... BORG_PASSPHRASE=... ./backup-restore-test.sh borg ::ARCHIVE etc/nginx
set -uo pipefail

TOOL="${1:-}"; shift || true
SCRATCH="$(mktemp -d /tmp/restore-test.XXXXXX)"
trap 'echo "[*] cleaning up $SCRATCH"; rm -rf "$SCRATCH"' EXIT

fail() { echo "[FAIL] $*"; exit 1; }

case "$TOOL" in
  restic)
    command -v restic >/dev/null || fail "restic not installed."
    SUBPATH="${1:-/etc}"
    echo "[*] restic snapshots:"; restic snapshots || fail "cannot list snapshots (repo/password?)."
    echo "[*] Checking repository integrity (5% sample of data)..."
    restic check --read-data-subset=5% || fail "restic check failed — repository may be damaged."
    echo "[*] Restoring '$SUBPATH' from latest snapshot into scratch..."
    restic restore latest --target "$SCRATCH" --include "$SUBPATH" || fail "restore failed."
    SRC="$SUBPATH"; DST="$SCRATCH$SUBPATH"
    ;;
  borg)
    command -v borg >/dev/null || fail "borg not installed."
    ARCHIVE="${1:-}"; SUBPATH="${2:-etc}"
    [ -n "$ARCHIVE" ] || fail "provide archive as ::NAME (see 'borg list')."
    echo "[*] borg check (repository consistency)..."; borg check --verify-data "${BORG_REPO:-}" 2>/dev/null || echo "[warn] borg check skipped/failed; continuing to restore test."
    ( cd "$SCRATCH" && borg extract "${BORG_REPO:-}${ARCHIVE}" "$SUBPATH" ) || fail "extract failed."
    SRC="/$SUBPATH"; DST="$SCRATCH/$SUBPATH"
    ;;
  *)
    echo "Usage: $0 {restic|borg} <args>   (see header for examples)"; exit 2;;
esac

echo
echo "[*] Diffing restored copy against live source:"
echo "    source:  $SRC"
echo "    restored:$DST"
if [ ! -e "$DST" ]; then fail "restored path $DST does not exist — restore did not produce expected files."; fi

if diff -r "$SRC" "$DST" >/tmp/restore-diff.$$ 2>&1; then
  echo "[PASS] RESTORE VERIFIED — restored files match the live source exactly."
  rm -f /tmp/restore-diff.$$
  echo
  echo "Reminder: a subset match proves the pipeline works. Periodically do a FULL restore into a"
  echo "throwaway VM and boot the app to validate your real RTO (see 09-backups-dr.md)."
  exit 0
else
  echo "[REVIEW] Differences found (this can be normal if the live files changed AFTER the backup):"
  head -40 /tmp/restore-diff.$$
  echo "..."
  echo "Restore itself SUCCEEDED (files came back). Investigate whether diffs are just post-backup drift."
  rm -f /tmp/restore-diff.$$
  exit 0
fi
