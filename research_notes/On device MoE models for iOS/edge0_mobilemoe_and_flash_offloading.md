# Edge0, Meta MobileMoE, and flash-streamed MoE inference on phones (state as of 2026-10-01)

Reader context: a solo iOS developer runs a fine-tuned Gemma 4 E4B (4-bit, ~2.7 GB on disk, ~4.3 GB peak RAM) with MLX Swift on an iPhone 17 Pro (12 GB RAM; ~7–8 GB usable with the increased-memory-limit entitlement) and an 8 GB iPad (~4.5–5.5 GB budget). The app is a German tutor, so German and multilingual quality matter. Below, "demonstrated" means a number measured on a named device and published by the project or paper. "Claim" means a headline, a press relay, or a number with no device attached.

## Q1. Edge0 (edge0.ai/research/edge0): what it is, who made it, models, technique, devices, numbers, code and weights, iPhone support

### Takeaway
Edge0 is an Apache-2.0 open-source engine for streaming MoE experts from SSD. It ships two 4-bit MoE checkpoints: a 35B-A3B built on Qwen3.5/3.6-35B-A3B, and an 8B-A1B built on inclusionAI Ling 3.0 tiny. Its main idea is a trained "prerouter" that predicts the next layer's experts so flash reads overlap compute. It has a working Swift + MLX Swift iPhone app, open-sourced 2026-09-30. On an iPhone 16 Pro, the project's own table shows 6.4 tok/s decode for the 35B and 10.9 tok/s for the 8B. The headline 15–20 tok/s figure was measured on a 24 GB Mac mini M4 Pro, not a phone. No multilingual or German results are published.

