# Dashboard Proxy Architecture

## Overview

The Hermes dashboard is accessed via a **socat proxy** container that shares the `hermes` container's network namespace. This allows two ports to coexist cleanly.

## Traffic Flow

```
User → localhost:9119 (host)
     → Docker port mapping: host:9119 → container:9118
     → socat on port 9118 (listening 0.0.0.0)
     → forwards to 127.0.0.1:9119 (Hermes dashboard)
     → returns 200 OK
```

## Compose Definition

From `/home/trader/hermes/docker-compose.yml`:

```yaml
hermes:
  image: nousresearch/hermes-agent:v2026.7.1
  ports:
    - "127.0.0.1:9119:9118"      # host:9119 → container:9118
  environment:
    HERMES_DASHBOARD: "1"
    HERMES_DASHBOARD_HOST: "127.0.0.1"
  healthcheck:
    test: ["CMD","curl","-f","http://127.0.0.1:9119/"]
    interval: 15s
    timeout: 5s
    retries: 10
    start_period: 30s

hermes-dashboard-proxy:
  image: alpine/socat
  network_mode: "service:hermes"     # shares hermes network namespace
  depends_on:
    hermes:
      condition: service_healthy
  command: TCP-LISTEN:9118,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:9119
```

## Key Detail: network_mode

`network_mode: "service:hermes"` means the proxy container shares the exact same network namespace as the `hermes` container. This is why:

- `127.0.0.1:9119` from the proxy → reaches the dashboard inside the hermes container
- The proxy listens on `0.0.0.0:9118` — this is the same namespace, so port 9118 is also visible on the hermes container's interfaces
- Docker port mapping `9119:9118` → reaches the socat listener on 9118

## Why Two Ports?

The dashboard listens on **9119** inside the container. The socat proxy listens on **9118** and forwards to 9119. Docker maps the host port **9119** to container port **9118**. This means:

- Healthcheck goes directly to `127.0.0.1:9119` (bypasses proxy)
- User traffic goes `host:9119 → container:9118 → socat → container:9119`

## Key Finding: Proxy IS Required — Test Context Matters

**The proxy container is required.** Docker's port mapping (`host:9119 → container:9118`) targets the socat listener on port 9118. If the proxy is stopped, nothing is listening on 9118 and the connection should fail.

**However, testing from the wrong context gives false positives.** The `terminal()` tool runs inside the Hermes agent container (or the execute_code sidecar), which has its own network namespace. A `curl` from there may reach the dashboard through different paths depending on the Docker networking setup.

**Reliable tests (use these):**
```bash
# From the host — tests full chain (Docker port mapping → proxy → dashboard)
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9119/
# 200 = full chain working

# From inside the hermes container — tests dashboard directly (bypasses proxy)
docker exec hermes sh -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9119/'
# 200 = dashboard alive

# From inside the proxy container — UNRELIABLE (user namespace false negatives)
# May return "Connection refused" even when everything is working
```

**Bottom line:** Always test from the host. If `curl http://127.0.0.1:9119/` from the host returns 200, everything is working. Do not trust tests from inside the proxy container.

## Debugging Techniques

### Checking Listening Sockets via /proc/net/tcp

When `netstat`/`ss` aren't available inside a container, use `/proc/net/tcp` to check listening ports:

```bash
# From inside the container
cat /proc/net/tcp

# Decode: hex IP:port pairs, state 0A = LISTEN
# 0100007F:239F → 127.0.0.1:9119 (dashboard)
# 00000000:21C2 → 0.0.0.0:8642 (gateway API)
# 00000000:239E → 0.0.0.0:9118 (socat proxy)
```

Compare output across containers to verify network namespace sharing. If the proxy container's `/proc/net/tcp` differs from the hermes container's, the network namespaces aren't actually shared.

### User Namespace False Negatives

