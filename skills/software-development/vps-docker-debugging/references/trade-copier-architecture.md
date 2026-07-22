# trade-copier Architecture Reference

## Host Layout

**Current flat layout (post-July 2026 restructuring):**

```
/home/trader/                  # or user's home directory
├── hermes/                    # Standalone hermes docker-compose
│   ├── docker-compose.yml     # ONLY hermes + dashboard-proxy (no project services)
│   └── .env
├── workspace/                 # Mapped to execute_code /workspace/ via config.yaml
│   ├── projects/trade-copier/ # Project code (bridge, router, listener, mt5, scripts, data)
│   ├── scripts/
│   ├── scratch/
│   └── downloads/
└── .hermes/                   # Hermes config/state — mounted as /opt/data in hermes container
    ├── config.yaml            # ← terminal.docker_volumes controls execute_code mounts
    └── skills/
```

**Legacy nested layout (pre-July 2026):**
```
~/trade-copier/
├── docker-compose.yml       # hermes + router + mt5 + bridge + listener + copier network
├── router/
├── bridge/
├── listener/
├── mt5/
├── scripts/
└── data/hermes/             # hermes state (mounted as /opt/data)
```

## Key Config Files

| File | Purpose | Controls |
|------|---------|----------|
| `~/.hermes/config.yaml` | Hermes agent configuration | `terminal.docker_volumes` (execute_code mounts), model, provider, skills, platforms |
| `~/.hermes/.env` | Hermes service environment variables | TELEGRAM_BOT_TOKEN, API keys, MT5 credentials |
| `~/hermes/docker-compose.yml` | Docker compose for hermes service | Hermes service container, dashboard proxy, shared network |
| `~/hermes/.env` | docker-compose env vars | HERMES_API_KEY, VNC_PASSWORD, MT5_LOGIN, MT5_PASSWORD, MT5_SERVER |

## Container Map

```
┌──────────────────────────────────────────────────────────────────┐
│  VPS Host                                                       │
│  ~/.hermes/config.yaml ── controls execute_code mounts          │
│  ~/workspace/projects/trade-copier/ ── project source code     │
│  ~/hermes/docker-compose.yml ── hermes + dashboard-proxy only  │
└──────────────────────────────────────────────────────────────────┘
          ↑ docker-compose up
          │
┌─────────┴──────────────────────────────────────────────────────┐
│  Docker network: copier (bridge driver)                        │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │ hermes (nousresearch/hermes-agent:v2026.7.1)            │  │
│  │ • ports: 8642, 9119                                     │  │
│  │ • volumes: /home/trader/.hermes:/opt/data               │  │
│  │            /var/run/docker.sock (check :rw!)            │  │
│  │ • sees: Hermes config/state at /opt/data                │  │
│  │ • can: docker ps, docker exec into all containers       │  │
│  │                                                         │  │
│  │  ┌────────────────────────────────────────────────────┐ │  │
│  │  │ hermes-dashboard-proxy (alpine/socat)              │ │  │
│  │  │ • network_mode: service:hermes                     │ │  │
│  │  │ • proxies: localhost:9118 → hermes:9119           │ │  │
│  │  │ • exposes: host:127.0.0.1:9118                    │ │  │
│  │  └────────────────────────────────────────────────────┘ │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌────────────────┐     ┌─────────────────────────────────┐   │
│  │ router          │     │ mt5 (gmag11/metatrader5_vnc)    │   │
│  │ build: ./router │     │ • ports: 127.0.0.1:3000         │   │
│  │ env_file: .env  │────▶│ • volumes: ./data/mt5:/config   │   │
│  │ HERMES_API_URL  │     │ • MT5_LOGIN/PASSWORD/SERVER      │   │
│  │ BRIDGE_URL      │     └──────────────┬──────────────────┘   │
│  └───────┬────────┘                    │                       │
│          │                               │                       │
│          │                    ┌──────────▼──────────┐            │
│          │                    │ bridge              │            │
│          │                    │ build: ./bridge     │            │
│          │                    │ network_mode:       │            │
│          │                    │   service:mt5      │            │
│          │                    │ port: 8002 (mt5)   │            │
│          │                    │ env_file: .env     │            │
│          │                    └────────────────────┘            │
│          │                                                       │
│  ┌──────▼────────┐                                             │
│  │ listener      │                                             │
│  │ build: ./listener                                            │
│  │ env_file: .env                                               │
│  │ volumes: ./data                                             │
│  └───────────────┘                                             │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  execute_code sidecar (nikolaik/python-nodejs)                   │
│  ● NOT in docker-compose.yml — spawned by Hermes process        │  │
│  ● Mounts controlled by ~/.hermes/config.yaml → terminal.docker_volumes
│  ● Default: only /workspace bound from host                     │
│  ● When configured: can also have Docker socket + CLI           │
│  ● container_persistent: true → must kill container to apply    │
│    config changes                                                │
└──────────────────────────────────────────────────────────────────┘
```

