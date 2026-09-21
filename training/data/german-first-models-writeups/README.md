# German-first models on the app's grammar task

Every model here was pretrained or re-adapted **for German specifically**, posted competitive German
benchmark numbers, and was evaluated as a possible tutor for this app. One file per family.

| family | best measured | size (4-bit) | licence | verdict |
|---|---|---|---|---|
| [LLäMmlein](llammlein.md) (Uni Würzburg) | **73%** EN 3-shot, stock | 3.5 GB | Research-only RAIL-M | ❌ good German, wrong tier, unusable licence |
| [ELMOD](elmod.md) (Fraunhofer IIS) | **72%** EN 3-shot, stock | 1.6 GB | CC BY-NC-4.0 | ⚠️ strongest 4 GB base measured; licence unresolved |
| [BübleLM](bueble.md) (Flair) | 7% strict / 25% lenient | 1.1 GB | Apache 2.0 | ❌ far below the fine-tune floor |
| [Apertus](apertus.md) (EPFL/ETH/CSCS) | **72%** EN 3-shot (8B) · **70%** (4B) | 0.8 / 2.0 / 4.6 GB | **Apache 2.0** | ⚠️ v1.1-**4B** the only candidate worth tuning — stock-E2B quality at 60% the size; 1.5B ❌, 8B ❌ |

All numbers are **core v0 (60 items), guarded** — scored the way the app actually behaves, where a
reply the app renders as nothing counts as nothing. Anchors on that same suite:

```
Gemma 4 E4B tuned (hero)   90%   4.9 GB, shipped
Gemma 4 E2B tuned          83%   3.3 GB, shipped
Gemma 4 E4B stock          80%   4.9 GB
Gemma 4 E2B stock          73%   3.3 GB   (44/60, measured guarded 2026-08-17)
LLäMmlein 7B chat 3-shot   73%   3.5 GB
Apertus-8B 3-shot          72%   4.6 GB
ELMOD 3-shot, stock        72%   1.6 GB
Apertus v1.1-4B 3-shot     70%   2.0 GB
LLäMmlein 7B base 3-shot   68%   3.9 GB
Granite 3.3 2B stock       57%   1.5 GB
Apertus v1.1-4B zero-shot  55%   2.0 GB   (0 format errors — see below)
Apertus v1.1-1.5B 3-shot   37%   0.8 GB
Gemma 3 1B stock           33%   0.8 GB, shipped (4 GB tier)
BübleLM-2B-SFT             25% lenient / 7% strict
```

## What four families agree on

### 1. `dawo` is the shared wall

Per-phenomenon, core v0 guarded, all 15 items per phenomenon, best condition for each model:

| | vmp | sep | refl | **dawo** |
|---|---|---|---|---|
| ELMOD 2.7B-it, EN 3-shot | 15/15 | 13/15 | 11/15 | **4/15 (27%)** |
| LLäMmlein 7B chat, EN 3-shot | 14/15 | 14/15 | 11/15 | **5/15 (33%)** |
| LLäMmlein 7B base, EN 3-shot | 10/15 | 14/15 | 12/15 | **5/15 (33%)** |
| LLäMmlein 1B chat, DE 3-shot | 7/15 | 10/15 | 9/15 | **2/15 (13%)** |
| Apertus-8B, EN 3-shot | 14/15 | 12/15 | 12/15 | **5/15 (33%)** |
| Apertus v1.1-4B, EN 3-shot | 14/15 | 11/15 | 12/15 | **5/15 (33%)** |
| Apertus v1.1-1.5B, EN 3-shot | 9/15 | 3/15 | 8/15 | **2/15 (13%)** |
| BübleLM-2B-SFT | — | — | — | — *(never rendered a verdict; not scorable per phenomenon)* |
| **Gemma 4 E2B stock, zero-shot** *(not German-first — the control)* | **14/15** | **12/15** | **9/15** | **9/15 (60%)** |

Three of the app's four target areas reach 73–100% with three examples. The fourth never clears 33%
in any model, at any size, in any prompt condition. Counting **error items only** — the slice that
asks "does it catch a real mistake" — LLäMmlein's `dawo` is **0–1 of 8 everywhere**; the `/15`
figures above are inflated by already-correct sentences it passes by accepting.

Da-/wo-compounds are the phenomenon German learners struggle with most. No German-first model
measured here can do them, and few-shot barely moves it. Treat it as a pretraining gap that a
fine-tune must fix from near-zero, not a prompting artifact.

