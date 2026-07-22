# exclude_tickets Fix — Self-Closing Trades

## Bug

Trades opened by the pipeline closed themselves within seconds, before hitting TP or SL. Affected Star FX Trade and Distinct Forex channels.

## Root Cause

Pipeline flow: `place new trade → THEN call /close_channel to cleanup old ones`.

The `/close_channel` endpoint closes ALL positions matching the channel comment. Since the new trade's comment is also the channel name (e.g. `"Star FX Trade"`), it matched and was closed by the cleanup call.

## Fix

**`CloseChannelRequest`** (bridge/bridge.py) — added `exclude_tickets: list[int]` field. When set, positions and pending orders whose ticket is in the list are skipped.

**`/close_channel` handler** (bridge/bridge.py) — two skip checks added:
```python
# Positions
if p.ticket in req.exclude_tickets:
    log.info("Skipping position %s (excluded)", p.ticket)
    continue

# Orders
if o.ticket in req.exclude_tickets:
    log.info("Skipping order %s (excluded)", o.ticket)
    continue
```

**Router** (router/router.py) — after `/trade` succeeds, extracts ticket IDs from the response:
```python
ticket_ids = []
if r.status_code < 400:
    trade_result = r.json()
    if trade_result.get("status") == "executed":
        ticket_ids = [o.get("order", 0) for o in trade_result.get("orders", []) if o.get("order")]
    log.info("Trade placed — tickets: %s", ticket_ids)
```
Then passes them to `/close_channel`:
```python
close_body = {"comment": ev.channel_title or "signal"}
if ticket_ids:
    close_body["exclude_tickets"] = ticket_ids
```

## Verification

Check bridge logs for `Skipping order <ticket> (excluded)` after a trade is placed. This confirms the just-placed trade is being excluded correctly.

## Git

Commit: `be48777` — `fix: exclude_tickets in /close_channel to prevent self-closing trades`