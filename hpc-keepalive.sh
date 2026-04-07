#!/bin/bash
# hpc-keepalive — Preemptive SLURM job renewal
# Monitors the running job's remaining time, submits a new one before it dies,
# waits for the new node, migrates tunnels, and keeps services alive seamlessly.
#
# Runs as a systemd timer on HPC origin nodes (primary/failover).

source "$HOME/.config/hpc-tunnel.conf" 2>/dev/null
source "$HOME/.config/hpc-route.conf" 2>/dev/null

LOG_PREFIX="[hpc-keepalive]"
RENEW_BEFORE_HOURS=2
SLURM_SCRIPT="${SLURM_JOB_SCRIPT:-/home/aat22g.fsu/qwen_1day.sh}"
HPC_JUMP="${HPC_JUMP:-hpg}"

log()  { echo "$(date '+%H:%M:%S') $LOG_PREFIX $1"; }

hpc_cmd() {
    ssh -o ConnectTimeout=15 -o BatchMode=yes "$HPC_JUMP" "$1" 2>/dev/null
}

# ─── Get current job info ────────────────────────────────────
get_job_info() {
    # Returns: JOB_ID STATE NODE REMAINING_SECS
    local raw=$(hpc_cmd "squeue -u \$USER -h -o '%i|%T|%N|%L' 2>/dev/null" | head -1)
    [ -z "$raw" ] && return 1

    JOB_ID=$(echo "$raw" | cut -d'|' -f1)
    JOB_STATE=$(echo "$raw" | cut -d'|' -f2)
    JOB_NODE=$(echo "$raw" | cut -d'|' -f3)
    local timeleft=$(echo "$raw" | cut -d'|' -f4)

    # Parse time remaining (formats: D-HH:MM:SS, HH:MM:SS, MM:SS)
    REMAINING_SECS=0
    if echo "$timeleft" | grep -q '-'; then
        local days=$(echo "$timeleft" | cut -d'-' -f1)
        local hms=$(echo "$timeleft" | cut -d'-' -f2)
        REMAINING_SECS=$((days * 86400))
        timeleft="$hms"
    fi
    IFS=: read -ra parts <<< "$timeleft"
    case ${#parts[@]} in
        3) REMAINING_SECS=$((REMAINING_SECS + ${parts[0]} * 3600 + ${parts[1]} * 60 + ${parts[2]})) ;;
        2) REMAINING_SECS=$((REMAINING_SECS + ${parts[0]} * 60 + ${parts[1]})) ;;
        1) REMAINING_SECS=$((REMAINING_SECS + ${parts[0]})) ;;
    esac
    return 0
}

# ─── Submit a new job ────────────────────────────────────────
submit_new_job() {
    local output=$(hpc_cmd "sbatch $SLURM_SCRIPT 2>&1")
    NEW_JOB_ID=$(echo "$output" | grep -oP '\d+' | tail -1)
    [ -n "$NEW_JOB_ID" ] && return 0 || return 1
}

# ─── Wait for new job to get a node ─────────────────────────
wait_for_node() {
    local job_id=$1
    local max_wait=1800  # 30 min
    local elapsed=0

    while [ $elapsed -lt $max_wait ]; do
        local info=$(hpc_cmd "squeue -j $job_id -h -o '%T|%N' 2>/dev/null")
        local state=$(echo "$info" | cut -d'|' -f1)
        local node=$(echo "$info" | cut -d'|' -f2)

        if [ "$state" = "RUNNING" ] && [ -n "$node" ]; then
            NEW_NODE="$node"
            return 0
        fi
        sleep 30
        elapsed=$((elapsed + 30))
    done
    return 1
}

# ─── Switch tunnels to new node ──────────────────────────────
switch_to_node() {
    local new_node=$1
    log "Switching tunnels to $new_node..."

    # Update config
    sed -i "s/^HPC_NODE=.*/HPC_NODE=${new_node}/" "$HOME/.config/hpc-tunnel.conf"

    # Update SSH config
    if grep -q "^Host hpc$" "$HOME/.ssh/config" 2>/dev/null; then
        sed -i "/^Host hpc$/,/^Host /{s/^\(\s*HostName\s\).*/\1${new_node}/}" "$HOME/.ssh/config"
    fi

    # Restart tunnel
    systemctl --user restart hpc-tunnel-forward 2>/dev/null
    sleep 5

    if systemctl --user is-active hpc-tunnel-forward >/dev/null 2>&1; then
        log "Tunnel active → $new_node"
        return 0
    else
        log "ERROR: Tunnel failed to start on $new_node"
        return 1
    fi
}

# ─── Main ────────────────────────────────────────────────────
log "Starting keepalive check..."

if ! get_job_info; then
    log "No running job found — submitting new one..."
    if submit_new_job; then
        log "Submitted job $NEW_JOB_ID"
        if wait_for_node "$NEW_JOB_ID"; then
            log "Job $NEW_JOB_ID running on $NEW_NODE"
            switch_to_node "$NEW_NODE"
        else
            log "ERROR: Job $NEW_JOB_ID didn't start within 30min"
        fi
    else
        log "ERROR: sbatch failed"
    fi
    exit 0
fi

log "Job $JOB_ID: state=$JOB_STATE node=$JOB_NODE remaining=${REMAINING_SECS}s ($((REMAINING_SECS/3600))h $((REMAINING_SECS%3600/60))m)"

THRESHOLD=$((RENEW_BEFORE_HOURS * 3600))

if [ "$REMAINING_SECS" -le "$THRESHOLD" ]; then
    log "Job expires in <${RENEW_BEFORE_HOURS}h — preemptively submitting replacement..."

    # Check if we already have a pending replacement
    PENDING=$(hpc_cmd "squeue -u \$USER -h -t PENDING -o '%i' 2>/dev/null" | head -1)
    if [ -n "$PENDING" ]; then
        log "Replacement job $PENDING already pending — waiting for it..."
        if wait_for_node "$PENDING"; then
            log "Replacement $PENDING running on $NEW_NODE"
            # Wait for services to start on new node (watchdog handles this)
            log "Waiting 5min for services to start on $NEW_NODE..."
            sleep 300
            switch_to_node "$NEW_NODE"
        fi
        exit 0
    fi

    if submit_new_job; then
        log "Replacement job $NEW_JOB_ID submitted"
        log "Current job $JOB_ID has ${REMAINING_SECS}s left — staying on $JOB_NODE until replacement is ready"

        if wait_for_node "$NEW_JOB_ID"; then
            log "Replacement $NEW_JOB_ID running on $NEW_NODE"
            # Let the watchdog on the new node start services (~5min for LLM)
            log "Waiting 5min for services on $NEW_NODE..."
            sleep 300

            # Verify services are up on new node before switching
            local port="${HEALTH_PORTS:-18082}"
            for attempt in $(seq 1 12); do
                # Check via SSH to new node
                if hpc_cmd "curl -sf --max-time 3 http://${NEW_NODE}:8082/health" >/dev/null 2>&1; then
                    log "Services healthy on $NEW_NODE — switching!"
                    switch_to_node "$NEW_NODE"
                    exit 0
                fi
                log "Services not ready on $NEW_NODE yet (attempt $attempt/12)..."
                sleep 30
            done
            log "WARNING: Services didn't come up on $NEW_NODE within 10min — switching anyway"
            switch_to_node "$NEW_NODE"
        else
            log "WARNING: Replacement job didn't start — staying on current node"
        fi
    else
        log "ERROR: Failed to submit replacement job"
    fi
else
    log "Job has plenty of time left — no action needed"
fi
