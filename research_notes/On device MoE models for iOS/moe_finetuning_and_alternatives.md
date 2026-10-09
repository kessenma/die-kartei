# Fine-tuning and deploying a Mixture-of-Experts model on device, and the non-MoE routes to a more capable phone model (as of October 2026)

Context these notes assume (from the brief): a solo developer trains on RunPod with Unsloth (LoRA, merged to fp16, then MLX 4-bit with a quant predicate that keeps Gemma 4's per-layer embeddings at higher precision, about 5.2 bpw effective). The fine-tuned Gemma 4 E4B German tutor scores about 83–90% on their German error suite, against 48–58% for general models. A ~2B model could not absorb the 15-phenomenon dataset, and dense ~3B was the floor where it paid off. RunPod spend is tracked in dollars.

Source-quality legend: [primary] = vendor docs, model cards, papers, source code; [secondary] = blogs and aggregators. Unmarked items come from primary sources.

---

## Q1. Fine-tuning an MoE with LoRA/QLoRA: tooling, which modules to target, router handling, VRAM, GPU cost, failure modes

### Takeaway
The tooling is mature as of 2026. Unsloth supports Qwen3-MoE, gpt-oss, GLM, DeepSeek and Gemma 4 26B-A4B with fused MoE kernels, and mlx-lm can LoRA the experts too. The settled practice is LoRA on attention plus expert MLPs, router frozen, and bf16 LoRA rather than 4-bit QLoRA (gpt-oss-20b is the exception). A 26–30B-total MoE needs a 40–80 GB GPU, so one run on RunPod costs a few dollars to a few tens of dollars. The main risks are a fragile router, forgetting when you use plain LoRA, and, for a German tutor, data that does not cover the expert routes German text takes.

### Cited Findings

**Unsloth: supported models, defaults, VRAM**
- Unsloth's MoE page names Qwen3 (30B-A3B, 235B, VL, Coder), gpt-oss (20B, 120B), GLM (4.5–4.7, 4.7-Flash) and DeepSeek (V3/R1/V3.1/V3.2) as supported. It adds: "We may have not uploaded some MoE models, but Unsloth should still support them." The new MoE Triton kernels (Feb 2026 release) claim about 12× faster MoE training, >35% less VRAM and about 6× longer context. Per-model speedups are smaller: Qwen3-30B-A3B 1.7–1.8×, gpt-oss-20B 7× at 16K context, GLM-4.7-Flash 2.1–2.6×. — [Unsloth: Fine-tune MoE Models 12x Faster](https://unsloth.ai/docs/basics/faster-moe)
- Default LoRA targets for MoE are `q_proj, k_proj, v_proj, o_proj, gate_up_proj, down_proj`, meaning attention plus the fused expert MLPs. The router is **disabled by default**: "it's not a good idea to fine-tune the router layer so we disabled it by default." — [Unsloth faster-moe](https://unsloth.ai/docs/basics/faster-moe); same statement in [Unsloth Qwen3 blog](https://unsloth.ai/blog/qwen3)
- QLoRA status for MoE: "Training MoE models in 4-bit QLoRA isn't recommended right now because BitsandBytes doesn't support it; for now, use bf16 for LoRA or full fine-tuning." — [Unsloth faster-moe](https://unsloth.ai/docs/basics/faster-moe)
- Measured VRAM, Unsloth vs Transformers v5:
  - gpt-oss-20B, bf16, 8K context: 47.43 GB vs 73.80 GB
  - gpt-oss-20b, 1K context: 40.91 GB
  - Qwen3-30B-A3B, 16-bit LoRA at rank 64: 63 GB (measured on a B200)
  - Source: [Unsloth faster-moe](https://unsloth.ai/docs/basics/faster-moe)
- The 2025 Qwen3 blog says Qwen3-30B-A3B "comfortably fits on 17.5GB of VRAM." That figure predates the "don't QLoRA MoE" guidance and appears to be a 4-bit load. — [Unsloth Qwen3 blog](https://unsloth.ai/blog/qwen3). **Conflict:** this is far below the 63 GB bf16 figure above, so treat 17.5 GB as a QLoRA-era number, not the recommended path.
- gpt-oss is the exception to "no MoE QLoRA". Unsloth emulates MXFP4 training with bitsandbytes NF4:
  - QLoRA: gpt-oss-20b 14 GB, gpt-oss-120b 65 GB
  - bf16 LoRA: 20b 44 GB, 120b 210 GB
  - Other libraries upcast to bf16, which costs about 300% more memory.
  - Merged export dequantizes to 16-bit (`save_pretrained_merged`). GGUF/vLLM export arrived in an Aug 28 (2025) update.
  - Source: [Unsloth gpt-oss guide](https://unsloth.ai/docs/models/gpt-oss-how-to-run-and-fine-tune)

**Gemma 4 26B-A4B (the MoE sibling of the user's E4B)**
- Unsloth's Gemma 4 guide gives these LoRA VRAM figures:
  - E2B: 8–10 GB
  - E4B: 17 GB
  - 26B-A4B: ">40GB"
  - 31B: QLoRA in 22 GB
- For 26B-A4B the guide says to prefer bf16 LoRA over full fine-tuning, set `load_in_4bit = False` ("MoE QLoRA not recommended"), and "use dense 31B if memory-constrained". It also advises to "start with shorter contexts and smaller ranks first." — [Unsloth Gemma 4 fine-tuning guide](https://unsloth.ai/docs/models/gemma-4/train)
- A secondary summary of the same Unsloth page says the 26B-A4B "requires an A100" and that "MoE routing and 4-bit quantization interact poorly." — search summary of [unsloth.ai/docs/models/gemma-4/train](https://unsloth.ai/docs/models/gemma-4/train) [secondary paraphrase]
- Model facts: 25.2B total, 3.8B active, 128 experts (8 active plus 1 shared), 30 layers, 256K context. Bf16 weights are about 52 GB on disk. — [google/gemma-4-26B-A4B-it model card](https://huggingface.co/google/gemma-4-26B-A4B-it); disk size from [0xSero/Gemma-4-21B card](https://huggingface.co/0xSero/Gemma-4-21B)

**mlx-lm (Mac-side LoRA)**
- mlx-lm has a `LoRASwitchLinear` layer that wraps both `SwitchLinear` and `QuantizedSwitchLinear`, the batched expert layers. LoRA can therefore target experts on a bf16 or a 4-bit MoE (QLoRA-style on Mac), and its `fuse` path reshapes the per-expert LoRA A/B back into a fused `SwitchLinear`. — [mlx-lm tuner/utils.py](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/tuner/utils.py), [mlx-lm tuner/lora.py](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/tuner/lora.py) (checked in source on 2026-10-01)
- Issue #571 (Oct 2025) reported LoRA on Qwen3-30B-A3B training only about 0.02% of parameters. The cause was user-supplied key names. The maintainer's fix was to use `mlp.switch_mlp.{gate,up,down}_proj` plus the `self_attn.*` projections, or to "leave the keys unset and it will LoRA every linear / MoE layer." — [mlx-lm issue #571](https://github.com/ml-explore/mlx-lm/issues/571)

**Router / load-balancing / forgetting evidence**
- ESFT (DeepSeek, 2024) studied DeepSeek-V2-Lite, a fine-grained-expert MoE. The expert count I fetched was garbled ("66 experts per layer", "162 non-shared"). My understanding is 2 shared plus 64 routed experts with 6 active, but that comes from prior knowledge, not this session, so re-check it in the PDF before relying on it.
  - On specialized tasks, LoRA averaged **44.9**, against **51.0** for full fine-tuning (FFT) and **50.2** for ESFT-Gate.
  - Retained general ability averaged LoRA 59.1, FFT 58.8, ESFT-Gate 60.6, ESFT-Token 61.5.
  - Routing for a given task is "highly concentrated" on a small subset of experts, and different tasks use different experts. Tuning only about 5–15% of experts matched FFT and forgot less.
  - The authors say the approach is less practical for coarse-grained MoEs such as Mixtral.
  - Source: [ESFT, arXiv 2407.01906](https://arxiv.org/html/2407.01906v2) (2024, older but still the main forgetting reference)
- A 2026 paper calls MoE router layers "fragile" under SFT. It says the existing fixes (DenseMixer; ESFT and auxiliary load-balancing losses) "introduce noisy gradients that often degrade performance," and finds that "even rarely activated experts encode non-trivial knowledge." Its auxiliary-loss-free method reports +2.5% on math and commonsense QA over prior baselines. — [Preserving Long-Tailed Expert Information in MoE Tuning, arXiv 2604.23036](https://paperswithcode.co/paper/2604.23036)
- Router collapse is the general MoE failure that auxiliary load-balancing losses were introduced to prevent. — [ICLR 2026 "Balancing the Experts" note](https://en.papernotes.org/ICLR2026/reinforcement_learning/balancing_the_experts_unlocking_lora-moe_for_grpo_via_mechanism-aware_rewards/) [secondary]

**RunPod prices (on-demand, page updated Sept 27, 2026)**

| GPU | Community $/hr | Secure $/hr |
|---|---|---|
| RTX 4090 | 0.34 | 0.74 |
| RTX 5090 | 0.69 | 0.99 |
| L40S | 0.79 | 1.09 |
| RTX Pro 6000 | 1.69 | 2.09 |
| A100 PCIe | 1.19 | 1.59 |
| A100 SXM | 1.39 | 1.59 |
| H100 PCIe | 1.99 | 2.89 |
| H100 SXM | 2.69 | 3.49 |
| H100 NVL | 2.59 | 3.19 |
| H200 | 3.59 | 4.59 |
| B200 | 5.98 | 6.79 |

Source: [RunPod pricing](https://www.runpod.io/pricing)

### Inferences
- **Recommended config for a German-tutor MoE LoRA:**
  - bf16 LoRA on attention plus expert MLPs (`gate_up_proj`/`down_proj`), router frozen, no auxiliary loss during SFT.
  - Rank 16–32 at first, short context.
  - A frozen router keeps the pretrained routing. Your German grammar data then adapts the experts that German text already reaches, instead of re-routing tokens. This is the cheapest guard against collapse.
  - ESFT's results suggest you could restrict LoRA to the experts German-tutor prompts actually route to. Tooling for that is not packaged in Unsloth (see Gaps).
- **mlx-lm trap:** "leave keys unset and it will LoRA every linear" probably includes the router. In Qwen3-MoE the router is a plain `nn.Linear` (`mlp.gate`), so leaving keys unset would quietly break the "router frozen" rule. When training MoE on a Mac, list the keys explicitly. This is inferred from the maintainer's comment plus the code structure. I did not verify which modules the default walk touches for Gemma 4's MoE.
- **GPU sizing:**
  - Gemma 4 26B-A4B or Qwen3-30B-A3B bf16 LoRA → one 80 GB card (A100 80GB at $1.19–1.59/hr, or H100 80GB at $1.99–3.49/hr). Qwen3 at r64 needed 63 GB, so an 80 GB card has headroom at r16–32.
  - gpt-oss-20b QLoRA (14 GB) fits an RTX 4090/5090 or L40S, but gpt-oss is a weak choice for German (see Q4f/Q5).
- **Cost per run (illustrative, not measured):**
  - Active parameters (3–4B) are about the same as E4B's effective 4.5B, so FLOPs per token are similar. Expert dispatch is less efficient, and Unsloth's MoE speedup on Qwen3-30B-A3B is only 1.7–1.8×.
  - Expect about 1.5–3× the wall-clock of an equivalent E4B run, on a card that costs about 1.5–4× more per hour.
  - If an E4B round takes 2 h on an L40S (about $1.60–2.20), a 26B-A4B round is roughly 3–6 h on an A100 80GB, about **$4–10**, or **$8–21** on an H100 SXM.
  - Budget extra for **disk**: about 52 GB bf16 download, plus a 52 GB merged fp16 export, plus checkpoints. Size the volume at 150–200 GB, and remember storage is billed while the pod idles.
- **Forgetting:** ESFT found that plain LoRA on a fine-grained MoE both under-fits the target task (−6 points vs FFT) and does not forget less. For a German tutor that must keep general German fluency, run the existing regression/eval suite on general German as well as the error suite after every MoE round.

### Gaps
- I did not verify Unsloth support for **Granite 4 MoE** or **LFM2/LFM2.5-MoE**. The MoE page lists only Qwen3/gpt-oss/GLM/DeepSeek, plus Gemma 4 on its own page, and says other MoEs "should" work.
- Not researched: **Hugging Face PEFT/TRL** (e.g., whether PEFT's `target_parameters` reaches fused `nn.Parameter` experts in Transformers v5) and **Axolotl** MoE support.
- No source gave **wall-clock time** for a 26B-A4B or 30B-A3B LoRA on a dataset of this size. The cost range above is extrapolated.
- No study found on **German or multilingual forgetting specifically after MoE SFT**. ESFT's general-ability numbers are the closest proxy.
- No ready-made tool found that does ESFT-style "train only the relevant experts" inside Unsloth or mlx-lm. DeepSeek's ESFT repo is the reference implementation (not checked for 2026 model support).

---

## Q2. After fine-tuning: merging LoRA into experts, quantizing (MLX mixed precision / DWQ, Unsloth dynamic / GGUF imatrix), and whether fine-tuning changes quantization sensitivity

### Takeaway
Merging into experts works in both Unsloth (dequantize-merge to 16-bit) and mlx-lm (`LoRASwitchLinear` fuse). MLX ships mixed-bit recipes plus AWQ/GPTQ/DWQ and dynamic-quant code paths. MoE quantization research agrees that attention, shared experts and early layers need more bits than routed experts, which also tolerate low bits better. I found **no direct evidence** on whether SFT makes MoE experts more or less quantization-sensitive. The practical rule is to calibrate any data-aware quantizer on in-domain German tutor text.

### Cited Findings
- **mlx-lm quantization tooling (source, checked 2026-10-01):**
  - `convert.py` has built-in mixed recipes `mixed_2_6`, `mixed_3_4`, `mixed_3_6` and `mixed_4_6`, built by a `mixed_quant_predicate_builder`, and accepts a custom `quant_predicate`.
  - `mlx_lm/quant/` contains `awq.py`, `dwq.py` (distilled weight quantization), `gptq.py` and `dynamic_quant.py`.
  - Source: [mlx-lm convert.py](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/convert.py), [mlx-lm quant directory](https://github.com/ml-explore/mlx-lm/tree/main/mlx_lm/quant)
- **mlx-lm LoRA fusion into experts:** `LoRASwitchLinear` fuses per-expert LoRA A/B (shape `num_experts × r × in`) into a `SwitchLinear`, and handles a `QuantizedSwitchLinear` base. — [mlx-lm tuner/lora.py](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/tuner/lora.py)
- **Unsloth export:** merged weights are dequantized to bf16 (`save_pretrained_merged`), and GGUF export offers q4_k_m, q8_0 and f16 for Gemma 4. — [Unsloth gpt-oss guide](https://unsloth.ai/docs/models/gpt-oss-how-to-run-and-fine-tune), [Unsloth Gemma 4 guide](https://unsloth.ai/docs/models/gemma-4/train)
- **MoE precision allocation findings:**
  - Attention layers need higher precision than FFN/expert layers.
  - Shared experts (seen by every token) need more bits than routed experts; one result suggests 4-bit shared and 2-bit routed experts.
  - Earlier MoE layers need more precision than later ones.
  - Quantizing attention to 2-bit makes the model "collapse entirely", while keeping attention at 4-bit "substantially mitigates" the loss.
  - Using a fine-tuned model gives more accurate expert-importance estimates for low-bit quantization.
  - Source: [QuantMoE-Bench, arXiv 2406.08155](https://arxiv.org/pdf/2406.08155) and [GEMQ, arXiv 2605.23078](https://arxiv.org/pdf/2605.23078), via a search-result summary that blends them. I did not trace each claim to a specific paper and table.
- **Expert weights tolerate low bits:** MoQE (2023, older) reports MoE expert layers are more robust to low-bit weight quantization than dense FFN layers. — [MoQE, arXiv 2310.02410](https://arxiv.org/pdf/2310.02410)
- **Active 2026 research on expert-wise mixed precision:** Q-Strata, BitsMoE, Colla-Q and MODE. — [Q-Strata 2608.30564](https://arxiv.org/pdf/2608.30564), [BitsMoE 2606.00079](https://arxiv.org/html/2606.00079v1), [Colla-Q 2609.18131](https://arxiv.org/pdf/2609.18131)
- **QLoRA-merge degradation:** merging adapters trained against a 4-bit base back into a quantized model causes "significant performance drop." This is the main fine-tune→quantize failure documented in general (dense) models, and the reason QAT and QA-LoRA exist. — [TACL: Accurate and Efficient Fine-Tuning of Quantized LLMs](https://direct.mit.edu/tacl/article/doi/10.1162/TACL.a.23/132118/Accurate-and-Efficient-Fine-Tuning-of-Quantized), [QA-LoRA explainer](https://kaitchup.substack.com/p/qa-lora-quantization-aware-fine-tuning) [secondary]
- **Routing concentrates after domain specialization:** a task's tokens use a small subset of experts. — [ESFT](https://arxiv.org/html/2407.01906v2)

### Inferences
- **Keep the user's current pipeline** (bf16 LoRA → merge to fp16 → quantize). It avoids the documented QLoRA-merge failure. For an MoE, extend the quant predicate in the direction the MoE literature points:
  - 6–8 bit: attention, shared expert, router/gate, embeddings, and the first few layers.
  - 4-bit or lower: routed experts.
  - The `mixed_4_6` recipe is the closest built-in. A custom predicate keyed on `switch_mlp` vs everything else is the precise version.
- **Calibration data:** fine-tuning concentrates routing on a subset of experts (ESFT). Data-aware quantizers (DWQ, AWQ, GPTQ, llama.cpp imatrix, Unsloth dynamic quants) must therefore be calibrated on German tutor prompts. Generic English calibration would under-weight exactly the experts the fine-tune made important. This is an inference; no paper tests it on a fine-tuned MoE.
- **Sensitivity in either direction is plausible:**
  - More sensitive: the experts the fine-tune leans on now carry most of the task signal.
  - Less sensitive: routed experts are robust (MoQE), and a frozen router cannot drift.
  - The user's own eval suite is the only reliable arbiter. Quantize at two or three bit allocations, run the 83–90% error suite on each, and compare before choosing.

### Gaps
- No paper or benchmark found that measures **quantization sensitivity of a LoRA-fine-tuned MoE vs its base**.
- I did not confirm whether **DWQ works on MoE (SwitchLinear) layers** in mlx-lm. The file exists, but I did not check that it handles `SwitchLinear`.
- I did not fetch details of **Unsloth Dynamic 2.0** behaviour on MoE layers (e.g., which expert tensors it keeps at higher bits).

---

## Q3. Shrinking an MoE to phone size: expert pruning (REAP etc.), merging, language-specific pruning, distillation, and the device-fit arithmetic

### Takeaway
REAP-style one-shot expert pruning is the best documented method:
- About 25% of experts can go with only a few points lost.
- At 50% the loss is noticeable on knowledge tasks (about −13% on multiple-choice) and depends heavily on calibration domain.
- Pruning "to the German experts" is a weak lever: German, a high-resource language, uses few exclusive experts and relies on shared ones.

Even pruned 50% and quantized to 4-bit, a 26–30B MoE is still about 7–9 GB, which is at or past the practical limit on a 12 GB iPhone. The phone-sized MoE class is the ~8B-total LFM2.5-8B-A1B, not Gemma 4 26B or Qwen3-30B.

### Cited Findings
- **REAP (Cerebras, ICLR 2026):** the pruning score multiplies the router gate value by the expert's output norm. Results:
  - Multiple-choice accuracy loss is about 4% at 25% compression and about 13% at 50% (excluding the largest models).
  - On Qwen3-30B code generation it loses 2.8% at 25% and 8.0% at 50%; the merging methods HC-SMoE/M-SMoE lose >20% at 50%.
  - Math loses a 1.1% mean at 50%. Creative writing is near-lossless at 25%.
  - Qwen3-Coder-480B at 50%: −1.4% on non-agentic coding, −5.9% on tool use.
  - Merging beats pruning on multiple-choice tasks but loses on generative ones.
  - **Calibration domain matters a lot:** with C4 (generic) calibration, "several compressed model instances fail[ed] to produce coherent outputs, resulting in 0% accuracy" on code.
  - The paper has no multilingual evaluation.
  - Sources: [REAP arXiv 2510.13999](https://arxiv.org/html/2510.13999v1), [ICLR 2026 poster](https://iclr.cc/virtual/2026/poster/10006871), [Cerebras repo](https://github.com/CerebrasResearch/reap); REAP is also in [vLLM llm-compressor](https://docs.vllm.ai/projects/llm-compressor/en/latest/examples/reap_expert_pruning/)
- **Gemma 4 REAP (community):** `0xSero/gemma-4-21b-a4b-it-REAP` prunes 20% of experts (128→103 per layer) and shrinks bf16 from about 52 GB to 43 GB. It was calibrated on 22K **English-only** samples (code, math, reasoning, tools, biomed). Before/after on 50 samples per task:
  - GSM8K 86→84
  - Elementary math 92→90
  - Philosophy 92→88
  - **World Religions 90→64**
  - College CS 56→76 (noise)
  - Source: [0xSero/Gemma-4-21B](https://huggingface.co/0xSero/Gemma-4-21B) [community, small-n]
- **Official REAP checkpoint:** `cerebras/Qwen3-Coder-REAP-25B-A3B` prunes 20% (128→103 experts). — [HF card](https://huggingface.co/cerebras/Qwen3-Coder-REAP-25B-A3B)
- **Language-specific experts (Qwen3-30B-A3B, 2026):**
  - Dominant languages (en/zh) have the most exclusive experts. High-resource languages "rely on remarkably few language-exclusive experts."
  - Exclusive experts follow a U shape by depth: early (layers 0–4) and late (43–47).
  - Masking **German**'s exclusive experts changed accuracy by **−3.2% (early layers), +1.2% (middle), +1.6% (late)**. For contrast, masking Bengali's early experts cost −31.2%, and late masking collapsed Bengali consistency by −72.8%.
  - Source: [Understanding Multilingualism in MoE LLMs, arXiv 2601.14050](https://arxiv.org/html/2601.14050)
- **Language-specific pruning in machine translation:** about 80% of NLLB-200's experts were removed without fine-tuning, with negligible translation loss (2022, encoder-decoder MT; older and a different setting). — [Memory-efficient NLLB-200, arXiv 2212.09811](https://arxiv.org/html/2212.09811v3)
- **Rare experts matter:** "even rarely activated experts encode non-trivial knowledge useful for downstream tasks." — [arXiv 2604.23036](https://paperswithcode.co/paper/2604.23036)
- **Device data points** (iPhone 17 Pro, 12 GB RAM; the source budgets about 70% of RAM for models):

  | Model | Footprint | Speed |
  |---|---|---|
  | Gemma 4 E4B | about 4 GB | about 12 tok/s |
  | LFM2.5-8B-A1B | 5.5 GB | about 16 tok/s |
  | Qwen3 8B | 6.5 GB | about 7 tok/s |
  | Qwen3.5-4B (Q8) | 4.3 GB | about 8 tok/s |
  | Qwen3.5-9B (Q8) | 10.7 GB | "more than this device's comfortable budget" |

  Source: [ModelFit iPhone 17 Pro](https://modelfit.io/iphone-17-pro/) [secondary; figures are estimates]. Another secondary source puts E4B at about 30 tok/s on the same phone, so throughput figures conflict across sources. — [ModelFit Gemma 4 page](https://modelfit.io/iphone/iphone-17-pro/) [secondary]
- **SSD expert streaming:** a 400B-parameter MoE ran on an iPhone 17 Pro by streaming weights from SSD at about **0.6 tok/s**. — reported in [TweakTown](https://www.tweaktown.com/news/110610/the-iphone-17-pro-can-run-a-400b-parameter-large-language-model-on-device-by-streaming-weights-from-the-ssd/index.html) / [MacObserver](https://www.macobserver.com/news/developer-runs-400b-ai-model-on-iphone-17-pro-that-needs-200gb-ram/) [secondary; I could not open the primary write-up (HTTP 403)]

### Inferences
- **Device-fit arithmetic** (weights only, about 4.5 bpw for 4-bit with group scales; KV cache and runtime extra):

  | Model | Total params | 4-bit size | Fit |
  |---|---|---|---|
  | Gemma 4 26B-A4B | 25.2B | ≈ 14 GB | does not fit a 12 GB iPhone |
  | + REAP 20% | ≈ 21B | ≈ 12 GB | no |
  | + REAP 50% (attention/embeddings unpruned) | ≈ 13–14B | ≈ 7.5–8 GB | at the edge of the about 8 GB budget, with little room for KV cache or the app's other heavy residents |
  | Qwen3-30B-A3B | 30.5B | ≈ 17 GB | no |
  | gpt-oss-20b (MXFP4) | about 21B | about 12–13 GB | no |
  | Gemma 4 12B dense | 12B | ≈ 6.7 GB | ≈ Qwen3 8B class |
  | LFM2.5-8B-A1B | 8B | 5.5 GB measured | yes |

  A 16 GB iPad or a Mac could host the 26B-A4B at 3–4 bit.
- **50% pruning plus 4-bit plus fine-tuning stacks three lossy steps.** REAP's −13% multiple-choice at 50% hits knowledge, and a tutor needs knowledge for explanations. If you try it:
  - Calibrate REAP on German tutor conversations, since generic calibration produced 0% outputs in REAP's own tests.
  - Prune **before** LoRA, so the fine-tune can repair damage.
  - Re-run the full error suite.
- **"Keep only experts that fire on German" is a weak strategy** for this user. German has few exclusive experts and masking them barely matters, so a German-only prune cannot remove much. The savings would have to come from *task* specificity (ESFT-style routing concentration), which is what REAP with German-tutor calibration measures anyway.
- **SSD expert streaming** (0.6 tok/s for 400B) is a demo, not a tutor UX. At 26B scale it might reach usable speeds, but no measurement was found.

### Gaps
- No REAP or MoE-pruning results found for **German or any multilingual generative task**.
- No measured **iPhone tok/s or memory for Gemma 4 26B-A4B, Qwen3-30B-A3B or gpt-oss-20b** (pruned or not). I found no authoritative per-app iOS memory limit (jetsam / increased-memory-limit entitlement ceiling) for 12 GB devices.
- I did not research **MoE→dense distillation** (collapsing experts into a dense student) as a separate technique. In practice, "distill a big MoE teacher into E4B" (Q4c) covers the same goal.

---

## Q4. Non-MoE routes to more on-device capability

### Takeaway
- **(a)** Gemma 4 has no larger "E" model. The family is E2B, E4B, a dense 12B (June 2026) that Google says nears the 26B MoE, the 26B-A4B MoE, and a 31B dense. On published benchmarks the 26B-A4B is far above E4B, but it does not fit a phone.
- **(b)** Speculative decoding is supported in MLX Swift and Apple's adapter toolkit and gives speed, not intelligence.
- **(c)** Distilling a large teacher into E4B is the cheapest proven lever.
- **(d)** Apple's Foundation Models adapters are a different, smaller (about 3B) base, with a heavy per-OS retraining tax and an iOS 27 toolkit gap.
- **(e)** A hybrid with Apple's Private Cloud Compute became nearly free for small developers at WWDC26.
- **(f)** The strongest new phone-sized models are LFM2.5-8B-A1B (a small MoE) and Qwen3.5-4B. Neither is shown to beat Gemma 4 E4B on German.

### Cited Findings

**(a) Gemma 4 family**
- Released April 2, 2026 in E2B, E4B, 26B MoE and 31B dense. — [Google blog](https://blog.google/innovation-and-ai/technology/developers-tools/gemma-4/), [Wikipedia](https://en.wikipedia.org/wiki/Gemma_(language_model)) [secondary]
- Parameter sizes:
  - E2B: 2.3B effective (5.1B with embeddings)
  - E4B: 4.5B effective (8B with embeddings)
  - 26B-A4B: 25.2B total, 3.8B active
  - 31B: 30.7B
  - E2B/E4B use per-layer embeddings, 128K context and a 512-token sliding window. Larger models have 256K context.
  - "Out-of-the-box support for 35+ languages, pre-trained on 140+."
  - Source: [Gemma 4 26B-A4B model card](https://huggingface.co/google/gemma-4-26B-A4B-it)
- Benchmarks (same model card):

  | Benchmark | E2B | E4B | 26B-A4B | 31B |
  |---|---|---|---|---|
  | MMLU-Pro | 60.0 | 69.4 | 82.6 | 85.2 |
  | GPQA Diamond | 43.4 | 58.6 | 82.3 | 84.3 |
  | **MMMLU (multilingual)** | 67.4 | 76.6 | **86.3** | 88.4 |

  Source: [model card](https://huggingface.co/google/gemma-4-26B-A4B-it)
- **Gemma 4 12B** (June 3, 2026): 11.95B dense, a unified encoder-free multimodal design (text, image, audio), 48 layers, 256K context, Apache 2.0. It targets "a laptop with roughly 16 GB." Google says it delivers "performance nearing our larger 26B MoE model" at "less than half the total memory footprint," and it ships **Multi-Token Prediction drafters**. The blog gives no per-benchmark numbers. — [Google: Introducing Gemma 4 12B](https://blog.google/innovation-and-ai/technology/developers-tools/introducing-gemma-4-12b/); release details also in [NYU Shanghai RITS](https://rits.shanghai.nyu.edu/ai/google-releases-gemma-4-12b-frontier-multimodal-ai-on-a-laptop/) [secondary]

**(b) Speculative decoding**
- Apple's adapter toolkit can optionally train a **draft model for on-device speculative decoding** paired with the adapter (`train_draft_model`). It warns: "If no speedup observed, retrain with different hyperparameters." — [Apple Foundation Models adapter page](https://developer.apple.com/apple-intelligence/foundation-models-adapter/)
- MLX Swift has a native speculative-decoding implementation; typical claimed speedup is 2–3× with identical output distribution. — [mlx-community/speculative-decoding](https://github.com/mlx-community/speculative-decoding), [omr.it.com explainer](https://omr.it.com/blog/speculative-decoding-mobile-llms-speedup/) [secondary; the 2–3× figure is generic, not measured on iPhone with Gemma 4]
- Gemma 4 12B ships MTP drafters. — [Google 12B blog](https://blog.google/innovation-and-ai/technology/developers-tools/introducing-gemma-4-12b/)

**(c) Distillation into E4B**
- The user's own data already shows the effect (83–90% vs 48–58% for general models). That number comes from the brief, not a public source.
- ESFT-style evidence that task routing is concentrated also implies a big teacher's task behaviour is "narrow" enough to transfer. — [ESFT](https://arxiv.org/html/2407.01906v2)

**(d) Apple Foundation Models + adapters**
- **WWDC26 / iOS 27:**
  - A "new on-device model, rebuilt from the ground up," "better at logic and tool calling," with image understanding.
  - `SystemLanguageModel.contextSize` = **8192** (iOS 26.4+).
  - The session does not state parameter count or languages.
  - Source: [WWDC26 "What's new in the Foundation Models framework"](https://developer.apple.com/videos/play/wwdc2026/241/)
  - Secondary sources describe it as "roughly 3-billion-parameter." — [ChatForest iOS 27 guide](https://chatforest.com/builders-log/apple-foundation-models-ios-27-on-device-llm-api-builder-guide/), [dev.to](https://dev.to/arshtechpro/wwdc-2026-apple-just-opened-the-foundation-models-framework-to-any-llm-provider-5ejn) [secondary]
- **Adapter toolkit:**
  - LoRA adapters (search summary says rank 32).
  - About **160 MB per adapter**, delivered via Background Assets, not bundled.
  - Each adapter is "compatible with a single specific system model version," so you must "train a different adapter for every version of the system model."
  - Needs the `com.apple.developer.foundation-model-adapter` entitlement.
  - Trains on a Mac with Apple silicon and ≥32 GB, or a Linux GPU.
  - Suggested data: 100–1,000 samples for basic tasks, 5,000+ for complex ones.
  - Supports "all languages supported by Apple Intelligence."
  - **Toolkit 26.0.0 is the last listed release and "NOT compatible with OS 27+."**
  - Apple's own advice is to try prompting and tool calling first.
  - Source: [Apple adapter page](https://developer.apple.com/apple-intelligence/foundation-models-adapter/)
- **`LanguageModel` protocol (iOS 27):** `SystemLanguageModel`, `PrivateCloudComputeLanguageModel`, an open-sourced `CoreAILanguageModel` (Neural Engine) and `MLXLanguageModel` (Mac GPU), plus Anthropic and Google Swift packages. — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)

**(e) Hybrid on-device + cloud**
- **Private Cloud Compute for developers (iOS 27):**
  - 32K context, configurable reasoning levels.
  - No account or API key.
  - **Free tier for developers with <2 million first-time downloads**; daily limits, higher for iCloud+ subscribers.
  - Needs an entitlement.
  - Source: [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- Third-party cloud models plug into the same `LanguageModelSession` API with OAuth and per-token billing. — same source

**(f) Newer small models**
- **LFM2.5-8B-A1B** (May 28, 2026):
  - 8B total, about 1B active, 128K-vocabulary tokenizer, "~30 tokens/s on a phone."
  - Day-one support in llama.cpp, MLX, vLLM and SGLang.
  - Beats Qwen3.5-4B on MATH500 (88.76 vs 80.76) and Gemma-4-E2B on non-hallucination (63.47 vs 15.05).
  - No German metrics were reported.
  - Source: [Liquid AI blog](https://www.liquid.ai/blog/lfm2-5-8b-a1b)
- **LFM2-8B-A1B** (Oct 2025, predecessor):
  - 8.3B total, 1.5B active. "Matches 3–4B dense model quality."
  - Supports English, Arabic, Chinese, French, **German**, Japanese, Korean and Spanish.
  - Pre-training mix about 75% English and 20% multilingual.
  - **MMMLU 55.26**, MGSM 72.4.
  - Source: [LFM2-8B-A1B HF card](https://huggingface.co/LiquidAI/LFM2-8B-A1B), [Liquid AI blog](https://www.liquid.ai/blog/lfm2-8b-a1b-an-efficient-on-device-mixture-of-experts)
- **Qwen3.5-4B** exists and runs on iPhone 17 Pro (about 4.3 GB at Q8). — [ModelFit](https://modelfit.io/iphone-17-pro/) [secondary]; benchmark comparison in [Liquid AI blog](https://www.liquid.ai/blog/lfm2-5-8b-a1b)

### Inferences
- **(a)** The 26B-A4B's MMMLU lead over E4B (+9.7 points) is the strongest public signal that a bigger MoE "knows more German." It does not fit a 12 GB phone (Q3 arithmetic). Its realistic roles:
  1. **Teacher** for distillation data.
  2. **Optional tier** on 16 GB+ iPads and Macs, which the user's macOS port could use.
  3. **Server model.**

  Gemma 4 12B dense, at about 6.7 GB in 4-bit, is the nearest "bigger Gemma" that might fit a 12 GB phone. It is unmeasured, would break the user's one-heavy-resident memory budget unless it replaces E4B outright, and gives up PLE offloading. Test it on an iPad first.
- **(b)** Speculative decoding buys **latency**, not capability. On a phone it costs extra RAM for the draft. It is worth it only if E4B's speed is the bottleneck for a bigger target (e.g., 12B plus an E2B draft on iPad). Gemma 4 12B's bundled MTP drafters are the cheapest path if MLX Swift supports Gemma MTP (unverified).
- **(c)** Distillation is the best dollars-per-quality lever. The user's 2B dilution result says capacity matters, but E4B (8B with embeddings) already clears the floor. Generating more and harder German data from a 26B-A4B/31B teacher (or a frontier API), with programmatic validation, targets the remaining 10–17% error gap without changing the deployed footprint. The training cost stays at E4B prices (L40S/4090 class, $0.34–1.09/hr).
- **(d)** Apple FM adapters do not fit this app well today:
  - A smaller base (about 3B, which the user found to be the floor).
  - An 8K context.
  - Retraining and re-shipping about 160 MB adapters for **every** system model version.
  - No public OS-27-compatible toolkit yet (as of the adapter page fetched 2026-10-01).

  Upside: zero model download and no RAM charged to the app. That makes it a candidate for a zero-download "lite tutor" tier on devices that cannot run E4B, not a replacement.
- **(e)** A hybrid is now very cheap. PCC is free under 2M first-time downloads, so heavy, non-latency-critical jobs (story generation, long explanations, Kasus stories) could route to PCC through the same `LanguageModelSession` API, with E4B kept for offline and low-latency correction. Caveats: PCC is Apple's model, not the user's fine-tune; daily limits apply; and it changes the app's privacy/offline story.
- **(f)** LFM2.5-8B-A1B is the one MoE that actually fits a phone well (5.5 GB). Its predecessor's MMMLU (55.3) is far below E4B's (76.6, possibly a different harness), and its pretraining is 75% English. It is unlikely to beat a fine-tuned E4B on German without heavy fine-tuning. Still, it is cheap to test (8B bf16 LoRA fits a 24–48 GB card).

### Gaps
- No **German-specific benchmark** for Gemma 4 12B, LFM2.5-8B-A1B or Qwen3.5-4B.
- I did not verify **MLX Swift support for Gemma 4 MTP drafters** or any measured iPhone speedup from speculative decoding with Gemma 4.
- **Parameter count, language list and German quality** of the iOS 27 Apple on-device model are not stated in Apple's WWDC26 session. The "~3B" figure is secondary. I did not find whether an OS-27 adapter toolkit has shipped (the page lists 26.0.0 as last).
- **PCC daily limits** for the free tier are not quantified in the source.
- I did not research other 2026 dense small models (e.g., Ministral, Granite 4 dense, Phi) for German.

---

## Q5. Realistic expected gain: does a fine-tuned ~30B-A3B MoE beat a fine-tuned dense 4–8B on narrow tasks like (German) grammatical error correction?

### Takeaway
I found **no head-to-head evidence** of a fine-tuned 26–30B-total MoE vs a fine-tuned dense 4–8B on GEC or any comparable narrow task, in German or otherwise. The indirect evidence supports a real gain:
- Gemma 4 26B-A4B leads E4B by +9.7 MMMLU points.
- MoE fine-tunes can match full fine-tunes when done well.
- An older seq2seq GEC MoE matched a dense model with 3× the active parameters.

That gain is mostly unreachable on a 12 GB iPhone. For the user's suite, a reasonable expectation is a few points of headroom above 83–90% from a bigger model, against a similar or larger gain from better distillation data into E4B.

### Cited Findings
- **MoECE (2024, older; T5-based seq2seq, English GEC):**
  - MoECE-GS-Large matched T5-XL "despite having three times fewer effective parameters (1B vs 3B)."
  - Gains over dense baselines were +0.43 to +1.32 F0.5 on CoNLL-2014 and BEA-2019.
  - Source: [Efficient and Interpretable GEC with MoE, arXiv 2410.23507](https://arxiv.org/pdf/2410.23507)
- **Multilingual GEC with a single LLM up to 9B (2025):** 17 models were tested on English, German, Italian and Swedish. All were dense; no MoE was included. A search summary says Qwen 2.5 scored best on German. — [arXiv 2505.06004 / MT Summit 2025](https://arxiv.org/pdf/2505.06004) (I could not extract the per-model German F0.5 table from the PDF)
- **German GEC with synthetic errors:** beat prior SOTA by 0.8–6 F0.5. — search summary of [arXiv 2506.13148](https://arxiv.org/pdf/2506.13148v1) [not verified in full text]
- **Minimal-edit GEC with LLMs:** edit-wise preference optimization (EPO) beats plain SFT. — [BEA 2025](https://aclanthology.org/2025.bea-1.9.pdf)
- **Gemma 4 MMMLU:** E4B 76.6 vs 26B-A4B 86.3 vs 31B 88.4. — [model card](https://huggingface.co/google/gemma-4-26B-A4B-it)
- **ESFT:** properly targeted MoE fine-tuning matches FFT (50.2 vs 51.0 average); plain LoRA lags (44.9). — [ESFT](https://arxiv.org/html/2407.01906v2)
- **LFM2-8B-A1B:** claims "3–4B dense quality" from a 1.5B active path, so a small MoE buys roughly a 2× active-parameter equivalence, not a size class jump. — [Liquid AI](https://www.liquid.ai/blog/lfm2-8b-a1b-an-efficient-on-device-mixture-of-experts)
- No direct comparison of fine-tuned Qwen3-30B-A3B vs Qwen3-8B on the same narrow task was found in a targeted search. — [search attempt, e.g. SiliconFlow comparison page](https://www.siliconflow.com/models/compare/qwen3-30b-a3b-vs-qwen3-8b) [secondary; base-model comparison only]

### Inferences
- **Why a bigger MoE could help this specific dataset:**
  - The user's failure mode at 2B was *breadth dilution* (15 phenomena), which is a capacity limit.
  - MoE total parameters add storage capacity at constant per-token compute, the mechanism that should relieve dilution.
  - The 26B-A4B's +9.7 MMMLU suggests more German/world knowledge for explanations.
- **Why the realized on-device gain is likely small:**
  1. The 26B/30B MoEs do not fit a 12 GB phone without about 50% pruning plus 4-bit, and each costs measurable quality (REAP −13% multiple-choice at 50%).
  2. The MoE that does fit (LFM2.5-8B-A1B) has a 1B active path and English-heavy pretraining. That is close to the regime where the user saw dilution, and its multilingual knowledge (MMMLU 55) trails E4B.
  3. The user is already at 83–90%. The remaining errors may be data/label issues or hard phenomena that more data addresses more cheaply than more parameters.
- **Cheapest decisive experiments, in order:**
  1. **Teacher ceiling:** bf16-LoRA Gemma 4 26B-A4B on the existing dataset, about $5–20 on an A100/H100 80GB, and run the error suite in fp16 and in 4-bit with the MoE-aware predicate (on a Mac).
     - If it does not beat E4B by a clear margin (e.g., >5 points), stop: no MoE route will pay off on the phone.
     - If it does, use it as the distillation teacher, and consider it as an iPad/Mac tier.
  2. **Phone-sized MoE:** LoRA LFM2.5-8B-A1B on the same data (a few dollars on a 24–48 GB card), MLX 4-bit, and compare against E4B on the suite plus a general-German regression check.
  3. Only if (1) wins big and a phone tier is essential: REAP the fine-tuned 26B-A4B to about 50% with German-tutor calibration, quantize with attention/shared/early layers at higher bits, and measure both quality and peak RAM on an actual 12 GB device.
- These recommendations follow the user's "measure before gating" preference: no fixed thresholds are pre-committed beyond a suggested ballpark, and the eval suite decides.

### Gaps
- **No published study compares fine-tuned MoE vs dense LLMs on GEC** (German or any language). The only MoE-GEC evidence is a 2024 T5-based model.
- The German per-model numbers in the 2025 multilingual GEC study could not be extracted.
- No public data on how much of a ~10-point MMMLU advantage carries into a narrow fine-tuned task once both models are fine-tuned. Benchmark gaps often shrink after task-specific fine-tuning, but I found no source quantifying this for MoE vs dense.
