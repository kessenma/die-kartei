# The tutor models on Android: llama.cpp (GGUF)

**Answer (2026-11-26, Mac mini): the four tutors convert to GGUF with no quality loss.** MLX
can't run on Android; llama.cpp can, and its `Q4_K_M` builds score the same as the shipped MLX
4-bit builds on all three suites. No retraining and no RunPod.

Why this works where Cactus and LiteRT-LM failed (see `RUNTIME_EXPLORATION.md`): llama.cpp's
`Q4_K_M` keeps Gemma 4's per-layer embeddings (`per_layer_token_embd`) and `token_embd` at
**Q6_K** by default, so the part that broke the other runtimes is protected. That's the
`--quant-predicate` analogue, and it comes out of the box. `--tensor-type` can push it higher.

## Scores (app-guarded, the shared scorer, /203 = core 60 + ext 61 + holdout 82)

| model | MLX 4-bit (scoreboard) | **GGUF Q4_K_M** | GGUF file | peak footprint* |
|---|---|---|---|---|
| Gemma 4 E4B v4 | 51 / 56 / 75 = 182 · FC 3% · miss 16% | **53 / 54 / 78 = 185** · FC 3% · miss 16% | 5.3 GB | 3.4 GB |
| Gemma 4 E2B v1 (shipped) | 50 / 52 / 69 = 171 · FC 3%† · miss 19% | **52 / 52 / 69 = 173** · FC 0% · miss 19% | 3.4 GB | 1.7 GB |
| Granite 4.1 3B v4 | 47 / 46 / 71 = 164 · FC 9% · miss 25% | **48 / 48 / 68 = 164** · FC 9% · miss 22% | 2.1 GB | 2.4 GB |
| Granite 3.3 2B v4 | 46 / 39 / 68 = 153 · FC 0% · miss 43% | **45 / 38 / 70 = 153** · FC 0% · miss 42% | 1.5 GB | 1.7 GB |

Control: Granite 4.1 as `Q8_0` scores 48 / 46 / 70 = 164, FC 6%, miss 25%, the same as Q4_K_M.
Zero format errors in every run.

\* `peak memory footprint` from `/usr/bin/time -l llama-cli -ngl 0 -c 2048`, Mac CPU, one tutor
turn. It counts anonymous memory, not the clean mmapped pages: Gemma's PLE table is read from the
file a few rows per token, which is why E2B's footprint (1.7 GB) is under its MLX peak (2.71 GB).
Needs a real-phone measurement before planning a 4 GB tier around it.
† RUNTIME_EXPLORATION.md's baseline; the scoreboard's v4-generation table lists E2B v1 at FC 12%.

Differences are within noise (no paired test: the MLX response files aren't on this Mac).

## Recipe

```bash
# llama.cpp at fa9f928 (2026-11-26), built in ~/ws/llama.cpp (Metal) and ~/ws/llama.cpp/build-android (NDK)
# convert venv: requirements-convert_hf_to_gguf.txt + transformers>=5.5 (4.57 doesn't know gemma4)

# E4B v4: from the public fp16 master
python convert_hf_to_gguf.py <kessenma/gemma4-e4b-german-v4-fp16> --outtype bf16 --outfile e4b-v4-bf16.gguf

# E2B v1 and both Granites: no fp16 master on this Mac (private / not on HF), so from the public
# MLX 4-bit, dequantized. Q8_0 vs Q4_K_M on Granite 4.1 shows the second rounding costs nothing.
python -m mlx_vlm convert --hf-path kessenma/gemma4-e2b-german-tutor-4bit --mlx-path e2b-v1-dequant --dequantize
python -m mlx_lm  convert --hf-path kessenma/granite41-3b-german-tutor-v4-4bit --mlx-path g41-dequant --dequantize
python convert_hf_to_gguf.py <dequant dir> --outtype bf16 --outfile <name>-bf16.gguf

llama-quantize <name>-bf16.gguf <name>-Q4_K_M.gguf Q4_K_M
```

Eval: `llama-server -m <gguf> --port 8899 -c 4096 -ngl 99 --jinja`, then
`scripts/gen_cactus_responses.py --port 8899 --out-prefix <p> --suites core,ext,holdout` (stdlib
only; llama-server is OpenAI-compatible) and score with `run_baseline_eval.py --responses …
--app-guard --tag scratch` (without `--tag` it overwrites `results/baseline_<model>.json`).
Responses: `results/gguf_*_{core,ext,holdout}.responses.json`. The chat template comes from
each repo's `chat_template.jinja`, embedded in the GGUF.

## On Android

- `llama-cli` cross-compiled with NDK r30 runs on the emulator (API 37, arm64) and answers the
  tutor prompt correctly with Granite 4.1 Q4_K_M ("FIX: Ich interessiere mich für Fußball.").
  The AVD has 1 core and 4 GB, so it swaps and crawls: emulator speed means nothing, measure on
  a phone.
- The emulator's CPU has dotprod but no i8mm, so `-march=armv8.7a` builds would crash there. For
  the app, build with `GGML_BACKEND_DL=ON GGML_CPU_ALL_VARIANTS=ON` so the right CPU kernels load
  at runtime on each phone.
- The Android app is native Swift (Skip Fuse), so it can call llama.cpp's C API directly: a C
  module over `llama.h` linking the NDK-built `libllama.so`. No Kotlin and no JNI.

## Open

- Publish the GGUFs to Hugging Face (`kessenma/*-gguf`); needs an HF login on this Mac.
- Phone measurements: tokens/s and memory on a real 6–8 GB and a 4 GB Android phone; CPU first,
  then the Vulkan/OpenCL backends.
- Which tiers ship on Android: same RAM floors as iOS to start (E4B 8 GB, E2B 6 GB, Granite 4 GB).
