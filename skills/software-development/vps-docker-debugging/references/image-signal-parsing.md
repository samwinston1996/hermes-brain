# Image-Based Trade Signal Parsing

## Overview

Extension to the trade-copier pipeline: parse trade signals from chart screenshots showing **coloured shaded zones** (RED SL zone, Grey trade direction zone) using a vision-capable LLM.

## Architecture

```
┌──────────┐   webhook (JSON)   ┌──────────┐   parsed JSON   ┌──────────┐
│ Listener │ ──────────────────▶│  Router  │ ────────────────▶│  Bridge  │
│(Telethon)│                    │(FastAPI) │                  │  → MT5  │
└──────────┘                    └────┬─────┘                  └──────────┘
     │                               │
     │ has_media=True?               │ Dual routing:
     │  └─ download_media(bytes)     │  • image_data present → Gemini vision
     │  └─ base64 encode             │  • text only          → DeepSeek text
     │  └─ include in payload        │
```

## Image Prompt (IMAGE_SYSTEM_PROMPT) — Zone-Based Parsing

Used when `image_data` is present. Model: `google/gemini-3.1-flash-lite-preview` (or `VISION_MODEL` env var).

### Chart Layout

The chart has **two adjacent shaded zones** separated by a horizontal border line:

```
4,127.515 ─────────────────────  ← SL (far edge of RED zone)
          [ RED ZONE ]
4,117.935 ─────────────────────  ← ENTRY (border between RED & Grey)
          [ GREY ZONE — trade direction ]
4,097.184 ─────────────────────  ← TP (far boundary of Grey zone)
```

- **RED zone** = Stop Loss zone. SL price is at the **far edge** of the red zone (side opposite the entry border).
- **Grey zone** = Trade direction / profit zone. Trade moves in this direction.
- **ENTRY** = The horizontal border line between RED and Grey.
- **TP** = The far boundary line of the Grey zone. Only **one** TP price (single target).

### Direction

- RED above + Grey below = **SELL**
- Grey above + RED below = **BUY**

### Right-Panel Boxed Prices (Accuracy)

The right-hand price panel shows **boxed price indicators**:
- **RED box** = SL price (far edge of red zone)
- **GREY box** = TP price (far boundary of grey zone)

Read these boxed values rather than guessing from lines inside the zones.

### Always

- `order_type`: always `"limit"` (image signals are always pending orders at a specific level)
- `symbol`: always `"XAUUSD"` (Gold)
- `entry`: always a `number` (the border line price), never `null`

### Router Handling (post-2026-07-10)

After Gemini returns the parsed signal, the router:

1. Sets `from_image: true` on the bridge body — tells bridge to skip the 20-pip market-override
2. Adds an **additional TP at 100 pips** from entry in the trade direction:
   - SELL: `entry - 10.00` as TP1 (closer target)
   - BUY: `entry + 10.00` as TP1
   - Image TP stays as TP2 (further target)
3. Skips its own market→limit conversion (already "limit" from the prompt)

## Text Prompt (TEXT_SYSTEM_PROMPT)

Used for text-only Telegram messages. Model: `deepseek/deepseek-v4-flash` (or `TEXT_MODEL` env var).
- Parses raw Telegram text for BUY/SELL/CLOSE/MODIFY signals
- Normalises symbols: GOLD/XAU → XAUUSD, DOW → US30, NAS → NAS100
- IGNORE for commentary, recaps, ads, screenshots, greetings
- Requires both SL and TP for valid BUY/SELL; sets confidence ≤ 0.3 if missing
- Temperature: 0

## Shared Output Schema

Both prompts produce the SAME JSON schema:

```json
{
  "action": "BUY|SELL|IGNORE",
  "symbol": "XAUUSD",
  "order_type": "limit",
  "entry": number,
  "sl": number,
  "tp": [number],
  "confidence": 0.0-1.0
}
```

For image signals, the bridge body also carries `from_image: true` (added by router).

## Listener Changes

### Image download flow

```python
MAX_IMAGE_KB = int(os.environ.get("MAX_IMAGE_KB", 512))

async def download_image(event) -> str | None:
    m = event.message
    if not m.media:
        return None
    is_photo = isinstance(m.media, MessageMediaPhoto)
    is_image_doc = isinstance(m.media, MessageMediaDocument) and ...
    if not is_photo and not is_image_doc:
        return None
    raw = await m.download_media(bytes)
    if raw is None or len(raw)/1024 > MAX_IMAGE_KB:
        return None
    return base64.b64encode(raw).decode("ascii")
```

### Payload structure

```python
payload = {
    "event": "new|edit",
    ...,
    "text": m.message or "",
    "has_media": m.media is not None,
    "image_data": downloaded_base64_or_None,
    "date": ...
}
```

Only images that download successfully and fit within MAX_IMAGE_KB produce image_data.

## Router Routing Logic

```python
is_image = False
if ev.image_data and len(ev.image_data) > 100:
    is_image = True
    sig = await parse_image_signal(ev.image_data, ev.text)  # Gemini vision
elif ev.text.strip():
    sig = await parse_text_signal(ev.text)                    # DeepSeek text
else:
    return {"status": "ignored", "reason": "empty message"}
```

Then when building bridge body:
- `from_image: is_image` is included
- For image signals: 100-pip TP is prepended as TP1
- Router's market→limit conversion is skipped for image signals (already "limit")

## Vision API Call Format

```python
payload = {
    "model": VISION_MODEL,
    "messages": [
        {"role": "system", "content": IMAGE_SYSTEM_PROMPT},
        {"role": "user", "content": [
            {"type": "text", "text": user_text},
            {"type": "image_url",
             "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}}
        ]}
    ],
    "temperature": 0
}
```

Timeout: 120s (images are larger payloads).

## Key Configuration

| Env var | Where | Default | Purpose |
|---------|-------|---------|---------|
| `OPENROUTER_API_KEY` | Router | _(required)_ | API key for OpenRouter |
| `TEXT_MODEL` | Router | `deepseek/deepseek-v4-flash` | Model for text signal parsing |
| `VISION_MODEL` | Router | `google/gemini-3.1-flash-lite-preview` | Model for image signal parsing |
| `MAX_IMAGE_KB` | Listener | `512` | Max image size to forward (base64) |
| `HERMES_WEBHOOK_TOKEN` | Router | _(required)_ | Shared secret auth between listener and router |

**Important:** The Router calls OpenRouter API directly (`https://openrouter.ai/api/v1/chat/completions`), NOT the Hermes API server.

## Errors & Edge Cases

- **Media but no image data**: video, GIF, sticker, or image too large — router falls through to text-only parsing.
- **Gemini doesn't return JSON**: `extract_json` regex fallback handles wrapped output. If no JSON found, alert sent and 502 returned.
- **Image too large**: listener logs a warning and skips.
- **Empty chart / no readable levels**: image prompt sets `action: IGNORE, confidence: 0.0`.
- **Single TP from image, router adds second**: 100-pip TP prepended as TP1, image TP stays as TP2. Bridge splits lot across both.
- **Entry <20 pips from market (image signals)**: `from_image` flag tells bridge to keep as pending order instead of overriding to market.