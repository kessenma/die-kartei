# German Grammar Fine-Tune Plan — Gemma 4 E4B

Goal: fine-tune the app's on-device model (Gemma 4 E4B, MLX 4-bit) to be reliably
correct at four German grammar areas it currently struggles with, plus broaden
useful vocabulary coverage:

1. **Verben mit Präpositionen** — verbs with fixed prepositions (`warten auf + Akk`, `denken an + Akk`)
2. **Trennbare Verben** — separable-prefix verbs (V2 placement, participle `aufgestanden`, `aufzustehen`)
3. **Reflexive Verben** — incl. accusative vs dative reflexive (`ich wasche mir die Hände`)
4. **Da-/Wo-Komposita** — `darauf/worauf` for things vs `auf ihn/auf wen` for people

## Key decisions

| Decision | Choice | Why |
|---|---|---|
| Base model | **Gemma 4 E4B** (`unsloth/gemma-4-E4B-it`) | Apache 2.0, app's flagship model, official Unsloth E4B notebook |
| Trainer | **Unsloth QLoRA** (~10 GB VRAM) | Free Colab T4 works; local NVIDIA GPU works if ≥12 GB VRAM |
| Method | LoRA r=8, alpha≥r, lr 2e-4, batch 1 + grad-accum 4, text-only (`finetune_vision_layers=False`) | Unsloth's recommended Gemma 4 starting point |
| Export | `save_pretrained_merged(..., save_method="merged_16bit")` — never merge into 4-bit | Unsloth rule; quantize from 16-bit |
| Convert | `mlx_lm.convert --hf-path <merged> -q --q-bits 4 --q-group-size 64` | Auto-strips vision/audio towers → ~4 GB text-only model |
| App integration | `ModelConfiguration(id: "<you>/gemma-4-e4b-german-tutor-4bit")` — new case in `ModelConfiguration.swift` | MLX Swift dispatches on `config.json` `model_type: gemma4`; no other code changes |

### Hardware options for training

- **Own GPU: RTX 2070 Super (8 GB)** — below the ~10 GB needed for E4B QLoRA, so **not usable for the main run** (also Turing = fp16-only, no bf16). Still useful for running LanguageTool, data-gen scripts, and small experiments.
- **Free Colab T4 (16 GB)**: confirmed working via the official notebook — zero cost, session limits apply. **← default choice**
- **Rented**: RunPod/Vast/Lambda — an RTX 4090/A10 at ~$0.20–0.50/hr; a full run is a few hours ≈ a few dollars. Use if Colab session limits get annoying during iteration.

### Reference links

- Unsloth Gemma 4 E4B text notebook: <https://colab.research.google.com/github/unslothai/notebooks/blob/main/nb/Gemma4_(E4B)-Text.ipynb>
- Unsloth Gemma 4 train guide: <https://unsloth.ai/docs/models/gemma-4/train>
- Unsloth datasets guide: <https://unsloth.ai/docs/get-started/fine-tuning-llms-guide/datasets-guide.md>
- mlx-lm convert/LoRA docs: <https://github.com/ml-explore/mlx-lm> (`LORA.md`, `LEARNED_QUANTS.md`)
- MLX Swift custom models: <https://github.com/ml-explore/mlx-swift-lm> (`ModelConfiguration.swift`)
- MLX 4-bit PLE-quantization bug thread (why we sanity-check after convert): <https://huggingface.co/mlx-community/gemma-4-e2b-4bit/discussions/1>

---

## Phase 1 — Ground-truth backbone ← WE ARE HERE

Licensing-clean inventories that anchor generation and validation.

- [x] Fetch separable-verb inventory from de.wiktionary `Kategorie:Verb trennbar (Deutsch)` → `data/raw/separable_verbs.json` (**6,526 verbs**, fetched 2026-07-07 via `scripts/fetch_wiktionary_verbs.py`)
- [x] Fetch reflexive-verb inventory from de.wiktionary `Kategorie:Verb reflexiv (Deutsch)` → `data/raw/reflexive_verbs.json` (**1,604 verbs**)
- [x] Curate verb→preposition+case table → `data/verb_praep_table.json` (**268 entries**, 15 prepositions; 99 reflexive, 47 separable, 223 da-compound-capable; levels A2 21 / B1 69 / B2 96 / C1 82)
- [x] Download Tatoeba German sentences (CC-BY 2.0 FR) and mine by target structure → `data/raw/tatoeba/` (2026-07-08: 773,911 sentences; `scripts/mine_tatoeba.py` extracted **83,262 seeds**: 11,353 vmp covering 236/268 table patterns, 46,953 sep (2,472 verbs, "separated" subtype = gold), 19,786 refl, 5,170 dawo; capped 200/key. Caveat: refl stream has false positives (plain dative objects) — filter against the curated table when generating.)
- [ ] Cross-check curated table against PONS / deutschlernerblog / mein-deutschbuch lists (facts only, no copying of example sentences)

