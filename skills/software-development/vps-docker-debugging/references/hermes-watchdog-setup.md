# Hermes Watchdog — Cron-Based Auto-Restart

## Purpose

Automatically restart the Hermes container within 60 seconds if it goes down, without requiring SSH access. Essential for 24/7 operation.

## Architecture

```
Cron (every 60s) → watchdog.sh → docker ps --filter health=healthy → docker compose up -d (if unhealthy)
```

## Script

Location: `/home/trader/workspace/scripts/watchdog.sh`

```bash
#!/bin/bash
LOG=/home/trader/hermes/watchdog.log
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking Hermes..." >> "$LOG"

if ! docker ps --filter name=hermes --filter health=healthy | grep -q hermes; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Unhealthy — restarting..." >> "$LOG"
  if cd /home/trader/hermes && /usr/bin/docker compose up -d >> "$LOG" 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restart succeeded." >> "$LOG"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RESTART FAILED — check manually!" >> "$LOG"
  fi
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Healthy." >> "$LOG"
fi
```

## Installation (Ubuntu — the standard way)

### 1. Create and fix permissions
```bash
# Script is created by sandbox (root-owned), fix ownership:
sudo chown trader:trader /home/trader/workspace/scripts/watchdog.sh
sudo chmod 755 /home/trader/workspace/scripts/watchdog.sh
```

### 2. Install in user crontab (standard Ubuntu approach)
```bash
(crontab -l 2>/dev/null; echo "*/1 * * * * /home/trader/workspace/scripts/watchdog.sh") | crontab -
```

### 3. Verify
```bash
crontab -l
# Should show: */1 * * * * /home/trader/workspace/scripts/watchdog.sh
```

## Pitfalls (learned the hard way)

### ❌ Don't use /etc/cron.d/ for user scripts
- Requires `username` field in the cron entry
- Filename must not have periods (e.g. `hermes-watchdog` not `hermes-watchdog.sh`)
- File must end with a trailing newline
- File must be owned by `root` with `chmod 644`
- System cron must be restarted after adding: `sudo systemctl restart cron`

### ❌ Don't mount host filesystem via Docker to install cron
Running `docker run --rm -v /home/trader:/mnt ... crontab -` writes to the container's filesystem, not the host. The host OS is detected incorrectly when checking from inside a Docker container (e.g., Docker container shows Alpine even when host is Ubuntu).

### ✅ Use user crontab (crontab -e or crontab -)
Standard Ubuntu user crontab at `/var/spool/cron/crontabs/<user>`. Simple, no special formatting needed.

### ❌ Wrong permissions prevent cron from executing
If the script was created by the sandbox (root user), `trader` cannot read/execute it. Fix with `sudo chown trader:trader`.

### ❌ Timing: user beats the cron tick
Cron runs at the top of each minute. If the user manually runs `docker compose up` within 60 seconds of a `compose down`, they beat the watchdog. Wait the full 60 seconds before declaring it broken.

### ❌ `docker compose down` from sandbox doesn't work reliably
Running compose down from inside the sandbox container has different Docker access semantics than running it from the host. The compose might not fully tear down the container, so the watchdog never sees the "down" state. Always run compose operations from the HOST terminal.

### ❌ `docker compose` requires being in the right directory
`docker compose up -d` without the `-f` flag requires being in the directory containing `docker-compose.yml`. The script does `cd /home/trader/hermes` first. Use absolute paths in scripts, NOT `cd ~/hermes` (cron's `~` may not resolve to the expected home directory).

## Testing the Watchdog

```bash
# 1. Run from HOST terminal:
cd ~/hermes && docker compose down

# 2. Wait 60 seconds (do NOT manually compose up)

# 3. Check if Hermes is back:
docker ps --filter name=hermes

# 4. Check the log:
tail -5 ~/hermes/watchdog.log
# Expected output:
# [2026-07-09 17:46:01] Checking Hermes...
# [2026-07-09 17:46:01] Unhealthy — restarting...
# [2026-07-09 17:46:01] Restart succeeded.
```

## Compose Restart Protocol (from Telegram)

When the user asks for a compose restart and you're on Telegram:

```bash
# Single line to minimize downtime:
docker compose down && docker compose up -d

# Or just restart (keeps container, just restarts process — no env var refresh):
docker compose restart hermes
```

⚠️ Running `down` without `&& up -d` kills the Telegram bot. The watchdog will bring it back within 60s, but the user will be waiting. Always chain both commands in a single line, or warn the user before running `down` alone.