# Runaway Cost Diagnosis — Real Example

## The Scenario

User reported $4 spent in 30 minutes. Telegram agent was configured for DeepSeek V4 (~$0.20/M input), but costs were flying as if using a premium model.

## Root Cause

The **dashboard web UI** (port 9119) had been switched to `anthropic/claude-sonnet-4` in its model picker dropdown. The dashboard and Telegram agent have INDEPENDENT model selection — changing config.yaml has zero effect on the dashboard, and vice versa.

## Diagnostic Commands Used

### Step 1 — Check what models are actually being used in agent sessions

```bash
# Run this from inside the hermes container or via docker exec
grep "model=" /opt/data/logs/agent.log | grep "client created"
```

### Step 2 — Spot the expensive model

Output from the actual incident:

```
2026-07-20 13:58:29,769 INFO run_agent: ... model=anthropic/claude-sonnet-4
2026-07-20 13:58:38,694 INFO run_agent: ... model=anthropic/claude-sonnet-4
2026-07-20 14:25:21,007 INFO run_agent: ... model=anthropic/claude-sonnet-4
2026-07-20 14:25:56,258 INFO run_agent: ... model=anthropic/claude-sonnet-4
2026-07-20 14:25:58,719 INFO run_agent: ... model=anthropic/claude-sonnet-4
2026-07-20 14:31:03,951 INFO run_agent: ... model=anthropic/claude-sonnet-4
2026-07-20 14:31:06,357 INFO run_agent: ... model=anthropic/claude-sonnet-4
2026-07-20 14:41:25,574 INFO run_agent: ... model=anthropic/claude-sonnet-4
```

16 total sessions created with sonnet-4 between 13:58-14:42.

### Step 3 — Check intended default

```bash
docker exec hermes cat /opt/data/config.yaml | grep -A3 "^model:"
# Output: model.default=deepseek/deepseek-v4-flash (correct — Telegram agent was fine)
```

### Step 4 — Count total sessions by model

```bash
# Count all sessions created per model
grep "model=" /opt/data/logs/agent.log | grep "client created" | grep -oP 'model=\S+' | sort | uniq -c | sort -rn
```

## Cost Math (approximate)

**Per typical tool-calling turn:**
- Input: ~8-10K tokens (system prompt + tool schemas + memory + conversation history)
- Output: ~200-300 tokens (reasoning + tool call JSON)

**Model comparison per turn:**
| Model | Per-turn cost (approx) | 16 sessions × 5 turns |
|-------|----------------------|----------------------|
| DeepSeek V4 | $0.002 | ~$0.16 |
| Claude Sonnet 4 | $0.15 | ~$12.00 |

**16 dashboard sessions** × average 5 turns each using Sonnet = easily $4-12 in 30 minutes.

## Key Lesson

**The dashboard model picker is the most common cause of unexpected high costs.** It's a dropdown in the web UI, not in config.yaml. Anyone using the dashboard should verify the model selected there matches their intended budget.
