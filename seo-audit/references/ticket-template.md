# Ticket template

Use this exact shape for every fix ticket this skill opens. The rigid parts (the `Check-ID:` line and the title prefix) exist so that de-duplication (`SKILL.md` Section 5) can search reliably for "has this exact problem already been filed for this exact URL," instead of fuzzy-matching titles that will drift in wording from run to run even when nothing about the underlying issue has changed.

## Title format

```
[<SEVERITY>] <short human description> — <path or page name>
```

Examples:

```
[P0] Pricing page noindexed since last deploy — /pricing
[P1] Redirect chain (3 hops) — /old-blog/post-title
[P2] Missing alt text on 6 images — /products/example-widget
```

Keep the path/page name recognizable at a glance on a crowded board — a human scanning tickets should be able to tell which page is affected without opening every one.

## Body format

```markdown
**Check-ID:** `<check_id from check-ids.md>`
**URL:** <full URL>
**Severity:** P0 | P1 | P2 (and: default | bumped — see note below)
**Trade:** Technical | Content
**Needs:** <role that couldn't be matched — omit this line entirely if routing succeeded>

### Evidence
<what you actually observed — the exact header value, the redirect chain, the missing tag, the metric and its value. Be specific enough that the assignee doesn't have to re-crawl the page themselves to confirm the problem is real.>

### Suggested fix
<a concrete next step, not just a restatement of the problem — e.g. "add rel=canonical pointing to https://example.com/pricing" rather than "fix the canonical">

### Notes
<anything else relevant: whether this is a regression of a previously-closed ticket (link it), whether severity was bumped for aging (say how many runs it's persisted), whether this finding's trade assignment was a judgment call worth revisiting>
```

## Worked example

**Title:**
```
[P0] Pricing page noindexed since last deploy — /pricing
```

**Body:**
```markdown
**Check-ID:** `indexability.blocked_by_robots_meta`
**URL:** https://example.com/pricing
**Severity:** P0 (default)
**Trade:** Technical

### Evidence
The page's <head> contains `<meta name="robots" content="noindex, follow">`. This tag is not
present on any other marketing page on the site, and Search Console shows this URL dropped
from the index three days ago — consistent with this shipping in the last deploy rather than
being intentional.

### Suggested fix
Remove the noindex directive from the page template (or the CMS field controlling it) for
this URL, redeploy, and request re-indexing once live.

### Notes
Not a regression — first time this URL has been flagged. Because this is an indexability
finding, it requires the review gate: a second Technical reviewer plus human approval before
this is considered shipped (SKILL.md Section 6).
```

## De-dupe search

Before opening a new ticket, search the board's open (not done, not cancelled) issues for a body containing both:

- the same `Check-ID:` value, and
- the same URL

If both match, do not open a new ticket — comment on the existing one instead (see `SKILL.md` Section 5 for exactly what that comment should say, and when a match should escalate the existing ticket's severity for aging). If the `Check-ID` matches but the URL differs, that's a different finding, even though it's the same class of problem — file it as its own ticket.

If a ticket for the same `Check-ID` + URL was previously closed (`done`) and the finding has reappeared, this is a regression, not a duplicate — open a new ticket and reference the old one explicitly in its `Notes` section, so the recurrence is visible rather than looking like an unrelated fresh problem.
