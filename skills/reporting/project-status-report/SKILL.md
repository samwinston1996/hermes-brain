---
name: project-status-report
description: Deliver a structured PMO-style project status report — component health, activity summary, risks, and next steps. Use when the user asks 'give me project status', 'PMO report', or 'what's the state of X'.
lang: en
---

# Project Status Report — PMO Format

When the user requests a project status update, deliver a structured report covering:

## Format

### Header
`📋 Project Status Report — PMO Brief`
`**Date:** <date> | **Prepared by:** Jarvis (Orchestrator)`

### Section 1 — Component Health Table
| Component | Status | Uptime | Health |
|-----------|--------|--------|--------|
| Service A | ✅ Running | 3 hrs | Detail |
| Service B | ❌ Down | — | Detail |

Include all relevant services. Uptime from `docker ps`. Health from logs or endpoint checks.

### Section 2 — Activity Summary (last N minutes)
Signal flow, recent events, or key metrics. Table format:

| Item | Source | Verdict | Reason |
|------|--------|---------|--------|
| Msg 123 | Channel A | 🟢 IGNORE | Low confidence |
| Signal X | Channel B | 🟡 Rejected | Missing SL |

### Section 3 — Active Resources
What's connected, what's monitored, what's configured.

### Section 4 — Risks & Issues
| # | Risk | Severity | Status |
|---|------|----------|--------|
| R1 | Description | 🟡/🟠/🔴 | Note |

### Section 5 — Next Steps
1-2 clear options for what the user can action. End with an open question.

## Data Sources

| Data | Source |
|------|--------|
| Container status | `docker ps -a` |
| Recent activity | `docker logs <service> --tail 30` |
| Git state | `git log --oneline -5` |
| Task pipeline | Kanban DB query (SQLite) |
| Config | `config.yaml`, `.env`, compose files |

## Pitfalls

- **Don't narrate the scan** — report findings, not the process of finding them. The user wants the status, not a play-by-play of how you checked.
- **Don't fabricate metrics** — if you don't have log data, say "no recent activity data" rather than inventing.
- **Keep it legible** — tables and bullet lists, not dense paragraphs. The user scans these, they don't read them.
- **Lead with failures** — if a service is down or a task is blocked, say it in the first section, not buried at the bottom.
- **Don't include every tool call** — summarize. If the router rejected 50 signals for missing SL, that's one row with a count, not 50 rows.
- **End with a call to action** — "What would you like to action?" or "Ready to flip to Paper stage?" gives the user a clear next step.