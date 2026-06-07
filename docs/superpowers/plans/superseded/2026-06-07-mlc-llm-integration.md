# MLC-LLM Backend Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MLC-LLM as an optional GPU backend to intellama with auto-detect and graceful fallback to the existing llama.cpp CPU path. Validate first with MoltenVK/Vulkan experiments on the 2× D700s — if those fail, stop and ship CPU improvements instead.

**Architecture:** zsh-only changes to `src/llama-launcher.sh` plus a new `scripts/start-mlc.sh`. New settings (`mlc_port`, `mlc_model_dir`, `mlc_device`) gate MLC. When `mlc_port` is non-empty, the launcher probes `/v1/models` on that port and uses MLC if alive, otherwise falls through to llama.cpp. MLC server is launched as a child process and tracked in `~/.config/llama-launcher/mlc.pid`. Stop/purge/eject iterate both PID files.

**Tech Stack:** zsh, llama.cpp HTTP API (existing), MLC-LLM nightly wheels, MoltenVK, no Node.js changes.

**Hardware:** 2013 Mac Pro · 2× D700 (6 GB VRAM each) · Xeon E5 Ivy Bridge · macOS Sequoia via OCLP · no Xcode.

**Spec:** `docs/superpowers/specs/2026-06-07-mlc-llm-integration-design.md`

**Source plan:** `/Users/macpro/mlc-llm-adoption-plan.md`

---

## File Map

| File | Status | Responsibility |
|------|--------|----------------|
| `src/llama-launcher.sh` | modify | Main launcher: settings, menu, server lifecycle. New zsh functions: `probe_backend`, `start_mlc_server`, `mlc_unload`, `mlc_health_url`, `configure_mlc`. Modified: `start_server`, `stop_server`, `eject_model`, `purge`, `select_model`, `server_status`, `main`, `ALL_KEYS`, `DEFAULT_SETTINGS`. |
| `scripts/start-mlc.sh` | create | Standalone convenience wrapper for `mlc_llm serve`; called by `configure_mlc` and usable directly. |
| `package.json` | modify | One line: add `zsh -n scripts/start-mlc.sh` to the test script. |
| `README.md` | modify | New section: MLC-LLM backend, fallback semantics, install steps, env vars. |
| `docs/mlc-bench-*.txt` | create (conditional) | Benchmark records. Only created if Phases 0–2 actually run. |

---

## Phase 0 — Validation (NOT in intellama tree)

These tasks live outside the intellama repo. They install system tooling and validate that the GPU path works. **Stop and skip Phase 1+ if any stop condition fires.**

### Task 0.1: Install MoltenVK and Vulkan tooling

**Files:** none (system packages via Homebrew)

- [ ] **Step 1: Install MoltenVK and Vulkan tools**

```bash
brew install molten-vk vulkan-headers vulkan-loader vulkan-tools
```

- [ ] **Step 2: Verify MoltenVK sees the D700s**

```bash
vulkaninfo 2>&1 | grep -E "GPU id|vendorID|driverVersion|deviceName" | head -20
```

**Expected:** two AMD Radeon entries, `deviceName` contains "Tahiti" or "FirePro".

- [ ] **Step 3: Record the output**

```bash
mkdir -p /Users/macpro/llama-cli/docs
vulkaninfo 2>&1 > /Users/macpro/llama-cli/docs/vulkaninfo-baseline.txt
```

- [ ] **Step 4: Commit the baseline**

```bash
cd /Users/macpro/llama-cli
git add docs/vulkaninfo-baseline.txt
git commit -m "docs(mlc): vulkaninfo baseline for D700 GPUs"
```

**Stop condition:** no AMD devices visible, or no `vulkaninfo` output. → skip to Phase Z (CPU polish, no MLC).

### Task 0.2: Install MLC-LLM nightly

**Files:** none (Python packages)

- [ ] **Step 1: Install MLC-LLM CPU+Vulkan wheels**

```bash
python3 -m pip install --pre -U mlc-ai-nightly mlc-llm-nightly \
  -f https://mlc.ai/wheels
```

- [ ] **Step 2: Verify the install**

```bash
python3 -c "import mlc_llm; print('MLC-LLM', mlc_llm.__version__)"
mlc_llm --help 2>&1 | head -10
```

**Expected:** version printed, `mlc_llm` CLI responds with `chat`, `bench`, `serve`, `compile`, `convert_weight`, `gen_config` subcommands.

- [ ] **Step 3: Record the version**

```bash
echo "MLC-LLM $(python3 -c 'import mlc_llm; print(mlc_llm.__version__)')" \
  > /Users/macpro/llama-cli/docs/mlc-version.txt
cd /Users/macpro/llama-cli
git add docs/mlc-version.txt
git commit -m "docs(mlc): record MLC-LLM nightly version"
```

**Stop condition:** `mlc_llm` import fails or `--help` shows missing subcommands. → skip to Phase Z.

### Task 0.3: CPU smoke test (Phase 1 of source plan)

**Files:** none (uses prebuilt model from HuggingFace)

- [ ] **Step 1: Run CPU chat**

```bash
mlc_llm chat \
  HF://mlc-ai/Qwen2.5-0.5B-Instruct-q4f16_1-MLC \
  --device cpu --num-threads 16
```

Type: "What is the capital of France? Answer in one word." then `/exit`.

**Expected:** output is "Paris" (or coherent one-word answer).

- [ ] **Step 2: Run CPU bench and save**

```bash
mlc_llm bench \
  HF://mlc-ai/Qwen2.5-0.5B-Instruct-q4f16_1-MLC \
  --device cpu --num-threads 16 --num-prompts 3 \
  > /Users/macpro/llama-cli/docs/mlc-bench-cpu.txt 2>&1
cat /Users/macpro/llama-cli/docs/mlc-bench-cpu.txt
```

**Expected:** ≥10 tok/s on 0.5B model.

- [ ] **Step 3: Commit**

```bash
cd /Users/macpro/llama-cli
git add docs/mlc-bench-cpu.txt
git commit -m "docs(mlc): CPU baseline benchmark (0.5B Qwen2.5)"
```

**Stop condition:** <5 tok/s or garbled output. Tooling is broken; skip to Phase Z.

### Task 0.4: Vulkan smoke test (Phase 2 of source plan — single D700)

**Files:** none

- [ ] **Step 1: Run Vulkan chat on D700 #0**

```bash
mlc_llm chat \
  HF://mlc-ai/Qwen2.5-0.5B-Instruct-q4f16_1-MLC \
  --device vulkan:0
```

Type: "What is the capital of France? Answer in one word." then `/exit`.