The `hermes` container runs processes as the `hermes` user (UID 1000) via `s6-setuidgid`, while the socat proxy runs as root. This creates a user namespace boundary — **`docker exec` into the proxy container gives false negatives** when testing `127.0.0.1:9119`:

```bash
# ❌ False negative — user namespace isolation blocks it
docker exec hermes-dashboard-proxy sh -c 'nc -z 127.0.0.1 9119'
# → Connection refused (but dashboard IS listening)

# ✅ Reliable — test from the host
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9119/
# → 200

# ✅ Reliable — test from the hermes container directly
docker exec hermes sh -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9119/'
# → 200
```

**Always test from the host or the hermes container — never from the proxy container.**

## Troubleshooting

### Symptom: "Connection refused" on localhost:9119

**Most likely:** The socat proxy is running but the dashboard process inside the hermes container restarted and is slowly reloading. Flow:

1. Check if dashboard responds directly: `docker exec hermes sh -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9119/'`
2. If 200 → dashboard is fine, check the proxy: `docker exec hermes sh -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9118/'`
3. If 000 on 9118 → socat isn't listening. Check: `docker logs hermes-dashboard-proxy`

### Symptom: Proxy container logs show "Connection refused" on 127.0.0.1:9119

The dashboard was restarted and hasn't finished loading yet, or the dashboard process crashed. Check:
- `docker inspect hermes --format '{{.State.Health.Status}}'` — should be "healthy"
- `docker exec hermes ps aux | grep dashboard` — should show the dashboard process

### Symptom: Proxy was recreated but still not working

The proxy container uses `network_mode: "service:hermes"` which means it must reference the `hermes` container by name. If you recreate the proxy with `docker run` directly, make sure to use `--network="container:hermes"`.

### Symptom: Can't test host:9119 from inside another Docker container

The port mapping `127.0.0.1:9119:9118` binds only on the host's loopback interface. From inside other Docker containers (including the execute_code sandbox), localhost is the container's own loopback, not the host's. Test from the host directly or use `docker exec hermes sh` to test within the shared namespace.

### Symptom: SSH tunnel returns ERR_EMPTY_RESPONSE from browser (VPS side is fine)

If `curl http://127.0.0.1:9119/` returns HTTP 200 on the VPS but the browser on your PC shows "This page isn't working / ERR_EMPTY_RESPONSE", the issue is on the **client side** — the SSH tunnel isn't forwarding properly.

**Troubleshooting flow:**

1. **Verify VPS side is healthy** (from the VPS):
   ```bash
   curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9119/
   # Should return 200
   ```

2. **Check if the tunnel is listening on your PC** (from your local machine):
   ```bash
   # Linux/Mac
   netstat -an | grep 9119 | grep LISTEN
   # Windows
   netstat -ano | findstr :9119
   ```
   Should show a `LISTENING` entry for `127.0.0.1:9119` or `0.0.0.0:9119`.

3. **If no LISTENING entry — restart the SSH tunnel:**

   **Windows:**
   ```cmd
   taskkill /f /im ssh.exe
   ssh -L 9119:localhost:9119 trade-copier
   ```
   (Your SSH config should have `LocalForward 9119 localhost:9119` under the `Host trade-copier` block.)

   **Linux/Mac:**
   ```bash
   pkill -f "ssh.*trade-copier"
   ssh -L 9119:localhost:9119 trade-copier
   ```

4. **Persistent tunnel (Linux/Mac):**
   ```bash
   ssh -f -N -L 9119:localhost:9119 trade-copier
   ```
   `-f` forks to background, `-N` means no remote command (tunnel only).

5. **Auto-reconnecting tunnel (Linux/Mac):**
   ```bash
   autossh -M 0 -f -N -L 9119:localhost:9119 trade-copier
   ```

**Key insight:** The VPS side almost never needs changes when the dashboard is returning HTTP 200 locally. The issue is nearly always a stale or disconnected SSH tunnel on the client machine. Do not touch Docker config, compose files, or proxy containers unless the VPS-side `curl` fails.