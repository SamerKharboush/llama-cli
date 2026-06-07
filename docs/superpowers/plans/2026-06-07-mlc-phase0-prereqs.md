# MLC-LLM Phase 0 — Prerequisites Sub-Project Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scripts/setup-mlc.sh` (+ brewfile + troubleshooting doc) to intellama so a clean box reaches the state described in the parent plan's Phase 0: brew formulae installed, project-local venv with MLC-LLM nightly wheels, and `vulkaninfo` reporting ≥2 AMD devices. Script exits 1 on GPU gate failure with a red diagnostic block.

**Architecture:** Pure zsh script + checked-in Brewfile + user-facing troubleshooting doc. No launcher changes, no menu changes, no Node changes, no models compiled. Idempotent re-runs. Strict GPU gate at the end.

**Tech Stack:** zsh, Homebrew, Python 3 stdlib `venv`, `pip` from MLC's nightly index (`https://mlc.ai/wheels`), `vulkaninfo` for GPU gate.

**Hardware:** 2013 Mac Pro · 2× D700 · macOS Sequoia via OCLP · no Xcode (warn-only at this phase).

**Spec:** `docs/superpowers/specs/2026-06-07-mlc-llm-phase0-prereqs-design.md`

**Parent index:** `docs/superpowers/specs/2026-06-07-mlc-llm-integration-design.md`

---

## File Map

| File | Status | Responsibility |
|------|--------|----------------|
| `scripts/setup-mlc.sh` | create | The install script (~120 lines) |
| `scripts/setup-mlc.brewfile` | create | Brew formulae (4 lines) |
| `docs/gpu-mlc-setup.md` | create | User-facing setup + troubleshooting doc (~80 lines) |
| `package.json` | modify | Add `zsh -n scripts/setup-mlc.sh` to `test` script |
| `README.md` | modify | One-line pointer to setup-mlc.sh |

The script and brewfile will ship in the npm tarball (already allowed by the existing `files` allowlist). The troubleshooting doc is in `docs/`, NOT under `docs/superpowers/`, so it's not in the npm tarball — README links to it via the GitHub URL.

---

## Task 1: Create the Brewfile

**Files:**
- Create: `scripts/setup-mlc.brewfile`

- [ ] **Step 1: Write the Brewfile**

Create `scripts/setup-mlc.brewfile` with:

```ruby
tap "moltenvk/vulkan"
brew "molten-vk"
brew "vulkan-headers"
brew "vulkan-loader"
brew "vulkan-tools"
```

- [ ] **Step 2: Verify file mode and content**

```bash
test -f /Users/macpro/llama-cli/scripts/setup-mlc.brewfile && wc -l /Users/macpro/llama-cli/scripts/setup-mlc.brewfile
cat /Users/macpro/llama-cli/scripts/setup-mlc.brewfile
```

Expected: 5 lines, content matches Step 1.

- [ ] **Step 3: Commit**

```bash
cd /Users/macpro/llama-cli
git add scripts/setup-mlc.brewfile
git commit -m "feat(mlc): Brewfile for MLC-LLM Vulkan toolchain"
```

---

## Task 2: Create the troubleshooting doc

**Files:**
- Create: `docs/gpu-mlc-setup.md`

- [ ] **Step 1: Write the doc**

Create `docs/gpu-mlc-setup.md` with:

````markdown
# MLC-LLM GPU Setup

The MLC-LLM backend can drive the 2× AMD FirePro D700 GPUs in the 2013
Mac Pro via Vulkan/MoltenVK. The setup script installs the toolchain
and verifies that Vulkan can see the GPUs.

## Quick start

```bash
# From the intellama repo root
zsh scripts/setup-mlc.sh
```

