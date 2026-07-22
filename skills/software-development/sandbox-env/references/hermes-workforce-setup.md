# Hermes Workforce Setup (from Sandbox)

End-to-end pattern for creating a multi-profile Hermes workforce from inside the execute_code sandbox. The sandbox has no `hermes` CLI — all profile/Kanban commands go through `docker exec hermes hermes`.

## Prerequisites

- Hermes gateway running (`docker exec hermes hermes gateway status`)
- Kanban initialized (`docker exec hermes hermes kanban init`)
- Profiles don't exist yet — first time setup

## Profile Creation

```bash
# Create all specialist profiles in one batch
docker exec hermes hermes profile create developer  --clone-from-default
docker exec hermes hermes profile create researcher --clone-from-default
docker exec hermes hermes profile create trader     --clone-from-default
docker exec hermes hermes profile create health     --clone-from-default
docker exec hermes hermes profile create ai-scout   --clone-from-default
```

**Important:** `--clone-from-default` creates the profile directory, copies bundled skills, and creates a CLI alias. It does NOT copy `config.yaml` from the default profile. Each profile starts with zero config — no model, no toolsets, no env vars.

## Per-Profile Config Setup

After creating profiles, each needs a `config.yaml` with at minimum the model provider and toolsets. Write these via Python `open()` in `execute_code` (since `write_file` is blocked):

```yaml
# Minimum viable config.yaml for a specialist profile
model:
  default: deepseek/deepseek-v4-flash
  provider: openrouter
  base_url: https://openrouter.ai/api/v1
  api_mode: chat_completions
toolsets:
  terminal: true
  memory: true
# Add per-role toolsets:
# researcher: web, browser, memory
# developer: terminal, code_execution, skill_manage, memory
# trader: terminal, memory (NO browser, NO web)
# health: memory, skill_manage
# ai-scout: memory, terminal
terminal:
  backend: docker
  cwd: /home/trader/workspace
  timeout: 600
  docker_image: nikolaik/python-nodejs:python3.11-nodejs20
  docker_volumes:
    - /home/trader/workspace:/home/trader/workspace
```

Write to: `/home/trader/.hermes/profiles/<name>/config.yaml`

**Failure mode without config:** The dispatcher spawns the profile, but the API call fails with `HTTP 400: No models provided` because `Model:` is empty. This looks like a Hermes bug but is actually just missing config.

## Per-Profile SOUL.md

Each profile needs a SOUL.md dropped into `/home/trader/.hermes/profiles/<name>/SOUL.md`. This is the identity/tone/voice file. Tool access is NOT gated by SOUL.md — real restrictions go in `config.yaml` under `toolsets:`.

Key sections to include:
- YAML frontmatter (name, description, model, tools — advisory only, tools are in config.yaml)
- Role description
- Values/rules
- Hard limits (especially for trader: no live orders without confirmation)
- What the profile is NOT

## Kanban Dispatcher Routing

The dispatcher needs `hermes profile describe` to route triage tasks correctly. Without descriptions, the auto-decomposer doesn't know which profile to assign:

```bash
docker exec hermes hermes profile describe developer  --text "Writes and maintains code: skills, MCP integrations, general engineering. Sandboxed terminal only."
docker exec hermes hermes profile describe researcher --text "Deep research and synthesis. No side effects — hands findings back."
docker exec hermes hermes profile describe trader     --text "MT5 monitoring/execution. Observe-only until further notice."
docker exec hermes hermes profile describe health     --text "System health monitoring, pattern surfacing. Never diagnoses."
docker exec hermes hermes profile describe ai-scout   --text "Weekly AI ecosystem scan, plus on-demand system explainer."
```

**Failure mode without descriptions:** `hermes kanban dispatch` reports `Spawned: 0` because the decomposer cannot match the task to any profile.

## Kanban Task Creation & Dispatch

```bash
# Create a triage task (auto-decompose by dispatcher)
docker exec hermes hermes kanban create "research topic X" --triage

# Create a directly assigned task
docker exec hermes hermes kanban create "task title" --assignee researcher

# Create with body text
docker exec hermes hermes kanban create "title" --body "Description goes here" --assignee researcher

# Dispatch (gateway runs this automatically every 60s, or manual)
docker exec hermes hermes kanban dispatch

# Check status
docker exec hermes hermes kanban list
docker exec hermes hermes kanban log <task_id>
```

**Note:** `--description` does NOT exist as a flag — use `--body` instead.

## Task States

| State | Meaning |
|---|---|
| `triage` | Raw idea — no spec yet. Auto-decomposer picks these up |
| `ready` | Spec'd and assigned — dispatcher will spawn the profile |
| `running` | Profile is actively working it |
| `blocked` | Stuck — auto-blocked after `failure_limit` consecutive crashes |
| `review` | Work done — CEO needs to sign off |
| `done` | Complete |

## Workflow Lifecycle (Auto-Decompose)

1. You or CEO creates a `--triage` task with a rough goal
2. Kanban auto-decomposer reads the goal, checks profile descriptions, produces child tasks
3. Child tasks get assigned to specialist profiles automatically
4. Each child moves: `triage → ready → running → review → done`
5. When all children complete, parent triage task promotes to `ready`
6. CEO (default profile) picks it up to judge results

## Purging Retired Profiles

When removing profiles (e.g., cutting unnecessary profiles like PMO, Scheduler):

```bash
# 1. Backup first
docker exec hermes hermes profile export <name> --output /opt/data/profiles/<name>-backup.tar.gz

# 2. Delete
docker exec hermes hermes profile delete <name> --yes
```

Backups go to `/opt/data/profiles/<name>-backup.tar.gz` (inside the Hermes container, maps to `/home/trader/.hermes/profiles/` on host).

If `hermes profile export` fails with permission error, write to a writable path first (e.g., explicitly use `--output /tmp/<name>-backup.tar.gz` then `cp`).

## Pitfalls

1. **Forgetting config.yaml** — Profiles with no config fail with "No models provided" on first dispatch. Not intuitive.
2. **Omitting profile descriptions** — Auto-decompose can't route without them. Dispatcher spawns 0 workers.
3. **Using `--description` instead of `--body`** — `kanban create` accepts `--body` for task text, not `--description`.
4. **Profiles not showing on Kanban assignees list** — They only appear after the dispatcher has tried to assign them. `on disk: no` is expected for profiles that haven't run tasks yet.
5. **Dashboard doesn't show Kanban profiles** — The dashboard is for the default profile only. Kanban is CLI-managed. Profiles won't appear in the dashboard UI.
6. **Gateway not running** — Without `hermes gateway start` (or `docker exec hermes hermes gateway start`), the dispatcher won't auto-tick every 60s.