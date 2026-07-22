---
name: trade-copier-pipeline
description: Multi-container MT5 trade copier — Telegram channel → Listener → Router (LLM) → Bridge (risk gates) → MT5. Docker Compose stack on VPS.
trigger: User mentions trade-copier, trade copier, MT5 pipeline, signal parsing, trade signals, OctaFX, XAUUSD copier, or chart images
lang: en
---

# trade-copier-pipeline

Multi-container MT5 trade copier: Telegram channel → Listener → Router (LLM parse) → Bridge (risk gates) → MT5. All config via `.env`, orchestrated with Docker Compose.

## Architecture (v3)

```
[Telegram Channel]
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│ LISTENER                                                     │
│ • NewMessage → push to router + store text_hash              │
│ • MessageEdited → skip if text_hash unchanged → push + update│
│ • MessageDeleted → push delete event                         │
│ • Image download → only for IMAGE_CHANNEL_IDS                │
└─────────────────────────┬───────────────────────────────────┘
                          │ POST /webhook
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ ROUTER                                                       │
│                                                              │
│  1. Delete event? → revert channel state, /close_channel     │
│  2. Image channel?  → Gemini vision LLM                      │
│  3. Text channel?                                            │
│       ├─ Regex pre-filter (Distinct Forex, BotX formats)    │
│       │   → direct parse — zero LLM cost                     │
│       └─ No regex match → DeepSeek LLM fallback              │
│                                                              │
│  4. TP type coercion (float → list)                          │
│  5. Forward valid signal to bridge (trade FIRST, race price) │
│  6. /close_channel on bridge — cleanup old trades            │
│  7. Update per-channel state machine (channel_state.py)      │
└─────────────────────────┬───────────────────────────────────┘
                          │ POST /trade, POST /close_channel
                          ▼
┌─────────────────────────────────────────────────────────────┐
│ BRIDGE                                                       │
│                                                              │
│  /close_channel:                                              │
│    • Close ALL open positions matching channel comment        │
│    • Cancel ALL pending orders matching channel comment       │
│    • Uses iterate_safe() for rpyc EOFError protection         │
│                                                              │
│  /trade:                                                      │
│    • Atomic executed_signals lock (threading.Lock)            │
│    • Per-channel MAX_PER_CHANNEL_TRADES cap                   │
│    • Global MAX_GLOBAL_TRADES safety net                      │
│    • Stale signal check, daily loss check                     │
│    • Order execution via order_send.py subprocess             │
└─────────────────────────┬───────────────────────────────────┘
                          │ order_send
                          ▼
                          MT5
```

## Key Rules

### 20-Pip Rule (Bridge, not Router)
- Distance = `abs(entry - current_market_price)`, threshold = `20 * pip_size`
- **≥20 pips from market → pending order** (LIMIT or STOP based on direction):
  - BUY: entry below market = **BUY_LIMIT**, entry above = **BUY_STOP**
  - SELL: entry above market = **SELL_LIMIT**, entry below = **SELL_STOP**
- **<20 pips from market → MARKET execution** (unless `from_image` flag is True)

### PIP_SIZES Map
`mt5.symbol_info().point` is NOT the pip size. Use the explicit map:
- XAUUSD = 0.10, US30 = 1.0, NAS100 = 1.0
- Defined in `bridge/bridge.py`

### Channel Routing & IMAGE_CHANNEL_IDS
- `IMAGE_CHANNEL_IDS` env var (comma-separated channel IDs) controls which channels process images for chart parsing
- **Only Trade.inn Forex** is an image channel. All others (BotX, XAUUSD ANALYSIS TEAM, etc.) are TEXT-only
- Non-image channels that send images (decorative screenshots): **ignore `image_data`**, route to TEXT parser using the message text
- This prevents decorative Telegram screenshots from being misparsed as chart signals

### Regex Pre-Filter for Known Text Formats

The router has a `parse_with_regex()` function that runs BEFORE the LLM call for text channels. It matches known signal formats with zero LLM token cost:

**Distinct Forex format:**
```
#XAUUSD BUY 4000
TP 4004
TP 4008
SL 3990
```
Regex: `#?XAUUSD\s+(BUY|SELL)\s+(\d+\.?\d*)` + `TP\s+(\d+\.?\d*)` + `SL\s+(\d+\.?\d*)`

