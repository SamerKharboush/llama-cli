# MLC-LLM Phase 0 — Prerequisites Sub-Project

**Status:** Approved (brainstorm completed 2026-06-07)
**Date:** 2026-06-07
**Parent index:** `docs/superpowers/specs/2026-06-07-mlc-llm-integration-design.md`
**Sub-project of:** intellama v1.3.0 MLC-LLM adoption (Phase 0 of 5)
**Hardware context:** 2013 Mac Pro · 2× AMD FirePro D700 (GCN 1.0, 6 GB VRAM each) · Intel Xeon E5 Ivy Bridge · macOS Sequoia via OCLP · no Xcode
**Source plan:** `/Users/macpro/mlc-llm-adoption-plan.md` (Phase 0 only)

---

## Goal & Non-Goals

**Goal.** Add `scripts/setup-mlc.sh` to the intellama repo. Running the
script on a clean target box brings the machine to the state described
in the source plan's "Phase 0" section: Homebrew formulae installed,
project-local Python venv at `~/.config/intellama/venv` with MLC-LLM
nightly wheels, and `vulkaninfo --summary` reporting ≥2 AMD devices
(sufficient to know that Vulkan can see both D700s). The script exits
non-zero if the strict GPU gate fails, and prints a red diagnostic block
pointing at the troubleshooting doc.

**Non-goals.**
- Running any `mlc_llm chat` or `mlc_llm bench` — that is sub-project 2.
- Compiling or running models — that is sub-project 2+.
- Touching intellama's launcher (`src/llama-launcher.sh`, `bin/intellama.js`).
- Adding `mlc_llm` to the bundled npm tarball.
- Wiring MLC into the intellama menu — that is sub-project 5.
- Supporting Apple Silicon, Linux, or any non-Darwin-x86_64 platform.
- Auto-running on `npm install` (no postinstall hook for Phase 0).

**Success criteria.**
- `zsh scripts/setup-mlc.sh` on a clean box exits 0 and produces:
  - `brew list` shows `molten-vk`, `vulkan-headers`, `vulkan-loader`, `vulkan-tools`.
  - `~/.config/intellama/venv/bin/python -c "import mlc_llm, tvm"` exits 0.
  - `vulkaninfo --summary | grep -c '^deviceName'` shows ≥2 AMD devices.
  - Last 3 lines of stdout are a green "✓ MLC-LLM toolchain ready" banner
    with a `next:` line pointing at sub-project 2 (`docs/mlc-bench-cpu.txt`).
- Re-running the script is a no-op: it skips work that's already done.
- Running on a box where Vulkan sees 0–1 AMD devices: script exits 1,
  prints the red diagnostic block, and does not touch the venv.
- `npm test` passes (gains one new `zsh -n scripts/setup-mlc.sh` line).

---

## Pre-flight Checks (script aborts with clear error if any fail)

Run **before** touching brew or pip. If any check fails, print a red
single-line error and `exit 1` immediately — do not partially install.

| Check | Command | Pass criterion | Failure message |
|-------|---------|---------------|-----------------|
| OS | `uname -s` | `Darwin` | `intellama setup-mlc: macOS required (got: <uname>).` |
| Arch | `uname -m` | `x86_64` | `intellama setup-mlc: Intel x86_64 required (Apple Silicon is a separate effort).` |
| Python | `python3 --version` | ≥ 3.9 | `intellama setup-mlc: python3 ≥ 3.9 required (got: <ver>). Install via 'brew install python@3.12'.` |
| Homebrew | `command -v brew` | exit 0 | `intellama setup-mlc: Homebrew required. Install from https://brew.sh.` |
| Xcode CLT (warn only) | `xcode-select -p` | non-empty | Yellow warning line: `intellama setup-mlc: warning — Xcode Command Line Tools not installed. Phase 0–2 work without Xcode; Phase 3 (Metal fallback) will need 'xcode-select --install'.` |

**Why warn-only on Xcode CLT.** Phase 0–2 (prereqs, CPU smoke test, Vulkan
experiment) do not need Xcode. The warning surfaces the cost of the
Metal fallback path without blocking progress on the more common Vulkan
path.

---

## Step 1 — Homebrew Install (idempotent)

**Why this exact bundle.** `molten-vk` provides the Vulkan→Metal
translation layer. `vulkan-headers` and `vulkan-loader` provide the
runtime + headers `vulkaninfo` needs. `vulkan-tools` provides
`vulkaninfo` itself.

**Implementation.** Use a `Brewfile` checked into the repo at
`scripts/setup-mlc.brewfile`:

```ruby
tap "moltenvk/vulkan"
brew "molten-vk"
brew "vulkan-headers"
brew "vulkan-loader"
brew "vulkan-tools"
```

**Script behavior.**
- Check `brew list` for each formula. If all present, print
  `brew: already installed, skipping` and continue.
