# Adding Telegram Channels to the Trade Copier

The listener runs as a Telethon userbot — logged in as the user's REAL Telegram account. This means:
- **No admin rights needed** — the user just needs to be a member of the channel
- **Anti-forwarding channels work** — Telethon reads messages directly via the API, the user doesn't forward anything
- **No bot token needed** — the session is authenticated as the user

## Procedure

### Step 1 — Get the Numeric Channel ID

The listener needs the channel's numeric ID (e.g. `-1002045136062`). Three ways to get it:

**Method A — Telethon dialog list (fastest, recommended)**
Run a one-shot script from the host using the existing session file:
```python
# Run from the project root where data/tg_session.session exists
# First install telethon if needed on the host
from telethon import TelegramClient
import asyncio

API_ID = int(os.environ["TG_API_ID"])
API_HASH = os.environ["TG_API_HASH"]

async def main():
    client = TelegramClient("/data/tg_session", API_ID, API_HASH)
    await client.start()
    async for d in client.iter_dialogs():
        if d.is_channel:
            print(f"ID={d.id} | title={d.name} | unread={d.unread_count}")
    await client.disconnect()

asyncio.run(main())
```
Or run it inside the listener container where Telethon is already installed:
```bash
docker exec listener python -c "
import asyncio
from telethon import TelegramClient
import os
API_ID = int(os.environ['TG_API_ID'])
API_HASH = os.environ['TG_API_HASH']
async def main():
    client = TelegramClient('/data/tg_session', API_ID, API_HASH)
    await client.start()
    async for d in client.iter_dialogs():
        if d.is_channel:
            print(f'ID={d.id} | title={d.name}')
    await client.disconnect()
asyncio.run(main())
"
```

**Method B — Forward to @getidsbot**
User forwards a message from the channel to @getidsbot on Telegram. The bot replies with the channel ID.

**Method C — Discovery mode**
Temporarily set `TG_CHANNELS=` (empty) in .env, restart the listener, and wait for new messages in the channel. The listener logs:
```
DISCOVERY | chat_id=-1001234567890 | title='Channel Name' | text=...
```
Then restore TG_CHANNELS and restart.

### Step 2 — Add to .env

Edit `.env` and add the channel ID to the `TG_CHANNELS` variable, comma-separated. **Always append the channel name as an inline comment** so future sessions can map IDs back to names without re-running discovery:

```ini
TG_CHANNELS=-1002045136062,-1001234567890,-1009876543210  # BotX channel, Distinct Forex, Star FX
```

This convention means:
- Anyone reading `.env` (human or agent) knows which ID belongs to which channel
- Adding/removing channels doesn't require re-running ID resolution
- The comment stays with the value across git pushes

### Step 3 — (Image channels only) Add to IMAGE_CHANNEL_IDS

If the channel sends **chart screenshot images** (only Trade.inn Forex), also add its ID to `IMAGE_CHANNEL_IDS` in `.env` so the Router routes its images to the vision parser:

```ini
IMAGE_CHANNEL_IDS=-1001766321748,-1001234567890
```

**All other channels** (text-only signals) skip this step — they default to TEXT parsing even if they include decorative screenshots.

### Step 4 — Restart

```bash
cd ~/workspace/projects/trade-copier
docker compose up -d --force-recreate listener
# If IMAGE_CHANNEL_IDS changed, also restart router:
docker compose up -d --force-recreate router
```

⚠️ **`docker compose restart` does NOT re-read the .env file** — it only restarts the existing container with its cached environment variables. Use `docker compose up -d --force-recreate <service>` instead, which creates a fresh container that reads the current `.env`.

### Step 5 — Verify

```bash
docker compose logs --tail=5 listener
```

Look for the startup log line showing the channel list:
```
Logged in as Sam. Channels: [-1002045136062, -1001234567890, -1009876543210]
```

### Step 5 — Test with a Real Signal

Wait for a new message in one of the added channels. The listener should:
1. Receive the message
2. Push it to the router
3. Log: `Pushed msg 12345 (new)`

Check the full pipeline:
```bash
docker compose logs --tail=20 listener router bridge
```

## Pitfalls

- **Stylized Unicode names** — channel titles may use fancy Unicode characters (e.g. `𝐃𝐢𝐬𝐭𝐢𝐧𝐜𝐭 𝐅𝐨𝐫𝐞𝐱` or `𝘀𝘁𝗮𝗿 𝗳𝘅 𝘁𝗿𝗮𝗱𝗲` instead of `Distinct Forex` or `star fx trade`). Regular text search by name will miss these. Two approaches:
  - **If the channel has a username**: use `await client.get_entity('username')` (no @ prefix needed)
  - **If the channel has NO username** (private/public but username-less): use Telethon's `SearchRequest` instead, which searches by title text. This works even for Unicode-styled titles:
    ```python
    from telethon.tl.functions.contacts import SearchRequest
    result = await client(SearchRequest(q='Distinct Forex', limit=10))
    for chat in result.chats:
        print(f'id={chat.id} title={chat.title!r}')  # Works with all Unicode
    ```
- **Channel IDs are negative** — most Telethon channel IDs are negative (e.g. -100...). The integer value is what the listener expects, not a string
- **Session expiry** — the Telethon session at `/data/tg_session.session` can expire if the user changes their password or logs out on another device. If the listener fails to connect, delete the session file and restart — the listener will prompt for a new login
- **Don't string-format the IDs** — `CHANNELS = [int(c) for c in os.environ.get("TG_CHANNELS", "").split(",") if c.strip()]` — the code handles strings, but make sure there are no spaces around commas
- **`--force-recreate` required** — `docker compose restart` doesn't re-read `.env`. Always use `docker compose up -d --force-recreate <service>` when changing channel configs. No `--build` needed (no code changed)