The script:
1. Pre-flights OS, arch, python, brew
2. Installs `molten-vk`, `vulkan-headers`, `vulkan-loader`, `vulkan-tools` via Homebrew
3. Creates a project venv at `~/.config/intellama/venv`
4. Installs `mlc-ai-nightly` and `mlc-llm-nightly` from `https://mlc.ai/wheels`
5. Verifies Vulkan sees ≥2 AMD devices

Re-running is safe — each step is idempotent.

## Environment variables

| Var | Default | Purpose |
|-----|---------|---------|
| `INTELLAMA_HOME` | `~/.config/intellama` | Override venv location |

## Requirements

- macOS (Darwin)
- Intel x86_64 (Apple Silicon is a separate effort)
- Python 3.9+ (`brew install python@3.12` if missing)
- Homebrew (`https://brew.sh`)
- For Phase 3 only (Metal fallback, not Phase 0): Xcode Command Line Tools (`xcode-select --install`)

## Troubleshooting

### "GPU verification FAILED — detected 0–1 AMD devices"

The script prints a red diagnostic and exits 1. Common causes:

1. **OCLP nightly regression.** OpenCore-Legacy-Patcher updates sometimes break
   Metal/Vulkan compute. Pin your OCLP nightly and check its release notes.
2. **Discrete GPU not selected.** Try `pmset gpuswitch 1` to force discrete GPU.
3. **MoltenVK not seeing the D700s.** Verify with:
   ```bash
   vulkaninfo --summary | grep deviceName
   ```
   Each D700 should appear as a separate device.
4. **macOS Sequoia regression.** Check the OCLP release notes for your nightly.

### "vulkaninfo not found"

Homebrew installed `vulkan-tools` but `vulkaninfo` is not on `PATH`. Run:

```bash
eval "$(brew --prefix)/bin/brew shellenv"
```

…and re-run the script.

### "pip install failed"

