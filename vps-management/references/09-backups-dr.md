# 09 — Backups & Disaster Recovery

A backup that has never been restored is not a backup — it's hope. This file covers the 3-2-1 rule,
tool choice (restic vs borg), offsite/object storage, database-consistent dumps, encryption, and —
most importantly — **restore testing**.

## Why

The 3-2-1 rule is the industry baseline: **3** copies of the data, on **2** different media/systems,
with **1** copy offsite. Provider snapshots alone fail this — they live on the same infrastructure, so
an account compromise, region failure, or ransomware event can take the primary *and* the snapshot.
RPO (how much data you can afford to lose) and RTO (how fast you must be back) drive frequency and
architecture.

## How

### 1. Choose a tool
Both dedupe and encrypt client-side; both are single binaries; both are excellent. Pick by target:
- **restic** — default recommendation for **cloud/object storage**. Native S3, Backblaze B2, Azure,
  GCS, plus SFTP; AES-256 client-side encryption; simple key handling; fast restores. One static Go
  binary.
- **BorgBackup** — best when **SSH targets and compression** dominate (better zstd ratios, lighter
  RAM — good on tiny VPSes). Repos are SSH/local; pair with `rclone` to push to object storage, or use
  a Borg-native remote (BorgBase/rsync.net).
- `rclone` (sync to 40+ cloud providers), `rsync` (simple file mirror), `duplicity` (older, GnuPG)
  remain useful for specific cases.

### 2. Set up restic to object storage (example: Backblaze B2 / S3)
```bash
apt -y install restic
export RESTIC_REPOSITORY="s3:s3.us-west-002.backblazeb2.com/mybucket/host01"
export RESTIC_PASSWORD_FILE="/root/.restic-pass"       # 0600; store the passphrase safely OFF-box too
# Provide AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY via an env file, not the command line.
restic init
restic backup /etc /home /srv /var/www \
  --exclude-caches --exclude /var/www/*/cache --tag daily
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune   # retention
```
**If you lose the restic/borg passphrase, the data is unrecoverable — by design.** Escrow it securely
(a secrets manager), never only on the server being backed up.

### 3. Back up databases *consistently* (dump before file backup)
File-copying live DB files can capture a torn, unrestorable state. Dump first:
```bash
# MySQL/MariaDB (single-transaction = consistent snapshot for InnoDB without locking):
mysqldump --single-transaction --routines --triggers --all-databases | zstd > /var/backups/mysql-$(date +%F).sql.zst
# PostgreSQL:
sudo -u postgres pg_dumpall | zstd > /var/backups/pg-$(date +%F).sql.zst
# Then let restic/borg pick up /var/backups. For large DBs use xtrabackup (physical, hot) instead.
```

### 4. Schedule (systemd timer preferred over cron for logging/retries)
```ini
# /etc/systemd/system/backup.service  (Type=oneshot, runs a wrapper script that dumps DBs then restic backup)
# /etc/systemd/system/backup.timer
[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=900
Persistent=true
```
`resticprofile` or `borgmatic` are excellent declarative wrappers (config file + retention + hooks).

### 5. Offsite + encryption
Push to a **different provider/region** than the server (server on Provider A → backups on B2/Wasabi/S3
elsewhere). restic/borg already encrypt client-side, so the object store never sees plaintext. Enable
object-lock / immutability on the bucket if available — it defends against an attacker with server
credentials deleting your backups (ransomware-resistant).

### 6. RESTORE TESTING — the step everyone skips
Schedule periodic restores into a scratch location and diff against source; better yet, restore into a
throwaway VM and boot the app.
```bash
restic restore latest --target /tmp/restore-test --include /etc/nginx
diff -r /etc/nginx /tmp/restore-test/etc/nginx && echo "RESTORE VERIFIED"
restic check --read-data-subset=5%      # verify repository integrity / detect bit-rot
```
`scripts/backup-restore-test.sh` automates a restore-and-diff. Put a calendar reminder (or a monthly
timer) on a full DB restore into staging — that's the only way to know your RTO is real.

## RHEL family differences
Tools are identical (restic/borg are distro-agnostic). `dnf install restic` (EPEL) or grab the
upstream binary. SELinux: if you restore files to non-default locations, run `restorecon -Rv <path>`
so contexts are correct, or the restored service may be denied access.

## Pitfalls
- **Snapshots treated as backups** — same infrastructure, no protection against account compromise or
  ransomware. Snapshots are a fast local tier, not the offsite copy.
- **Never test-restoring** — the #1 cause of "we had backups but couldn't recover."
- **Losing the encryption passphrase** — permanent, total data loss. Escrow it off-box.
- **File-copying a live database** → inconsistent, unrestorable dump. Always logical/hot dump first.
- **Backups reachable/deletable with the server's own credentials** — an attacker wipes them too. Use
  append-only/object-lock and separate credentials.
- **Backing up caches/temp** — bloats storage and time; exclude them.
- **No monitoring of backup success** — a job that's been failing silently for weeks. Alert on
  failure (see `08`).

## Verify
```bash
restic snapshots            # recent snapshots exist on schedule
restic check                # repository consistent
# Prove restorability (the real test):
bash scripts/backup-restore-test.sh
# Confirm the timer is active and last run succeeded:
systemctl list-timers backup.timer ; journalctl -u backup.service --since -2d | tail
```

## How managed services handle it
GridPane's V2 backup system (built on the Duplicacy engine, incremental + deduplicated) supports
offsite targets including **AWS S3, Backblaze B2, Wasabi, and Dropbox**, and its guidance recommends a
layered approach — local + provider snapshot + offsite — which is the 3-2-1 rule in practice.
SpinupWP, Forge, and Ploi provide scheduled backups (files + database) with offsite destinations
(S3/B2/DO Spaces) and configurable retention. The panels get the architecture right; where operators
still get burned is restore-testing, which the tools make easy but nobody schedules — hence step 6.
