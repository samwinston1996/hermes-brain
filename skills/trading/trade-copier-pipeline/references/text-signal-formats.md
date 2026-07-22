# Structured Text Signal Formats

The text prompt was tuned for these signal formats. The LLM went from conf=0.20 (null SL) to conf=0.90 after prompt updates.

## Common Format: Labeled Fields (XAUUSD ANALYSIS TEAM)

```
XAUUSD BUY Signal (Gold)
Entry: 4069
Target:
  - TP1: 4074
  - TP2: 4079
  - TP3: 4084
Stop Loss: 4059
```

The prompt handles these by adding explicit rules for:
- "Entry: X", "Stop Loss: X" / "SL: X"
- "TP1: X", "TP2: X", "Target: X", "TP: X"
- Multiple TP levels as a list

## Simple Format (BotX channel style)

```
BUY XAUUSD
ENTRY: 4120
SL: 4110
TP: 4137
```

All-caps labels, single TP, straightforward.

## Formats That Should Be IGNORED

- Commentary, "Good morning", "XAU/USD ANALYSIS" headers without actionable levels
- Results screenshots showing filled trades
- Market views and recaps
- Advertising messages
- Any message where Entry, SL, and TP are not all present as labeled numbers