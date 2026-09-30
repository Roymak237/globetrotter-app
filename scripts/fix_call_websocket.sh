#!/usr/bin/env bash
#
# Restore audio and video calling by forwarding the websocket Upgrade
# handshake through the host nginx.
#
# ---------------------------------------------------------------------------
# Why this script exists
# ---------------------------------------------------------------------------
# Traffic reaches the app through two layers of nginx:
#
#     browser -> host nginx (TLS, /etc/nginx/sites-enabled/globetrotter)
#             -> container nginx (globetrotter_nginx, port 6003)
#             -> backend:5000
#
# The container layer handles the call-signalling socket correctly. The host
# layer does not: its `location /` sets Host and the X-Forwarded-* headers but
# never sets Upgrade or Connection, so nginx quietly downgrades the handshake
# to an ordinary GET. The backend then answers 400 and no call can ever
# connect. Measured directly:
#
#     through the public URL   -> 400
#     straight to the container -> 101
#
# The correct block already exists in
# frontend/deploy/nginx/host-vhost.conf.template. It simply never reached the
# server: the installed copy predates it, and Certbot has since rewritten that
# copy in place to add the TLS listener. Reinstalling the template wholesale
# would drop the 443 server block and take HTTPS down with it, so this script
# patches the live file instead and leaves every Certbot line untouched.
#
# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
#     bash fix_call_websocket.sh --dry-run    # show the diff, change nothing
#     sudo bash fix_call_websocket.sh         # apply, test, reload, verify
#
# Applying is safe to repeat: it is a no-op once the block is present. The
# live config is backed up first, `nginx -t` runs before anything is reloaded,
# and the backup is restored automatically if the test or the post-reload
# handshake check fails. That matters here because this nginx also serves nine
# unrelated sites.
set -euo pipefail

SITE=/etc/nginx/sites-available/globetrotter
PORT=6003
DOMAIN=kamer-go.duckdns.org
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

[ -r "$SITE" ] || { echo "cannot read $SITE" >&2; exit 1; }

if grep -q 'location = /api/chat/ws' "$SITE"; then
    echo "The websocket block is already present in $SITE."
    echo "Nothing to change."
    exit 0
fi

CANDIDATE=$(mktemp)
trap 'rm -f "$CANDIDATE"' EXIT

# Insert the websocket location immediately before `location /`, inheriting
# that line's indentation. `location = /api/chat/ws` is an exact match, so it
# takes precedence over the `location /` prefix match regardless of ordering,
# but keeping it first also keeps the file readable.
awk -v port="$PORT" '
  /^[[:space:]]*location \/ \{[[:space:]]*$/ && !inserted {
    indent = $0; sub(/location.*/, "", indent)
    print indent "# Call signalling websocket. The Upgrade handshake has to be"
    print indent "# forwarded explicitly; without it nginx drops the upgrade,"
    print indent "# the backend answers 400, and audio and video calls never"
    print indent "# connect. A literal \"upgrade\" is used rather than the"
    print indent "# usual $connection_upgrade map because that map must be"
    print indent "# declared in the http block, which is shared with the other"
    print indent "# sites on this box and is not ours to edit."
    print indent "#"
    print indent "# The long read timeout matters: the app pings every 40s, so"
    print indent "# the 60s default on `location /` would leave almost no"
    print indent "# margin and would drop a quiet call."
    print indent "location = /api/chat/ws {"
    print indent "    proxy_pass http://127.0.0.1:" port ";"
    print indent "    proxy_http_version 1.1;"
    print indent "    proxy_set_header Upgrade $http_upgrade;"
    print indent "    proxy_set_header Connection \"upgrade\";"
    print indent "    proxy_set_header Host $host;"
    print indent "    proxy_set_header X-Real-IP $remote_addr;"
    print indent "    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
    print indent "    proxy_set_header X-Forwarded-Proto $scheme;"
    print indent "    proxy_read_timeout 3600s;"
    print indent "    proxy_send_timeout 3600s;"
    print indent "    proxy_buffering off;"
    print indent "}"
    print ""
    inserted = 1
  }
  { print }
  END { if (!inserted) { print "no `location /` found to anchor to" > "/dev/stderr"; exit 1 } }
' "$SITE" > "$CANDIDATE"

echo "--- proposed change to $SITE ---"
diff "$SITE" "$CANDIDATE" || true

if [ "$DRY_RUN" = "1" ]; then
    echo
    echo "Dry run only. Re-run with: sudo bash $0"
    exit 0
fi

[ "$(id -u)" = "0" ] || { echo "Applying needs root: sudo bash $0" >&2; exit 1; }

BACKUP="${SITE}.bak.$(date +%Y%m%d-%H%M%S)"
cp -p "$SITE" "$BACKUP"
echo "Backed up to $BACKUP"

restore() {
    echo "Restoring the previous configuration." >&2
    cp -p "$BACKUP" "$SITE"
    nginx -t >/dev/null 2>&1 && nginx -s reload || true
}

cat "$CANDIDATE" > "$SITE"

if ! nginx -t; then
    restore
    echo "nginx rejected the patched config; nothing was changed." >&2
    exit 1
fi

nginx -s reload
echo "Reloaded."

# Prove it on the real URL rather than trusting the reload. A websocket
# handshake must now come back as 101 Switching Protocols; 400 means the
# upgrade is still being stripped. The token is deliberately invalid, which
# the backend rejects only *after* the protocol switch.
sleep 1
STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    "https://${DOMAIN}/api/chat/ws?token=probe" || true)

if [ "$STATUS" = "101" ]; then
    echo "Verified: the handshake returns 101 through ${DOMAIN}. Calls can connect."
else
    echo "Handshake still returns ${STATUS} (expected 101)." >&2
    restore
    exit 1
fi
