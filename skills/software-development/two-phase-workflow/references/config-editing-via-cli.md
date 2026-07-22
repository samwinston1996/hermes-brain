# Config Editing via Hermes CLI

Hermes protects `config.yaml` from direct file writes. Use the CLI instead.

## Setting values
```bash
/opt/hermes/bin/hermes config set section.key value
```

## Reading current config
```bash
/opt/hermes/bin/hermes config            # view entire config
/opt/hermes/bin/hermes config edit       # open in $EDITOR
```

## Key settings currently applied
- `approvals.mode: smart` — auxiliary model auto-approves low-risk commands
- `compression.threshold: 0.35` — compress sessions earlier (cheaper long sessions)
- `compression.enabled: true`
- `curator.consolidate: true` — auto-merge overlapping skills
- `curator.enabled: true`

## Pitfall
`hermes` is NOT on PATH in the terminal backend — it's at `/opt/hermes/bin/hermes`. Always use the full path. Or add `export PATH=/opt/hermes/bin:$PATH` at session start.

## Kanban→Telegram bridge (no_agent cron pattern)

A reusable pattern for surfacing completed Kanban work to Telegram without token burn:

1. **Write a Python script** that queries `kanban.db` for tasks completed since last check
2. **Track last check** in a state file (`/opt/data/state/kanban_bridge_last_check`)
3. **Print nothing if empty** — silent tick
4. **Print formatted message if new completions** — delivered as Telegram message
5. **Cron config:** `no_agent: True` with the script path

```python
# Pseudocode shape
def main():
    tasks = query_completed_since(last_check)
    if not tasks:
        save_last_check(now)
        return  # silent — zero tokens
    print(format_completions(tasks))
    save_last_check(now)
```

See: `/opt/data/scripts/kanban_bridge.py` (live instance)