The MLC nightly index at `https://mlc.ai/wheels` rebuilds wheels frequently.
Common breakage: upstream build break, network egress blocked, or PEP 668
externally-managed-environment (rare on macOS Python ≤3.12, can bite on 3.13+).
If a wheel fails to import, check the [MLC nightly status page](https://mlc.ai)
for upstream issues.

### "Apple Silicon detected"

This script is Intel-only. Apple Silicon Macs use different setup
(no MoltenVK needed; Metal is native).

### Cleaning up

To remove the project venv:

```bash
rm -rf ~/.config/intellama/venv
```

To remove the brew formulae:

```bash
brew uninstall molten-vk vulkan-headers vulkan-loader vulkan-tools
brew untap moltenvk/vulkan
```

## After setup

Phase 0 is complete. The next sub-project (CPU validation) runs:

```bash
source ~/.config/intellama/venv/bin/activate
mlc_llm chat HF://mlc-ai/Qwen2.5-0.5B-Instruct-q4f16_1-MLC \
  --device cpu --num-threads 16
```

See the parent plan for the full Phase 1+ roadmap.
````

- [ ] **Step 2: Verify file**

```bash
test -f /Users/macpro/llama-cli/docs/gpu-mlc-setup.md && wc -l /Users/macpro/llama-cli/docs/gpu-mlc-setup.md
```

Expected: ~95 lines.

- [ ] **Step 3: Commit**

```bash
cd /Users/macpro/llama-cli
git add docs/gpu-mlc-setup.md
git commit -m "docs(mlc): gpu-mlc-setup guide and troubleshooting"
```

---

## Task 3: Create the setup script (preflight + main)

**Files:**
- Create: `scripts/setup-mlc.sh`

- [ ] **Step 1: Write the script (full content)**

Create `scripts/setup-mlc.sh` with this exact content:

```bash
#!/usr/bin/env zsh
# setup-mlc.sh — Install MLC-LLM toolchain and verify Vulkan sees the D700s.
# Idempotent. Refuses to run as root. macOS / Intel x86_64 only.
#
# Usage: zsh scripts/setup-mlc.sh
# Env:   INTELLAMA_HOME (default: ~/.config/intellama)

set -euo pipefail

# ─── Paths & colors ──────────────────────────────────────────────
INTELLAMA_HOME="${INTELLAMA_HOME:-$HOME/.config/intellama}"
VENV_DIR="$INTELLAMA_HOME/venv"
BREWFILE="$(cd "$(dirname "$0")" && pwd)/setup-mlc.brewfile"

RED=$'\033[31m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# ─── Pre-flight checks (abort on any failure) ───────────────────
# Refuse to run as root — Homebrew refuses too, and a root-run venv
# would land in the wrong place.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "${RED}intellama setup-mlc: do not run as root.${RESET}" >&2
    exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "${RED}intellama setup-mlc: macOS required (got: $(uname -s)).${RESET}" >&2
    exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "${RED}intellama setup-mlc: Intel x86_64 required (Apple Silicon is a separate effort).${RESET}" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "${RED}intellama setup-mlc: python3 not found. Install via 'brew install python@3.12'.${RESET}" >&2
    exit 1
fi

PY_VERSION="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
PY_MAJOR="${PY_VERSION%.*}"
PY_MINOR="${PY_VERSION#*.}"
if [[ "$PY_MAJOR" -lt 3 ]] || { [[ "$PY_MAJOR" -eq 3 ]] && [[ "$PY_MINOR" -lt 9 ]]; }; then
    echo "${RED}intellama setup-mlc: python3 ≥ 3.9 required (got: $PY_VERSION). Install via 'brew install python@3.12'.${RESET}" >&2
    exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
    echo "${RED}intellama setup-mlc: Homebrew required. Install from https://brew.sh.${RESET}" >&2
    exit 1
fi

# Warn-only: Xcode CLT — Phase 0–2 do not need it.
if ! xcode-select -p >/dev/null 2>&1; then
    echo "${YELLOW}intellama setup-mlc: warning — Xcode Command Line Tools not installed.${RESET}" >&2
    echo "${YELLOW}Phase 0–2 work without Xcode; Phase 3 (Metal fallback) will need 'xcode-select --install'.${RESET}" >&2
fi

# Ensure Homebrew is on PATH for this script's subprocesses only.
eval "$(brew --prefix)/bin/brew shellenv" 2>/dev/null || true

# ─── Step 1 — Homebrew install (idempotent) ─────────────────────
BREW_FORMULAE=(molten-vk vulkan-headers vulkan-loader vulkan-tools)
MISSING=()
for f in "${BREW_FORMULAE[@]}"; do
    brew list --formula "$f" >/dev/null 2>&1 || MISSING+=("$f")
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo "brew: ${#BREW_FORMULAE[@]} formulae already installed, skipping"
else
    if [[ ! -f "$BREWFILE" ]]; then
        echo "${RED}intellama setup-mlc: Brewfile not found: $BREWFILE${RESET}" >&2
        exit 1
    fi
    echo "brew: installing ${#MISSING[@]} missing formulae from $BREWFILE"
    brew bundle --file="$BREWFILE" --no-upgrade
    BREW_EXIT=$?
    if [[ $BREW_EXIT -ne 0 ]]; then
        echo "${RED}intellama setup-mlc: brew install failed — see output above.${RESET}" >&2
        echo "${RED}Common cause: missing Xcode CLT (required by Homebrew itself, not just by Phase 3).${RESET}" >&2
        echo "${RED}Try 'xcode-select --install' and re-run.${RESET}" >&2
        exit 1
    fi
fi

# Re-eval shellenv in case brew just installed for the first time.
eval "$(brew --prefix)/bin/brew shellenv" 2>/dev/null || true

# ─── Step 2 — Project venv + MLC-LLM wheels ────────────────────
mkdir -p "$INTELLAMA_HOME"

if [[ -x "$VENV_DIR/bin/python" ]]; then
    echo "venv: already present at $VENV_DIR, skipping create"
    echo "venv: upgrading pip"
    "$VENV_DIR/bin/pip" install --upgrade pip --quiet
else
    echo "venv: creating at $VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi

if ! "$VENV_DIR/bin/python" -c "import mlc_llm, tvm" >/dev/null 2>&1; then
    echo "pip: installing mlc-ai-nightly and mlc-llm-nightly from https://mlc.ai/wheels"
    "$VENV_DIR/bin/pip" install --pre -U mlc-ai-nightly mlc-llm-nightly -f https://mlc.ai/wheels
    PIP_EXIT=$?
    if [[ $PIP_EXIT -ne 0 ]]; then
        echo "${RED}intellama setup-mlc: pip install failed — see output above.${RESET}" >&2
        echo "${RED}The nightly index is at https://mlc.ai/wheels; check for upstream build breakages.${RESET}" >&2
        exit 1
    fi
    # Re-verify
    if ! "$VENV_DIR/bin/python" -c "import mlc_llm, tvm" >/dev/null 2>&1; then
        echo "${RED}intellama setup-mlc: pip install completed but import still fails.${RESET}" >&2
        echo "${RED}The nightly index may be broken. See docs/gpu-mlc-setup.md#troubleshooting.${RESET}" >&2
        exit 1
    fi
else
    echo "pip: mlc-ai-nightly and mlc-llm-nightly already installed, skipping"
fi

# ─── Step 3 — GPU verification (strict gate) ────────────────────
if ! command -v vulkaninfo >/dev/null 2>&1; then
    echo "${RED}intellama setup-mlc: vulkaninfo not found — brew install of vulkan-tools did not put it on PATH.${RESET}" >&2
    echo "${RED}Try 'eval \"\$(brew --prefix)/bin/brew shellenv\"' and re-run.${RESET}" >&2
    exit 1
fi

VULKAN_OUTPUT="$(vulkaninfo --summary 2>&1 || true)"
if [[ -z "$VULKAN_OUTPUT" ]]; then
    # Fallback: --summary may not be supported on older vulkan-tools.
    VULKAN_OUTPUT="$(vulkaninfo 2>&1 || true)"
fi

# Count deviceName lines containing AMD (case-insensitive).
AMD_COUNT="$(echo "$VULKAN_OUTPUT" | grep -c '^deviceName' || true)"
AMD_COUNT_AMD="$(echo "$VULKAN_OUTPUT" | grep -i '^deviceName.*amd' | wc -l | tr -d ' ' || true)"

# Prefer the AMD-specific count; if 0, fall back to total deviceName count
# to give a clearer error message.
if [[ "$AMD_COUNT_AMD" -ge 2 ]]; then
    echo "GPU: detected $AMD_COUNT_AMD AMD devices via Vulkan"
elif [[ "$AMD_COUNT" -ge 2 ]]; then
    echo "GPU: detected $AMD_COUNT devices via Vulkan (no 'AMD' string match — MoltenVK may report a generic name)"
else
    echo "${RED}intellama setup-mlc: GPU verification FAILED.${RESET}" >&2
    echo "" >&2
    echo "${RED}Detected $AMD_COUNT_AMD AMD device(s) via Vulkan.${RESET}" >&2
    echo "${RED}Expected: ≥ 2 AMD devices (Mac Pro 2013 has 2× FirePro D700).${RESET}" >&2
    echo "" >&2
    echo "${RED}Common causes:${RESET}" >&2
    echo "${RED}  1. OCLP nightly regression — Metal/Vulkan compute sometimes breaks${RESET}" >&2
    echo "${RED}     after OpenCore-Legacy-Patcher updates. See 'pmset gpuswitch 1' to${RESET}" >&2
    echo "${RED}     force discrete GPU.${RESET}" >&2
    echo "${RED}  2. MoltenVK not seeing the D700s — verify with${RESET}" >&2
    echo "${RED}     'vulkaninfo --summary | grep deviceName'. Each D700 should appear.${RESET}" >&2
    echo "${RED}  3. macOS Sequoia regression — check the OCLP release notes for your nightly.${RESET}" >&2
    echo "" >&2
    echo "${RED}Troubleshooting: see docs/gpu-mlc-setup.md#troubleshooting${RESET}" >&2
    exit 1
fi

# ─── Final banner ──────────────────────────────────────────────
MLC_VERSION="$("$VENV_DIR/bin/python" -c 'import mlc_llm; print(mlc_llm.__version__)' 2>/dev/null || echo unknown)"
echo "${GREEN}✓ MLC-LLM toolchain ready${RESET}"
echo "${DIM}venv:  $VENV_DIR${RESET}"
echo "${DIM}mlc:   $MLC_VERSION${RESET}"
echo "${DIM}next:  see docs/mlc-bench-cpu.txt (sub-project 2)${RESET}"
```

- [ ] **Step 2: Make executable and verify syntax**

```bash
chmod +x /Users/macpro/llama-cli/scripts/setup-mlc.sh
zsh -n /Users/macpro/llama-cli/scripts/setup-mlc.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Smoke test — refuses to run as root**

```bash
sudo -n zsh /Users/macpro/llama-cli/scripts/setup-mlc.sh 2>&1 | head -1 || true
```

Expected: prints `intellama setup-mlc: do not run as root.` and exits non-zero. (If `sudo` isn't available non-interactively, skip this step.)

- [ ] **Step 4: Smoke test — fails fast on non-Darwin or non-x86_64**

This box is Darwin + x86_64 so we test by running under a fake arch:

```bash
arch -x86_64 zsh /Users/macpro/llama-cli/scripts/setup-mlc.sh 2>&1 | head -3
```

Expected: passes the arch check, proceeds into the script (may fail later on brew if not configured, that's OK — the point is the arch check passes).

- [ ] **Step 5: Commit**

```bash
cd /Users/macpro/llama-cli
git add scripts/setup-mlc.sh
git commit -m "feat(mlc): setup-mlc.sh — brew + venv + GPU verification"
```

---

## Task 4: Add the new check to npm test

**Files:**
- Modify: `package.json:24` (the `test` script)

- [ ] **Step 1: Read the current test script**

```bash
grep '"test"' /Users/macpro/llama-cli/package.json
```

- [ ] **Step 2: Modify the test script**

Replace the `test` value (currently:

```json
"test": "zsh -n src/llama-launcher.sh && node --check bin/intellama.js && node --check bin/llama-cli.js && node --check scripts/postinstall.js"
```

) with:

```json
"test": "zsh -n src/llama-launcher.sh && zsh -n scripts/setup-mlc.sh && node --check bin/intellama.js && node --check bin/llama-cli.js && node --check scripts/postinstall.js"
```

- [ ] **Step 3: Run npm test**

```bash
cd /Users/macpro/llama-cli
npm test
```

Expected: all checks pass (the new `zsh -n scripts/setup-mlc.sh` is included).

- [ ] **Step 4: Commit**

```bash
cd /Users/macpro/llama-cli
git add package.json
git commit -m "test: add setup-mlc.sh syntax check to npm test"
```

---

## Task 5: README pointer

**Files:**
- Modify: `README.md` (find an appropriate place in the existing `## Development` section, or add a new section if needed)

- [ ] **Step 1: Find the Development section or a logical insertion point**

```bash
grep -n "^## " /Users/macpro/llama-cli/README.md
```

- [ ] **Step 2: Add the MLC pointer**

Locate the existing `## Development` section (or a section about advanced setup). If one exists, add the following line at the end of that section:

```markdown
- MLC-LLM toolchain: see [`docs/gpu-mlc-setup.md`](docs/gpu-mlc-setup.md)
  and run `scripts/setup-mlc.sh` to install.
```

If no `## Development` section exists, add a new section:

````markdown
## Development

- MLC-LLM toolchain: see [`docs/gpu-mlc-setup.md`](docs/gpu-mlc-setup.md)
  and run `scripts/setup-mlc.sh` to install.
````

- [ ] **Step 3: Verify the README still renders sensibly**

```bash
head -50 /Users/macpro/llama-cli/README.md
```

- [ ] **Step 4: Commit**

```bash
cd /Users/macpro/llama-cli
git add README.md
git commit -m "docs(readme): link to MLC-LLM setup script and guide"
```

---

## Task 6: End-to-end dry run (manual, on this box)

**Files:** none

This task verifies the script works on the actual target hardware before tagging. Run on the intellama repo root. **If anything fails, document in `docs/mlc-setup-run-2026-06-07.txt` and either fix the script (Tasks 3–5 patches) or stop and report.**

- [ ] **Step 1: Run the script and capture output**

```bash
zsh /Users/macpro/llama-cli/scripts/setup-mlc.sh 2>&1 | tee /tmp/setup-mlc-dryrun.log
```

Expected: brew step skips (formulae not yet installed — script will install), venv creates, pip installs, GPU gate runs. Either the green banner (success) or the red diagnostic (GPU failure). Both are valid outcomes — capture the result.

- [ ] **Step 2: If red diagnostic fires** (GPU gate fails), the script is working correctly. Capture the log to docs:

```bash
cp /tmp/setup-mlc-dryrun.log /Users/macpro/llama-cli/docs/mlc-setup-run-2026-06-07.txt
cd /Users/macpro/llama-cli
git add docs/mlc-setup-run-2026-06-07.txt
git commit -m "docs(mlc): record Phase 0 dry-run output (GPU gate failed — investigate)"
```

Then **stop**. The D700 Vulkan issue is a known risk; the script's job is to surface it cleanly. Do not invent workarounds.

- [ ] **Step 3: If green banner fires**, verify the venv works:

```bash
/Users/macpro/llama-cli/../../.config/intellama/venv/bin/python -c "import mlc_llm; print(mlc_llm.__version__)"
```

Note: if `INTELLAMA_HOME` is overridden in your shell, use that path instead. Default is `~/.config/intellama/venv`.

- [ ] **Step 4: Re-run for idempotency check**

```bash
zsh /Users/macpro/llama-cli/scripts/setup-mlc.sh 2>&1
```

Expected: each step prints "already <state>, skipping". Should complete in <2 seconds.

- [ ] **Step 5: Capture the success log to docs:**

```bash
cp /tmp/setup-mlc-dryrun.log /Users/macpro/llama-cli/docs/mlc-setup-run-2026-06-07.txt
cd /Users/macpro/llama-cli
git add docs/mlc-setup-run-2026-06-07.txt
git commit -m "docs(mlc): record Phase 0 successful dry-run output"
```

- [ ] **Step 6: No code changes** in this task — pure verification.

---

## Task 7: Bump version to 1.3.0-alpha and tag

**Files:**
- Modify: `package.json:3` (version field)
- Modify: `README.md:1-3` (version banner — only if a banner exists)

- [ ] **Step 1: Check current version**

```bash
grep '"version"' /Users/macpro/llama-cli/package.json
```

- [ ] **Step 2: Bump version**

```bash
cd /Users/macpro/llama-cli
sed -i.bak 's/"version": "1.2.3"/"version": "1.3.0-alpha"/' package.json
rm -f package.json.bak
grep '"version"' package.json
```

Expected: `"version": "1.3.0-alpha",`

- [ ] **Step 3: Update README banner if present**

```bash
grep -n "v1.2.3\|v1\." /Users/macpro/llama-cli/README.md | head -5
```

If a version banner exists, replace the line with:

```markdown
> **v1.3.0-alpha — MLC-LLM Phase 0 toolchain (brew + venv + Vulkan verify)**
> - New `scripts/setup-mlc.sh` brings the box to MLC-ready state in one command.
> - New `docs/gpu-mlc-setup.md` covers install + troubleshooting.
> - `npm test` gains a `zsh -n scripts/setup-mlc.sh` gate.
```

- [ ] **Step 4: Final npm test**

```bash
cd /Users/macpro/llama-cli
npm test
```

Expected: all checks pass.

- [ ] **Step 5: Commit and tag (do NOT push without user approval)**

```bash
cd /Users/macpro/llama-cli
git add package.json README.md
git commit -m "release: v1.3.0-alpha — MLC-LLM Phase 0 prerequisites"
git tag v1.3.0-alpha
git log --oneline -10
```

- [ ] **Step 6: Stop here.** Do not push. Ask the user before pushing.

---

## Self-Review

**Spec coverage:**

| Spec section | Covered by task |
|--------------|-----------------|
| Goal + non-goals (script, brewfile, doc; no launcher changes) | Tasks 1, 2, 3, 4 (no launcher files touched) |
| Pre-flight checks (OS, arch, python, brew, warn-only Xcode) | Task 3 Step 1 (lines covering each check) |
| Step 1 Homebrew (idempotent, --no-upgrade, shellenv) | Task 3 Step 1 (Step 1 section) |
| Step 2 venv + wheels (stdlib, reuse, error handling) | Task 3 Step 1 (Step 2 section) |
| Step 3 GPU verification (strict gate, red block, 2-line counts) | Task 3 Step 1 (Step 3 section) |
| Files added: setup-mlc.sh, setup-mlc.brewfile, gpu-mlc-setup.md | Tasks 1, 2, 3 |
| `package.json` test script change | Task 4 |
| README pointer | Task 5 |
| Logging format (key: value) | Task 3 (each step prints `<key>: <value>`) |
| Idempotency contract | Task 6 Step 4 verifies it |
| Static + manual verification matrix (fresh run, re-run, partial state, GPU failure, arch failure, no brew) | Task 6 covers fresh run + re-run; arch/brew failures covered by Task 3 Step 3/Step 4 |
| Logging closeout: `docs/mlc-setup-run-<date>.txt` | Task 6 Steps 2/5 |
| Out-of-scope items (no chat, no compile, no launcher, no menu) | Plan does not include any of these |

**Placeholder scan:** None. Every command is shown with expected output. Script body is a single complete file in Task 3.

**Type/name consistency:**
- `INTELLAMA_HOME` defined in Task 3, used in Tasks 4 (npm test doesn't touch it), 6 (dry run reads from default). ✓
- `VENV_DIR`, `BREWFILE` defined in Task 3, only used within Task 3. ✓
- `setup-mlc.sh` created in Task 3, referenced in Tasks 4, 5, 6, 7. ✓
- `setup-mlc.brewfile` created in Task 1, referenced in Task 3. ✓
- `docs/gpu-mlc-setup.md` created in Task 2, referenced in Task 3's red diagnostic, Task 5 README link, Task 6. ✓
- `mlc-setup-run-2026-06-07.txt` filename matches spec's `docs/mlc-setup-run-<date>.txt` pattern. ✓

**Gaps:** None. The plan is fully self-contained for Sub-project 1.

---

## Out of Scope (NOT in this plan)

- Phase 1 (CPU validation) — sub-project 2
- Phase 2 (Vulkan experiment) — sub-project 3
- Phase 3 (Metal fallback) — sub-project 4, only if sub-project 3 fails
- Phase 4 (intellama integration) — sub-project 5, only after sub-projects 2+3 produce a coherent GPU path
- Phase 5 (dual-GPU tensor parallel) — sub-project 6
- llama.cpp PR for subgroupBroadcast fix
- Changes to `src/llama-launcher.sh` or any other intellama launcher code
- Changes to `bin/intellama.js` or any Node.js code
- Model compilation or chat testing
