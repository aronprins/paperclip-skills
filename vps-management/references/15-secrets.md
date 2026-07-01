# 15 — Secrets & Credential Resolution

This file tells the agent **how to obtain the credentials a server task needs** — SSH keys, provider
API tokens, backup passphrases, database passwords — without hardcoding them and without inventing
values. It complements `AGENTS.md` §7 (the principle: never hardcode, escrow off-box, rotate). This
file is the *mechanism*.

The rule in one line: **resolve every secret from your environment; if a required one is missing,
stop and report exactly which secret to provide — never prompt for a plaintext value to paste, and
never hardcode.**

## The model: secrets are pushed to you as environment variables

When you run inside an orchestrator (Paperclip is the primary target here), secrets are **not fetched
at runtime**. There is no "get secret value" call. Instead, an operator **binds** a stored secret to
your agent's environment, and the platform **resolves and injects the plaintext as an environment
variable** into your process immediately before the run.

So from your side, obtaining a secret is just **reading an environment variable**:

```bash
: "${RESTIC_PASSWORD:?}"   # present → use it; unset → missing binding (see the protocol below)
```

The presence or absence of the expected variable *is* the signal of whether the secret is configured.
Creating a secret in the platform does **not** create the variable — the operator must also *bind* it
to your agent's env. Your job is to read it, and to report clearly when it isn't there.

## Detect your runtime first

Branch on whether you're running under Paperclip. This decides how you report a missing secret.

```bash
if [ -n "${PAPERCLIP_COMPANY_ID:-}" ] && [ -n "${PAPERCLIP_API_URL:-}" ]; then
  RUNTIME=paperclip        # secrets arrive via secret_ref bindings; report in Paperclip's terms
else
  RUNTIME=standalone       # no orchestrator; fall back to asking the human over a secure channel
fi
```

Paperclip auto-injects `PAPERCLIP_AGENT_ID`, `PAPERCLIP_COMPANY_ID`, `PAPERCLIP_API_URL`,
`PAPERCLIP_RUN_ID`, and (for local adapters) a short-lived `PAPERCLIP_API_KEY`. Their presence means
you can also *diagnose* missing secrets against the platform (below).

## The secret/credential contract (env-var interface)

These are the environment variables this skill reads. Names use `_TOKEN` / `_SECRET` / `_API_KEY`
suffixes where possible so Paperclip **strict mode** forces them to be secret references rather than
inline plaintext. Tool-mandated names (e.g. `RESTIC_PASSWORD`) keep the tool's spelling and are bound
as secrets manually. Host/user/port are ordinary configuration, not secrets.

| Purpose | Reference | Env key(s) | Secret? |
|---|---|---|---|
| SSH connect — private key | all | `VPS_SSH_PRIVATE_KEY` (PEM contents) | 🔑 |
| SSH connect — host / user / port | all | `VPS_SSH_HOST`, `VPS_SSH_USER`, `VPS_SSH_PORT` | config |
| SSH host-key pin (avoid TOFU) | `02` | `VPS_SSH_KNOWN_HOSTS` | config |
| sudo password (only if not `NOPASSWD`) | `01`,`04` | `VPS_SUDO_PASSWORD` | 🔑 |
| Cloud provider API (provision / snapshot / firewall) | `01`,`09`,`14` | provider-specific: `DO_API_TOKEN`, `HCLOUD_TOKEN`, or `AWS_ACCESS_KEY_ID`+`AWS_SECRET_ACCESS_KEY` | 🔑 |
| Backup repo passphrase | `09` | `RESTIC_PASSWORD` / `BORG_PASSPHRASE` | 🔑 |
| Backup object-store credentials | `09` | `AWS_ACCESS_KEY_ID`+`AWS_SECRET_ACCESS_KEY` or `B2_ACCOUNT_ID`+`B2_ACCOUNT_KEY` | 🔑 |
| Ubuntu Pro / livepatch token | `06` | `UBUNTU_PRO_TOKEN` | 🔑 |
| CrowdSec enrollment key | `10` | `CROWDSEC_ENROLL_KEY` | 🔑 |
| ACME DNS-01 provider (wildcard TLS) | `07` | provider-specific, e.g. `CF_API_TOKEN` | 🔑 |
| Database root/app password to set | `07` | `DB_ROOT_PASSWORD` (+ app-specific) | 🔑 |
| Alerting / SMTP / dashboards | `08` | `ALERT_WEBHOOK_URL`, `SMTP_PASSWORD`, `GRAFANA_ADMIN_PASSWORD` | 🔑 |
| Ansible Vault password (IaC) | `14` | `ANSIBLE_VAULT_PASSWORD` | 🔑 |

This table is the skill's public "secrets interface." Read only the variables the current task needs —
don't demand the whole list up front.

## The resolve-or-report protocol

Run this at the **point of need**, for each secret a step requires:

1. **Read the variable.** If set and non-empty, use it (see *Handling* below). Done.
2. **If unset/empty and `RUNTIME=paperclip`, diagnose** whether the secret exists but isn't bound to
   you, versus doesn't exist at all — this changes the fix:

   ```bash
   curl -sS "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/secrets" \
     -H "Authorization: Bearer $PAPERCLIP_API_KEY"
   # Returns secret metadata (names/keys) ONLY — never values. Look for a matching name.
   ```

   - **Name present** → the secret exists but isn't bound to your agent's env. Report: *bind it.*
   - **Name absent** → the secret doesn't exist yet. Report: *create it, then bind it.*
