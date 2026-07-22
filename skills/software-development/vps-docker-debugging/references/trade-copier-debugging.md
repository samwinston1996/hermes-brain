# Trade-Copier Pipeline Debugging

## Architecture Overview

```
Listener (Telethon userbot) ──webhook──→ Router (FastAPI :8080) ──LLM──→ OpenRouter API
                                                │
                                          Bridge (uvicorn :8002, shares mt5 netns)
                                                │
                                            MT5 (Wine + mt5linux :8001)
```

| Service | Role | Port | Network |
|---------|------|------|---------|
| **Listener** | Telethon userbot — catches Telegram signals, pushes to router webhook | — | `trade-copier_copier` |
| **Router** | Receives webhook, calls OpenRouter to parse signal intent, forwards to Bridge | 8080 | `trade-copier_copier` |
| **OpenRouter** | LLM proxy — routes parsing to DeepSeek (text) or Gemini (vision) | external | internet |
| **Bridge** | Risk & compliance gates (dedup, daily loss cap, max trades, lot sizing) | 8002 | shares `mt5` netns |
| **MT5** | MetaTrader 5 via Wine + mt5linux RPC | 3000 (VNC), 8001 (RPC) | `trade-copier_copier` |

**Important:** The Router calls OpenRouter DIRECTLY, NOT through the Hermes API server. The Hermes API server at `:8642` processes requests through the Jarvis agent system — it is NOT a raw LLM proxy. Using OpenRouter directly decouples the pipeline from Hermes uptime and avoids unwanted agent processing of system prompts.

## Pipeline Trace Checklist

When a signal fails, check ALL containers at once:

```bash
cd /home/trader/workspace/projects/trade-copier
docker compose logs --tail=50 listener router bridge
```

Present as a one-line-per-stage trace table. Always show:
1. **Where** in the pipeline it broke (which service)
2. **What** the actual problem is (error, retcode, None response)
3. **What's expected** (correct JSON format, retcode 10009, etc.)

## Consent-First Rule

When debugging this pipeline, follow this strict workflow:

