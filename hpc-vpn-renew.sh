#!/bin/bash
# Auto-renew EduVPN before it expires
# Runs via systemd timer on HPC origin nodes (primary + failover)
source "$HOME/.config/hpc-tunnel.env" 2>/dev/null
SHARE="$HOME/.local/share/hpc-reconnect"

# Check if VPN is connected and how much time remains
STATUS=$(eduvpn-cli status 2>/dev/null)
if ! echo "$STATUS" | grep -q "Connected"; then
    echo "[vpn-renew] VPN disconnected — reconnecting..."
elif echo "$STATUS" | grep -q "expired"; then
    echo "[vpn-renew] VPN expired — reconnecting..."
else
    # Parse remaining time
    REMAINING=$(echo "$STATUS" | grep "Valid for" | sed 's/.*Valid for: //')
    HOURS=$(echo "$REMAINING" | grep -oP '\d+(?=h)' || echo "0")
    if [ "${HOURS:-0}" -gt 1 ]; then
        echo "[vpn-renew] VPN healthy ($REMAINING remaining) — no action needed"
        exit 0
    fi
    echo "[vpn-renew] VPN expiring soon ($REMAINING) — renewing..."
fi

# Disconnect + reconnect
eduvpn-cli disconnect >/dev/null 2>&1
sleep 1

# URL capture
rm -f /tmp/vpn-url.txt
cat > /tmp/capture-browser.sh << 'EOF'
#!/bin/bash
echo "$@" > /tmp/vpn-url.txt
EOF
chmod +x /tmp/capture-browser.sh

BROWSER=/tmp/capture-browser.sh eduvpn-cli connect -n 1 >/dev/null 2>&1 &
CONNECT_PID=$!

# Wait for silent refresh or URL
AUTH_URL=""
for i in $(seq 1 15); do
    if eduvpn-cli status 2>/dev/null | grep -q "Valid for:" && \
       ! eduvpn-cli status 2>/dev/null | grep -q "expired"; then
        echo "[vpn-renew] Reconnected via refresh token"
        kill $CONNECT_PID 2>/dev/null
        rm -f /tmp/capture-browser.sh /tmp/vpn-url.txt
        exit 0
    fi
    [ -s /tmp/vpn-url.txt ] && { AUTH_URL=$(cat /tmp/vpn-url.txt); break; }
    sleep 1
done
rm -f /tmp/capture-browser.sh

if [ -z "$AUTH_URL" ]; then
    echo "[vpn-renew] ERROR: no auth URL and no connection"
    kill $CONNECT_PID 2>/dev/null
    exit 1
fi

# Playwright auth
if [ -z "$IDP_USER" ] || [ -z "$IDP_PASS" ]; then
    echo "[vpn-renew] ERROR: credentials not set"
    kill $CONNECT_PID 2>/dev/null
    exit 1
fi

echo "[vpn-renew] Browser auth needed — launching Playwright..."
NODE_PATH="$SHARE/node_modules" \
AUTH_URL="$AUTH_URL" IDP_USER="$IDP_USER" IDP_PASS="$IDP_PASS" \
    node "$SHARE/eduvpn-auth.js" 2>&1

for i in $(seq 1 60); do
    status=$(eduvpn-cli status 2>/dev/null)
    if echo "$status" | grep -q "Valid for:" && ! echo "$status" | grep -q "expired"; then
        echo "[vpn-renew] VPN renewed: $(echo "$status" | grep 'Valid for')"
        kill $CONNECT_PID 2>/dev/null
        rm -f /tmp/vpn-url.txt
        exit 0
    fi
    sleep 2
done

kill $CONNECT_PID 2>/dev/null
echo "[vpn-renew] FAILED"
exit 1
