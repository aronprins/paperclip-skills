# Agent routing reference

Full detail behind `SKILL.md` Section 4. Read this once when you set up the routine for a new company, and re-check it any time the roster might have changed. The short version lives inline in `SKILL.md`; this file is the complete keyword table, the tie-break order, and the fallback chain, spelled out so routing decisions are reproducible rather than improvised per finding.

## The two trades

Every `check_id` in `check-ids.md` maps to exactly one of two trades — both fully coverable from what the crawl itself observes, with no dependency on data this skill can't gather by fetching pages:

- **Technical** — anything requiring a code, server, template, or config change: indexability, link health, structured data, performance.
- **Content** — anything requiring an editorial/copy change: titles, meta descriptions, headings, alt text, thin/duplicate content, orphan pages (by default).

## Step 1 — List the roster

Pull every agent in the company (or, at minimum, every agent attached to the project this audit is scoped to), along with:

- their title/role string
- their reporting line (who they report to), if visible
- how many issues are currently open and assigned to them, if visible

Do this once at the start of the run. Do not re-fetch per finding — the whole point of resolving a routing map up front is that every finding in the same run gets routed consistently and cheaply.

## Step 2 — Score every agent against every trade

For each agent, check their title/role text (case-insensitive substring match) against these keyword groups. Count how many keywords match; an agent's score for a trade is that count.

| Trade | Matching keywords |
|---|---|
| Technical | `engineer`, `developer`, `dev`, `swe`, `software`, `technical`, `tech lead`, `web`, `backend`, `frontend`, `full stack`, `fullstack`, `devops`, `site reliability`, `sre`, `webmaster`, `architect`, `platform`, `cto` |
| Content | `content`, `editor`, `copywriter`, `writer`, `editorial`, `blogger`, `marketing` *(generalist fallback — see note below)*, `seo`, `cmo` |

Notes on the keyword groups:

- `marketing` alone is a weak, generic signal — it will often match a "Marketing Manager" or "CMO" title that isn't a dedicated content specialist. Treat a `marketing`-only match as a lower-confidence Content candidate than an explicit `content`/`editor`/`writer` match, and prefer the explicit match when both exist.
- An agent can score on both trades if their title genuinely spans both (e.g. "Technical Content Lead," rare but not impossible) — that's fine, it just means they're a candidate for either.
- These keyword lists are a starting point, not a closed set. If a company uses an unusual title that clearly maps to a trade, use judgment rather than refusing to match because the exact string isn't listed.

## Step 3 — Resolve ties

If more than one agent has the top score for a trade, break the tie in this order:

1. **Reporting-line fit.** Prefer the agent whose reporting chain matches the trade's natural functional owner — Technical candidates who report (directly or through their chain) to a CTO/engineering-lead-type role outrank those who don't; Content candidates who report to a CMO/marketing-lead-type role outrank those who don't.
2. **Current load.** If you can see open-issue counts, prefer whichever tied candidate currently has fewer issues assigned — this spreads work rather than concentrating it on whoever happened to be listed first.
3. **Deterministic fallback.** If neither of the above breaks the tie, pick the same way every time — e.g. the agent that was created earliest, or alphabetically first by name — so that re-running the routing resolution twice on an unchanged roster always produces the same answer. A routing map that flips between two equally-plausible agents from run to run is confusing and makes the run summary's "what changed since last time" note meaningless.

## Step 4 — Handle a trade with zero matches

This can happen on very small teams, most often when there's a single generalist agent covering everything and their title doesn't happen to match either keyword group cleanly. Work down this list and stop at the first option that applies:

1. **Functional manager.** If a manager for that function exists (a CTO for Technical; a CMO for Content), route to them. A manager can triage, redelegate, or do the fix themselves even without holding the specialist title.
2. **The auditor's own reporting chain.** If no functional manager exists either, route to whoever the auditor itself reports to.
3. **Unassigned, clearly labeled.** If neither of the above exists, leave the ticket unassigned. Do not leave this implicit — put the missing role directly in the ticket per `ticket-template.md`'s `Needs:` field (e.g. `Needs: Web Engineer`), so a human scanning the board immediately sees what kind of hire or reassignment would unblock it.
4. **Roll up, don't spam.** However many findings hit this fallback in a single run, they get exactly one line in that run's summary per missing trade (e.g. "3 findings need a Web Engineer, none exists yet") — never one escalation comment per individual finding. A human should learn about a routing gap once per run, clearly, not get buried in repetition.

## Step 5 — Don't cache across runs

Re-run Steps 1–4 fresh at the start of every audit run. Rosters change — a company might hire a Web Engineer next month, or an existing agent's title might get updated. If the resolved routing map differs from the previous run (a trade that was previously unmatched now has a candidate, or vice versa), say so plainly in the run summary — that's exactly the kind of change a human wants surfaced without having to diff two runs themselves.

## Worked example

Roster: `Priya` — title "Senior Web Engineer", reports to `Alex` (title "CTO"). `Sam` — title "Content & SEO Lead", reports to `Jordan` (title "CMO").

- Technical → `Priya` (score 2 on "engineer"+"web"; only candidate).
- Content → `Sam` (score 2 on "content"+"seo"; only candidate).

No routing gaps this run — both trades resolved to a named agent.