**BotX format:**
```
BUY XAUUSD
ENTRY: 4120
SL: 4110
TP: 4137
```
Regex: `(BUY|SELL)\s+XAUUSD` + `ENTRY:\s*(\d+\.?\d*)` + `SL:\s*(\d+\.?\d*)` + `TP\d?:?\s*(\d+\.?\d*)`

### Result post guard:** Messages containing `HIT`, `✅`, `❌`, `😄`, `💯`, or `PROFIT` automatically return `None` (fall through to LLM) — these are result screenshots, not signals.

**Fallback:** If regex doesn't match, the router falls back to the DeepSeek LLM parser. No accuracy loss — the regex is conservative (only returns high-confidence parses).

**Routing flow:**
```
Message arrives
  ↓
Channel in IMAGE_CHANNEL_IDS? → YES → Image LLM (Gemini), no pre-filter
  ↓ NO
Regex pre-filter → Match? → direct parse (conf=1.0)
                → No match? → LLM fallback
                → Result keywords? → LLM fallback
```

### Signal Validation Guards (Router, after LLM/Regex parse)

- **Missing SL**: If BUY/SELL signal has `sl: null` after LLM parse → reject immediately (no forward to bridge)
- **Low confidence**: If BUY/SELL signal has `confidence < 0.5` → reject (incomplete signal)
- **Image SL too tight**: For image signals, if |entry - sl| < 50 pips → reject (likely results screenshot, not a signal)
- **Distinct Forex single-TP rejection**: For channel `-1001547583661` (Distinct Forex), BUY/SELL signals with only 1 TP are rejected as marketing. Distinct Forex signals always have 4+ TPs. Single-TP signals from this channel are marketing posts that the LLM incorrectly parses as valid trades. Trade.inn Forex (image channel) is exempt — it always has single-TP signals.
- **TP as single float (422 guard)**: If the LLM returns `tp` as a single number (e.g., `"tp": 4036`) instead of a list (`"tp": [4036]`), the router must coerce it: `raw_tp = sig.get("tp"); if isinstance(raw_tp, (int, float)): raw_tp = [raw_tp]`. Without coercion, Pydantic on the bridge rejects with 422.

### Per-Channel State Machine

The router maintains a per-channel state machine at `router/channel_state.py` that tracks the latest valid signal for each channel. This replaces ad-hoc dedup and supersession logic with a single coherent system.

**State schema (JSON-persisted):**
```python
{
    channel_id: {
        "current": {
            "msg_id": 88466,
            "channel_title": "Distinct Forex",
            "action": "BUY",
            "entry": 4000.0,
            "sl": 3990.0,
            "tp": [4004.0, 4008.0, 4012.0, 4016.0],
            "order_type": "limit",
            "from_image": False,
            "timestamp": "2026-07-17T06:24:06+00:00",
        },
        "previous": {...} | None,  # previous signal for revert on delete
        "channel_title": "Distinct Forex",  # persists after revert
    }
}
```

**Key methods:**
- `update(channel_id, signal)` → pushes current → previous, sets new current
- `remove_signal_id(channel_id, msg_id)` → reverts to previous on delete
- `get_channel_title(channel_id)` → returns last known title (survives revert)
- `current_signal(channel_id)` → returns current signal dict or None

**Thread safety:** All state mutations are protected by `threading.Lock()`. JSON persistence uses atomic write (tmp file → `os.replace`).

**Persistence:** State file at `CHANNEL_STATE_FILE` (default: `/data/channel_state.json`). Persisted via Docker named volume (`router_data:/data/`) — survives container restarts.

### ⚠️ Compose: `env_file` vs `environment` variable substitution override

When a service has both `env_file: .env` and `environment:` with a variable reference like `OPENROUTER_API_KEY=${OPENROUTER_API_KEY}`, Docker Compose's variable substitution can **override** the `env_file` value to empty if the `.env` file is missing from the compose project directory.

```yaml
# DANGER — this pattern
router:
    env_file: .env
    environment:
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY}  # ← overrides env_file to empty if .env is missing
```

**Why:** `${OPENROUTER_API_KEY}` is interpolated by Docker Compose from the project's `.env` file (same directory as docker-compose.yml). If that file doesn't exist, the variable resolves to empty string, which **overrides** the value loaded by `env_file: .env`.

**Fix — remove the redundant variable from `environment:`:**
```yaml
router:
    env_file: .env
    environment:
      # Do NOT also list OPENROUTER_API_KEY here — env_file already loads it
      - VISION_MODEL=${VISION_MODEL:-google/gemini-3.1-flash-lite-preview}
      - TEXT_MODEL=${TEXT_MODEL:-deepseek/deepseek-v4-flash}
```

