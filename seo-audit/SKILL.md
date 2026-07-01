---
name: seo-audit
description: Run a recurring technical + on-page SEO audit inside Paperclip and turn every finding into a scored, owned, de-duplicated fix ticket — routed to whichever agent in the company actually covers that trade, with clear fallbacks when no matching specialist exists yet. Use this when a routine wakes an SEO auditor agent for its scheduled crawl, when setting up a new monthly/weekly SEO audit routine, or when asked to convert an SEO audit's findings into tracked, assigned work instead of a static report. Do not use this for one-off manual audits with no follow-through, and do not use it for the crawl-and-report-only use case — this skill's job starts where a plain audit report ends: turning findings into tickets the right people actually pick up.
---

# SEO Audit-to-Ticket

You are running one execution of a recurring SEO audit. Your job is not to write a report. Your job is to crawl the site, score what you find, and leave the company's Issues board with the right tickets, on the right people, evidence attached — while never re-filing the same problem twice and never letting a risky fix ship without a second set of eyes.

This skill assumes you already have working access to your company's Paperclip coordination surface — whatever lets you list agents, create and search issues, post comments, and (if configured) request an approval. This document tells you **what to do with those capabilities and how to decide**, not which specific calls to make — your existing Paperclip access already knows that part. If any capability mentioned below isn't available to you (e.g. you can't request approvals), fall back to the nearest equivalent (post a comment tagging a human) and note the gap in your run summary.

Read this whole document once before your first run. After that, you're applying the same rules every time — that consistency is the entire point of automating this.

## Files in this skill

- `SKILL.md` (this file) — the run procedure and the decisions you make every time.
- `references/check-ids.md` — the canonical checklist: every `check_id`, its exact detection criteria and thresholds, its default severity and trade, and the list of high-risk `check_id`s that must go through the review gate. This is the single source of truth the other files point back to.
- `references/agent-routing.md` — the full keyword-matching table, tie-break order, and fallback chain behind Section 4, plus a worked example.
- `references/ticket-template.md` — the exact title/body format for every ticket, including the `Check-ID:` line that makes de-duplication possible, and how to run the de-dupe search itself.
- `references/run-summary-template.md` — the recurrence/aging notation for tickets that keep coming back, and the exact end-of-run summary template.

Load the reference files as you reach the section that needs them — you don't need all four in front of you for every step.

---

## 1. What a run looks like, end to end

1. **Resolve your routing map** — find out who in the company can take technical fixes and who can take content fixes (Section 4). Do this once per run, not once per finding.
2. **Crawl and check** the site against the fixed checklist (Section 2).
3. **Score every finding** by severity (Section 3).
4. **De-dupe** against what's already open on the board (Section 5).
5. **Open one ticket per genuinely new finding**, assigned via your routing map, with evidence attached.
6. **Flag high-risk findings** for the review-gate treatment (Section 6) instead of a normal ticket.
7. **Respect your budget** (Section 7) — stop opening new tickets before you blow through it, and summarize what's left instead.
8. **Post a run summary** (Section 8) so a human can see what happened in one place without reading every ticket.

If you only do steps 2–3 and stop, you have produced exactly the kind of audit this skill exists to replace. Steps 4 through 8 are not optional cleanup — they are the reason this is a skill and not a report template.

---

## 2. The checklist

Run this identically every time. Consistency across runs is what makes month-over-month comparison possible — an agent that invents new checks each run cannot tell "regression" from "different lens."

The checks fall into five groups — indexability, link health, on-page, structured data, and Core Web Vitals performance. **The exact detection criteria, numeric thresholds, and stable `check_id` for every single check live in `references/check-ids.md` — that file is what you actually work from, not the summary below.** In short:

- **Indexability** — is anything that should rank actually blocked (robots.txt, meta robots, x-robots-tag), does every page have a correct canonical, does the sitemap match reality.
- **Link health** — internal 4xx/5xx, redirect chains and loops, orphan pages.
- **On-page** — titles, meta descriptions, headings, alt text, thin/duplicate content.
- **Structured data** — present, valid, and matching the page type where expected.
- **Performance** — LCP/INP/CLS against Google's published thresholds, checked per key template, not one sampled page total.

Crawl scope note: on a large site, crawl every URL if you can afford it; if not, sample every template type rather than the first N pages alphabetically — a thin sample that misses an entire template (e.g. every product page) is worse than no audit at all, because it reports a clean bill of health that isn't one.

**Cadence isn't fixed — it's a function of site size and change velocity.** A small, low-churn site is well served by monthly. A site pushing tens of thousands of pages through deploy, or publishing/updating content daily, needs weekly or near-continuous attention — issues compound faster than a monthly cadence can catch them, and by the time a monthly run finds a regression it may have been live for weeks. When you (or whoever configures your routine's trigger) pick a schedule, size it to the site, not to a calendar-convenience default. If you don't know the site's scale, ask, or default to monthly and say so explicitly in your first run summary so a human can tighten it if needed.

---

## 3. Severity rubric

Score every finding against the table in `references/check-ids.md` — it lists a default severity and trade for every `check_id`, and that file is the single source of truth (this document doesn't repeat it, so the two can't drift out of sync). Do not invent new severities and do not let a finding go unscored — an unscored finding cannot be routed or prioritized, which means it will not get fixed.

A finding's severity can be bumped by context even against the default table — e.g. a P1 redirect chain on the site's highest-traffic page deserves P0 treatment. Use judgment, but record *why* you deviated from the default in the ticket (the `**Severity:**` line format is in `references/ticket-template.md`), so the next run — and any human reading it — can tell a deliberate override from a scoring mistake.

---

## 4. Finding the right agent when you don't know the roster

This is the part a fixed template can't hand you, because every company running this skill has a different set of agents — some have a dedicated Web Engineer and Content Editor exactly like the article's example; many have one generalist; some have none yet. Do this resolution **once at the start of the run**, cache it, and reuse it for every finding in that run.

### Step 4a — List the company's agents

Pull the full agent roster for the company (or at minimum the project this audit is scoped to), including each agent's title/role and reporting line if available.

### Step 4b — Score each agent against each trade

Two trades come out of the checklist above: **Technical** and **Content**. For each agent, check their title/role text (case-insensitive) against the keyword groups in `references/agent-routing.md` and count matches — e.g. Technical keywords include `engineer`, `developer`, `web`, `backend`, `devops`; Content includes `content`, `editor`, `writer`, `seo`. That file has the complete list plus notes on weak/generic matches (e.g. why a bare `marketing` match is lower-confidence than an explicit `content`/`editor` match).

An agent can score on both trades if their title genuinely spans both — that's fine, it just means they're the candidate for both.

### Step 4c — Pick the best candidate per trade

For each trade, take the agent(s) with the highest keyword-match score. If more than one agent ties, break it in order: reporting-line fit (does their chain lead to the trade's natural functional owner), then current open-issue load (spread work rather than piling on whoever's listed first), then a deterministic fallback so the same tie always resolves the same way. Full detail and a worked example are in `references/agent-routing.md`.

### Step 4d — Handle the case where no agent matches a trade

This can happen on very small teams, most often when a single generalist agent covers everything and their title doesn't cleanly match either keyword group. In order of preference:

1. **Route to the functional manager** for that trade if one exists (the CTO for Technical, the CMO for Content) — a manager can triage or reassign even without doing the fix themselves.
2. **Route to the auditor's own manager or reporting chain** if no functional manager exists either.
3. **Leave the ticket unassigned**, tagged clearly with a `Needs:` line per `references/ticket-template.md`, naming exactly what specialist role is missing. Do not silently drop the finding — an unassigned, clearly-labeled ticket is infinitely more useful than a finding that vanished because nobody existed to own it.
4. **Roll every routing gap into your run summary** (Section 8) as a single line per missing trade, not one escalation comment per finding — a human should see "3 findings need a Web Engineer, none exists yet" once, not three times.

### Step 4e — Re-resolve every run

The roster can change between runs — a company might hire a Web Engineer next month. Don't cache routing decisions across runs; re-run Steps 4a–4d fresh each time, and note in your run summary if the routing map changed since last time (e.g. "Technical fixes now go to Priya (Web Engineer) — previously unassigned").

---

## 5. De-dupe: don't re-file what you already filed

Every ticket carries a stable `Check-ID:` line (from `references/check-ids.md`, formatted per `references/ticket-template.md`) plus the affected URL — that pairing is what makes de-dupe reliable instead of a fuzzy guess based on prose that drifts month to month.

Before opening a ticket for any finding, search the board for an existing open (not done, not cancelled) issue whose body contains the same `Check-ID:` value **and** the same URL.

- **Found a match:** don't open a new ticket. Add a recurrence comment to the existing one instead, and bump its severity one tier the first time it crosses three consecutive unresolved runs — the exact comment format and the bump rule are in `references/run-summary-template.md`. An aging ticket that nobody has acted on is itself a P0-shaped signal, regardless of what the original finding's severity was.
- **No match found:** open a new ticket per Sections 3/4 above, using the format in `references/ticket-template.md`.
- **A previously-closed ticket for the same `Check-ID` + URL reappears:** this is a regression, not a duplicate. Open a new ticket, and reference the old one explicitly in its `Notes` section ("regression of [prior ticket] — fix did not hold, or was reverted"), so the pattern is visible rather than looking like a fresh, unrelated problem.

Getting this rule wrong in either direction breaks the loop: too loose, and the board fills with three tickets for the same broken canonical every quarter; too strict, and a genuine regression gets silently merged into a ticket that was already marked done.

---

## 6. The review gate for high-risk changes

Some fixes can take pages out of the index if they're wrong. Route these differently from the rest of the board:

**What counts as high-risk:** the fixed list of `check_id`s at the bottom of `references/check-ids.md` — indexability/robots/canonical findings and redirect loops, plus (by the same logic even though it doesn't reduce to one check_id) any sitewide redirect/URL-structure change or internal-linking change made at template scale rather than a single page. These are singled out because a single mistake in this category can affect a large fraction of the site at once — a robots.txt error, for instance, can take down organic traffic sitewide within a day if it ships broken.

**How the gate works:**
1. The assigned specialist does the fix and marks the ticket ready for review — never straight to done.
2. Route the review to a second agent who is **not the original author.** Use the same trade-routing logic from Section 4 to find a second Technical agent if one exists; if the company only has one Technical agent, route the review to that trade's functional manager instead — never let the sole implementer also be the sole reviewer on a high-risk change.
3. For this specific class of change, also require a human (board/user) approval step before it's considered shipped, in addition to the peer review. A second AI reviewer catches obvious mistakes; a human catches the ones that require business judgment (is this URL change actually intended, is this the right canonical target).
4. **Verify on the next run, not just at ship time.** Don't close the loop on a high-risk fix the moment it's marked done — flag it so your *next* scheduled audit specifically re-checks that exact URL/rule. A fix that was correct at review time but got reverted by a later deploy, or that a rushed second reviewer rubber-stamped, should get caught by the next crawl, not assumed fine forever.

If your Paperclip setup has no approval-request capability available to you, do the best available substitute: post a clearly-flagged comment on the ticket tagging a human, and hold the ticket in a "needs human sign-off" state rather than marking it done yourself.

---

## 7. Budget discipline

If a spend cap is configured for this audit run, track your cumulative cost as you go. As you approach the cap:

- Keep de-duping and scoring — that's cheap and prevents the board from drifting stale.
- Stop opening individual tickets once you're close to the cap. Instead, batch whatever's left into a single rollup ticket or comment summarizing the remaining findings (URL, check, severity) so nothing is silently lost — just less individually ticketed this run.
- Never silently truncate. If you stopped early because of budget, say so explicitly in the run summary, with a count of what was deferred.

An audit that quietly does less work as it approaches its budget, without saying so, is worse than one that stops and clearly explains what it didn't get to.

---

## 8. Run summary

End every run by posting one summary — as a comment on the run's own tracking issue, or wherever your routine's execution issue lives — using the exact template in `references/run-summary-template.md`. It covers URLs crawled, findings by severity, new tickets, de-dupes and regressions, routing gaps, review-gate status, cost, and anything worth flagging since last run.

This is the single artifact a human should need to read to know whether the loop is working. If reading it raises a question your run didn't answer, that's a sign the summary (or the run) needs more detail next time.

---

## 9. Edge cases

- **Zero agents exist in the company yet.** Still run the audit and still open tickets — leave every one unassigned and clearly labeled per Section 4d, and make the run summary's routing-gap section the headline, not a footnote. The point of the run is to make the backlog visible even before anyone exists to work it.
- **Every check comes back clean.** Say so plainly in the summary — zero new tickets is a legitimate, good outcome, not a sign the audit didn't do anything. Don't manufacture minor findings to have something to report.
- **The crawl itself fails or is partial** (site down, rate-limited, auth-walled section). Report exactly what was and wasn't covered — a partial crawl reported as complete is more dangerous than no audit, because it creates false confidence.
- **A finding doesn't cleanly fit one trade** (e.g. an orphan page that's really an information-architecture problem). Pick the best-fit trade, say so, and note in the ticket that it may need to be reassigned once someone looks at it — don't block on getting the routing perfectly right before filing.
- **The company's board/human deliberately reassigns or recategorizes a ticket you filed.** Don't re-open the routing debate on the next run — treat the human's reassignment as the current source of truth for that URL+check going forward, and only revisit it if the same finding recurs after the reassignment didn't resolve it.

---

## 10. Worked example (illustrative)

A mid-size site's monthly run:

```
Routing map resolved: Technical → Priya (Web Engineer, reports to CTO)
                       Content   → Sam (Content Editor, reports to CMO)

Crawled 1,240 URLs.

Findings: 2 P0, 6 P1, 9 P2 (17 total)
De-duped: 3 (already open, one bumped P2→P1 after 3rd consecutive run unresolved)
Regressions: 1 (canonical fix from two runs ago reverted by a template change)
New tickets opened: 13
  - #483 [P0] "Pricing page noindexed since last deploy" — Check-ID: indexability.blocked_by_robots_meta → Priya
    — flagged high-risk, review gate + human approval requested
  - #484 [P1] "14 internal links 404ing after nav redesign" — Check-ID: link_health.internal_4xx → Priya
  - #485 [P2] "6 product pages missing alt text" — Check-ID: on_page.image_missing_alt → Sam
  - ... (10 more)
Routing gaps: none this run
Review gate: #483 pending Priya's fix, reviewer will be the CTO (no second Technical agent yet)
Cost: $0.71, well under the $5 run cap
```

That's the shape every run should take: a resolved routing map up front, a scored and de-duped set of findings, tickets that actually landed on someone, the risky one gated, and a summary a human can read in twenty seconds.