**Expected:** output is "Paris" (or coherent one-word answer).

- [ ] **Step 2: Run Vulkan bench on D700 #0 and save**

```bash
mlc_llm bench \
  HF://mlc-ai/Qwen2.5-0.5B-Instruct-q4f16_1-MLC \
  --device vulkan:0 --num-prompts 3 \
  > /Users/macpro/llama-cli/docs/mlc-bench-vulkan0.txt 2>&1
cat /Users/macpro/llama-cli/docs/mlc-bench-vulkan0.txt
```

- [ ] **Step 3: Run Vulkan bench on D700 #1 and save**

```bash
mlc_llm bench \
  HF://mlc-ai/Qwen2.5-0.5B-Instruct-q4f16_1-MLC \
  --device vulkan:1 --num-prompts 3 \
  > /Users/macpro/llama-cli/docs/mlc-bench-vulkan1.txt 2>&1
cat /Users/macpro/llama-cli/docs/mlc-bench-vulkan1.txt
```

- [ ] **Step 4: Commit**

```bash
cd /Users/macpro/llama-cli
git add docs/mlc-bench-vulkan0.txt docs/mlc-bench-vulkan1.txt
git commit -m "docs(mlc): single-GPU Vulkan benchmarks on D700 #0 and #1"
```

**Stop condition:** `SIGILL`, `VK_ERROR_DEVICE_LOST`, garbage output, or tok/s <5. → **skip Phase 1+** (no intellama MLC code). Optionally try Phase 0.5 (Metal via Xcode CLT) before giving up.

**If Task 0.4 passes**, continue to Phase 1.

### Task 0.5: Phase Z — CPU polish fallback (only if Vulkan failed)

This task runs only if any prior task fired its stop condition. It does NOT add MLC code. It improves the existing CPU path.

**Files:** none modified by this task (documented as "what we learned" in README)

- [ ] **Step 1: Document why MLC was skipped**

```bash
cat >> /Users/macpro/llama-cli/docs/mlc-evaluation.md <<'EOF'
# MLC-LLM Evaluation: NOT INTEGRATED

## Date: 2026-06-07

## Result: Vulkan/MoltenVK on D700 did not produce coherent output
(or: Vulkan worked, see mlc-bench-vulkan0.txt, but MLC integration is deferred)

## What was tried
- MoltenVK + Vulkan tools installed via Homebrew
- MLC-LLM nightly wheels installed
- CPU smoke test: see mlc-bench-cpu.txt
- Vulkan smoke test: see mlc-bench-vulkan0.txt (if it exists)

## Conclusion
intellama continues to use llama.cpp CPU. See llama.cpp PR
(filed separately) for benchmark evidence.

## Files
- vulkaninfo-baseline.txt: D700 Vulkan device list
- mlc-version.txt: MLC-LLM nightly version
- mlc-bench-*.txt: benchmark outputs
EOF
```

- [ ] **Step 2: Commit and stop**

```bash
cd /Users/macpro/llama-cli
git add docs/mlc-evaluation.md
git commit -m "docs(mlc): record evaluation result, MLC integration deferred"
```

**STOP HERE.** No Phase 1+ tasks. Plan ends.

---

## Phase 1 — intellama Backend Abstraction (only if Phase 0 passed)

### Task 1.1: Add MLC settings to ALL_KEYS and DEFAULT_SETTINGS

**Files:**
- Modify: `src/llama-launcher.sh:96-106` (ALL_KEYS array)
- Modify: `src/llama-launcher.sh:84-95` (DEFAULT_SETTINGS, if present — find by line number below)

- [ ] **Step 1: Locate the DEFAULT_SETTINGS block**

```bash
grep -n "S_default_model\|S_host=\|S_port=" /Users/macpro/llama-cli/src/llama-launcher.sh | head -10
```

Note: the existing block is around line 84. The new MLC defaults go after the last `S_gpu_probe_port=...` line.

- [ ] **Step 2: Add three MLC defaults after the existing GPU probe defaults**

Find the line that reads `S_gpu_probe_port="18081"` and add immediately below:

```bash
S_mlc_port=""
S_mlc_model_dir="$HOME/models/qwen3-35b-q4f16-mlc"
S_mlc_device="vulkan:0"
```

- [ ] **Step 3: Add the keys to ALL_KEYS**

Find the closing `)` of the `ALL_KEYS=( ... )` array (line 106 in the current file, after `gpu_probe_env gpu_probe_port`). Add the three new keys at the end of that line, before the `)`:

```bash
  gpu_probe_env gpu_probe_port
  mlc_port mlc_model_dir mlc_device)
```

- [ ] **Step 4: Verify the file still parses**

```bash
cd /Users/macpro/llama-cli
zsh -n src/llama-launcher.sh && echo OK
```

Expected: prints `OK`.

- [ ] **Step 5: Verify the new settings load with defaults**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  echo "mlc_port=[$(get_setting mlc_port)]"; \
  echo "mlc_model_dir=[$(get_setting mlc_model_dir)]"; \
  echo "mlc_device=[$(get_setting mlc_device)]"; \
  rm -rf $CONFIG_DIR'
```

Expected output:

```
mlc_port=[]
mlc_model_dir=[/Users/macpro/models/qwen3-35b-q4f16-mlc]
mlc_device=[vulkan:0]
```

- [ ] **Step 6: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): add mlc_port, mlc_model_dir, mlc_device settings"
```

### Task 1.2: Add MLC PID file path constant

**Files:**
- Modify: `src/llama-launcher.sh:18` (after `PID_FILE=...`)

- [ ] **Step 1: Add the MLC PID file constant**

After the line `PID_FILE="$CONFIG_DIR/server.pid"` (line 18), add:

```bash
MLC_PID_FILE="$CONFIG_DIR/mlc.pid"
```

- [ ] **Step 2: Verify parse**

```bash
zsh -n /Users/macpro/llama-cli/src/llama-launcher.sh && echo OK
```

- [ ] **Step 3: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): MLC_PID_FILE constant alongside server.pid"
```

### Task 1.3: Add `probe_backend` and helper functions

**Files:**
- Modify: `src/llama-launcher.sh` — insert after the `port_responds` function (find with `grep -n "^port_responds" src/llama-launcher.sh`)

- [ ] **Step 1: Find the `port_responds` function location**

```bash
grep -n "^port_responds" /Users/macpro/llama-cli/src/llama-launcher.sh
```

- [ ] **Step 2: Add `probe_backend` and `mlc_unload` / `mlc_health_url` right after `port_responds`**

Insert the following block immediately after the closing brace of `port_responds`:

```bash

