#!/usr/bin/env zsh
# ╔══════════════════════════════════════════════════════════════╗
# ║  intellama — Interactive llama.cpp Launcher                 ║
# ║  (formerly llama-cli)  Optimized for Intel Mac Pro 2013    ║
# ╚══════════════════════════════════════════════════════════════╝

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

# Read version from package.json (written at postinstall time as a fallback)
VERSION_FILE="$PACKAGE_DIR/VERSION"
if [[ -f "$VERSION_FILE" ]]; then
    VERSION=$(cat "$VERSION_FILE" 2>/dev/null | tr -d '[:space:]')
fi
if [[ -z "$VERSION" ]]; then
    VERSION=$(node -p "require('$PACKAGE_DIR/package.json').version" 2>/dev/null) || VERSION="unknown"
fi

# Hardware detection results (set by detect_hardware)
typeset -g HW_PHYSICAL_CORES=0
typeset -g HW_LOGICAL_CORES=0
typeset -g HW_MEM_GB=0
typeset -g HW_CPU_BRAND=""
typeset -g HW_HAS_AVX=0
typeset -g HW_HAS_AVX2=0
typeset -g HW_HAS_FMA=0
typeset -g HW_HAS_F16C=0
typeset -g HW_IS_IVYBRIDGE=0

# ─── Colors ────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' B='\033[0;34m'
M='\033[0;35m' C='\033[0;36m' W='\033[1;37m' D='\033[0;90m'
RST='\033[0m'

# ─── Default Settings ─────────────────────────────────────────
S_n_gpu_layers="0"
S_ctx_size="8192"
S_batch_size="2048"
S_ubatch_size="512"
S_threads="0"
S_threads_batch="0"
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
S_spec_type="off"
S_spec_draft_model=""
S_spec_n_max="16"
S_spec_n_min="0"

ALL_KEYS=(n_gpu_layers ctx_size batch_size ubatch_size threads threads_batch
  n_predict parallel_seqs repeat_last_n rope_scaling rope_scale rope_freq_base
  rope_freq_scale cache_type_k cache_type_v flash_attn mlock no_mmap
  cont_batching ctx_shift host port jinja jinja_template keep_moe_cpu
  moe_cpu_layers disable_kv_offload override_tensor prompt_cache cache_reuse
  full_swa_cache keep_first_n auto_start default_model fit fit_target
  spec_type spec_draft_model spec_n_max spec_n_min)

# ─── Helpers ───────────────────────────────────────────────────
get_setting() { eval "echo \$S_$1"; }
set_setting() {
    local key="$1"
    local value="$2"
    case "$key" in
        spec_type)
            case "$value" in
                off|none|ngram-simple|ngram-mod|ngram-cache|draft-mtp) ;;
                *) print -r -- "[intellama] invalid spec_type: $value (allowed: off|ngram-simple|ngram-mod|ngram-cache|draft-mtp)"; return 1 ;;
            esac
            ;;
        n_gpu_layers|threads|threads_batch|batch_size|ubatch_size|ctx_size|n_predict|parallel_seqs|repeat_last_n|moe_cpu_layers|fit_target|prompt_cache|cache_reuse|keep_first_n|port|spec_n_max|spec_n_min|spec_ngram_simple_size_n|spec_ngram_simple_size_m|spec_ngram_simple_min_hits|spec_ngram_mod_n_min|spec_ngram_mod_n_max|spec_ngram_mod_n_match|cache_ram_mib)
            if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
                print -r -- "[intellama] invalid $key (not an integer): $value"; return 1
            fi
            ;;
        rope_scale|rope_freq_base|rope_freq_scale)
            if ! [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                print -r -- "[intellama] invalid $key (not a number): $value"; return 1
            fi
            ;;
        *) ;;
    esac
    eval "S_$key=\"\$value\""
}

