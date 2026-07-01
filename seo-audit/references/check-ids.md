# Check-ID taxonomy

Every finding this skill produces must be tagged with exactly one `check_id` from this table. The `check_id` is the stable string that makes de-duplication and aging possible across runs (Section 5 of `SKILL.md`) — it goes in the ticket body via the format in `ticket-template.md`, so a later run can search for it instead of fuzzy-matching titles or prose, which drift month to month even when the underlying problem hasn't changed.

This file is the single source of truth for severity defaults and trade assignment. `SKILL.md` and `agent-routing.md` both point here rather than repeating the table, so the two never drift out of sync.

Detection method notes below tell you *what to look at*, not a specific tool call — use whatever page-fetching/inspection capability you have (fetch the raw HTML/headers, follow redirects, parse the sitemap XML) to gather the evidence.

---

## INDEXABILITY

| check_id | Default severity | Trade | What it means | How to detect it |
|---|---|---|---|---|
| `indexability.blocked_by_robots_meta` | P0 | Technical | A page that should be indexable carries a `noindex` directive | Fetch the page; check the `<meta name="robots">` tag content and the `X-Robots-Tag` response header for `noindex`. A page intentionally excluded (e.g. an internal search results page) is not a finding — only flag pages that should rank. |
| `indexability.blocked_by_robots_txt` | P0 | Technical | robots.txt disallows a path that contains indexable content | Fetch `/robots.txt`, parse the `Disallow` rules for the relevant user-agent group (including `User-agent: *`), and check whether any URL that should be indexable falls under a disallowed path. |
| `indexability.canonical_missing` | P0 | Technical | No canonical link element on the page | Fetch the page; look for `<link rel="canonical" href="...">` in the `<head>`. |
| `indexability.canonical_wrong_domain` | P0 | Technical | Canonical points to a different domain than the page itself | Resolve the canonical `href` against the page URL; compare the resulting domain to the site's own domain. |
| `indexability.canonical_not_absolute` | P1 | Technical | Canonical is present and same-domain, but is a relative path rather than a full URL | Check whether the `href` value starts with a scheme (`http://` / `https://`). A relative canonical is fragile — it silently breaks if the page is ever served from an unexpected path or a CDN mirror. |
| `indexability.sitemap_dead_url` | P1 | Technical | A URL listed in the sitemap 404s or redirects instead of returning 200 | Fetch every `<loc>` entry from `/sitemap.xml` (or whatever the `Sitemap:` directive in robots.txt points to, including sitemap indexes); note any non-200 response. |
| `indexability.sitemap_missing_live_url` | P1 | Technical | A live, indexable page has no corresponding sitemap entry | Compare the set of pages found during the crawl (excluding ones already flagged as noindex/blocked) against the sitemap's URL list. |

## LINK HEALTH

| check_id | Default severity | Trade | What it means | How to detect it |
|---|---|---|---|---|
| `link_health.internal_4xx` | P1 | Technical | An internal link resolves to a 4xx status | While crawling, follow every internal `<a href>` you discover and record its final status code. |
| `link_health.internal_5xx` | P1 | Technical | An internal link resolves to a 5xx status, or the request times out / fails outright | Same as above; treat a hard failure/timeout the same as a 5xx for scoring purposes, and say so explicitly in the evidence. |
| `link_health.redirect_chain` | P1 | Technical | Following a URL takes more than one redirect hop before reaching a final destination | Follow redirects manually (don't let a client auto-follow silently) and count hops; 2+ hops is a chain. Report the full hop sequence as evidence, not just the endpoints. |
| `link_health.redirect_loop` | P0 | Technical | A redirect chain returns to a URL already seen in the same chain | Same tracking as above; if a URL reappears in its own chain, it's a loop, not a chain — score it higher, since loops can break both crawlers and, in some client implementations, real browsers. |
| `link_health.orphan_page` | P2 | Content (reroute to Technical if the fix is structural/navigational rather than editorial) | An indexable page has no internal links from any other crawled page pointing to it | While crawling, build a simple in-vs-out link map: for every internal link found on every page, note the destination. After the crawl, any indexable/crawled page with zero recorded inbound internal links is an orphan candidate. Caveat: a page linked only from a section you didn't crawl (e.g. a mega-menu fragment your crawler didn't render) can look orphaned when it isn't — note this uncertainty in the ticket rather than asserting orphan status as fact if your crawl coverage was partial. |

## ON-PAGE