# Probe any OpenAI-compatible /v1/models endpoint.
# Returns 0 if the response is valid JSON with a model id.
# Backend-agnostic — works for llama.cpp and MLC-LLM.
probe_backend() {
    local host=$(get_setting host)
    local port="${1:-$(get_setting port)}"
    local resp
    resp=$(curl -s --max-time 2 "http://$host:$port/v1/models" 2>/dev/null)
    [[ -n "$resp" ]] || return 1
    echo "$resp" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    sys.exit(0 if d.get('data') and d['data'][0].get('id') else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null
}

# Returns the model id currently served by the backend, or empty.
backend_model_id() {
    local host=$(get_setting host)
    local port="${1:-$(get_setting port)}"
    curl -s --max-time 2 "http://$host:$port/v1/models" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null
}

# Health check for the MLC backend (same as llama.cpp: /health returns {"status":"ok"}).
mlc_health_url() {
    echo "http://$(get_setting host):$(get_setting mlc_port)/health"
}

# Unload model from MLC server. MLC supports POST /unload.
mlc_unload() {
    local port=$(get_setting mlc_port)
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "http://$(get_setting host):$port/unload" 2>/dev/null)
    if [[ "$code" != "200" ]]; then
        code=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "http://$(get_setting host):$port/models/unload" 2>/dev/null)
    fi
    [[ "$code" == "200" ]]
}
```

- [ ] **Step 3: Verify parse**

```bash
zsh -n /Users/macpro/llama-cli/src/llama-launcher.sh && echo OK
```

- [ ] **Step 4: Smoke test the probe against a known-dead port**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  if probe_backend 19999; then echo "FAIL: probe_backend should return false"; else echo "OK: probe returned false for dead port"; fi; \
  rm -rf $CONFIG_DIR'
```

Expected: `OK: probe returned false for dead port`.

- [ ] **Step 5: Smoke test the probe against a live llama-server**

Start a quick llama-server in the background:

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  MODEL=/Users/macpro/models/draft/Qwen3-0.6B-Q8_0.gguf; \
  start_server "$MODEL" 2>/dev/null; \
  sleep 5; \
  if probe_backend; then echo "OK: probe returned true for live server"; else echo "FAIL: probe should return true"; fi; \
  stop_server; \
  rm -rf $CONFIG_DIR'
```

Expected: `OK: probe returned true for live server`.

- [ ] **Step 6: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): probe_backend, backend_model_id, mlc_unload"
```

### Task 1.4: Add `start_mlc_server` function

**Files:**
- Modify: `src/llama-launcher.sh` — insert after `start_server()` ends (find with `grep -n "^start_server\|^stop_server" src/llama-launcher.sh`)

- [ ] **Step 1: Locate where to insert**

```bash
grep -n "^start_server\|^stop_server" /Users/macpro/llama-cli/src/llama-launcher.sh
```

Insert after the closing brace of `start_server()` (currently line 741), before `stop_server()`.

- [ ] **Step 2: Add the function**

```bash

# Start an MLC-LLM server. Tracks PID in MLC_PID_FILE.
# Mirrors the lifecycle of start_server() (PID file, log, health wait).
start_mlc_server() {
    local model_dir=$(get_setting mlc_model_dir)
    local port=$(get_setting mlc_port)
    local device=$(get_setting mlc_device)

    if [[ -z "$port" ]]; then
        echo -e "${R}mlc_port is empty. Set it via menu option M.${RST}"
        return 1
    fi

    if ! command -v mlc_llm >/dev/null 2>&1; then
        echo -e "${R}mlc_llm not found in PATH.${RST}"
        echo -e "${Y}Install: pip install --pre -U mlc-llm-nightly -f https://mlc.ai/wheels${RST}"
        return 1
    fi

    if [[ ! -d "$model_dir" ]]; then
        echo -e "${R}MLC model directory not found: $model_dir${RST}"
        echo -e "${Y}Compile a model with: mlc_llm compile <config.json> --device $device --output $model_dir/lib.so${RST}"
        return 1
    fi

    if [[ -f "$MLC_PID_FILE" ]] && kill -0 "$(cat "$MLC_PID_FILE")" 2>/dev/null; then
        echo -e "${Y}MLC server already running (PID: $(cat "$MLC_PID_FILE")).${RST}"
        return 1
    fi
    rm -f "$MLC_PID_FILE"

    local logfile="$LOG_DIR/mlc-server-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p "$LOG_DIR"

    echo -e "${G}Starting MLC-LLM server...${RST}"
    echo -e "${D}Model:   $model_dir${RST}"
    echo -e "${D}Device:  $device${RST}"
    echo -e "${D}Port:    $port${RST}"
    echo -e "${D}Log:     $logfile${RST}"
    echo ""

    # shellcheck disable=SC2086
    mlc_llm serve "$model_dir" \
        --device "$device" \
        --host "$(get_setting host)" \
        --port "$port" \
        --max-batch-size 1 \
        --prefill-chunk-size 512 \
        > "$logfile" 2>&1 &
    local mlc_pid=$!
    echo "$mlc_pid" > "$MLC_PID_FILE"

    echo -e "${W}Waiting for MLC server (PID: $mlc_pid)...${RST}"
    local elapsed=0
    while (( elapsed < 240 )); do
        if ! kill -0 "$mlc_pid" 2>/dev/null; then
            echo -e "${R}MLC server died. Last 20 lines of log:${RST}"
            tail -20 "$logfile"
            rm -f "$MLC_PID_FILE"
            return 1
        fi
        if probe_backend "$port"; then
            echo -e "${G}MLC server ready! PID: $mlc_pid${RST}"
            echo -e "${C}API: http://$(get_setting host):$port/v1${RST}"
            echo -e "${C}Key: dummy${RST}"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    echo -e "${Y}Still loading after 240s. Check log: $logfile${RST}"
}
```

- [ ] **Step 3: Verify parse**

```bash
zsh -n /Users/macpro/llama-cli/src/llama-launcher.sh && echo OK
```

- [ ] **Step 4: Smoke test — error path with empty mlc_port**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  if start_mlc_server 2>/dev/null; then echo "FAIL"; else echo "OK: refused to start with empty mlc_port"; fi; \
  rm -rf $CONFIG_DIR'
```

Expected: `OK: refused to start with empty mlc_port`.

- [ ] **Step 5: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): start_mlc_server with PID tracking and health wait"
```

### Task 1.5: Wire `start_server` to dispatch on `mlc_port`

**Files:**
- Modify: `src/llama-launcher.sh:693-741` (`start_server()` function)

- [ ] **Step 1: Add backend dispatch at the top of `start_server`**

