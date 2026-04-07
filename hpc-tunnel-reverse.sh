#!/bin/bash
# Reverse tunnel: expose forwarded HPC ports on a remote workstation
# Supports direct SSH, Cloudflare Tunnel, or any ProxyCommand
source "$HOME/.config/hpc-tunnel.conf"

# Build reverse port args from FORWARD_PORTS or legacy vars
REVERSE_ARGS=""

if [ -n "$FORWARD_PORTS" ]; then
    IFS=',' read -ra PAIRS <<< "$FORWARD_PORTS"
    for pair in "${PAIRS[@]}"; do
        local_port=$(echo "$pair" | cut -d: -f1)
        REVERSE_ARGS="$REVERSE_ARGS -R ${local_port}:localhost:${local_port}"
    done
else
    [ -n "$LLM_PORT" ] && REVERSE_ARGS="$REVERSE_ARGS -R ${LLM_PORT}:localhost:${LLM_PORT}"
    [ -n "$ASR_PORT" ] && REVERSE_ARGS="$REVERSE_ARGS -R ${ASR_PORT}:localhost:${ASR_PORT}"
    [ -n "$TTS_PORT" ] && REVERSE_ARGS="$REVERSE_ARGS -R ${TTS_PORT}:localhost:${TTS_PORT}"
fi

if [ -z "$REVERSE_ARGS" ]; then
    echo "No ports configured."
    exit 1
fi

# Build SSH command
SSH_CMD="/usr/bin/ssh -N \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=15 \
    -o BatchMode=yes \
    -i $WORKSTATION_KEY"

# Add proxy if configured (Cloudflare Tunnel, etc.)
if [ -n "$WORKSTATION_PROXY" ]; then
    SSH_CMD="$SSH_CMD -o ProxyCommand='$WORKSTATION_PROXY'"
fi

SSH_CMD="$SSH_CMD $REVERSE_ARGS ${WORKSTATION_USER}@${WORKSTATION}"

eval exec $SSH_CMD