3. **Stop the step and report** using the format below. Do **not** ask the human to paste a plaintext
   value into the chat, do **not** hardcode a placeholder, and do **not** continue past the step.
4. **If `RUNTIME=standalone`**, fall back to `AGENTS.md` §7: ask the human to provide the secret over a
   secure channel (or place it in an access-restricted file / their own secrets manager), never in
   chat history or on a command line.

### Missing-secret report format (Paperclip)

> ⚠️ **Missing secret — cannot proceed with this step.**
> **Step:** restic backup (`references/09-backups-dr.md`).
> **Needs:** repository passphrase in env var **`RESTIC_PASSWORD`** — currently unset.
> **Status:** *(from the metadata check)* secret exists but is not bound to me / does not exist yet.
> **To provide it:** Company Settings → Secrets → create or select the secret → bind it to **this
> agent's Environment variables** with key `RESTIC_PASSWORD` (source: *Secret*, version `latest`).
> Then re-run. I will not continue until it is bound.

Name the env key, the reference that needs it, and the exact bind steps every time. If several secrets
are missing for one workflow, list them together so the operator fixes them in one pass.

## Handling secrets once you have them

Custody ends at injection — once a value is in your process env, you own not leaking it further.

- **Never put a secret on a command line** (it lands in `ps`, shell history, and logs). Pass via
  stdin, an env var the tool reads, or a `0600` file you create and delete.
- **SSH private key:** write it to a mode-`0600` temp file and point `ssh -i` at it, or `ssh-add` it
  into an agent; shred the file afterward.

  ```bash
  umask 077; keyfile="$(mktemp)"; printf '%s\n' "$VPS_SSH_PRIVATE_KEY" > "$keyfile"
  ssh -i "$keyfile" -o IdentitiesOnly=yes "$VPS_SSH_USER@$VPS_SSH_HOST"
  # ... then: shred -u "$keyfile"  (or rm -f)
  ```
- **Getting a secret onto the remote box:** don't echo it into a remote command line. Prefer piping
  over stdin (`ssh host 'restic ...' <<<"$RESTIC_PASSWORD"` via `RESTIC_PASSWORD_FILE`), or write a
  `0600` file on the remote and reference it. Remember cloud-init user-data is world-readable via the
  metadata service — never bake secrets into it (`14-automation-iac.md`).
- **Don't print it.** Keep it out of your own transcript, comments, and any file you commit. A secret
  captured in a run transcript should be treated as exposed and rotated.

## Naming & strict mode

- Prefer env keys ending in `_API_KEY`, `_TOKEN`, or `_SECRET` for anything sensitive — Paperclip's
  strict mode *requires* those to be secret references, so an operator can't accidentally inline them.
- Tool-fixed names (`RESTIC_PASSWORD`, `BORG_PASSPHRASE`, `AWS_SECRET_ACCESS_KEY`) can't be renamed;
  bind them as secrets deliberately even though the suffix doesn't trigger strict mode.
- Host, user, port, region, and bucket names are **not** secrets — pass them as plain env/config, and
  don't burn a secret binding on them.

## Standalone fallback (no orchestrator)

Outside Paperclip the skill stays generic. With no injected env:
- Ask the human to export the needed variable in your session, or point you at a file/secrets manager
  they control — over a secure channel, never pasted into shared history.
- The generic tools in `14-automation-iac.md` §4 (Ansible Vault, HashiCorp Vault, SOPS + age, cloud
  KMS) are the off-platform equivalents of the bind-and-inject flow above.

## Pitfalls

- **Treating "secret created" as "secret available."** Creation ≠ binding. If the env var is unset, the
  operator still has to bind it to *your* agent — say so.
- **Trying to fetch a value from the API.** The secrets API returns metadata only; there is no value
  endpoint. Read the env var; use the API just to check existence.
- **Continuing past a missing secret** with a guessed default or an empty string — this silently
  produces a broken or insecure result (e.g. an unencrypted backup). Stop and report instead.
- **Leaking via argv/history** — the classic. Use stdin / env / `0600` files.
- **Ignoring strict mode** — inlining a `*_API_KEY` value will be rejected in configured deployments;
  bind it as a secret.

## Verify

```bash
# Which required vars are set for the task at hand (values redacted):
for v in VPS_SSH_PRIVATE_KEY VPS_SSH_HOST VPS_SSH_USER; do
  [ -n "${!v:-}" ] && echo "$v: set" || echo "$v: MISSING"
done
# Under Paperclip, list secret names available to the company (never values):
[ -n "${PAPERCLIP_COMPANY_ID:-}" ] && curl -sS \
  "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/secrets" \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" | head
```

## How managed services handle it

The panels (Forge, Ploi, RunCloud, GridPane, SpinupWP) never ask you to hardcode credentials into a
server: you store provider API tokens, database passwords, and deploy keys in the panel, and the panel
injects them into the provisioning run at execution time. Paperclip's bind-and-inject model is the
same discipline — the secret lives in the control plane, is resolved server-side, and reaches the
workload only as a runtime environment variable, with an audit event per resolution.
