---
name: hermes-workforce-setup
description: "Set up a multi-profile Hermes agent workforce with per-profile SOUL.md identity files, model config, Kanban board, and dispatcher. Covers the full lifecycle: profile creation → identity writing → Kanban init → dispatch → monitoring."
version: "0.1"
author: "Hermes Agent (auto-generated)"
metadata:
  hermes:
    tags: [hermes, profiles, kanban, workforce, multi-agent, orchestration]
    related_skills: [hermes-agent, sandbox-env]
---

# Hermes Workforce Setup

## When to Use

- Setting up multiple Hermes profiles (CEO, PMO, Developer, Researcher, etc.)
- Configuring Kanban board for multi-agent task dispatch
- Writing per-profile SOUL.md identity files
- Troubleshooting dispatcher failures ("No models provided")
- Creating the first smoke-test task to verify the pipeline

## Profile Creation

```bash
# Create profiles (simplified roster — PMO and Scheduler cut, they duplicate native features)
hermes profile create developer   --clone-from-default
hermes profile create researcher  --clone-from-default
hermes profile create trader      --clone-from-default
hermes profile create health      --clone-from-default
hermes profile create ai-scout    --clone-from-default
```

**What this does:**
- Creates `~/.hermes/profiles/<name>/` directory
- Clones all bundled skills from default
- Creates CLI wrappers (`.local/bin/<name>`)
- Creates an initial SOUL.md with generic content
- **Does NOT** create a `config.yaml` — you must write one

## After Creation: Critical Steps

### 1. Write per-profile SOUL.md

Each profile needs a SOUL.md with:
- YAML frontmatter: `name`, `description`, `model`, `tools`, `version`
- Identity section: who this profile is, what it does
- Rules/boundaries: hard limits specific to this role
- Style/tone: how it communicates

See the **Per-Profile SOUL.md Template** section below for the standard structure.

### 2. Write `config.yaml`

**This is the step that's most commonly missed.** Profiles created with `--clone-from-default` do NOT get a config.yaml. Without one, the Kanban dispatcher cannot spawn them:

```bash
HTTP 400: No models provided
Provider: openrouter  Model: <empty>
```

Minimal config required:

```yaml
# ~/.hermes/profiles/<name>/config.yaml
model:
  default: deepseek/deepseek-v4-flash
  provider: openrouter
  base_url: https://openrouter.ai/api/v1
  api_mode: chat_completions
terminal:
  backend: docker
  cwd: /home/trader/workspace
  timeout: 600
  docker_image: nikolaik/python-nodejs:python3.11-nodejs20
  docker_volumes:
    - /home/trader/workspace:/home/trader/workspace
```

**All 7+ profiles need this** — not just the first one you test.

### 3. Install Kanban plugin for each profile

```bash
hermes skills install /opt/hermes/plugins/kanban             # CEO/default profile
hermes -p developer skills install /opt/hermes/plugins/kanban
hermes -p researcher skills install /opt/hermes/plugins/kanban
# ...etc for all profiles
```

## Kanban Board Setup

```bash
# Initialize
hermes kanban init

# Create first task
hermes kanban create "Task title" --assignee researcher --body "Description"

# Check status
hermes kanban list
hermes kanban assignees
```

## Dispatch Pipeline

The Kanban dispatcher runs inside the gateway. On each tick (default 60s):
1. Scans `ready` tasks
2. Spawns the assigned profile as a subprocess
3. Profile reads the task, works on it, marks complete

### Manual dispatch (for testing)
```bash
hermes kanban dispatch           # dry run first time
hermes kanban dispatch           # actual dispatch
```

### Common dispatch failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Spawned: 0` | Dispatcher can't find profile | Check `hermes kanban assignees` — does the profile show up? |
| `Model: <empty>` | Profile has no config.yaml | Write `config.yaml` with `model.default` set |
| `HTTP 400: No models provided` | Model name empty | Same as above |
| Task stays `ready` forever | Gateway dispatcher not running | `hermes gateway start` or run `hermes kanban dispatch` manually |
| Task goes `running` but never completes | Model/API key issue | Check `hermes kanban log <task_id>` for error details |
| `on disk: no` for profile | Profile exists on disk but dispatcher hasn't cached it | Run dispatch once, it auto-discovers |
| `failed to connect` | Docker socket not accessible from spawned profile | Mount docker socket in profile's config.yaml terminal section |

