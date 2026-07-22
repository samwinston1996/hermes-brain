# Model Cost Optimization

Pricing and strategy for reducing API token burn on trade-copier tasks.

## Model Pricing (OpenRouter, July 2026)

| Model | Input (per 1M) | Output (per 1M) | Vision? |
|---|---|---|---|
| **deepseek/deepseek-v4-flash** | **$0.09** | **$0.18** | ❌ |
| google/gemini-3.1-flash-lite-preview | $0.25 | $1.50 | ✅ |
| google/gemini-2.5-flash | $0.30 | $2.50 | ✅ |

DeepSeek is 2-8x cheaper than Gemini for text tasks. Use it for signal parsing. Use Gemini only when vision is required (image/chart signals).

## Cost Drivers (ranked)

1. **Session context length** — 70-80% of cost. A 700K-token session costs ~$0.09. Two 60K-token sessions cost ~$0.02 (80% savings).
2. **Model choice** — 10-15% of cost. DeepSeek signals cost ~$0.000045 each. Gemini vision signals cost ~$0.00015 each.
3. **Image processing** — 5-10% of cost. Only when chart images are sent.

## Token Thresholds

| Level | Size | Action |
|---|---|---|
| 🟢 GREEN | < 200K | Normal |
| 🟡 AMBER | 200K - 400K | `/compress` or wrap up |
| 🔴 RED | > 400K | Fresh session immediately |

## Router Model Assignment

The trade-copier Router uses two distinct models:
- **Text signals:** `deepseek/deepseek-v4-flash` (cheapest)
- **Image signals:** `google/gemini-3.1-flash-lite-preview` (cheapest vision option)

Router environment variables control this:
- `TEXT_MODEL` (default: `deepseek/deepseek-v4-flash`)
- `VISION_MODEL` (default: `google/gemini-3.1-flash-lite-preview`)