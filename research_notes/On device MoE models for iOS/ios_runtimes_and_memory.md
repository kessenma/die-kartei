# iOS / Apple-silicon runtimes and memory for MoE LLMs on iPhone and iPad (state as of 2026-10-01)

Scope: which engines can run Mixture-of-Experts models on iOS today, whether any stream experts from flash, and what iOS memory accounting means for a model bigger than the app's RAM budget. User context: the app ships mlx-swift-lm 3.31.x and mlx-swift 0.31.x with a fine-tuned Gemma 4 E4B (MLX 4-bit, ~2.7 GB on disk, ~4.2 GB weights resident, ~4.3 GB peak) on iPhone 17 Pro (12 GB) and an 8 GB iPad, with the increased-memory-limit entitlement already in place.

Dating: most sources are GitHub issues, PRs and READMEs from March to September 2026. Older material is marked as such.

---

## 1. MLX Swift / mlx-swift-lm: which MoE architectures, any expert offload or mmap, and the Python mlx-lm quantization tools

### Takeaway
Upstream mlx-swift-lm (newest **3.32.3**, 2026-09-30) ships Swift ports of almost every relevant MoE family: Qwen3-MoE, Qwen3.5-MoE, Qwen3-Next, gpt-oss, OLMoE, GraniteMoeHybrid, LFM2-MoE, Mixtral, PhiMoE, DeepSeek-V2/V3, ERNIE 4.5, GLM4-MoE, Gemma 4 with its MoE block, and others. It loads every expert into memory, though. Neither upstream MLX nor mlx-swift-lm has an mmap, lazy-weight or expert-offload mode. The MLX maintainers declined an mmap PR in August 2026, and an mlx-lm expert-offload PR was closed unreviewed. The only working MLX-Swift expert streaming is in third-party forks (SharpAI/SwiftLM's `--stream-experts`), and those are tested on Macs.

### Cited Findings
**Versions**
- mlx-swift-lm releases: **3.32.3 (2026-09-30)**, 3.31.4 (2026-06-30), 3.31.3 (2026-04-15). mlx-swift **0.32.3** (2026-09-30), core MLX **v0.32.3** (2026-09-29) — [mlx-swift-lm releases](https://github.com/ml-explore/mlx-swift-lm/releases), [mlx-swift releases](https://github.com/ml-explore/mlx-swift/releases), [mlx releases](https://github.com/ml-explore/mlx/releases)
- 3.32.3 notes: "pick up mlx-swift 0.32.3", "massive improves in draft models, KVCache handling, tool handling", "**add MLXFoundationModels** and MLXGuidedGeneration". 3.31.4 warned that a newer mlx-swift "will require a newer swift-tools-version (newer Xcode)" — [mlx-swift-lm releases](https://github.com/ml-explore/mlx-swift-lm/releases)

**Model files in `Libraries/MLXLLM/Models` (main, 2026-10-01)**
- MoE or hybrid-MoE files present: `AfMoE`, `BailingMoe`, `DeepseekV2` (covers DeepSeek-V2-Lite), `DeepseekV3`, `Ernie4_5`, `GLM4MOE`, `GLM4MOELite`, `GPTOSS`, `GraniteMoeHybrid` (granite-4.0-h), `Hunyuan`, `Jamba`, `LFM2MoE`, `MiniMax`, `MiMoV2Flash`, `Mixtral`, `NemotronH`, `OlmoE`, `PhiMoE`, `Qwen3MoE`, `Qwen35MoE`, `Qwen3Next`, plus `Gemma4Text`. **No SmallThinker file** — [mlx-swift-lm Models dir](https://github.com/ml-explore/mlx-swift-lm/tree/main/Libraries/MLXLLM/Models)
- `Gemma4Text.swift` decodes `enable_moe_block`, `num_experts`, `top_k_experts` and `moe_intermediate_size`, and has a `Gemma4TextRouter` with `per_expert_scale`, "ported from MLXVLM/Models/Gemma4.swift (ml-explore PRs #180, #228)" — [Gemma4Text.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/Models/Gemma4Text.swift)
- The Swift MLX stack runs `gemma-4-26b-a4b-it-4bit` (15.3 GB), `Qwen3.6-35B-A3B-UD-MLX-4bit` (21.6 GB) and others through SharpAI's mlx-swift-lm fork, measured on Macs — [SharpAI/SwiftLM README](https://github.com/SharpAI/SwiftLM)
- Open or recent MoE work upstream: NemotronH "make MoE config keys optional" (PR #635, open); "Allow downstream specialization of the Qwen3.5 GDN/MoE blocks and SwitchGLU" (#511, merged 2026-08-04); "ParoQuant: extend to MoE…" (#471, merged 2026-07-25) — [#635](https://github.com/ml-explore/mlx-swift-lm/pull/635), [#511](https://github.com/ml-explore/mlx-swift-lm/pull/511), [#471](https://github.com/ml-explore/mlx-swift-lm/pull/471)
- Issue #466 (closed 2026-07-25) listed measured MoE perf wins on Qwen3.5/3.6 35B-A3B (M3 Max): compiled decode +7.5% MoE decode, a fused router top-k Metal kernel +1.9% ("today every decode token fully sorts all 256 expert scores to pick 8"), and PARO prepared checkpoints taking 35B load time "from 41 s down to 9 s" — [mlx-swift-lm #466](https://github.com/ml-explore/mlx-swift-lm/issues/466)
- PR #632 (open, 2026-09-20) loads only the shard the safetensors index maps a key prefix to. For Qwen3.5-27B's MTP head it cut bytes read from 15.1 GB to 0.85 GB. This is a load-path fix, not streaming — [mlx-swift-lm #632](https://github.com/ml-explore/mlx-swift-lm/pull/632)
- mlx-swift-lm has `WiredMemoryPolicies.swift` (e.g. `WiredSumPolicy`), which clamps the wired limit to `GPU.maxRecommendedWorkingSetBytes()` — [WiredMemoryPolicies.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLMCommon/WiredMemoryPolicies.swift)

**mmap / lazy loading / offload in MLX: the state of play**
- **mlx #2878** "On-disk (out-of-core) streaming of model weights for low-RAM inference": **open** since 2025-12-06 — [mlx #2878](https://github.com/ml-explore/mlx/issues/2878)
- **mlx #3371** "Add streaming weight loader and layer-streaming inference" was closed the same day (2026-04-04) by maintainer angeloskath: "Nothing here memory maps anything, evaluating per-shard requires exactly the same memory as evaluating the whole model" — [mlx #3371](https://github.com/ml-explore/mlx/pull/3371)
- **mlx #4249** "Add mmap_weights: zero-copy file-backed weight arrays" (2026-08-14) was **closed, not merged**. Maintainer zcbenz: "At the moment we are not considering using mmap, see …discussions/615" — [mlx #4249](https://github.com/ml-explore/mlx/pull/4249)
- #4249's measured findings (M5 Max 128 GB, macOS):
  - Mapped views ran gemma-4-26B at 132 tok/s, the same as resident and bit-identical; the bf16 53 GB checkpoint ran at 101% of resident decode.
  - "**Whole-buffer wiring.** Metal wires the entire bytesNoCopy buffer on first kernel use, not touched pages: a one-expert `gather_qmm` (3 MB logical) faults its full 1.2 GB stacked tensor. Page-granular laziness does not exist — the unit of residency is the buffer."
  - "**The wired ceiling applies to mapped buffers.** A model whose touched buffers exceed `max_recommended_working_set_size` fails with a hard kIOGPUCommandBufferCallbackError…"
  - Source: [mlx #4249](https://github.com/ml-explore/mlx/pull/4249)
- The same author on #2878: "transparent bigger-than-RAM streaming is impossible on Metal — measured". A 217 GB model died with kIOGPUCommandBufferCallbackErrorOutOfMemory at ~112 GB touched on a 128 GB machine — [mlx #2878 comment](https://github.com/ml-explore/mlx/issues/2878)
- Related zero-copy primitives that were merged: "Metal DLPack zero-copy sharing" (#3531, merged 2026-05-11) and "Zero-copy CPU import: mx.array(host_buffer, copy=False) on unified memory" (#3872, merged 2026-07-19). "save_safetensors: pad the header so the data section can be memory-mapped" (#4439) was closed — [mlx #3531](https://github.com/ml-explore/mlx/pull/3531), [mlx #3872](https://github.com/ml-explore/mlx/pull/3872), [mlx #4439](https://github.com/ml-explore/mlx/issues/4439)
- Bug to know about if you slice expert tables yourself: "gather_qmm with sorted_indices=True silently returns wrong results for a row-sliced quantized weight" (#4055, closed 2026-08-07) — [mlx #4055](https://github.com/ml-explore/mlx/issues/4055)
- **mlx-lm #1588** "Add opt-in disk-backed expert offloading to SwitchLinear/QuantizedSwitchLinear" (2026-07-19) was closed 2026-08-21 without review: "the number of PRs is way beyond our capacity to review" — [mlx-lm #1588](https://github.com/ml-explore/mlx-lm/pull/1588)
- #1588's results:
  - Qwen3.6-35B-A3B-8bit (35 GB) ran on a 32 GB Mac at a 12.7 GB resident peak with `load(lazy=True)` plus offload at fraction 0.3.
  - On a model that already fits, offload at 0.3 was "about 5x slower decode and 8 to 12x slower prefill."
  - Implementation traps: MLX arrays are thread-affine, so build the `mx.array` on the model thread. "A prefix slice of an `mx.array` is a view that pins the whole parent buffer."
  - Source: [mlx-lm #1588](https://github.com/ml-explore/mlx-lm/pull/1588)
- **mlx-lm #1438**, a feature request for MoE expert streaming / SSD offload, is still open. Its comments include an Apple-side sweep (GLM-5.2 on an M5 Max 128 GB): with a 10 GB materialized expert cache, decode was 0.40 t/s, beating a 60 GB cache (0.34 t/s). "The OS page cache, given room, outruns a materialized cache large enough to starve it" — [mlx-lm #1438](https://github.com/ml-explore/mlx-lm/issues/1438)
- **Third-party MLX-Swift streaming: SharpAI/SwiftLM** `--stream-experts`
  - Base Mac mini M6 32 GB, Qwen3.6-35B-A3B 4-bit: 48.4 tok/s fully on the GPU at a 20.2 GB peak, versus **14.1 tok/s at a 5.7 GB peak** with `--stream-experts`.
  - Gemma-4-26B-A4B 8-bit: 9.7 tok/s at 7.1 GB.
  - Design: "concurrent NVMe pread (QD=24)", "speculative pread" using previous-token routing (~70% hit), and "Don't cache experts in application memory — an LRU expert cache *stole* from the OS page cache and regressed performance (4.84 → 4.01 tok/s)."
  - Source: [SharpAI/SwiftLM](https://github.com/SharpAI/SwiftLM)
- The SwiftLM streaming path lives in a fork (SharpAI/mlx-swift-lm) and broke on an upstream sync: "`--stream-experts` crashes on quantized MoE models in releases b769 and b773", fixed by fork PRs #69 and #71 (2026-09-25) — [SwiftLM README](https://github.com/SharpAI/SwiftLM), [SharpAI/mlx-swift-lm #69](https://github.com/SharpAI/mlx-swift-lm/pull/69), [#71](https://github.com/SharpAI/mlx-swift-lm/pull/71)
- SwiftLM has an iOS companion app, SwiftBuddy, "Running live on iPhone 13 Pro (6 GB)" with MLX Swift. The README gives iPhone numbers only for ordinary resident models and **does not claim `--stream-experts` on iOS** — [SwiftLM README](https://github.com/SharpAI/SwiftLM)

**Quantization flexibility (Python mlx-lm convert, read by mlx-swift-lm)**
- `mlx_lm.convert` supports `--q-mode` choices `affine`, `mxfp4`, `nvfp4`, `mxfp8`. `--quant-predicate` recipes are `mixed_2_6`, `mixed_3_4`, `mixed_3_6`, `mixed_4_6` ("similar choices to … llama.cpp's Q4_K_M"), and "Quant predicates only support 'affine' quantization." A custom Python `quant_predicate` callable can set per-module bits and group size — [mlx-lm convert.py](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/convert.py)
- Learned quantization in mlx-lm: DWQ (`mlx_lm.dwq`, "works best distilling to lower precision, anywhere from 2-bit to 4-bit"), AWQ, dynamic quantization ("estimates the sensitivity … uses a higher precision for layers which have higher sensitivity") and GPTQ. They can be cascaded — [LEARNED_QUANTS.md](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/LEARNED_QUANTS.md)
- mlx-swift-lm's `BaseConfiguration` reads per-layer overrides (`PerLayerQuantization`, `QuantizationOption.skip / .quantize(…)`) and a `mode` field from config.json, i.e. "Mixed-Precision" or "Heterogeneous" quantization — [BaseConfiguration.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLMCommon/BaseConfiguration.swift)
- An example in the wild: `granite-4.0-h-tiny-MLX-4bit` is "4-bit affine, group_size 64, MoE router layers 8-bit (from config.json)" — [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)
- ParoQuant (pairwise rotation quantization) is in mlx-swift-lm (#164) and was extended to MoE (#471) — [mlx-swift-lm releases](https://github.com/ml-explore/mlx-swift-lm/releases), [#471](https://github.com/ml-explore/mlx-swift-lm/pull/471)

### Inferences
- For the user, MLX keeps the property that protected their fine-tune: per-tensor and per-module precision control (keep Gemma 4 per-layer embeddings, routers and LM head at 8-bit or bf16), plus DWQ to recover quality. Of the engines reviewed, it is still the most flexible quantizer an iOS app can consume directly.
- Upstream MLX copies safetensors into MLX-owned buffers, so all weights count toward phys_footprint. That matches the user's 4.2 GB resident E4B, and MLX-Swift's 3,010 MB footprint for Gemma 4 E2B in the bench (section 4). Any MoE run on upstream mlx-swift-lm must therefore fit entirely inside the jetsam budget and the Metal working set.
- Stacked `SwitchLinear` / `QuantizedSwitchLinear` expert tensors share one quantization per module, so precision can vary per projection but not per expert. Per-expert precision needs a custom engine; Flash-MoE uses per-layer 2-bit flags (section 3).
- Even with an mmap PR, MLX's stacked-expert layout plus Metal's whole-buffer wiring would fault the whole expert table for a layer on first use. Real streaming on MLX needs explicit per-expert pread into small slot buffers (SwiftLM, mlx-lm #1588), not mmap.

### Gaps
- No upstream issue or PR in mlx-swift-lm or mlx-swift proposes expert offloading for iOS. The SwiftLM fork's streaming has no published iPhone measurements.
- Discussion #615 (the past mmap experiments zcbenz cited) was not read in detail.
- Whether mlx-swift exposes the Python zero-copy import (#3872) is unverified.

---

## 2. llama.cpp on iOS: MoE support, mmap vs jetsam footprint, expert-on-CPU flags, Metal, Swift packaging

### Takeaway
llama.cpp maps GGUF files `MAP_SHARED`, and on iPhone those clean, file-backed pages are **not charged to `phys_footprint`**. Measured on an iPhone 17 Pro: llama.cpp ran Gemma 4 E2B at a **191 MB** footprint while 2.9 GB of mmap'd GGUF was resident. That avoids jetsam kills, but GPU-bound weights still have to fit under Metal's `recommendedMaxWorkingSetSize`, which is 8 GB on a 12 GB iPhone Air, and a 7.3 GB 13B model failed to load there. Upstream llama.cpp supports MoE (`--cpu-moe`, `--n-cpu-moe`, `-ot`) and ships an official xcframework. Real flash streaming of experts exists only in the Anemll fork, which has been tested on Macs.

### Cited Findings
- llama.cpp `src/llama-mmap.cpp` maps with `int flags = MAP_SHARED;` and applies `posix_madvise` `POSIX_MADV_WILLNEED` / `POSIX_MADV_RANDOM` hints, plus a `llama_prefetch` using `MADV_WILLNEED` — [llama-mmap.cpp](https://github.com/ggml-org/llama.cpp/blob/master/src/llama-mmap.cpp)
- MoE placement flags in `common/arg.cpp`: `-ot, --override-tensor <tensor name pattern>=<buffer type>`, `-cmoe, --cpu-moe`, `-ncmoe, --n-cpu-moe N` — [llama.cpp arg.cpp](https://github.com/ggml-org/llama.cpp/blob/master/common/arg.cpp)
- `llama-quantize` supports per-tensor precision: `--tensor-type tensor_name=ggml_type` ("example: --tensor-type attn_q=q8_0"), `--tensor-type-file`, `--output-tensor-type`, `--token-embedding-type`, `--imatrix`, `--prune-layers` — [quantize.cpp](https://github.com/ggml-org/llama.cpp/blob/master/tools/quantize/quantize.cpp)
- Packaging: the newest release, b11324 (2026-10-01), ships `llama-b11324-xcframework.zip` — [llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases)
- **iPhone 17 Pro measurement** (apple-silicon-llm-bench, Gemma 4 E2B, warm protocol, memory = "jetsam-charged `phys_footprint`"):

  | Runtime | Decode | Footprint | GSM8K |
  |---|---|---|---|
  | llama.cpp Q4_K_M | 38.8 tok/s | **191 MB** | 76% |
  | MLX-Swift PTQ 4-bit | 49.1 tok/s | **3,010 MB** | 84% |
  | MLX-Swift QAT OptiQ int4 | 36.0 tok/s | 4,592 MB | 91% |
  | LiteRT-LM wNa8o8 QAT | 61.1 tok/s | 497 MB | 86% |

  The bench's note: "**mmap'd weights: clean pages aren't charged to `phys_footprint`** … llama.cpp's 191 MB hides 2.9 GB of mmap'd GGUF that shows up in residency (3.1 GB)." llama.cpp with the "official QAT q4_0" Gemma build was "**unloadable**" — [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)
- Same bench, energy: llama.cpp "pulls ~2× any other arm's average power (9.8 W), hits the thermal ceiling hardest, and keeps the least of its burst rate under sustained load (54%)" on iPhone 17 Pro — [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)
- **Metal working-set ceiling on iPhone**: an iPhone Air (12 GB) reports `recommendedMaxWorkingSetSize` = **8,192 MB**. Llama-2-13B Q4_K (~7.32 GB weights) "failed to load" with llama.cpp Metal, while 7B/8B Q4_K load and decode at ~9 tok/s. The poster asked for the iPhone 17 Pro value and whether the limit is enforced; the thread is unanswered (Oct 2025) — [Apple Developer Forums 805161](https://developer.apple.com/forums/thread/805161)
- macOS evidence on how Metal treats mapped weights (geistlib #541, 2026-10-01): when a command buffer makes a `newBufferWithBytesNoCopy` wrapper resident, "Metal wires its pages." With `MAP_PRIVATE` that is copy-on-write, so "every page of every GPU-bound weight becomes a private anonymous copy" (2,918 MiB copied for gemma4-e2b Q4_K_M), and "none of this shows in the process's `phys_footprint` or RSS." With `MAP_SHARED`, "Metal then wires the file's own page-cache pages: no copy… llama.cpp maps its models `MAP_SHARED` too" — [geistlib #541](https://github.com/geisten/geistlib/issues/541)
- A search-result summary (not verified in llama.cpp source) said llama.cpp "hands Metal the entire mmap'd region of any shard containing GPU tensors", so interleaved data gets wired too, and an over-large model can die with `kIOGPUCommandBufferCallbackErrorOutOfMemory` — [search result pointing at geistlib/llama.cpp discussion](https://github.com/geisten/geistlib/issues/541) *(treat as unverified)*
- **Anemll/anemll-flash-llama.cpp** (MIT, last push 2026-09-04) is a llama.cpp fork adding "sidecar-backed routed expert loading, streamed slot-bank execution":
  - `--moe-mode stock|resident|resident-bank|slot-bank|…`, `--moe-slot-bank N`, `--moe-prefetch-temporal`. Routed experts are extracted to per-layer sidecar files "streamed from SSD on demand via `pread()`".
  - Stable models: Qwen3.5-35B-A3B, Qwen3.5-397B-A17B, **Gemma4-26B-A4B**. Experimental: Kimi K2/K2.5, MiniMax-M2.7, GLM-5.1/5.2, DeepSeek V4, HY V3, Qwen3.8-2.4T.
  - Rule of thumb: "bank should be 5-15% of available RAM". Hardware table covers Macs only (M1/M2 8 GB: `--moe-slot-bank 16 -ngl 0`).
  - Source: [anemll-flash-llama.cpp](https://github.com/Anemll/anemll-flash-llama.cpp)
- No llama.cpp iOS-specific jetsam or mmap issues turned up through GitHub search. The A-series perf discussion exists but no A19 Pro MoE numbers were gathered from it — [llama.cpp discussion #4508](https://github.com/ggml-org/llama.cpp/discussions/4508)

### Inferences
- On iOS, llama.cpp's memory profile is the opposite of MLX's. Weights sit in the page cache (reclaimable, not jetsam-charged) instead of anonymous or wired app memory. A model can then show a tiny footprint, and under pressure the kernel evicts weight pages and re-reads them from flash rather than killing the app. That is the "Trust the OS" mechanism the MoE streamers rely on (section 3).
- The binding constraint on llama.cpp Metal for iPhone is the GPU working set (~8 GB on 12 GB phones per the forum post), not jetsam. A resident MoE whose GPU tensors exceed ~8 GB (gpt-oss-20b MXFP4 ≈ 12–13 GB, Qwen3-30B-A3B Q4 ≈ 17–19 GB, Gemma 4 26B-A4B Q4 ≈ 15 GB) will not load fully on the GPU.
- `--n-cpu-moe` / `-ot exps=CPU` would keep experts on the CPU path. On iOS those would be clean mmap pages that the CPU reads through the page cache, not GPU-wired. In principle that allows a larger-than-budget MoE with CPU expert math. Expect it to be slow and thermally poor: SwiftLM measured CPU-resident MoE layers at ~3 s per token on Macs (section 3), and llama.cpp already has the worst sustained-throttle profile on the iPhone. Untested on iPhone.
- For the user's fine-tune, `llama-quantize --tensor-type` can keep specific tensors (such as Gemma 4 per-layer embeddings) at q8_0 or f16, so llama.cpp has enough per-tensor flexibility to avoid the PLE damage seen with Cactus and LiteRT-LM. Verify the GGUF tensor names for Gemma 4 PLE before relying on this. The bench's Gemma 4 E2B Q4_K_M PTQ scored 76% GSM8K against 84–91% for MLX builds, so the stock recipe is not good enough.

### Gaps
- No Apple documentation was found that states how Metal-wired, file-backed (`MAP_SHARED` + `bytesNoCopy`) pages are charged on **iOS** specifically. The 191 MB llama.cpp footprint on iPhone 17 Pro is strong empirical evidence that they are not charged to `phys_footprint`, but whether the working-set limit counts them on iOS is shown only indirectly (the iPhone Air 13B load failure).
- No measured llama.cpp MoE tok/s on A19 Pro or M-series iPads (e.g. LFM2-8B-A1B, Granite-4.0-H-Tiny, OLMoE) was found.
- Swift wrappers other than the official xcframework (llama.rn, LocalLLMClient and the like) were not surveyed.

---

## 3. Other engines and MoE-specific runtimes (ExecuTorch, Core ML / Core AI, Foundation Models / AFM 3, MLC-LLM, Cactus, LiteRT-LM, Flash-MoE, Swiftlet)

### Takeaway
The only engines with **demonstrated flash-streamed MoE on an iPhone** are two small purpose-built Swift/C + Metal runtimes:
- **Anemll Flash-MoE**: Qwen3.5-35B-A3B at ~5.5 tok/s on an iPhone 17, and a 397B at 0.6 tok/s on a 17 Pro.
- **Swiftlet**: Qwen3.6-35B-A3B at ~1 tok/s in ~2.5 GB on an iPhone 17, shipping inside the Priv AI app.

Both run only Qwen-family checkpoints in custom repacked formats.

Apple's iOS 27 stack now does three relevant things:
- It ships its own 20B sparse on-device model (AFM 3 Core Advanced) that keeps weights in NAND and routes **per prompt**. Apple's stated reason is that per-token expert swapping is too slow over NAND.
- It replaces Core ML with **Core AI**.
- It opens Foundation Models to third-party models through a `LanguageModel` protocol, which mlx-swift-lm 3.32.3 already bridges.

ExecuTorch, LiteRT-LM and Cactus have no iPhone MoE demonstration in what was found.

### Cited Findings
**Anemll Flash-MoE (C / Obj-C / Metal; iOS app on branch `iOS-App`)**
- Desktop engine: Qwen3.5-397B-A17B streams from SSD, with "parallel `pread()`… The OS page cache manages caching — no custom expert cache needed ('Trust the OS')… ~71% hit rate". Measured 17.5 GB/s sequential read on an M3 Max MacBook Pro 1 TB — [Anemll/flash-moe (iOS-App README)](https://github.com/Anemll/flash-moe/tree/iOS-App), [danveloper/flash-moe (original)](https://github.com/danveloper/flash-moe)
- iOS port review, March 2026:
  - "**5.5 tok/s on iPhone 17 with Qwen3.5-35B-A3B**". The comparison table lists the iPhone 17 (A19) with 8 GB memory and SSD bandwidth "~3-4 GB/s (est.)".
  - Reasoning given: expert reads of ~2.24 GB/token at ~3 GB/s would give ~1.3 tok/s if purely I/O-bound, so "the OS page cache is hitting ~75%+ of expert reads."
  - Context is sized adaptively from `os_proc_available_memory()`. The doc calls ~6 GB "the app limit" on that phone.
  - Source: [FlashMoE-iOS/REVIEW.md](https://github.com/Anemll/flash-moe/blob/iOS-App/FlashMoE-iOS/REVIEW.md)
- Port notes: "iPhones have ~6GB of usable app memory". The KV cache had to be capped (a 128k context would need 2.5 GB). Debug builds roughly double GPU memory through Metal validation wrappers — [FlashMoE-iOS/IOS_PORT.md](https://github.com/Anemll/flash-moe/blob/iOS-App/FlashMoE-iOS/IOS_PORT.md)
- 397B on iPhone 17 Pro: **0.6 tok/s**, ~200 GB on flash, demoed by @anemll around 2026-03-23. The iOS changelog adds 2-bit experts for it — [dev.to write-up](https://dev.to/max_quimby/iphone-17-pro-just-ran-a-400b-llm-on-device-ai-changes-everything-2026-53bm), [HN thread](https://news.ycombinator.com/item?id=47490594), [CHANGELOG-ios-port.md](https://github.com/Anemll/flash-moe/blob/iOS-App/FlashMoE-iOS/CHANGELOG-ios-port.md)
- Quality notes from the desktop engine: 2-bit experts give PPL 5.71 vs 3.64 for 4-bit and "breaks JSON/tool calling". Unsloth Q3 experts give PPL 3.81 at 36% faster decode — [Anemll/flash-moe](https://github.com/Anemll/flash-moe/tree/iOS-App)

**Swiftlet (Swift + Metal, Apache-2.0, created 2026-08-28)**
- Qwen3-Next and Qwen3.5/3.6 MoE only:
  - Qwen3.6-35B-A3B 4-bit: 18 GB disk, **2.6 GB peak RAM**, 7–11 tok/s on an M5 Mac.
  - 8-bit: 34 GB disk, 7.6 GB RAM.
  - Qwen3-Next-80B-A3B 4-bit: 42 GB disk, 4.3 GB RAM.
  - "The 35B also runs on an **iPhone 17 in about 2.5 GB of RAM, at about 1 tok/s** today."
  - Source: [Swiftlet README](https://github.com/Avicennasis/Swiftlet)
- Design: dense core resident (~1.3 GB for the 35B). Experts are repacked into a `.qpack` "so fetching one expert is exactly one `pread`… **no mmap and no page-cache thrash**", with an LFU+recency bounded pool ("measured 43 to 70 percent hit rates at the same throughput"). Shaders are compiled at runtime so "the same code ships on iOS". The decode loop is "dispatch bound, not IO bound" — [Swiftlet README](https://github.com/Avicennasis/Swiftlet)
- Shipped in "**Priv AI**" on the App Store (Settings ▸ Experimental Models). The README says that version was "still in App Store review". App source: leonickson1/localLLM — [Priv AI](https://apps.apple.com/us/app/priv-ai/id6765706001), [localLLM](https://github.com/leonickson1/localLLM)

**Apple: AFM 3, the Foundation Models framework and Core AI (WWDC26, June 2026)**
- AFM 3 Core is a 3B dense model. **AFM 3 Core Advanced** is a 20B sparse model "activating just 1 to 4 billion parameters at a time", built on Instruction-Following Pruning:
  - "Instead of forcing the entire model into DRAM, the full model is stored in flash memory (NAND)."
  - "**Because NAND-to-DRAM bandwidth is too slow to swap weights token by token, as standard MoE models require, AFM 3 Core Advanced makes routing decisions per prompt.**"
  - A dense block "selects a fixed set of experts during initial processing, periodically reselecting them during generation", with many always-active shared experts.
  - Quantization-aware training is used. It is "unlocked by and optimized for our most capable Apple silicon systems". German is in the supported locales.
  - Source: [Apple ML Research — Third generation of Apple Foundation Models](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)
- WWDC26 "What's new in the Foundation Models framework":
  - On-device `SystemLanguageModel` `contextSize` is 8192. A Private Cloud Compute model offers 32K context and reasoning, free below 2M first-time downloads.
  - A new **`LanguageModel` protocol** "allows both local and server models to back a LanguageModelSession". Apple is "open sourcing… **CoreAILanguageModel and MLXLanguageModel**". The framework itself is going open source.
  - The session summary has **no mention of adapter or LoRA training** for third-party developers.
  - Source: [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- mlx-swift-lm 3.32.3 "add[s] MLXFoundationModels" — [mlx-swift-lm releases](https://github.com/ml-explore/mlx-swift-lm/releases)
- **Core AI** is the successor to Core ML (announced WWDC26). It runs CPU, GPU and Neural Engine "under one API", targets models "from compact 3B… up to 70B-parameter reasoning models" across iPhone, iPad, Mac and Vision Pro, and converts via `TorchConverter().add_exported_program(ep).to_coreai()` with quantization and palettization. No MoE or flash-streaming details were published — [InfoQ](https://www.infoq.com/news/2026/06/apple-core-ai-wwdc/)
- Core AI measurements (M4 Max, macOS 27β):
  - **gpt-oss-20b (MoE, MXFP4, 13 GB artifact)**: Core AI 78.1 tok/s vs MLX 100.2. "MLX's one clear win is the MoE."
  - `COREAI_CHUNK_THRESHOLD` "is a memory dial — unchunked 4096-token prefill… at 18 GB dirty footprint, chunk-128… caps memory at 1.7 GB".
  - On iPhone 17 Pro, Core AI has an "iOS KV cap (1,024)", and the app "is jetsammed at setup" under a 2048 budget.
  - The 0.6B artifact exported on macOS 27β was ~2× slower than the macOS-26 export ("Benchmark the artifact you ship").
  - Source: [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)

**ExecuTorch (Meta)**
- `examples/models/qwen3_5_moe` is a "self-contained ExecuTorch implementation of Qwen3.5-35B-A3B… **Supports CUDA and MLX backends**". It was tested on an A100 80 GB, uses int4 (`--qlinear 4w`, optional `--hqq` for experts), and adds TurboQuant KV. No iOS run is described. Latest release is v1.5.1 (2026-09-23) — [ExecuTorch qwen3_5_moe](https://github.com/pytorch/executorch/tree/main/examples/models/qwen3_5_moe), [ExecuTorch releases](https://github.com/pytorch/executorch/releases)
- react-native-executorch 0.10.x on iOS (MLX path), measured on a physical iPhone 17: prefill memory grew to 3.5–3.9 GiB and was jetsam-killed with `vm-pageshortage`, versus 14 MB growth on 0.9.2. Closed 2026-09-24 — [RNE #1489](https://github.com/software-mansion/react-native-executorch/issues/1489)

**LiteRT-LM (Google)**
- Has Swift APIs with Metal GPU on iOS and Gemma 4 MTP drafters (search-result summary of Google's blog; not fetched) — [Google Developers Blog](https://developers.googleblog.com/blazing-fast-on-device-genai-with-litert-lm/)
- Fastest and leanest arm on Gemma 4 E2B on iPhone 17 Pro: 61.1 tok/s at 497 MB, using Google's own wNa8o8 **QAT** `.litertlm` build. "LiteRT-LM is vendored as a local SwiftPM package… the released package trips SwiftPM's unsafe-flags rule via its `-all_load`" — [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)
- flutter_gemma (a LiteRT-LM wrapper) notes "~2 GiB single-section mmap budget on iOS" and "iPhone / 8 GB phones excluded" for some models. It has an open **proposal** (2026-09-16, unbuilt) for an out-of-core MoE runtime:
  - Targets: ≤4 GiB anonymous, ≥5 tok/s decode on flagships for Qwen3.6-35B-A3B int4 (~18 GiB checkpoint; ~1.32 GiB dense; ~1.85 GiB of weights touched per token).
  - Design: `pread` + `F_NOCACHE` by default rather than mmap, "converts storage errors to error codes rather than SIGBUS".
  - Source: [flutter_gemma #517](https://github.com/DenisovAV/flutter_gemma/issues/517), [#518](https://github.com/DenisovAV/flutter_gemma/issues/518)

**Cactus**
- The default "CQ4 as shipped" Gemma 4 E2B build scored **3.0% GSM8K** ("reasoning-dead") against 87.0% for the demoted uncalibrated build, and Cactus's mixed-precision prebuilts (cq3.26/cq2.54) "probe at 4%/16%". This independently confirms the user's experience that Cactus quantization can wreck a model — [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)
- Cactus mmaps a shared weight once per component graph. On an iPhone 13 (4 GB) gemma-4-e2b maps a 1.13 GiB PLE file three times and fails with `mmap → ENOMEM`, "a mapped-memory ceiling, not footprint/jetsam (phys_footprint at the failure is ~107 MB)" — [cactus #793](https://github.com/cactus-compute/cactus/issues/793)

**MLC-LLM**
- The repo is still active (pushed 2026-10-01), but GitHub releases show only `v0.1.dev0` (2023). No iOS MoE material was found — [mlc-ai/mlc-llm](https://github.com/mlc-ai/mlc-llm)

### Inferences
- Apple's own architecture choice is the strongest signal on per-token expert streaming. Apple has the best view of iPhone NAND, and it rejected per-token expert swapping for its 20B on-device model. Flash-streamed classic MoE on iPhone works, but expect single-digit tok/s and heavy reliance on the OS page cache.
- For a German-tutor app the two demonstrated iPhone streamers are poor fits. Both run only Qwen MoE checkpoints in custom repacked formats, neither has a fine-tune or adapter path, and 1–5.5 tok/s with long cold TTFT is far below the ~40–50 tok/s E4B-class experience.
- The new `LanguageModel` protocol plus mlx-swift-lm's MLXFoundationModels means the user could expose their MLX Gemma tutor and Apple's on-device model behind one Foundation Models session API. That is an architectural option, not a capacity gain.
- ExecuTorch and Core AI may become viable MoE paths on iOS (Core AI already runs gpt-oss-20b on a Mac with a 1.7 GB dirty footprint when prefill is chunked, which suggests it maps weights), but neither has a published iPhone MoE result. Core AI's current iOS KV cap (1,024) and the export-environment sensitivity are red flags.

### Gaps
- Whether third-party apps can call **AFM 3 Core Advanced** (versus Core) through `SystemLanguageModel`, which devices get it, and whether an adapter toolkit exists for AFM 3. Session 241's summary did not say.
- Core AI MoE support on iPhone, and how Core AI accounts mmap'd weights on iOS.
- LiteRT-LM support for Gemma 4 26B-A4B or any MoE on iOS: nothing found.
- Cactus MoE support and MLC-LLM MoE on iOS were not investigated further.
- Flash-MoE's "iPhone 17 (A19), 8 GB" 5.5 tok/s comes from the project's own review doc. It is not independently reproduced, and its SSD bandwidth figure is an estimate.

---

## 4. iOS memory rules: jetsam limits, entitlements, mmap and phys_footprint, Metal working set, no-copy buffers

### Takeaway
Jetsam kills on **`phys_footprint`** (dirty + compressed + IOKit/Metal-owned anonymous memory). **Clean file-backed (mmap'd) pages are not counted**, and the kernel evicts them under pressure instead of killing the app. Separate ceilings still apply:
- Metal's GPU working set: `recommendedMaxWorkingSetSize` = 8,192 MB on a 12 GB iPhone Air. On macOS, mapped buffers count against it.
- A per-process mapped-memory / virtual address ceiling: ~6.5 GiB on a 4 GB iPhone without entitlements, lifted by the entitlements.
- iOS 18+'s `vm-compressor-space-shortage` kill.

The increased-memory-limit entitlement roughly doubles the app's budget, to ~6 GB on 8 GB phones. A model larger than the budget can only run if its weights stay clean and file-backed: mmap'd and CPU-read, or pread into a small bounded pool. Whole-tensor GPU wiring of stacked expert tables defeats this.

### Cited Findings
- Apple's model of memory: "clean memory is data that can be paged out, which includes **memory-mapped files**" (e.g. "training models"). Dirty memory is written-to or malloc'd memory, and compressed memory is compressed dirty pages. Footprint = dirty + compressed — [WWDC18 Session 416 "iOS Memory Deep Dive"](https://developer.apple.com/videos/play/wwdc2018/416) *(2018, older but still the canonical Apple statement)*
- On iPhone, Gemma 4 2B on the RNE/MLX stack read `phys_footprint` 953.8 MB after load while `resident_size` read 3,281.7 MB. At the prefill peak, as the process was dying, footprint was 3,278.8 MB and resident 3,039.5 MB. "As dirty tensors fill memory the kernel evicts the clean file-backed pages of the mapped model, so resident *drops* while footprint climbs into the kill." "iOS kills on `phys_footprint`, and that is also what Xcode's memory gauge shows" (read via `task_info(TASK_VM_INFO).phys_footprint`) — [private-mind #388](https://github.com/software-mansion-labs/private-mind/issues/388)
- "iOS: jetsam enforces `phys_footprint` (anonymous + compressed + IOKit/Metal). Clean file-backed (mmap'd) weight pages are *not* counted." The maintainer agreed: a model whose weights are mmap'd and one that reads the same weights into anonymous memory "both show roughly the same RSS, and only the second one gets killed by jetsam" — [flutter_gemma #517](https://github.com/DenisovAV/flutter_gemma/issues/517)
- iPhone 17 Pro measurement: llama.cpp (mmap) 191 MB footprint vs 3.1 GB resident, against MLX-Swift at 3,010 MB footprint for the same Gemma 4 E2B — [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)
- **Mapped-memory ceiling**: on an iPhone 13 (4 GB), a probe measured the per-process mapped-memory ceiling at "~6.5 GiB with the entitlement off". "iOS charges each duplicate mapping." Adding `com.apple.developer.kernel.increased-memory-limit` "raises the process's mapped-memory ceiling (measured: ~6.5 GiB → >46 GiB on this device)" — [cactus #793](https://github.com/cactus-compute/cactus/issues/793)
- **Entitlements**:
  - `increased-memory-limit` (iOS 15+) "raises the resident limit and eases the jetsam threshold".
  - `extended-virtual-addressing` (iOS 14+) expands virtual address space so "multiple `mmap()` sections" don't fail on fragmentation.
  - Loading Gemma 4 E4B (3.65 GB) crashed with no entitlements but succeeded 36/36 with either one alone (peak 4,651 MB with increased-memory-limit only; 4,775 MB with extended-VA only).
  - The article calls the test phone an "iPhone 17 Pro (A19 Pro, 8GB)", which **conflicts** with the 12 GB that Xcode reports for the 17 Pro (see below). Device identity is uncertain.
  - Source: [zenn.dev, 2026-06-18](https://zenn.dev/mtfum/articles/ios_memory_entitlements?locale=en)
- A search-result snippet of that article said that on an iPhone 15 Pro Max (8 GB) under iOS 27, `os_proc_available_memory()` returns ~3.3 GB without the entitlement and ~6 GB with it, and that the limit "does not change for iPhone 11 and earlier (4 GB)". This was seen only in the snippet, not in the fetched text — [zenn.dev](https://zenn.dev/mtfum/articles/ios_memory_entitlements?locale=en)
- iPhone 17 Pro and Pro Max have 12 GB (reported via Xcode 26, up from 8 GB on the 16 Pro) — [MacRumors/TrendForce](https://www.macrumors.com/2025/09/04/iphone-17-ram-amounts-trendforce/) (search-result summary)
- **iPad**: 2021 iPadOS limited apps to ~5 GB on both 8 GB and 16 GB M1 iPad Pros (old) — [9to5Mac 2021](https://9to5mac.com/2021/05/28/ipad-pro-ram-limits/). On iPadOS 18.3/18.4 with increased-memory-limit plus extended-VA, a 16 GB iPad Pro M4 malloc test reached ~16 GB before a kill. The jetsam reason was **`vm-compressor-space-shortage`** with ~13.0 GiB charged, mostly compressed. Apple DTS: iOS 18 "introduced restrictions on total compressed page volume", and in January (iPadOS 18.0–18.1) patterned data had reached 31–32 GB because it compressed well — [Apple Developer Forums 777370](https://developer.apple.com/forums/thread/777370)
- **Metal working set**: iPhone Air 12 GB reports `recommendedMaxWorkingSetSize` 8,192 MB (~68% of RAM), and a 7.32 GB model failed to load under llama.cpp Metal — [Apple Developer Forums 805161](https://developer.apple.com/forums/thread/805161)
- **Metal and mapped files (macOS measurements)**:
  - "Metal wires the entire bytesNoCopy buffer on first kernel use" (whole-buffer residency), and "the wired ceiling applies to mapped buffers" — [mlx #4249](https://github.com/ml-explore/mlx/pull/4249)
  - With `MAP_SHARED`, "Metal… wires the file's own page-cache pages: no copy". With `MAP_PRIVATE`, wiring makes anonymous copies of every page. Neither shows in `phys_footprint` on macOS — [geistlib #541](https://github.com/geisten/geistlib/issues/541)
- Hybrid caution on iOS (RNE 0.10.x): "taking a large part of the system down with it" — the jetsam reports for the app's kills list `vm-pageshortage` and other processes (Safari, Messages, WebKit) killed in the cascade. File-backed weights do not protect against dirty-memory growth in prefill — [RNE #1489](https://github.com/software-mansion/react-native-executorch/issues/1489)
- Flash-MoE iOS review: "iOS doesn't overcommit memory the way macOS does. When `calloc` fails on iPhone (because you're close to the ~6 GB app limit), it returns NULL silently" — [FlashMoE-iOS/REVIEW.md](https://github.com/Anemll/flash-moe/blob/iOS-App/FlashMoE-iOS/REVIEW.md)

### Inferences
- **The answer to "does mmap'd, clean, file-backed memory count against the iOS jetsam footprint?" is no**, by consistent measurement: llama.cpp on iPhone 17 Pro, RNE on iPhone, and the flutter_gemma maintainers. That includes, empirically, llama.cpp's `MAP_SHARED` weights that Metal reads. What still counts: anything the runtime copies into its own buffers (upstream MLX), KV cache, activations, dirty scratch, and, for the GPU path, buffers that must fit in the Metal working set.
- Budget arithmetic for an MoE larger than the budget on the user's devices:
  - The dense core plus the KV cache must fit in the jetsam budget (~7–8 GB on the 17 Pro per the user; ~4.5–5.5 GB on the 8 GB iPad).
  - Expert bytes must stay clean (mmap/page cache) or live in a small pread pool.
  - Expert bytes touched per token, times the page-cache miss rate, divided by flash bandwidth, sets the decode ceiling.
  - Example: Qwen3.6-35B-A3B int4 touches ~1.85 GiB/token. At a 75% page-cache hit rate and ~1.65 GB/s (256 GB iPhone 17-class flash) that is ~0.28 s of I/O per token, so roughly ≤3.5 tok/s before compute. That is consistent in magnitude with the 1–5.5 tok/s reports.
- On the user's 8 GB iPad and 8 GB-class phones, the OS page cache has little spare room beside a 4–5 GB app, so hit rates and tok/s will be lower than on a 12 GB iPhone 17 Pro.
- Entitlement-wise the user is set (increased-memory-limit). Adding `extended-virtual-addressing` is cheap insurance for any mmap-heavy engine, since cactus #793 and the zenn article show mapping and VA ceilings failing before jetsam.

### Gaps
- No authoritative Apple table of per-device jetsam limits (with and without the entitlement) exists in what was found, for the iPhone 15 Pro, 16 Pro, 17 Pro, Air or M-series iPads. The user's own measurements (~7–8 GB on the 17 Pro; ~4.5–5.5 GB on the 8 GB iPad) remain the best numbers available here.
- `recommendedMaxWorkingSetSize` for the iPhone 17 Pro and M4/M5 iPads was not found (only the iPhone Air's 8,192 MB).
- No Apple documentation confirms iOS accounting of Metal-wired `MAP_SHARED` file pages. The evidence is empirical (one bench, macOS geistlib measurements).
- Whether iOS jetsam has a page-cache-size interaction (e.g. thrash kills from a heavily streamed mmap) was not documented. `vm-pageshortage` kills are the closest signal.

---

## 5. iPhone flash (NAND) read bandwidth on recent devices

### Takeaway
Sequential reads on iPhone 17-generation storage run from ~1.4–1.65 GB/s (base 256 GB iPhone 17 / 17 Pro) to ~3.2 GB/s (iPhone Air 256 GB), with 512 GB and 1 TB models faster. That is about 5–10× below an M-series Mac SSD (17.5 GB/s measured on an M3 Max). Random or expert-sized read throughput on iPhone has not been measured publicly.

### Cited Findings
- AnTuTu storage, from YouTuber DirectorFeng: **iPhone 17 (256 GB): 1,653.2 MB/s read**, 1,749.3 MB/s write; **iPhone Air (256 GB): 3,246.7 MB/s read**, 4,195.5 MB/s write. 512 GB and 1 TB iPhone 17 / 17 Pro / Pro Max score ~150,000 AnTuTu storage points (faster, MB/s not given). The 256 GB models are attributed to single-NAND configurations — [BGR](https://www.bgr.com/1986271/iphone-17-256gb-models-flash-memory-slow-speeds/)
- Another summary: iPhone 17 Pro sequential read 1,667 MB/s vs 1,418 MB/s for the base iPhone 17 (search-result snippet) — [mysmartprice](https://www.mysmartprice.com/performance-test/apple-iphone-17-23279) *(unverified)*
- An X post by Grok claims 512 GB and 1 TB iPhone 17 Pro models "hit ~3-4 GB/s". This is AI-generated and not a primary source — [X/Grok](https://x.com/grok/status/1975841707028783360?lang=en) *(low reliability)*
- Flash-MoE's estimate for the iPhone 17 was "~3-4 GB/s (est.)" against 17.5 GB/s measured on an M3 Max MacBook Pro — [FlashMoE-iOS/REVIEW.md](https://github.com/Anemll/flash-moe/blob/iOS-App/FlashMoE-iOS/REVIEW.md), [Anemll/flash-moe](https://github.com/Anemll/flash-moe/tree/iOS-App)
- Mac reference points for buffered pread under page-cache pressure: Linux colibri measured "~800 → ~180 MB/s" when the page cache was squeezed; SwiftLM uses concurrent pread at QD=24 to saturate the controller — [mlx-lm #1588 thread](https://github.com/ml-explore/mlx-lm/pull/1588), [SwiftLM](https://github.com/SharpAI/SwiftLM)
- Apple's own conclusion: "NAND-to-DRAM bandwidth is too slow to swap weights token by token" — [Apple ML Research](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)

### Inferences
- Expert sizes for 30B-class MoEs are ~1.5–7 MB per expert per layer (Flash-MoE: 6.75 MB 4-bit experts for the 397B; ~7 MB × K=8 for the 35B). These are large enough that per-expert reads behave close to sequential, so the 1.6–3.2 GB/s figures are a usable first-order bound.
- The storage tier matters. A 256 GB base iPhone 17 / 17 Pro would stream experts at roughly half the speed of an iPhone Air or a 512 GB+ Pro, so a streamed-MoE feature would show visible per-SKU performance differences.

### Gaps
- No public random-read or QD-sweep measurements for iPhone 17 Pro or iPad M4/M5 NAND at 1–8 MB block sizes.
- No iPad M-series storage-bandwidth numbers were found.
- The 512 GB / 1 TB iPhone 17 Pro sequential MB/s is not pinned down from a primary source.

---

## 6. Real reports of 15–30B MoE (Qwen3-30B-A3B, gpt-oss-20b, etc.) on iPhone or iPad

### Takeaway
The only credible iPhone reports of 20B+ MoEs use **flash-streaming custom engines**:
- Qwen3.5-35B-A3B at ~5.5 tok/s (Flash-MoE, iPhone 17).
- Qwen3.6-35B-A3B at ~1 tok/s in 2.5 GB (Swiftlet / Priv AI, iPhone 17).
- Qwen3.5-397B-A17B at 0.6 tok/s (Flash-MoE, iPhone 17 Pro).

No measured report was found of gpt-oss-20b or Qwen3-30B-A3B running **resident** on any iPhone or iPad through PocketPal, LLM Farm, Private LLM, Locally AI or Enclave. The memory math (13–19 GB of weights against an ~8 GB Metal working set) makes resident runs on iPhone implausible.

### Cited Findings
- Flash-MoE iOS: "5.5 tok/s on iPhone 17 with Qwen3.5-35B-A3B" (March 2026, project doc), and a 397B at 0.6 tok/s on iPhone 17 Pro (12 GB, ~200 GB on flash) — [REVIEW.md](https://github.com/Anemll/flash-moe/blob/iOS-App/FlashMoE-iOS/REVIEW.md), [dev.to](https://dev.to/max_quimby/iphone-17-pro-just-ran-a-400b-llm-on-device-ai-changes-everything-2026-53bm)
- Swiftlet: "The 35B also runs on an iPhone 17 in about 2.5 GB of RAM, at about 1 tok/s today", installable through Priv AI's Experimental Models — [Swiftlet](https://github.com/Avicennasis/Swiftlet)
- Resident limits seen in practice: llama.cpp on an iPhone Air 12 GB fails to load a 7.32 GB 13B Q4_K, while 7B/8B Q4_K run at ~9 tok/s — [Apple Forums 805161](https://developer.apple.com/forums/thread/805161)
- Mac reference sizes and speeds (MLX Swift via SwiftLM, base M6 32 GB):

  | Model | Weights | Resident decode | `--stream-experts` decode |
  |---|---|---|---|
  | `gemma-4-26b-a4b-it-4bit` | 15.3 GB | 53.9 tok/s | — |
  | `Qwen3.6-35B-A3B-UD-MLX-4bit` | 21.6 GB | 48.4 tok/s | 14.1 tok/s (5.7 GB peak) |

  Source: [SwiftLM](https://github.com/SharpAI/SwiftLM)
- gpt-oss-20b MXFP4 is a 13 GB artifact, at 100.2 tok/s on MLX and 78.1 on Core AI on an M4 Max — [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench). mlx-lm issue "Running mlx-community/gpt-oss-20b-MXFP4-Q8 with 16GB" (closed 2025-12) — [mlx-lm #644](https://github.com/ml-explore/mlx-lm/issues/644)
- Small MoEs that fit resident:
  - LFM2-8B-A1B (8.3B total, ~1.5B active) is reported at "approximately 30 tokens per second on a phone" (search-result summary of Liquid AI material; device and runtime unspecified) — [Liquid AI docs](https://docs.liquid.ai/lfm/models/lfm2-8b-a1b) *(unverified)*
  - Granite-4.0-H-Tiny and Nemotron-3-Nano-30B-A3B appear in the bench only on M4 Max — [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)
- PocketPal issue: gpt-oss-20b MXFP4_MOE quants fail on OpenCL (Android). No iOS 30B report was found in its issues — [pocketpal-ai #718](https://github.com/a-ghorbani/pocketpal-ai/issues/718)

### Inferences
- Resident on an iPhone 17 Pro (~8 GB Metal working set, ~7–8 GB jetsam budget), the largest MoE that plausibly fits is ~8B total at 4-bit (LFM2-8B-A1B ≈ 4.5–5 GB, Granite-4.0-H-Tiny 7B-A1B, OLMoE-1B-7B), or a ~20B MoE squeezed to ~3 bits. gpt-oss-20b (~12–13 GB), Qwen3-30B-A3B (~17–19 GB at 4-bit) and Gemma 4 26B-A4B (~15 GB at 4-bit) need flash streaming on iPhone.
- On a 16 GB M4/M5 iPad with the entitlement, gpt-oss-20b at ~12–13 GB is borderline at best. It depends on the unmeasured iPad `recommendedMaxWorkingSetSize`; on Macs it is ~65–75% of RAM, which would give ~10.5–12 GB.
- On the user's 8 GB iPad no 20B+ MoE runs resident, and streamed speed would be the weakest of all the devices.

### Gaps
- No tok/s or memory reports were found for Qwen3-30B-A3B or gpt-oss-20b on an iPad Pro M4/M5 16 GB in any App Store app (PocketPal, LLM Farm, Private LLM, Locally AI, Enclave). X/Twitter was not searchable here.
- No independent reproduction of the Flash-MoE 5.5 tok/s or the Swiftlet 1 tok/s iPhone figures, and neither reports thermal-sustained rates.

---

## 7. Bottom line: what an iOS app can run today, and with which engine

### Takeaway
As of 2026-10-01, the user's existing engine (upstream mlx-swift-lm) can run every relevant MoE architecture, but **only resident**. On a 12 GB iPhone 17 Pro that limits MoEs to roughly ≤6–7 GB of weights (8B-A1B class, or a 20B at ~3 bits). Going larger means switching to a flash-streaming runtime:
- **Flash-MoE**: C/Metal, Qwen-only, ~5.5 tok/s for a 35B-A3B on an iPhone 17.
- **Swiftlet**: Swift/Metal, Qwen-only, ~1 tok/s.
- **Anemll's llama.cpp fork**: supports Gemma4-26B-A4B as stable, but has been tested only on Macs.
- **SwiftLM's MLX fork**: `--stream-experts` has been tested only on Macs.

None of these offers a fine-tuning or adapter path, and all give up most of the decode speed. llama.cpp is the one mainstream engine whose iOS memory model (MAP_SHARED mmap, ~0 footprint for weights) suits oversized models. Its stock Gemma 4 quality lagged MLX in independent tests, although per-tensor `--tensor-type` overrides exist.

### Cited Findings
- Upstream MLX: MoE ports present ([Models dir](https://github.com/ml-explore/mlx-swift-lm/tree/main/Libraries/MLXLLM/Models)), with mmap and offload declined or unmerged ([mlx #4249](https://github.com/ml-explore/mlx/pull/4249), [mlx-lm #1588](https://github.com/ml-explore/mlx-lm/pull/1588)).
- iPhone streaming demos: [Flash-MoE iOS](https://github.com/Anemll/flash-moe/blob/iOS-App/FlashMoE-iOS/REVIEW.md), [Swiftlet](https://github.com/Avicennasis/Swiftlet). Mac-only streaming: [SwiftLM](https://github.com/SharpAI/SwiftLM), [anemll-flash-llama.cpp](https://github.com/Anemll/anemll-flash-llama.cpp).
- llama.cpp's iPhone footprint advantage (191 MB vs MLX 3,010 MB on Gemma 4 E2B), and its lower GSM8K with stock Q4_K_M (76% vs 84–91% for MLX builds) — [apple-silicon-llm-bench](https://github.com/john-rocky/apple-silicon-llm-bench)
- Apple chose per-prompt rather than per-token expert routing for its own 20B on-device model because of NAND bandwidth — [Apple ML Research](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)

### Inferences
- **Cheapest experiment within the current stack:** a small resident MoE on MLX (LFM2-MoE or GraniteMoeHybrid are already in mlx-swift-lm), quantized with mlx-lm's per-module predicates and DWQ so routers and embeddings stay high-precision. It fits the 17 Pro's budget without new runtime risk. On the 8 GB iPad it competes with the existing E4B for the same ~4.5–5.5 GB.
- **If the goal is a 20–35B MoE on iPhone:** expect a new runtime (fork or port), a 10–20 GB per-model download, single-digit tok/s that depends on storage tier and free page cache, and no maintained fine-tune pipeline for the streaming formats. Apple's AFM 3 design note and the measured 1–5.5 tok/s say this is a research spike, not a product swap.
- **A memory win for the current dense E4B that needs no MoE:** an mmap-based engine (llama.cpp with `--tensor-type` overrides protecting PLE) could cut the E4B's jetsam-charged footprint from ~4.2 GB to a few hundred MB. That would help the 8 GB iPad. It trades for slower decode, higher power, and a quality re-validation of the fine-tune. Upstream MLX cannot do this today.

### Gaps
- No head-to-head on-device test of an MLX-resident small MoE (e.g. LFM2-8B-A1B) against the current Gemma 4 E4B for German tutoring quality and tok/s on the user's devices. That needs the user's own DeviceHub runs.
- Whether AFM 3 Core Advanced is developer-accessible, and on which devices.