Or, ensure the `.env` file always exists in the compose project directory with the correct value.

**Symptoms when this breaks:** Router container has `OPENROUTER_API_KEY=` empty. Every LLM parse call returns 502. Listener dead-letters messages. Only regex-pre-filtered signals (Distinct Forex) still work.

### ⚠️ File permission: root-owned files cause build/runtime failures

Files owned by `root` with `600` permissions (`-rw-------`) inside the project directory can break Docker builds and container runtime. Symptoms:

- **Build succeeds** but image doesn't contain the file content
- **Container crashes** with `ImportError: cannot import name 'channel_state' from 'channel_state'` — file exists but is empty/corrupted

**Fix:** Ensure project source files are world-readable:
```bash
chmod 644 router/channel_state.py
# Or fix recursively via Docker:
docker run --rm -v /home/trader/workspace/projects/trade-copier:/mnt alpine chmod -R a+r /mnt/router/ /mnt/bridge/
```

### ⚠️ Docker-in-Docker: volume paths resolve from container, not host

When `docker compose` runs **inside** the Hermes container (via Docker socket), relative paths in `volumes:` resolve to the container's filesystem, not the host's. The Docker daemon on the host interprets them from the host's root — so `./mt5/start.sh` becomes `/opt/data/trade-copier/mt5/start.sh` which doesn't exist on the host.

**Symptoms:** `Error: not a directory: Are you trying to mount a directory onto a file?` when starting containers with bind-mounted files.

**Fix options:**
1. Run `docker compose` from the host directly (SSH in), not from inside the container
2. Use absolute host paths in the compose file
3. For persistent containers (mt5), start with `docker run` using correct host paths

**Docker volume pitfall:** Mounting a Docker volume at `/app/` (where app code lives) erases the application files. Always use a dedicated directory like `/data/` for state persistence.

### Signal Supersession & Reconciliation (per-channel)

The latest signal from a channel is always the ground truth. When a new BUY/SELL signal arrives, the pipeline must reconcile MT5 state against it. The order matters: **place the new trade FIRST** (race for best price), then clean up old trades.

#### User-facing: "Why did my trade close without hitting TP/SL?"

**Most likely cause: the fix below wasn't applied yet (pre-v3.1).** Before `exclude_tickets`, `/close_channel` matched the just-placed trade's comment (channel name) and closed it seconds after opening.

**If the fix IS applied and a trade still closes early:**
- Another signal from the same channel arrived → old trade was superseded (expected)
- Delete event on the signal triggered → state machine reverted, all positions closed (expected)
- Opposite-direction signal from same channel → pipeline reversed the position (expected)
- None of the above → investigate broker/MT5 (margin call, stop-out, expiry)

#### Flow

```
New signal arrives from channel
  ↓
  → Fetch latest valid signal from channel (skip deleted messages)
  → If mismatch: signal was superseded or deleted → STOP
  → Place the new trade FIRST (race for price)
  → Extract ticket IDs from trade response (for exclude_tickets)
  → Then clean up old trades from the same channel:
      → Cancel pending orders (comment match, via /close_channel)
      → If new signal is opposite direction to existing executed trades:
          → Close those trades
  → Update per-channel signal tracker
```

#### Implementation Notes

- Router calls `POST /close_channel` on Bridge with `{"comment": "<channel_title>"}` AFTER placing the new trade
- Router **must** pass `exclude_tickets` from the trade response to prevent self-closing the just-placed trade. Without it, every new trade closes itself within seconds.
- The `/close_channel` endpoint closes ALL open positions + cancels ALL pending orders matching the channel comment, **except** those whose ticket is in `exclude_tickets`
- Track `MAX_OPEN_TRADES` per channel, not globally
- See `references/reconciliation-architecture.md` for full design details

#### ⚠️ `/close_channel` — rpyc Cache + Subprocess Issues (FIXED 2026-07-20)

The `/close_channel` endpoint had two bugs that prevented MT5 cleanup:

**Bug A (orders not cancelled):** The `order_send.py` subprocess with `TRADE_ACTION_REMOVE` returned `retcode=10014` for every pending order but never actually removed them.

**Bug B (positions not closed):** `mt5.positions_get()` returned empty on the first call due to stale rpyc cache; the positions loop silently ran zero iterations.

