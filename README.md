# paperclip-skills

> Reusable, portable operating procedures for AI agents running inside [Paperclip](https://github.com/paperclipai/paperclip) — *the open-source app everyone uses to manage agents at work.*

Each skill in this repo is a complete, self-contained procedure an agent can pick up cold and run **identically every time it wakes** — the checklist, the scoring rubric, the routing logic, the de-duplication rules, and the review gate. Not "what to do," but "exactly how to decide." These are the skills Paperclip injects into an agent at runtime.

## Table of contents

- [What is Paperclip?](#what-is-paperclip)
- [Why skills?](#why-skills)
- [What's in this repo](#whats-in-this-repo)
- [Available skills](#available-skills)
- [Repository layout](#repository-layout)
- [Using a skill](#using-a-skill)
- [How this relates to the articles](#how-this-relates-to-the-articles)
- [License](#license)
- [Author](#author)

## What is Paperclip?

Paperclip is a Node.js server and React UI that orchestrates a team of AI agents to run a business. In its own framing: *if OpenClaw is an employee, Paperclip is the company.* You define a goal, hire agents into an org chart, and Paperclip coordinates the work — atomic execution, persistent agent state, governance with rollback, and goal-aware execution — so the agents run the business rather than you running the agents.

An agent is any runtime that can receive a heartbeat — Claude Code, Codex, Cursor, a bash script, an HTTP bot. Paperclip is deliberately **not** a chatbot, an agent framework, a workflow builder, a prompt manager, or a single-agent tool; it's the coordination and governance layer above whatever agents you already run.

The core building blocks a skill in this repo works with:

| Concept | What it is |
|---|---|
| **Agents** | Any bot/runtime that can receive a heartbeat — *"if it can receive a heartbeat, it's hired."* |
| **Issues** | Work units with goal ancestry, atomic checkout, and blocker dependencies — the actual work, assigned and tracked. |
| **Heartbeats** | Scheduled wakeups where an agent checks its work and acts. |
| **Org chart** | Hierarchies with roles, titles, reporting lines, and budgets. |
| **Routines** | Recurring work on cron / webhook / API triggers that mints its own execution issues. |
| **Approvals** | Board governance and execution policies — the review gate so risky changes get a second set of eyes before they ship. |
| **Budgets** | Token and cost tracking with hard-stop enforcement. |

Under the hood: Node.js 20+, PostgreSQL, a React/TypeScript UI, managed with pnpm. See [`paperclipai/paperclip`](https://github.com/paperclipai/paperclip) for the full picture.

## Why skills?

Paperclip is agent- and adapter-agnostic — it doesn't care whether the agent working an issue is Claude Code, Codex, or something else entirely. What it *does* need is **instructions**: a hired agent still has to know exactly what to do when it wakes up for a given kind of work.

That's what a skill in this repo provides. A skill is **not** a task description ("audit the site for SEO issues"). It's the whole decision procedure:

- the exact checklist,
- the exact scoring rubric,
- the exact rule for routing a finding to the right specialist when you don't know who's on the team,
- the exact de-duplication logic so the same problem doesn't get re-filed every run,
- and the exact review/approval gate for anything too risky to ship unsupervised.

## What's in this repo

Each top-level folder is one skill. Every skill follows the same shape:

```
<skill-name>/
├── SKILL.md      # the run procedure: what happens each time the agent wakes,
│                 # and every decision it has to make
└── references/   # the detail SKILL.md points to instead of repeating:
                  # exact thresholds, lookup tables, ticket templates
```

`SKILL.md` reads top-to-bottom as the run procedure. Anything that's a lookup table, an exact threshold, or a reusable template lives in `references/`, so `SKILL.md` stays a decision procedure rather than a wall of reference data.

## Available skills

| Skill | What it does |
|---|---|
| [`seo-audit`](seo-audit/) | Runs a recurring technical + on-page SEO audit and turns every finding into a scored, owned, de-duplicated fix ticket — routed to whichever agent in the company actually covers that trade, with clear fallbacks when no matching specialist exists yet. Its job starts where a plain audit report ends. |

## Repository layout

```
paperclip-skills/
├── README.md
└── seo-audit/
    ├── SKILL.md                          # run procedure + per-run decisions
    └── references/
        ├── check-ids.md                  # canonical checklist: every check_id,
        │                                  # thresholds, default severity/trade,
        │                                  # and which checks need the review gate
        ├── agent-routing.md              # keyword-matching table, tie-breaks,
        │                                  # fallback chain, worked example
        ├── ticket-template.md            # exact ticket format + de-dupe search
        └── run-summary-template.md       # recurrence/aging notation + summary
```

## Using a skill

Point the agent's instructions at the skill's `SKILL.md` — for example via Paperclip's per-agent instructions-path setting, or by including it in the agent's system prompt / skill directory, depending on your adapter.

`SKILL.md` assumes the agent already has working access to Paperclip's coordination surface — listing agents, creating and searching issues, posting comments, requesting approvals. It tells the agent **what to do with that access and how to decide**, not which specific API calls to make, so a skill isn't tied to one particular adapter or client.

## How this relates to the articles

Paperclip's content repo publishes articles that describe a *pattern* — a standing role or recurring loop assembled from Paperclip's primitives (an agent, a routine, a schedule trigger, a review gate) — as a narrative walkthrough: here's the problem, here's how you'd wire it up in the app, here's what you get.

This repo is where a pattern that's been written up as an article gets turned into something an agent can actually run:

- **The article** explains *why* you'd want a standing SEO auditor and *how* to assemble the loop in Paperclip (hire the agent, attach the routine, wire the review gate).
- **The skill** (`seo-audit`) is the concrete checklist, rubric, and routing logic you'd hand that agent as its instructions, so the loop runs the same way every time.

Not every article has a skill, and not every skill here started life as an article — but where both exist, expect the article to be the "why and how to set it up" and the skill to be the "here's exactly what the agent does."

## License

MIT — see [`LICENSE`](LICENSE).

## Author

Built by [Aron Prins](https://github.com/aronprins).

If you're building an AI-run company on Paperclip and need help with setup, architecture, or consulting — reach out on X:

**[@aronprins](https://x.com/aronprins)**

Follow for updates on Paperclip, new skills, and AI company building.
