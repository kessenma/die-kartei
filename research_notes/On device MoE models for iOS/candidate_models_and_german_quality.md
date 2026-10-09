# On-device MoE candidates (as of Oct 2026) and how good they are at German

Scope: open-weight models that could replace or sit above the app's fine-tuned Gemma 4 E4B tutor (MLX 4-bit, ~2.7 GB on disk, ~4.3 GB peak RAM) on an iPhone 17 Pro (12 GB) or an 8 GB iPad. The section on the 6 GB per-app ceiling (Q5) changes the size budget the brief assumed, so read it first.

Legend: rows marked **[recalled]** come from model cards I know from before this session. I did not re-fetch them this session, so re-check them before relying on them. All other rows were fetched or searched this session.

---

## Q1. Which MoE models have a total size and active-parameter count that are plausible for a phone (≤ ~35B total, ≤ ~4B active)?

### Takeaway
Gemma 4 does include an MoE: **Gemma 4 26B-A4B** (25.2B total, 3.8B active, Apache 2.0, April 2026). It and **Qwen3.5/3.6-35B-A3B** are the strongest small MoEs by far. Both are 14–20 GB at 4-bit, so neither can sit in RAM on any iPhone. They would need expert streaming from flash. The MoEs that do fit in RAM are 6–8B total with 1–1.5B active: LFM2-8B-A1B, Ling-3.0-tiny, Phi-mini-MoE, Granite-4.0-h-tiny, Trinity Nano and MobileMoE. Their active-parameter counts are below the ~3B dense capacity floor the project measured.

### Cited Findings

**Candidate table (MoE)**

