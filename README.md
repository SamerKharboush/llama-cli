# intellama

Optimized terminal launcher for local GGUF models on Intel x64 Macs, built around a pinned `llama.cpp` binary package and an interactive `intellama` menu (formerly `llama-cli`).

> **v1.3.0-alpha — MLC-LLM Phase 0 prerequisites**
> - New `scripts/setup-mlc.sh` brings the box to MLC-ready state in one command.
> - New `docs/gpu-mlc-setup.md` covers install + troubleshooting.
> - `npm test` gains a `zsh -n scripts/setup-mlc.sh` gate.
> - Note: current x86_64 macOS MLC nightly wheels import-fail in `tvm_ffi` on Python 3.12; Vulkan detection succeeds on both D700s.

> **v1.2.3 — Select actually loads + GPU probe env vars**
> - `select_model` now detects a running server (ours or foreign) and asks "Stop the current server and start '<new>'? [y/N]". Same-model picks skip the prompt.
> - New `gpu_probe_env` setting (default `MTL_DEBUG_LAYER,MTL_SHADER_VALIDATION,GGML_METAL_DEVICE`) — the `g` menu probe exports any listed var that is set in your shell, so you can test Metal/Vulkan env knobs without code changes.
> - New `gpu_probe_port` setting (default 18081) so the probe never collides with a real server on 8081.