Findings so far:
- Raw Wiktionary lists contain minor noise (a few miscategorized non-German titles, some multi-word Funktionsverbgefüge like "Abschied nehmen") — filter at dataset-build time, keep raw files untouched.
- All 47 `sep:true` table entries confirmed against the Wiktionary separable inventory. `übersetzen` is a known dual lexeme (separable "ferry across" vs inseparable "translate") — table has the inseparable reading, correctly.
- **Wiktionary's reflexive category is NOT exhaustive** (missing e.g. sich interessieren, sich kümmern) — treat `verb_praep_table.json` as the authority for reflexivity; use the category only as a supplementary pool.

## Phase 2 — Eval + local baseline (before any training)

Environment: `training/.venv` (Python 3.12 via uv, `mlx-lm` installed). Eval items live in
`data/eval/`; results in `results/` (gitignored).

- [x] v0 smoke eval built → `data/eval/grammar_eval_v0.json` (**60 items**: 48 correction items in the app's exact `FIX:`/`WHY:`/`OK` format — 8 error + 4 correct per phenomenon — plus 12 cloze items; all auto-scorable)
- [x] Harness built + scorer unit-tested offline → `scripts/run_baseline_eval.py` (`--dry-run` validates without a model)
- [x] **Base model downloaded** (`mlx-community/gemma-4-e4b-it-4bit` — the exact repo the app ships)
- [x] **Baseline run (2026-07-08)** — `results/baseline_gemma-4-e4b-it-4bit.json`:

      | Phenomenon | Correction | Cloze | Total |
      |---|---|---|---|
      | Verben mit Präpositionen | 10/12 | 3/3 | **13/15 (87%)** |
      | Trennbare Verben | 9/12 | 3/3 | **12/15 (80%)** |
      | Reflexive Verben | 7/12* | 2/3 | **9/15 (60%)** |
      | Da-/Wo-Komposita | 7/12 | 2/3 | **9/15 (60%)** |
      | **Overall** | | | **43/60 (72%)**, 0 format errors |

      *after accepting one valid alternative fix (refl-e6). Confirms the user's observation:
      reflexives and da/wo-compounds are the weak areas. Failure modes to target in training data:
      1. **FIX-echo on correct sentences** (5 of 16 correct items): outputs `FIX:` with the identical
         sentence + WHY "the sentence is correct" instead of `OK` — verdict discipline, very trainable,
         and directly hurts the app's correction UX.
      2. **Missed reflexive errors** ("Ich freue auf...", "das Auto nicht leisten" judged OK) and
         **removal of valid reflexives** ("Sie zieht sich die Schuhe an" → sich deleted).
      3. **Person vs thing confusion in da-compounds**: corrected "damit gesprochen" (about a person)
         to "darüber gesprochen" instead of "mit ihm".
      4. **Evasive rewrites** that dodge the target structure instead of fixing it
         ("stolz darauf" → drops the compound; "stelle mir vor" → rewrites to "Ich glaube").
      Re-run after training with `--tag finetuned --model <new repo>` for the before/after.

      Tooling notes (will matter again at conversion time): mlx-lm 0.31.3 needs a guarded
      `AutoTokenizer.register` monkeypatch under transformers 5.x (in the eval script); generation
      must pass `enable_thinking=False` to `apply_chat_template` or Gemma 4 emits `<|channel>thought`
      blocks (the harness also strips channel blocks, mirroring the app's `stripThinkBlocks`).

- [x] **Extension baseline (2026-07-08)** — 10 candidate weak areas tested (`data/eval/grammar_eval_v1_extra.json`, 61 items) → `results/baseline-extra_gemma-4-e4b-it-4bit.json`: **53/61 (87%)**.
      - **Strong, no training data needed**: word order 8/8, relative pronouns 6/6, Konjunktiv II 6/6, nicht/kein 4/4.
      - **Confirmed weaknesses**: haben/sein auxiliary (missed "hat eingeschlafen"; matches v0's missed "habe aufgestanden"); adjective endings 5/7; noun gender 7/8 ("der Gehalt" — small sample, but article accuracy is flashcard-critical → expand eval from Wiktionary gender data).
      - **The dominant failure is cross-cutting, not phenomenon-specific**: 10 of 28 correct sentences across both evals (36%) got a FIX-echo (identical sentence returned as a "fix", WHY admits it's correct) — N-Deklination and imperative knowledge was actually fine; only the verdicts failed. Plus repeated **evasive rewrites** (changed "Freund"→"Freundin" to dodge fixing the possessive case, altering meaning).
- [ ] Expand to the full eval (~150–200 items per phenomenon): scale up with error patterns mined from Falko/MERLIN (<https://huggingface.co/datasets/matejklemen/falko_merlin>) + LanguageTool/spaCy-validated production probes
- [ ] Keep `grammar_eval_v0.json` and all successors **strictly held out** of training data

### DeepL cross-checking (API key available)

Key lives in `training/.env` (gitignored — never commit it). Account limit: 1M chars lifetime; usage so far ≈ 5.6k.

- [x] Cross-check the English glosses in `verb_praep_table.json` → `scripts/deepl_gloss_check.py` (2026-07-07: 268 probes, 54 flagged, all reviewed = synonym paraphrases, **0 gloss errors**; 3 da-flags refined as a side effect: investieren in / sich irren in / sich vertiefen in → da:true). Full diff view in `results/deepl_gloss_check.json`.
- [ ] Phase 3 use: back-translation QC of synthetic training sentences (DE → EN via DeepL; a teacher model checks the EN matches the intended meaning) — budget ~50 chars/sentence, so even 10k sentences ≈ 500k chars; sample rather than translate everything

## Phase 3 — Synthetic training data

Teacher model (Claude/GPT) generates examples **in the app's exact prompt formats**
(conversation, `FIX:`/`WHY:` correction, translation, flashcard JSON). Target ~8–12k total.

- [x] Validators set up (2026-07-08): LanguageTool 6.8 self-hosted via `language_tool_python` (Java 17 present) + spaCy structural checks → `scripts/validate_data.py` (schema, eval-overlap guard, dedup, LT on the gold side, per-phenomenon structure checks). **Calibration finding: LT German misses our target error types entirely** (wrong fixed preposition, reflexive case, aux, word order all pass unflagged) — LT's role is surface QC of correct sentences only; spaCy + verb-table checks carry phenomenon verification.
- [x] Pilot batch generated + validated end-to-end (2026-07-08): 60 correction examples (refl 20, dawo 12, aux 12, verdict-discipline 16) via subagent → **59/60 passed** (`data/generated/pilot_correction_v1.valid.jsonl`); the 1 reject was the eval-overlap guard correctly catching "An was denkst du gerade?" (near-identical to held-out item dawo-e8). Schema: `data/generated/README.md`.
- [x] **Teacher-model A/B (2026-07-08): use Sonnet; Haiku ruled out.** Haiku sep batch: 42% of ok-verdict items were broken German labeled correct + ~6 flawed fixes — quarantined in `data/generated/quarantine/`. Sonnet vmp batch: 58/60 usable (2 borderline items dropped: "schützen gegen" is valid German, "sich nach der Grippe erholen" has a valid temporal reading); all 12 ok-items flawless. Sonnet batches take up to ~40 min — run 4+ in parallel. Generation prompts now include explicit flawless-ok-item + word-order rules.
- [x] **Wave 4 + packing (2026-07-09)**: pool at **960 validated** — 816 corrections, **94 conversations** (incl. Sie-formality, role-play scenario mode, deck-word weaving mode, 11-turn long dialogues), **50 flashcard lines**. `scripts/pack_dataset.py` renders everything with the app's exact prompt strings (ConversationPrompts / ConversationConfig / buildJSONPrompt replicas) + 516 mix-in examples → **`data/packed/train.jsonl` (1,447) + val.jsonl (29)**. Wave-4 quality: 2 hand-fixes (1 Lena "Daran→Darauf" earlier, 1 "Seid→Habt ihr angehalten"), comma fixes, 2 more LT whitelist rules (recommendation-level merges), role-play scenarios use an explicit string set in the packer. Ready for Phase 4 (Colab training).
- [ ] Old note — **superseded batch progress** (wave-3 state): 865 total (2026-07-08): 817 corrections (vmp 138, dawo 116, sep 116, refl 114, aux 88, verdict-ok 245 = 30%), **24 conversation dialogues** (7-turn Lena exchanges, all five phenomena — one hand-fixed Lena error: Daran→Darauf), **24 flashcard-JSON examples** (all noun genders verified correct; conjugations incl. sein-Perfekt + reflexive-separable combos). Wave 3: dawo person-slice redone in unambiguous partner-question format; vmp advanced tail incl. impersonal es-constructions; validator extended with conversation + flashcards branches (smoke-tested).
- [x] General-German mix-in downloaded: alpaca-gpt4-deutsch (51 MB) + sharegpt-deutsch (34 MB), both Apache 2.0, in HF cache.

  **Wave-2 lessons (bake into future prompts/pipeline):**
  - Two agents drifted to GERMAN why-notes → rewritten to English via a follow-up agent (DeepL unsuitable: it translates the quoted German terms too). Prompts now need an explicit "why in English, quote German words untranslated" line.
  - One agent emitted fix-FRAGMENTS instead of full sentences → validator now rejects non-sentence fixes; agent re-emitted via SendMessage.
  - **Two-sentence da/wo "person" items are systematically ambiguous** (da-compound can legitimately refer to the situation) — 10 of 12 dropped. Only the partner-question format ("Hast du mit deinem Chef gesprochen?") is unambiguous; regenerate that slice in wave 3.
  - Validator improvements: colloquial-register LT flags whitelisted; preposition contractions (zum/am/im...) recognized; full-sentence fix check added.
  - Optional-correlate over-corrections keep appearing ("Ich freue mich, dich zu besuchen" needs no darauf) — dawo prompts must list required-correlate verbs explicitly and ok-items must include bare dass-clauses.
- [ ] **At packing time: run cross-batch global dedup** — validate_data.py dedups only within a single file.
- [ ] Generate ~800–1,200 conversation exchanges per phenomenon (levels A1–C1, du/Sie)
- [ ] Generate ~600–1,000 correction pairs per phenomenon (balanced OK/FIX, errors modeled on Falko/MERLIN patterns, hard negatives included)
- [ ] **Verdict-discipline slice** (~15–20% of correction data): correct sentences — including near-miss lookalikes of common errors — whose gold answer is exactly `OK`. Targets the dominant baseline failure (36% FIX-echo rate on correct input).
- [ ] **haben/sein auxiliary slice** (~500 pairs): Perfekt with motion/change-of-state verbs; seed sentences mineable from Tatoeba (sein-Perfekt patterns)
- [ ] **Anti-evasion examples**: fixes must preserve the student's intended structure and meaning (counter the "Freund→Freundin" / drop-the-da-compound dodges)
- [ ] Light slices for adjective endings + noun-gender accuracy (gender folded into flashcard-JSON examples); **skip** word order, relative pronouns, Konjunktiv II, negation (baseline-strong)
- [ ] Generate ~300 flashcard-JSON examples featuring target verbs (schema from `MLXGenerationService.buildJSONPrompt`)
- [ ] Vocab injection: weave CEFR A1–B1 vocabulary through the same examples (Goethe lists as internal reference only; Wiktionary/Netzverb/Tatoeba as redistributable sources)
- [ ] Mix-in 30–40% general German to prevent forgetting: alpaca-gpt4-deutsch + sharegpt-deutsch (both Apache 2.0) + self-generated examples of the app's other tasks (translation, summary, phrase check)
- [ ] Validate + dedup everything; split train/val

## Phase 4 — Train (Unsloth on RunPod)

- [x] **RunPod bundle ready (2026-07-09)**: `runpod/gemma4_finetune_runpod.tar.gz` (339 KB) = train.jsonl (1,447) + val.jsonl (29, integrity-verified) + `train_gemma4_e4b.py` + runbook README. Script: QLoRA r=8/alpha=16, lr 2e-4, 2 epochs (EPOCHS env), `train_on_responses_only` with auto-detected Gemma-4 turn markers (env-overridable fallback), system-role fallback merge, saves LoRA + merged-16bit, optional private HF push via HF_TOKEN/HF_REPO.
- [x] **Trained (2026-07-09)** on RunPod RTX 3090 ($0.22/hr, ~20 min run ≈ $0.25 total incl. false start): 2 epochs, 362 steps, loss 0.39→0.21, `train_runtime` 1,147 s. One crash-and-fix: conversation dialogues needed the app's hidden `openerSeed` user turn for Gemma's user/assistant alternation (packer fixed; all 1,476 examples now validated against the real Gemma-4 template pre-upload). Gemma-4 turn markers auto-detected: `<|turn>user\n` / `<|turn>model\n`.
- [x] Pushed to private HF: `kessenma/gemma4-e4b-german-tutor` (merged 16-bit + `lora/` adapters + `loss_history.txt`; dataset at `kessenma/gemma4-german-tutor-data`). SSH-driven via proxy PTY; token in `training/.env` (rotate after project if desired).

### Qwen3-4B track (added 2026-07-09)

- [x] **Qwen3-4B baseline** (`mlx-community/Qwen3-4B-4bit`, the app's repo): core four **29/60 (48%)** — vmp 12/15, sep 7/15, refl 5/15, dawo 5/15 (0/3 on refl+dawo cloze); extension **35/61 (57%)** — weak nearly everywhere Gemma was strong (word order 4/8, relpron 3/6, K2 3/6, imperativ 1/4, wechsel 3/6, ndekl 3/6, aux 3/6); parity with Gemma only on artikel 7/8 + adjend 5/7. **Inverse failure profile vs Gemma**: false-correction rate only 19% (vs Gemma 36%) but misses/misfixes **61% of real errors** (vs Gemma ~23%) — Qwen lacks German grammar knowledge rather than verdict discipline.
- [x] Qwen3-4B fine-tuned on the shared dataset (same RunPod pod, env-driven script: MODEL_NAME/CHAT_TEMPLATE=native/OUT_PREFIX) → `kessenma/qwen3-4b-german-tutor`
- [x] **Qwen post-fine-tune (2026-07-09)**: core **37/60 (62%)** vs 29/60 base (+14 pts, refl 5→9), extension **39/61 (64%)** vs 35/61. Converted at `models/qwen3-4b-german-tutor-4bit` (2.1 GB; Unsloth config needed rope_theta patched from Qwen/Qwen3-4B before mlx-lm convert). **Conclusion: same dataset lifts Gemma +13 / Qwen +14 pts — consistent gain, but base-model German substrate sets the ceiling (tuned Qwen 62% < stock Gemma 72%).** Qwen-tailored wave 5 deprioritized: even a strong result wouldn't beat tuned Gemma E4B at the same size.

## Phase 5 — Convert + evaluate

- [x] **Converted (2026-07-09)**: mlx-lm convert FAILED on Gemma 4 (expects KV-shared-layer projections the checkpoint legitimately omits) → **use `mlx_vlm convert`** (the path all mlx-community Gemma-4 quants used): `models/gemma4-e4b-german-tutor-4bit`, 4.9 GB, 5.2 effective bits (PLE-safe mixed precision). Sanity generation clean — correct FIX/WHY format, fixed "auf es"→"darauf".
- [x] **RESULTS (fine-tuned 4-bit vs baseline 4-bit)**: core four **51/60 (85%)** vs 43/60 — vmp 15/15, sep 14/15, dawo 12/15 (60%→80%), refl 10/15 (60%→67%); extension **55/61 (90%)** vs 53/61 (ndekl 6/6, artikel 8/8). Behavioral: **false corrections 36%→22%, missed errors 17%→9%** — both improved. Remaining weakness: reflexives (still deletes valid sich in "zieht sich die Schuhe an"; still misses "Ich freue auf..."). Minor single-item slips in wo (8/8→7/8) and k2 (6/6→5/6).
- [ ] Wave 5 (optional iteration): reflexive-focused top-up + guard slices for wo/k2
- [x] **Multi-model baselines (2026-07-09, app's exact 4-bit repos)** — core / extension: Llama-3.2-1B **17/60 / 20/61**; Mistral-7B **26/60 / 30/61** (dawo 1/15, artikel 2/8 — drop as "high tier"; slow AND weakest-per-byte at German); Qwen3-4B **29/60 / 35/61**; Gemma-4-E4B stock **43/60 / 53/61**; Gemma-4-E4B fine-tuned **51/60 / 55/61**. Lesson: size ≠ German quality; Gemma's multilingual training dominates. Tier implication: fine-tuned E4B = mid+high tier.
- [x] **Gemma-3-1B baseline (qat-4bit, the app's repo): core 35/60 (58%), extension 36/61 (59%) — beats Qwen3-4B AND Mistral-7B.** Behavior: 0% false corrections, catches 45% of real errors (vs Llama-1B 0%); ndekl 6/6, refl corrections 9/12. Ideal fine-tune candidate for the entry tier (~800 MB): knowledge-recall deficit + perfect verdict discipline = low-risk training target. Llama-1B verdict: NOT salvageable (answered OK to all 69 error items).
- [x] **Gemma-3-1B fine-tune (2026-07-09): NEGATIVE RESULT — do not ship.** Core 19/60 (32%) vs 35/60 baseline; false-corrections 0%→56%. The 1B learned the FIX-producing *behavior* without the knowledge to aim it (train loss plateaued ~1.5 vs E4B's 0.21) — capacity cliff. Same dataset: E4B +13 pts, Qwen +14 pts, 1B −26 pts. **Entry tier = STOCK gemma-3-1b-qat** (58% core, 0% false corrections). Model kept at `kessenma/gemma3-1b-german-tutor` for reference only.

## Phase 6 — Ship in the app

- [ ] Add model case to `german-ai-flashcards/Models/ModelConfiguration.swift` + descriptors (size ~4 GB, RAM budget like gemma3n_E4B)
- [ ] Add the four new `GrammarFocus` cases (verbenMitPraepositionen, trennbareVerben, reflexiveVerben, daWoKomposita) with steering hints
- [ ] On-device eval pass + regression check on flashcard JSON parsing
- [ ] Ship

## Phase 7 — Low/mid tier (Gemma 4 E2B) ← full log in [`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md)

- [x] **E2B fine-tuned + evaluated (2026-07-13)**: core 65→68%, miss 28→19%, but false corrections 34→59% → originally benched "do not ship".
- [x] **Echo decomposition (2026-07-22): the 59% was a measurement artifact.** 18 of the 19 false corrections are the model echoing the input verbatim under `FIX:` — which `ConversationPrompts.parseCorrection` already discards. Re-scored app-equivalently: **core 83%, false-corr 3%, miss 19% — clears the ship bar and beats stock E2B on every axis.**
- [x] Eval harness now models the app: `apply_app_guard()` + `--app-guard` on `run_baseline_eval.py` and `behavior_metrics.py`. Raw generations still saved unmodified.
- [x] App guard hardened (`ConversationPrompts.echoNormalized`): dropped `.diacriticInsensitive` (it was swallowing real umlaut corrections — `Madchen`→`Mädchen`); added whitespace/trailing-punctuation folding (an echo plus a period used to leak through). Builds clean.
- [x] **B1 refuted**: Gemma 3 4B as a smaller/better base — QAT 50% core raw / 73% guarded, ties *stock* E2B and loses to the tune by 10 pts (dawo 3/15, evasive rewrites). Naive 4-bit is 7 pts worse than QAT — use QAT builds when comparing.
- [ ] **Ship tuned E2B for the 6–8 GB tier**: publish `kessenma/gemma4-e2b-german-tutor-4bit`, add the `ModelConfiguration` case, update the tier table
- [ ] Restate ship criteria on the guarded scale and re-report `MODEL_SCOREBOARD.md` with both columns
- [ ] A3-inverted: bias the verdict token *toward* `FIX` (the guard absorbs the downside) to attack the remaining 19% miss rate
- [ ] Small DPO run targeting the 2 remaining real defects: `sep-c3` (`zumachen`→`zuschlagen`) and the sep regression (11→8)

## Writing

- [ ] **Article draft**: `training/ARTICLE.md` — on-device tutor story + fine-tuning process, real numbers baked in; `[TODO]` sections await training results (latency comparison, loss curve, before/after eval table, ship status).
- [ ] **Revise ARTICLE.md §"Round two" and §"The floor"** — both tell a capacity-cliff story that the echo decomposition contradicts (see `GEMMA_E2B_FINETUNING.md`). The 1B cliff is still real; E2B was never on it.

## Risks / cautions

- **PLE quantization bug**: naive 4-bit MLX quants of Gemma 4 produced garbage (fixed in current mlx-lm/mlx-vlm) — always sanity-check generation after convert.
- **Chat template drift**: Gemma 4 changed roles/tokens vs 3n; take ground truth from the tokenizer, not blog posts.
- **Catastrophic forgetting**: without the general mix-in, JSON flashcard output and translation quality will regress. Eval those too.
- **License hygiene**: Tatoeba CC-BY 2.0 (attribution), Wiktionary/Netzverb CC-BY-SA (share-alike applies to a *redistributed dataset*; weights are generally treated as non-derivative but unsettled), Goethe lists copyrighted (internal reference only).
- **Public LanguageTool API is not for batch** — self-host (`java -jar languagetool-server.jar` or Docker).

---

# Image Generation Track — on-device story illustrations (added 2026-07-20)

Parallel to the LLM tutor: the CoreML model that draws Short-Story illustrations and AI
flashcard pictures (`ImageGenModel.swift` / `StoryImageService.swift`). Ships **SD 2.1 base
palettized** today (~1.2 GB). Goal: evaluate smaller/faster distilled alternatives, convert
the viable ones on-Mac, test locally, host on HF, and map picks to device tiers — the same
measure-then-ship discipline as the LLM track. Full survey + verdicts in `MODEL_SCOREBOARD.md`
(Image generation section).

## Key decisions

| Decision | Choice | Why |
|---|---|---|
| Convert on | **Mac, not RunPod** | CoreML compile (`coremlcompiler`) + validation are macOS-only; conversion is CPU/RAM-bound, so a rented GPU is idle spend |
| Converter | `apple/ml-stable-diffusion` 1.1.1 `torch2coreml` (py3.9 venv, `training/imagegen/`) | The frozen-but-working toolchain the app already targets; `--bundle-resources-for-swift-cli` emits exactly the `Resources/` layout `StableDiffusionPipeline(resourcesAt:)` wants |
| Attention | **ORIGINAL** → `.cpuAndGPU` | Background task grants GPU, not ANE — nota-ai's shipped `split_einsum` zips are wrong for our path |
| Host | HF `kessenma/coreml-<model>` (public) | `ResumableModelDownloader`/`HubCacheLocation` already speak HF hub-cache layout → new `ImageGenModel` case is the only app change |
| App config | **per-model** steps/guidance/neg-prompt | SDXS is 1-step / guidance-1 / no neg-prompt; today's `ImageGenConstants` hardcodes 25 steps / 7.5 |

## Candidates (why these two first)

- **BK-SDM-Tiny** — block-removed knowledge-distilled SD1.4, 0.5 B, ~10 steps, OpenRAIL-M. Same
  pipeline family as current SD2.1 → lowest integration risk. Must convert ORIGINAL (its HF repo
  ships ANE `split_einsum` zips, not the GPU layout our background task needs).
- **SDXS-512-DreamShaper** — 1-step, ~0.89 GB, OpenRAIL++. Biggest latency win on the current
  toolchain; needs the `vae_large` swap (default `vae/` is a TAESD tiny-AE) + guidance=1.

## Phase I1 — Survey  ← DONE (2026-07-20)

- [x] Map the coupling: only `StoryImageService.swift` + `ImageGenModel.swift` import
  `StableDiffusion`; everything else is prompt→CGImage→PNG. Swap = 1 file + 1 enum.
- [x] Survey the field (FLUX / Wan / Chroma / SDXL / turbo / distilled / MLX / Draw Things /
  Image Playground) → `MODEL_SCOREBOARD.md`. Verdicts: FLUX/Wan/Chroma too big; SDXL too slow;
  SANA/Cascade/Kolors license-blocked; **BK-SDM + SDXS the viable converts**; FLUX.2 Klein 4B is
  the iOS-27 frontier. Confirmed `ml-stable-diffusion` frozen at 1.1.1, `ImageCreator` dead in
  iOS 27, DiffusionKit archived, sd.cpp iOS unsupported.

## Phase I2 — Convert (Mac)  ← DONE (2026-07-20)

- [x] Toolchain: `training/imagegen/.venv-coreml` (py3.9, torch 2.8, **coremltools 7.2**, diffusers
  0.36) + `ml-stable-diffusion` @ pinned `5a170d29`, patched via `patch_converter.py`. **coremltools 9
  bakes NaN — must pin 7.2.** `setup_toolchain.sh` rebuilds it.
- [x] BK-SDM-Tiny → ORIGINAL/GPU, **fp16** (948 MB). Palettization skipped — the frozen converter's
  k-means path is broken under modern coremltools; fp16 is already < the current 1.2 GB.
- [x] SDXS-512-DreamShaper → ORIGINAL, `vae_large`, fp16 (933 MB). Needed 3 converter patches
  (mid_block=None, only_cross_attention, variant=fp16→None).
- [x] BK-SDM-Base → converted but renders **noise**; dropped (marginal value).

## Phase I3 — Test locally  ← DONE (2026-07-20)

- [x] Validate via **Swift `StableDiffusionSample` on the Neural Engine** — coremltools Python predict
  AND the Mac GPU both render black here (macOS-26 Metal fp16 regression; memory
  `coreml-sd-fp16-mac-gpu-black`). Swift+ANE is the only truthful path on this Mac.
- [x] **BK-SDM-Tiny: ✅ coherent** watercolor at ~10 steps in the app's exact runtime. Ships.
- [x] **SDXS: ✅ gorgeous 1-step in PyTorch, ❌ off-prompt in Apple's Swift pipeline** — no scheduler
  matches its single fixed-timestep denoise (1-step dpmpp = coherent-but-off-prompt; multi-step = blur).
  Blocked on a custom Swift scheduler.
- [x] Results recorded in `MODEL_SCOREBOARD.md` (Conversion log).
- [ ] Still open: on-device (iPhone) confirmation that `.cpuAndGPU` renders Tiny correctly (expected
  yes — Apple's fp16 SD2.1 runs there; only this Mac's GPU is affected). Peak-RAM/seconds-per-image.

## Phase I4 — Host on HF  ← DONE (2026-07-20)

- [x] Pushed `original/compiled/*` → **`kessenma/coreml-bk-sdm-tiny`** (public) with OpenRAIL-M
  LICENSE + README (attribution to nota-ai/bk-sdm-tiny-2m). Upload script: `imagegen/upload_bksdm.py`.
- [ ] SDXS held — not usable in Apple's pipeline (scheduler); local convert kept, not published.

## Phase I5 — App integration  ← DONE (2026-07-20, builds clean)

- [x] `ImageGenModel` now multi-case (`sd21Base`, `bkSdmTiny`); `current` is UserDefaults-backed and
  user-selectable. BK-SDM-Tiny needs **no** `ImageGenConstants` change — same scheduler (dpmSolver)
  + guidance 7.5 + no-safety as SD 2.1, so the existing pipeline drives it unchanged.
- [x] Settings picker in `ImageGenerationSection.swift` (per-model size labels, unloads pipeline on
  switch); hardcoded "Stable Diffusion" strings genericized. `ImageGenModel+Descriptors` gets the
  BK-SDM info-sheet metadata.
- [x] Default active model set to **BK-SDM-Tiny** so Stories + flashcards use it out of the box.
  Stop/background-abort unchanged (shared pipeline path).
- [ ] **On-device check still open**: confirm `.cpuAndGPU` renders BK-SDM-Tiny on a real iPhone (Mac
  GPU can't be tested — its Metal fp16 is broken). If it's black on device, either switch the picker
  to SD 2.1 or convert a `split_einsum` (ANE) variant.

## Phase I6 — Device-tier recommendations

- [ ] Map converted+tested models to RAM tiers (entry / low-mid / high) with measured numbers
- [ ] Auto-pick a sensible default per device RAM (mirror the LLM tier logic)

## Risks / cautions (image track)

- **Frozen converter + modern deps**: `ml-stable-diffusion` 1.1.1 targets py3.8–3.10 / coremltools
  7–8; pin the venv to py3.9. Always sanity-generate after convert (a "successful" convert can
  still emit garbage — same rule as the Gemma PLE bug).
- **ORIGINAL vs split_einsum is not cosmetic**: an ANE model in the GPU-granted background task
  can be suspended when backgrounded. Convert ORIGINAL for the story path.
- **SDXS TAESD**: point the converter at `vae_large`; the default tiny `vae/` is a different arch.
- **License redistribution**: OpenRAIL requires shipping the license + use-restrictions in the
  re-host repo — not just a tag.
