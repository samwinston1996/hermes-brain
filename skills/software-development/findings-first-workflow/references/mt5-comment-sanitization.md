# MT5 Comment Sanitization

## Problem

MT5 (running under Wine) cannot store Unicode Mathematical Bold/Italic letters (U+1D400–U+1D433). Telegram channel titles sometimes use these characters for visual styling (e.g. `𝐃𝐢𝐬𝐁𝐢𝐧𝐁𝐂 𝐅𝐨𝐫𝐞𝐱`). When such a title is used as a trade comment, MT5 stores replacement characters (`???????? ?????`), which breaks the `cancel_pending` comment-matching logic.

## Fix

Use Python's `unicodedata.normalize("NFKC", text)` to convert Mathematical Bold → plain ASCII before the comment reaches MT5.

```python
import unicodedata

def sanitize_comment(comment: str) -> str:
    """Normalize Unicode bold/italic chars to plain ASCII for MT5 compatibility."""
    if not comment:
        return comment
    return unicodedata.normalize("NFKC", comment).strip()
```

## Where to apply

1. **When placing an order** — sanitize comment before passing to MT5's `order_send()`:
   ```python
   order = {
       ...
       "comment": sanitize_comment(req.comment)[:31],  # 31-char MT5 limit
   }
   ```
2. **When cancelling pending orders** — sanitize both the request comment and each order's stored comment before matching:
   ```python
   req_comment = sanitize_comment(req.comment) if req.comment else None
   for o in orders:
       order_comment = sanitize_comment(o.comment or "")
       if req_comment and req_comment in order_comment:
           # match found
   ```
3. **Also fall back by `symbol`** — when comment matching fails (e.g. for orders placed before the fix was deployed):
   ```python
   symbol_matches = req.symbol and o.symbol == req.symbol
   ```

## How NFKC works

| Input | NFKC Output | MT5 stores |
|-------|-------------|------------|
| `𝐃𝐢𝐬𝐁𝐢𝐧𝐁𝐂 𝐅𝐨𝐫𝐞𝐱` | `Distinct Forex` | `Distinct Forex` |
| `𝘴𝘤𝘳𝘦𝘢𝘮𝘦𝘳` | `screamer` | `screamer` |
| `𝐀𝑩𝓒` | `ABC` | `ABC` |

NFKC is lossy (it loses the bold/italic styling) but that's fine — the comment is an internal identifier, not a display value.