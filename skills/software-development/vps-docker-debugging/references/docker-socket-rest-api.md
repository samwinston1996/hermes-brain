# Docker REST API via curl (when socket is available)

When you have `/var/run/docker.sock` mounted into a container, you can use the Docker REST API directly via curl instead of the `docker` CLI.

## Base URL

```bash
curl --unix-socket /var/run/docker.sock http://localhost/version
```

## Common Endpoints

| What | curl command |
|------|-------------|
| Docker version | `curl --unix-socket /var/run/docker.sock http://localhost/version` |
| List containers | `curl --unix-socket /var/run/docker.sock http://localhost/containers/json` |
| Container info | `curl --unix-socket /var/run/docker.sock http://localhost/containers/<name>/json` |
| Container logs | `curl --unix-socket /var/run/docker.sock "http://localhost/containers/<name>/logs?stdout=1&stderr=1"` |
| Exec in container | `curl --unix-socket /var/run/docker.sock -X POST http://localhost/containers/<name>/exec -d '{"AttachStdin":true,"AttachStdout":true,"AttachStderr":true,"Cmd":["sh"]}'` |
| Start exec | `curl --unix-socket /var/run/docker.sock -X POST http://localhost/exec/<id>/start -d '{"Detach":false,"Tty":true}'` |
| List images | `curl --unix-socket /var/run/docker.sock http://localhost/images/json` |
| Pull image | `curl --unix-socket /var/run/docker.sock -X POST http://localhost/images/create?fromImage=alpine` |

## Streaming Response (logs, exec)

Use `-N` (no buffer) with curl:
```bash
curl -N --unix-socket /var/run/docker.sock "http://localhost/containers/<name>/logs?stdout=1&stderr=1&follow=1"
```

## Docker Exec with TTY

```bash
# 1. Create exec instance
EXEC=$(curl -s --unix-socket /var/run/docker.sock -X POST http://localhost/containers/<name>/exec \
  -H "Content-Type: application/json" \
  -d '{"AttachStdin":true,"AttachStdout":true,"AttachStderr":true,"Tty":true,"Cmd":["sh"]}')

EXEC_ID=$(echo $EXEC | python3 -c "import sys,json; print(json.load(sys.stdin)['Id'])")

# 2. Start it (returns stream)
curl -N --unix-socket /var/run/docker.sock -X POST http://localhost/exec/$EXEC_ID/start \
  -H "Content-Type: application/json" \
  -d '{"Detach":false,"Tty":true}'
```

## Python requests library

```python
import requests

socket_path = "/var/run/docker.sock"

def docker_api(method, path, **kwargs):
    return requests.request(
        method,
        f"http://localhost{path}",
        unix_socket=socket_path,
        **kwargs
    )

# List containers
r = docker_api("GET", "/containers/json")
print(r.json())

# Container logs
r = docker_api("GET", "/containers/bridge/logs?stdout=1&stderr=1")
print(r.text)
```

## Limitations

- No shell expansion, globbing, or pipeline support (use docker CLI or python for that)
- Multipart responses (logs, exec stream) need special handling
- For `docker build`, use the Image API (POST with tarball)

## When to use vs docker CLI

| Use REST API | Use docker CLI |
|-------------|----------------|
| Scripted automation in containers | Interactive commands |
| Parsing JSON responses | Complex command structures |
| No docker binary available | Shell features needed |
| Cross-container coordination | Image build/push |