| Model | Total / active | Architecture | Context | License | Released | Key general / multilingual scores | Source |
|---|---|---|---|---|---|---|---|
| **Gemma 4 26B-A4B** | 25.2B / 3.8B | MoE, 30 layers, 128 experts, 8 active + 1 shared, 1024 sliding window; text + image (no audio) | 256K | Apache 2.0 | 2 Apr 2026 | MMLU-Pro 82.6, GPQA-D 82.3, **MMMLU 86.3**, LiveCodeBench v6 77.1; Arena text 1441 Elo (#6 at launch) | [HF card](https://huggingface.co/google/gemma-4-26B-A4B-it); [launch coverage](https://www.gigazine.net/gsc_news/en/20260403-google-released-gemma-4); [techwyse](https://www.techwyse.com/news/ai-search/google-deepmind-gemma-4-open-models-apache-2-0-release) |
| **Qwen3.5-35B-A3B** | 35B / 3B | Gated DeltaNet (linear attention) + gated attention hybrid, 40 layers, 256 experts, 8 routed + 1 shared; native vision | 262K (to ~1M) | Apache 2.0 | 24–26 Feb 2026 | MMLU-Pro 85.3, IFEval 91.9, **MMMLU 85.2, MMLU-ProX 81.0**, INCLUDE 79.7, Global PIQA 86.6, WMT24++ 76.3, MAXIFE 86.6; supports 201 languages | [HF card](https://huggingface.co/Qwen/Qwen3.5-35B-A3B); [release-date note](https://apxml.com/models/qwen35-35b-a3b) |
| **Qwen3.6-35B-A3B** | 35B / ~3B | Same layout as 3.5 (256 experts, 8 + 1 shared), multimodal | 262K (to ~1.01M) | Apache 2.0 | Apr 2026 | Coding-focused update, "surpassing Qwen3.5-35B-A3B by a wide margin" in agentic coding. I found no multilingual numbers | [dsebastien](https://www.dsebastien.net/qwen3-6-35b-a3b/); [quintarelli](https://blog.quintarelli.it/2026/04/qwen3-6-35b-a3b-il-nuovo-modello-open-weights-di-alibaba/) |
| Qwen3-30B-A3B **[recalled]** | 30.5B / 3.3B | 48 layers, 128 experts, top-8 | 32K (131K YaRN) | Apache 2.0 | Apr 2025 | Claims 119 languages | [HF card](https://huggingface.co/Qwen/Qwen3-30B-A3B) |
| **gpt-oss-20b** | 21B / 3.6B | MoE with MXFP4 expert weights. **[recalled]** 32 experts, top-4, 128K context | 128K **[recalled]** | Apache 2.0 | 5–8 Aug 2025 | GPQA-D 58.6; **MMMLU 14-language average 75.7 (high) / 73.5 (medium) / 67.0 (low); German 78.7 / 77.2 / 71.4**; "runs within 16GB of memory" | [HF card](https://huggingface.co/openai/gpt-oss-20b); [model card PDF](https://arxiv.org/pdf/2508.10925) |
| **LFM2-24B-A2B** | 24B / 2.3B | Hybrid gated short-conv + GQA (30 conv + 10 attention layers) | 32K | LFM Open License v1.0 | 24–25 Feb 2026 | Supports **9 languages including German**; card has throughput charts but no accuracy table; "fits within 32 GB of RAM" | [HF card](https://huggingface.co/LiquidAI/LFM2-24B-A2B); [OpenRouter id 20260224](https://openrouter.ai/liquid/lfm-2-24b-a2b-20260224); [Liquid docs](https://docs.liquid.ai/lfm/models/lfm2-24b-a2b) |
| **LFM2-8B-A1B** | 8.3B / 1.5B | 18 conv + 6 attention layers, MoE | 32K | LFM Open License v1.0 | late 2025 (card cites a 28 Nov 2025 report) | MMLU 64.8, MMLU-Pro 37.4, GSM8K 84.4, **MMMLU 55.26, MGSM 72.4**. Languages: EN, AR, ZH, FR, **DE**, JA, KO, ES | [HF card](https://huggingface.co/LiquidAI/LFM2-8B-A1B) |
| **Ling-3.0-tiny** (inclusionAI) | 7.9B / 1.3B | Kimi Delta Attention + MLA hybrid (3:1), 128 experts, 8 routed + 1 shared | 256K | MIT | 6 Aug 2026 | Artificial Analysis Intelligence Index 25; official INT4 checkpoint; 86–90 tok/s FP8 on an M4 Pro MacBook. **No language list or German claim** | [HF card](https://huggingface.co/inclusionAI/Ling-3.0-tiny); [release post](https://0dev.duckdns.org/en/posts/inclusionai-releases-ling-3-0-tiny-a-fast-local-moe-model); [INT4](https://huggingface.co/inclusionAI/Ling-3.0-tiny-int4) |
| **Edge0-35B-A3B-preview / Edge0-8B-A1B-preview** | 35B / 3B; 8B / ~1.3B | Fine-tunes of Qwen3.5-MoE and Ling-3.0-tiny, shipped with a runtime that streams experts from SSD, a "prerouter" head and a Recover-LoRA | (base) | Apache 2.0 | 10 Sep 2026 | 4-bit. 35B: 2.9 GB peak memory, 14.9–17.7 tok/s on M4 Pro, benchmark score **79.2 vs 83.2 for the base**. 8B: ~1 GB (3.3 GB at a 3.3K-token context), 23.9–25.3 tok/s, **69.9 vs 72.7**. Runs on macOS/MLX only; the 1–2.5 GB iPhone claim is unverified. Nothing on German | [runtimewire](https://runtimewire.com/article/edge0-open-source-35b-model-streaming-inference); [mer.vin](https://mer.vin/news/edge0-runs-a-35b-parameter-moe-model-in-under-3gb-of-ram/) |
| **Granite-4.0-h-tiny** | ~7B / ~1B | Mamba-2 / transformer hybrid MoE | long context | Apache 2.0 | Oct 2025 | MMLU 66.8, MMLU-Pro 32.0 (from Liquid's comparison table). 12 languages **including German** | [llmreference](https://www.llmreference.com/model/granite-4.0-h-tiny); [LFM2-8B-A1B card table](https://huggingface.co/LiquidAI/LFM2-8B-A1B) |
| Granite 4.1 / 4.2 | (dense, not MoE) | IBM **went back to dense** in 4.1 (3B / 8B / 30B, up to 512K context, 29 Apr 2026). 4.2-3B (25 Aug 2026) is a dense reasoning retrain | — | Apache 2.0 | 2026 | The 8B instruct "matches or beats" the Granite 4.0 32B MoE | [NYU RITS](https://rits.shanghai.nyu.edu/ai/ibm-releases-granite-4-1-dense-8b-matches-prior-32b-moe-flagship/); project scoreboard `training/MODEL_SCOREBOARD.md` |
| **Phi-mini-MoE / Phi-tiny-MoE** | 7.6B / 2.4B; 3.8B / 1.1B | Built with SlimMoE: compressed from Phi-3.5-MoE (41.9B / 6.6B) using 400B tokens | **[recalled]** 4K | MIT | mid-2025 (paper Jun 2025) | No multilingual claims found | [SlimMoE paper](https://arxiv.org/abs/2506.18349v1); [HF](https://huggingface.co/microsoft/phi-mini-moe-instruct) |
| **SmallThinker-21B-A3B / 4B-A0.6B** | 21B / 3B; 4B / 0.6B | Built for local deployment (Shanghai Jiao Tong IPADS + Zenergize) | — | Apache 2.0 | Jul 2025 | >20 tok/s on consumer CPUs at Q4_0 using **8 GB / 1 GB** of memory | [paper](https://huggingface.co/papers/2507.20984) |
| **Trinity Nano** (Arcee) | 6B / 1B | Sparse MoE, preview / experimental | 128K | Apache 2.0 | Dec 2025 | 10T training tokens; languages include **German** (11 listed); "personality-forward chat model" | [Arcee docs](https://docs.arcee.ai/language-models/trinity-nano-6b); [opensourceforu](https://opensourceforu.com/2025/12/arcee-launches-apache-licensed-trinity-suite-to-challenge-chinas-open-weight-lead/) |
| **MobileMoE** (MobileLLM team) | 1.3–5.3B / 0.3–0.9B | 60 fine-grained experts, top-4, + 1 shared expert. S / M / L sizes × Base / SFT / **QAT** variants | — | arXiv page lists CC-BY-4.0 (license of the weights unconfirmed) | arXiv 26 May 2026 | INT4 footprint < 3 GB; matches or beats OLMoE-1B-7B with up to 60% fewer parameters. **No multilingual evaluation mentioned** | [arXiv 2605.27358](https://arxiv.org/abs/2605.27358); [coverage naming Meta](https://0dev.duckdns.org/en/posts/meta-releases-mobilemoe-efficient-on-device-mixture-of-experts-models) |
| NVIDIA Nemotron 3 Nano 30B-A3B | ~31.6B / ~3.2B **[recalled]** | Hybrid Mamba-2 / transformer MoE | **[recalled]** up to 1M | NVIDIA Open Model License (commercial use allowed) | Dec 2025 **[recalled]** | Languages: EN, **DE**, ES, FR, IT, JA | [NVIDIA build](https://build.nvidia.com/nvidia/nemotron-3-nano-30b-a3b.md) |
| ERNIE-4.5-21B-A3B **[recalled]** | 21B / 3B | MoE | 128K | Apache 2.0 | Jun 2025 | Chinese / English focus | [HF](https://huggingface.co/baidu/ERNIE-4.5-21B-A3B-PT) |
| Ling-mini-2.0 **[recalled]** | 16.3B / 1.4B | MoE, 1/32 activation | 32K (128K YaRN) | MIT | Sep 2025 | — | [HF](https://huggingface.co/inclusionAI/Ling-mini-2.0) |
| Moonlight-16B-A3B **[recalled]** | 16B / 3B | DeepSeek-V3-style MoE, trained with Muon | 8K | MIT | Feb 2025 | — | [HF](https://huggingface.co/moonshotai/Moonlight-16B-A3B) |
| DeepSeek-V2-Lite **[recalled]** | 15.7B / 2.4B | MLA + DeepSeekMoE | 32K | DeepSeek Model License (commercial use allowed) | May 2024 | EN / ZH focus | [HF](https://huggingface.co/deepseek-ai/DeepSeek-V2-Lite) |
| OLMoE-1B-7B **[recalled]** | 6.9B / 1.3B | MoE, 64 experts, top-8 | 4K | Apache 2.0 | Sep 2024 | English-only data | [HF](https://huggingface.co/allenai/OLMoE-1B-7B-0924) |
| EuroMoE-2.6B-A0.6B | 2.6B / 0.6B | EuroLLM project; targets EU languages | — | — | announced as "soon" | Not released as far as I found | [eurollm.io](https://eurollm.io/) |

- Gemma 4 also gained a **dense 12B** (11.95B, 48 layers, 256K, text + image + audio, Apache 2.0) on **3 Jun 2026**. It sits between E4B and the 26B MoE — [Google dev blog](https://developers.googleblog.com/en/gemma-4-12b-the-developer-guide/); [analyticsvidhya](https://www.analyticsvidhya.com/blog/2026/06/google-gemma-4-12b/)
- Quality index from Artificial Analysis: Qwen3.5-35B-A3B scores 30 vs Gemma 4 12B at 22; Gemma 4 E2B 10 vs Qwen3.5-2B 7; Gemma 4 31B 30 vs Qwen3.5-9B 22 — [AA 12B vs 35B-A3B](https://artificialanalysis.ai/models/releases/comparisons/gemma-4-12b-vs-qwen3-5-35b-a3b); [AA E2B vs Qwen3.5 2B](https://artificialanalysis.ai/models/releases/comparisons/gemma-4-e2b-vs-qwen3-5-2b)
- Google says Gemma 4 26B-A4B reaches about 97% of the dense 31B's quality at much lower compute — [Gemma 4 primer](https://aman.ai/primers/ai/gemma-4/); [ApX](https://apxml.com/models/gemma-4-26b-a4b)
- Granite 4.0 h-small (32B total / 9B active) has too many active parameters for a phone and is now superseded by dense 4.1 — [NYU RITS](https://rits.shanghai.nyu.edu/ai/ibm-releases-granite-4-1-dense-8b-matches-prior-32b-moe-flagship/)

### Inferences
- The candidates fall into three groups.
  - **(A) Big-sparse, needs streaming:** Gemma 4 26B-A4B, Qwen3.5/3.6-35B-A3B, Qwen3-30B-A3B, Nemotron 3 Nano, gpt-oss-20b, LFM2-24B-A2B, SmallThinker-21B, ERNIE-21B.
  - **(B) Mid-size, RAM-resident only at about 2-bit:** Ling-mini-2.0, Moonlight, DeepSeek-V2-Lite. All are older, all are EN/ZH-centric, and none is compelling.
  - **(C) Small-sparse, fits in RAM:** LFM2-8B-A1B, Ling-3.0-tiny / Edge0-8B, Phi-mini-MoE, Granite-4.0-h-tiny, Trinity Nano, MobileMoE.
- **Gemma 4 26B-A4B is the natural "above E4B" candidate.** It shares the Gemma 4 family's tokenizer, chat template and training pipeline with the current tutor. Its MMMLU is +9.7 points over E4B. It is Apache 2.0 and has Google QAT 4-bit weights (see Q4). Its only real problem is size.
- **Group C models have 1–1.5B active parameters.** That is below the ~3B dense capacity floor the project measured (`training/MODEL_SCOREBOARD.md`: "Capacity gates the corpus", where E2B's ~2B got hurt). Whether total parameters in an MoE give back the capacity to absorb fine-tuning data is unproven for this task. Expect behaviour between a 1.5B and a 4B dense model, and test it.

### Gaps
- I could not confirm exact layer and expert counts for gpt-oss-20b, Nemotron 3 Nano or Granite-4.0-h-tiny this session (they are marked [recalled]).
- No accuracy table on the LFM2-24B-A2B card. I found no numbers for "LFM2.5-24B-A2B" (only a citation string), and the LFM2.5 release (Jan 2026) was dense 1.2–1.6B models only ([Liquid blog](https://liquid.ai/blog/introducing-lfm2-5-the-next-generation-of-on-device-ai)).
- Not checked: a Mistral MoE small enough for a phone (I found none, and Ministral 3 is dense), Tencent Hunyuan small MoEs, Xiaomi MiMo, Ling-lite.
- The "Germany takes on US with strongest non-Chinese open-source model" story (17 Jul 2026) was not followed up. The model's identity and size are unknown ([propakistani](https://propakistani.pk/2026/07/17/germany-takes-on-us-with-strongest-non-chinese-open-source-ai-model/)).

---

## Q2. What evidence is there on German quality specifically (German or multilingual benchmarks, official language support, known weaknesses)?

### Takeaway
German-specific numbers are scarce. Only **gpt-oss-20b publishes a German split** (MMMLU-DE 78.7 at high reasoning, above its 14-language average). Everything else reports aggregate multilingual scores (MMMLU, MMLU-ProX, Global PIQA, WMT24++). Several models officially list German: Granite 4.0, LFM2, Nemotron 3 Nano, Trinity Nano, Ministral 3 and Qwen3.5 (201 languages). Many sparse models document no German at all: Ling-3.0-tiny, MobileMoE, Phi-MoE, SmallThinker, ERNIE, OLMoE, Moonlight and DeepSeek-V2-Lite. No public benchmark measures German grammar error detection; the app's own suite is the only relevant measure.

### Cited Findings
- **gpt-oss-20b** on MMMLU (human-translated, 14 languages): German 71.4 / 77.2 / 78.7 at low / medium / high reasoning, vs a 14-language average of 67.0 / 73.5 / 75.7 — [gpt-oss model card](https://arxiv.org/pdf/2508.10925)
- **Gemma 4:** "pre-trained on 140+ languages", with "out-of-the-box support for 35+ languages". The fetched card text did not list German explicitly. MMMLU: E2B 67.4, E4B 76.6, 26B-A4B 86.3, 31B 88.4 — [HF card](https://huggingface.co/google/gemma-4-26B-A4B-it)
- **Qwen3.5-35B-A3B:** MMMLU 85.2, MMLU-ProX 81.0, INCLUDE 79.7, NOVA-63 57.1, Global PIQA 86.6, WMT24++ 76.3, MAXIFE 86.6; 201 languages — [HF card](https://huggingface.co/Qwen/Qwen3.5-35B-A3B)
- **LFM2-8B-A1B:** MMMLU 55.26, MGSM 72.4. German is officially supported — [HF card](https://huggingface.co/LiquidAI/LFM2-8B-A1B)
- **LFM2-24B-A2B** officially supports EN, AR, ZH, FR, **DE**, JA, KO, ES and PT — [HF card](https://huggingface.co/LiquidAI/LFM2-24B-A2B)
- **Granite-4.0-h-tiny** officially supports 12 languages, German included — [llmreference](https://www.llmreference.com/model/granite-4.0-h-tiny)
- **Nemotron 3 Nano** supports EN, **DE**, ES, FR, IT, JA — [NVIDIA](https://build.nvidia.com/nvidia/nemotron-3-nano-30b-a3b.md)
- **Trinity Nano** lists German among 11 languages — [Arcee docs](https://docs.arcee.ai/language-models/trinity-nano-6b)
- **Ling-3.0-tiny** documents no languages — [HF card](https://huggingface.co/inclusionAI/Ling-3.0-tiny). Edge0's author has an MT background, but the release says nothing about German — [runtimewire](https://runtimewire.com/article/edge0-open-source-35b-model-streaming-inference)
- **MobileMoE:** trained on "open-source datasets". The abstract mentions no multilingual evaluation — [arXiv](https://arxiv.org/abs/2605.27358)
- **EuroEval** is the main European leaderboard: generative tasks in DE, FR, IT, ES, NL, PL, the Nordic languages and more, scored by rank (lower is better). An older snapshot surfaced in search had Gemma-3-27B-it at 1.74, Mistral-Small-24B at 1.89 and Gemma-3-12B-it at 1.90 among open models — [EuroEval HF](https://huggingface.co/EuroEval); [danish-foundation-models collection](https://huggingface.co/collections/danish-foundation-models/danish-benchmarks). The live German leaderboard page is rendered by JavaScript and could not be fetched ([euroeval.com](https://euroeval.com/leaderboards/Monolingual/german/))
- A community German-adherence benchmark found small models often fail to answer in German: SmolLM 1.7B 39.6% German output, Gemma2 2B 42.1%, EuroLLM 1.7B 45.8%, while Mistral Small 3.1 and Llama 3.1 8B reached ≥99%. Qwen3 4B scored 0.689 (rank 8) on German QA — [community writeup](https://thenote.app/post/en/german-llm-benchmark-fvbvq2vfq4?amp=true) (a blog-level source, not peer reviewed)
- MÖVE (Jun 2026), a German public-sector benchmark, tested 39 models: "no single model dominates… model size alone is a poor predictor of quality". Per-model scores are on its website, which was not retrieved — [arXiv 2606.13111](https://arxiv.org/abs/2606.13111)
- The project's own evidence: stock E4B scores 72%→80% on the core suite and the tuned E4B 85%→90%. Granite-4.1-3B stock scored 111/203 and Granite-4.2-3B stock 100/203. The brief notes that general-purpose Qwen3 4B/8B, Mistral 7B and Phi-4 Mini scored 48–58% — `training/MODEL_SCOREBOARD.md`

### Inferences
- MMMLU and MMLU-ProX test **knowledge and reasoning in German**, not grammar, morphology or error spotting. A model can score high on MMMLU and still miss case-ending errors. The project's earlier finding (general models at 48–58% vs tuned at 83–90%) shows that the base model's German *knowledge* is necessary but far from sufficient. Fine-tuning carries most of the gain.
- Among RAM-resident MoEs, **LFM2-8B-A1B is the only one with a published multilingual score, and at 55.3 MMMLU it is well below Gemma 4 E2B (67.4)**. That is weak evidence it would be a worse German base than what ships today.
- Models trained mostly on Chinese and English data (ERNIE, DeepSeek-V2-Lite, Moonlight, Ling family, SmallThinker) carry a higher risk of German adherence and morphology problems. The community adherence data shows small models drifting out of German, and that drift gets worse the less German they saw in training.

### Gaps
- No German-only split (MMMLU-DE, Global-MMLU-de, MMLU-ProX-de, Belebele-deu) found for Gemma 4, Qwen3.5/3.6, LFM2, Granite or Ling. Only aggregates were published.
- Current EuroEval German rankings for any 2026 model (Gemma 4, Qwen3.5, LFM2) could not be retrieved.
- I found no public benchmark of German **grammatical error detection or correction** (a German GEC benchmark such as Falko-MERLIN) for any of these models.

---

## Q3. How do these compare with Gemma 4 E4B / E2B and other strong dense 3–8B models on multilingual quality? Does "bigger but sparse" beat "best dense that fits"?

### Takeaway
On the one cross-model multilingual metric available (MMMLU, with mixed protocols), **E4B (76.6) is at the frontier for dense models that fit in RAM**. Qwen3.5-4B scores 76.1, and Ministral 3 8B scores 70.6 on 5-shot multilingual MMLU. Only the **big** sparse models clearly beat E4B: Gemma 4 26B-A4B (86.3), Qwen3.5-35B-A3B (85.2) and gpt-oss-20b (75.7 average, 78.7 German). No sparse model small enough for RAM has published evidence of beating E4B. So "bigger but sparse" beats "best dense that fits" only if expert streaming works.

### Cited Findings

**Dense comparison set**

| Model | Params | Multilingual score | Other | License / date | Source |
|---|---|---|---|---|---|
| **Gemma 4 E4B** | 8B total incl. PLE / 4.5B effective; 42 layers; 128K | **MMMLU 76.6** | MMLU-Pro 69.4, GPQA-D 58.6 | Apache 2.0, Apr 2026 | [HF card](https://huggingface.co/google/gemma-4-26B-A4B-it) |
| **Gemma 4 E2B** | 5.1B total / 2.3B effective; 35 layers | **MMMLU 67.4** | MMLU-Pro 60.0 | Apache 2.0, Apr 2026 | same |
| Gemma 4 12B (dense) | 11.95B | (not retrieved) | text + image + audio, 256K | Apache 2.0, 3 Jun 2026 | [Google dev blog](https://developers.googleblog.com/en/gemma-4-12b-the-developer-guide/) |
| **Qwen3.5-4B** | ~4B dense, 32 layers (Gated DeltaNet 3:1), 262K | **MMMLU 76.1, MMLU-ProX 71.5**, INCLUDE 71.0, Global PIQA 78.9, WMT24++ 66.6, MAXIFE 78.0 | MMLU-Pro 79.1, IFEval 89.8 | Apache 2.0, 2 Mar 2026 | [HF card](https://huggingface.co/Qwen/Qwen3.5-4B); [release](https://rits.shanghai.nyu.edu/ai/qwen-3-5-small-models-9b-parameters-that-beat-120b) |
| Qwen3.5-9B / 2B / 0.8B | dense | (not retrieved) | 201 languages, vision built in | Apache 2.0, 2 Mar 2026 | [release](https://rits.shanghai.nyu.edu/ai/qwen-3-5-small-models-9b-parameters-that-beat-120b) |
| **Ministral 3** 3B / 8B / 14B | dense + 0.4B vision encoder, 256K | Multilingual MMLU (5-shot) **65.2 / 70.6 / 74.2** | German officially supported | Apache 2.0, Dec 2025 | [Ministral 3 paper](https://arxiv.org/pdf/2601.08584); [awesomeagents](https://awesomeagents.ai/models/ministral-3-8b/) |
| Qwen3-4B-Instruct-2507 | 4B dense | — | MMLU 72.3, MMLU-Pro 52.3 | Apache 2.0 | [LFM2-8B-A1B card table](https://huggingface.co/LiquidAI/LFM2-8B-A1B) |
| Gemma-3-4b-it / Llama-3.2-3B | dense | — | MMLU 58.4 / 60.4 | — | same |
| Granite 4.1 3B / 8B; Granite 4.2 3B | dense | — | 4.1-8B ≈ Granite 4.0 32B MoE on enterprise benchmarks | Apache 2.0, Apr / Aug 2026 | [NYU RITS](https://rits.shanghai.nyu.edu/ai/ibm-releases-granite-4-1-dense-8b-matches-prior-32b-moe-flagship/) |

- MoE vs dense at matched compute: LFM2-8B-A1B (1.5B active) scores MMLU 64.8 vs Qwen3-4B-2507 at 72.3, and MMLU-Pro 37.4 vs 52.3. It trades quality for speed against a 4B dense model — [LFM2-8B-A1B card](https://huggingface.co/LiquidAI/LFM2-8B-A1B)
- MobileMoE claims "2–4× fewer inference FLOPs" than leading on-device dense models at comparable quality, and 2.2–3.4× faster decode than MobileLLM-Pro at equal INT4 memory. The claim is about speed and efficiency, not about beating a 4B dense model — [arXiv](https://arxiv.org/abs/2605.27358)
- Edge0's streamed 4-bit 35B-A3B kept 79.2 of the base's 83.2 points (−4.0). The 8B-A1B kept 69.9 of 72.7 (−2.8) — [runtimewire](https://runtimewire.com/article/edge0-open-source-35b-model-streaming-inference)

### Inferences
- **The only MoEs with a large, published multilingual lead over E4B are 25–35B total** (+9 to +10 MMMLU points). gpt-oss-20b is roughly at E4B's level on average (75.7 vs 76.6) and a bit higher on German (78.7). It is reasoning-tuned, English-centric in style, and needs ~13 GB. That makes it a poor trade.
- **Qwen3.5-4B effectively ties E4B** on MMMLU (76.1 vs 76.6). It would be the strongest dense alternative to fine-tune, but it changes tokenizer, template and architecture (Gated DeltaNet), so the whole pipeline would need porting. **Gemma 4 12B dense** is the other "best dense that might fit" option, at about 6.7 GB at 4-bit (see Q5).
- Even after Edge0's −4 point streaming and quantization loss, a 35B-A3B (~79 on Edge0's score) would very likely remain above E4B in general and multilingual knowledge. Whether that turns into better German *error detection* after fine-tuning is untested.
- **Fine-tuning cost goes up.** LoRA on a 26–35B MoE needs far more GPU memory and data handling than on E4B. Both RunPod and Unsloth support Qwen3 MoE models (the Unsloth docs say Qwen3-30B-A3B fits in 17.5 GB VRAM for training — [Unsloth Qwen3 docs](https://docs.unsloth.ai/basics/qwen3-how-to-run-and-fine-tune)).

### Gaps
- MMMLU protocols differ (0-shot vs 5-shot, chat vs base, thinking on or off), so cross-vendor numbers are only roughly comparable.
- Not retrieved: MMMLU for Qwen3.5-9B / 2B, Gemma 4 12B, Qwen3-30B-A3B or Granite 4.1.
- No head-to-head German grammar benchmark between E4B and any MoE exists publicly. The app's own suites (core / ext / holdout) are the right tool.

---

## Q4. How well do MoE models tolerate aggressive quantization (3-bit, 2-bit, mixed: low-bit experts with high-bit attention, router and shared expert)?

### Takeaway
At 4-bit, MoE models drift *less* than dense ones. On MLX, Qwen3.6-35B-A3B at DWQ 4-bit had a mean KLD of 0.027, against 0.11 for the dense Qwen3.6-27B at 4-bit RTN. The research consensus: routed experts tolerate low bits well, but **attention, the router and shared experts need more bits**. Naive 2-bit (GPTQ) collapses on Qwen3-30B-A3B; 2-bit only works with special methods (BitsMoE, dynamic quants, QAT or recovery LoRA). A 3-bit mix (3-bit routed experts; 4–8-bit attention, router, shared expert and embeddings) is the practical floor before quality falls off a cliff.

### Cited Findings
- MLX KL-divergence study (Apr 2026, Apple Silicon):
  - **Qwen3.6-35B-A3B (MoE):** DWQ 4-bit at 4.84 bpw, 20.66 GB, mean KLD **0.0266**; oQ4 4.95 bpw, 21.10 GB, KLD 0.0402; 6-bit RTN 6.81 bpw, 29.06 GB, KLD 0.0119.
  - **Qwen3.6-27B (dense):** 4-bit RTN 5.27 bpw, 16.05 GB, KLD **0.1132**.
  - DWQ beat oQ4 on the MoE by ~34% "because DWQ protects router tensors". No 2- or 3-bit data. KLD here is measured at prefill only.
  - [smcleod.net](https://smcleod.net/2026/04/measuring-model-quantisation-quality-with-kl-divergence/)
- **QuantMoE-Bench:** attention layers need more bits than the feed-forward and expert layers; shared experts (used by every token) need more precision than routed experts; giving early MoE layers more bits helps at low budgets — [arXiv 2406.08155](https://arxiv.org/html/2406.08155v2)
- **MoQE (NeurIPS 2023):** expert layers are "much more robust to quantization" than dense FFN layers, and MoE models with **2-bit expert weights** can beat the dense model trained on the same data — [NeurIPS](https://neurips.cc/virtual/2023/81188)
- **BitsMoE (Jun 2026):** under **2-bit** quantization of Qwen3-30B-A3B-Base, BitsMoE improves average accuracy by **27.83 percentage points over GPTQ** (and quantizes 12.3× faster, decodes 1.76× faster). So plain 2-bit GPTQ loses a lot on this model — [alphaxiv 2606.00079](https://www.alphaxiv.org/abs/2606.00079)
- Other mixed-precision MoE methods: MoPEQ (per-expert bit width from Hessian sensitivity) and GEMQ (down to ~1.5 bits) — [arXiv 2509.02512](https://arxiv.org/pdf/2509.02512); [GEMQ GitHub](https://github.com/jndeng/gemq)
- **Unsloth:** its dynamic quants keep sensitive layers at higher bits. Its 1.58-bit DeepSeek-R1 dynamic GGUF "was effective only for MoE architectures". For Qwen3.6-35B-A3B GGUFs, Unsloth claims the lowest mean KLD in 21 of 22 sizes — [Unsloth Dynamic 3.0](https://unsloth.ai/docs/basics/dynamic-3.0-ggufs); [Unsloth Dynamic 2.0](https://docs.unsloth.ai/basics/unsloth-dynamic-2.0-ggufs)
- **Gemma 4 26B-A4B quant sizes:** official 4-bit Q4_0 is 14.4 GB; Unsloth UD-IQ3_XXS (3-bit) is ~11.2 GB. Google / mlx-community publish a **QAT 4-bit MLX** checkpoint — [jacar.es](https://jacar.es/en/gemma-4-locally-with-ollama/); [mlx-community QAT](https://huggingface.co/mlx-community/gemma-4-26B-A4B-it-qat-4bit); [3-bit MLX](https://huggingface.co/NexVeridian/gemma-4-26B-A4b-3bit)
- **Edge0:** 4-bit plus a distillation-trained "Recover-LoRA" to offset quantization loss gives −4.0 points (35B) and −2.8 points (8B) vs base — [runtimewire](https://runtimewire.com/article/edge0-open-source-35b-model-streaming-inference)
- **MobileMoE** ships official QAT variants, aimed at INT4 — [arXiv](https://arxiv.org/abs/2605.27358)

### Inferences
- A recipe for this app, if it went MoE:
  - Keep embeddings and LM head at 6–8-bit; attention, router and shared expert at 6–8-bit (or 4-bit DWQ with protected routers); routed experts at 3-bit, or 2-bit only with QAT, DWQ or a recovery LoRA.
  - Because routed experts are 85–95% of total parameters in these models, this mix lands around **3.2–3.8 effective bpw**.
  - Validate with the app's grammar suites, not perplexity or KLD. Both of the project's earlier lessons apply (pass-rate gates miss class collapse; measure before gating).
- A 4-bit LoRA fine-tune followed by quantization is how the project already ships. For an MoE, distilled weight quantization (DWQ) or a recovery LoRA after quantization would likely matter more than for E4B, because router errors cascade.

### Gaps
- No published German-specific (or grammar-task) quality-loss numbers for any MoE at 3-bit or 2-bit.
- No 3-bit numbers for Gemma 4 26B-A4B beyond file size (11.2 GB). No published KLD or accuracy deltas.
- BitsMoE's absolute baselines (BF16 accuracy, GPTQ 2-bit accuracy) were not visible in the abstract.

---

## Q5. Practical size math: what does each top candidate weigh at 4-bit and ~3-bit, and does it fit in RAM on a 12 GB iPhone 17 Pro or an 8 GB iPad, or does it need expert streaming?

### Takeaway
**The iPhone 17 Pro budget is likely smaller than assumed.** A June 2026 Apple developer-forum report measured a flat **~6.0 GB per-app ceiling** on 12 GB iPhone 17 Pro Max, even with `increased-memory-limit` (6.5 GB only with a debugging entitlement). In the same report, a Gemma 4 model loaded via mlx-swift-lm sat at 4.4 GB resident, with ~1.7 GB left. On that budget:
- Only the 6–8B-total MoEs fit, at 4-bit on the iPhone and at about 3-bit on an 8 GB iPad.
- Gemma 4 26B-A4B and Qwen3.5/3.6-35B-A3B need 8–20 GB even at 2–4 bits, so they need expert streaming from flash.
- Streaming of that kind has been shown on Mac (Edge0: 2.9 GB peak, ~15–18 tok/s on an M4 Pro) and as a slow iPhone demo (a 397B model at 0.6 tok/s), but there is no shipping iOS runtime.

### Cited Findings
- iPhone 16 Pro Max (8 GB) and **iPhone 17 Pro Max (12 GB)** both measured **~6144 MB** with `com.apple.developer.kernel.increased-memory-limit`. Adding `extended-virtual-addressing` changed nothing; adding `increased-debugging-memory-limit` gave ~6656 MB. 12 GB iPads "expose more memory" (not quantified). The thread had no Apple reply when fetched (FB23183521, June 2026) — [Apple Developer Forums](https://developer.apple.com/forums/thread/834805)
- The same report: Gemma 4 multimodal via mlx-swift-lm loads at ~4.4 GB resident, leaving ~1.7 GB. The developer had to shrink the GPU buffer cache from 512 MB to 64 MB to avoid jetsam — [Apple Developer Forums](https://developer.apple.com/forums/thread/834805)
- iPhone 17 Pro **ran Qwen3.5-397B-A17B (2-bit) by streaming weights from SSD at 0.6 tok/s, with ~50 s time to first token**. It proves streaming works on iPhone; it is not a usable speed — [TweakTown](https://tweaktown.com/news/110610/the-iphone-17-pro-can-run-a-400b-parameter-large-language-model-on-device-by-streaming-weights-from-the-ssd/images/applenews.png); [wccftech](https://wccftech.com/iphone-17-pro-successfully-runs-400b-llm-locally//amp/)
- **Edge0** streams experts from SSD with a prerouter: 35B-A3B at 2.9 GB peak and 14.9–17.7 tok/s on an M4 Pro; 8B-A1B at ~1 GB. The repo supports only macOS/MLX; the iPhone 1–2.5 GB claim is unverified — [runtimewire](https://runtimewire.com/article/edge0-open-source-35b-model-streaming-inference); [mindstudio](https://www.mindstudio.ai/blog/edge0-35b-phone-memory-moe)
- Measured sizes: Gemma 4 26B-A4B Q4_0 is 14.4 GB and UD-IQ3_XXS ~11.2 GB ([jacar.es](https://jacar.es/en/gemma-4-locally-with-ollama/)). Qwen3.6-35B-A3B MLX DWQ 4-bit is 20.66 GB at 4.84 bpw ([smcleod.net](https://smcleod.net/2026/04/measuring-model-quantisation-quality-with-kl-divergence/)). gpt-oss-20b "runs within 16GB" ([HF](https://huggingface.co/openai/gpt-oss-20b)). MobileMoE INT4 is < 3 GB ([arXiv](https://arxiv.org/abs/2605.27358)). SmallThinker 21B-A3B and 4B-A0.6B run at Q4_0 in **8 GB / 1 GB** with their runtime ([paper](https://huggingface.co/papers/2507.20984)).
- The current tutor (E4B, MLX 4-bit) is ~2.7 GB on disk and ~4.3 GB at peak (from the brief). The forum's 4.4 GB resident figure for Gemma 4 is consistent with that.

### Inferences

Size estimates are **computed**, for weights only. The formula is params × bpw / 8, with MLX affine group-64 quantization: 4-bit ≈ 4.5 bpw, 3-bit ≈ 3.5 bpw, 2-bit ≈ 2.5 bpw. Real MLX files run ~5–10% larger because embeddings and vision towers are kept at higher precision (the DWQ 4-bit above was 4.84 bpw). Add ~1–1.7 GB for KV cache, activations and the app.

Budgets used:
- **iPhone 17 Pro:** a reported ~6.0 GB ceiling (forum) vs the brief's 7–8 GB assumption. Usable for weights: about 4.3–4.8 GB if 6 GB, about 5.5–6.5 GB if 7–8 GB.
- **8 GB iPad:** about 4.5–5.5 GB total, so about 3–4 GB of weights.

| Model | Total / active | ~4-bit | ~3-bit | ~2-bit | iPhone 17 Pro (6 GB ceiling) | 8 GB iPad |
|---|---|---|---|---|---|---|
| Qwen3.5/3.6-35B-A3B | 35B / 3B | ~19.7 GB (measured 20.7) | ~15.3 | ~10.9 | streaming only | streaming only |
| Nemotron 3 Nano | ~31.6B / ~3.2B | ~17.8 | ~13.8 | ~9.9 | streaming only | streaming only |
| Qwen3-30B-A3B | 30.5B / 3.3B | ~17.2 | ~13.3 | ~9.5 | streaming only | streaming only |
| **Gemma 4 26B-A4B** | 25.2B / 3.8B | ~14.2 (Q4_0 14.4) | ~11.0 (IQ3_XXS 11.2) | ~7.9 | streaming only (even 2-bit is over) | streaming only |
| LFM2-24B-A2B | 24B / 2.3B | ~13.5 | ~10.5 | ~7.5 | streaming only | streaming only |
| gpt-oss-20b | 21B / 3.6B | ~12.8–13 (native MXFP4) | ~9.2 | — | streaming only | streaming only |
| SmallThinker-21B-A3B / ERNIE-4.5-21B-A3B | ~21B / 3B | ~11.8–12.1 | ~9.2–9.4 | ~6.6 | streaming only | streaming only |
| Ling-mini-2.0 / Moonlight / DeepSeek-V2-Lite | ~16B / 1.4–3B | ~8.8–9.2 | ~6.9–7.1 | ~4.9–5.1 | 2-bit borderline | no |
| Gemma 4 12B (dense) | 11.95B | ~6.7 | ~5.2 | — | 3-bit borderline / no | no |
| **LFM2-8B-A1B** | 8.3B / 1.5B | ~4.7 | ~3.6 | — | 4-bit borderline, 3-bit yes | 3-bit yes |
| **Ling-3.0-tiny / Edge0-8B** | 7.9B / 1.3B | ~4.4 | ~3.5 | — | 4-bit borderline, 3-bit yes | 3-bit yes |
| Phi-mini-MoE | 7.6B / 2.4B | ~4.3 | ~3.3 | — | 4-bit yes | 3-bit yes |
| Granite-4.0-h-tiny / OLMoE | ~7B / ~1B | ~3.9 | ~3.0 | — | yes | 4-bit borderline, 3-bit yes |
| Trinity Nano | 6B / 1B | ~3.4 | ~2.6 | — | yes | yes |
| MobileMoE-L | 5.3B / 0.9B | ~3.0 (paper: < 3 GB INT4) | ~2.3 | — | yes | yes |
| Gemma 4 E4B (current) | 8B incl. PLE / 4.5B effective | 2.7 GB disk / 4.3 GB peak (measured) | — | — | yes (today) | tight |
| Qwen3.5-4B (dense) | ~4B | ~2.3 | ~1.8 | — | yes | yes |

- **Streaming throughput (inference):**
  - A 3–4B-active model at ~4 bits touches ~1.7–2.1 GB of expert weights per token if nothing is cached. Usable speed depends on keeping hot experts resident and pre-routing, which is what Edge0 does.
  - Edge0's ~15–18 tok/s at 2.9 GB peak on an M4 Pro is the best evidence that a 26–35B MoE could run in a ~3 GB working set. iPhone flash bandwidth and thermals are lower than a Mac's, so expect it to be slower.
  - No mlx-swift-lm expert-offload path was found.
  - **Gemma 4 26B-A4B on iPhone therefore means building or porting a streaming runtime.** That is a research project, not a model swap.
- **The 6 GB ceiling matters most.** If it holds on the user's devices, the "app budget ~7–8 GB" in the brief is too optimistic. Gemma 4 12B dense, and anything else above ~4.5 GB of weights, would also be out without streaming. This should be checked against the project's own `docs/MEMORY.md` measurements (Settings ▸ Speicher).
- **The 8 GB iPad (~4.5–5.5 GB budget) is already tight for E4B (4.3 GB peak).** Only the ≤ 3.5 GB MoE quants (Trinity Nano, Granite-h-tiny, MobileMoE, or LFM2-8B / Ling-3.0-tiny / Phi-mini-MoE at 3-bit) leave headroom. None of them has evidence of better German than E4B.

### Gaps
- No Apple documentation on the per-app ceiling for iPhone 17 Pro or for 8 GB / 12 GB / 16 GB iPads. The forum report is one developer's measurement with no Apple reply.
- No measured iPhone tokens/sec for any 20–35B MoE using flash streaming, other than the 0.6 tok/s 397B demo.
- iPhone NAND sustained random-read bandwidth (which sets the streaming speed) was not found.
- License detail: the LFM Open License v1.0 commercial-use terms (reportedly free below a revenue threshold) were not confirmed this session. Read the license text before choosing an LFM2 model for the App Store.
- The license of the MobileMoE weights is unconfirmed (the arXiv page shows CC-BY-4.0, which may apply only to the paper).
