#!/usr/bin/env zsh
# ╔══════════════════════════════════════════════════════════════╗
# ║  intellama — Interactive llama.cpp Launcher                 ║
# ║  (formerly llama-cli)  Optimized for Intel Mac Pro 2013    ║
# ╚══════════════════════════════════════════════════════════════╝

setopt KSH_ARRAYS

# ─── Paths (auto-detect from package install or env) ───────────
SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"

LLAMA_DIR="${LLAMA_DIR:-${PACKAGE_DIR}/vendor/llama-cpp-macpro}"
SERVER_BIN="$LLAMA_DIR/bin/llama-server"
BENCH_BIN="$LLAMA_DIR/bin/llama-bench"
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
CONFIG_DIR="$HOME/.config/llama-launcher"
CONFIG_FILE="$CONFIG_DIR/settings.conf"
LOG_DIR="$CONFIG_DIR/logs"
PID_FILE="$CONFIG_DIR/server.pid"

# ─── Colors ────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' B='\033[0;34m'
M='\033[0;35m' C='\033[0;36m' W='\033[1;37m' D='\033[0;90m'
RST='\033[0m'

# ─── Default Settings ─────────────────────────────────────────
S_n_gpu_layers="0"
S_ctx_size="8192"
S_batch_size="2048"
S_ubatch_size="512"
S_threads="12"
S_threads_batch="12"
S_n_predict="-1"
S_parallel_seqs="1"
S_repeat_last_n="64"
S_rope_scaling="none"
S_rope_scale="1.0"
S_rope_freq_base="0.0"
S_rope_freq_scale="0.0"
S_cache_type_k="q4_0"
S_cache_type_v="q4_0"
S_flash_attn="off"
S_mlock="on"
S_no_mmap="on"
S_cont_batching="on"
S_ctx_shift="on"
S_host="127.0.0.1"
S_port="8081"
S_jinja="off"
S_jinja_template=""
S_keep_moe_cpu="off"
S_moe_cpu_layers="0"
S_disable_kv_offload="off"
S_override_tensor=""
S_prompt_cache="0"
S_cache_reuse="0"
S_full_swa_cache="off"
S_keep_first_n="0"
S_auto_start="off"
S_default_model=""
S_fit="on"
S_fit_target="0"

ALL_KEYS=(n_gpu_layers ctx_size batch_size ubatch_size threads threads_batch
  n_predict parallel_seqs repeat_last_n rope_scaling rope_scale rope_freq_base
  rope_freq_scale cache_type_k cache_type_v flash_attn mlock no_mmap
  cont_batching ctx_shift host port jinja jinja_template keep_moe_cpu
  moe_cpu_layers disable_kv_offload override_tensor prompt_cache cache_reuse
  full_swa_cache keep_first_n auto_start default_model fit fit_target)

# ─── Helpers ───────────────────────────────────────────────────
get_setting() { eval "echo \$S_$1"; }
set_setting() { eval "S_$1=\"\$2\""; }

is_our_server_running() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid=$(cat "$PID_FILE")
    kill -0 "$pid" 2>/dev/null || { rm -f "$PID_FILE"; return 1; }
    ps -o command= -p "$pid" 2>/dev/null | grep -q "$SERVER_BIN" || { rm -f "$PID_FILE"; return 1; }
    return 0
}

get_our_pid() {
    [[ -f "$PID_FILE" ]] && cat "$PID_FILE" || echo ""
}

# ─── Functions ─────────────────────────────────────────────────
banner() {
    clear
    echo -e "${C}"
    echo '  ╔═══════════════════════════════════════════════════════╗'
    echo '  ║         llama-cli v1.1.0                             ║'
    echo '  ║         Optimized llama.cpp for Intel Mac             ║'
    echo '  ╚═══════════════════════════════════════════════════════╝'
    echo -e "${RST}"
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    echo "# llama-cli config" > "$CONFIG_FILE"
    for key in "${ALL_KEYS[@]}"; do
        echo "$key=$(get_setting "$key")" >> "$CONFIG_FILE"
    done
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] || return
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# || -z "$key" ]] && continue
        set_setting "$key" "$value"
    done < "$CONFIG_FILE"
}

