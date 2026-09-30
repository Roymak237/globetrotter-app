#!/usr/bin/env bash
# Post-change health check. The host nginx serves nine other sites, so a
# reload has to be confirmed harmless for all of them, not just for ours.
echo "=== every vhost on this box ==="
for s in /etc/nginx/sites-enabled/*; do
    name=$(basename "$s")
    d=$(grep -m1 -oP 'server_name\s+\K[^;]+' "$s" 2>/dev/null | awk '{print $1}')
    if [ -z "$d" ] || [ "$d" = "_" ]; then
        echo "  $name -> (no domain, skipped)"
        continue
    fi
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$d/" 2>/dev/null)
    echo "  $name ($d) -> $code"
done

echo "=== kamer-go surfaces ==="
for p in / /app/ /api/healthz; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://kamer-go.duckdns.org$p")
    echo "  $p -> $code"
done

echo "=== websocket upgrade ==="
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    'https://kamer-go.duckdns.org/api/chat/ws?token=probe')
echo "  /api/chat/ws -> $code (101 means the upgrade is forwarded)"
