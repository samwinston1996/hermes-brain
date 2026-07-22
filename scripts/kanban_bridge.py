#!/usr/bin/env python3
"""Kanban→Telegram bridge: prints newly completed tasks since last check.
Designed for `no_agent: True` cron: empty stdout = silent, non-empty = delivery."""

import sqlite3, os, json
from datetime import datetime, timezone

DB = "/opt/data/kanban.db"
STATE_FILE = "/opt/data/state/kanban_bridge_last_check"
HOME = "641927046"  # Sam's Telegram DM

def get_last_check():
    try:
        with open(STATE_FILE) as f:
            return float(f.read().strip())
    except (FileNotFoundError, ValueError):
        return 0.0

def save_last_check(ts):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        f.write(f"{ts:.6f}")

def format_ts(ts):
    if not ts:
        return "?"
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

def main():
    last_check = get_last_check()
    now = datetime.now(timezone.utc).timestamp()

    conn = sqlite3.connect(DB)
    cur = conn.cursor()

    # Find tasks completed since last check
    cur.execute(
        """SELECT id, title, assignee, status, completed_at, result
           FROM tasks
           WHERE completed_at IS NOT NULL
             AND completed_at > ?
             AND status IN ('done', 'archived')
           ORDER BY completed_at ASC""",
        (last_check,)
    )
    tasks = cur.fetchall()
    conn.close()

    if not tasks:
        # Silent — nothing to report
        save_last_check(now)
        return

    lines = ["📋 **Kanban Completions**"]
    for tid, title, assignee, status, completed_at, result in tasks:
        result_summary = ""
        if result:
            try:
                meta = json.loads(result)
                if isinstance(meta, dict) and meta.get("summary"):
                    s = meta["summary"]
                    # Truncate long summaries
                    if len(s) > 120:
                        s = s[:117] + "..."
                    result_summary = f"\n  > {s}"
            except (json.JSONDecodeError, TypeError):
                pass
        assignee = assignee or "default"
        icon = "✅" if status == "done" else "📦"
        lines.append(f"\n{icon} **{title}**")
        lines.append(f"  `by {assignee}` · {format_ts(completed_at)}")
        if result_summary:
            lines.append(result_summary)

    save_last_check(now)

    # Print the full message — this becomes the Telegram delivery
    print("\n".join(lines))

if __name__ == "__main__":
    main()