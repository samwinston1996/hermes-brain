---
name: session-startup-ritual
description: Pre-work orientation protocol — read internal files, re-familiarize with project state and next steps, then discuss before acting.
trigger: Beginning of any new session or significant task handoff
lang: en
---

# Session Startup Ritual

Every session begins with a read-only orientation BEFORE any planning, coding, or decision-making. The goal is to be grounded in current internal state before proposing anything.

## Protocol

### Step 1 — Re-read Internal Context
Read the durable references:
- `skill_view(name='session-startup-ritual')` — this file (re-affirm the protocol)
- Memory (already injected — mentally acknowledge current entries)
- USER.md / user profile (scrutinize for drift)
- Session history if continuing a prior conversation

### Step 2 — Session Recovery from Restart (if applicable)

If this session started after a Hermes container restart mid-workflow:

1. **Read memory** for a `SESSION PICKUP — Hermes restart pending` entry. If found, that entry contains the exact unfinished work, container state, and next steps.
2. **Verify** that the state described is still accurate.
3. **Do not re-plan from scratch** — the pickup note is the plan. Confirm with the user.
4. **If no pickup note exists**, run the normal startup sequence (Steps 1 → 3 → 4) to establish current state.

### Step 3 — Report in PMO Style
State what you remember from the last session: what was being worked on, where it was left off, and any open questions. Present it as a **working memory table**:

| # | Item | Status |
|---|------|--------|
| 1 | Last session's focus | ✅ Done |
| 2 | Open questions | 🟡 Pending |

Keep it compact — max 5-6 rows. This table becomes the session's initial working memory.

### Step 4 — Propose Path Forward
Do NOT start building or fixing. Present the situation, propose 2-3 options with tradeoffs, and end with:

> "Whenever you're ready, say **Execute Jarvis**."

Wait for explicit direction. Do not execute anything in this turn.

## Why This Exists

- Prevents acting on stale knowledge
- Establishes shared context so the user doesn't have to re-explain
- Approved by user on July 10, 2026; revised July 22, 2026

## Pitfalls

- **Preferred edit method: patch over write_file** — use `patch` for targeted edits on existing files; `write_file` only for new file creation or complete rewrites.
  - **Exception for root-owned files:** If a file is root-owned with 600 permissions, `patch` cannot read it. Use `write_file` instead.
- **Do NOT run shell commands or tool calls during the ritual** — this is a read-only internal familiarization step. No `find`, `git`, `docker`, `grep`, or any other terminal commands. No `delegate_task`, `execute_code`, or `cronjob`. Only `skill_view`, `read_file`, `session_search`, and `memory`.
- **Don't jump to Step 4** — Present the situation first, then ask. Going straight to "what should we do?" misses the orientation value.
- **Save session pickup note before restarting Hermes** — If you need to restart the Hermes container, save a `SESSION PICKUP — Hermes restart pending` entry to memory first with the exact unfinished work and next steps.

## Related Skills

- `findings-first-workflow` — When investigation turns into a code fix, use this companion skill for the approval gate before applying changes.