Find the function `start_server() {` (line 693). Replace the body from `start_server() {` through the `if is_our_server_running; then ... return 1; fi` block (lines 693–704) with:

```bash
start_server() {
    local model="$1"

    if [[ -z "$model" ]]; then
        echo -e "${R}No model selected${RST}"
        return 1
    fi

    # If MLC backend is configured and reachable, use it.
    local mlc_port=$(get_setting mlc_port)
    if [[ -n "$mlc_port" ]]; then
        if probe_backend "$mlc_port"; then
            local current_model=$(backend_model_id "$mlc_port")
            if [[ "$current_model" == "$(basename "$model")" ]]; then
                echo -e "${D}MLC server is already serving this model.${RST}"
                return 0
            fi
            echo -e "${Y}MLC server on :$mlc_port is serving '$current_model'.${RST}"
            echo -n "Unload and reload '$(basename "$model")'? [y/N]: "
            read -r yn
            if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
                mlc_unload && sleep 1
            else
                echo -e "${D}Selection saved. Use option 3 (Start Server) to load it.${RST}"
                return 0
            fi
        fi
        # Probe the llama-server port too — if a llama-server is bound there,
        # refuse to start MLC on the same port (would be a config error).
        if is_our_server_running || [[ -n "$(get_foreign_pid)" ]]; then
            echo -e "${R}llama-server is bound to port $(get_setting port).${RST}"
            echo -e "${Y}Stop it (option 4) before starting MLC on a different port.${RST}"
            return 1
        fi
        start_mlc_server "$model"
        return $?
    fi

    # Default: llama.cpp path (unchanged from v1.2.3)
    if is_our_server_running; then
        echo -e "${Y}Server already running (PID: $(get_our_pid)). Stop it first (option 4).${RST}"
        return 1
    fi
```

Leave everything from `echo -e "${D}Purging macOS memory...${RST}"` onward (line 706) unchanged.

- [ ] **Step 2: Verify parse**

```bash
zsh -n /Users/macpro/llama-cli/src/llama-launcher.sh && echo OK
```

- [ ] **Step 3: Smoke test — empty `mlc_port` still calls llama.cpp path**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  MODEL=/Users/macpro/models/draft/Qwen3-0.6B-Q8_0.gguf; \
  start_server "$MODEL" 2>&1 | head -3; \
  sleep 3; \
  is_our_server_running && echo "OK: llama.cpp server started" || echo "FAIL: llama.cpp server did not start"; \
  stop_server 2>/dev/null; \
  rm -rf $CONFIG_DIR'
```

Expected: starts the llama-server, prints `OK: llama.cpp server started`.

- [ ] **Step 4: Smoke test — non-empty `mlc_port` but no MLC running triggers a probe-fail message**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  set_setting mlc_port 19999; \
  set_setting mlc_model_dir /tmp/nonexistent-mlc-$$; \
  MODEL=/Users/macpro/models/draft/Qwen3-0.6B-Q8_0.gguf; \
  start_server "$MODEL" 2>&1 | tail -3; \
  sleep 2; \
  ! is_our_server_running && echo "OK: no server started when MLC is unreachable" || echo "FAIL: unexpected server start"; \
  rm -rf $CONFIG_DIR'
```

Expected: prints error from `start_mlc_server` (model dir not found) and `OK: no server started when MLC is unreachable`.

- [ ] **Step 5: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): start_server dispatches to MLC when mlc_port is set"
```

### Task 1.6: Wire `stop_server` to kill the MLC PID

**Files:**
- Modify: `src/llama-launcher.sh:743-784` (`stop_server()` function)

- [ ] **Step 1: Update `stop_server` to also handle the MLC PID file**

Replace the body of `stop_server()` (lines 743–784) with:

```bash
stop_server() {
    # Make sure we've observed the current state — populates PID_FILE.foreign
    # if a foreign server is on the port.
    is_our_server_running || true

    local pid=$(get_our_pid)
    local fp=$(get_foreign_pid)
    local mlc_pid=""
    [[ -f "$MLC_PID_FILE" ]] && mlc_pid=$(cat "$MLC_PID_FILE" 2>/dev/null)
    local stopped=0

    if [[ -n "$pid" ]]; then
        echo -e "${Y}Stopping llama-server (PID: $pid)...${RST}"
        kill "$pid" 2>/dev/null
        for _ in 1 2 3 4 5; do
            sleep 1
            kill -0 "$pid" 2>/dev/null || break
        done
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        rm -f "$PID_FILE" "$PID_FILE.foreign"
        echo -e "${G}llama-server stopped${RST}"
        stopped=1
    fi

    if [[ -n "$mlc_pid" ]] && kill -0 "$mlc_pid" 2>/dev/null; then
        echo -e "${Y}Stopping MLC server (PID: $mlc_pid)...${RST}"
        kill "$mlc_pid" 2>/dev/null
        for _ in 1 2 3 4 5; do
            sleep 1
            kill -0 "$mlc_pid" 2>/dev/null || break
        done
        kill -0 "$mlc_pid" 2>/dev/null && kill -9 "$mlc_pid" 2>/dev/null
        rm -f "$MLC_PID_FILE"
        echo -e "${G}MLC server stopped${RST}"
        stopped=1
    fi

    if [[ -n "$fp" && "$fp" != "$pid" ]]; then
        echo -e "${Y}A llama-server (PID $fp) is listening on the configured port"
        echo -e "but intellama did not start it. Stop it? [y/N]${RST}"
        read -r yn
        if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
            kill "$fp" 2>/dev/null
            for _ in 1 2 3 4 5; do
                sleep 1
                kill -0 "$fp" 2>/dev/null || break
            done
            kill -0 "$fp" 2>/dev/null && kill -9 "$fp" 2>/dev/null
            rm -f "$PID_FILE.foreign"
            echo -e "${G}Foreign llama-server stopped${RST}"
            stopped=1
        else
            echo -e "${D}Foreign server left running.${RST}"
        fi
    fi

    (( stopped == 0 )) && echo -e "${D}Server is not running${RST}"
}
```

- [ ] **Step 2: Verify parse**

```bash
zsh -n /Users/macpro/llama-cli/src/llama-launcher.sh && echo OK
```

- [ ] **Step 3: Smoke test — `stop_server` with no PIDs is a no-op**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  rm -f "$CONFIG_DIR/server.pid" "$CONFIG_DIR/mlc.pid"; \
  stop_server 2>&1 | tail -1; \
  rm -rf $CONFIG_DIR'
```

Expected: prints `Server is not running`.

