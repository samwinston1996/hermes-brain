# Telegram Gateway Setup on VPS Deployments

## The QR Code vs Bot Token Conflict

This reference captures a recurring pitfall discovered during troubleshooting a VPS-hosted Hermes instance (docker-compose, trade-copier pattern).

### The Problem

A user sets up Telegram connectivity by:
1. Creating a bot via BotFather and putting `TELEGRAM_BOT_TOKEN` in `.env`
2. Restarting the gateway
3. Going to the Hermes dashboard (`localhost:9119`) → Channels → Telegram
4. Scanning the QR code shown there from their phone
5. The QR code scan appears to work (a bot shows up in Telegram, user ID populates green in dashboard)
6. **But the bot never replies to messages**
7. The `TELEGRAM_BOT_TOKEN` in `.env` has been silently overwritten with a different value

### Root Cause

The dashboard's Telegram Channels page offers **two distinct connection mechanisms**, but they share the same env var name and conflict:

| Mechanism | What it uses | Config layer | Endpoint |
|-----------|-------------|-------------|----------|
| **Bot Token** (`.env`) | Telegram Bot API (`python-telegram-bot`) | `TELEGRAM_BOT_TOKEN` in `.env` | `api.telegram.org` |
| **QR Code Scan** (dashboard) | User-account MTProto (Telethon-style QR login) | Writes to `.env` file, overwriting `TELEGRAM_BOT_TOKEN` with user session artifact | MTProto layer |

When the user scans the QR code from the dashboard:
- It authenticates a **user account** (not a bot) via Telegram's QR login flow
- The user account session is saved to config
- **This writes into the same `TELEGRAM_BOT_TOKEN` env var**, replacing the real bot token
- The gateway then loads the wrong credentials on restart
- The bot talks to Telegram's API with the wrong token → silently fails

### Why the Bot Appears to Work

The user-account QR login produces a "bot" entry in the user's Telegram chats because Hermes registers itself as a contact/conversation through the user session. The user can message it — but the user-account bridge doesn't process messages the same way the Bot API does. No autoreplies ever fire.

### Diagnosis

Check these in order:

```bash
# 1. Is the token still valid? (should be 1234567890:ABCdef... format)
cat ~/.hermes/.env

# 2. Any Telegram config in config.yaml?
grep -A10 -i telegram ~/.hermes/config.yaml

# 3. Gateway logs for errors
tail -30 ~/.hermes/logs/gateway.log

# 4. Gateway running?
hermes gateway status
```

If `.env` contains something that doesn't look like a standard bot token (not in `NUMBER:HEXSTRING` format), the QR code flow overwrote it.

### The Fix

1. **Reset `.env`** to only contain your bot token and allowed users:
   ```
   TELEGRAM_BOT_TOKEN=***
   TELEGRAM_ALLOWED_USERS=***
   ```

2. **Check and remove** any Telegram-related sections from `config.yaml` that the dashboard may have written.

3. **Restart the gateway**:
   ```bash
   hermes gateway restart
   ```

4. **Verify** by sending a message to the bot.

5. **Do NOT scan the QR code again.** Use the dashboard for monitoring only.

### Prevention

- Always set up Telegram via the **CLI** (`hermes gateway setup`) or by editing `.env` directly
- Never use the dashboard's Telegram Channels QR code if you're using the bot-token approach
- If you need user-account Telegram access (e.g., MTProto for user-bot operations), configure it explicitly in `config.yaml` under `platforms.telegram.extra` — don't mix with the `.env` bot-token setup
- After any dashboard configuration changes, always verify `.env` hasn't been altered

### Quick Reference

```bash
# Set up Telegram from CLI
hermes gateway setup

# Check env vars
cat ~/.hermes/.env | grep TELEGRAM

# Restart gateway
hermes gateway restart

# Look at live gateway logs
tail -f ~/.hermes/logs/gateway.log | grep -iE "telegram|error|invalid"

# Check config for conflicting Telegram blocks
grep -A15 "^telegram:" ~/.hermes/config.yaml 2>/dev/null
grep -B2 -A15 "telegram" ~/.hermes/config.yaml 2>/dev/null
```