**Fix applied:**
1. Use direct `mt5.order_send()` (not subprocess) for cancelling orders — added `magic: MAGIC` to the request
2. Retry `positions_get()` 3 times with 1s delay to warm the rpyc cache before iterating
3. Check retcodes against `TRADE_RETCODE_DONE` (10009) — log warnings on non-DONE retcodes

#### ⚠️ Cancel Pending Implementation Caveats

1. **mt5linux has NO `order_delete()` method** — Calling `mt5.order_delete(ticket)` raises `AttributeError`. Must use `order_send()` with `action = TRADE_ACTION_REMOVE` (int 3) instead.

2. **Direct `mt5.order_send()` works (FIXED 2026-07-20)** — Previously used a subprocess via `order_send.py` for TRADE_ACTION_REMOVE, which returned `retcode=10014` without actually removing orders. Fixed by using direct `mt5.order_send()` with `magic: MAGIC` added to the request.

#### ⚠️ rpyc EOFError — MT5 RPC stream drops mid-iteration

`mt5.orders_get()` and `mt5.positions_get()` return rpyc proxy objects tied to a live RPC connection. By the time you iterate and access `o.comment`, the connection may have closed (`EOFError: stream has been closed`). The endpoint crashes with 500, no pending orders are cancelled, and subsequent trades create duplicates.

**Symptoms:** `POST /cancel_pending` or `POST /close_channel` returns 500. Old pending orders survive. Bridge logs show `EOFError: stream has been closed` accessing order attributes.

**Fix:** Use `iterate_safe()` wrapper that catches EOFError, retries up to 3 times, and returns partial results on total failure:

```python
def iterate_safe(mt5_collection, max_retries=3):
    """Safely iterate rpyc proxy objects, retrying on EOFError."""
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
                _ = item.ticket  # force RPC attribute access
                result.append(item)
            except (EOFError, AttributeError) as e:
                log.warning("MT5 item error: %s — retry %d/%d", e, attempt, max_retries)
                time.sleep(1)
                break
        else:
            return result
    return result  # partial results on final failure
```

Use this for ALL rpyc iteration: `for p in iterate_safe(mt5.positions_get()):` and `for o in iterate_safe(mt5.orders_get()):`.

#### ⚠️ Atomic Lock for executed_signals Set

The `executed_signals` dedup set has a race condition when two requests arrive concurrently. Fix with a threading lock:

```python
executed_signals: set[str] = set()
executed_lock = threading.Lock()

# On trade:
with executed_lock:
    if req.signal_id in executed_signals:
        return {"status": "duplicate_ignored"}
    executed_signals.add(req.signal_id)

try:
    # ... execute trade ...
    if all_ok:
        return {"status": "executed", ...}
    raise HTTPException(500, ...)
except Exception:
    with executed_lock:
        executed_signals.discard(req.signal_id)  # un-burn on failure
    raise
```

