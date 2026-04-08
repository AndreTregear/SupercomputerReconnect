#!/bin/bash
# hpc-watchdog — Monitors and restarts AI services on HPC compute node
# Runs inside the SLURM job's tmux session
# Checks ASR (8082), TTS (8083), LLM (8080) every 60s, restarts if dead

SERVE_DIR=/blue/xiuwenliu/aat22g.fsu/yaya-omni
LOG_DIR=$SERVE_DIR/logs
API_KEY=omnimoney

check_service() {
    local port=$1 name=$2
    curl -sf --max-time 5 "http://localhost:${port}/health" >/dev/null 2>&1 && return 0
    # LLM needs auth
    [ "$port" = "8080" ] && curl -sf --max-time 5 -H "Authorization: Bearer $API_KEY" "http://localhost:${port}/v1/models" >/dev/null 2>&1 && return 0
    return 1
}

restart_service() {
    local port=$1 name=$2 script=$3 tmux_window=$4
    echo "[$(date)] $name on :$port is DOWN — restarting..."
    
    # Kill old process on this port
    local pid=$(ss -tlnp | grep ":${port} " | grep -oP 'pid=\K[0-9]+' | head -1)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null && sleep 3
    
    # Restart in tmux window
    tmux send-keys -t "${TMUX_SESSION}:${tmux_window}" C-c 2>/dev/null
    sleep 2
    tmux send-keys -t "${TMUX_SESSION}:${tmux_window}" "bash ${script}" C-m
    echo "[$(date)] $name restart triggered in tmux window '${tmux_window}'"
}

# Detect tmux session
TMUX_SESSION=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep 'omni' | head -1)
if [ -z "$TMUX_SESSION" ]; then
    echo "No omni tmux session found. Exiting."
    exit 1
fi
echo "[$(date)] Watchdog started — session: $TMUX_SESSION"
echo "[$(date)] Monitoring LLM(:8080) ASR(:8082) TTS(:8083)"

# Ensure ASR and TTS tmux windows exist
tmux has-session -t "${TMUX_SESSION}:asr" 2>/dev/null || {
    tmux new-window -t "$TMUX_SESSION" -n asr
    tmux send-keys -t "${TMUX_SESSION}:asr" "bash $SERVE_DIR/serve_qwen_asr.sh" C-m
    echo "[$(date)] Created ASR window"
}
tmux has-session -t "${TMUX_SESSION}:tts" 2>/dev/null || {
    tmux new-window -t "$TMUX_SESSION" -n tts
    tmux send-keys -t "${TMUX_SESSION}:tts" "bash $SERVE_DIR/serve_qwen_tts.sh" C-m
    echo "[$(date)] Created TTS window"
}

# Initial grace period — let services start
echo "[$(date)] Waiting 120s for initial startup..."
sleep 120

FAIL_LLM=0; FAIL_ASR=0; FAIL_TTS=0
THRESHOLD=3

while true; do
    # LLM
    if check_service 8080 "LLM"; then
        FAIL_LLM=0
    else
        ((FAIL_LLM++))
        echo "[$(date)] LLM health fail ($FAIL_LLM/$THRESHOLD)"
        if [ "$FAIL_LLM" -ge "$THRESHOLD" ]; then
            restart_service 8080 "LLM" "$SERVE_DIR/serve_gpu0_122b_spec.sh" "gpu0"
            FAIL_LLM=0
            sleep 300  # LLM takes ~5min to load
        fi
    fi

    # ASR
    if check_service 8082 "ASR"; then
        FAIL_ASR=0
    else
        ((FAIL_ASR++))
        echo "[$(date)] ASR health fail ($FAIL_ASR/$THRESHOLD)"
        if [ "$FAIL_ASR" -ge "$THRESHOLD" ]; then
            restart_service 8082 "ASR" "$SERVE_DIR/serve_qwen_asr.sh" "asr"
            FAIL_ASR=0
            sleep 60
        fi
    fi

    # TTS
    if check_service 8083 "TTS"; then
        FAIL_TTS=0
    else
        ((FAIL_TTS++))
        echo "[$(date)] TTS health fail ($FAIL_TTS/$THRESHOLD)"
        if [ "$FAIL_TTS" -ge "$THRESHOLD" ]; then
            restart_service 8083 "TTS" "$SERVE_DIR/serve_qwen_tts.sh" "tts"
            FAIL_TTS=0
            sleep 60
        fi
    fi

    sleep 60
done