### Monitoring
```bash
hermes kanban list               # all active tasks
hermes kanban log <task_id>      # full execution log
hermes kanban watch              # live feed
hermes kanban assignees          # profile availability
```

## Per-Profile SOUL.md Template

Each workforce profile SOUL.md follows this structure:

```markdown
---
name: "<Role Name>"
description: "<One-line role description>"
model: "<model-name>"
tools: ["<tool1>", "<tool2>"]
version: "0.1"
lang: "en"
---

# <Role Name> — <Subtitle>

You are <Role Name>, part of a personal AI workforce. <One-paragraph role definition>.

## Boundaries / Hard Rules

- <Concrete rule about what this profile never does>
- <Another rule>

## Style

- <Communication preference>
- <Output format preference>

## What you are not

<Clear statement of non-responsibilities>
```

### Tool assignment by role

| Profile | Core Tools | Model | Notes |
|---------|-----------|-------|-------|
| CEO / Default | memory, skill_manage, kanban_create, kanban_list, delegate_task, cronjob, todo, session_search | **minimax/m2.7** (plan) / deepseek-v4-flash (execute) | Orchestrator — model switches based on phase |
| Developer | terminal, execute_code, skill_manage | **deepseek/deepseek-v4-flash** | Code writing — needs quality |
| Researcher | web_search, web_extract, memory | **minimax/m2.7** | Deep research — cheap model fine |
| Trader | terminal, memory | **deepseek-v4-flash** | MT5, trading decisions |
| Health | memory, skill_manage | **minimax/m2.7** | Pattern analysis, reports |
| AI Scout | memory, terminal | **minimax/m2.7** | Tool discovery + tutoring — cheap model ideal |

**Model rationale:** minimax-m2.7 has a 205K context cap which naturally limits session growth. deepseek-v4-flash has 1.05M context — sessions can grow massive before hitting the limit, driving up cost. Using minimax for planning (where quality requirements are lower) and deepseek for execution (where quality matters) is the optimal split.

**Phase switching:** When the user starts a new chat for planning → minimax. When they say "execute task X" → deepseek. The active model is announced at the start of each session.

## Architecture Decision: Which Profiles to Keep

Not all profiles from the blueprint are worth creating. Two profiles duplicate Hermes-native features:

| Profile | Verdict | Why |
|---------|---------|-----|
| PMO | **Cut** | Kanban's auto-decomposer (configured at `kanban_decomposer` in config.yaml) already breaks down tasks and links dependencies. PMO's only job was decomposition — it's redundant. |
| Scheduler | **Cut** | Cron is a native top-level Hermes feature. Give each specialist its own cron entry instead of routing through a middleman profile. |
| Developer, Researcher, Trader, Health, AI Scout | **Keep** | Real tool/model/risk boundaries worth isolating as separate profiles. |

**Recommended roster:** CEO (default) + 5 specialists = 6 profiles total.

### Profile Descriptions for Auto-Decomposer

After creating profiles, set routing descriptions so the Kanban auto-decomposer can route triage tasks to the right specialist:

```bash
hermes profile describe developer --text "Builds and maintains skills, MCP servers, and all custom software. Uses terminal, execute_code, skill_manage."
hermes profile describe researcher --text "Deep-dives defined questions, returns synthesis with citations. Uses web_search, web_extract. No action on findings."
hermes profile describe trader --text "Monitors MT5 connection, observe-only by default. No live orders without per-order Telegram confirmation. Kill-switch wired."
hermes profile describe health --text "System health, resource optimization, finds inefficiencies. Tough advisor style."
hermes profile describe ai-scout --text "Weekly scan for new AI tools. Cross-references against installed stack. Agent Tutor mode. Proposes, never auto-installs."
```

### Per-Profile Tool Restrictions

Some profiles (especially Trader) should not have full terminal or browser access. Restrict toolsets in the profile's `config.yaml`:

```yaml
# ~/.hermes/profiles/trader/config.yaml
toolsets:
  web: false
  browser: false
  terminal: true
  file: false
  code_execution: false
  memory: true
  skills: false
```

Note: per-profile toolset restrictions may not fully take effect if the profile inherits from the default toolset. The SOUL.md hard rules are the real safety mechanism — treat config.yaml tool restrictions as defense-in-depth, not the sole boundary.

### Before Deleting Profiles: Pause and Show

