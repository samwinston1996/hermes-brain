# Workforce Health Audit

When the operator asks "are the profiles working?" or "what's the status of the workforce?", use this diagnostic approach.

## Step 1 — Inspect Kanban Database

The Kanban DB at `/opt/data/kanban.db` stores all task lifecycle data. Query it to see which profiles are succeeding vs failing:

```python
import sqlite3

conn = sqlite3.connect('/opt/data/kanban.db')

# Task status by profile
cur = conn.execute("""
    SELECT assignee, status, COUNT(*) as count
    FROM tasks
    GROUP BY assignee, status
    ORDER BY assignee, status
""")
for row in cur.fetchall():
    print(f"{row[0]:20s} | {row[1]:15s} | {row[2]}")

# Failed tasks with error details
cur = conn.execute("""
    SELECT t.assignee, t.title, t.status, t.last_failure_error
    FROM tasks t
    WHERE t.status IN ('crashed', 'blocked')
    ORDER BY t.assignee
""")
```

## Step 2 — Check Which Profiles Actually Have Configs

Profiles created with `--clone-from-default` do NOT get a `config.yaml`. Without one, the Kanban dispatcher cannot spawn them:

```bash
ls ~/.hermes/profiles/*/config.yaml
# Missing config.yaml = profile won't dispatch
```

## Step 3 — Check Dispatcher Activity

The Kanban dispatcher runs inside the gateway. Check if it's spawning workers:

```bash
# Recent spawn events
docker exec hermes sqlite3 /opt/data/kanban.db \
  "SELECT task_id, profile, status, outcome, error FROM task_runs ORDER BY started_at DESC LIMIT 20;"
```

## Common Findings

| Pattern | Meaning | Action |
|---------|---------|--------|
| `default` tasks crash with "pid not alive" | Default profile spawned by dispatcher may not handle Kanban tasks reliably. | Assign tasks to specialist profiles (developer, researcher, trader, planner) |
| Profile has config.yaml but 0 runs | Profile exists but was never dispatched a task | Create a task for it or assign it a cron job |
| Many "protocol_violation" failures | Worker exited (rc=0) without calling `kanban_complete` | Usually a session timeout or tool limitation — check worker session logs |
| Profile status = `blocked` | Worker called `kanban_block` — waiting for operator input | Flag to operator for review |
| Profile has no config.yaml | `hermes profile create` doesn't generate configs | Write a minimal config.yaml per profile template |

## Pitfalls

- **sqlite3 may not be installed** inside the Hermes container. Use Python's `sqlite3` module via `execute_code` instead.
- **Session-specific state** — task success/failure is current state, not a permanent assessment. Re-audit before reporting.
- **Don't delete failing profiles** — first check if the dispatcher just didn't have configs or the tasks were ill-specified.