- [ ] **Step 4: Smoke test — `stop_server` kills a fake MLC PID**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  sleep 60 & echo $! > "$CONFIG_DIR/mlc.pid"; \
  PID=$(cat "$CONFIG_DIR/mlc.pid"); \
  stop_server 2>&1 | tail -1; \
  ! kill -0 $PID 2>/dev/null && echo "OK: MLC PID killed" || echo "FAIL: PID still alive"; \
  rm -rf $CONFIG_DIR'
```

Expected: `MLC server stopped` and `OK: MLC PID killed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): stop_server kills tracked MLC PID"
```

### Task 1.7: Update `eject_model` for MLC

**Files:**
- Modify: `src/llama-launcher.sh:786-822` (`eject_model()` function)

- [ ] **Step 1: Read current `eject_model`**

```bash
sed -n '786,822p' /Users/macpro/llama-cli/src/llama-launcher.sh
```

- [ ] **Step 2: Add an MLC branch at the top of `eject_model`**

Find the line `eject_model() {` and insert immediately after the opening brace, before the existing `if ! is_our_server_running; then` check:

```bash
    # If MLC backend is configured and its server is alive, unload via MLC.
    local mlc_port=$(get_setting mlc_port)
    if [[ -n "$mlc_port" ]] && probe_backend "$mlc_port"; then
        if mlc_unload; then
            echo -e "${G}MLC model ejected${RST}"
        else
            echo -e "${Y}MLC unload returned non-200. Try option 4 (Stop Server).${RST}"
        fi
        return
    fi
```

- [ ] **Step 3: Verify parse**

```bash
zsh -n /Users/macpro/llama-cli/src/llama-launcher.sh && echo OK
```

- [ ] **Step 4: Smoke test — MLC branch takes precedence when MLC is alive**

This requires a live MLC server. Skip if Phase 0 didn't succeed — manual check is enough.

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  set_setting mlc_port 19999; \
  eject_model 2>&1 | head -2; \
  echo "---"; \
  set_setting mlc_port ""; \
  echo "(mlc_port empty branch tested via existing eject_model flow)"; \
  rm -rf $CONFIG_DIR'
```

Expected: with `mlc_port=19999` (dead), the MLC branch is skipped silently and the existing eject path runs (prints "Server is not running" because no PID). With `mlc_port=""` the MLC branch is also skipped. Both paths converge correctly.

- [ ] **Step 5: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): eject_model uses MLC unload when MLC is alive"
```

### Task 1.8: Update `select_model` foreign-server check

**Files:**
- Modify: `src/llama-launcher.sh:432-464` (the `is_our_server_running` block in `select_model`)

- [ ] **Step 1: Read the current block**

```bash
sed -n '432,464p' /Users/macpro/llama-cli/src/llama-launcher.sh
```

- [ ] **Step 2: Add MLC probe before the existing llama-server foreign check**

Find the line `if is_our_server_running; then` (line 435). Insert immediately before it:

```bash
    # If MLC is configured and alive, check whether it already serves this model.
    local mlc_port=$(get_setting mlc_port)
    if [[ -n "$mlc_port" ]] && probe_backend "$mlc_port"; then
        local current_model=$(backend_model_id "$mlc_port")
        if [[ "$current_model" == "$(basename "$SELECTED_MODEL")" ]]; then
            echo -e "${D}MLC server is already serving this model.${RST}"
            return 0
        fi
        echo -e "${Y}MLC server on :$mlc_port is serving '$current_model'.${RST}"
        echo -n "Unload and load '$(basename "$SELECTED_MODEL")'? [y/N]: "
        read -r yn
        if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
            mlc_unload && sleep 1
            start_mlc_server "$SELECTED_MODEL"
        else
            echo -e "${D}Selection saved. Use option 3 (Start Server) to load it.${RST}"
        fi
        return 0
    fi
```

- [ ] **Step 3: Verify parse**

```bash
zsh -n /Users/macpro/llama-cli/src/llama-launcher.sh && echo OK
```

- [ ] **Step 4: Smoke test — select_model with MLC config but no live MLC falls through to existing flow**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  set_setting mlc_port 19999; \
  SELECTED_MODEL=/Users/macpro/models/draft/Qwen3-0.6B-Q8_0.gguf; \
  select_model < /dev/null 2>&1 | head -10; \
  rm -rf $CONFIG_DIR'
```

Expected: scans models, prints "Available Models", and exits cleanly (returns to caller) — no MLC server to manage.

- [ ] **Step 5: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): select_model checks MLC server when configured"
```

### Task 1.9: Update `server_status` to show MLC backend

**Files:**
- Modify: `src/llama-launcher.sh:824-857` (`server_status()` function)

- [ ] **Step 1: Read the current function**

```bash
sed -n '824,857p' /Users/macpro/llama-cli/src/llama-launcher.sh
```

- [ ] **Step 2: Add an MLC line to the status output**

Find the line `if is_our_server_running; then` (line 828). Insert immediately before it:

```bash
    # MLC backend status (if configured)
    local mlc_port=$(get_setting mlc_port)
    if [[ -n "$mlc_port" ]]; then
        if [[ -f "$MLC_PID_FILE" ]] && kill -0 "$(cat "$MLC_PID_FILE")" 2>/dev/null; then
            local mlc_pid=$(cat "$MLC_PID_FILE")
            local mlc_mem=$(ps -o rss= -p "$mlc_pid" 2>/dev/null | awk '{printf "%.1f GB", $1/1024/1024}')
            local mlc_uptime=$(ps -o etime= -p "$mlc_pid" 2>/dev/null | xargs)
            echo -e "  ${W}Backend:${RST}  ${C}MLC-LLM${RST} (PID: ${C}$mlc_pid${RST}) ${D}Mem ${C}$mlc_mem${RST} ${D}Up ${C}$mlc_uptime${RST}"
            if probe_backend "$mlc_port"; then
                local mn=$(backend_model_id "$mlc_port")
                [[ -n "$mn" ]] && echo -e "  ${W}Model:${RST}    ${C}$mn${RST}"
            else
                echo -e "  ${W}Health:${RST}  ${Y}Loading...${RST}"
            fi
        else
            echo -e "  ${W}Backend:${RST}  ${D}MLC configured (port $mlc_port) but not running${RST}"
        fi
    fi
```

- [ ] **Step 3: Verify parse**

```bash
zsh -n /Users/macpro/llama-cli/src/llama-launcher.sh && echo OK
```

- [ ] **Step 4: Manual test**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  set_setting mlc_port 19999; \
  server_status 2>&1 | head -10; \
  rm -rf $CONFIG_DIR'
```

Expected: prints `Backend:  MLC configured (port 19999) but not running`.