get_size() {
    local bytes=$(stat -f%z "$1" 2>/dev/null)
    if (( bytes > 1073741824 )); then
        echo "$(echo "scale=1; $bytes/1073741824" | bc) GB"
    elif (( bytes > 1048576 )); then
        echo "$(echo "scale=0; $bytes/1048576" | bc) MB"
    else
        echo "$(echo "scale=0; $bytes/1024" | bc) KB"
    fi
}

# ─── Model Selection ──────────────────────────────────────────
typeset -a MODELS_LIST=()
SELECTED_MODEL=""

scan_models() {
    MODELS_LIST=()
    while IFS= read -r f; do
        [[ "$f" == *mmproj* || -z "$f" ]] && continue
        MODELS_LIST+=("$f")
    done < <(find "$MODELS_DIR" -name "*.gguf" -not -name "*.part" -not -name "mmproj*" 2>/dev/null | sort)
}

select_model() {
    scan_models
    if [[ ${#MODELS_LIST[@]} -eq 0 ]]; then
        echo -e "${R}No .gguf models found in $MODELS_DIR${RST}"
        echo -e "${D}Place .gguf model files in ~/models/${RST}"
        return 1
    fi

    echo -e "${W}Available Models:${RST}"
    echo -e "${D}────────────────────────────────────────────────${RST}"

    local i=1
    for model in "${MODELS_LIST[@]}"; do
        local rel="${model#$MODELS_DIR/}"
        local size=$(get_size "$model")
        local folder=$(dirname "$rel" | xargs basename)
        local fname=$(basename "$rel" .gguf)
        printf "  ${G}%2d${RST}) ${C}%-30s${RST} ${D}%s${RST} ${Y}[%s]${RST}\n" "$i" "$fname" "$folder" "$size"
        ((i++))
    done

    echo ""
    local default_choice=1
    local saved=$(get_setting default_model)
    if [[ -n "$saved" ]]; then
        local idx=1
        for model in "${MODELS_LIST[@]}"; do
            [[ "$model" == "$saved" ]] && { default_choice=$idx; break; }
            ((idx++))
        done
    fi

    echo -n "Select model [${default_choice}]: "
    read choice
    choice="${choice:-$default_choice}"

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#MODELS_LIST[@]} )); then
        echo -e "${R}Invalid selection${RST}"
        return 1
    fi

    SELECTED_MODEL="${MODELS_LIST[$((choice - 1))]}"
    set_setting default_model "$SELECTED_MODEL"
    echo -e "\n${G}Selected:${RST} $(basename "$SELECTED_MODEL")"
    return 0
}

# ─── Settings Configuration ───────────────────────────────────
toggle() {
    local val=$(get_setting "$1")
    [[ "$val" == "on" ]] && set_setting "$1" "off" || set_setting "$1" "on"
    echo -e "  ${Y}$1${RST} = ${C}$(get_setting "$1")${RST}"
}

configure_settings() {
    while true; do
        banner
        echo -e "${W}Configuration${RST}"
        echo -e "${D}────────────────────────────────────────────────${RST}"
        echo ""
        printf "  ${G} 1${RST}) Context Size              ${C}%-10s${RST}\n" "$(get_setting ctx_size)"
        printf "  ${G} 2${RST}) GPU Layers                ${C}%-10s${RST} ${D}(0=CPU only)${RST}\n" "$(get_setting n_gpu_layers)"
        printf "  ${G} 3${RST}) Batch Size                ${C}%-10s${RST}\n" "$(get_setting batch_size)"
        printf "  ${G} 4${RST}) uBatch Size               ${C}%-10s${RST}\n" "$(get_setting ubatch_size)"
        printf "  ${G} 5${RST}) Threads                   ${C}%-10s${RST}\n" "$(get_setting threads)"
        printf "  ${G} 6${RST}) Threads (Batch)           ${C}%-10s${RST}\n" "$(get_setting threads_batch)"
        printf "  ${G} 7${RST}) Max Tokens to Predict     ${C}%-10s${RST} ${D}(-1=infinite)${RST}\n" "$(get_setting n_predict)"
        printf "  ${G} 8${RST}) Parallel Sequences        ${C}%-10s${RST}\n" "$(get_setting parallel_seqs)"
        printf "  ${G} 9${RST}) Repeat Last N             ${C}%-10s${RST}\n" "$(get_setting repeat_last_n)"
        printf "  ${G}10${RST}) KV Cache K Type           ${C}%-10s${RST}\n" "$(get_setting cache_type_k)"
        printf "  ${G}11${RST}) KV Cache V Type           ${C}%-10s${RST}\n" "$(get_setting cache_type_v)"
        printf "  ${G}12${RST}) Flash Attention           ${C}%-10s${RST}\n" "$(get_setting flash_attn)"
        printf "  ${G}13${RST}) MLock                     ${C}%-10s${RST}\n" "$(get_setting mlock)"
        printf "  ${G}14${RST}) Disable mmap              ${C}%-10s${RST}\n" "$(get_setting no_mmap)"
        printf "  ${G}15${RST}) Continuous Batching       ${C}%-10s${RST}\n" "$(get_setting cont_batching)"
        printf "  ${G}16${RST}) Context Shift             ${C}%-10s${RST}\n" "$(get_setting ctx_shift)"
        printf "  ${G}17${RST}) Jinja Chat Template       ${C}%-10s${RST}\n" "$(get_setting jinja)"
        printf "  ${G}18${RST}) Custom Jinja Template     ${C}%-20s${RST}\n" "$(get_setting jinja_template)"
        printf "  ${G}19${RST}) Keep MoE Weights in CPU   ${C}%-10s${RST}\n" "$(get_setting keep_moe_cpu)"
        printf "  ${G}20${RST}) MoE CPU Layers            ${C}%-10s${RST}\n" "$(get_setting moe_cpu_layers)"
        printf "  ${G}21${RST}) Disable KV Offload        ${C}%-10s${RST}\n" "$(get_setting disable_kv_offload)"
        printf "  ${G}22${RST}) Override Tensor Buffer     ${C}%-20s${RST}\n" "$(get_setting override_tensor)"
        printf "  ${G}23${RST}) RoPE Scaling Method       ${C}%-10s${RST}\n" "$(get_setting rope_scaling)"
        printf "  ${G}24${RST}) RoPE Scale Factor         ${C}%-10s${RST}\n" "$(get_setting rope_scale)"
        printf "  ${G}25${RST}) RoPE Frequency Base       ${C}%-10s${RST}\n" "$(get_setting rope_freq_base)"
        printf "  ${G}26${RST}) RoPE Freq Scale Factor    ${C}%-10s${RST}\n" "$(get_setting rope_freq_scale)"
        printf "  ${G}27${RST}) Fit (auto-adjust memory)  ${C}%-10s${RST}\n" "$(get_setting fit)"
        printf "  ${G}28${RST}) Fit Target per Device     ${C}%-10s${RST} ${D}(MiB, 0=auto)${RST}\n" "$(get_setting fit_target)"
        printf "  ${G}29${RST}) Prompt Cache RAM          ${C}%-10s${RST} ${D}(MiB)${RST}\n" "$(get_setting prompt_cache)"
        printf "  ${G}30${RST}) Cache Reuse               ${C}%-10s${RST} ${D}(0=off, token chunk size)${RST}\n" "$(get_setting cache_reuse)"
        printf "  ${G}31${RST}) Full SWA Cache            ${C}%-10s${RST} ${D}(stored only; unsupported by this build)${RST}\n" "$(get_setting full_swa_cache)"
        printf "  ${G}32${RST}) Keep First N Tokens       ${C}%-10s${RST} ${D}(stored only; unsupported by this build)${RST}\n" "$(get_setting keep_first_n)"
        printf "  ${G}33${RST}) Server Port               ${C}%-10s${RST}\n" "$(get_setting port)"
        printf "  ${G}34${RST}) Server Host               ${C}%-10s${RST}\n" "$(get_setting host)"
        printf "  ${G}35${RST}) Auto Start Server         ${C}%-10s${RST}\n" "$(get_setting auto_start)"
        echo ""
        echo -e "  ${Y} s${RST}) Save & Return"
        echo -e "  ${Y} r${RST}) Reset to Defaults"
        echo ""
        echo -n "Select setting [s]: "
        read sel
        sel="${sel:-s}"

        case "$sel" in
            1)  echo -n "Context Size [$(get_setting ctx_size)]: "; read v; [[ -n "$v" ]] && set_setting ctx_size "$v" ;;
            2)  echo -n "GPU Layers [$(get_setting n_gpu_layers)]: "; read v; [[ -n "$v" ]] && set_setting n_gpu_layers "$v" ;;
            3)  echo -n "Batch Size [$(get_setting batch_size)]: "; read v; [[ -n "$v" ]] && set_setting batch_size "$v" ;;
            4)  echo -n "uBatch Size [$(get_setting ubatch_size)]: "; read v; [[ -n "$v" ]] && set_setting ubatch_size "$v" ;;
            5)  echo -n "Threads [$(get_setting threads)]: "; read v; [[ -n "$v" ]] && set_setting threads "$v" ;;
            6)  echo -n "Threads Batch [$(get_setting threads_batch)]: "; read v; [[ -n "$v" ]] && set_setting threads_batch "$v" ;;
            7)  echo -n "Max Tokens [$(get_setting n_predict)]: "; read v; [[ -n "$v" ]] && set_setting n_predict "$v" ;;
            8)  echo -n "Parallel Sequences [$(get_setting parallel_seqs)]: "; read v; [[ -n "$v" ]] && set_setting parallel_seqs "$v" ;;
            9)  echo -n "Repeat Last N [$(get_setting repeat_last_n)]: "; read v; [[ -n "$v" ]] && set_setting repeat_last_n "$v" ;;
            10) echo -n "KV Cache K Type [$(get_setting cache_type_k)]: "; read v; [[ -n "$v" ]] && set_setting cache_type_k "$v" ;;
            11) echo -n "KV Cache V Type [$(get_setting cache_type_v)]: "; read v; [[ -n "$v" ]] && set_setting cache_type_v "$v" ;;
            12) toggle "flash_attn" ;;
            13) toggle "mlock" ;;
            14) toggle "no_mmap" ;;
            15) toggle "cont_batching" ;;
            16) toggle "ctx_shift" ;;
            17) toggle "jinja" ;;
            18) echo -n "Jinja Template [$(get_setting jinja_template)]: "; read v; set_setting jinja_template "$v" ;;
            19) toggle "keep_moe_cpu" ;;
            20) echo -n "MoE CPU Layers [$(get_setting moe_cpu_layers)]: "; read v; [[ -n "$v" ]] && set_setting moe_cpu_layers "$v" ;;
            21) toggle "disable_kv_offload" ;;
            22) echo -n "Override Tensor [$(get_setting override_tensor)]: "; read v; set_setting override_tensor "$v" ;;
            23) echo -n "RoPE Scaling [$(get_setting rope_scaling)]: "; read v; [[ -n "$v" ]] && set_setting rope_scaling "$v" ;;
            24) echo -n "RoPE Scale [$(get_setting rope_scale)]: "; read v; [[ -n "$v" ]] && set_setting rope_scale "$v" ;;
            25) echo -n "RoPE Freq Base [$(get_setting rope_freq_base)]: "; read v; [[ -n "$v" ]] && set_setting rope_freq_base "$v" ;;
            26) echo -n "RoPE Freq Scale [$(get_setting rope_freq_scale)]: "; read v; [[ -n "$v" ]] && set_setting rope_freq_scale "$v" ;;
            27) toggle "fit" ;;
            28) echo -n "Fit Target MiB [$(get_setting fit_target)]: "; read v; [[ -n "$v" ]] && set_setting fit_target "$v" ;;
            29) echo -n "Prompt Cache MiB [$(get_setting prompt_cache)]: "; read v; [[ -n "$v" ]] && set_setting prompt_cache "$v" ;;
            30) echo -n "Cache Reuse token chunk size, 0=off [$(get_setting cache_reuse)]: "; read v; [[ -n "$v" ]] && set_setting cache_reuse "$v" ;;
            31) toggle "full_swa_cache" ;;
            32) echo -n "Keep First N [$(get_setting keep_first_n)]: "; read v; [[ -n "$v" ]] && set_setting keep_first_n "$v" ;;
            33) echo -n "Port [$(get_setting port)]: "; read v; [[ -n "$v" ]] && set_setting port "$v" ;;
            34) echo -n "Host [$(get_setting host)]: "; read v; [[ -n "$v" ]] && set_setting host "$v" ;;
            35) toggle "auto_start" ;;
            s|S) save_config; return ;;
            r|R) reset_defaults ;;
        esac
    done
}

