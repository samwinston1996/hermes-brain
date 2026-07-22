---
name: hermes-cost-awareness
description: Understand and diagnose what drives OpenRouter token costs in Hermes — model selection, tool call compounding, dashboard vs telegram independence, and max_turns tradeoffs.
trigger: User asks about token costs, credit usage, "why am I spending so much", or suspiciously high API bills
lang: en
---

# Hermes Cost Awareness

Every Hermes interaction costs tokens. Understanding the drivers lets you pinpoint runaway spending before it becomes a surprise bill.

## Cost Drivers (by magnitude)

| Factor | Impact | Details |
|--------|--------|---------|
| **Model choice** | 75x+ | Sonnet (~$15/$75 per M) vs DeepSeek (~$0.20/$1.10 per M). This is the BIGGEST lever. |
| **Tool call count** | Linear per turn | Each tool call is a round-trip (input + output). More calls = more turns = more spent. |
| **Context growth** | Compounding | Every turn's tool RESULT gets appended to conversation history. The NEXT turn pays for ALL of it. A 10-turn session costs more than 10x a 1-turn session because the input grows. |
| **Conversation length** | Compounding | Long sessions with many user messages grow the history the same way. |
| **max_turns** | Ceiling | Default 90. Higher = agent works longer before stopping = more total tokens per response. |

## Model Cost Table (OpenRouter, approximate)

| Model | Input ($/M tokens) | Output ($/M tokens) | Relative to DeepSeek |
|-------|-------------------|--------------------|---------------------|
| deepseek/deepseek-v4-flash | ~$0.20 | ~$1.10 | 1x (baseline) |
| google/gemini-2.0-flash-001 | ~$0.10 | ~$0.40 | ~0.5x |
| google/gemini-3.1-flash-lite-preview | ~$0.30 | ~$1.00 | ~1x |
| minimax/minimax-m2.7 | ~$1.50 | ~$5.00 | ~5x |
| anthropic/claude-sonnet-4 | ~$15.00 | ~$75.00 | ~75x |
| anthropic/claude-opus-4.8 | ~$75.00 | ~$375.00 | ~375x |

*Prices change. Check OpenRouter dashboard for current rates.*

## Dashboard vs Telegram Model Independence

**Critical:** The dashboard web UI (port 9119) has its OWN model picker that is COMPLETELY SEPARATE from `config.yaml`. This means:

- You can be chatting on **Telegram via DeepSeek** (~$0.20/M input) while the **dashboard is running Sonnet** (~$15/M input)
- Both consume credits simultaneously
- There is no single "master model switch" — two independent places control what model gets used

**How to diagnose:** Check the agent logs for model names in use:

```bash
grep "model=" /opt/data/logs/agent.log | grep "client created" | tail -20
```

If you see models you didn't intend (especially sonnet/opus), the dashboard or a cron job is using them.

**How to fix:**
1. Open the dashboard at port 9119
2. Find the model picker dropdown in the chat UI
3. Select your intended model (DeepSeek, MiniMax, etc.)
4. Future dashboard chat sessions will use that model

## How One Tool Call Burns Tokens

Concrete example — Step 1 of the startup ritual:

```
Turn 1: I call terminal("git log --oneline -5")
  Input:  8K tokens (system prompt + tool defs + memory + conversation history)
  Output: 200 tokens (reasoning + tool call JSON)
  Cost (DeepSeek): 8K×$0.20/M + 200×$1.10/M = $0.0018
  Cost (Sonnet):   8K×$15/M  + 200×$75/M  = $0.135

Turn 2: Result comes back (500 tokens). I process it, call docker ps.
  Input:  9K tokens (system prompt + tool defs + memory + history + previous result)
  Output: 200 tokens
  Cost (DeepSeek): $0.002
  Cost (Sonnet):   $0.15

After 10 turns (typical startup ritual):
  DeepSeek: ~$0.02  ← barely registers
  Sonnet:   ~$1.50  ← $4 in 30 min is conservative
```

The compounding effect: Turn 10's input includes ALL previous tool results, not just the latest one. A tool that returns 5K tokens of log output inflates every subsequent turn.

## Diagnosing Runaway Costs

When the user says their credits are flying:

```bash
# 1. Check what model(s) are actually in use
docker exec hermes grep "model=" /opt/data/logs/agent.log | grep "client created" | tail -20

# 2. Check config for the intended default
docker exec hermes cat /opt/data/config.yaml | grep -A3 "^model:"

# 3. Check if the dashboard is running an expensive model
# (The dashboard's model picker is independent — no CLI check possible)

# 4. Check cron jobs that might be running autonomously
docker exec hermes ls /opt/data/cron/
```

Common patterns:
- **Dashboard left on Sonnet** — silent $15/M input burn while Telegram stays cheap
- **Cron jobs running on expensive model** — every scheduled tick costs more than expected
- **Very long sessions** — a single session with 50+ tool calls and large log outputs costs more than 10 short sessions

## The max_turns Tradeoff

| Setting | Effect on Cost |
|---------|---------------|
| `max_turns: 90` (default) | Agent stops after 90 internal turns. Forces user to continue, limiting per-response burn |
| `max_turns: 200` | Agent works longer uninterrupted. Each "response" processes more intermediate results. More tokens per response. Useful for complex pipelines but burns more per response |

Set via `agent.max_turns` in config.yaml:
```yaml
agent:
  max_turns: 90
```

## Pitfalls

- **Don't assume the model in config.yaml is the only model running** — the dashboard and cron jobs are independent
- **Don't forget tool results compound** — the biggest cost driver isn't the tool call itself, it's that ALL previous results get re-read every turn
- **Don't rely on max_turns as a cost-control mechanism** — it caps per-response runtime, not total spend. A task that needs 200 turns will just take 2-3 responses instead of 1, costing the same overall.
- **'My credits are flying' + 'my dashboard was using sonnet'** is the most common root cause — check model first, tool calls second

## Related Skills

- `session-startup-ritual` — This ritual alone causes 10-15 tool calls; its Pitfalls section has token cost awareness
- `hermes-agent` — Config setup and profile management (bundled, read-only)

## Reference Files

- `references/runaway-cost-diagnosis.md` — Full walkthrough of a real incident (16 sonnet sessions, $4 in 30 min) with exact commands and outputs