When asked to delete profiles, **always pause and report what they contain** before executing. The user expects to see:
- Any cron jobs owned by the profile
- Memory content worth keeping
- Skills installed
- Then ask for confirmation before deleting

Profile deletion command:
```bash
hermes profile delete <name> --yes
```

## VPS Operation — Hermes 24/7 Configuration

### WRITE_SAFE_ROOT Configuration

The `HERMES_WRITE_SAFE_ROOT` env var controls which paths the `write_file` tool is allowed to write to. It's set inside the Hermes Docker container (baked into the image or set via docker-compose `environment:`). Default is usually `/opt/data` (the Hermes data directory).

To allow `write_file` on workspace paths, override it in docker-compose.yml:

```yaml
# docker-compose.yml — hermes service environment section
environment:
  HERMES_WRITE_SAFE_ROOT: "/opt/data:/home/trader/workspace"
```

The env var supports multiple paths separated by `:` (Unix) or `;` (Windows). After changing it, restart the Hermes container for it to take effect.

**Where it's read:** The `write_file` tool runs in the **Hermes agent process** (main container), not the sandbox. The sandbox does not need this env var.

**Sandbox vs Host verification:** After updating, verify from the host side with `cat` — the sandbox bind mount may show a cached/buffered version that differs from the actual file on disk. Always check the file directly on the host when investigating corruption claims.

### Hermes Watchdog — Auto-Restart on Crash

For 24/7 operation, set up a cron job on the host that checks if the Hermes container is healthy and restarts it if not. This compensates for the brief gap when running `docker compose down` from Telegram (the bot goes offline, then comes back when the watchdog restarts it).

**Script location:** `/home/trader/workspace/scripts/watchdog.sh`

```bash
#!/bin/bash
if ! docker ps --filter name=hermes --filter health=healthy | grep -q hermes; then
  cd /home/trader/hermes && /usr/bin/docker compose up -d
fi
```

**Cron installation:**

```bash
# Ubuntu (crontabs in /var/spool/cron/crontabs/):
(crontab -l 2>/dev/null | grep -v watchdog; echo "*/1 * * * * /home/trader/workspace/scripts/watchdog.sh") | crontab -

# Alpine (crontabs in /etc/crontabs/):
echo "*/1 * * * * /home/trader/workspace/scripts/watchdog.sh" >> /etc/crontabs/trader
```

**Determining the cron system:** Check the host OS to find the correct crontab location:
- Ubuntu/Debian: `/var/spool/cron/crontabs/` — use `crontab -` command
- Alpine Linux: `/etc/crontabs/` — write directly to file
- To detect: `docker run --rm alpine cat /etc/os-release 2>/dev/null` (but note this checks the container OS, not the host — verify by checking host paths directly)

After installation, verify cron daemon is running: `ps aux | grep cron | grep -v grep`

**Testing the watchdog:** The user should run `docker compose down`, wait 60 seconds, then check if Hermes came back. After testing, check the watchdog log at `/home/trader/hermes/watchdog.log` (if logging is enabled in the script) for confirmation.

### Config File Editing Best Practices

When editing config or system files (docker-compose.yml, config.yaml, .env):

1. **Prefer `patch` tool over Python `open()`** — `patch` shows a unified diff of exactly what changed, making the edit transparent. Python `open()` shows the entire file content in a code block.

2. **Show the diff before applying** for any config/system file change:
   ```python
   # Show what will change first
   with open(path) as f:
       old = f.read()
   print(old.find(target_line))  # Show location
   # Then after edit, show the diff
   ```

3. **Atomic writes when using Python `open()`:** Always write to a temp file first, then `os.rename()` over the target. Rename is atomic on Linux — readers always see a complete file:
   ```python
   with open(path + '.tmp', 'w') as f:
       f.write(new_content)
   os.rename(path + '.tmp', path)  # atomic
   ```

4. **Verify from the host side** after writing through a Docker bind mount. The sandbox may show a cached/buffered version. Use `docker exec hermes cat /opt/data/path` or check via a temporary container that mounts the host directory.

5. **The `write_file` tool was previously blocked** on workspace paths. After fixing `HERMES_WRITE_SAFE_ROOT`, test: `write_file(path='/home/trader/workspace/.write_test', content='test')` then clean up the test file.

## Two-Phase Workflow (Standard Operating Procedure)

This user operates on a strict **two-phase workflow** for every task. This is a hard requirement, not a suggestion.

