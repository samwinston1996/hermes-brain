# Execute_code Full Access — Achieved (Jul 2026)

## Architecture

```
VPS Host (trader)
├── /home/trader/hermes/                   ← Standalone compose (hermes + dashboard-proxy)
│   ├── docker-compose.yml
│   └── .env
├── /home/trader/workspace/                ← Project files (mapped as /home/trader/workspace)
│   └── projects/trade-copier/             ← All project files (bridge, router, listener, mt5)
└── /home/trader/.hermes/                  ← Hermes state + config
    ├── config.yaml                        ← terminal.docker_volumes controls mounts
    └── memories/

## Key Config (config.yaml → terminal section)

```yaml
terminal:
  backend: docker
  cwd: /home/trader                         ← default working directory
  docker_image: nikolaik/python-nodejs:python3.11-nodejs20
  container_persistent: true
  docker_volumes:
    - /home/trader:/home/trader             ← full home access (replaces old /workspace mount)
    - /var/run/docker.sock:/var/run/docker.sock:rw
    - /usr/bin/docker:/usr/bin/docker:ro
    - /usr/libexec/docker/cli-plugins:/usr/libexec/docker/cli-plugins:ro
  docker_mount_cwd_to_workspace: false       ← no redundant workspace alias
```

### Why `/home/trader` instead of `/workspace`?

The old pattern mounted only `/home/trader/workspace:/workspace`. The new pattern mounts the **entire** home directory, which means:
- ✅ Projects: `/home/trader/workspace/projects/trade-copier/`
- ✅ SSH keys: `/home/trader/.ssh/`
- ✅ Hermes config: `/home/trader/.hermes/config.yaml`
- ✅ Compose file: `/home/trader/hermes/docker-compose.yml`
- No need for a separate `/workspace` alias

### SSH Key Security Consideration

Mounting the full home exposes `.ssh/` to the sandbox. The Docker socket (also mounted) is already root-level access to the host, so the marginal risk is low. For tighter security, mount only specific directories:

```yaml
  docker_volumes:
    - /home/trader/workspace:/home/trader/workspace
    - /home/trader/.hermes:/home/trader/.hermes
    - /home/trader/hermes:/home/trader/hermes
    - /var/run/docker.sock:/var/run/docker.sock:rw
    - /usr/bin/docker:/usr/bin/docker:ro
    - /usr/libexec/docker/cli-plugins:/usr/libexec/docker/cli-plugins:ro
```

## Applying Config Changes — The Right Way

1. Edit `~/.hermes/config.yaml` (no inline comments on volume lines)
2. Find ALL running executor containers: `docker ps | grep python-nodejs`
3. **Force remove** each one: `docker rm -f <name>` — `docker kill` alone is insufficient because the container respawns with old config
4. Wait for confirmation they're gone: `docker ps | grep python-nodejs || echo "✅ Gone"`
5. The next terminal() call spawns a fresh container with updated mounts

### Why `docker kill` alone fails

With `container_persistent: true`, the container has a 300s lifetime. `docker kill` terminates it, but Hermes sees it missing and immediately spawns a replacement using the OLD config (because the new config hasn't been applied yet). The replacement gets cached. Only `docker rm -f` prevents this by removing the container record entirely.