1. **Report** — present all findings clearly (what's wrong, where, evidence from logs)
2. **Wait** — let the user read and acknowledge the diagnosis
3. **Get consent** — user explicitly says "fix it" or "go ahead"
4. **Fix** — then apply the change

NEVER apply fixes autonomously. The user corrected this behaviour explicitly. Even fixes that seem "obvious" go through this workflow. The SKILL.md for this skill has the full rule.

## Common Failure Points

### 0. Pipe Character in MT5 Comment → order_send Returns None

**Symptom:** `order_send` returns `None` (not a retcode) for orders where the `comment` field contains a pipe `|` character. Same order with `|` removed works fine.

**Root cause:** MT5's `order_send` silently rejects the `|` character in the comment field. The mt5linux RPC library returns Python `None` instead of an `OrderSendResult` object.

**Fix — sanitize comment before sending:**
```python
"comment": f"{req.comment}|{req.signal_id}"[:31].replace("|", "-"),
```

The `|` is replaced with `-` (safe separator). The truncation to 31 chars must happen before the replace, or the `|` in the format string might be past the 31-char boundary.

### 0a. Invalid "comment" Argument → MT5 Rejects with last_error=(-2, 'Invalid "comment" argument')

**Symptom:** `order_send` returns `None` with `last_error=(-2, 'Invalid "comment" argument')`. The comment field contains the channel name followed by the signal_id (e.g. `"BotX channel-BotX channel:4133"`).

**Root cause:** The bridge concatenated the channel name and signal_id into the comment field:
```python
# BROKEN — concatenates channel + signal_id into comment
"comment": f"{req.comment}|{req.signal_id}"[:31].replace("|", "-"),
```
This produced `"BotX channel-BotX channel:4133"` — the duplicated channel name combined with the colon from signal_id format upsets MT5's comment parser.

**Fix — only use the clean channel name:**
```python
# FIXED — just the channel name, no signal_id
"comment": req.comment[:31],
```

The `signal_id` is still used for deduplication (`executed_signals` set) and alert messages — it doesn't need to be in the MT5 comment field.

**Relationship to the pipe bug:** The pipe character `|` was previously fixed by `.replace("|", "-")`, but the underlying issue was the concatenation itself creating a garbled comment string. The real fix is to not concatenate signal_id into the comment at all.

### 1. Daily Loss Cap Hit → 423 Locked

**Symptom:** Bridge returns HTTP 423 with `"DAILY LOSS CAP HIT — trading disabled today"`.

**Root cause:** `daily_loss_exceeded()` checks total profit from today's closed deals (since 00:00 UTC). If absolute loss exceeds `MAX_DAILY_LOSS_PERCENT` of current balance, trading is blocked.

**Fix:**
```bash
sed -i 's/MAX_DAILY_LOSS_PERCENT=4.0/MAX_DAILY_LOSS_PERCENT=20.0/' .env
docker compose up -d --no-deps bridge
```

### 2. Hermes API Agent Processing → 502 Bad Gateway

**Symptom:** Router returns 502. Logs show "Routing msg X to TEXT parser" then "502". Response shows Jarvis conversational voice, not raw JSON.

**Root cause:** Hermes API server routes through the Jarvis agent, not a raw LLM proxy.

**Fix — Call OpenRouter directly:**
```python
OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions"
OPENROUTER_API_KEY = os.environ["OPENROUTER_API_KEY"]
```

### 3. Filling Mode Issue → "Unsupported filling mode"

**Symptom:** MT5 rejects with retcode 10030. OctaFX-Demo uses Request execution mode (trade_mode=4) for XAUUSD.

**Fix — FOK for market orders only:**
```python
if is_market:
    order["type_filling"] = mt5.ORDER_FILLING_FOK
```
Determine `is_market` from `final_type` (after 20-pip rule), not from `req.order_type`.

### 4. 20-Pip Rule: MARKET vs LIMIT

**Rule:** Entry ≥20 pips from market → LIMIT/STOP at entry price. Entry <20 pips from market → MARKET at current price.

**Pip sizes (critical — point ≠ pip!):**
| Symbol | `point` (MT5) | 1 Pip | 20 Pips | Notes |
|--------|---------------|-------|---------|-------|
| XAUUSD | 0.01 | **0.10** | **2.00** | Gold — 1 pip = 10 points |
| US30 | 0.01 | **1.00** | **20.00** | Dow Jones — 1 pip = 100 points |
| NAS100 | 0.01 | **1.00** | **20.00** | NASDAQ — 1 pip = 100 points |

⚠️ **The original code used `mt5.symbol_info(symbol).point` (0.01 for XAUUSD) as the pip size, making 20 pips = 0.20 instead of the correct 2.00.** This caused every entry-based signal to be treated as ≥20 pips away and sent as LIMIT even when it should have been MARKET.

**Fix — use a `PIP_SIZES` map (added Jul 2026):**
```python
PIP_SIZES = {"XAUUSD": 0.10, "US30": 1.0, "NAS100": 1.0}
pip_size = PIP_SIZES.get(symbol, mt5.symbol_info(symbol).point * 10)
twenty_pips = 20 * pip_size
```

**Bridge is the sole decider — router's order_type is ignored.** The Router converts ALL signals with entries to `order_type="limit"` (line 192-194 of router.py). This was historically a problem because the bridge's <20 pips branch checked `req.order_type == "market"` (which was never true after router's conversion). The fix: bridge ignores whatever the router sent and makes its own decision.
**Correct implementation in bridge (post-July 2026 fix, commit `d1c0768` + `c66517a`):**

```python
pip_size = PIP_SIZES.get(symbol, mt5.symbol_info(symbol).point * 10)
twenty_pips = 20 * pip_size
final_type = req.order_type
if req.entry is not None:
    if abs(req.entry - price) >= twenty_pips:
        entry = req.entry
        # Direction logic: entry below market = LIMIT, above = STOP for BUY (vice versa for SELL)
        if (req.action == "BUY" and req.entry < price) or (req.action == "SELL" and req.entry > price):
            final_type = "limit"
            log.info("entry=%.2f is %.1f pips from market=%.2f — LIMIT at %.2f",
                     req.entry, abs(req.entry - price) / pip_size, price, entry)
        else:
            final_type = "stop"
            log.info("entry=%.2f is %.1f pips from market=%.2f — STOP at %.2f",
                     req.entry, abs(req.entry - price) / pip_size, price, entry)
    else:
        if req.from_image:
            # Image signals: keep as pending order even if <20 pips from market
            entry = req.entry
            if (req.action == "BUY" and req.entry < price) or (req.action == "SELL" and req.entry > price):
                final_type = "limit"
                log.info("entry=%.2f is %.1f pips from market=%.2f — IMAGE LIMIT at %.2f",
                         req.entry, abs(req.entry - price) / pip_size, price, entry)
            else:
                final_type = "stop"
                log.info("entry=%.2f is %.1f pips from market=%.2f — IMAGE STOP at %.2f",
                         req.entry, abs(req.entry - price) / pip_size, price, entry)
        else:
            final_type = "market"
            entry = price
            log.info("entry=%.2f is <20 pips from market=%.2f — MARKET at %.2f",
                     req.entry, price, price)
```

Note: no `elif`, no `req.order_type == "market"` guard. Only two branches — both unconditional when entry is present.

**ALWAYS use `final_type` everywhere in the order building:**
- `is_market = final_type == "market"`
- `tmap[(req.action, final_type)]`
- `"price": price if is_market else entry`

#### Direction Trap: LIMIT vs STOP

The 20-pip rule sets `final_type="limit"`, but MT5 requires the correct order type based on entry position relative to market:

| Signal | Entry position | Should be | Wrong mapping |
|--------|---------------|-----------|---------------|
| BUY | Below market (entry < price) | BUY_LIMIT ✅ | — |
| BUY | Above market (entry > price) | BUY_STOP | BUY_LIMIT ❌ |
| SELL | Above market (entry > price) | SELL_LIMIT ✅ | — |
| SELL | Below market (entry < price) | SELL_STOP | SELL_LIMIT ❌ |

**Failure symptom:** A SELL with entry below market that's ≥20 pips away gets sent as `ORDER_TYPE_SELL_LIMIT`. MT5 rejects with **retcode=10015 (timeout)** because a SELL LIMIT price must be above the current bid — placing it below is invalid.

**Example from 2026-07-10:** Signal `SELL XAUUSD 4101.0 SL 4111.0 TP1 4085.0 TP2 4070.0` with bid=4103.04. Distance=2.04 (20.4 pips → ≥20). Bridge set `final_type="limit"` → `ORDER_TYPE_SELL_LIMIT` at 4101 (below market). MT5 returned retcode=10015: **timeout** — invalid order type for that price side.

**Fix (implemented 2026-07-10, commit `d1c0768`):** When entry is ≥20 pips from market, the bridge determines the correct MT5 order type by comparing entry to current market:

```python
if abs(req.entry - price) >= twenty_pips:
    entry = req.entry
    if (req.action == "BUY" and req.entry < price) or (req.action == "SELL" and req.entry > price):
        final_type = "limit"    # BUY_LIMIT or SELL_LIMIT
    else:
        final_type = "stop"     # BUY_STOP or SELL_STOP
```

The `tmap` dict then maps `(action, final_type)` to the correct MT5 constant. This is cleaner than conditionally mapping inside the type lookup — the decision is explicit in the 20-pip block.

### 5. Stale MT5 RPC Connection → order_send Returns None

**Symptom:** Bridge logs `order_send returned None for BUY XAUUSD lot=...`. Health check works. Direct test from container with same params works.

**Root cause — THREE issues:**

**Issue A: Cached RPC connection dies.** The `_mt5` global caching pattern reuses a stale connection.

**Fix — fresh connection per trade:**
```python
def get_mt5(retries: int = 30, delay: int = 2):
    """Create a fresh MT5 connection. No caching."""
    for attempt in range(1, retries + 1):
        try:
            client = MetaTrader5(host="localhost", port=8001)
            return client
        except Exception as e:
            time.sleep(delay)
    raise HTTPException(503, ...)
```

**Issue B: Multiple RPC connections conflict.** `daily_loss_exceeded()` and `calc_lot()` each create separate connections. Having 3+ concurrent RPC connections to the same MT5 terminal causes `order_send` to return `None` on some.

**Fix — pass the same client instance:**
```python
def daily_loss_exceeded(mt5_client=None) -> bool:
    mt5 = mt5_client if mt5_client else get_mt5()
    ...

def calc_lot(symbol, entry, sl, risk_pct, mt5_client=None) -> float:
    mt5 = mt5_client if mt5_client else get_mt5()
    ...

# In trade():
mt5 = ensure_mt5()
if daily_loss_exceeded(mt5_client=mt5):
    raise HTTPException(423, ...)
lot = calc_lot(symbol, entry, sl, risk_pct, mt5_client=mt5)
```

**Issue C (persistent): RPC `order_send` returns None from fresh connections.** The mt5linux rpyc RPC library has a bug where `order_send` loses its return value across the RPC boundary when called from inside FastAPI's process.

**Definitive fix — subprocess instead of direct RPC:**

Create `bridge/order_send.py`:
```python
"""Called as a subprocess to send MT5 orders — bypasses rpyc RPC issues."""
import sys, json
from mt5linux import MetaTrader5

order_json, login, password, server = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
order = json.loads(order_json)

c = MetaTrader5(host="localhost", port=8001)
c.initialize(login=int(login), password=password, server=server)
c.symbol_select(order["symbol"], True)
r = c.order_send(order)
if r:
    print(f"OK:{r.retcode}:{r.order}")
else:
    # Capture MT5's last_error before giving up (added Jul 2026)
    err = c.last_error() if hasattr(c, 'last_error') else ("unknown", "N/A")
    print(f"ERR:None:order_send returned None — last_error={err}")
```

The `last_error()` capture is critical — without it, a failing order just prints "ERR:None" with zero diagnostic information and you have to guess why MT5 rejected it.

In `bridge.py`, call via subprocess:
```python
import subprocess, json as _json
order_json = _json.dumps(order)
sp = subprocess.run(
    ["python3", "/app/order_send.py", order_json,
     os.environ["MT5_LOGIN"], os.environ["MT5_PASSWORD"], os.environ["MT5_SERVER"]],
    capture_output=True, text=True, timeout=30)
out = sp.stdout.strip()
if out.startswith("OK:"):
    parts = out.split(":")
    res = type("obj", (), {"retcode": int(parts[1]), "order": int(parts[2])})()
else:
    log.error("order_send subprocess failed: %s", sp.stderr[:300])
    res = None
```

**Dockerfile:**
```dockerfile
COPY bridge.py order_send.py .
```

### 6. Invalid Price (10015) for LIMIT Orders

**Symptom:** retcode=10015. MT5 rejects BUY LIMIT above market or SELL LIMIT below market.

**Fix:** MT5 validates direction — the 20-pip rule determines MARKET vs LIMIT. If retcode=10015, check whether the signal is stale (market moved past the entry).

### 7. Missing TP

**Fix:** Router prompt + Bridge both require TP. Empty `tp` array is rejected by Bridge.

### 8. Logging Format String Bug (bridge.py line ~236)

**Symptom:** When the subprocess returns None and bridge falls back to a direct `order_send` call, the log line produces `TypeError: not all arguments converted during string formatting`.

**Root cause:** The `log.info()` call on the fallback path had 7 arguments but only 2 `%s` placeholders:
```python
# BROKEN — 7 args for 2 placeholders
log.info("Sending order to MT5: action=%s type=%s ...",
         order.get("action"), order.get("type"), order.get("symbol"),
         order.get("volume"), order.get("price"), order.get("sl"), order.get("tp"))
```

**Fix — match format string to arguments:**
```python
# FIXED — 7 args, 7 placeholders
log.info("Sending order to MT5: action=%s type=%s symbol=%s vol=%s price=%s sl=%s tp=%s (fallback after subprocess None)",
         order.get("action"), order.get("type"), order.get("symbol"),
         order.get("volume"), order.get("price"), order.get("sl"), order.get("tp"))
```

## Logging Inside the Bridge

Add this before the order_send call to capture the exact payload:
```python
log.info("Sending order to MT5: action=%s type=%s symbol=%s vol=%s price=%s sl=%s tp=%s",
         order.get("action"), order.get("type"), order.get("symbol"),
         order.get("volume"), order.get("price"), order.get("sl"), order.get("tp"))
```

The primary log line (before subprocess) uses 7 placeholders. The fallback log line (after subprocess None) must use the SAME number of placeholders — not 2.

## Lot Sizing Formula

```
lot = 0.01 + floor(max(balance / 100, 0)) * 0.01
```

Clamped to `volume_min`/`volume_max`/`volume_step` of the symbol.

## Container Inspection Pattern

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}' --filter name=listener --filter name=router --filter name=bridge --filter name=mt5
docker inspect listener router bridge --format '{{.Name}}\nNetworks: {{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}\n---'
docker exec router cat /app/router.py
docker exec bridge cat /app/bridge.py
docker exec listener cat /app/listener.py
```