- If any are missing, run `brew bundle --file=scripts/setup-mlc.brewfile --no-upgrade`.
  `--no-upgrade` keeps the script deterministic — upgrades happen on
  user-driven `brew upgrade`, not via this script.
- After install, ensure Homebrew's bin is on `PATH`. Detect with
  `brew --prefix` and prepend if needed; export for the script's
  subprocesses only (do not modify the user's shell rc).

**Failure handling.** If `brew bundle` exits non-zero, print
`brew install failed — see output above. Common cause: missing Xcode CLT
(required by Homebrew itself, not just by Phase 3). Try
'xcode-select --install' and re-run.` and `exit 1`. Do not attempt to
recover — Homebrew failures are user-actionable.

---

## Step 2 — Project venv + MLC-LLM Wheels

**Why a project venv.** The system Python (and any user `pyenv` /
`conda`) is out of scope. The venv lives at
`${INTELLAMA_HOME:-$HOME/.config/intellama}/venv` — overridable for
testing, but a single default that all intellama scripts share.

**Why stdlib only.** `python3 -m venv` ships with the macOS system
Python 3.9+. No `conda`, no `uv`, no `pyenv` — those are not
prerequisites for a clean box.

**Why the non-canonical index.** `mlc-ai-nightly` and `mlc-llm-nightly`
are not on PyPI's default index. The canonical source is
`https://mlc.ai/wheels`. This is a supply-chain surface — the spec
records the URL, the script does not silently change it.

**Script behavior.**
- If `$INTELLAMA_HOME/venv/bin/python` exists:
  - Print `venv: already present at <path>, skipping create`.
  - Run `pip install --upgrade pip` only (no MLC re-install).
- Else:
  - `python3 -m venv "$INTELLAMA_HOME/venv"`.
  - Print `venv: created at <path>`.
- Activate the venv (`source "$INTELLAMA_HOME/venv/bin/activate"` — or
  invoke pip via `$INTELLAMA_HOME/venv/bin/pip` to avoid polluting the
  parent shell environment).
- `pip install --pre -U mlc-ai-nightly mlc-llm-nightly -f https://mlc.ai/wheels`.
- Verify: `"$INTELLAMA_HOME/venv/bin/python" -c "import mlc_llm, tvm; print(mlc_llm.__version__)"`.
  If the import fails, print `pip install failed — see output above. The
  nightly index is at https://mlc.ai/wheels; check for upstream build
  breakages.` and `exit 1`.

**Failure handling.** Pip failures abort the script — partial installs
are worse than no install. The troubleshooting doc covers the most
common breakage (upstream build break, network egress blocked, PEP 668
externally-managed-environment — but on macOS system Python ≤ 3.12, this
last one is rare; on 3.13+ it can bite).

---

## Step 3 — GPU Verification (strict gate)

**Strict gate semantics.** This is the only step in Phase 0 that exits
non-zero on detection failure. The whole point of Phase 0 is to know
"can the D700s be reached via Vulkan?" If no, we stop here and the user
investigates **before** they spend an hour on the Phase 2 chat smoke
test only to discover Vulkan is blocked.

**Script behavior.**
- Run `vulkaninfo --summary 2>&1` and capture stdout.
- If `vulkaninfo` is not on `PATH`, print `vulkaninfo not found — brew
  install of vulkan-tools did not put it on PATH. Try 'eval
  "$(brew --prefix)/bin/brew shellenv"' and re-run.` and `exit 1`.
- Count `^deviceName` lines in the output (`grep -c '^deviceName'`).
  (Note: `vulkaninfo --summary` prints a `deviceName` line per physical
  device.)
- Count `deviceName` lines that contain `AMD` (case-insensitive
  `grep -ci 'amd'`). Call this `amd_count`.
- If `amd_count >= 2`: print `GPU: detected <amd_count> AMD devices via Vulkan.`
- If `amd_count < 2`: print the red diagnostic block (below) and
  `exit 1`.

**Red diagnostic block** (printed to stderr, with ANSI red):

```
intellama setup-mlc: GPU verification FAILED.

Detected <amd_count> AMD device(s) via Vulkan.
Expected: ≥ 2 AMD devices (Mac Pro 2013 has 2× FirePro D700).

Common causes:
  1. OCLP nightly regression — Metal/Vulkan compute sometimes breaks
     after OpenCore-Legacy-Patcher updates. See 'pmset gpuswitch 1' to
     force discrete GPU.
  2. MoltenVK not seeing the D700s — verify with
     'vulkaninfo --summary | grep deviceName'. Each D700 should appear.
  3. macOS Sequoia regression — check the OCLP release notes for your
     nightly.

Troubleshooting: see docs/gpu-mlc-setup.md#troubleshooting
```

**Strict gate justification.** Soft-fail (warn and continue) is tempting
but harmful: the user gets a "toolchain ready" banner, walks into Phase
2, and discovers Vulkan is broken only after running the chat smoke
test. Hard-fail surfaces the problem at the cheapest possible point.

---

## Files Added to the Repo

| File | Purpose | Mode | Lines (target) |
|------|---------|------|----------------|
| `scripts/setup-mlc.sh` | The script itself | `0755` | ~120 |
| `scripts/setup-mlc.brewfile` | Brew formulae for the install | `0644` | 6 |
| `docs/gpu-mlc-setup.md` | User-facing setup + troubleshooting doc | `0644` | ~80 |

**`package.json` change.** Add one line to the `test` script:

```diff
-  "test": "zsh -n src/llama-launcher.sh && node --check bin/intellama.js && node --check bin/llama-cli.js && node --check scripts/postinstall.js"
+  "test": "zsh -n src/llama-launcher.sh && zsh -n scripts/setup-mlc.sh && node --check bin/intellama.js && node --check bin/llama-cli.js && node --check scripts/postinstall.js"
```

**npm tarball behavior.** The current `package.json` `files` allowlist
includes `scripts/`, so `scripts/setup-mlc.sh` and
`scripts/setup-mlc.brewfile` will ship in the npm tarball. This is
intentional: users on a fresh `npm install -g intellama` should be able
to run `intellama-setup-mlc` (or read the README's path pointer) to
kick off the MLC toolchain install. The troubleshooting doc
`docs/gpu-mlc-setup.md` is in the repo root's `docs/`, not under
`docs/superpowers/specs/`, so it does not ship with npm. README links
to it via the GitHub URL.

**README change.** One line in the existing `## Development` section:

```markdown
- MLC-LLM toolchain: see [`docs/gpu-mlc-setup.md`](docs/gpu-mlc-setup.md)
  and run `scripts/setup-mlc.sh` to install.
```

---

## Logging & Idempotency

**Stdout format.** Each step prints one `key: value` line (e.g.
`brew: 4 formulae already installed`, `venv: created at /Users/x/.config/intellama/venv`,
`GPU: detected 2 AMD devices via Vulkan.`). Final line is the green
`✓ MLC-LLM toolchain ready` banner with the sub-project-2 pointer.

**Stderr format.** Errors and the red diagnostic block. Never mix red
diagnostic with green banner.

**Idempotency contract.**
- Re-running with everything already installed: each step prints
  `already <state>, skipping` and exits 0 in <2 seconds.
- Re-running with venv present but wheels stale: venv kept, wheels
  upgraded in place.
- Re-running with brew formulae present but `vulkaninfo` not on PATH:
  the brew step prints `already installed` (it is), but the venv / GPU
  steps still run, and the GPU step surfaces the PATH issue with a
  clear remediation message.

**Re-runnability of `pip install --pre -U`.** MLC's nightly index
rebuilds wheels frequently. `--pre -U` is the canonical "give me the
latest pre-release" command — it does not downgrade, and it is
deterministic on a given day. This is the right knob for "I'm a dev
trying MLC; just give me the newest build."

---

## Testing & Verification

### A. Static (npm test)

`npm test` gains the `zsh -n scripts/setup-mlc.sh` line. CI / local gate
catches syntax errors before any install runs.

### B. Manual verification matrix (run before tagging the sub-project)

| Scenario | Expected | Notes |
|----------|----------|-------|
| **Fresh run on clean box** | Brew installs, venv creates, MLC wheels install, GPU gate passes, banner green, exit 0 | The happy path |
| **Re-run after success** | Each step prints `already <state>, skipping`, exit 0 in <2s | Idempotency proof |
| **Brew already installed, venv missing** | Brew step skipped, venv created, GPU gate runs, exit 0 | Partial state |
| **Venv already present, brew missing** | Brew installs, venv reused, MLC wheels upgraded, GPU gate runs, exit 0 | Partial state |
| **Simulated GPU failure** (e.g. `vulkaninfo` returns 0 devices) | Red diagnostic block to stderr, exit 1, venv untouched | Strict gate |
| **Apple Silicon Mac** | Arch check fires, exits 1 with clear message, no install attempted | Pre-flight |
| **No Homebrew** | Brew check fires, exits 1 with brew.sh link, no install attempted | Pre-flight |
| **No python3** | Python check fires, exits 1 with brew install hint, no install attempted | Pre-flight |

**Logging convention for sub-project closeout.** Commit
`docs/mlc-setup-run-<date>.txt` capturing the full script output from
the fresh-run scenario. This is the same pattern sub-projects 2-6 will
use for `docs/mlc-bench-*.txt`.

---

## Out of Scope (intentionally)

- **Running `mlc_llm chat` or `mlc_llm bench`.** That is sub-project 2
  (CPU validation) and sub-project 3 (Vulkan experiment).
- **Compiling any model for Vulkan.** That is sub-project 3.
- **Touching intellama's launcher or menu.** That is sub-project 5.
- **Resolving the zsh-vs-Node adapter question.** That is sub-project 5.
- **Xcode CLT installation.** Sub-project 4 only, and only if Phase 2
  fails.
- **Supply-chain pinning (e.g. SHA-locking the wheel index).** The
  nightly index is moving; pinning defeats the purpose. The
  troubleshooting doc tells users how to verify a wheel if they care.
- **Conda / uv / pyenv support.** Stdlib `venv` only. Users with a
  different preference can read the script and adapt it.

---

## Risks

- **R1 — `vulkaninfo --summary` output format is not stable across
  MoltenVK versions.** Mitigation: count `^deviceName` lines (the field
  name is stable even when fields around it move). Fall back to
  `vulkaninfo | grep -ci 'amd'` if the `--summary` flag is missing on
  the user's installed version.
- **R2 — `pip install --pre -U` from a non-canonical index can pull a
  broken wheel.** Mitigation: the `import mlc_llm, tvm` check at the
  end of Step 2 catches "wheel installed but unimportable" — the script
  exits 1 in that case and the troubleshooting doc points the user at
  the MLC nightly status page.
- **R3 — The project venv path (`~/.config/intellama/venv`) collides
  with a user-installed venv at the same path.** Mitigation:
  `INTELLAMA_HOME` env var override is documented; the default path is
  namespaced under `intellama/`, which is the existing launcher config
  directory.
- **R4 — The script is run with `sudo` or as root, polluting
  `/Users/<whoever>/.config/intellama/venv` for the wrong user.**
  Mitigation: refuse to run as root (`[ "$(id -u)" -eq 0 ] && exit 1`
  with a clear message). Homebrew itself refuses to run as root.
- **R5 — `npm pack` includes `scripts/setup-mlc.sh` in the tarball
  even though only some users want it.** Mitigation: the script is
  opt-in (you run it manually after `npm install -g`); it does not run
  on `postinstall`. Users who never call it pay ~2 KB of tarball size.
- **R6 — The strict GPU gate blocks users who want to install the
  toolchain but defer GPU validation.** Mitigation: this is a feature,
  not a bug. The user can run Phase 1 (CPU smoke) on a box where Vulkan
  is broken; Phase 1 does not require Phase 0's GPU gate to pass.
  Future sub-projects can revisit, but for Phase 0 the strict gate is
  right.

---

## Verification (end-to-end for this sub-project)

```bash
# 1. Static gate
npm test
# Expect: all checks pass, including the new zsh -n scripts/setup-mlc.sh

# 2. Fresh-run happy path (clean box, or after `rm -rf ~/.config/intellama/venv`)
zsh scripts/setup-mlc.sh
# Expect:
#   brew: 4 formulae already installed   (or: brew: installed <N> formulae)
#   venv: created at /Users/<you>/.config/intellama/venv
#   pip:  installed mlc-ai-nightly, mlc-llm-nightly
#   GPU:  detected 2 AMD devices via Vulkan.
#   ✓ MLC-LLM toolchain ready
#   next: see docs/mlc-bench-cpu.txt (sub-project 2)
# Exit code: 0

# 3. Re-run idempotency
zsh scripts/setup-mlc.sh
# Expect: each step prints "already <state>, skipping"
# Exit code: 0, < 2s wall time

# 4. Simulated GPU failure
PATH=/usr/bin:/bin zsh scripts/setup-mlc.sh
# (PATH trim removes brew's bin; vulkaninfo missing)
# Expect: red diagnostic block on stderr, exit 1
# (Note: PATH trim also breaks brew detection, so pre-flight will fire first
# in this exact form. To simulate GPU-only failure, install brew+venv, then
# temporarily mask vulkaninfo: `chmod 000 $(brew --prefix)/bin/vulkaninfo`.)

# 5. Apple Silicon failure
# Run on an arm64 Mac (or under `arch -arm64 zsh scripts/setup-mlc.sh`)
# Expect: arch check fires, exit 1, no install
```

---

## Handoff to Sub-Project 2 (CPU validation)

Once Phase 0 exits 0, sub-project 2 can begin. Phase 2 does:

```bash
source ~/.config/intellama/venv/bin/activate
mlc_llm chat HF://mlc-ai/Qwen2.5-0.5B-Instruct-q4f16_1-MLC \
  --device cpu --num-threads 16
mlc_llm bench HF://mlc-ai/Qwen2.5-0.5B-Instruct-q4f16_1-MLC \
  --device cpu --num-threads 16 --num-prompts 3 \
  | tee docs/mlc-bench-cpu.txt
```

This is **not** part of Phase 0. Sub-project 2 owns it.
