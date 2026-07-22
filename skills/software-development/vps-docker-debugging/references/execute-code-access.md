# execute_code Sidecar — Access Resolution

## The Problem

The `execute_code` sidecar container is isolated from the host and the hermes docker-compose service. It runs in its own filesystem with no Docker socket or project volumes by default.

## The Solution: `terminal.docker_volumes` in config.yaml

**The execute_code sidecar is NOT a docker-compose service.** It is spawned by the Hermes process itself. Its volume mounts are configured in **`~/.hermes/config.yaml`** under the `terminal:` section:

```yaml
# ~/.hermes/config.yaml
terminal:
  backend: docker
  docker_image: nikolaik/python-nodejs:python3.11-nodejs20
  container_persistent: true
  docker_volumes:
    - /home/trader/workspace:/workspace                    # project files (rw)
    - /var/run/docker.sock:/var/run/docker.sock:rw          # Docker API (rw)
    - /usr/bin/docker:/usr/bin/docker:ro                    # Docker CLI (ro)
    - /usr/libexec/docker/cli-plugins:/usr/libexec/docker/cli-plugins:ro  # compose plugin
  docker_mount_cwd_to_workspace: false
```

## Finding the Right Host Paths

The project workspace path depends on your architecture:

```bash
# Check where your project files are on the host
ls -la /home/<user>/workspace/           # typical flat layout
ls -la /home/<user>/workspace/projects/  # if projects are nested
```

For the Docker socket and CLI, the paths are standard:
```bash
ls -la /var/run/docker.sock    # Docker socket
which docker                    # → /usr/bin/docker
ls /usr/libexec/docker/         # → docker compose plugin
```

## The `container_persistent` Gotcha

With `container_persistent: true` (the default), the execute_code container **does NOT restart** when `docker_volumes` changes. The old container keeps running with its original mounts. To apply new mount config:

```bash
# 1. Edit config.yaml
vim ~/.hermes/config.yaml

# 2. Find ALL persistent containers (there may be multiple)
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep python-nodejs

# 3. FORCE REMOVE them — docker kill is NOT sufficient!
#    The container respawns with old config if killed but not removed.
docker rm -f <container-name-1> <container-name-2>

# 4. Verify they're gone
docker ps | grep python-nodejs || echo "✅ All gone"

# 5. The next terminal() call spawns a fresh container with updated mounts
```

**⚠️ CRITICAL: `docker kill` vs `docker rm -f`**
- `docker kill` → container stops, but Hermes respawns it with the OLD config
- `docker rm -f` → container is removed entirely; Hermes creates a NEW one with the current config.yaml

**⚠️ Filter by ancestor image can miss containers**
Using `docker kill $(docker ps -q -f ancestor=nikolaik/python-nodejs)` may not catch all containers because the image tag stored in the container's config may differ from the image name used in `docker_image`. Always inspect by name/ID directly.

**⚠️ YAML comments after volume entries**
Although YAML spec allows trailing comments (`# comment`), Hermes config parser may silently drop entries with inline comments. Keep volume lines clean:
```yaml
# ✅ GOOD
    - /var/run/docker.sock:/var/run/docker.sock

# ⚠️ MAY FAIL
    - /var/run/docker.sock:/var/run/docker.sock  # ← Docker API
```

## Verification — After Mounting

After the new container spawns, verify access:

```bash
# Project files visible?
ls /workspace/projects/trade-copier/ 2>/dev/null || ls /workspace/

# Docker API accessible?
ls -la /var/run/docker.sock
docker ps

# Can you read project files?
cat /workspace/projects/trade-copier/bridge/bridge.py 2>/dev/null
```

## Without the Fix — Workarounds

While waiting to add the mounts, access resources via `docker exec` into the hermes service container:

```bash
docker exec hermes docker ps
docker exec hermes cat /workspace/bridge/bridge.py
docker exec hermes sh -c "cd /workspace && ls"
```