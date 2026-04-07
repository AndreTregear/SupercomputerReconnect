#!/bin/bash
# HiPerGator partition presets — sourced by hpc-job
# Last updated: 2026-04-07

# Format: NAME|PARTITION|GPU_TYPE|GPUS_PER_NODE|MAX_GPUS|CPUS|MEM|MAX_TIME|DESCRIPTION
HIPERGATOR_PRESETS=(
    "b200-1gpu|hpg-b200|B200|1|8|14|256gb|14-00:00:00|1x NVIDIA B200 (183GB VRAM) — LLM inference, training"
    "b200-2gpu|hpg-b200|B200|2|8|28|512gb|14-00:00:00|2x NVIDIA B200 — tensor parallel, large models"
    "b200-4gpu|hpg-b200|B200|4|8|56|1024gb|14-00:00:00|4x NVIDIA B200 — distributed training"
    "b200-full|hpg-b200|B200|8|8|112|2048gb|14-00:00:00|Full B200 node (8 GPUs, 1.4TB VRAM)"
    "l4-1gpu|hpg-turin|L4|1|3|32|256gb|14-00:00:00|1x NVIDIA L4 (24GB) — light inference, dev"
    "l4-3gpu|hpg-turin|L4|3|3|96|771gb|14-00:00:00|Full L4 node (3 GPUs) — multi-model serving"
    "l4-gui|hwgui|L4|1|3|32|256gb|4-00:00:00|1x L4 with GUI/desktop support"
    "cpu-dev|hpg-dev|none|0|0|16|64gb|12:00:00|CPU only — quick dev/test (12h max)"
    "cpu-milan|hpg-milan|none|0|0|32|256gb|31-00:00:00|CPU only — long-running compute"
    "cpu-burst|hpg-default|none|0|0|64|512gb|31-00:00:00|CPU only — default partition"
)

show_hipergator_presets() {
    echo -e "  ${BOLD}GPU Nodes${NC}"
    printf "  ${DIM}%-4s %-14s %-8s %-6s %-8s %-8s %-14s${NC}\n" "#" "Name" "GPU" "GPUs" "CPUs" "Mem" "Max Time"
    echo -e "  ${DIM}──── ────────────── ──────── ────── ──────── ──────── ──────────────${NC}"

    local idx=1
    for preset in "${HIPERGATOR_PRESETS[@]}"; do
        IFS='|' read -r name part gpu_type gpus max_gpus cpus mem maxtime desc <<< "$preset"
        if [ "$gpu_type" != "none" ]; then
            printf "  ${CYAN}[%2d]${NC} %-14s %-8s %-6s %-8s %-8s %s\n" "$idx" "$name" "$gpu_type" "${gpus}" "$cpus" "$mem" "$maxtime"
        fi
        ((idx++))
    done

    echo ""
    echo -e "  ${BOLD}CPU-Only Nodes${NC}"
    printf "  ${DIM}%-4s %-14s %-8s %-6s %-8s %-8s %-14s${NC}\n" "#" "Name" "Part" "GPUs" "CPUs" "Mem" "Max Time"
    echo -e "  ${DIM}──── ────────────── ──────── ────── ──────── ──────── ──────────────${NC}"

    idx=1
    for preset in "${HIPERGATOR_PRESETS[@]}"; do
        IFS='|' read -r name part gpu_type gpus max_gpus cpus mem maxtime desc <<< "$preset"
        if [ "$gpu_type" = "none" ]; then
            printf "  ${CYAN}[%2d]${NC} %-14s %-8s %-6s %-8s %-8s %s\n" "$idx" "$name" "$part" "-" "$cpus" "$mem" "$maxtime"
        fi
        ((idx++))
    done
    echo ""

    echo -e "  ${DIM}Your QOS (xiuwenliu): max 10 GPUs simultaneous, 31-day wall time${NC}"
    echo -e "  ${DIM}B200 nodes: 8 GPUs/node, 112 CPUs, ~2TB RAM | L4 nodes: 3 GPUs/node${NC}"
    echo ""
}

get_preset() {
    local num="$1"
    if [ "$num" -ge 1 ] && [ "$num" -le ${#HIPERGATOR_PRESETS[@]} ]; then
        echo "${HIPERGATOR_PRESETS[$((num-1))]}"
    fi
}
