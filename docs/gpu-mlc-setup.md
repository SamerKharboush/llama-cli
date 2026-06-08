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

Homebrew installed `vulkan-tools` but `vulkaninfo` is not on PATH. Run:

```bash
eval "$(brew --prefix)/bin/brew shellenv"
```

…and re-run the script.

### "pip install failed"

The MLC nightly index at `https://mlc.ai/wheels` rebuilds wheels frequently.
Common breakage: upstream build break, network egress blocked, or PEP 668
externally-managed-environment (rare on macOS Python ≤3.12, can bite on 3.13+).
If a wheel fails to import, check the MLC nightly status page for upstream issues.

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
