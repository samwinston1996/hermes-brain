#!/bin/bash
# ---------------------------------------------------------------------------
# Setup Tailscale reverse proxy for Hermes Dashboard
# 
# Creates an nginx container that listens on the VPS Tailscale IP and 
# proxies to the Hermes dashboard (127.0.0.1:9119) with Host header fix 
# and WebSocket support — no auth needed since Tailscale provides network-
# level security.
#
# Usage: sudo bash setup-tailscale-proxy.sh
# ---------------------------------------------------------------------------

set -e

TAILSCALE_IP="100.82.135.83"
DASHBOARD_PORT="9119"
CONTAINER_NAME="hermes-tailscale-proxy"

echo "[+] Checking if container already exists..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[+] Container '${CONTAINER_NAME}' exists. Removing and recreating..."
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1
fi

echo "[+] Creating nginx proxy container..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart always \
  --network host \
  nginx:alpine \
  sh -c "
cat > /etc/nginx/conf.d/tailscale.conf << 'CONF'
server {
    listen ${TAILSCALE_IP}:${DASHBOARD_PORT};
    
    location / {
        proxy_pass http://127.0.0.1:${DASHBOARD_PORT};
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
        
        # Rewrite Host to match dashboard's bound host
        proxy_set_header Host 127.0.0.1:${DASHBOARD_PORT};
        
        # Strip Origin so dashboard WS/SSE endpoints accept non-loopback origins
        proxy_set_header Origin \"\";
        
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_buffering off;
        proxy_read_timeout 86400s;
    }
}
CONF
rm -f /etc/nginx/conf.d/default.conf
nginx -g 'daemon off;'
"

echo "[+] Waiting for container to start..."
sleep 4

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[✓] Proxy is running!"
    echo ""
    echo "    Access the dashboard from your Tailnet at:"
    echo "    http://${TAILSCALE_IP}:${DASHBOARD_PORT}/chat"
    echo ""
    echo "    Via SSH tunnel (same as always):"
    echo "    http://127.0.0.1:${DASHBOARD_PORT}/chat"
else
    echo "[✗] Container failed to start. Check logs:"
    docker logs "${CONTAINER_NAME}" --tail 20
    exit 1
fi