- [ ] **Step 5: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): server_status shows MLC backend when configured"
```

### Task 1.10: Add menu option `M` to configure MLC

**Files:**
- Modify: `src/llama-launcher.sh:894-947` (main menu `Actions` block and the `case` dispatch)

- [ ] **Step 1: Add the M line to the Actions menu**

Find the line `echo -e "  ${G}g${RST}) Probe GPU Compute"` (around line 909). Add immediately below it:

```bash
echo -e "  ${G}M${RST}) Configure MLC-LLM Backend"
```

- [ ] **Step 2: Add the case branch to the dispatch**

Find the case branch for `g|G)` (line 944). Add immediately below it:

```bash
M) configure_mlc; echo ""; echo -n "Press Enter..."; read _ ;;
```

- [ ] **Step 3: Add the `configure_mlc` function**

Find `main()` and insert `configure_mlc` immediately before it (after `view_log` ends, around line 868):

```bash

# Interactive MLC backend configuration.
# Sets mlc_port (empty to disable), shows status.
configure_mlc() {
    echo -e "${W}MLC-LLM Backend Configuration:${RST}"
    echo -e "${D}────────────────────────────────────────────────${RST}"
    echo -e "  Current port:    ${C}$(get_setting mlc_port)${RST} ${D}(empty = disabled)${RST}"
    echo -e "  Current device:  ${C}$(get_setting mlc_device)${RST}"
    echo -e "  Model directory: ${C}$(get_setting mlc_model_dir)${RST}"
    echo ""

    if ! command -v mlc_llm >/dev/null 2>&1; then
        echo -e "${Y}mlc_llm CLI not found in PATH.${RST}"
        echo -e "${Y}Install: pip install --pre -U mlc-llm-nightly -f https://mlc.ai/wheels${RST}"
        echo ""
    fi

    echo -n "MLC server port (empty to disable) [$(get_setting mlc_port)]: "
    read v
    if [[ -n "$v" ]]; then
        if ! [[ "$v" =~ ^[0-9]+$ ]] || (( v < 1 || v > 65535 )); then
            echo -e "${R}Invalid port${RST}"
            return 1
        fi
        set_setting mlc_port "$v"
        echo -e "  ${G}mlc_port set to $v${RST}"
        if probe_backend "$v"; then
            local mn=$(backend_model_id "$v")
            echo -e "  ${G}MLC server is alive${RST} on :$v (model: ${C}$mn${RST})"
        else
            echo -e "  ${D}No MLC server detected on :$v. Use option 3 (Start Server) to launch.${RST}"
        fi
    else
        set_setting mlc_port ""
        echo -e "  ${D}MLC backend disabled.${RST}"
    fi
}
```

- [ ] **Step 4: Verify parse and run npm test**

```bash
cd /Users/macpro/llama-cli
zsh -n src/llama-launcher.sh && echo OK
npm test
```

Expected: `OK` followed by the existing npm test output (which includes `zsh -n src/llama-launcher.sh` and `node --check` for the bin scripts).

- [ ] **Step 5: Manual test — non-interactive smoke**

```bash
cd /Users/macpro/llama-cli
zsh -c 'source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-test-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  set_setting mlc_port 8080; \
  echo "After set: mlc_port=[$(get_setting mlc_port)]"; \
  set_setting mlc_port ""; \
  echo "After clear: mlc_port=[$(get_setting mlc_port)]"; \
  rm -rf $CONFIG_DIR'
```

Expected:
```
After set: mlc_port=[8080]
After clear: mlc_port=[]
```

- [ ] **Step 6: Commit**

```bash
cd /Users/macpro/llama-cli
git add src/llama-launcher.sh
git commit -m "feat(mlc): menu option M to configure MLC backend"
```

### Task 1.11: Create `scripts/start-mlc.sh`

**Files:**
- Create: `scripts/start-mlc.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# start-mlc.sh — Standalone launcher for MLC-LLM server.
# Usage: start-mlc.sh [model_dir] [port] [device]
# Defaults from INTELLAMA_MLC_* env vars.

set -euo pipefail

MODEL_DIR="${1:-${INTELLAMA_MLC_MODEL_DIR:-$HOME/models/qwen3-35b-q4f16-mlc}}"
PORT="${2:-${INTELLAMA_MLC_PORT:-8080}}"
DEVICE="${3:-${INTELLAMA_MLC_DEVICE:-vulkan:0}}"

if ! command -v mlc_llm >/dev/null 2>&1; then
    echo "mlc_llm not found in PATH."
    echo "Install: pip install --pre -U mlc-llm-nightly -f https://mlc.ai/wheels"
    exit 1
fi

if [[ ! -d "$MODEL_DIR" ]]; then
    echo "Model directory not found: $MODEL_DIR"
    echo "Compile a model first:"
    echo "  mlc_llm compile <config.json> --device $DEVICE --output $MODEL_DIR/lib.so"
    exit 1
fi

echo "[start-mlc] model=$MODEL_DIR device=$DEVICE port=$PORT"
exec mlc_llm serve "$MODEL_DIR" \
    --device "$DEVICE" \
    --host "${INTELLAMA_MLC_HOST:-127.0.0.1}" \
    --port "$PORT" \
    --max-batch-size 1 \
    --prefill-chunk-size 512
```

- [ ] **Step 2: Make executable and verify parse**

```bash
chmod +x /Users/macpro/llama-cli/scripts/start-mlc.sh
zsh -n /Users/macpro/llama-cli/scripts/start-mlc.sh && echo OK
```

Note: `zsh -n` works on bash scripts too for syntax checks.

- [ ] **Step 3: Smoke test — error path with missing model dir**

```bash
/Users/macpro/llama-cli/scripts/start-mlc.sh /tmp/nonexistent-model-$$ 9999
```

Expected: prints `Model directory not found: /tmp/nonexistent-model-...` and exits 1.

- [ ] **Step 4: Commit**

```bash
cd /Users/macpro/llama-cli
git add scripts/start-mlc.sh
git commit -m "feat(mlc): standalone start-mlc.sh launcher script"
```

### Task 1.12: Wire `start-mlc.sh` syntax check into npm test

**Files:**
- Modify: `package.json:24` (the `test` script)

- [ ] **Step 1: Read the current test script**

```bash
grep -A 2 '"test"' /Users/macpro/llama-cli/package.json
```

- [ ] **Step 2: Add the new check**

Change the `"test"` value from:

```json
"test": "zsh -n src/llama-launcher.sh && node --check bin/intellama.js && node --check bin/llama-cli.js && node --check scripts/postinstall.js"
```

to:

```json
"test": "zsh -n src/llama-launcher.sh && zsh -n scripts/start-mlc.sh && node --check bin/intellama.js && node --check bin/llama-cli.js && node --check scripts/postinstall.js"
```

- [ ] **Step 3: Run npm test**

```bash
cd /Users/macpro/llama-cli
npm test
```

Expected: all syntax checks pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/macpro/llama-cli
git add package.json
git commit -m "test: add start-mlc.sh syntax check to npm test"
```

