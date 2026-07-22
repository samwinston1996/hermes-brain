# Dashboard Model Audit

## Why This Matters

The Hermes dashboard (port 9119) has its own **model picker dropdown** in the web UI. Selecting a model there creates **separate agent sessions** that use that model regardless of what `config.yaml` says. This is the #1 cause of surprise credit burn.

## Detection

Check the agent log for sessions spawned by the dashboard:

```bash
docker exec hermes grep 'model=' /opt/data/logs/agent.log | grep -v 'deepseek' | tail -10
```

If you see `anthropic/claude-sonnet-4`, `anthropic/claude-opus-4.8`, or any expensive model:
- The dashboard is overriding the config
- Each session burns credits at the dashboard model's rate
- 75x cost difference vs. DeepSeek

## Cost Comparison

| Model | Input (per M tokens) | Output (per M tokens) | Session cost (10 turns) |
|-------|---------------------|----------------------|------------------------|
| deepseek/deepseek-v4-flash | ~$0.20 | ~$1.10 | ~$0.02 |
| anthropic/claude-sonnet-4 | ~$15 | ~$75 | ~$1.50 |
| anthropic/claude-opus-4.8 | ~$75 | ~$150 | ~$7.50 |

## Fix

1. SSH into the VPS: `ssh -L 9119:localhost:9119 <user>@<vps-ip>` (replace `<user>` with the SSH user from their config — e.g. `trader`, `root`, `ubuntu`)
2. Open `http://localhost:9119` in browser
3. Find the model picker (top-right or settings area)
4. Select `deepseek/deepseek-v4-flash` (or whatever config.yaml has)

## Diagnostic — Dashboard Not Loading

If the SSH tunnel is set up but the dashboard shows `ERR_EMPTY_RESPONSE`:

1. **Verify the dashboard is running inside the container:**
   ```bash
   docker exec hermes sh -c "ps aux | grep dashboard | grep -v grep"
   ```
   You should see a `hermes dashboard --host 127.0.0.1 --port 9119` process.

2. **Verify it responds locally:**
   ```bash
   docker exec hermes sh -c "curl -s http://127.0.0.1:9119/"
   ```
   Should return HTML with `<title>Hermes Agent - Dashboard</title>`.

3. **Check the Docker port mapping:**
   ```bash
   docker inspect hermes --format '{{range $p, $conf := .HostConfig.PortBindings}}{{$p}} -> {{range $conf}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}'
   ```
   The dashboard inside the container runs on port 9119. Verify the host port maps to the correct container port. If the mapping shows `9118/tcp -> 127.0.0.1:9119`, the host port 9119 is being forwarded to container port 9118 (wrong port) — the dashboard is on 9119.

## Dashboard Accessibility

The dashboard is bound to `127.0.0.1:9119` (localhost-only) by design:
- `docker exec hermes sh -c "curl -s http://127.0.0.1:9119/"` — works from inside the VPS
- `http://localhost:9119` — works after SSH tunnel from your machine
- The `hermes-dashboard-proxy` (alpine/socat) container is a legacy add-on; the dashboard runs inside the `hermes` container via `s6-supervise dashboard`

## Vision Model Check

The auxiliary vision model in `config.yaml` can also get deprecated on OpenRouter:

```bash
docker exec hermes grep vision /opt/data/config.yaml
```

If `vision_analyze` returns 404 errors, the model was removed from the provider. Common deprecations:
- `google/gemini-2.0-flash-001` → no longer on OpenRouter
- Replace with: `google/gemini-2.5-flash` or `google/gemini-3.1-flash-lite-preview`

## Port Mapping

With `network_mode: host` in the Hermes docker-compose, the dashboard binds directly to the host. No port mapping needed — just SSH tunnel to `localhost:9119`. The `hermes-dashboard-proxy` container (alpine/socat) exists for legacy reasons and is not required for dashboard access.