### Phase 1 — Plan (current session)
- **Primarily read-only.** No file writes, no config changes, no Docker operations.
- **Exception: terminal commands are ALLOWED for operational debugging** — if the gateway, dashboard, or a service goes down, fix it immediately in Phase 1. The two-phase rule exists to reduce planning-context costs, not to prevent emergency fixes.
- Analyze the task, break it into actionable subtasks.
- Research costs, dependencies, and alternatives (web search allowed).
- Save the plan as a Kanban task with detailed documentation.
- Keep replies short — minimize token usage.
- Present the plan to the user for approval.

### Phase 2 — Execute (fresh session)
- Start a new session (reduces context from ~700K to ~50K tokens).
- Reference the Kanban task for the action plan.
- Execute with clear guidelines from the plan.
- No planning overhead in the execution session.
- Report results back to the user.

### Session Memory Overflow — All Tools Fail

**Symptom:** Every tool call returns "operation interrupted: waiting for model response (0.3-3s elapsed)". Terminal, file reads, execute_code — all fail.

**Root cause:** Hermes tool memory exceeded the 2,200 character limit. Every tool call triggers a memory write, which fails when over limit, cascading into session interruption.

```
WARNING agent.tool_executor: Tool memory returned error: ... memory would be at 2,844/2,200 chars -- over the limit.
```

**Fix:** Trim memory entries via `memory` tool until under 2,200 chars. Session becomes responsive immediately.

**Prevention:** Keep memory entries lean — only durable facts, not task narratives or logs.

### Token cost rationale
| Approach | Tokens per task | Relative cost |
|----------|----------------|---------------|
| Single long session (97 msgs) | ~728K | ~100% |
| Two-phase (Plan 30msgs + Execute 30msgs) | ~60K × 2 = 120K | **~20%** |

The two-phase workflow saves ~80% of token costs by keeping sessions short. The majority of cost comes from growing context, not from individual model calls.

### Session token thresholds
| Level | Size | Action |
|-------|------|--------|
| 🟢 GREEN | < 200K | Normal |
| 🟡 AMBER | 200K - 400K | Consider `/compress` or wrap up |
| 🔴 RED | > 400K | Start fresh session immediately |

## Pitfalls

1. **`hermes profile create` does NOT create config.yaml.** The most common failure mode is the dispatcher spawning a profile that has no model configured. Always write config.yaml manually after creating a profile.

2. **Kanban profiles do not appear in the dashboard.** The Hermes dashboard (port 9119) is for the default profile only. Kanban is a CLI/API system. Use `hermes kanban list` to check board state.

3. **API keys are inherited from the environment.** Profiles without explicit API keys in their own `.env` will inherit from the shell environment. This usually works for OpenRouter but can fail for provider-specific auth methods.

4. **Smoke test with a simple task first.** Before real work, create a task assigned to the researcher profile that takes 30 seconds (e.g. "list installed Hermes skills"). Verify it completes before scaling up.

5. **Don't fabricate SOUL.md content.** The user explicitly rejected filled-in placeholders. Use genuinely known facts or leave brackets empty.

6. **`Spawned: 0` doesn't mean broken.** The dispatcher may need a manual `hermes kanban dispatch` call to discover profiles. Check `hermes kanban assignees` to see if the profile is registered. `on disk: no` with `running=1` is normal — the dispatcher spawns profiles as subprocesses, not persistent gateways.

7. **Always explain before running commands.** The user corrected this behavior early. For any multi-step or destructive operation, first explain what you're going to do and why, then ask for confirmation or approval before executing. This includes: profile deletion, config changes, Docker operations, file writes to system paths.

8. **Use milestone protocol for multi-step tasks.** When a task requires 2+ sequential steps: state the milestone name and estimate upfront, list the steps, execute, then report back with a status table. Do NOT stay in a hidden loop of silent commands.

9. **GitHub API rate limits block `hermes skills install` from hub.** Unauthenticated requests are capped at 60/hr. Set `GITHUB_TOKEN` in `.env` to raise to 5,000/hr. Without it, installs from the skills hub will fail with "GitHub API rate limit exhausted." Workaround: install from local path (`/opt/hermes/plugins/kanban`) instead.

## Reference Files

- `references/workforce-health-audit.md` — SQL queries and diagnostic procedure for checking which profiles are completing tasks vs crashing. Use when the operator asks "are the profiles working?" or "what's the workforce status."
- `references/workforce-architecture.md` — Architecture diagrams and design rationale.