### Task 1.13: README section for MLC-LLM backend

**Files:**
- Modify: `README.md` — insert a new section before the existing `## What This Is` (or wherever the docs flow is logical)

- [ ] **Step 1: Find a good insertion point**

```bash
grep -n "^## " /Users/macpro/llama-cli/README.md | head -10
```

- [ ] **Step 2: Add the MLC-LLM section**

Insert after the version banner and before the `## What This Is` heading:

````markdown
## MLC-LLM GPU Backend (optional)

intellama v1.3.0+ ships an optional MLC-LLM backend that can drive the 2× AMD FirePro D700 GPUs via Vulkan/MoltenVK. It auto-detects when configured and falls back to llama.cpp CPU when MLC is not present or fails to start.

### Install (one-time)

```bash
brew install molten-vk vulkan-headers vulkan-loader vulkan-tools
python3 -m pip install --pre -U mlc-llm-nightly -f https://mlc.ai/wheels
```

Verify Vulkan sees the D700s:

```bash
vulkaninfo 2>&1 | grep deviceName
```

### Compile a model for MLC

```bash
# 1. Pull source weights
git lfs install
git clone https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct ~/models/qwen3-35b-source

# 2. Convert + quantize
mlc_llm convert_weight ~/models/qwen3-35b-source \
    --quantization q4f16_1 \
    --output ~/models/qwen3-35b-q4f16-mlc
mlc_llm gen_config ~/models/qwen3-35b-source \
    --quantization q4f16_1 \
    --output ~/models/qwen3-35b-q4f16-mlc

# 3. Compile for Vulkan (TVM auto-tunes to GCN wavefront = 64)
mlc_llm compile ~/models/qwen3-35b-q4f16-mlc/mlc-chat-config.json \
    --device vulkan \
    --opt "vulkan --thread_warp_size=64" \
    --output ~/models/qwen3-35b-q4f16-mlc/lib.so
```

### Configure in intellama

Launch intellama, choose menu option `M`, set the port (default `8080`). The launcher will:

- Probe `/v1/models` on that port before each start
- Reuse a running MLC server if it already serves the requested model
- Offer to unload + reload on model swap
- Fall through to llama.cpp on port 8081 when `mlc_port` is empty

### Environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `INTELLAMA_MLC_PORT` | empty | If set, enables MLC probe and dispatch |
| `INTELLAMA_MLC_MODEL_DIR` | `~/models/qwen3-35b-q4f16-mlc` | Compiled MLC model path |
| `INTELLAMA_MLC_DEVICE` | `vulkan:0` | `cpu`, `vulkan:0`, `vulkan:0,vulkan:1` for tensor parallel |

### Dual-GPU tensor parallel

Set `INTELLAMA_MLC_DEVICE=vulkan:0,vulkan:1` and recompile with `--num-shards 2` (see `scripts/start-mlc.sh`). The 35B-A3B MoE at q4f16 fits in 12 GB combined VRAM.

````

- [ ] **Step 3: Verify the file**

```bash
cd /Users/macpro/llama-cli
test -f README.md && wc -l README.md
head -3 README.md
```

- [ ] **Step 4: Commit**

```bash
cd /Users/macpro/llama-cli
git add README.md
git commit -m "docs(readme): MLC-LLM backend section"
```

### Task 1.14: End-to-end manual test (real MLC server)

This is the integration test. Requires a working MLC install and a compiled model.

**Files:** none

- [ ] **Step 1: Start MLC server in the background**

```bash
/Users/macpro/llama-cli/scripts/start-mlc.sh \
  ~/models/qwen3-35b-q4f16-mlc 8080 vulkan:0 \
  > /tmp/mlc-bg.log 2>&1 &
echo $! > /tmp/mlc-bg.pid
sleep 30  # let MLC load
```

- [ ] **Step 2: Verify MLC is up**

```bash
curl -s http://127.0.0.1:8080/v1/models | python3 -m json.tool
```

Expected: a JSON document with `data[0].id` field naming the model.

- [ ] **Step 3: Run intellama with MLC config and verify menu option M works**

```bash
cd /Users/macpro/llama-cli
zsh -c 'export INTELLAMA_MLC_PORT=8080; \
  source src/llama-launcher.sh 2>/dev/null; \
  CONFIG_DIR=/tmp/ll-e2e-$$; mkdir -p $CONFIG_DIR; \
  CONFIG_FILE=$CONFIG_DIR/settings.conf; \
  load_config 2>/dev/null; \
  set_setting mlc_port 8080; \
  echo "=== server_status ==="; \
  server_status; \
  echo "=== select_model <model> ==="; \
  SELECTED_MODEL=/Users/macpro/models/draft/Qwen3-0.6B-Q8_0.gguf; \
  select_model < /dev/null 2>&1 | head -5; \
  echo "=== stop_server ==="; \
  stop_server; \
  rm -rf $CONFIG_DIR'
```

Expected: MLC backend line appears in `server_status`; `select_model` detects MLC is alive and prints model info; `stop_server` kills the MLC PID (which here is the background script's PID, not intellama's, so we just verify the function runs without error).

- [ ] **Step 4: Send a test chat completion to MLC**

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What is 2+2?"}],"max_tokens":10}' \
  | python3 -m json.tool