### Cited Findings
**Identity and authorship**
- Edge0 calls itself "an open-source streaming MoE inference framework — SSD expert offload + Recover-LoRA + prerouter routing prediction". Peak memory "is bounded by the active expert set, not the parameter count." — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)
- Authors in the citation: Yu Lin, Yiming Wang, Runyuan Cai, Hanze Liu, Xiaodong Zeng. GitHub org: Edge0-AI. Contact: samuel@edge0.ai. — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)
- The arXiv abstract page lists no affiliation. One news aggregator calls it "AutoArk's Edge0"; that attribution is unconfirmed by any primary source. — [arXiv 2609.18063](https://arxiv.org/abs/2609.18063); [aiweekly](https://aiweekly.co/alerts/autoarks-edge0-serves-35b-moe-from-ssd-at-20-toks-on-24gb-mac)

**Timeline**
- 2026-09-08: initial open-source release with both model tiers.
- 2026-09-16: technical report on arXiv, titled "The Other Half of the Memory Wall: Serving 35B MoEs from SSD with Trained Routing Prediction" (revised 2026-09-17).
- 2026-09-30: iOS (Swift + MLX Swift), macOS (Rust), Android (Kotlin + native) and Windows (C++ + Vulkan) engines open-sourced.
- Sources: [Edge0 GitHub](https://github.com/Edge0-AI/Edge0); [arXiv 2609.18063](https://arxiv.org/abs/2609.18063)

**Models**
- **Edge0-35B-A3B-preview**
  - Website: based on "Qwen3.5-MoE 35B-A3B", 40 layers, 256 routed experts, "~23 GB" weights, "~2.9 GiB" peak active memory. — [edge0.ai research page](https://edge0.ai/research/edge0)
  - The repo's architecture doc and benchmark table name the base as **Qwen3.6-35B-A3B**, run with **K=4** active experts. — [Edge0 architecture.md](https://raw.githubusercontent.com/Edge0-AI/Edge0/master/docs/architecture.md); [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)
  - The paper says "a 35B-class model is 19.5GB at 4-bit". — [arXiv 2609.18063](https://arxiv.org/abs/2609.18063)
- **Edge0-8B-A1B-preview**
  - Base: inclusionAI Ling 3.0 tiny (hybrid MLA + MoE).
  - Size: ~7.9B total, ~1.2B active. 128 experts, top-8, 24 layers, hidden size 1536, 128k context, thinking mode via chat template.
  - Weights: int4, 4.55 GB in MLX format.
  - Apache 2.0, labelled "preview" with "agent capabilities remain underdeveloped".
  - Language note on the card: "Multilingual; primarily tuned for base model languages". — [HF Edge0-8B-A1B-preview](https://huggingface.co/Edge0/Edge0-8B-A1B-preview)
  - The website lists it as "~4.2 GB" with "~1.0 GiB" peak active memory. — [edge0.ai](https://edge0.ai/research/edge0)

**Technique**
- **SSD expert offload.** Expert weights are "mmapped and read on demand, they are not loaded into RAM up front". — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)
- **Prerouter.** "A per-layer head predicts the next layer's routing one token ahead, and the prediction is consumed as the routing itself, so the staged expert set equals the routed set and nothing is dropped." The project credits it with "up to +59% decode throughput". — [arXiv 2609.18063](https://arxiv.org/abs/2609.18063); [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)
- **Why naive offloading fails.** "layer N+1's experts must be chosen before layer N's output exists, so the reads cannot start early enough to hide behind compute." — [arXiv 2609.18063](https://arxiv.org/abs/2609.18063)
- **Recover-LoRA.** "The int4 base is frozen and LoRA adapters are trained by distillation from the FP teacher". The LoRA is unmerged and pays back loss from both int4 quantization and routing replacement. — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0); [arXiv](https://arxiv.org/abs/2609.18063)
- **Implementation details.** A cross-layer LRU `SharedExpertCache`, a byte-range mmap reader, double-buffered "staged" expert slots, `gather_qmm` quantized kernels, and full-layer loading for the first N prefill layers. — [architecture.md](https://raw.githubusercontent.com/Edge0-AI/Edge0/master/docs/architecture.md)

**Mac numbers (demonstrated, Mac mini M4 Pro 24 GB)**
- Method: "3.3k-token prompt prefill → 10 sampled warmup steps → 200 timed sampled decode tokens". — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)

| Model | Decode | Prefill cold / warm | Peak active memory |
| --- | --- | --- | --- |
| 35B | 14.9–17.7 tok/s | 113 / 140 tok/s | 2.9 GiB |
| 8B | 23.9–25.3 tok/s | 500 / 1428 tok/s | 1.0 GiB |

- The abstract rounds the 35B result to "20tok/s inside 3GiB". — [arXiv](https://arxiv.org/abs/2609.18063)

**iPhone numbers (demonstrated, project's own table)**
- iPhone 16 Pro on iOS 26.6.2. — [Edge0 ios/README](https://github.com/Edge0-AI/Edge0/tree/main/ios)

| Model | Prefill | TTFT | Decode |
| --- | --- | --- | --- |
| 8B | 7.2 tok/s | 3.6 s | 10.9 tok/s |
| 35B | 4.9 tok/s | 2.1 s | 6.4 tok/s |

- Prompt length, memory use and thermal state are not stated for these runs.

**iOS app details**
- SwiftUI app with an `Edge0MLX` engine on MLX Swift / Metal. Deployment target iOS 17. Requires a Developer-Mode device and your own signing. — [Edge0 ios/README](https://github.com/Edge0-AI/Edge0/tree/main/ios)
- Weights are copied into the `.app` at build time. The 8B app is "about 5 GB"; the 35B build is "about 20 GB". — [Edge0 ios/README](https://github.com/Edge0-AI/Edge0/tree/main/ios)
- The 35B must be repacked for iPhone. The published checkpoint "stores each expert as nine scattered reads across a 19 GB file. On an iPhone that is too slow". The tools rewrite "each expert into one sequential read" with one file per layer (`experts-L00.bin`…`experts-L39.bin`, plus `resident.safetensors`). — [Edge0 ios/README](https://github.com/Edge0-AI/Edge0/tree/main/ios)
- Sampling: "Prompt prefill runs a whole layer at a time, in chunks of up to 2048 tokens". The prefix cache lives in Application Support. Only one model is loaded at a time. — [Edge0 ios/README](https://github.com/Edge0-AI/Edge0/tree/main/ios)

**Quality (OpenCompass, five English-centric benchmarks: AIME 2026, HumanEval, GPQA-Diamond, MMLU-Pro, IFBench)**

| Benchmark | edge0-35b | Qwen3.6-35B-A3B fp16 | edge0-8b | Ling 3.0 tiny fp16 |
| --- | --- | --- | --- | --- |
| AIME 2026 | 86.6 | 92.7 | 63.3 | 73.3 |
| HumanEval | 90.9 | 95.1 | 91.5 | 92.7 |
| GPQA-Diamond | 79.8 | 81.8 | 70.7 | 71.2 |
| MMLU-Pro | 81.0 | 84.6 | 70.1 | 65.8 |
| IFBench | 57.9 | 61.7 | 53.9 | 60.6 |
| **Average** | **79.2** | **83.2** | **69.9** | **72.7** |

- Source: [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)
- No multilingual or German evaluations are published. — [edge0.ai](https://edge0.ai/research/edge0)

**Known issues and dependencies**
- Python pins "mlx==0.30.6 / mlx-metal==0.30.6 with mlx-lm==0.31.0". — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)
- Known issue: "Garbled, mixed-language output on Apple A18 / A18 Pro means an older mlx". — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)
- Both the LoRA and the prerouter adapter are required, unless you run with `--no-prerouter` / `--no-lora`. — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)
- Q4 2026 roadmap: a unified cross-platform layer, a CUDA backend, and "Qwen3.8-Flash class" support. These are plans, not deliverables. — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0)

### Inferences
- **Active-expert count.** Edge0-35B runs K=4 experts per token. Qwen3.6-35B-A3B natively routes top-8 (see Q3, Paging the Experts). So Edge0 likely halves the experts read per token, which halves flash traffic. That would be part of the "routing replacement" loss the Recover-LoRA is meant to recover.
- **Phone vs Mac.** On the phone, decode is 6.4 tok/s vs ~15–18 tok/s on the Mac (~2.5x slower). Prefill is ~23x slower (4.9 vs 113 tok/s). The iPhone 8B prefill of 7.2 tok/s (vs 500–1428 on Mac) means a 300-token prompt would wait ~40 s. That is a real problem for a tutor that sends long system prompts.
- **App Store fit.** The iOS app bundles weights inside the `.app`, a sideload demo pattern. A shipping app would need runtime downloads, as this app already does. The 35B also needs the repack step, so a ~20 GB download per device.
- **Fit on the reader's devices.** Memory is not the blocker: the 35B's ~2.9 GiB peak fits both the 7–8 GB iPhone budget and the 4.5–5.5 GB iPad budget. The open questions are storage (20 GB), prefill latency and German quality.
- **Fine-tuning cost.** The prerouter and Recover-LoRA are trained against a specific base model. A German fine-tune of the base would probably need both adapters retrained. That is a distillation pipeline on a 35B MoE, not a quick LoRA.
- **MLX versions.** The A18-garbling note suggests sensitivity to the MLX version. The reader's app links its own MLX Swift version, so any integration needs version reconciliation.

### Gaps
- No iPhone 17 Pro numbers, no iPhone peak-memory or prompt-length figures, and no thermal or energy data.
- No prerouter hit-rate or accuracy figure in the abstract-level content I could read.
- No German or multilingual benchmarks, for either tier.
- The organization behind Edge0 is unconfirmed.
- The website says the 35B base is Qwen3.5; the repo says Qwen3.6. Both share the `qwen3_5_moe` architecture, so this is probably a naming update, but it is unverified.

## Q2. Meta MobileMoE (HF collection facebook/mobilemoe): models, paper, benchmarks, license, runtime, iOS numbers

### Takeaway
MobileMoE is a Meta research family of small MoE models that fit in RAM. They are not models streamed from flash. Sizes run 1.3–5.3B total and 0.27–0.92B active; every size uses 60 fine-grained experts, top-4, plus one shared expert. They are trained mostly on English, use the Llama-3 tokenizer, and carry the noncommercial FAIR NC license. Measured on a Galaxy S25 and an iPhone 16 Pro with ExecuTorch/XNNPACK (and MLX on the iPhone GPU), the smallest model decodes 2.2–3.4x faster than Meta's dense MobileLLM-Pro. The models are downloadable, gated behind a Meta form. No ExecuTorch kernel release is linked.

### Cited Findings
**Collection and paper**
- Collection description: "a family of on-device MoE language models with sub-billion active parameters (0.3-0.9B active and 1.3-5.3B total)". Nine checkpoints, Base / SFT / QAT for each of S, M and L, updated Aug 25–30. — [HF collection](https://huggingface.co/collections/facebook/mobilemoe)
- Paper: "MobileMoE: Scaling On-Device Mixture of Experts", arXiv 2605.27358v1, 26 May 2026.
- Authors: Yanbei Chen, Hanxian Huang, Ernie Chang, Jacob Szwejbka, Digant Desai, Zechun Liu, Vikas Chandra, Raghuraman Krishnamoorthi. — [arXiv 2605.27358](https://arxiv.org/abs/2605.27358)

**Model configurations (paper Table 1 / Fig 2)**
- All sizes: "60 fine-grained experts, top-4 routing and a shared expert".

| Size | Active | Total | INT4 weight memory |
| --- | --- | --- | --- |
| S | 272M | 1.3B | 0.68 GB |
| M | 528M | 2.8B | 1.48 GB |
| L | 922M | 5.3B | 2.75 GB |

- Source: [arXiv HTML](https://arxiv.org/html/2605.27358)

**L-QAT model card**
- 32 layers, d=1280, 20 heads / 4 KV heads, 8,192 context, vocab 128,256. — [HF MobileMoE-L-QAT](https://huggingface.co/facebook/MobileMoE-L-QAT)
- Quantization: INT4 symmetric, group size 32, FP16 scales. Router stays FP32; norms are BF16. — [HF MobileMoE-L-QAT](https://huggingface.co/facebook/MobileMoE-L-QAT)
- Packaged sizes: S-QAT 0.71 GB, M-QAT 1.59 GB, L-QAT 3.00 GB. — [HF MobileMoE-L-QAT](https://huggingface.co/facebook/MobileMoE-L-QAT)
- Running it needs `trust_remote_code=True` with custom `modeling_mobilemoe.py`. A BF16 conversion script is provided for vLLM. — [HF MobileMoE-L-QAT](https://huggingface.co/facebook/MobileMoE-L-QAT)

**Training data and language**
- ~6T pre-training tokens of open-licensed data (">60% web-heavy"), ~500B mid-training, ~80M SFT samples. — [arXiv HTML](https://arxiv.org/html/2605.27358)
- Uses the "Llama-3 tokenizer with 128K vocabulary". — [arXiv HTML v1](https://arxiv.org/html/2605.27358v1)
- The model card says "English only". No multilingual evaluation. — [HF MobileMoE-L-QAT](https://huggingface.co/facebook/MobileMoE-L-QAT); [arXiv HTML v1](https://arxiv.org/html/2605.27358v1)

**Runtime and devices (demonstrated)**
- Runtime: "ExecuTorch with XNNPACK backend and custom fused MoE kernel". — [arXiv HTML](https://arxiv.org/html/2605.27358)
- Devices: Samsung Galaxy S25 (Snapdragon 8 Elite, 4 CPU threads); iPhone 16 Pro (A18 Pro, 2 CPU threads); iPhone 16 Pro GPU via Metal/MLX. — [arXiv HTML](https://arxiv.org/html/2605.27358)

**INT4 speed vs MobileLLM-Pro (Table 7, 512–2k context)**

| Device | Model | TTFT | Decode |
| --- | --- | --- | --- |
| iPhone 16 Pro (CPU) | MobileMoE-S | 1.02–5.23 s | 180.5–90.2 tok/s |
| iPhone 16 Pro (CPU) | MobileLLM-Pro | 2.90–14.13 s | 55.1–32.4 tok/s |
| Galaxy S25 | MobileMoE-S | 0.90–7.82 s | 130.0–61.7 tok/s |
| Galaxy S25 | MobileLLM-Pro | 1.73–14.21 s | 56.5–27.6 tok/s |

- Source: [arXiv HTML](https://arxiv.org/html/2605.27358)
- iPhone 16 Pro GPU (MLX, Table 8): MobileMoE-S decodes at 141.9–154.3 tok/s vs 56.3–61.8 dense. That is 3.6–3.8x faster prefill and 2.5–2.6x faster decode. — [arXiv HTML v1](https://arxiv.org/html/2605.27358v1)
- Larger sizes, CPU only, as extracted from Table 7:
  - iPhone 16 Pro: M 17.2–106.8 tok/s; L 10.8–59.4 tok/s.
  - Galaxy S25: M 15.4–83.6 tok/s; L 8.9–53.4 tok/s.
  - The ranges appear to span context lengths up to 8k.
  - No GPU/MLX numbers for M or L. — [arXiv HTML v1](https://arxiv.org/html/2605.27358v1)
- Peak RSS at 8k context (Table 9): MobileLLM-Pro 1.91 GB; S 1.49 GB; M 2.77 GB; L 4.71 GB. — [arXiv HTML](https://arxiv.org/html/2605.27358)

**Quality (14 English benchmarks, INT4 QAT)**
- Averages: S 44.0 (vs MobileLLM-Pro 45.5); M 52.5; L 57.8. The L card shows 58.1 average (MMLU 5-shot 57.4, GSM8K 73.2). — [arXiv HTML](https://arxiv.org/html/2605.27358); [HF card](https://huggingface.co/facebook/MobileMoE-L-QAT)
- L beats OLMoE-1B-7B by about 7–8 points, and the paper reports it beating Qwen3.5-2B on multiple benchmarks. — [arXiv HTML v1](https://arxiv.org/html/2605.27358v1)

**License, access and missing pieces**
- License: "MobileMoE is FAIR NC licensed" (FAIR Noncommercial Research License). Access is gated behind Meta's form and privacy-policy acknowledgement. — [HF card](https://huggingface.co/facebook/MobileMoE-L-QAT)
- No energy or power measurements, and no GitHub link for the fused MoE ExecuTorch kernel. — [arXiv HTML v1](https://arxiv.org/html/2605.27358v1)

### Inferences
- MobileMoE does not stream from flash. It shows that small MoEs beat small dense models on speed per unit of quality, with all weights resident.
- For a German tutor it is a poor fit on three counts: English-only data, a Llama-3 tokenizer trained for English-heavy text, and a noncommercial license. Even MobileMoE-L (58 average on English benchmarks, 4.71 GB peak RSS at 8k) would need heavy German continued pre-training that the license may not permit for an App Store app.
- The iPhone 16 Pro CPU numbers via ExecuTorch are among the few published, independently measured iPhone MoE figures this year. Without a released kernel, they cannot be reproduced in MLX Swift.

### Gaps
- No German or multilingual scores.
- No ExecuTorch export or kernel release found.
- No iPhone GPU numbers for M or L.
- No energy data.
- The exact column meaning of the M/L decode ranges (512 vs 8k context) was not confirmed from the table itself.

## Q3. Other 2024–2026 work that runs MoE models larger than RAM on phones by streaming experts from flash

### Takeaway
Only a handful of projects have measured MoE-from-flash on an actual iPhone:

| Project | iPhone result | Status |
| --- | --- | --- |
| Edge0 (Q1) | 6.4 tok/s, 35B-A3B, iPhone 16 Pro | Open code |
| "Paging the Experts" / Routide | 1.8–3.1 tok/s, Qwen3.6-35B-A3B 4-bit, iPhone 17 Pro Max, ~2–2.7 GiB footprint | MIT research runtime |
| flash-moe iPhone port (ANEMLL) | 0.6–0.7 tok/s, Qwen3.5-397B 2-bit, iPhone 17 Pro | Demo only |

On Android: SmallThinker (21B-A3B at ~23 tok/s on a OnePlus 13 via PowerInfer), PowerInfer-2 (2024; 11.68 tok/s on a 47B, but only with ReLU-sparsified models) and BigMoMo (Sept 2026; Qwen3-30B-A3B / Gemma-4-26B-A4B on OnePlus phones, 4.83x over naive offloading, no code). Older systems (LLM in a Flash, EdgeMoE, SwapMoE, HOBBIT, MoE-Infinity, Mixtral-offloading) were evaluated on Macs, GPUs or Jetsons, not iPhones.

### Cited Findings
**Paging the Experts / Routide (iPhone, Sept 2026, demonstrated)**
- Paper: "Paging the Experts: A Reproducible Characterization of Flash-Backed MoE Inference on iPhone", arXiv 2609.29032v1, 24 Sept 2026. Author: Musa Shams, independent researcher. — [arXiv HTML](https://arxiv.org/html/2609.29032)
- Setup:
  - Device: iPhone 17 Pro Max on iOS 26.5.2, 26.6.1 and 27.0.
  - Model: `mlx-community/Qwen3.6-35B-A3B-4bit` (qwen3_5_moe; 40 layers, 256 routed experts per layer, top-8; affine INT4 group size 64). Expert payload "18,119,393,280" bytes.
  - Engine: Swift/MLX ("Swift positional reader, byte-budgeted cache, quantized MLX executor") on MLX 0.31.2.
  - Source: [arXiv HTML](https://arxiv.org/html/2609.29032)
- Decode results:
  - 2.246 tok/s with a 512 MiB LRU, cold.
  - 3.052 tok/s with a 576 MiB LRU, cold.
  - 1.795–2.085 tok/s sustained over 512 tokens (four runs).
  - Prefill is serial, one token at a time ("a major implementation boundary").
  - Process footprint: 1.87–2.32 GiB on short prompts; 2.39–2.73 GiB on a 340-token prompt. No memory warnings.
  - Source: [arXiv HTML](https://arxiv.org/html/2609.29032)
- Routide is MIT-licensed, Swift 6.3+, needs Xcode 27 / MLX Swift 0.31.6, runs on iOS and macOS, and supports only the text decoder. It ships source libraries (`RoutideRuntime`, `RoutideMLXRuntime`) but not the original Xcode workspace. — [Routide GitHub](https://github.com/MusaShams/Routide)

**flash-moe and the iPhone 397B demo (Mar 2026)**
- Mac result (demonstrated): flash-moe, by Dan Woods (GitHub danveloper), is a pure C/Metal engine running Qwen3.5-397B-A17B (512 experts per layer, K=4, 60 layers).
  - Hardware: MacBook Pro M3 Max, 48 GB, measured SSD "17.5 GB/s sequential read".
  - Speed: "4.36" tok/s at 4-bit (209 GB on disk).
  - Memory: ~6 GB resident (5.5 GB non-expert weights).
  - Caching: it relies on the OS page cache (~35 GB, ~71% hit rate).
  - 2-bit "breaks JSON/tool calling".
  - No iPhone run is documented in that repo.
  - Source: [flash-moe GitHub](https://github.com/danveloper/flash-moe)
- iPhone claim (press-reported, not a project benchmark): ANEMLL (@anemll) ran the 397B on an iPhone 17 Pro (12 GB) on 2026-03-23.
  - Speed is reported as "0.6 t/s" by [wccftech](https://wccftech.com/iphone-17-pro-successfully-runs-400b-llm-locally/) and "0.7 tokens per second" by [Gigazine](https://gigazine.net/gsc_news/en/20260324-iphone-397b-ai/). The sources conflict.
  - A search snippet from [TweakTown](https://tweaktown.com/news/110610/the-iphone-17-pro-can-run-a-400b-parameter-large-language-model-on-device-by-streaming-weights-from-the-ssd/index.html) describes 2-bit weights, 5.5 GB resident, and a TTFT of almost 50 s.
- Gigazine quotes the Mac run at "5.7 tokens per second", which conflicts with the README's 4.36 at 4-bit. The higher figure may be from 2-bit. — [Gigazine](https://gigazine.net/gsc_news/en/20260324-iphone-397b-ai/); [flash-moe](https://github.com/danveloper/flash-moe)

**SmallThinker (Jul 2025, SJTU IPADS + Zenergize; Android/CPU)**
- Models built for local deployment:
  - 21B-A3B: 64 experts, top-6, 52 layers, ReGLU, NoPE-RoPE hybrid attention, 16K context, 7.2T tokens "primarily English", Apache 2.0.
  - 4B-A0.6B.
  - Source: [HF SmallThinker-21BA3B-Instruct](https://huggingface.co/PowerInfer/SmallThinker-21BA3B-Instruct); [arXiv 2507.20984](https://arxiv.org/html/2507.20984)
- Q4_0 decode:

| Device | 21B-A3B | 4B-A0.6B |
| --- | --- | --- |
| OnePlus 13 | 23.03 tok/s | 78.99 tok/s |
| i9-14900 | 30.19 tok/s | 108.17 tok/s |
| RK3588 | 10.84 tok/s | 39.76 tok/s |
| Raspberry Pi 5 | 6.61 tok/s | 28.77 tok/s |

- Source: [arXiv 2507.20984](https://arxiv.org/html/2507.20984)
- The paper says "both models exceed 20 tokens/s on ordinary consumer CPUs, while consuming only 1GB and 8GB of memory respectively". A "pre-attention router" lets the engine "prefetch expert parameters from storage while computing attention". Under memory limits, the 21B reaches "up to 85× higher throughput than Qwen3-30B-A3B". — [arXiv 2507.20984](https://arxiv.org/html/2507.20984)
- Runtimes: PowerInfer, llama.cpp, Transformers. No iOS-specific work. — [HF card](https://huggingface.co/PowerInfer/SmallThinker-21BA3B-Instruct)
- Secondary only: QbitAI reports the 4B at 19.41 tok/s at 1 GB peak memory, device unspecified. — [QbitAI](https://www.qbitai.com/2025/07/313482.html)

**PowerInfer-2 (Jun 2024, v3 Dec 2024; older)**
- Hardware: OnePlus 12 (Snapdragon 8 Gen 3, 24 GB, UFS 4.0, flash "4 GB/s with 512KB blocks", ~1 GB/s random 4 KB). — [arXiv HTML 2406.06282](https://arxiv.org/html/2406.06282)
- Speed: TurboSparse-Mixtral-47B at 9.96–11.68 tok/s with 50% of FFN weights offloaded. That is 21.2x over llama.cpp and 3.12x over LLM-in-a-Flash. Energy: 0.257 J/token. — [arXiv HTML 2406.06282](https://arxiv.org/html/2406.06282)
- It "Requires sparsified models with ReLU activations": 4.6x acceleration on ReLU models vs 2.4x on SiLU models. PowerInfer-2 is 12K lines of C++ on top of PowerInfer; its release status is unclear. — [arXiv HTML 2406.06282](https://arxiv.org/html/2406.06282)

**BigMoMo (13 Sept 2026, Peking U. / Tianjin U.; Android)**
- Hardware:

| Phone | SoC | RAM (available) | Storage |
| --- | --- | --- | --- |
| OnePlus 15 | Snapdragon 8 Elite Gen 5 | 16 GB (11.52 GB) | UFS 4.1 |
| OnePlus 13 | Snapdragon 8 Elite | 24 GB (18.23 GB) | UFS 4.0 |
| OnePlus Ace 5 | Snapdragon 8 Gen 3 | 12 GB (6.00 GB) | UFS 4.0 |

- Flash "typically around 4 GB/s". — [arXiv HTML 2609.14643](https://arxiv.org/html/2609.14643)
- Models, all Q4_0: Qwen3-30B-A3B, LFM2-24B-A2B, **Gemma-4-26B-A4B-it**, ERNIE-4.5-21B-A3B. — [arXiv HTML 2609.14643](https://arxiv.org/html/2609.14643)
- Method: speculative decoding verify windows drive expert reuse, flash re-layout (1.23x effective bandwidth), and NPU (HTP) overlap.
- Results: 4.83x over on-demand autoregressive offloading and 1.82x over the best speculative MoE baseline. Gemma4 gets 1.80x. MMLU-Pro drops "approximately 0.26% relative" from pruning.
- Built on llama.cpp (+~5,000 lines) under Termux. No iOS results and no code release. — [arXiv HTML 2609.14643](https://arxiv.org/html/2609.14643)

**Other 2026 work (search snippets only, not verified in full text)**
- DraftExpert (arXiv 2607.24434): 1.45x decode on DeepSeek-V2-Lite and Moonlight-16B-A3B, across CPU→GPU and Flash→NPU offload. — [arXiv](https://arxiv.org/abs/2607.24434)
- FreeToken (arXiv 2608.16157): "77–83 tok/s on Qwen3.6 and 22–25 tok/s on DSV4-Flash"; "edge-native", hardware not confirmed as a phone. — [arXiv](https://arxiv.org/html/2608.16157v1)
- SeqMoE (arXiv 2609.12978) and DALI (arXiv 2602.03495) target offloading on GPUs or local PCs. — [SeqMoE](https://arxiv.org/pdf/2609.12978); [DALI](https://arxiv.org/pdf/2602.03495)

**Apple "LLM in a Flash" (Dec 2023, ACL 2024 v3; older, dense models)**
- Runs models "up to twice the size of the available DRAM", 4–5x faster on CPU and 20–25x on GPU vs naive loading. Techniques: windowing and row-column bundling. — [arXiv 2312.11514](https://arxiv.org/abs/2312.11514)
- Hardware: M1 Max (1 TB) and M2 Ultra; no iPhone. The M1 Max reads ">6 GiB/s for a 1GiB linear read", but sparse 32 KiB × 32-thread reads get ~2.25 GB/s. — [arXiv HTML](https://arxiv.org/html/2312.11514v3)
- Example: OPT-6.7B on M1 Max CPU drops from 3182 ms/token naive to 669 ms. About 50% of the model stays in DRAM. MoE is mentioned only as future applicability. — [arXiv HTML](https://arxiv.org/html/2312.11514v3)

**HOBBIT (Nov 2024)**
- Mixed-precision expert offloading: on a cache miss it loads a low-precision copy of less-important experts. Adds token-level loading, layer-level prefetch and sequence-level caching.
- Up to 9.93x decode speedup over prior offloading systems. Built on llama.cpp. Evaluated on RTX 4090 and Jetson AGX Orin with Mixtral-8x7B and Phi-MoE, not phones. — [arXiv 2411.01433](https://arxiv.org/html/2411.01433v2)

**Earlier systems (2023–2024; mechanisms per a survey)**
- EdgeMoE keeps non-expert weights in memory and experts in external storage, predicting next-layer experts from a calibrated table.
- Mixtral-offloading uses an LRU expert cache.
- MoE-Infinity uses activation-aware, sequence-level prefetching.
- SwapMoE caches and schedules experts by access frequency and importance.
- Source: [MoE inference survey arXiv 2412.14219](https://arxiv.org/pdf/2412.14219)

### Inferences
- **Usable code today for iOS:** Edge0 (Apache-2.0, Swift + MLX Swift app, own checkpoints) and Routide (MIT, Swift/MLX research runtime, generic mlx-community Qwen3.6 checkpoint). flash-moe is C/Metal for macOS; the iPhone port is a demo with no documented repo.
- **Android only:** PowerInfer/SmallThinker, BigMoMo and PowerInfer-2.
- **Paper or older-hardware only:** LLM in a Flash, HOBBIT, EdgeMoE, SwapMoE, MoE-Infinity and Mixtral-offloading.
- **Same model, two engines.** Edge0 (6.4 tok/s, iPhone 16 Pro, K=4) and Routide (1.8–3.1 tok/s, iPhone 17 Pro Max, native top-8) run the same Qwen3.6-35B-A3B class. The 2–3x gap fits two things: Edge0's halved expert count with prediction-driven prefetch, and Routide's untuned research reader. Note the reversed hardware: the faster result came on the older phone.
- **BigMoMo and Gemma.** BigMoMo is the only work found that streams a **Gemma 4** MoE (26B-A4B) on a phone. Gemma's multilingual pedigree makes that the closest technical match to a German tutor. It is Android-only, with no code and no absolute tok/s in the extract.
- **Quality loss at 2-bit.** The 397B demo is impractical at 0.6–0.7 tok/s, and its 2-bit quantization visibly harms structured output. A tutor that needs reliable JSON for grammar-error detection should not use 2-bit experts.

### Gaps
- BigMoMo's absolute tok/s per model and phone was not extracted.
- SmallThinker's phone number under its 8 GB memory cap was not confirmed. The 23.03 tok/s OnePlus 13 figure may be with ample RAM.
- No iPhone numbers exist for SmallThinker, PowerInfer, HOBBIT, EdgeMoE, SwapMoE, MoE-Infinity or Mixtral-offloading.
- EdgeMoE, SwapMoE, MoE-Infinity and Mixtral-offloading primary papers were not fetched; I have no per-device decode figures for them.
- ANEMLL's own iPhone code and repo were not located. The flash-moe repo has no license in its README.
- A search snippet claimed Gemma 4 26B-A4B runs ">40 tok/s" on iPhone 17 Pro via MLX ([36kr](https://eu.36kr.com/en/p/3754860403294985)). That conflicts with memory math: ~26B at 4-bit is well above a 12 GB phone's app budget. It likely conflates E2B/E4B and is treated as unverified.

## Q4. Realistic speed penalty of streaming experts from iPhone NAND, and how routing locality and caching mitigate it

### Takeaway
Reported iPhone sequential reads are about 1.6 GB/s (256 GB iPhone 17 / 17 Pro, and reportedly iPhone 16 Pro-class chips) and about 2.9–3.2 GB/s (512 GB and up). That is roughly 5–10x below a MacBook's 17.5 GB/s SSD and below Android UFS 4.x's ~4 GB/s. Small random reads are much slower everywhere. Measured penalties for the same engine: Edge0-35B decodes ~2.5x slower on iPhone 16 Pro than on an M4 Pro Mac (6.4 vs ~15–18 tok/s), and flash-moe's 397B ~6–7x slower on iPhone 17 Pro than on an M3 Max (0.6–0.7 vs 4.36 tok/s). The mitigations that matter: fewer bytes per token (fewer active experts, one contiguous read per expert), prediction one step ahead so reads overlap compute, and a cache sized beyond the routing reuse distance. One iPhone study shows LRU collapsing to 0% hits at 512 MiB.

### Cited Findings
**iPhone storage speed (secondary sources; Apple publishes no NAND speeds)**
- iPhone 17 (base) sequential read benchmark: 2,929.5 MB/s. — [MySmartPrice (via search)](https://www.mysmartprice.com/mobile/apple-iphone-17-msp23279/benchmark-scores)
- 256 GB iPhone 17 / 17 Pro / 17 Pro Max: ~1600 MB/s read and ~1700 MB/s write. 512 GB and 1 TB: ~3200 MB/s read and ~4100 MB/s write. The 256 GB tier reportedly uses the same older chips as the iPhone 16 Pro series. — [HK01](https://global.hk01.com/數碼生活/60284861/iphone-17系列被爆低配版硬碟-苹果成本控制导致扩容升级被封死); [MacObserver (via search snippet)](https://www.macobserver.com/?p=407224)
- iPhone 18 Pro 1 TB / 2 TB use QLC. Sustained **writes** fall to 79.4 MB/s (dips to 25.6 MB/s) after the SLC cache fills. Weighted 4K **read** scores are 46,045 on QLC vs 51,282 on TLC. Reads matter for streaming; writes only for the one-time model download. — [Notebookcheck / GadgetReview (via search)](https://www.gadgetreview.com/?p=413422)

**Reference bandwidths elsewhere**
- MacBook Pro M3 Max SSD: 17.5 GB/s sequential. — [flash-moe](https://github.com/danveloper/flash-moe)
- M1 Max: >6 GiB/s linear, ~2.25 GB/s for 32 KiB sparse chunks. — [LLM in a Flash](https://arxiv.org/html/2312.11514v3)
- OnePlus 12 UFS 4.0: 4 GB/s at 512 KB blocks, ~1 GB/s at random 4 KB. — [PowerInfer-2](https://arxiv.org/html/2406.06282)
- Snapdragon phones generally: "typically around 4 GB/s" with degradation on small or random accesses. — [BigMoMo](https://arxiv.org/html/2609.14643)

**Measured penalties**
- Edge0-35B: 14.9–17.7 tok/s on M4 Pro vs 6.4 tok/s on iPhone 16 Pro. Prefill: 113–140 vs 4.9 tok/s. — [Edge0 GitHub](https://github.com/Edge0-AI/Edge0); [Edge0 ios/README](https://github.com/Edge0-AI/Edge0/tree/main/ios)
- flash-moe 397B: 4.36 tok/s on M3 Max (4-bit) vs 0.6–0.7 tok/s on iPhone 17 Pro (2-bit). — [flash-moe](https://github.com/danveloper/flash-moe); [wccftech](https://wccftech.com/iphone-17-pro-successfully-runs-400b-llm-locally/); [Gigazine](https://gigazine.net/gsc_news/en/20260324-iphone-397b-ai/)

**Data layout**
- Edge0's published 35B checkpoint needs "nine scattered reads" per expert, which is "too slow" on iPhone. They repack to "one sequential read" per expert. — [Edge0 ios/README](https://github.com/Edge0-AI/Edge0/tree/main/ios)
- BigMoMo's on-flash re-layout gives 1.23x effective bandwidth. — [BigMoMo](https://arxiv.org/html/2609.14643)
- LLM in a Flash uses row-column bundling for the same reason. — [arXiv](https://arxiv.org/abs/2312.11514)

**Prediction and prefetch**
- Edge0's prerouter adds up to +59% decode. — [Edge0](https://github.com/Edge0-AI/Edge0)
- SmallThinker's pre-attention router prefetches during attention. — [SmallThinker](https://arxiv.org/html/2507.20984)
- On iPhone, a confidence-gated predictor reached 61.31% accuracy, but "Prediction accuracy does not imply useful prefetch". Prefetch checks polluted the cache (74 demand hits lost through recency changes). — [Paging the Experts](https://arxiv.org/html/2609.29032)

**Cache locality (iPhone 17 Pro Max, five 128-token prompts)**

| Policy | 512 MiB | 576 MiB | 1,024 MiB |
| --- | --- | --- | --- |
| LRU hit rate | 0.00% | 38.58% | 47.59% |
| Random | 18.80% | 21.80% | 37.47% |
| Pinned farthest-next-use | 54.49% | 56.93% | 68.23% |

- "The minimum observed distinct-expert reuse distance is 312 on every trace", and "The LRU capacity cliff is not a universal RAM threshold". Logical expert reads during cold decode: 16.987 GB at 512 MiB vs 9.709 GB at 576 MiB. — [Paging the Experts](https://arxiv.org/html/2609.29032)
- On a Mac, flash-moe's OS page cache (~35 GB) hits ~71% on a 397B. Phones lack that headroom. — [flash-moe](https://github.com/danveloper/flash-moe)

### Inferences
These are back-of-envelope estimates from the cited figures, not measurements.
- **Bytes per token.** Qwen3.6-35B-A3B's 18.12 GB expert payload over 40 × 256 = 10,240 experts is ~1.77 MB per expert.
  - Native top-8 × 40 layers ≈ 566 MB per token with all misses. At 1.6 GB/s that is ≈2.8 tok/s; at 3.2 GB/s ≈5.6 tok/s, before caching.
  - At Edge0's K=4 (~283 MB per token), the I/O-only ceilings become ≈5.6 and ≈11 tok/s.
  - These bounds bracket the observed 1.8–3.1 tok/s (Routide, top-8) and 6.4 tok/s (Edge0, K=4).
- **Storage tier matters.** On a 256 GB iPhone 17 Pro, streaming should run ~2x slower than on a 512 GB+ unit. Any per-device speed claim must name the storage tier.
- **Cache sizing.** With a reuse distance of ≥312 experts × ~1.77 MB ≈ 550 MB, an LRU cache much under ~0.6 GB gives nearly no hits. That matches the 512 MiB cliff. The reader's ~7–8 GB iPhone budget could hold a cache of several GB, so hit rates above the 1,024 MiB figure are plausible, but no one has published that curve on iPhone.
- **Prefill is the real penalty for a tutor.** Prefill tok/s on iPhone (4.9–7.2 in Edge0, serial in Routide) is orders of magnitude below in-RAM models. A long system prompt plus learner context would dominate latency unless the prefix cache is reused, which Edge0 does via a persisted prefix cache.

### Gaps
- No primary, controlled measurement of iPhone 17 Pro random or 4 K-to-2 MB read bandwidth: pread vs mmap, F_NOCACHE, queue depth.
- Routide explicitly does not measure physical NAND traffic.
- No published iPhone cache-size curve beyond 1 GiB.
- No iPhone DRAM bandwidth figure sourced in this pass for a flash-vs-DRAM ratio.

## Q5. Energy and thermal cost on phones

### Takeaway
Energy data is thin. The only iPhone figure is a whole-device estimate of ~26.5% battery per hour during a 512-token flash-backed decode on an iPhone 17 Pro Max, with one "fair" thermal state observed. PowerInfer-2 reports 0.257 J/token on a OnePlus 12 (2024). Edge0, MobileMoE, flash-moe, SmallThinker and BigMoMo publish no energy numbers in the material reviewed. The iPhone 397B coverage only says the battery "will be heavily taxed".

### Cited Findings
- Paging the Experts, iPhone 17 Pro Max:
  - One whole-device power-estimator integral over a 512-token run gave a "26.505 battery-percent/hour rate". The author says this "is not app-only watts or joules… [or] calibrated energy per token" and that there was "No matched no-prefetch power control".
  - One request was marked "fair" thermal state.
  - Run-to-run timing varied by ±10.58%.
  - Source: [arXiv HTML 2609.29032](https://arxiv.org/html/2609.29032)
- PowerInfer-2: 0.257 J/token, 31% less than QNN and 62% less than llama.cpp, on a OnePlus 12. — [arXiv HTML 2406.06282](https://arxiv.org/html/2406.06282)
- MobileMoE: "Not reported", meaning no energy or power data. — [arXiv HTML v1](https://arxiv.org/html/2605.27358v1)
- Edge0: no energy or thermal data on the research page. — [edge0.ai](https://edge0.ai/research/edge0)
- iPhone 397B demo: "the iPhone 17 Pro's battery will be heavily taxed", with no measurements. — [wccftech](https://wccftech.com/iphone-17-pro-successfully-runs-400b-llm-locally/)

### Inferences
- At ~26.5% per hour, a 20-minute tutoring session of continuous generation would use roughly 9% of battery. Real chat is bursty, so actual drain would be lower. This rests on a single uncalibrated run.
- Sustained flash reads plus GPU decode likely raise thermals more than resident inference. The lone "fair" state hints at this but does not establish throttling.
- Throttling tests over a full lesson are a gap the reader would have to measure with their own app.

### Gaps
- No per-token energy for any iPhone MoE streaming engine.
- No resident-vs-streaming energy comparison on the same phone.
- No long-session thermal throttling curves for Edge0 or Routide.
