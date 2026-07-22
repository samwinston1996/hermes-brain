---
name: ai-tool-scout
description: "Weekly scan for new AI agent tools/frameworks/models relevant to this specific JARVIS stack, plus an on-demand tutor mode. Use when running the scheduled Monday digest, or when the operator asks 'what's new', 'should I switch to X', or 'explain how [feature] works'."
version: "0.1"
author: "Jarvis (auto-generated)"
---

# AI Tool Scout & Agent Tutor

This skill is deliberately not generic AI-news summarization. Its value is entirely in the cross-reference step: it only surfaces things that are actually new *relative to what this system already has installed*, and actually relevant *to this operator's specific stack* (development, trading, health tracking, home VPS ops — whatever's live in MEMORY.md).

## Mode 1 — Weekly Scan (triggered by cron)

1. **Current state inventory.**
   - Run `hermes skills list` to get installed skills.
   - Run `hermes mcp list` to get configured MCP servers.
   - Read `MEMORY.md` §Standing goals and Active projects to understand current stack focus.
   - Read `JARVIS-BLUEPRINT.md` §8 Curated references for known ecosystem players.

2. **Scan targets** (search in this priority order):
   - **Hermes ecosystem:** `awesome-hermes-agent` (0xNyk on GitHub), Hermes Agent releases/tags, `hermes skills search` for new hub entries, MCP servers catalog.
   - **Memory providers:** Mnemosyne, mem0, Honcho releases.
   - **Multi-agent frameworks:** New Kanban/dispatch features, swarmclaw, OpenJarvis (Stanford Hazy Research).
   - **Perception tools:** `computer-use-linux` updates, new Hermes browser backends, openWakeWord / Porcupine releases for voice.
   - **Trading/MT5:** New MT5 Python wrappers, broker API integrations relevant to trade-copier stack.
   - **Model releases:** New models on OpenRouter/Anthropic/DeepSeek that could replace or supplement current profile models.

> **Caveat: GitHub API rate limits.** `hermes skills search` and hub lookups use unauthenticated GitHub API (60 req/hr). If searches fail with "GitHub API rate limit exhausted," the `GITHUB_TOKEN` env var needs to be set in the profile's `.env`. For the ai-scout profile, ensure this is configured before the first scheduled run.

3. **Cross-reference.** For every item found:
   - Is it already installed? → skip.
   - Is it a version update of something installed? → note the delta.
   - Is it relevant to a current goal or active project from MEMORY.md? → prioritize.
   - Is it new-to-the-world? → flag with "watch" status.

4. **Write digest.** Output a short, structured report:
   ```markdown
   ## AI Tool Scout — [Date]

   ### 🔵 Adopt
   - [Name] — [why it's better than current solution, one sentence]

   ### 🟡 Watch
   - [Name] — [interesting but not urgent, why]

   ### ⚪ Skip
   - [Name] — [not relevant, why]
   ```
   Deliver to Telegram. Never auto-install anything — the scout proposes, the operator approves.

## Mode 2 — On-Demand Tutor

Triggered when the operator asks "explain [X]" or "how does [Y] work" about any component in the JARVIS system.

1. Identify what they're asking about — is it a Hermes concept, a profile, a tool, a skill, an MCP server, a plan phase?
2. Pull context from:
   - `JARVIS-BLUEPRINT.md` for architectural reasoning.
   - `SOUL.md`, `MEMORY.md`, `USER.md` for how it fits the operator personally.
   - Relevant skill SKILL.md files for implementation details.
3. Answer in terms of:
   - What it does (plain language).
   - Why it exists in *this* system (not generic docs).
   - Where to find it (CLI command, file path, profile name).
   - When to use it vs not use it (boundaries).
4. If the answer reveals a gap in the operator's understanding that could lead to a mistake (e.g. running Kanban tasks without the dispatcher), flag that proactively.

## Boundaries

- **Never auto-install** anything discovered in a scan. The scout proposes, the operator approves.
- **Never give trading advice.** Explain the MT5 skill mechanics, the kill switch, and the guardrails — but the operator makes all strategy decisions.
- **Never fabricate a tool comparison.** If you don't have real release notes or changelogs, say "I don't have current data on that — here's what I'd check."
- **Keep tutor answers short first, expand on request.** Default to a 3-sentence explanation; go deeper only if asked.

## Related files

- `/home/trader/.hermes/memories/MEMORY.md` — goals and stack context
- `/home/trader/workspace/JARVIS-BLUEPRINT.md` — full architecture and phased plan
- `/home/trader/workspace/CONFIG-AND-SECURITY-NOTES.md` — cron setup and trading guardrails
- `/home/trader/.hermes/skills/` — installed skills inventory
