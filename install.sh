#!/bin/bash
set -e

# SupercomputerReconnect installer
# Sets up persistent SSH tunnels between your machine, an HPC cluster,
# and a remote workstation. Survives node changes with one command.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_DIR="$HOME/.config/systemd/user"
CONF="$HOME/.config/hpc-tunnel.conf"

echo "========================================="
echo "  SupercomputerReconnect — installer"
echo "========================================="
echo ""

# ─── Gather config ───────────────────────────────────────────

if [ -f "$CONF" ]; then
    echo "Existing config found at $CONF"
    source "$CONF"
    read -rp "Reconfigure? [y/N] " reconf
    if [[ ! "$reconf" =~ ^[Yy] ]]; then
        echo "Keeping existing config."
        SKIP_CONFIG=1
    fi
fi

if [ -z "$SKIP_CONFIG" ]; then
    echo "── HPC settings ──"
    read -rp "HPC jump host SSH alias or hostname [hpg]: " input
    HPC_JUMP="${input:-hpg}"

    read -rp "HPC username [$(whoami)]: " input
    HPC_USER="${input:-$(whoami)}"

    read -rp "HPC SSH key path [$HOME/.ssh/id_ed25519]: " input
    HPC_KEY="${input:-$HOME/.ssh/id_ed25519}"

    read -rp "Current compute node (e.g. c1100a-s15): " HPC_NODE
    if [ -z "$HPC_NODE" ]; then
        echo "Error: compute node is required."
        exit 1
    fi

    echo ""
    echo "── Port forwarding ──"
    echo "Define port pairs as LOCAL_PORT:REMOTE_PORT"
    echo "Defaults are set for a Qwen voice pipeline (LLM + ASR + TTS)"
    read -rp "LLM ports [18080:8080]: " input
    IFS=: read -r LLM_PORT HPC_LLM_PORT <<< "${input:-18080:8080}"

    read -rp "ASR ports [18082:8082]: " input
    IFS=: read -r ASR_PORT HPC_ASR_PORT <<< "${input:-18082:8082}"

    read -rp "TTS ports [18083:8083]: " input
    IFS=: read -r TTS_PORT HPC_TTS_PORT <<< "${input:-18083:8083}"

    echo ""
    echo "── Remote workstation (optional) ──"
    echo "If set, a reverse tunnel exposes HPC services on the workstation."
    read -rp "Workstation hostname (blank to skip): " WORKSTATION

    if [ -n "$WORKSTATION" ]; then
        read -rp "Workstation user [$(whoami)]: " input
        WORKSTATION_USER="${input:-$(whoami)}"

        read -rp "Workstation SSH key [$HOME/.ssh/id_ed25519]: " input
        WORKSTATION_KEY="${input:-$HOME/.ssh/id_ed25519}"
    fi

    # Write config
    mkdir -p "$(dirname "$CONF")"
    cat > "$CONF" <<EOF
# SupercomputerReconnect config
# Edit manually or run: install.sh to reconfigure
HPC_NODE=$HPC_NODE
HPC_USER=$HPC_USER
HPC_JUMP=$HPC_JUMP
HPC_KEY=$HPC_KEY
WORKSTATION=${WORKSTATION:-}
WORKSTATION_USER=${WORKSTATION_USER:-}
WORKSTATION_KEY=${WORKSTATION_KEY:-}
LLM_PORT=$LLM_PORT
ASR_PORT=$ASR_PORT
TTS_PORT=$TTS_PORT
HPC_LLM_PORT=$HPC_LLM_PORT
HPC_ASR_PORT=$HPC_ASR_PORT
HPC_TTS_PORT=$HPC_TTS_PORT
EOF
    echo ""
    echo "Config written to $CONF"
fi

source "$CONF"

# ─── Install scripts ─────────────────────────────────────────

mkdir -p "$BIN_DIR" "$SYSTEMD_DIR"

install -m 755 "$SCRIPT_DIR/hpc-node" "$BIN_DIR/hpc-node"
install -m 755 "$SCRIPT_DIR/hpc-tunnel-forward.sh" "$BIN_DIR/hpc-tunnel-forward.sh"

echo ""
echo "Installed:"
echo "  $BIN_DIR/hpc-node"
echo "  $BIN_DIR/hpc-tunnel-forward.sh"

# Forward tunnel service (always installed)
cp "$SCRIPT_DIR/hpc-tunnel-forward.service" "$SYSTEMD_DIR/"
echo "  $SYSTEMD_DIR/hpc-tunnel-forward.service"

# Reverse tunnel (only if workstation configured)
if [ -n "$WORKSTATION" ]; then
    install -m 755 "$SCRIPT_DIR/hpc-tunnel-reverse.sh" "$BIN_DIR/hpc-tunnel-reverse.sh"
    cp "$SCRIPT_DIR/hpc-tunnel-reverse.service" "$SYSTEMD_DIR/"
    echo "  $BIN_DIR/hpc-tunnel-reverse.sh"
    echo "  $SYSTEMD_DIR/hpc-tunnel-reverse.service"
fi

# ─── Enable services ─────────────────────────────────────────

# Ensure user lingering is enabled so services survive logout
loginctl enable-linger "$(whoami)" 2>/dev/null || true

systemctl --user daemon-reload
systemctl --user enable hpc-tunnel-forward
if [ -n "$WORKSTATION" ]; then
    systemctl --user enable hpc-tunnel-reverse
fi

echo ""
echo "── Starting tunnels ──"
systemctl --user restart hpc-tunnel-forward
sleep 3
if [ -n "$WORKSTATION" ]; then
    systemctl --user restart hpc-tunnel-reverse
    sleep 2
fi

# ─── Verify ──────────────────────────────────────────────────

echo ""
if systemctl --user is-active hpc-tunnel-forward >/dev/null 2>&1; then
    echo "Forward tunnel: ACTIVE → $HPC_NODE"
    echo "  localhost:$LLM_PORT → $HPC_NODE:$HPC_LLM_PORT"
    echo "  localhost:$ASR_PORT → $HPC_NODE:$HPC_ASR_PORT"
    echo "  localhost:$TTS_PORT → $HPC_NODE:$HPC_TTS_PORT"
else
    echo "Forward tunnel: FAILED (check VPN and SSH keys)"
fi

if [ -n "$WORKSTATION" ]; then
    if systemctl --user is-active hpc-tunnel-reverse >/dev/null 2>&1; then
        echo "Reverse tunnel: ACTIVE → $WORKSTATION"
    else
        echo "Reverse tunnel: FAILED (check workstation SSH keys)"
    fi
fi

# ─── PATH check ──────────────────────────────────────────────

if ! echo "$PATH" | grep -q "$BIN_DIR"; then
    echo ""
    echo "NOTE: Add $BIN_DIR to your PATH:"
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
fi

echo ""
echo "========================================="
echo "  Done! Usage:"
echo "    hpc-node               — show current node"
echo "    hpc-node <node>        — switch to new node"
echo "    hpc-node --auto        — auto-detect from SLURM"
echo "    hpc-node --stop        — stop tunnels"
echo "========================================="
