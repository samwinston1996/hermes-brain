# Workforce Architecture Notes

## Recommended Roster: CEO + 5 Specialists

| Profile | Role | Key Tools | Risk Level |
|---------|------|-----------|------------|
| default (CEO) | Orchestrator, reviews, approves | memory, skill_manage, kanban, cronjob, todo | Full |
| developer | Builds skills, MCP servers, code | terminal, execute_code, skill_manage | Full |
| researcher | Deep research, synthesis | web_search, web_extract, memory | Medium |
| trader | MT5 observe/paper/live | terminal, memory | **Restricted** |
| health | System health, resource audits | memory, skill_manage | Low |
| ai-scout | Weekly tool scan + tutor | memory, terminal | Low |

## Profiles That Were Cut

| Profile | Cut Reason | Replaced By |
|---------|-----------|-------------|
| PMO | Duplicates Kanban auto-decomposer | `kanban_decomposer` in config.yaml (gemini model) |
| Scheduler | Duplicates native cron | Direct cron entries per specialist profile |

## Kanban Column Lifecycle

Triage → Todo → Scheduled → Ready → In Progress → Blocked → Review → Done

The dispatcher picks up `ready` tasks and spawns the assigned profile as a subprocess. The profile works the task, marks it complete, and the cycle continues.

## Key Config References

- `kanban_decomposer` in config.yaml uses `gemini/gemini-2.5-flash` as auxiliary model
- `profile_describer` uses same model
- Auto-decompose is enabled by default when kanban_decomposer is configured