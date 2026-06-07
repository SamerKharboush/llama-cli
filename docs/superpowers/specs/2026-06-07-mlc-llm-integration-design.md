# intellama + MLC-LLM Integration — Decomposition Index

**Status:** Decomposition index (replaces the monolithic Draft v1)
**Date:** 2026-06-07
**Target release:** intellama v1.3.0 (post-validation)
**Hardware context:** 2013 Mac Pro · 2× AMD FirePro D700 (GCN 1.0, 6 GB VRAM each) · Intel Xeon E5 Ivy Bridge · macOS Sequoia via OCLP · no Xcode
**Source plan:** `/Users/macpro/mlc-llm-adoption-plan.md`

This document is the **decomposition index**. Each sub-project has its own
spec → plan → impl cycle, owned by its own brainstorm session. Do not
implement Phase 0 + Phase 1 + ... in a single plan; the source plan spans
multiple independent subsystems and was decomposed on 2026-06-07.

---

## Goal & Non-Goals (overall)

**Goal.** Validate whether MLC-LLM can drive the 2× D700 GPUs via
Vulkan/MoltenVK on this Mac Pro. If validation succeeds, integrate MLC-LLM
as a first-class backend in intellama with auto-detect and graceful
fallback to the existing llama.cpp CPU path. If validation fails, ship CPU
improvements and file a llama.cpp PR with the Vulkan-vs-Metal benchmarks
as evidence.

**Non-goals.**
- Replacing llama.cpp — it remains the default and fallback backend.
- Supporting non-Intel Macs or non-macOS platforms.
- Writing a generic multi-backend framework for backends that don't exist
  yet (YAGNI).
- Tokenizer or chat template work — the server handles all of that.
- Touching the intellama → Ollama / OpenAI-remote integrations.

**Hard stop conditions.** If the Vulkan experiment (Phase 2) fails after
the Metal fallback (Phase 3) is attempted, **no Phase 4** — we ship CPU
polish and file the llama.cpp PR instead. The stop conditions are
respectable failure points, not nice-to-haves.

---

## Sub-Project Decomposition

| # | Sub-project | Spec | Owns |
|---|-------------|------|------|
| 1 | **Phase 0 — Prerequisites** | `2026-06-07-mlc-llm-phase0-prereqs-design.md` | `scripts/setup-mlc.sh`, `docs/gpu-mlc-setup.md`, project venv at `~/.config/intellama/venv` |
| 2 | **Phase 1 — CPU validation** | (TBD) | CPU smoke test (`mlc_llm chat/bench --device cpu`), `docs/mlc-bench-cpu.txt` |
| 3 | **Phase 2 — Vulkan/MoltenVK experiment** | (TBD) | GPU smoke test on D700s, `docs/mlc-bench-vulkan{0,1,0-1}.txt`, gating decision |
| 4 | **Phase 3 — Metal fallback (only if Phase 2 fails)** | (TBD) | Xcode CLT install, Metal compile, `docs/mlc-bench-metal.txt` |
| 5 | **Phase 4 — intellama integration** | (TBD) | Resolves zsh-vs-Node adapter question, settings, menu option, backend abstraction |
| 6 | **Phase 5 — Dual-GPU tensor parallelism** | (TBD) | `--tensor-parallel-shards 2`, dual-GPU bench, integration with Phase 4 |

Each sub-project is fully self-contained: spec → plan → impl → verify
→ commit → tag → ship. Sub-projects 1, 2, 3 execute serially. Sub-project
4 (Metal) only runs if sub-project 3 (Vulkan) fails. Sub-projects 5 and 6
only run if sub-projects 2 + 3 produce a coherent GPU path.

---

## Open Questions (to resolve inside the relevant sub-project)

- **Adapter language: zsh vs Node.js.** The source plan proposes
  `src/backends/mlc.js` (Node.js). intellama is a zsh launcher. The right
  layer is **decided inside sub-project 5 (Phase 4 integration)**, not
  in this index. Do not pre-decide.

- **`package.json` `files` allowlist.** The current allowlist includes
  `scripts/`, so anything we add under `scripts/` ships to the npm
  tarball. Sub-projects that add helper scripts must verify allowlist
  behavior at plan time.

---

## Success Criteria (rolled up from each sub-project)

- **Sub-project 1:** `scripts/setup-mlc.sh` brings the box to a state
  where `vulkaninfo --summary` shows ≥2 AMD devices and `mlc_llm --help`
  runs in the project venv.
- **Sub-project 2:** `mlc_llm bench` on the 0.5B model produces ≥10 tok/s
  on CPU. `docs/mlc-bench-cpu.txt` committed.
- **Sub-project 3:** `mlc_llm chat` on the 0.5B model via `--device
  vulkan:0` produces a coherent "Paris" answer on this hardware.
  `docs/mlc-bench-vulkan{0,1,0-1}.txt` committed.
- **Sub-project 4 (conditional):** Metal compile succeeds and produces
  a coherent "Paris" answer. `docs/mlc-bench-metal.txt` committed.
- **Sub-project 5 (conditional on GPU success):** intellama menu option
  `M` configures the MLC port; the launcher auto-detects MLC at startup
  and uses it when present; llama.cpp remains the fall-through path when
  MLC is not configured.
- **Sub-project 6 (conditional on dual-GPU success):** dual-GPU tensor
  parallel serve runs; bench vs single-GPU committed; README documents
  the dual-GPU path.

**Failure rollup.** If sub-projects 3 and 4 both fail, sub-projects 5
and 6 do not run. We ship the CPU polish + llama.cpp PR instead.

---

## Risks (cross-cutting)

1. **MoltenVK on D700 may not compute at all.** GCN 1.0 + Metal 2 only
   + OCLP is a fragile stack. Sub-project 3's 0.5B smoke test is the
   canary.
2. **Vulkan memory model + 6 GB VRAM cap.** A 35B q4f16 is ~17–20 GB;
   only the MoE 35B-A3B (~9–11 GB q4f16) fits in 12 GB combined. Single-
   GPU Vulkan would require a smaller quant or offloading. Dual-GPU
   tensor parallel is the realistic path for 35B.
3. **OCLP nightly regressions.** OCLP changes can break Metal compute
   overnight. Pin the OCLP version in the README when MLC integration
   lands.
4. **No Xcode = no Metal compile path.** We cannot use MLC's
   `--device metal` until Xcode CLT is installed (~1.5 GB). Sub-project
   4 assumes Vulkan is the path; Metal is a fallback if and only if
   sub-project 3 fails.
5. **Supply-chain surface.** `pip install --pre -U mlc-ai-nightly
   mlc-llm-nightly -f https://mlc.ai/wheels` pulls from a non-canonical
   PyPI index. Sub-project 1's spec records the index URL; users are
   on the hook for reviewing what they install.
