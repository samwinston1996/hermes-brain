# Reconciliation Architecture — Channel Signal vs MT5 State (v3)

## Core Principle

**The latest non-deleted signal in each Telegram channel is the ground truth for that channel's trades in MT5.** The pipeline reconciles every new signal against the per-channel state machine on registration.

## v3 Implementation Flow

The v3 pipeline implements reconciliation as part of the standard trade flow. No separate "fetch latest channel message" step needed — the state machine is the source of truth:

```
New signal arrives at router
  ↓
1. Router parses (regex or LLM)
2. Router calls POST /close_channel {comment: channel_title}
   → Bridge closes ALL positions + cancels ALL pending matching this channel
3. Router calls POST /trade {signal details}
4. On 200 response: router updates channel_state via channel_state.update()
```

This handles in a single `/close_channel` call:
- **Same direction** → pending orders cancelled, new pending placed
- **Opposite direction** → existing executed trades closed first, then new trade placed
- **First signal from channel** → no-op on /close_channel (nothing matches)

## Per-Channel State Machine

```python
# File: router/channel_state.py — Thread-safe, JSON-persisted

class ChannelState:
    def __init__(self):
        self._data: dict[str, dict] = {}
        self._lock = threading.Lock()
        self._load()  # from /data/channel_state.json

    def update(self, channel_id, signal):
        """Push current → previous, set new current."""
        with self._lock:
            entry = self._data.get(cid) or self._default()
            entry["previous"] = entry["current"]
            entry["current"] = {
                "msg_id": signal["msg_id"],
                "channel_title": signal["channel_title"],
                "action": signal["action"],
                "entry": signal["entry"],
                "sl": signal["sl"],
                "tp": signal["tp"],
                "order_type": signal["order_type"],
                "from_image": signal["from_image"],
                "timestamp": signal["timestamp"],
            }
            entry["channel_title"] = signal["channel_title"]  # persists after revert
            self._data[cid] = entry
            self._save()  # atomic write: tmp → os.replace

    def remove_signal_id(self, channel_id, msg_id) -> bool:
        """Revert to previous signal on delete. Returns True if removed."""
        with self._lock:
            entry = self._data.get(str(channel_id))
            if entry and entry["current"] and entry["current"]["msg_id"] == msg_id:
                if entry["previous"]:
                    entry["current"] = entry["previous"]
                    entry["previous"] = None
                else:
                    entry["current"] = None
                self._save()
                return True
            return False

    def get_channel_title(self, channel_id) -> str:
        """Return last known title — survives signal deletions and reverts."""
        with self._lock:
            entry = self._data.get(str(channel_id))
            return entry.get("channel_title", "") if entry else ""
```

## Listener Changes

### Message Deleted Handler

```python
@client.on(events.MessageDeleted(chats=CHANNELS))
async def on_delete(event):
    for msg_id in event.deleted_ids:
        payload = {
            "event": "delete",
            "channel_id": event.chat_id,
            "message_id": msg_id,
        }
        await push(payload)
```

Router's webhook handler checks `ev.event == "delete"` first (before any text/image processing), calls `channel_state.remove_signal_id()` to revert, retrieves the channel title via `get_channel_title()`, then calls `/close_channel` to clean up MT5.

### Text Hash Dedup (stops duplicates at source)

```python
last_pushed: dict[tuple[int, int], tuple[int, float]] = {}

@client.on(events.MessageEdited(chats=CHANNELS))
async def on_edit(event):
    key = (event.chat_id, event.message.id)
    current_hash = hash(event.message.message or "")
    if key in last_pushed and last_pushed[key][0] == current_hash:
        return  # text unchanged → skip (Telegram auto-formatting)
    payload = await make_payload(event, "edit")
    if await push(payload):
        last_pushed[key] = (current_hash, time.time())
```

Push failure safety: hash is only stored on SUCCESSFUL push. If push dead-letters (router down), the hash isn't stored — the next edit will push the signal through.

## Bridge Changes

### /close_channel Endpoint (replaces /cancel_pending)

```python
@app.post("/close_channel")
def close_channel(req: CloseChannelRequest, authorization: str = Header(None)):
    if not req.comment:
        raise HTTPException(400, "comment is required — refusing to close all")
    mt5 = ensure_mt5()
    comment = sanitize_comment(req.comment)
    closed, cancelled = [], []

    for p in iterate_safe(mt5.positions_get()):
        if comment not in sanitize_comment(p.comment or ""):
            continue
        # Close position via TRADE_ACTION_DEAL
        ...

    for o in iterate_safe(mt5.orders_get()):
        if comment not in sanitize_comment(o.comment or ""):
            continue
        # Cancel pending via TRADE_ACTION_REMOVE subprocess
        ...

    return {"status": "done", "closed": closed, "cancelled": cancelled}
```

Critical safety: `comment` is required. No-arg calls are rejected with 400 to prevent accidentally closing ALL MT5 positions.

### iterate_safe() — rpyc EOFError Protection

```python
def iterate_safe(mt5_collection, max_retries=3):
    result = []
    for attempt in range(1, max_retries + 1):
        try:
            items = list(mt5_collection) if mt5_collection else []
        except (EOFError, OSError, AttributeError) as e:
            log.warning("MT5 collection error: %s — retry %d/%d", e, attempt, max_retries)
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

### Atomic Lock for executed_signals

```python
executed_lock = threading.Lock()

with executed_lock:
    if req.signal_id in executed_signals:
        return {"status": "duplicate_ignored"}
    executed_signals.add(req.signal_id)

try:
    # ... execute trade ...
except Exception:
    with executed_lock:
        executed_signals.discard(req.signal_id)  # un-burn on failure
    raise
```

## Per-Channel vs Global Limits

| Parameter | v2 (global) | v3 (per-channel) |
|-----------|-------------|------------------|
| MAX_PER_CHANNEL_TRADES | 5 total across all channels | 5 per channel |
| MAX_GLOBAL_TRADES | (didn't exist) | 25 (safety net) |
| Daily loss cap | Global | Global (protects account) |
| Opposite-direction close | No | Yes — /close_channel before /trade |

## Handling Deleted Signals (Real Example)

**July 17, 2026 — Distinct Forex msg 88469 (BUY 4020) deleted after processing**

With v3, when the delete event arrived:
1. Router received `{"event": "delete", "channel_id": -1001547583661, "message_id": 88469}`
2. `channel_state.remove_signal_id(-1001547583661, 88469)` → reverted to msg 88466 (BUY 4000)
3. `get_channel_title(-1001547583661)` → "Distinct Forex"
4. `POST /close_channel {"comment": "Distinct Forex"}` → cleaned up the ghost 4020 orders in MT5
5. State machine now shows msg 88466 as the current valid signal