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

## Q4_0 vs Q4_K_M (speed on ARM CPUs, same scores?)

llama.cpp repacks Q4_0 weights for ARM's int8 dot-product instructions; Q4_0 also keeps the PLE
and `token_embd` at Q6_K. Emulator (6 Mac cores, dotprod, no i8mm), `llama-bench -p 128 -n 32`:

| model | threads | Q4_K_M read / write t/s | Q4_0 read / write t/s |
|---|---|---|---|
| Granite 4.1 3B | 4 | 119 / 44 | **176 / 54** |
| Granite 4.1 3B | 6 | 153 / 44 | **216 / 54** |
| Gemma 4 E2B | 4 | 297 / 52 | (pushed, run lost to a full disk) |

Writing speed flattens after 4 threads (memory bandwidth); reading keeps scaling. A phone's cores
are 2–4× slower than these, so treat the numbers as ratios.

Scores, Q4_0 (/203, guarded): E4B **184** (K_M 185, McNemar p = 1.0), E2B **169** (K_M 173,
p = 0.42), Granite 4.1 **160** (K_M 164, p = 0.48), Granite 3.3 **148** (K_M 153, p = 0.27).
None significant on its own, but the three small models all moved the same way. **The app ships
E4B as Q4_0 and the three smaller tutors as Q4_K_M** (`TutorStore.swift`). The prompt cache
(below) means most of a turn's prompt is never re-read, so the read-speed gain matters less than
it looks. On the emulator, E2B Q4_0 "corrected" the correct "Ich habe ein neues Auto gekauft."
(added "mir"); Q4_K_M left it alone.

## From the masters (release_model.py, 2026-11-27)

`scripts/release_model.py --tutor <t> --master <bf16 repo>` builds MLX 4-bit and GGUF from the
same master and scores all of them (/203, guarded; p is McNemar against MLX). The rebuilt MLX is
tensor-for-tensor what the app ships for both Granites (E2B: only two audio/vision projection
tensors differ), so the MLX column is the iOS model.

| tutor | MLX | GGUF from master Q4_K_M | Q4_0 | GGUF from MLX (published) Q4_K_M | Q4_0 |
|---|---|---|---|---|---|
| Granite 3.3 2B | 151 | 153 (p=0.81) | **169 (p<0.001)** | 153 | 148 |
| Granite 4.1 3B | 165 | 154 (p=0.04) | 160 (p=0.36) | 164 | 160 |
| Gemma 4 E2B | 172 | 162 (p=0.10) | 169 (p=0.65) | 173 | 169 |

(E4B's published GGUF already came from its fp16 master: Q4_0 184, Q4_K_M 185, MLX 182.)

Reading: quantizing these fine-tunes moves 10–30 items each way, and the direction isn't
predictable from the format. Re-quantizing the MLX 4-bit weights stays closest to MLX (its
values already sit on a 4-bit grid); quantizing from bf16 makes independent rounding choices,
which cost Granite 4.1 and E2B ~10 items at Q4_K_M and gained Granite 3.3 18 items at Q4_0 (mostly
extension-suite corrections it now catches, 15 → 24 of 37; it also flagged one of the 56 correct sentences, MLX none). The
published files stay the dequantized-MLX builds; the release gate (no quant > 6 items or
significantly behind MLX) is why the master builds weren't uploaded. A 203-item suite picked the
winner here, so a better-looking build needs a fresh eval set before it replaces the shipped one.

**Checked on the frozen v3 suite (300 items, scored once each, 2026-11-27), Granite 3.3 2B:**

| build | v3 /300 | false corrections /150 | traps fooled /93 | misses /150 |
|---|---|---|---|---|
| MLX 4-bit (iOS) | 234 | 7 | 6 | 59 |
| Q4_K_M from MLX (Android) | 238 | 8 | 6 | 54 |
| Q4_0 from MLX | 232 | 8 | 6 | 60 |
| Q4_K_M from bf16 | 238 | 4 | 3 | 58 |
| Q4_0 from bf16 | 245 | 12 | 10 | 43 |

The +16 on the 203 shrank to +7 against Android's file (+16/−9, p = 0.23), and it isn't a better
model so much as a differently balanced one: it says FIX more often, catching 11 more errors and
wrongly "fixing" 4 more correct sentences. That's the same seesaw as the FIX-bias controls in
REINFORCEMENT_LEARNING.md Part C.2. Every build stays within 13 items of the others, all close to
MLX. Android keeps Q4_K_M from MLX: Granite 2B's selling point is that it rarely flags correct German.

## In the Android app (2026-11-26)

`DieKarteiAndroid/Sources/DieKartei/TutorEngine.swift`: llama.cpp's C API from native Swift
(Skip Fuse), through a `CLlama` module. No Kotlin, no JNI. Libraries:
`scripts/build_llama_android.sh` (pinned commit, NDK r30, `GGML_BACKEND_DL` +
`GGML_CPU_ALL_VARIANTS`: one CPU backend per ARM feature level, the best one loaded at launch;
the emulator gets `android_armv8.2_2`, DOTPROD + FP16).

What it does for speed on a phone:
- **Fast cores only:** threads = cores outside the slowest cluster (`/sys/.../cpuinfo_max_freq`),
  so 4 on a 1+3+4 phone. A llama.cpp step waits for its slowest thread.
- **Prompt cache, two slots:** the conversation and the correction pass each keep their own KV
  prefix (two sequences), so they don't evict each other. Measured on the emulator: the second
  sentence check read 19 of 210 tokens (0.8 s → 0.1 s); the second chat turn 25 of 284.
- **mmap + lazy PLE rows:** Gemma's per-layer embedding table stays in the file.

Verified on the emulator with E2B: model loads in ~1.5 s, Satz prüfen corrects "Ich warte fuer
den Bus." → "Ich warte auf den Bus." and leaves a correct sentence alone, and Gespräch runs the
iOS flow (opener, correction pass, reply) with streaming. No crashes.

Older emulator notes:
- `llama-cli` with the AVD at 1 core / 4 GB swapped and crawled; it now runs 6 cores / 8 GB.
- The emulator's CPU has no i8mm, so a `-march=armv8.7a` build crashes there; the app's
  per-feature backends avoid this.

## Open

- Publish the GGUFs to Hugging Face (`kessenma/*-gguf`) and download them in the app; needs an
  HF login on this Mac.
- Phone measurements: tokens/s and memory on a real 6–8 GB and a 4 GB Android phone; then the
  Vulkan/OpenCL (Adreno) GPU backends.
- Which tiers ship on Android: same RAM floors as iOS to start (E4B 8 GB, E2B 6 GB, Granite 4 GB).