detect_hardware() {
  HW_PHYSICAL_CORES=$(sysctl -n hw.physicalcpu 2>/dev/null || echo 0)
  HW_LOGICAL_CORES=$(sysctl -n hw.logicalcpu 2>/dev/null || echo "$HW_PHYSICAL_CORES")
  local mem_bytes
  mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  HW_MEM_GB=$(( mem_bytes / 1073741824 ))
  HW_CPU_BRAND=$(sysctl -n machdep.cpu.brand_string 2>/dev/null | sed 's/^ *//;s/ *$//')
  local feats leaf7
  feats=$(sysctl -n machdep.cpu.features 2>/dev/null || echo "")
  leaf7=$(sysctl -n machdep.cpu.leaf7_features 2>/dev/null || echo "")
  [[ "$feats" == *AVX1.0* || "$feats" == *AVX* ]] && HW_HAS_AVX=1
  [[ "$leaf7" == *AVX2* ]] && HW_HAS_AVX2=1
  [[ "$feats" == *FMA* ]] && HW_HAS_FMA=1
  [[ "$feats" == *F16C* ]] && HW_HAS_F16C=1
  # Ivy Bridge = AVX+F16C, no AVX2, no FMA
  if [[ $HW_HAS_AVX -eq 1 && $HW_HAS_AVX2 -eq 0 && $HW_HAS_FMA -eq 0 && $HW_HAS_F16C -eq 1 ]]; then
    HW_IS_IVYBRIDGE=1
  fi
}

show_hardware() {
    banner
    echo -e "${W}Hardware Information:${RST}"
    echo -e "${D}────────────────────────────────────────────────${RST}"
    echo -e "  CPU Brand:     ${C}$HW_CPU_BRAND${RST}"
    echo -e "  Physical Cores:${C}$HW_PHYSICAL_CORES${RST}"
    echo -e "  Logical Cores: ${C}$HW_LOGICAL_CORES${RST}"
    echo -e "  Memory (RAM):  ${C}$HW_MEM_GB GB${RST}"
    echo -e "  Features:      AVX=${C}$HW_HAS_AVX${RST} AVX2=${C}$HW_HAS_AVX2${RST} FMA=${C}$HW_HAS_FMA${RST} F16C=${C}$HW_HAS_F16C${RST}"
    echo -e "  Ivy Bridge:    ${C}$HW_IS_IVYBRIDGE${RST}"
}

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
    printf '  ║         intellama %-34s║\n' "v$VERSION"
    echo '  ║         Optimized llama.cpp for Intel Mac             ║'
    echo '  ╚═══════════════════════════════════════════════════════╝'
    echo -e "${RST}"
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    echo "# intellama v$VERSION config" > "$CONFIG_FILE"
    for key in "${ALL_KEYS[@]}"; do
        echo "$key=$(get_setting "$key")" >> "$CONFIG_FILE"
    done
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] || return
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^# || -z "$key" ]] && continue
        if ! set_setting "$key" "$value"; then
            local default_var="S_$key"
            print -r -- "[intellama] config: invalid $key='$value', reset to default (${(P)default_var})"
        fi
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
        printf "  ${G}36${RST}) Speculative Type          ${C}%-10s${RST}\n" "$(get_setting spec_type)"
        printf "  ${G}37${RST}) Spec Draft Model          ${C}%-20s${RST}\n" "$(get_setting spec_draft_model)"
        printf "  ${G}38${RST}) Spec Draft N Max         ${C}%-10s${RST}\n" "$(get_setting spec_n_max)"
        printf "  ${G}39${RST}) Spec Draft N Min         ${C}%-10s${RST}\n" "$(get_setting spec_n_min)"
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
            36) echo -n "Spec Type (off|ngram-simple|ngram-mod|ngram-cache|draft-mtp) [$(get_setting spec_type)]: "; read v; [[ -n "$v" ]] && set_setting spec_type "$v" ;;
            37) echo -n "Spec Draft Model Path [$(get_setting spec_draft_model)]: "; read v; set_setting spec_draft_model "$v" ;;
            38) echo -n "Spec Draft N Max [$(get_setting spec_n_max)]: "; read v; [[ -n "$v" ]] && set_setting spec_n_max "$v" ;;
            39) echo -n "Spec Draft N Min [$(get_setting spec_n_min)]: "; read v; [[ -n "$v" ]] && set_setting spec_n_min "$v" ;;
            s|S) save_config; return ;;
            r|R) reset_defaults ;;
        esac
    done
}