> **v1.2.2 — Server discovery + unload endpoint**
> - `eject` / `stop` / `purge` now detect a `llama-server` already on the port (even if intellama didn't start it) and report honestly instead of printing "done" while the foreign server keeps running.
> - `eject` calls `POST /models/unload` (llama.cpp master) with a fallback to legacy `POST /unload`. No more silent 404 false-positive.
> - `stop` on a foreign server asks for confirmation before killing the PID (`lsof -ti :port` discovery).
> - `server_status` annotates foreign-server ownership with a clear note.

> **v1.2.1 — Bugfixes + Ivy Bridge perf track + GPU probe**
> - Banner reads version from `package.json` (no more stale "v1.1.0").
> - Settings menu count derives from `ALL_KEYS` (no more stale "35 options").
> - Model select works for any index (root cause: `setopt KSH_ARRAYS` removed).
> - `set_setting()` validates numeric and `spec_type` inputs; `load_config()` resets invalid entries to defaults with a warning. The crash on `cache_reuse=off` is fixed.
> - `build_command()` gates `--cache-reuse`, `--cache-ram`, `--fit-target` to integer regex.
> - New settings: `spec_ngram_simple_{size_n,size_m,min_hits}`, `spec_ngram_mod_{n_min,n_max,n_match}`, `cache_ram_mib`. Ivy Bridge: `spec_type` defaults to `ngram-simple` on first run.
> - New menu option `g` — "Probe GPU Compute" — runs a tiny model with `-ngl 99` against the optional Metal companion build (`releases/llama-cpp-macpro-metal.tar.gz`) and reports whether GPU compute is functional under your current OCLP nightly.

![intellama terminal screenshot](assets/llama-cli-screenshot.png)

## What This Is

`llama-cli` packages an optimized `llama.cpp` build and a zsh terminal launcher for Intel Macs. The default profile is tuned for the 12-core Mac Pro 2013 / Xeon E5 Ivy Bridge class of machines running modern macOS through OCLP.

The launcher scans `~/models` for `.gguf` files, lets you choose a model by number, configures server/runtime settings, starts an OpenAI-compatible local API server, tracks only the server it started, and writes logs under `~/.config/llama-launcher/logs`.

## Install With npm

```bash
npm install -g intellama
intellama
```

> Back-compat: the `llama-cli` command is still installed as an alias to `intellama` for this release.

Put models anywhere under:

```bash
~/models
```

You can override paths:

```bash
MODELS_DIR=/Volumes/Models intellama
LLAMA_DIR=/usr/local/llama-cpp intellama
```

## Standalone Archive Install

Download or copy one of the release archives from `releases/`.

```bash
tar xzf releases/llama-cpp-macpro-optimized.tar.gz
cd llama-cpp-macpro
./install.sh
/usr/local/llama-cpp/bin/llama-launcher.sh
```

ZIP is also available:

```bash
unzip releases/llama-cpp-macpro-optimized.zip
cd llama-cpp-macpro
./install.sh
```

## Included Tools

| Tool | Purpose |
|---|---|
| `intellama` | NPM command that launches the terminal app |
| `llama-cli` | Back-compat alias to `intellama` |
| `llama-launcher.sh` | Interactive zsh launcher |
| `llama-server` | OpenAI-compatible API server |
| `llama-bench` | Local benchmark runner |
| `llama-quantize` | Quantization utility |
| `llama-perplexity` | Perplexity testing utility |

## Build Profile

The bundled `llama.cpp` build is CPU-first and tuned for Ivy Bridge:

```text
GGML_AVX=ON
GGML_AVX2=OFF
GGML_FMA=OFF
GGML_F16C=ON
GGML_METAL=OFF
GGML_BLAS=ON
GGML_BLAS_VENDOR=Apple
CFLAGS=-march=ivybridge -mtune=ivybridge
CXXFLAGS=-march=ivybridge -mtune=ivybridge
CMAKE_BUILD_TYPE=Release
```

Why CPU-first: on this Mac Pro/OCLP setup, `llama-server` reports no usable GPU for this build, and the tested stable path is Apple Accelerate BLAS on CPU with AVX/F16C and no AVX2/FMA.

## Performance

The launcher auto-detects CPU cores, RAM, and instruction-set features
(`AVX`, `AVX2`, `FMA`, `F16C`) on launch via `sysctl`. Thread count defaults
to the number of physical cores. The “Show Hardware” menu option prints
the probe results so you can verify what the launcher saw.

On Ivy Bridge (DDR3-1866 quad-channel, ~60 GB/s ceiling) the inference
ceiling is memory bandwidth. Mitigations baked into the launcher:

- **MoE-friendly defaults** — `-ngl 0`, `-t <physical cores>`,
  `--mlock --no-mmap`, quantized KV cache.
- **Self-speculative decoding** — settings 36–39 let you opt into
  `ngram-simple` / `ngram-mod` / `ngram-cache` / `draft-mtp`. The n-gram
  modes reuse the active model and look up recent token windows instead
  of reading extra weights. On Ivy Bridge the launcher caps
  `--spec-draft-n-max` at 16 — beyond that the extra draft reads cost
  more DDR3 bandwidth than they save.
- **N-gram tuning knobs (v1.2.1)** — settings 40–46 expose
  `--spec-ngram-simple-size-n/m/min-hits` and
  `--spec-ngram-mod-n-min/n-max/n-match`, plus a `--cache-ram` MiB cap
  for the prompt cache (default 0 = unlimited up to server's 8 GiB).
  On Ivy Bridge the launcher now auto-selects `ngram-simple` for new
  installs so first-time users hit the documented baseline.
- **MTP draft models** — `draft-mtp` requires a clean MTP-capable GGUF
  (some community MTP conversions are corrupted and will produce
  garbage). Leave `spec_type` on `off` unless you have a known-good MTP
  file.

Pick a single model that fits comfortably in RAM, keep the launcher
defaults, and you should match or slightly exceed the baseline Q8_0
throughput. The 35B-A3B MoE at Q8_0 is the sweet spot: ~8.7 tok/s
baseline; `ngram-simple` should land at or just above that on Ivy
Bridge.

## Default Runtime Profile

The launcher defaults are conservative for a 12-core / 64 GB RAM Intel Mac Pro:

| Setting | Default |
|---|---|
| Threads | `12` |
| Context | `8192` |
| Batch | `2048` |
| uBatch | `512` |
| GPU layers | `0` |
| KV cache | `q4_0/q4_0` |
| mmap | disabled |
| mlock | enabled |
| Fit | `on` |
| Server | `127.0.0.1:8081` |

Direct server example:

```bash
llama-server \
  -m ~/models/model-folder/model.gguf \
  -ngl 0 -t 12 -tb 12 \
  --mlock --no-mmap \
  -c 8192 -b 2048 -ub 512 \
  --cache-type-k q4_0 --cache-type-v q4_0 \
  --fit on \
  --port 8081 --host 127.0.0.1
```

OpenAI-compatible endpoint:

```text
http://127.0.0.1:8081/v1
```

API key can be any placeholder value, for example `dummy`.

## Launcher Features

- Lists every `.gguf` model under `~/models`, including models in separate folders.
- Saves settings in `~/.config/llama-launcher/settings.conf`.
- Starts `llama-server` in the background and records its PID.
- Avoids killing unrelated `llama-server` processes from other apps.
- Shows health, memory, uptime, and loaded model when available.
- Offers model eject through the server unload endpoint, with stop fallback.
- Supports advanced flags including context, batch, threads, KV cache type, RoPE settings, MoE CPU options, prompt cache RAM, cache reuse, custom Jinja chat template, and fit target.

## Performance Notes

Measured on the target Mac Pro profile:

| Model | Generation | Prompt | Output |
|---|---:|---:|---|
| Dense 27B Q6_K | about 1.9 tok/s | about 3.2 tok/s | clean |
| Qwopus3.6 35B A3B Q8_0 | about 8.6 tok/s | about 20.8 tok/s | bad conversion output in testing |

Model quality and GGUF conversion correctness matter. Runtime flags cannot fix corrupted or badly converted weights.

## GPU / Experimental Backends

This package intentionally ships the stable CPU/Accelerate build. Current practical notes:

- `vLLM` is strongest on Linux GPU servers. Its macOS GPU path is aimed at Apple Silicon through vLLM-Metal/MLX, not Intel Mac Pro FirePro GPUs.
- `llama.cpp` Metal can work on some Intel Mac AMD systems, but this target build and OCLP setup reported no usable GPU during testing.
- Vulkan/ROCm paths are worth testing on Linux or newer AMD hardware. They are not the default here because the goal is a portable package that works on the matching Intel Mac without extra driver work.

If you want to experiment, keep this CPU build as the stable baseline and create a separate `LLAMA_DIR` build with Metal or Vulkan so the launcher can switch via:

```bash
LLAMA_DIR=/path/to/experimental/llama.cpp/build intellama
```

**Probe the GPU (v1.2.1):** the launcher ships an opt-in companion
`releases/llama-cpp-macpro-metal.tar.gz` (Metal-enabled, otherwise
identical to the default AVX build). The `g` menu option probes this
companion binary with `-ngl 99` and reports whether the D700s compute
path is functional under your current OCLP nightly. Read-only with
respect to the running server and your saved config — safe to run at
any time.

## Rebuild Release Archives

From this repo on the optimized Mac:

```bash
npm run pack:release
```

This rebuilds:

```text
vendor/llama-cpp-macpro.tar.gz
releases/llama-cpp-macpro-optimized.tar.gz
releases/llama-cpp-macpro-optimized.zip
```

To additionally build the Metal companion archive for the GPU probe:

```bash
npm run pack:release -- --with-metal
```

…which adds `releases/llama-cpp-macpro-metal.tar.gz`.

## Development

```bash
npm test
npm pack
```

Local run without global install:

```bash
node bin/intellama.js
```

- MLC-LLM toolchain: see [`docs/gpu-mlc-setup.md`](docs/gpu-mlc-setup.md)
  and run `scripts/setup-mlc.sh` to install.

## Renamed from `llama-cli`

This project was previously published as `llama-cli`. The `llama-cli` npm
command still works as an alias to `intellama` for backwards compatibility.
The on-disk launcher (`llama-launcher.sh`) and config dir
(`~/.config/llama-launcher/`) keep their original names.

## License

MIT. The bundled `llama.cpp` binaries are built from `llama.cpp`; see the upstream project license for its components.