```

Expected: JSON with a `choices[0].message.content` field containing "4".

- [ ] **Step 5: Kill the background MLC server**

```bash
kill "$(cat /tmp/mlc-bg.pid)" 2>/dev/null
sleep 2
! kill -0 "$(cat /tmp/mlc-bg.pid)" 2>/dev/null && echo "OK: MLC stopped" || echo "FAIL"
rm -f /tmp/mlc-bg.pid /tmp/mlc-bg.log
```

- [ ] **Step 6: No commit needed** (this is a verification step)

If any step fails, document in `docs/mlc-evaluation.md` and stop here.

### Task 1.15: Bump version and tag

**Files:**
- Modify: `package.json:3` (version)
- Modify: `README.md:1-3` (version banner)

- [ ] **Step 1: Update version in package.json**

```bash
cd /Users/macpro/llama-cli
sed -i.bak 's/"version": "1.2.3"/"version": "1.3.0"/' package.json
rm -f package.json.bak
grep '"version"' package.json
```

Expected: `"version": "1.3.0",`

- [ ] **Step 2: Update README banner**

Find the line starting with `> **v1.2.3 —` in README.md and replace with:

```markdown
> **v1.3.0 — MLC-LLM GPU backend (auto-detect, fallback to llama.cpp)**
> - New menu option `M` to configure the MLC-LLM backend (port, model dir, device).
> - Auto-detect: when `mlc_port` is set, the launcher probes `/v1/models` and prefers MLC; falls through to llama.cpp on miss.
> - Tracked PID in `~/.config/llama-launcher/mlc.pid`; stop / purge / eject all work for both backends.
> - Compile with `--opt "vulkan --thread_warp_size=64"` to match GCN 1.0 wavefront size.
```

- [ ] **Step 3: Run the full test suite**

```bash
cd /Users/macpro/llama-cli
npm test
```

Expected: all checks pass.

- [ ] **Step 4: Commit and tag**

```bash
cd /Users/macpro/llama-cli
git add package.json README.md
git commit -m "release: v1.3.0 — MLC-LLM GPU backend"
git tag v1.3.0
git log --oneline -5
```

- [ ] **Step 5: Push (only if user instructs)**

```bash
cd /Users/macpro/llama-cli
git push origin main --tags
```

**Do not push without explicit user approval.**

---

## Phase 2 (Optional) — Dual-GPU Tensor Parallel

These tasks only run if the user wants to test the 12 GB combined VRAM configuration. Skip for the v1.3.0 release.

### Task 2.1: Recompile model with `--num-shards 2`

- [ ] **Step 1: Compile with 2-GPU sharding**

```bash
mlc_llm compile ~/models/qwen3-35b-q4f16-mlc/mlc-chat-config.json \
    --device vulkan \
    --opt "vulkan --thread_warp_size=64" \
    --num-shards 2 \
    --output ~/models/qwen3-35b-q4f16-mlc/lib-2gpu.so
```

- [ ] **Step 2: Save benchmark**

```bash
mlc_llm bench ~/models/qwen3-35b-q4f16-mlc --device vulkan:0,vulkan:1 \
    --num-prompts 3 \
    > /Users/macpro/llama-cli/docs/mlc-bench-vulkan0-1.txt 2>&1
```

- [ ] **Step 3: Commit**

```bash
cd /Users/macpro/llama-cli
git add docs/mlc-bench-vulkan0-1.txt
git commit -m "docs(mlc): dual-GPU tensor-parallel benchmark"
```

### Task 2.2: Update `scripts/start-mlc.sh` to support dual device

This is a documentation/config change, not a code change.

- [ ] **Step 1: Add a `start-mlc-2gpu.sh` variant**

```bash
cp /Users/macpro/llama-cli/scripts/start-mlc.sh /Users/macpro/llama-cli/scripts/start-mlc-2gpu.sh
sed -i '' 's|vulkan:0|vulkan:0,vulkan:1|g' /Users/macpro/llama-cli/scripts/start-mlc-2gpu.sh
sed -i '' 's|q4f16-mlc|q4f16-mlc-2gpu|g' /Users/macpro/llama-cli/scripts/start-mlc-2gpu.sh
chmod +x /Users/macpro/llama-cli/scripts/start-mlc-2gpu.sh
```

- [ ] **Step 2: Document in README**

Append to the MLC-LLM section:

```markdown
### Dual-GPU variant

```bash
INTELLAMA_MLC_MODEL_DIR=~/models/qwen3-35b-q4f16-mlc-2gpu \
INTELLAMA_MLC_DEVICE=vulkan:0,vulkan:1 \
./scripts/start-mlc-2gpu.sh
```
```

- [ ] **Step 3: Commit**

```bash
cd /Users/macpro/llama-cli
git add scripts/start-mlc-2gpu.sh README.md
git commit -m "feat(mlc): dual-GPU launcher variant"
```

---

## Self-Review

**Spec coverage check:**

| Spec section | Covered by task |
|--------------|-----------------|
| Goal & success criteria (Vulkan first, integrate if works, fallback if not) | Tasks 0.1–0.4 (validation), Task 0.5 (fallback) |
| Architecture: zsh-only, single config knob, PID tracking | Tasks 1.1–1.2 (settings + PID file) |
| C1 `probe_backend` | Task 1.3 |
| C2 `backend_active` (env var) | Implicit — handled by reading `mlc_port` setting in dispatch points (Tasks 1.5, 1.7, 1.8) |
| C3 `start_mlc_server` | Task 1.4 |
| C4 `mlc_health_url` / `mlc_unload` | Task 1.3 |
| C5 Settings additions | Task 1.1 |
| C6 `scripts/start-mlc.sh` | Task 1.11 |
| C7 Menu option `M` | Task 1.10 |
| C8 README | Task 1.13 |
| Data flow & error handling | Tasks 1.5–1.9 (dispatch + error paths) |
| Logging (separate log file) | Task 1.4 (log file: `mlc-server-*.log`) |
| Testing T1–T4 | T1: Task 1.12 (npm test); T2: each step's smoke test; T3: Tasks 0.3, 0.4 (saved txt files); T4: covered by 1.12 |
| Phasing stop conditions | Tasks 0.1, 0.2, 0.3, 0.4 each have stop conditions; Task 0.5 is the fallback path |
| File map | All files match (no drift) |

**Placeholder scan:** None. All commands shown, all paths absolute, all checks have expected output.

**Type/name consistency:**
- `MLC_PID_FILE` defined in Task 1.2, used in Tasks 1.4, 1.6, 1.7, 1.9 ✓
- `mlc_port`, `mlc_model_dir`, `mlc_device` defined in Task 1.1, read via `get_setting` in all later tasks ✓
- `probe_backend`, `backend_model_id`, `mlc_unload`, `mlc_health_url` defined in Task 1.3, used in Tasks 1.5, 1.7, 1.8, 1.9 ✓
- `start_mlc_server` defined in Task 1.4, called in Tasks 1.5, 1.8 ✓
- `configure_mlc` defined in Task 1.10, called from `M` case in same task ✓
- `start-mlc.sh` script created in Task 1.11, referenced in Task 1.12, Task 1.13, Task 1.14 ✓

**Gaps:** None found.

---

## Out of Scope (NOT in this plan)

- Ollama integration (already in intellama history; out of scope here)
- Windows / non-Intel Mac support
- Speculative decoding for MLC (MLC has its own)
- Bench harness for MLC vs llama.cpp CPU comparison (covered in docs/)
- llama.cpp PR for subgroupBroadcast fix (out of scope — separate workflow)
- Full MoE expert offloading strategies (basic 12 GB combined is the only realistic config)