reset_defaults() {
    S_n_gpu_layers="0"; S_ctx_size="8192"; S_batch_size="2048"
    S_ubatch_size="512"; S_threads="12"; S_threads_batch="12"
    S_n_predict="-1"; S_parallel_seqs="1"; S_repeat_last_n="64"
    S_rope_scaling="none"; S_rope_scale="1.0"; S_rope_freq_base="0.0"
    S_rope_freq_scale="0.0"; S_cache_type_k="q4_0"; S_cache_type_v="q4_0"
    S_flash_attn="off"; S_mlock="on"; S_no_mmap="on"
    S_cont_batching="on"; S_ctx_shift="on"; S_host="127.0.0.1"
    S_port="8081"; S_jinja="off"; S_jinja_template=""
    S_keep_moe_cpu="off"; S_moe_cpu_layers="0"; S_disable_kv_offload="off"
    S_override_tensor=""; S_prompt_cache="0"; S_cache_reuse="0"
    S_full_swa_cache="off"; S_keep_first_n="0"; S_auto_start="off"
    S_default_model=""; S_fit="on"; S_fit_target="0"
    echo -e "  ${G}Settings reset${RST}"
    sleep 1
}

# ─── Build Command ─────────────────────────────────────────────
build_command() {
    local model="$1"
    local cmd="\"$SERVER_BIN\" -m \"$model\""
    cmd+=" -ngl $(get_setting n_gpu_layers)"
    cmd+=" -c $(get_setting ctx_size)"
    cmd+=" -b $(get_setting batch_size)"
    cmd+=" -ub $(get_setting ubatch_size)"
    cmd+=" -t $(get_setting threads)"
    cmd+=" -tb $(get_setting threads_batch)"
    cmd+=" -n $(get_setting n_predict)"
    cmd+=" -np $(get_setting parallel_seqs)"
    cmd+=" --repeat-last-n $(get_setting repeat_last_n)"
    cmd+=" --port $(get_setting port)"
    cmd+=" --host $(get_setting host)"

    [[ "$(get_setting cache_type_k)" != "f16" ]] && cmd+=" --cache-type-k $(get_setting cache_type_k)"
    [[ "$(get_setting cache_type_v)" != "f16" ]] && cmd+=" --cache-type-v $(get_setting cache_type_v)"
    [[ "$(get_setting mlock)" == "on" ]] && cmd+=" --mlock"
    [[ "$(get_setting no_mmap)" == "on" ]] && cmd+=" --no-mmap"
    [[ "$(get_setting cont_batching)" == "on" ]] && cmd+=" --cont-batching"
    [[ "$(get_setting ctx_shift)" == "on" ]] && cmd+=" --context-shift"
    [[ "$(get_setting flash_attn)" == "on" ]] && cmd+=" --flash-attn on"
    [[ "$(get_setting jinja)" == "on" ]] && cmd+=" --jinja"
    [[ "$(get_setting disable_kv_offload)" == "on" ]] && cmd+=" --no-kv-offload"
    [[ "$(get_setting fit)" == "on" ]] && cmd+=" --fit on" || cmd+=" --fit off"

    [[ -n "$(get_setting jinja_template)" ]] && cmd+=" --chat-template '$(get_setting jinja_template)'"
    [[ -n "$(get_setting override_tensor)" ]] && cmd+=" --override-tensor '$(get_setting override_tensor)'"
    [[ "$(get_setting keep_moe_cpu)" == "on" ]] && cmd+=" --cpu-moe"
    [[ "$(get_setting moe_cpu_layers)" -gt 0 ]] 2>/dev/null && cmd+=" --n-cpu-moe $(get_setting moe_cpu_layers)"
    [[ "$(get_setting rope_scaling)" != "none" ]] && cmd+=" --rope-scaling $(get_setting rope_scaling)"
    [[ "$(get_setting rope_scale)" != "1.0" ]] && cmd+=" --rope-scale $(get_setting rope_scale)"
    [[ "$(get_setting rope_freq_base)" != "0.0" ]] && cmd+=" --rope-freq-base $(get_setting rope_freq_base)"
    [[ "$(get_setting rope_freq_scale)" != "0.0" ]] && cmd+=" --rope-freq-scale $(get_setting rope_freq_scale)"
    [[ "$(get_setting fit_target)" != "0" ]] && cmd+=" --fit-target $(get_setting fit_target)"
    [[ "$(get_setting prompt_cache)" != "0" ]] && cmd+=" --cache-ram $(get_setting prompt_cache)"
    [[ "$(get_setting cache_reuse)" != "0" ]] && cmd+=" --cache-reuse $(get_setting cache_reuse)"
    # full_swa_cache and keep_first_n are retained in config for compatibility
    # with frontends that expose them, but this pinned llama-server does not.

    echo "$cmd"
}

