#!/bin/bash
# SSH tunnel: local machine -> HPC compute node
# Forwards service ports through the jump host
source "$HOME/.config/hpc-tunnel.conf"
exec /usr/bin/ssh -N \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=15 \
    -o BatchMode=yes \
    -o "ProxyJump=${HPC_JUMP}" \
    -i "$HPC_KEY" \
    -L "${LLM_PORT}:localhost:${HPC_LLM_PORT}" \
    -L "${ASR_PORT}:localhost:${HPC_ASR_PORT}" \
    -L "${TTS_PORT}:localhost:${HPC_TTS_PORT}" \
    "${HPC_USER}@${HPC_NODE}"
