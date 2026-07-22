# Token Cost Mechanics

## How Tool Calls Burn Credits

Every time I make a tool call, it's a **round trip** to the LLM provider. Each round trip costs tokens on **both** sides:

### Anatomy of One Turn

```
┌─ INPUT (you pay for this) ─────────────────────┐
│  System prompt (SOUL.md + memory + tools) ≈ 8K  │
│  + Conversation history (grows every turn)       │
│  + Tool result (the output from the last call)   │
│  ≈ 8K–15K tokens                                 │
└──────────────────────────────────────────────────┘
  ↓ LLM processes all of it
┌─ OUTPUT (you pay for this) ────────────────────┐
│  Model's reasoning + next tool call JSON ≈ 200  │
└──────────────────────────────────────────────────┘
```

**Key insight:** Every tool result feeds into the **next** turn's input, making each subsequent turn more expensive. The conversation compound effect.

### Real Example — Session Startup Ritual

| Turn | Action | Input (approx) | Output | What gets added |
|------|--------|----------------|--------|-----------------|
| 1 | `git log --oneline -5` | 8K | 200 | Git output (~200 tokens) |
| 2 | `docker compose ps` | 8.2K | 200 | Container list (~100) |
| 3 | `docker compose logs --tail=100 router` | 8.3K | 200 | Router logs (~3K tokens!) |
| 4 | Same for bridge | 11.3K | 200 | Bridge logs (~3K) |
| 5 | Same for listener | 14.3K | 200 | Listener logs (~3K) |
| ... | continues | grows | 200 | Keeps compounding |

By turn 5, **input is already 14K** because all previous tool results are in context. By turn 10, it can hit 25K+.

### Cost by Model

| Model | 10-turn ritual | 20-turn debug session |
|-------|---------------|----------------------|
| DeepSeek V4 ($0.20/$1.10) | ~$0.02 | ~$0.05 |
| Claude Sonnet 4 ($15/$75) | ~$1.50 | ~$4.00 |
| Claude Opus 4.8 ($75/$150) | ~$7.50 | ~$20.00 |

The difference is **75x between DeepSeek and Sonnet**.

### What Makes a Session Expensive

| Factor | Impact | Example |
|--------|--------|---------|
| **Model choice** | 75x+ | DeepSeek vs Sonnet |
| **Large tool results** | Compounds fast | `logs --tail=100` = 3K tokens per container |
| **Tool-heavy tasks** | More turns | Startup ritual = 10-15 turns |
| **Conversation length** | Every turn adds to input | Long sessions cost more per turn |
| **Dashboard model override** | Hidden cost | Dashboard has its own model picker, independent of config.yaml |

### How to Estimate

```python
# Rough formula for a session
turns = 12  # typical startup ritual
avg_input = 10000  # tokens per turn (grows, but average)
avg_output = 200   # tokens per turn
input_tokens = turns * avg_input  # ~120K
output_tokens = turns * avg_output  # ~2.4K

# DeepSeek
cost = (120000 / 1_000_000 * 0.20) + (2400 / 1_000_000 * 1.10)
# = $0.024 + $0.0026 = ~$0.03

# Sonnet
cost = (120000 / 1_000_000 * 15) + (2400 / 1_000_000 * 75)
# = $1.80 + $0.18 = ~$1.98
```

### Minimizing Costs

1. **Use DeepSeek** for most sessions — it's the cheapest capable model
2. **Limit `--tail=N`** on logs — N=50 instead of 100 halves the token cost
3. **Short sessions** — `/reset` frequently when switching tasks (clears conversation history)
4. **Check dashboard model** — never assume config.yaml is the only model source
5. **Beware of `find`/`grep` output** — large file trees or search results are expensive
