# MT5 Trade Copier — Error Reference

## MT5 Trade Return Codes

| Retcode | Constant | Meaning | Common Causes |
|---------|----------|---------|---------------|
| 10009 | TRADE_RETCODE_DONE | Success | — |
| 10014 | TRADE_RETCODE_REJECT | Rejected | Invalid params, market closed |
| 10015 | (varies by version) | Order rejected | Wrong order type for price direction (e.g. SELL_LIMIT below market), comment field issues |

## Bridge Pydantic 422 Validation Errors

When Router sends a request to Bridge with invalid field types:

### `sl: null` → 422 (`"Input should be a valid number"`)
- **Cause**: LLM parsed a BUY/SELL signal but returned `"sl": null` (couldn't find SL in text/image)
- **Fix (v2)**: Bridge `sl: float` → `sl: Optional[float] = None`. Old behavior: Pydantic rejected with 422.
- **Guard (v2)**: Router now rejects BUY/SELL with `sl: null` before forwarding. Also rejects confidence < 0.5.

### `tp` as single float → 422 (`"Input should be a valid list"`)
- **Cause**: LLM returned `"tp": 4036` (single float) instead of `"tp": [4036]` (list). The router's `sig.get("tp") or []` does NOT coerce — a truthy number like `4036` passes through as-is, and Pydantic rejects it.
- **Log pattern**: Router logs `parsed -> BUY conf=0.60`, bridge logs `422 Unprocessable Entity` with no handler code reached.
- **Fix (v3)**: Router must coerce: `raw_tp = sig.get("tp"); if isinstance(raw_tp, (int, float)): raw_tp = [raw_tp]; body["tp"] = raw_tp or []`

## Router Guard Behaviors (v3)

| Guard | Trigger | Response | Log pattern |
|-------|---------|----------|-------------|
| Missing SL | BUY/SELL parsed with `sl: null` | 200 OK, `reason: "SL missing from signal"` | `Rejected — SL missing, conf=0.20` |
| Low confidence | BUY/SELL parsed with `confidence < 0.5` | 200 OK, reason shown | `Rejected — confidence 0.20 below 0.5` |
| Tight SL (image) | Image signal with `abs(entry - sl) < 50 pips` | 200 OK + Telegram alert | `SL only X pips from entry (min 50)` |
| Non-image channel has image | Channel has image_data but NOT in IMAGE_CHANNEL_IDS | Routes to TEXT parser | `Channel [...] has image but not in IMAGE_CHANNEL_IDS` |
| Max per-channel trades | Channel has >= MAX_PER_CHANNEL_TRADES open positions | Bridge 429 | `max 5 trades reached for channel '...'` |
| Max global trades | MT5 has >= MAX_GLOBAL_TRADES total positions | Bridge 429 | `max global trades reached` |

## /close_channel Endpoint (v3, replaces /cancel_pending)

Bridge has `POST /close_channel` accepting `{"comment": "...", "symbol": "..."}`. Returns `{"closed": [...], "cancelled": [...]}`. Router calls this BEFORE each new BUY/SELL signal from the same channel.

**What it does:**
1. Closes ALL open positions (executed trades) matching the channel comment
2. Cancels ALL pending orders matching the channel comment

**Safety:** `comment` is required — empty/None raises 400. This prevents accidentally closing all MT5 positions.

**EOFError protection:** Both the positions and orders loops use `iterate_safe()` to handle rpyc RPC drops mid-iteration.

### mt5linux: No `order_delete()` — use `TRADE_ACTION_REMOVE` directly (FIXED 2026-07-20)

⚠️ **Gotcha**: mt5linux's `MetaTrader5` class does **not** have an `order_delete(ticket)` method. Calling it raises `AttributeError`.

To cancel a pending order, use `order_send()` with `action = TRADE_ACTION_REMOVE` (int value 3) via the **direct MT5 connection** (not subprocess):

```python
res = mt5.order_send({
    "action": mt5.TRADE_ACTION_REMOVE,
    "order": o.ticket,
    "symbol": o.symbol,
    "magic": MAGIC,
})
```

**Previous subprocess approach (deprecated):** The old code used `order_send.py` subprocess for TRADE_ACTION_REMOVE, which returned `retcode=10014` (`TRADE_RETCODE_INVALID_ORDER`) without actually removing orders. The direct `mt5.order_send()` call with `magic: MAGIC` resolves this. The subprocess is still used for trade placement (`/trade` endpoint) where it works correctly.

## rpyc EOFError — MT5 RPC Stream Drops Mid-Iteration

`mt5.orders_get()` and `mt5.positions_get()` return rpyc proxy objects tied to a live RPC connection. Accessing `o.comment` or `o.ticket` can raise `EOFError: stream has been closed`.

**Symptoms:** Bridge endpoint returns 500. Log shows `EOFError` accessing order attributes. Old orders survive. Subsequent trades create duplicates.

**Fix (v3):** Use `iterate_safe()` — catches EOFError, retries up to 3 times, returns partial results on total failure:

```python
def iterate_safe(mt5_collection, max_retries=3):
    result = []
    for attempt in range(1, max_retries + 1):
        try:
            items = list(mt5_collection) if mt5_collection else []
        except (EOFError, OSError, AttributeError) as e:
            log.warning("MT5 error: %s — retry %d/%d", e, attempt, max_retries)
            time.sleep(1)
            continue
        result = []
        for item in items:
            try:
                _ = item.ticket
                result.append(item)
            except (EOFError, AttributeError) as e:
                time.sleep(1)
                break
        else:
            return result
    return result  # partial results on final failure
```

## Duplicate Execution — Three-Layer Defense (v3)

### Root Cause
The listener registers both `NewMessage` and `MessageEdited` for the same channels. When a channel auto-edits a message (formatting, emoji, typo fix), both handlers fire for the same `message_id`. The bridge's `executed_signals` set is non-atomic — if the second request arrives before the first finishes, both pass.

### Log Pattern
```
04:02:51 router parsed msg 88218 -> BUY conf=1.00  (from 39734)
04:02:52 router parsed msg 88218 -> BUY conf=0.90  (from 39746)
04:02:52 bridge Sending order to MT5: ... (first batch)
04:02:53 bridge Sending order to MT5: ... (second batch)
```
Two different HTTP connections, same message_id, same channel, both forwarded.

### Layer 1 — Listener Text Hash (Root Cause)
```python
last_pushed = {}

@client.on(events.MessageEdited(chats=CHANNELS))
async def on_edit(event):
    key = (event.chat_id, event.message.id)
    current_hash = hash(event.message.message or "")
    if key in last_pushed and last_pushed[key][0] == current_hash:
        return  # text unchanged — skip
    ...
```

Only stores hash on SUCCESSFUL push. If push fails, hash isn't stored — next edit delivers the signal.

### Layer 2 — Bridge Atomic Lock (Race Condition)
```python
executed_lock = threading.Lock()

with executed_lock:
    if req.signal_id in executed_signals:
        return {"status": "duplicate_ignored"}
    executed_signals.add(req.signal_id)
```

### Layer 3 — Un-Burn on Failure (Recovery)
```python
try:
    # ... execute trade ...
except Exception:
    with executed_lock:
        executed_signals.discard(req.signal_id)
    raise
```

## Delete Event 422 — Missing `date` Field (FIXED 2026-07-20)

**Root cause (now fixed):** The listener's `on_delete` handler sent a minimal payload without the `date` field, which the router's `ListenerEvent` Pydantic model requires (`date: str` — no default).

**Fix applied:** Added `"date": datetime.now(timezone.utc).isoformat()` to the delete payload in `listener/listener.py`.

### Log Pattern (before fix)

```
listener  | Message 89040 deleted in chat -1001547583661
listener  | HTTP Request: POST http://router:8080/webhook "HTTP/1.1 422 Unprocessable Entity"
listener  | Push attempt 1 failed: Client error '422 Unprocessable Entity' ...
listener  | Push attempt 2 failed: ...
listener  | Push attempt 3 failed: ...
listener  | DEAD-LETTERED message 89040 — check failed_pushes.jsonl
```

Router side shows no delete processing — the 422 response is returned before any handler code runs.

### Root Cause

The listener's `on_delete` handler (line 134-138 in `listener/listener.py`) sends a minimal payload:

```python
payload = {
    "event": "delete",
    "channel_id": event.chat_id,
    "message_id": msg_id,
}
```

The router's `ListenerEvent` Pydantic model (line 82-92 in `router/router.py`) requires:

```python
class ListenerEvent(BaseModel):
    event: str
    channel_id: int
    channel_title: str = ""       # has default
    message_id: int
    reply_to_id: Optional[int] = None  # Optional
    text: str = ""                # has default
    has_media: bool = False       # has default
    image_data: Optional[str] = None   # Optional
    date: str                     # <-- NO DEFAULT — REQUIRED
```

The `date` field is missing from the delete payload, so Pydantic rejects the entire request with 422 before any handler code executes.

### Why It's a Problem

The router's `MessageDeleted` handler (lines 216-230) is designed to:
1. Call `channel_state.remove_signal_id()` to revert to the previous valid signal
2. Call `/close_channel` on the bridge to close MT5 positions and cancel pending orders

Because the delete events never reach the handler, **deleted signals are never cleaned up from MT5**. The user sees orphaned trades on MT5 with no corresponding message in Telegram.

### Concrete Example (2026-07-20)

- **Signal**: Message 89040 in Distinct Forex channel → `BUY XAUUSD 3980.0 SL 3975.0 TP 3990.0`
- **Action**: Router processed it, placed limit order at 3980.0, 1.14 lot
- **Delete**: Message was deleted from Telegram
- **Result**: Delete event dead-lettered with 422. Trade remains on MT5. User cannot find the signal in the Telegram channel.

### Fix Options

**Option A — Add `date` to the listener's delete payload (preferred, minimal change):**
```python
from datetime import datetime, timezone

@client.on(events.MessageDeleted(chats=CHANNELS))
async def on_delete(event):
    for msg_id in event.deleted_ids:
        payload = {
            "event": "delete",
            "channel_id": event.chat_id,
            "message_id": msg_id,
            "date": datetime.now(timezone.utc).isoformat(),
        }
        await push(payload)
```

**Option B — Make `date` optional in the router's Pydantic model:**
```python
date: str = ""  # add default
```

This is a broader change — every endpoint that uses `ListenerEvent` gets the new default, including new/edit events where `date` is always provided. Safe but less clean.

### Test

After the fix, delete events should show in router logs:
```
router | Delete event: channel=-1001547583661 msg=89040
router | Cleaned up MT5 for channel -1001547583661 after signal deletion
```

And `failed_pushes.jsonl` should stop accumulating delete entries.

## Deleted Signal Ghost Orders

**⚠️ FIXED (2026-07-20):** The `date` field was added to the listener's delete payload, so the `MessageDeleted` handler now runs correctly. Delete events reach the router, the channel state machine reverts to the previous signal, and `/close_channel` is called on the bridge to clean up MT5.

### Root Cause
A channel deletes a trade signal after the pipeline processed it. Without a working `MessageDeleted` handler, MT5 retains the orders. The real latest signal in the channel is now different from what MT5 shows.

### Log Pattern
```
Router logs: processed msg 88469, placed orders at 4020
Channel: msg 88469 deleted, msg 88466 (BUY 4000) is now the latest
MT5: still has 2 pending orders at 4020 (ghost orders)
```

### Fix (v3) — MessageDeleted Handler + State Machine Revert (APPLIED 2026-07-20)

The handler code exists in both listener and router. The `date` field was missing from the listener's delete payload, causing Pydantic 422 on every delete event. The fix added `date` to the delete payload.

**Listener side (fixed):**
```python
@client.on(events.MessageDeleted(chats=CHANNELS))
async def on_delete(event):
    for msg_id in event.deleted_ids:
        payload = {
            "event": "delete",
            "channel_id": event.chat_id,
            "message_id": msg_id,
            # MISSING: "date": datetime.now(timezone.utc).isoformat(),
        }
        await push(payload)
```

**Router side (works correctly when payload validates):**
```python
if ev.event == "delete":
    removed = channel_state.remove_signal_id(str(ev.channel_id), ev.message_id)
    if removed:
        comment = channel_state.get_channel_title(str(ev.channel_id)) or str(ev.channel_id)
        await c.post(f"{BRIDGE_URL}/close_channel", json={"comment": comment}, ...)
```

## Docker Volume Pitfall

**Never mount a Docker volume at the application directory (e.g., `/app/`).** The empty volume overwrites the app code — the container won't start.

**Fix:** Use a dedicated directory for persistent data:
```yaml
router:
  environment:
    - CHANNEL_STATE_FILE=/data/channel_state.json
  volumes:
    - router_data:/data/   # NOT /app/
```

## Diagnostic Command

```bash
# Check if MT5 is alive and get current prices
docker exec bridge python3 -c "
from mt5linux import MetaTrader5
import os
c = MetaTrader5(host='localhost', port=8001)
c.initialize(login=int(os.environ['MT5_LOGIN']), password=os.environ['MT5_PASSWORD'], server=os.environ['MT5_SERVER'])
c.symbol_select('XAUUSD', True)
t = c.symbol_info_tick('XAUUSD')
acct = c.account_info()
print(f'XAUUSD ask={t.ask} bid={t.bid}')
print(f'Balance={acct.balance} Open positions={len(c.positions_get() or [])}')
print(f'last_error: {c.last_error()}')
"
```

## Order Debugging

When an order fails, trace through:
1. **Router log**: what did the LLM/regex parse? (action, entry, sl, tp, confidence)
2. **Bridge log**: what was the 20-pip decision? (LIMIT, STOP, or MARKET)
3. **Bridge log**: what order was actually sent? (action, type, price, sl, tp, comment)
4. **order_send subprocess**: what did the subprocess return? (OK:retcode:order or ERR:None with last_error)
5. **MT5 log**: check `last_error()` for the rejection reason

## Health Check

```bash
# Quick health
curl -s http://localhost:8002/health  # from bridge container
# Expected: {"mt5_connected":true,"balance":4206.35}
```

## Rebuild & Restart

```bash
# Single service
docker compose up -d --build bridge

# All services
docker compose up -d --build
```

## Git

```bash
git add -A
git commit -m "descriptive message"
git push
```