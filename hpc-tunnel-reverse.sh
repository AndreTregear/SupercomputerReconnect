#!/bin/bash
# Reverse tunnel: expose forwarded HPC ports on a remote workstation
# So the workstation can reach HPC services via localhost
source "$HOME/.config/hpc-tunnel.conf"
exec /usr/bin/ssh -N \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -o ConnectTimeout=15 \
    -o BatchMode=yes \
    -i "$WORKSTATION_KEY" \
    -R "${LLM_PORT}:localhost:${LLM_PORT}" \
    -R "${ASR_PORT}:localhost:${ASR_PORT}" \
    -R "${TTS_PORT}:localhost:${TTS_PORT}" \
    "${WORKSTATION_USER}@${WORKSTATION}"