reset_defaults() {
    S_n_gpu_layers="0"; S_ctx_size="8192"; S_batch_size="2048"
    S_ubatch_size="512"; S_threads="0"; S_threads_batch="0"
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
    S_spec_type="off"; S_spec_draft_model=""; S_spec_n_max="16"; S_spec_n_min="0"
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

    case "$(get_setting spec_type)" in
        off) ;;
        ngram-simple|ngram-mod|ngram-cache)
            cmd+=" --spec-type $(get_setting spec_type)" ;;
        draft-mtp)
            cmd+=" --spec-type draft-mtp"
            [[ -n "$(get_setting spec_draft_model)" ]] && cmd+=" --spec-draft-model '$(get_setting spec_draft_model)'" ;;
    esac
    if [[ "$(get_setting spec_type)" != "off" ]]; then
        cmd+=" --spec-draft-n-max $(get_setting spec_n_max)"
        [[ "$(get_setting spec_n_min)" -gt 0 ]] && cmd+=" --spec-draft-n-min $(get_setting spec_n_min)"
    fi

    [[ -n "$(get_setting jinja_template)" ]] && cmd+=" --chat-template '$(get_setting jinja_template)'"
    [[ -n "$(get_setting override_tensor)" ]] && cmd+=" --override-tensor '$(get_setting override_tensor)'"
    [[ "$(get_setting keep_moe_cpu)" == "on" ]] && cmd+=" --cpu-moe"
    [[ "$(get_setting moe_cpu_layers)" -gt 0 ]] 2>/dev/null && cmd+=" --n-cpu-moe $(get_setting moe_cpu_layers)"
    [[ "$(get_setting rope_scaling)" != "none" ]] && cmd+=" --rope-scaling $(get_setting rope_scaling)"
    [[ "$(get_setting rope_scale)" != "1.0" ]] && cmd+=" --rope-scale $(get_setting rope_scale)"
    [[ "$(get_setting rope_freq_base)" != "0.0" ]] && cmd+=" --rope-freq-base $(get_setting rope_freq_base)"
    [[ "$(get_setting rope_freq_scale)" != "0.0" ]] && cmd+=" --rope-freq-scale $(get_setting rope_freq_scale)"
    [[ "$(get_setting fit_target)" != "0" ]] && cmd+=" --fit-target $(get_setting fit_target)"
    local creuse=$(get_setting cache_reuse)
    [[ "$creuse" =~ ^[1-9][0-9]*$ ]] && cmd+=" --cache-reuse $creuse"
    # cache_ram_mib is the canonical MiB cap; prompt_cache is the legacy alias.
    local crammib=$(get_setting cache_ram_mib)
    if [[ "$crammib" =~ ^[1-9][0-9]*$ ]]; then
        cmd+=" --cache-ram $crammib"
    else
        local cram=$(get_setting prompt_cache)
        [[ "$cram" =~ ^[1-9][0-9]*$ ]] && cmd+=" --cache-ram $cram"
    fi
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
    detect_hardware
    load_config
    [[ "$S_threads" == "0" && $HW_PHYSICAL_CORES -gt 0 ]] && S_threads=$HW_PHYSICAL_CORES
    [[ "$S_threads_batch" == "0" && $HW_PHYSICAL_CORES -gt 0 ]] && S_threads_batch=$HW_PHYSICAL_CORES
    [[ $HW_IS_IVYBRIDGE -eq 1 && "$S_spec_n_max" -gt 16 ]] && S_spec_n_max="16"
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
        echo -e "  ${G}2${RST}) Configure Settings (${#ALL_KEYS[@]} options)"
        echo -e "  ${G}3${RST}) Start Server"
        echo -e "  ${G}4${RST}) Stop Server"
        echo -e "  ${G}5${RST}) Eject Model (unload without stopping)"
        echo -e "  ${G}6${RST}) View Server Log"
        echo -e "  ${G}7${RST}) Purge Memory"
        echo -e "  ${G}8${RST}) Benchmark Current Model"
        echo -e "  ${G}h${RST}) Show Hardware"
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
            h|H) show_hardware; echo ""; echo -n "Press Enter..."; read _ ;;
            q|Q) stop_server 2>/dev/null; echo -e "${G}Goodbye!${RST}"; exit 0 ;;
        esac
    done
}

main "$@"