# ─── Server Management ────────────────────────────────────────
start_server() {
    local model="$1"

    if [[ -z "$model" ]]; then
        echo -e "${R}No model selected${RST}"
        return 1
    fi

    if is_our_server_running; then
        echo -e "${Y}Server already running (PID: $(get_our_pid)). Stop it first (option 4).${RST}"
        return 1
    fi

    echo -e "${D}Purging macOS memory...${RST}"
    sudo purge 2>/dev/null || true

    local cmd=$(build_command "$model")
    local logfile="$LOG_DIR/llama-server-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$LOG_DIR"

    echo -e "${G}Starting server...${RST}"
    echo -e "${D}Log: $logfile${RST}"
    echo ""

    eval "$cmd" > "$logfile" 2>&1 &
    local server_pid=$!
    echo "$server_pid" > "$PID_FILE"

    echo -e "${W}Waiting for server (PID: $server_pid)...${RST}"
    local elapsed=0
    while (( elapsed < 180 )); do
        if ! kill -0 "$server_pid" 2>/dev/null; then
            echo -e "${R}Server died. Last 20 lines of log:${RST}"
            tail -20 "$logfile"
            rm -f "$PID_FILE"
            return 1
        fi
        if curl -s "http://$(get_setting host):$(get_setting port)/health" 2>/dev/null | grep -q ok; then
            echo -e "${G}Server ready! PID: $server_pid${RST}"
            echo -e "${C}API: http://$(get_setting host):$(get_setting port)/v1${RST}"
            echo -e "${C}Key: dummy${RST}"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    echo -e "${Y}Still loading after 180s. Check log: $logfile${RST}"
}

