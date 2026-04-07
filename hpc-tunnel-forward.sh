#!/bin/bash
# SSH tunnel: local machine -> HPC compute node
# Reads port pairs from config and builds -L flags dynamically
source "$HOME/.config/hpc-tunnel.conf"

# Build port forward args from FORWARD_PORTS or legacy individual ports
FORWARD_ARGS=""

if [ -n "$FORWARD_PORTS" ]; then
    # New format: comma-separated LOCAL:REMOTE pairs
    # e.g. FORWARD_PORTS="18080:8080,18082:8082,18083:8083"
    IFS=',' read -ra PAIRS <<< "$FORWARD_PORTS"
    for pair in "${PAIRS[@]}"; do
        local_port=$(echo "$pair" | cut -d: -f1)
        remote_port=$(echo "$pair" | cut -d: -f2)
        FORWARD_ARGS="$FORWARD_ARGS -L ${local_port}:localhost:${remote_port}"
    done
else
    # Legacy format: individual port variables
    [ -n "$LLM_PORT" ] && [ -n "$HPC_LLM_PORT" ] && \
        FORWARD_ARGS="$FORWARD_ARGS -L ${LLM_PORT}:localhost:${HPC_LLM_PORT}"
    [ -n "$ASR_PORT" ] && [ -n "$HPC_ASR_PORT" ] && \
        FORWARD_ARGS="$FORWARD_ARGS -L ${ASR_PORT}:localhost:${HPC_ASR_PORT}"
    [ -n "$TTS_PORT" ] && [ -n "$HPC_TTS_PORT" ] && \
        FORWARD_ARGS="$FORWARD_ARGS -L ${TTS_PORT}:localhost:${HPC_TTS_PORT}"
fi

if [ -z "$FORWARD_ARGS" ]; then
    echo "No ports configured. Set FORWARD_PORTS in ~/.config/hpc-tunnel.conf"
    exit 1
fi

exec /usr/bin/ssh -N \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=15 \
    -o BatchMode=yes \
    -o "ProxyJump=${HPC_JUMP}" \
    -i "$HPC_KEY" \
    $FORWARD_ARGS \
    "${HPC_USER}@${HPC_NODE}"
