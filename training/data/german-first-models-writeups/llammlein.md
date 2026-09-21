# LLäMmlein (LSX-UniWue, Uni Würzburg) — good German, wrong tier, unusable licence

**Verdict: measured, genuinely strong, not worth the licence bureaucracy.**
`LLaMmlein_7B_chat` scores **73% guarded on core v0 with a 3-shot prompt**, stock — the best
non-Gemma stock number on this bench, edging [ELMOD](elmod.md)'s 72%. But it lands at **3.5 GB in
the 8 GB tier**, where the shipped hero already scores **90%**, and it is **research-only RAIL-M**.
Its 73% is level with *stock Gemma 4 E2B* (73%), which is smaller, cleanly licensed, and **83% once
tuned**.

> ⚠️ **`dawo` never clears 33% in any condition**, and counting error items only it is **0–1 of 8
> everywhere** — both sizes, base and chat, all four prompt modes. The 73% is carried entirely by
> `refl`/`sep`/`vmp`. This is the class collapse the plan process exists to catch, and it is the
> [family-wide wall](README.md#1-dawo-is-the-shared-wall).

Ran 2026-08-17 against `data/eval/grammar_eval_v0.json` (60 items), all `--app-guard`, greedy decode
(one condition was re-run and reproduced exactly). Harness:
[`scripts/eval_llammlein.py`](../../scripts/eval_llammlein.py),
[`scripts/merge_llammlein_chat.py`](../../scripts/merge_llammlein_chat.py).
Family index: [README.md](README.md). Scoreboard: [`MODEL_SCOREBOARD.md`](../../MODEL_SCOREBOARD.md).

## What it is

Trained from scratch at Uni Würzburg on the **German split of RedPajama V2** — the
[dataset card](https://huggingface.co/datasets/LSX-UniWue/LLaMmlein-Dataset) confirms a *"strict
subset"*, 838M rows, **no English by construction**. Llama architecture (adapted TinyLlama
codebase), custom German tokenizer. Paper: [arXiv 2411.11171](https://arxiv.org/abs/2411.11171).

| | `LLaMmlein_1B` | `LLaMmlein_7B` | `LLaMmlein_7B_chat` |
|---|---|---|---|
| params / layers | 1.1B, 22 × 2048 | 6.7B, 32 × 4096 | same as 7B |
| attention | GQA (4 KV heads) | **MHA (32 KV)** | **MHA (32 KV)** |
| context | 2048 | 4096 | **32768** (YaRN, factor 8) |
| 4-bit on disk | **0.67 GB** @ 5.00 bpw | **3.9 GB** @ 5.00 bpw | **3.5 GB** @ 4.50 bpw |
| instruction-tuned | ❌ no chat template | ❌ no chat template | ✅ ChatML, by the authors |

**The 7B is the largest LLäMmlein that exists.** `LLaMmlein_32B` is an **empty repo** (1 file, 0
bytes, 0 downloads); `LLaMmlein_120M` is 120 *million* params, their smallest. There is no 120B.

The 1B chat variants (`_chat_all`, `_chat_selected`) are LoRA adapters on
**`LLaMmlein_1B_prerelease`** — a *different* base (vocab 32000 vs 32064), not on `LLaMmlein_1B`.
Merging onto the wrong one silently produces garbage. Both ship full `embed_tokens`/`lm_head`
despite `adapter_config.json` claiming `modules_to_save: null`, so the ChatML rows *are* trained.

The authors' own caveat, from the chat model cards: *"chat versions are research demonstrations and
are not ready to be used in settings where close instruction following is necessary."*

## Results — core v0 (60 items), guarded

| model | prompt mode | core | accepts OK | catches errors | cloze | format |
|---|---|---|---|---|---|---|
| **7B chat** | **English 3-shot** | **44/60 (73%)** | 15/16 | 22/32 | 7/12 | 100% |
| 7B chat | German 3-shot | 41/60 (68%) | 14/16 | 20/32 | 7/12 | 100% |
| **7B base** | **English 3-shot** | **41/60 (68%)** | **16/16** | 17/32 | 8/12 | 100% |
| 7B base | German 3-shot | 40/60 (67%) | 14/16 | 18/32 | 8/12 | 100% |
| 7B chat | English 0-shot *(ship)* | 35/60 (58%) | 11/16 | 17/32 | 7/12 | 94% |
| 1B chat (merged) | German 3-shot | 28/60 (47%) | 13/16 | 10/32 | 5/12 | 100% |
| 1B base | German 3-shot | 22/60 (37%) | 15/16 | 7/32 | 0/12 | 92% |
| 1B base | English 3-shot | 20/60 (33%) | 14/16 | 6/32 | 0/12 | 90% |
| 7B chat | German 0-shot | 14/60 (23%) | 2/16 | 5/32 | 7/12 | 23% |
| 1B chat (merged) | English 0-shot | 5/60 (8%) | **0/16** | 0/32 | 5/12 | 25% |

### Most of the score is substrate, not instruction tuning

Base vs chat, same prompt condition:

| | base | chat | delta |
|---|---|---|---|
| English 3-shot | 68% | 73% | +5 |
| German 3-shot | 67% | 68% | +1 |

The authors' SFT buys **+1 to +5 points** once examples are in the prompt — real but small. What is
being measured at 67–73% is overwhelmingly the **pretraining substrate**, which is the relevant fact
for a fine-tune-base decision, and it is a good substrate: well clear of the ~55% floor.

Two details favour the *base* model. It never false-corrects (**0/16**, vs the chat's 1–5/16), and
it matches or beats the chat on `dawo` (5/15 vs 5/15 English, 4/15 vs 3/15 German). Where the SFT
earns its keep is zero-shot: without examples the base has no verdict format at all, while the chat
reaches 94% adherence.

That also means the 1B's failure is a **capacity** result, not a tuning artifact: same corpus, same
recipe, 37% base / 47% chat.

### Per phenomenon (all 15 items each, comparable to [ELMOD](elmod.md))

| condition | vmp | sep | refl | **dawo** |
|---|---|---|---|---|
| 7B chat, EN 3-shot | 14/15 | 14/15 | 11/15 | **5/15** |
| 7B base, EN 3-shot | 10/15 | 14/15 | 12/15 | **5/15** |
| 7B chat, DE 3-shot | 13/15 | 14/15 | 11/15 | **3/15** |
| 7B base, DE 3-shot | 11/15 | 13/15 | 12/15 | **4/15** |
| 7B chat, EN 0-shot | 11/15 | 12/15 | 9/15 | **3/15** |
| 1B chat, DE 3-shot | 7/15 | 10/15 | 9/15 | **2/15** |
| 1B base, DE 3-shot | 4/15 | 6/15 | 8/15 | **4/15** |

Counting **error items only**, `dawo` is 0–1 of 8 in every row above. The `/15` numbers are lifted
by already-correct sentences the model passes by accepting.

### The dominant failure: echoing

Across conditions, **20–35 of 48** correction items produce a `FIX:` line that just repeats the
input. The app guard folds those to `OK`, so the learner sees nothing. Worked example from the 7B:

```
FIX: "Ich interessiere für Musik."                              <- the input, unchanged
Der Satz ist grammatikalisch korrekt, aber ...
Eine bessere Version könnte sein: "Ich interessiere mich für Musik."   <- the right answer, in prose
```

It knows the correction and puts it in the wrong place, while asserting the broken sentence is
correct. That is why raw scores and guarded scores diverge so far here.

## Two findings that change how the next candidate gets scored

### 1. ELMOD's "translate the prompt" lesson does NOT generalise — it inverts

| | English 0-shot | German 0-shot |
|---|---|---|
| ELMOD 2.7B-it (German+English) | 12% (format 2%) | **53%** (format 100%) |
| LLäMmlein 7B chat (German-only) | **58%** (format 94%) | 23% (format 23%) |

LLäMmlein is *more* German-first and gets *worse* from a German prompt. What carries the format is
the worked examples, in either language: 3-shot → 100% adherence for both models. Full reasoning and
the revised standing criteria in [README.md](README.md#what-they-disagree-on--and-the-correction-it-forced).

### 2. A repo can mislabel `tokenizer_class`, and `AutoTokenizer` believes the label over the file

The 1B chat adapters ship a **ByteLevel-BPE** `tokenizer.json` (vocab uses `Ġ` for space, `Ã¼` for
`ü`) while declaring `"tokenizer_class": "LlamaTokenizer"` — SentencePiece semantics. transformers
honours the label and reinterprets every word-boundary marker, on **both encode and decode**:

```
AutoTokenizer            "Ich warte für den Bus."  ->  "IchwartefrdenBus."      spaces + ü destroyed
PreTrainedTokenizerFast  (identical file)          ->  "Ich warte für den Bus."   round-trips
tokenizers.Tokenizer     (identical file)          ->  "Ich warte für den Bus."   round-trips
```

`mlx_lm` loads via `AutoTokenizer`, so the model received corrupted prompts and its replies decoded
to corrupted text (`FIX:IchwartefrdenBusan.`). It scored **0/60** — a measurement of the loader.
Rebuilding the tokenizer with `PreTrainedTokenizerFast` took the same weights to **47%**.

**The check that catches it:** round-trip a German string containing a space and an umlaut *through
`AutoTokenizer`* — not through `tokenizers.Tokenizer`, which reads the file's own components and
passes even when the wrapper is broken. The 7B chat repo is unaffected (its Metaspace tokenizer
genuinely matches its label), so this is per-repo, not per-family. Pre-fix runs are preserved as
`results/llammlein_BROKEN-TOKENIZER_*.json`.

### The English tokenizer tax

Measured fertility, LLäMmlein vs Gemma 4:

| text | LLäMmlein | Gemma 4 |
|---|---|---|
| German sentence | **1.24** tok/word | 1.29 |
| the app's English system prompt | **2.12** tok/word | 1.06 |
| an English `WHY:` line | 1.73 | 1.13 |

`sentence` → `['sen','ten','ce']`, `meticulous` → `['me','tic','ul','ous']`, `student` →
`['stu','dent']`. Better than Gemma on German, **2× worse on English** — which is what the app's
prompt is written in, and what the `WHY:` line is required to be. The scorer only checks the `FIX:`
line, so the German-prompt conditions above measure its German fairly, without the English penalty.

## Licence — the actual blocker

**Research-only RAIL-M**
([`license.md`](https://huggingface.co/LSX-UniWue/LLaMmlein_1B/raw/main/license.md)), materially
stricter than ELMOD's CC BY-NC:

- §1(m) *"**Permitted Purpose** means for academic or research purposes only."*
- §2 and §3 grant copyright and patent licences **"only in connection with the Permitted Purpose."**
- §6.5 *"You and any Third Party recipients of the Artifact or its **Derivative** shall adhere to
  the Permitted Purpose."* — a fine-tune inherits.

CC BY-NC turns on whether use is commercial, so a no-IAP app had a good-faith reading. Research-only
has no such opening: a consumer App Store release is not "academic or research," free or not.
**Measuring is squarely permitted — that is research. Shipping requires a separate grant from
Würzburg.**

This binds harder on **using it to generate training data**: the corpus and every model trained from
it sit inside the Derivative clause. Declining to ship one model is recoverable; a contaminated
corpus follows every future tutor trained from it. The current teacher
(`data/generated_sonnet_v2`) is both stronger and licence-clean.

## Recommendation

**Don't open the licence conversation.** Not because the model is weak — 73% stock is the strongest
non-Gemma result measured here — but because of where it lands:

- At **3.5 GB it is an 8 GB tier model**, and that tier ships **Gemma 4 E4B German at 90%**.
- Its stock 73% **ties stock Gemma 4 E2B**, which is *smaller* (3.3 GB) and reaches **83% tuned**.
- The best realistic outcome is a research-only-licensed model matching something already shipped
  under a clean licence, in the tier that is already the app's strongest.
- It would arrive with `dawo` needing to be fixed from ~0/8.

**What would have changed this:** a *1B* near 70% would be a real result — 0.67 GB at tuned-Granite
quality would unlock the 4 GB tier. It isn't: 37% base, 47% chat, both under the ~55% floor. The
size that performs is the size with no gap to fill.

## Caveats

- **The v2 holdout is unspent.** Nothing here touched it; it is scored once per candidate.
- **`dawo` may be a data gap rather than a capability ceiling** — tuning lifted other models on it.
  But 0–1/8 is a worse starting point than Gemma 4 had.
- **The 7B's 32k context is YaRN-extended** from 4096 (`rope_scaling.factor: 8.0`). `mlx_lm`
  implements YaRN (`rope_utils.YarnRoPE`) so the scores are sound, but long-context quality is
  unverified — every prompt here is under 700 tokens.
- **MHA, not GQA:** ~524 KB/token of KV vs Mistral 7B's ~131 KB. Immaterial at correction length
  (~800 MB at 1.5k tokens), significant for conversation or story use.
- **3-shot demos were hand-written** and cover OK/FIX/FIX deliberately — a fix-only demo set teaches
  "always fix" (the `packed-v2` lesson). One draw, not a distribution.
- **4-bit only**, no BF16 control. Mac readings; no device memory measurement was taken, since
  nothing here justified one.

## Reproduce

```bash
cd training
# NB: download without *.bin or mlx_lm convert trips IncompleteSnapshotError on the repo id —
# convert from the snapshot path instead.
.venv/bin/python -c "from huggingface_hub import snapshot_download; \
    snapshot_download('LSX-UniWue/LLaMmlein_7B_chat', ignore_patterns=['*.bin'])"
SNAP=$(ls -d ~/.cache/huggingface/hub/models--LSX-UniWue--LLaMmlein_7B_chat/snapshots/*/ | head -1)
.venv/bin/python -m mlx_lm convert --hf-path "$SNAP" -q --q-bits 4 --mlx-path models/llammlein-7b-chat-4bit

.venv/bin/python scripts/eval_llammlein.py --model models/llammlein-7b-chat-4bit --mode fewshot
.venv/bin/python scripts/eval_llammlein.py --model models/llammlein-7b-chat-4bit --mode english

# 1B chat: merge the LoRA onto its OWN base (prerelease), repairing the tokenizer_class mislabel
.venv/bin/python scripts/merge_llammlein_chat.py --adapter LSX-UniWue/LLaMmlein_1B_chat_all \
    --out models/llammlein-1b-chat-all-merged
.venv/bin/python -m mlx_lm convert --hf-path models/llammlein-1b-chat-all-merged -q --q-bits 4 \
    --mlx-path models/llammlein-1b-chat-all-4bit

# base models have no chat template — use the raw-completion modes
.venv/bin/python scripts/eval_llammlein.py --model models/llammlein-7b-4bit --mode base_german
```