stop_server() {
    if is_our_server_running; then
        local pid=$(get_our_pid)
        echo -e "${Y}Stopping server (PID: $pid)...${RST}"
        kill "$pid" 2>/dev/null
        sleep 1
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        rm -f "$PID_FILE"
        echo -e "${G}Server stopped${RST}"
    else
        echo -e "${D}Server is not running${RST}"
        rm -f "$PID_FILE"
    fi
}

eject_model() {
    if ! is_our_server_running; then
        echo -e "${D}Server is not running${RST}"
        return
    fi
    echo -e "${Y}Ejecting model...${RST}"
    local result=$(curl -s -X POST "http://$(get_setting host):$(get_setting port)/unload" 2>/dev/null)
    if [[ -n "$result" ]]; then
        echo -e "${G}Model ejected${RST}"
    else
        echo -e "${Y}API unload not available. Stopping server...${RST}"
        stop_server
    fi
}

server_status() {
    echo -e "${W}Server Status:${RST}"
    echo -e "${D}────────────────────────────────────────────────${RST}"

    if is_our_server_running; then
        local pid=$(get_our_pid)
        local mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%.1f GB", $1/1024/1024}')
        local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | xargs)

        echo -e "  Status:   ${G}Running${RST} (PID: ${C}$pid${RST})"
        echo -e "  Memory:   ${C}$mem${RST}   Uptime: ${C}$uptime${RST}"

        local health=$(curl -s "http://$(get_setting host):$(get_setting port)/health" 2>/dev/null)
        if echo "$health" | grep -q ok; then
            echo -e "  Health:   ${G}OK${RST}"
            local resp=$(curl -s "http://$(get_setting host):$(get_setting port)/v1/models" 2>/dev/null)
            if [[ -n "$resp" ]]; then
                local mn=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null)
                [[ -n "$mn" ]] && echo -e "  Model:    ${C}$mn${RST}"
            fi
        else
            echo -e "  Health:   ${Y}Loading...${RST}"
        fi
    else
        echo -e "  Status:   ${R}Stopped${RST}"
    fi

    echo ""
    echo -e "${W}Settings:${RST} Threads=${C}$(get_setting threads)${RST}  Context=${C}$(get_setting ctx_size)${RST}  Batch=${C}$(get_setting batch_size)${RST}  KV=${C}$(get_setting cache_type_k)/$(get_setting cache_type_v)${RST}"
}