The `discard` in the except block ensures failed trades can be retried (signal_id isn't permanently burned).

### Image Chart Signals (Gemini Vision)
- **Only Trade.inn Forex channel** processes images. Controlled via `IMAGE_CHANNEL_IDS` env var.
- **Keywords**: Genuine Trade.inn signals contain bullish/bearish directional keywords in the image/caption (e.g. **"BULLISH SETUP"**, **"BEARISH SETUP"**, **"VIEW BULLISH"**, **"VIEW BEARISH"**, **"BULLISH"**, **"BEARISH"**, **"BUY SETUP"**, **"SELL SETUP"**, or any text clearly indicating a trade signal direction). Absence of any directional keyword = results screenshot or commentary → IGNORE.
- **Two-zone layout**: RED zone (SL at far edge) + Grey zone (profit zone, TP at far boundary)
- **Entry** = horizontal border line between RED and Grey zones
- **Direction**: RED above + Grey below = SELL. Grey above + RED below = BUY
- Always `order_type = "limit"`, always XAUUSD
- **All three prices read from the right-hand panel** (boxed indicators), not Y-axis labels. Order of definition follows level-first (price level before visual cue):
  - **SL price** = the RED box, horizontally aligned with the far edge of the RED zone
  - **ENTRY price** = the GREY box, horizontally aligned with the border line between zones
  - **TP price** = the GREY box, horizontally aligned with the far boundary of the Grey zone
- **There may be multiple boxed prices on the right panel.** Only use the ones matching the alignment rules above. Ignore all other boxes.
- **Do not guess prices from the right panel labels.** The boxes aligned with the zone boundaries are the true SL, ENTRY, and TP prices.
- Router prepends **extra TP at 100 pips** (10.00) in trade direction as TP1
- `from_image: True` flag tells bridge to keep pending order type
- **SL must be ≥50 pips from entry** — tighter SL means results screenshot, not signal

> **Anti-hallucination pattern**: When iterating on vision prompts, add (1) level-first naming so the LLM knows *what* to find before *how* to find it, (2) "ignore all other X" to filter false positives, (3) "do not guess" authority statement as a final guard. This pattern was refined across 3 iterations and fixed entry price misreadings.

### MT5 Comment Field (Critical)
- **Channel name only** — e.g. "BotX channel", not concatenated with signal_id
- Max 31 chars
- No pipe `|` character — pipe causes `order_send` to silently return None
- Signal_id leaking into comment → MT5 error code -2: `'Invalid "comment" argument'`

### Lot Sizing

Step-based formula in `bridge/bridge.py`:

```python
step = max(int(balance / 100), 0)
lot = 0.01 + step * 0.01
```

This produces a single linear lot size for the entire position, then splits it across TP targets:

```python
lot_each = round(max(volume_min, lot / len(tps)), 2)
```

**What this yields at different balances:**

| Balance | Lot (1 TP) | Lot (2 TPs) | Lot (4 TPs) |
|---------|-----------|-------------|-------------|
| $500    | 0.06      | 0.03        | 0.02        |
| $2,000  | 0.21      | 0.11        | 0.05        |
| $5,000  | 0.51      | 0.26        | 0.13        |
| $10,000 | 1.01      | 0.51        | 0.25        |
| $11,300 | 1.14      | 0.57        | 0.29        |

**⚠️ Risk note:** This is a pure balance-scaling formula with no account of SL distance, win rate, or risk-per-trade %. At higher balances, 1+ lot on XAUUSD is aggressive — a 50-pip SL at 1.14 lot risks ~$570 (5% of a $11.3K account) in a single trade. The user has flagged this as unusual/unexpected.

### Risk Gates (Deterministic, LLM cannot bypass)
- Daily loss cap (MAX_DAILY_LOSS_PERCENT)
- Per-channel max open trades (each channel has its own MAX_OPEN_TRADES budget)
- Opposite-direction close: if new signal is opposite direction of existing trade from same channel, close existing trade first
- SL on wrong side rejected
- Duplicate signal dedup via `executed_signals` set
- Stale signal check (>0.5% market move since signal)

### Listener: Deleted Message Handling

The listener registers `NewMessage`, `MessageEdited`, and `MessageDeleted` events. When a channel deletes a message that the pipeline already processed, the delete handler fires and pushes a `{"event": "delete", "channel_id": ..., "message_id": ...}` payload to the router. The router's state machine (`channel_state.py`) is meant to revert to the previous valid signal and call `/close_channel` on the bridge.

**Implementation:**
```python
@client.on(events.MessageDeleted(chats=CHANNELS))
async def on_delete(event):
    for msg_id in event.deleted_ids:
        payload = {"event": "delete", "channel_id": event.chat_id, "message_id": msg_id}
        await push(payload)
```

**⚠️ Fix (2026-07-20):** The delete payload was missing the `date` field, causing 422 and dead-lettering. Fix applied: `"date": datetime.now(timezone.utc).isoformat()` added to the delete payload in `listener/listener.py`.

**Fix:** Add `date` to the delete payload in `listener/listener.py` (`datetime.now(timezone.utc).isoformat()`), or make `date` optional in the router's `ListenerEvent` model with a default of `""`.

### Listener: Duplicate Execution Prevention (Text Hash Tracking)

The listener registers both `NewMessage` and `MessageEdited`. When a channel posts and auto-edits a message (formatting, emoji, typo fix), both handlers fire. The fix is **three-layer defense**:

**Layer 1 — Listener hash dedup (root cause fix):**
Track `(chat_id, msg_id) → text_hash`. On `MessageEdited`, skip if the text hash matches the stored hash from the original `NewMessage` push. Only store the hash on SUCCESSFUL push (returns `True` from `push()`).

```python
last_pushed: dict[tuple[int, int], tuple[int, float]] = {}

@client.on(events.NewMessage(chats=CHANNELS))
async def on_new(event):
    payload = await make_payload(event, "new")
    if await push(payload):
        key = (event.chat_id, event.message.id)
        last_pushed[key] = (hash(event.message.message or ""), time.time())

@client.on(events.MessageEdited(chats=CHANNELS))
async def on_edit(event):
    key = (event.chat_id, event.message.id)
    current_hash = hash(event.message.message or "")
    if key in last_pushed and last_pushed[key][0] == current_hash:
        return  # text unchanged — skip
    payload = await make_payload(event, "edit")
    if await push(payload):
        last_pushed[key] = (current_hash, time.time())
```

**Layer 2 — Bridge atomic lock (race condition fix):**
Threading.Lock around the `executed_signals` check+add prevents the race where two requests arrive simultaneously.

**Layer 3 — try/except un-burn (recovery fix):**
If the trade fails, `executed_signals.discard()` frees the signal_id so the next attempt can retry.

**Evidence:** Before the fix, every message appeared twice in router logs. After the fix, only unique text changes trigger a push.

## Debugging** — a single error can manifest in any of them. Never only look at the one you think is broken:

```bash
# Full scope: show ALL container logs simultaneously
cd ~/workspace/projects/trade-copier
docker compose logs --tail=100 router bridge listener mt5
```

| Container | What to look for |
|-----------|-----------------|
| listener | Push failures, image download issues, channel discovery |
| router | LLM parse results, guard triggers, forward to bridge |
| bridge | order_send results, retcodes, 20-pip decisions |
| mt5 | Connection/disconnection activity |

```bash
# Quick health check
docker compose ps
```

**Known issue — duplicate parses (RESOLVED in v3):** Before v3, every message appeared twice in router logs — the listener had both `NewMessage` and `MessageEdited` handlers, and when a channel auto-edited a message both fired. The v3 text hash dedup (`last_pushed` dict tracking `(chat_id, msg_id) → text_hash`) resolved this: `MessageEdited` now skips if the hash matches the original `NewMessage` push. The bridge's atomic lock on `executed_signals` provides a second layer. See `references/errors-and-diagnostics.md` → "Duplicate Execution".

**Known issue — 422 on valid signals:** If the router logs `BUY conf=0.60` but bridge returns 422, the LLM likely returned `tp` as a single number instead of a list. See `references/errors-and-diagnostics.md` → "Bridge Pydantic 422" → "tp as single float".

**Known issue — delete event 422 (FIXED 2026-07-20):** The listener's delete payload was missing the `date` field, causing 422. Fix applied — `date` field added to the delete payload. See `Listener: Deleted Message Handling` above for the fix.

## Workflow (Consent-First)

1. **Diagnose** — read `.env`, check logs **on ALL 4 containers** (`docker compose logs --tail=50 router bridge listener mt5`), check health endpoint
2. **Report** findings to user — explain what is wrong, what the fix is, and why
3. **Get explicit written go-ahead** before touching any code — never apply fixes autonomously
4. **Apply** the fix to **source files**, then rebuild and restart: `docker compose up -d --build <service>`
5. **Verify** the service is up: `docker compose ps`
6. **Push** to git after each verified fix

### ⚠️ Pitfall: Don't edit files inside running containers

Editing files inside running containers (`docker exec <container> sed -i ...` or `docker exec <container> python3 -c "..."`) makes the fix **live but ephemeral**. It will be lost on:
- Container restart
- Image rebuild
- Container migration

Always patch the **source files** on disk, then rebuild the image. Container edits are only acceptable for quick debugging to confirm a fix works before committing to the source.

## Containers

| Service | Path | Notes |
|---------|------|-------|
| listener/ | `listener/listener.py` | Telethon userbot, watches TG_CHANNELS |
| router/ | `router/router.py` | Dual LLM parser, FastAPI on :8080 |
| bridge/ | `bridge/bridge.py`, `bridge/order_send.py` | Risk gates, network_mode: service:mt5 |
| data/ | `data/mt5/` | MT5 config + Python env inside Wine |
| mt5/ | `mt5/start.sh` | MT5 startup script |

## Adding Channels
See `references/adding-channels.md` for the full procedure to add new Telegram signal channels to the listener. The Telethon userbot reads channels the user is a member of — no admin rights needed, anti-forwarding channels work.

## Text Signal Formats
See `references/text-signal-formats.md` for the labeled-field formats (Entry:/Stop Loss:/TP1:) that the text prompt was tuned for. The prompt update boosted parse confidence from 0.20→0.90 on structured signals.

## Reconciliation Architecture
See `references/reconciliation-architecture.md` for the full design of per-channel signal reconciliation, opposite-direction close, and deleted message handling.

## Git
- Repo: https://github.com/samwinston1996/trade-copier
- Master branch only
- Push after every verified fix