| check_id | Default severity | Trade | What it means | How to detect it |
|---|---|---|---|---|
| `on_page.title_missing` | P2 | Content | No `<title>` element, or it's empty | Fetch the page; check for a non-empty `<title>`. |
| `on_page.title_duplicate` | P2 | Content | The exact same `<title>` text appears on more than one crawled page | Collect every page's title text during the crawl; flag any title string shared by 2+ distinct URLs. |
| `on_page.meta_description_missing` | P2 | Content | No `<meta name="description">`, or it's empty | Check the `<head>` for a non-empty description meta tag. |
| `on_page.meta_description_duplicate` | P2 | Content | The exact same meta description appears on more than one crawled page | Same collection approach as title duplication. |
| `on_page.h1_missing` | P2 | Content | No `<h1>` on the page | Count `<h1>` elements. |
| `on_page.h1_multiple` | P2 | Content | More than one `<h1>` on the page | Same count; report how many were found. |
| `on_page.image_missing_alt` | P2 | Content | One or more `<img>` elements have no `alt` attribute, or an empty one, and are not decorative | Check every `<img>` tag's `alt` attribute; purely decorative images with `alt=""` intentionally set are correct and not a finding — only flag images that are missing the attribute entirely or clearly convey content (e.g. inside an `<a>`, or a product photo) without one. |
| `on_page.thin_content` | P2 | Content | Visible body text is unusually short for the page's apparent purpose | A rough default: fewer than ~150 words of visible body copy on a page that isn't a intentionally minimal type (e.g. a contact page) is worth flagging; use judgment for the site's own norms rather than treating 150 as a hard universal cutoff. |
| `on_page.duplicate_content` | P2 | Content | Body content substantially overlaps with another indexed page | Compare visible body text (not boilerplate nav/footer) across pages that look like near-duplicates; note which other URL it duplicates as evidence. |

## STRUCTURED DATA

| check_id | Default severity | Trade | What it means | How to detect it |
|---|---|---|---|---|
| `structured_data.invalid` | P1 | Technical | A structured data block is present but fails to parse or fails schema validation | Locate `<script type="application/ld+json">` blocks (or microdata/RDFa if that's what the site uses); confirm each JSON-LD block is valid JSON and matches a real schema.org type with its required properties present. Invalid structured data is worse than none — it can trigger a manual action rather than just a missed opportunity. |
| `structured_data.missing_expected` | P2 | Technical | A page type where structured data is expected (product, article, FAQ, breadcrumb, recipe, etc.) has none | Compare the page's apparent content type against what markup you'd expect for it; only flag page types where the site has a clear pattern of using structured data elsewhere (don't invent a requirement the site never had). |

## PERFORMANCE (Core Web Vitals)

Google's published "good" / "needs improvement" / "poor" thresholds, applied per key template (home, listing/category, detail — not one sampled page total):

| Metric | Good | Needs improvement | Poor |
|---|---|---|---|
| LCP (Largest Contentful Paint) | ≤ 2.5s | 2.5s – 4.0s | > 4.0s |
| INP (Interaction to Next Paint) | ≤ 200ms | 200ms – 500ms | > 500ms |
| CLS (Cumulative Layout Shift) | ≤ 0.1 | 0.1 – 0.25 | > 0.25 |

| check_id | Default severity | Trade | What it means |
|---|---|---|---|
| `performance.lcp_poor` | P1 | Technical | LCP over 4.0s on a key template |
| `performance.lcp_needs_improvement` | P2 | Technical | LCP between 2.5s and 4.0s on a key template |
| `performance.inp_needs_improvement` | P2 | Technical | INP between 200ms and 500ms on a key template |
| `performance.inp_poor` | P1 | Technical | INP over 500ms on a key template |
| `performance.cls_needs_improvement` | P2 | Technical | CLS between 0.1 and 0.25 on a key template |
| `performance.cls_poor` | P1 | Technical | CLS over 0.25 on a key template |

Prefer real-user field data (e.g. from a Core Web Vitals report tied to the site, such as Search Console's or a CrUX-backed dashboard) over a single synthetic lab measurement when both are available — field data reflects what real visitors experienced across many sessions; a one-off lab run on a single machine is noisier and can flag a page as "poor" on a slow test connection when real users are actually fine, or vice versa. If you only have lab data available, say so in the ticket's evidence rather than presenting a single synthetic run as equivalent to aggregated field data.

---

## High-risk check_ids (mandatory review gate — see `SKILL.md` Section 6)

Any finding tagged with one of these requires the non-author review + human approval treatment, no exceptions:

```
indexability.blocked_by_robots_meta
indexability.blocked_by_robots_txt
indexability.canonical_missing
indexability.canonical_wrong_domain
indexability.canonical_not_absolute
link_health.redirect_loop
```

Everything else follows the normal fix → review → done path from Section 4/5, without the mandatory human-approval step (a second agent's review is still good practice for anything P0/P1, but only this list is *mandatory* to gate).