## Service Communication Flow

```
Telegram → Hermes Agent (port 8642)
              │
              ├──▶ router (HERMES_API_URL)
              │         │
              │         └──▶ bridge (BRIDGE_URL → mt5:8002)
              │                      │
              │                      └──▶ mt5 (MT5 server)
              │
              └──▶ listener (polling / data feed)
                        └──▶ writes to ./data/

Hermes Dashboard: host:9118 ──▶ hermes-dashboard-proxy ──▶ hermes:9119
```

## Key Filesystem Paths

| On Host | In hermes container | In execute_code sidecar (default) | In execute_code sidecar (configured) |
|---------|---------------------|-----------------------------------|--------------------------------------|
| `~/workspace/projects/trade-copier/` | Not mounted by default | ❌ (unless in docker_volumes) | ✅ /workspace/ (if docker_volumes maps it) |
| `~/hermes/` | Not mounted | ❌ | ❌ |
| `~/.hermes/` | `/opt/data/` | ❌ (unless added) | ✅ (if added to docker_volumes) |
| `/var/run/docker.sock` | `/var/run/docker.sock` | ❌ | ✅ (if added to docker_volumes) |
| `/usr/bin/docker` | `/usr/bin/docker` | ❌ | ✅ (if added to docker_volumes) |

## Configuring execute_code Mounts

In `~/.hermes/config.yaml`:

```yaml
terminal:
  docker_volumes:
    - /home/trader/workspace:/workspace                    # project files
    - /var/run/docker.sock:/var/run/docker.sock:rw          # Docker API
    - /usr/bin/docker:/usr/bin/docker:ro                    # Docker CLI
    - /usr/libexec/docker/cli-plugins:/usr/libexec/docker/cli-plugins:ro
```

After editing config.yaml, force-remove ALL persistent containers:

```bash
# Find all executor containers
docker ps --format "table {{.Names}}\t{{.Image}}" | grep python-nodejs

# FORCE REMOVE — docker kill alone is insufficient!
docker rm -f <name-1> <name-2> <name-3>

# Verify they're gone
docker ps | grep python-nodejs || echo "✅ Gone"
```

**⚠️ CRITICAL: `docker kill` alone is insufficient.** With `container_persistent: true`, `docker kill` terminates the process but Hermes immediately spawns a replacement using the OLD config cache — making it look like the config change had no effect. Always `docker rm -f`.

**⚠️ Image filter caveat:** Some executor containers may use different image tags/digests and won't be caught by `grep python-nodejs`. Check `docker ps` manually for any `nikolaik/python-nodejs` or `sleep infinity` containers that may have been missed. Kill them by name:
```bash
docker rm -f <missed-container-name>
```

## Hermes API Endpoints

| Endpoint | Description |
|----------|-------------|
| `http://hermes:8642/v1/chat/completions` | Chat completions (router → Hermes) |
| `http://hermes:8642/v1/models` | Model list |
| `http://127.0.0.1:9118/` | Dashboard (via proxy) |
| `http://127.0.0.1:9119/` | Dashboard (direct, behind proxy) |

## Debugging from execute_code Sidecar

```bash
# Identify: check if you have docker or hermes
which docker        # empty → not mounted
ls /var/run/docker.sock  # missing → no docker socket
hostname            # 631ee2fa7f0e = execute_code sidecar

# Workaround: exec into hermes container
docker exec hermes docker ps
docker exec hermes cat /workspace/bridge/bridge.py
docker exec hermes sh -c "cd /workspace && ls"

# Or: check workspace mount
cat /workspace/projects/trade-copier/bridge/bridge.py 2>/dev/null
```