**The control row is the strongest evidence.** Gemma 4 E2B stock — not German-first, merely
well-trained multilingually — scores **9/15 (60%)** on `dawo` zero-shot while matching or beating
every German-first model on the other three areas. Four German-first families, spanning 0.8 B to
7 B parameters and four independent pretraining corpora, all cap at ~33%. Whatever produces
da-/wo- competence, **"more German pretraining data" is demonstrably not it.**

### 2. German benchmark scores do not predict this task

BübleLM posts 47.9% HellaSwag-DE and scores 7% here. ELMOD's card claims "matching 7B models in
German" and it scored 12% on the app's real prompt. Model cards measure German *knowledge*; this
suite measures the *job* — rendering a parseable verdict about someone else's sentence. They
disagree every time, and only one of them gates shipping.

### 3. The failure mode is task discipline, not German

All four know German. BübleLM correctly fixes *warten für→auf* while never once emitting a bare
`OK`. ELMOD answered in fluent English prose. LLäMmlein's 7B echoes the input into `FIX:` and buries
the real correction in commentary. Apertus-8B produced *"The student's sentence is grammatically
correct, but it can be improved..."* — with the correct fix inside the prose, scored zero. The German
content is repeatedly right; what is missing is the instruction-following discipline to deliver it in
a fixed shape.

Apertus supplies the counter-example that makes this concrete: its **v1.1-4B scores 0 format errors
zero-shot** while its own 8B sibling fails 48 of 48. Same family, same tokenizer, different chat
template. Task discipline tracks the instruction-tuning recipe, not the German.

## What they disagree on — and the correction it forced

ELMOD produced a rule that looked general and **is not**: translate the prompt to German for a
German-first model. LLäMmlein inverts it.

| | English 0-shot | German 0-shot |
|---|---|---|
| ELMOD 2.7B-it (German+English) | 12% (format 2%) | **53%** (format 100%) |
| LLäMmlein 7B chat (German-only) | **58%** (format 94%) | 23% (format 23%) |

LLäMmlein is *more* German-first than ELMOD — German-only RedPajama V2 vs German+English — and gets
**worse** from a German prompt. So the effect was never "German-first models want German prompts";
it was ELMOD-specific.

**What actually carries the format is the worked examples**, in either language: 3-shot gives 100%
adherence for both models. Standing criteria, revised:

- **Ship criterion:** English zero-shot. It is what the app sends. Do not soften it — that is how
  the Gemma-3-1B fake-58% happened.
- **Base-selection criterion:** **few-shot compliance.** Zero-shot answers "can we ship it," which
  is a poor proxy for "can we tune it." The ~55% lenient floor got ELMOD badly wrong (45% lenient vs
  72% few-shot on the same weights).
- **Prompt language:** a per-model variable to *test*, not a known correction. Run the control
  (SauerkrautLM went 53% → 50% under a German prompt, i.e. no lift) before rescoring anything.

## Harness traps this family has produced

Each one yields a *plausible wrong number* rather than an error. Per-family detail in the linked
files:

| trap | family | symptom |
|---|---|---|
| Tokenizer omits its own chat-control tokens | ELMOD | never emits EOS; runs to max_tokens into pretraining text |
| `mlx_lm` arch hardcodes an activation `config.json` overrides | ELMOD | greedy decode diverges at token ~20; nothing crashes |
| Repo mislabels `tokenizer_class` | LLäMmlein | spaces and umlauts destroyed on encode **and** decode; scored 0/60 |
| Untied `lm_head` + EOS colliding with `<unk>` | BübleLM | correct answer, then `<unk>` spam to max-tokens |
| Adapter targets a *different* base than the release | LLäMmlein | silent garbage if merged onto the wrong checkpoint |
| Version bump changes `model_type` | Apertus | `v1.5` is `apertus1p5` + multimodal + gated; mlx-lm supports `apertus` only. Reads as "unsupported model", is actually "wrong repo" |
| `mlx_lm convert` throws *after* quantizing | Apertus | `save()` re-resolves the repo `local_files_only=True`; missing `README.md` aborts a successful conversion. `snapshot_download` in full first |

The general shape: **a model can fail an eval for being bad, or for never having been run
correctly, and those look identical in a summary table.** Verify before trusting a score.