view_log() {
    local latest=$(ls -t "$LOG_DIR"/llama-server-*.log 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
        echo -e "${W}Log: $latest${RST}"
        echo -e "${D}────────────────────────────────────────────────${RST}"
        tail -30 "$latest"
    else
        echo -e "${D}No logs found${RST}"
    fi
}

# ─── Main Menu ─────────────────────────────────────────────────
main() {
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    load_config
    if [[ ! -x "$SERVER_BIN" ]]; then
        echo -e "${R}llama-server not found or not executable:${RST} $SERVER_BIN"
        echo "Set LLAMA_DIR to a directory that contains bin/llama-server."
        exit 1
    fi
    [[ -n "$(get_setting default_model)" && -f "$(get_setting default_model)" ]] && SELECTED_MODEL="$(get_setting default_model)"
    if [[ "$(get_setting auto_start)" == "on" && -n "$SELECTED_MODEL" && ! is_our_server_running ]]; then
        start_server "$SELECTED_MODEL"
        sleep 1
    fi

    while true; do
        banner
        server_status
        echo ""
        echo -e "${W}Actions:${RST}"
        echo -e "${D}────────────────────────────────────────────────${RST}"
        echo -e "  ${G}1${RST}) Select Model"
        echo -e "  ${G}2${RST}) Configure Settings (35 options)"
        echo -e "  ${G}3${RST}) Start Server"
        echo -e "  ${G}4${RST}) Stop Server"
        echo -e "  ${G}5${RST}) Eject Model (unload without stopping)"
        echo -e "  ${G}6${RST}) View Server Log"
        echo -e "  ${G}7${RST}) Purge Memory"
        echo -e "  ${G}8${RST}) Benchmark Current Model"
        echo ""
        echo -e "  ${R}q${RST}) Quit"
        echo ""

        [[ -n "$SELECTED_MODEL" ]] && echo -e "  ${D}Selected: $(basename "$SELECTED_MODEL")${RST}"

        echo -n "Choice: "
        read choice

        case "$choice" in
            1) select_model ;;
            2) configure_settings ;;
            3)
                if [[ -z "$SELECTED_MODEL" ]]; then
                    echo -e "${Y}Select a model first (option 1)${RST}"
                    sleep 1
                else
                    start_server "$SELECTED_MODEL"
                    echo -n "Press Enter..."; read _
                fi
                ;;
            4) stop_server; sleep 1 ;;
            5) eject_model; sleep 2 ;;
            6) view_log; echo ""; echo -n "Press Enter..."; read _ ;;
            7) sudo purge 2>/dev/null && echo -e "${G}Done${RST}" || echo -e "${Y}Needs sudo${RST}"; sleep 1 ;;
            8)
                if [[ -n "$SELECTED_MODEL" ]]; then
                    "$BENCH_BIN" -m "$SELECTED_MODEL" -ngl 0 -t "$(get_setting threads)" 2>&1 | tail -20
                    echo -n "Press Enter..."; read _
                else
                    echo -e "${Y}Select a model first${RST}"; sleep 1
                fi
                ;;
            q|Q) stop_server 2>/dev/null; echo -e "${G}Goodbye!${RST}"; exit 0 ;;
        esac
    done
}

main "$@"
