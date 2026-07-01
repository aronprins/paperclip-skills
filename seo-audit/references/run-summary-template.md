# Recurrence notation and run summary template

Two concrete formats that `SKILL.md` refers to but doesn't spell out in full: how to mark a ticket as aging/recurring when the same `check_id` + URL shows up again, and the exact shape of the end-of-run summary.

## Recurrence notation (on an existing ticket, when de-dupe finds a match)

When your de-dupe search (`ticket-template.md`) finds an existing open ticket for the same `Check-ID` + URL, add a comment to it in this form rather than opening a duplicate:

```markdown
**Recurrence update — <date>:** still present as of this run (seen in <N> consecutive runs).
```

Then update the ticket body's `**Severity:**` line to record the bump and why, e.g.:

```markdown
**Severity:** P1 (bumped from P2 — unresolved across 3 consecutive runs)
```

Bump exactly one tier (P2→P1, P1→P0) the first time a finding crosses three consecutive runs unresolved. Don't bump further on every subsequent run past that — three runs is the signal that this has stalled; re-bumping every month after that just inflates severity without adding new information. If it's still unresolved five or six runs later, that's a conversation for the run summary's staleness callout, not another severity bump.

## Run summary template

Post this as a single comment (or the equivalent durable note) at the end of every run:

```markdown
## SEO Audit Run Summary — <date>

**Routing map:**
- Technical → <agent, or "unassigned — no match">
- Content → <agent, or "unassigned — no match">
(note anything that changed since last run)

**Crawl coverage:** <N> URLs crawled <<note any partial-coverage caveats — auth-walled sections, rate-limited, etc.>>

**Findings this run:** P0: <n> · P1: <n> · P2: <n>

**New tickets opened:** <N>
- [<ticket link>] <title>
- ...

**De-duped (already open, no new ticket):** <N>
- <N> unchanged · <N> severity-bumped for aging (list which)

**Regressions (previously-closed finding reappeared):** <N>
- <ticket link> — regression of <prior ticket link>

**Routing gaps:** <trade>: <N> findings, no matching agent — routed to <fallback> / left unassigned
(one line per affected trade, not one line per finding)

**Review gate:** <N> high-risk findings this run
- <ticket link> — status: <awaiting fix / awaiting peer review / awaiting human approval / approved>

**Skipped checks:** <any check_ids skipped this run and why — e.g. performance checks skipped for a template with no representative URL to sample>

**Cost:** $<amount> of $<budget cap, if configured> — <"under budget" / "truncated N remaining findings into a rollup, see below">

**Anything else worth flagging:** <e.g. a check that's been clean for 3+ runs straight, a newly available agent that closed a previous routing gap>
```

Keep every section even when it's empty ("Regressions: none this run") — a reader scanning several months of these should see the same shape every time, so a genuinely new problem (the first-ever regression, the first-ever routing gap) stands out instead of blending into inconsistent formatting.
