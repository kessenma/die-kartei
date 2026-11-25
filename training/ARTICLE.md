# Teaching a Pocket-Sized AI German Grammar: Fine-Tuning an On-Device Tutor

*Draft — remaining [TODO]s: on-device latency numbers, App Store link, and a few
late-arriving baselines still running on the eval bench.*

> **⚠️ Two scoring corrections are folded into this draft — both worth reading before the
> numbers below.**
>
> **2026-07-22 — E2B was never on the cliff.** "Round two" and "The floor" were built on E2B's
> 59% false-correction rate, which was an artifact of the *eval*, not the model: 18 of the 19
> false corrections were the model echoing the student's sentence back under a `FIX:` header,
> which the app has always discarded. Scored as the app behaves, the tuned E2B lands at **83%
> core / 3% false corrections** and shipped on 2026-07-22. The 1B cliff is still real.
>
> **2026-07-30 — stock Gemma 3 1B was never 58%.** The same guard was missing
> `parseCorrection`'s `hasPrefix("OK\n")` clause, so a reply opening `OK` and then appending a
> real `FIX:` got credited twice over. That model emits exactly that shape on nearly every
> input and the app shows **none** of it: true score **34% core, 100% miss**, not 58%/55%. It
> is not the cautious floor this article described. See the correction note in "The floor" and
> the new section "Round three".
>
> Full workings: [`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md) and
> [`training-v2.md`](training-v2.md) §3.2. Gemma 4 numbers are unaffected throughout.

I've been building a German learning app with a turn-based AI tutor that runs entirely
on the phone. No server, no API key, no network round trip — the model lives on the
device, and you can practice spoken German with it on a plane. This is the story of why
I decided to fine-tune that model, what I learned about where small on-device models
actually fail at German, and the pipeline I built to fix it.

## The app, briefly

The core of the app is a conversation partner: you talk (out loud — speech recognition
feeds the model), it answers in German, keeps the conversation flowing, and quietly
adapts to your CEFR level and du/Sie preference. A separate correction pass reviews each
thing you said and either accepts it or returns a fix with a one-line explanation. The
same on-device model also generates vocabulary flashcards as structured JSON, translates,
and validates phrases you've picked up in the wild.

Everything runs on Apple's MLX stack with a 4-bit quantized **Gemma 4 E4B** — just under
5 GB on disk, comfortably within a modern iPhone's memory budget.

## Why on-device

When I researched similar tutor apps, almost all of them call a server-side model. The
surprising thing: the on-device approach is *faster* in practice. There's no network
round trip and no queueing behind other users — first tokens start streaming from local
silicon almost immediately, which matters enormously for a turn-based spoken
conversation where a two-second pause feels like talking to a wall.

[TODO: latency comparison numbers vs. the server-based apps tested — time-to-first-token
and full-reply times.]

I've built other on-device AI apps, and my honest read of the current state: **language
tasks are the sweet spot.** Conversation, translation, grammar correction, structured
generation — a 4B-class model handles these well enough to ship. Heavier patterns like
RAG over large document sets are not really feasible on-device yet — the retrieval
infrastructure, context lengths, and memory pressure fight you at every step. But a
tutor is almost a pure language task, which makes it one of the best possible fits for
on-device AI today. And these models are advancing fast — Gemma's E-series effectively
doubled in usable quality within a year while staying phone-sized.

## The problem: four grammar areas where the model quietly fails

Using the app daily, I noticed the tutor was unreliable in exactly the areas German
learners struggle with most:

1. **Verbs with fixed prepositions** — *warten auf*, *sich freuen über/auf*, *denken an*
2. **Separable verbs** — *aufstehen → ich stehe … auf*, participle *aufgestanden*, *aufzustehen*
3. **Reflexive verbs** — including the accusative/dative distinction (*ich wasche mir die Hände*)
4. **Da-/wo-compounds** — *darauf/worauf* for things vs. *auf ihn* for people

A tutor that makes the same mistakes as its students is worse than useless — it
*confirms* the student's errors.

## Measure first: building the eval

Before generating a single training example, I built a held-out evaluation set that
mirrors the app's actual correction task: learner sentences with known errors (the model
must produce the right fix) and correct sentences that *look* wrong (the model must say
"OK"). Scoring is fully automated.

The baseline results for the stock 4-bit Gemma 4 E4B were clarifying:

| Area | Baseline |
|---|---|
| Verbs + prepositions | 87% |
| Separable verbs | 80% |
| **Reflexive verbs** | **60%** |
| **Da-/wo-compounds** | **60%** |
| Overall (core four) | 72% |

My intuition was right — and wrong in an interesting way. I then tested ten *more*
candidate areas (word order, relative pronouns, Konjunktiv II, noun gender,
haben/sein auxiliaries, N-Deklination…). The model turned out to be **strong** at word
order, relative pronouns, and Konjunktiv II — no training data needed. But the failure
analysis surfaced something better than any single grammar gap:

**The dominant failure was behavioral, not grammatical.** On 36% of *correct* sentences,
the model returned a "fix" — usually the identical sentence back, with an explanation
admitting it was fine. In the app, that means users see corrections for sentences they
got right. The second pattern: when unsure, the model *dodges* — asked to fix
*"Mit meiner alten Freund"*, it changed *Freund* to *Freundin* (changing who the sentence
is about!) rather than fixing the case. Neither of these shows up in a benchmark
number; both destroy trust in a tutor.

## Building the dataset

There is no off-the-shelf dataset for "German verbs with fixed prepositions as a
correction task," so the data is synthetic — but grounded and gated:

- **Ground truth first.** I compiled a 268-entry table of verb+preposition pairs (with
  governed case, reflexivity, separability, CEFR level), pulled **6,526 separable verbs**
  and 1,604 reflexive verbs from the German Wiktionary's categories, and mined **83,000
  seed sentences** from Tatoeba's 774k-sentence German corpus with a spaCy pipeline.
- **Teacher-model generation.** Batches of ~60 examples in the app's *exact* prompt
  formats — correction pairs, multi-turn tutor dialogues, flashcard JSON. An early A/B
  taught me a hard lesson about teacher choice: the budget model produced training
  examples where **42% of "this sentence is correct" labels were wrong** — broken German
  labeled as correct, which is precisely the poison that would reinforce the
  false-corrections problem. The mid-tier model's error rate was ~3%, all caught in review.
- **A validation gate on everything.** Self-hosted LanguageTool + spaCy structural checks
  + dedup + a guard that rejects anything resembling a held-out eval item (it caught the
  generator reproducing an eval sentence on day one). Sobering discovery: LanguageTool's
  open-source German rules caught **none** of my four target error types — wrong fixed
  prepositions, wrong reflexive case, wrong auxiliary, and broken word order all passed
  silently. Automated checking is necessary but wildly insufficient for grammar data;
  every batch also got a human (well, a fluent-model-assisted) read-through.

The read-throughs earned their keep. Recurring traps: "corrections" of German that is
actually fine (*"Ich freue mich, dich zu besuchen"* needs no *darauf*; *"Ich wundere
mich, dass…"* needs no *darüber*) — training on those would *teach* over-correction,
the exact behavior I'm trying to remove. And ambiguity traps: in "Die Zwillinge haben
die Prüfung bestanden. Alle Lehrer erzählen begeistert **davon**", the *davon* legitimately
refers to the event — marking it wrong would be wrong.

Final dataset: **960 targeted examples** (816 corrections — 30% of them correct
sentences whose gold answer is exactly "OK" — plus 94 tutor dialogues across freestyle,
formal-Sie, role-play, and vocabulary-weaving modes, and 50 flashcard-JSON examples)
blended with ~35% general German instruction data to prevent catastrophic forgetting.
About 1,450 training examples total. Small, but every one of them aimed at a measured
failure.

Total cash spent on data: roughly **$0** — generation ran through my coding-assistant
subscription's agents, grammar validation was self-hosted, and the only API involved
(DeepL, for cross-checking English glosses) used about 0.5% of its free tier.

## Training

QLoRA (r=8, lr 2e-4, 2 epochs) via Unsloth. My own GPU — an 8 GB RTX 2070 Super —
ironically can't fit the job that a phone will run the result of, so training ran on a
rented RTX 3090 community pod at **$0.22/hour**. The training run itself took **19
minutes**. The whole GPU session — which ended up covering *three* fine-tunes (more on
that below), plus model downloads, fp16 merges, and pushes to Hugging Face — cost about
a dollar. The single most expensive resource in this entire project was my attention
during data review.

The run itself was undramatic: training loss eased from 0.39 to 0.22 over two epochs,
held-out eval loss settled at 0.67 and stayed flat — no overfitting on 1,447 examples
at rank 8.

What actually broke, for anyone repeating this:

- **Gemma 4's chat template enforces strict user/model alternation**, and my tutor
  dialogues start with the *model* (it greets you first). Training crashed on every
  dialogue example until I prepended the same synthetic "begin the conversation" user
  turn the app itself uses — which is also the honest way to render it: training data
  should match the exact token stream the model sees in production.
- **`mlx_lm.convert` cannot convert Gemma 4 at all.** The architecture shares KV
  projections across the last 18 layers, and mlx-lm goes looking for per-layer weights
  that don't exist. The path that works is `mlx_vlm convert` (the same one the community
  4-bit builds used). Always sanity-generate after converting — a conversion that
  "succeeds" can still produce garbage.
- **MLX Swift merges *every* `*.safetensors` file it finds in a model repo, recursively.**
  My LoRA adapter folder rode along into the inference repo and broke app loading with an
  opaque `Unhandled keys ["base_model"]` error. An inference repo must contain exactly one
  `model.safetensors`.

## Results

Same eval, same automated scoring, both models as the 4-bit MLX quantizations that
actually ship on a phone:

| Metric | Stock E4B | Fine-tuned |
|---|---|---|
| **Core four areas** | 43/60 (72%) | **51/60 (85%)** |
| — verbs + prepositions | 13/15 | **15/15** |
| — separable verbs | 12/15 | **14/15** |
| — da-/wo-compounds | 9/15 | **12/15** |
| — reflexive verbs | 9/15 | 10/15 |
| **Extension suite** (10 untargeted areas) | 53/61 (87%) | **55/61 (90%)** |
| **False corrections** (n=32 correct sentences) | 34% | **22%** |
| **Missed / wrongly-fixed errors** (n=69) | 17% | **9%** |

Four things I read off this table:

1. **The behavioral metrics moved most, and they're the ones that matter.** Missed errors
   halved (17% → 9%), false corrections dropped by a third (34% → 22%). That was the
   thesis of the whole dataset design — verdict discipline over grammar trivia — and it
   paid out.
2. **The knowledge areas the model half-knew went to (near-)perfect.** Verbs with
   prepositions 15/15, separable verbs 14/15. Where the base model already had the
   substrate, 19 minutes of QLoRA finished the job.
3. **Reflexives barely moved** (60% → 67%). The accusative/dative reflexive distinction
   (*ich wasche mich* vs. *ich wasche mir die Hände*) appears to be genuinely hard, not
   just under-trained. That slice gets a dedicated second data wave.
4. **The untargeted extension suite went up, not down** (87% → 90%). The ~35% general
   instruction mix-in did its anti-forgetting job; nothing was traded away.

[TODO: on-device latency and memory on iPhone — time-to-first-token and full-reply
times for the tuned model vs. the server-based competitor apps.]

## The bake-off: what happened when I ran every other phone-sized model through the same eval

Once the eval harness existed, any candidate model was one command away from a scorecard —
so the project turned into an accidental survey of German competence across the current
open-weight, phone-sized field. Two of them also got the identical fine-tune (same
dataset, same QLoRA recipe, same $0.22/hr pod), which turned out to be the most
instructive experiment of the project.

| Model | Size (4-bit) | Core | Extension | False corr. | Missed errors |
|---|---|---|---|---|---|
| Gemma 4 E4B (tuned) | 4.9 GB | **85%** | **90%** | 22% | 9% |
| Gemma 4 E4B (stock) | 4.9 GB | 72% | 87% | 34% | 17% |
| Gemma 4 E2B → tuned | 3.3 GB | 65% → 68% | 75% → 70% | 34% → **59%** ⚠️ | 28% → 19% |
| Qwen3-4B → tuned | 2.3 GB | 48% → 62% | 57% → 64% | 19% | 61% |
| Qwen3-8B | 4.9 GB | 58% | 77% | 6% | 48% |
| Aya Expanse 8B* | 4.2 GB | 57% | 64% | **100%** | 12% |
| Ministral 8B* | 4.2 GB | 52% | 69% | **84%** | 23% |
| Apple Intelligence (on-device)† | ~3B built-in | 42% | 52% | **100%** | 35% |
| Gemma 3 1B → tuned | 0.8 GB | 58% → **32%** ⚠️ | 59% → 36% | 0% → 56% | 55% → 72% |
| Mistral 7B v0.3 | 4.1 GB | 43% | 49% | — | — |
| Phi-4 Mini 3.8B | 2.3 GB | 43% | 48% | 12% | 77% |
| Llama 3.2 1B | 0.7 GB | 28% | 33% | 0% (trivially) | **100%** |
| EuroLLM-1.7B | 1.0 GB | **13%** | **7%** | 100% | 97% |

*\*Ministral 8B and Aya Expanse 8B carry non-commercial licenses — they're in the survey
as research data points, not app candidates.*
*†Apple Intelligence is the system on-device model, reached through the FoundationModels
Swift API rather than as a downloadable checkpoint — measured as Apple exposes it,
greedy-decoded, with the same prompts and scorer as every other row.*

An aside on the ceiling: it's not the phone's RAM spec that limits model size — it's
iOS's *per-app* memory cap, which sits around 8 GB even on devices shipping 11–12 GB.
I tried 12B-class models; they don't load. A ~5 GB 4-bit E4B with room for KV cache and
the app itself is realistically the top of the on-device range today, which makes
squeezing quality out of that size class via fine-tuning the only way up.

What this table taught me:

**There is a capacity cliff, and fine-tuning below it actively harms.** Gemma 3 1B was
the shock: a respectable 58% baseline, and the *identical* fine-tune that lifted both 4B
models dropped it to 32% — with false corrections exploding from 0% to 56%. My reading:
the dataset teaches a *behavior* (confidently produce FIX verdicts in a strict format),
and a 1B model has room for the behavior but not the knowledge to aim it. It learned to
sound like a tutor without knowing German well enough to be one. Below some capacity
floor, fine-tuning doesn't add skill — it adds confidence. Which is roughly the worst
possible trade for a teacher. (The E2B fine-tune later reproduced this from the *edge* of
the cliff rather than the bottom of it — see "Round two" — which is what turned this
single shock into a gradient.)

**The base model's multilingual substrate sets the ceiling.** The same data, recipe, and
GPU gave E4B +13 points and Qwen3-4B +14 — a strikingly consistent lift. But tuned
Qwen3-4B (62%) still landed *below stock* E4B (72%). You cannot fine-tune your way past
a weaker pretraining substrate with a dataset this size; you can only cash in the
knowledge that's already latent. Pick the base by measured target-language quality, not
by leaderboard rank.

**Parameter count tells you almost nothing about German.** Mistral 7B (43%) lost to
Gemma 3 1B (58%) — a model a tenth its size. And 8B Qwen matched 1B Gemma on the core
suite. "Supports 100+ languages" on a model card is marketing; thirty minutes with a
held-out eval is data. The purpose-built European entrant made the same point from the
other direction: EuroLLM-1.7B, pretrained on all 24 official EU languages, scored 13% —
not because it lacks German, but because it can't follow the correction-task *format*,
answering in rambling English prose instead. Multilingual pretraining without
instruction-following is worthless for a structured tutor task.

A reader later handed me the cleanest possible confirmation of this: **BübleLM-2B**, a
Gemma 2-2B *re-adapted for German* with a custom German tokenizer and 3.5B tokens of German
pretraining — a model built for exactly this. On its own German benchmarks it looks strong
(47.9% HellaSwag-DE). On the app's task it scored **7%**, below even EuroLLM: it never once
said "OK", opened three-quarters of its answers with a bare reframed sentence and no verdict
marker, and — tellingly — its actual German fixes were often *correct*. All the substrate,
none of the discipline to deliver it in a parseable verdict. Forgiving the format entirely
lifts it only to 25%, still less than half the ~55% floor below which fine-tuning adds
confidence rather than skill. It's the whole thesis in one reader suggestion: the model card
measures German; the eval measures the job. (Full workup:
[`bueble.md`](data/german-first-models-writeups/bueble.md).)

I ran the same test on three more small candidates hunting a lighter base than E4B —
Granite 3.3 2B, Llama 3.2 3B, Salamandra 2B — and got the same wall from three new angles.
Salamandra (35 EU languages) reprised EuroLLM's collapse almost exactly: 99 of 121 answers
weren't even in the correction format. Llama 3.2 3B had the discipline (zero format errors) but
not the German — it over-corrected half the *correct* sentences, a substrate deficit no
instruction-tuning fixes. Only IBM's Granite 3.3 2B cleared the floor at all, and only by *tying*
the 0.8 GB Gemma 3 1B it would have had to beat. Four models, four confirmations of the one finding
that has held since the first bake-off: the German substrate is the ceiling, and Gemma is the only
family that clears it. (Survey: [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md).)

**Model families have personalities, and they're inverse.** Every Gemma failed the same
way: over-eager corrections of sentences that were already right (a *judgment* deficit) —
a failure mode other models take to its extreme: Ministral 8B "fixed" **84%** of the
perfectly correct sentences shown to it, and Aya Expanse 8B — Cohere's multilingual
flagship — corrected **all 32 of them**. A model that never says "this is fine" and a
model that never says "this is wrong" (Llama 1B OK'd all 69 errors) score surprisingly
similarly on a naive accuracy metric, and are equally useless as tutors. This is why the
two behavioral rates, not the headline score, became my primary metrics.
Every Qwen failed the opposite way: serenely rubber-stamping broken German as OK (a
*knowledge* deficit) — Qwen3-8B falsely corrects only 6% of the time but waves through
48% of real errors, and Phi-4 Mini waves through 77%. Llama 3.2 1B took this to its
logical conclusion and answered OK to *all 69* errors in the suites — a perfect
false-correction score achieved by never correcting anything. For a tutor, the Gemma
failure mode is annoying but the Qwen/Phi/Llama one is fatal: a student can't learn from
a teacher who validates their mistakes.

**The model already on the phone is the worst tutor of all.** The obvious question about an
on-device German app in 2026 is "why ship your own model — the iPhone already has Apple
Intelligence." So I ran it through the identical eval (its FoundationModels Swift API instead
of MLX, same prompts, same scorer). Apple's ~3B on-device model produced the most extreme
over-corrector personality in the entire survey: it "fixed" **all 32** correct sentences — a
100% false-correction rate, tying Cohere's Aya Expanse for dead last — by echoing the
student's sentence back *unchanged* under a `FIX:` header with a confabulated reason
(*"Incorrect subject-verb agreement needed"* on the flawless *Sie wartet auf ihren Freund*;
*"'würde ich' is incorrect"* on a textbook Konjunktiv II). It never once said "this is fine."
Its raw grammar knowledge is Mistral-tier — 42% on the core four, a clean **0/15** on
da-/wo-compounds — below even the 0.8 GB Gemma 3 1B. And tellingly it produced *zero* format
errors: it has learned the exact shape of a correction task impeccably and has none of the
judgment to know when not to apply it. That's the FIX-behavior without the knowledge to aim
it — the same failure the small fine-tunes taught themselves — except here it's baked into
the default model on the device. Which is the whole case for the project in a single data
point: the tutor a learner reaches for by default would actively confirm their mistakes.

One meta-lesson: none of this was visible before building the eval. Every one of these
models ships with a beautiful model card and strong multilingual benchmark numbers —
Phi-4 Mini in particular is a benchmark darling that turned in Mistral-tier German. The
entire bake-off — ten checkpoints, twenty eval runs and counting — cost nothing but Mac
compute time, because the harness already existed. Evals are the cheapest instrument in
the whole on-device toolchain, and the highest-leverage one.

## Takeaways so far

1. **Evaluate before you train.** Half of my planned training areas turned out not to
   need training. The eval also revealed that my most valuable slice of data would be
   *correct sentences* — which no intuition about "grammar weaknesses" would have produced.
2. **Behavioral failures beat knowledge failures.** The model mostly *knows* N-Deklination;
   it fails at *verdict discipline* — knowing when to say "this is fine." That's a
   fine-tuning problem, not a knowledge problem, and it's cheap to fix with data.
3. **Synthetic data works if the teacher is strong and the gate is real.** The
   cheap-teacher experiment failed in exactly the way that would have been invisible
   without review: confidently wrong labels on correct-looking German.
4. **On-device is not a compromise for language learning — it's an advantage.** Faster
   turns, total privacy for your fumbling attempts at a new language, works offline, and
   the per-user marginal cost is zero, which changes what kind of app you can afford to build.
5. **Below a capacity floor, fine-tuning subtracts — and the floor is a gradient.** The
   same dataset that added 13–14 points to two 4B models cut a 1B model nearly in half, and
   left a 2B a runaway over-corrector (false corrections 34% → 59%) despite a 65% base that
   cleared my own "≥55%" rule. Baseline first, but judge small models by their *post-tune
   false-correction rate*, not the headline score: a sub-~55% base is a hard stop, and even
   clearing it isn't a guarantee.
6. **Choose the base model by measured target-language substrate.** Fine-tuning gave a
   consistent lift, but never enough to jump families: the best stock model was still
   better than every tuned competitor. Thirty minutes of evals beats any model card.

## Round two: the same recipe hits a different wall

With the E4B tutor shipped, the obvious next move was its smaller sibling. Older and
cheaper phones don't have the memory headroom for a ~5 GB model, and the bake-off had
already flagged **Gemma 4 E2B** as the one model below E4B worth training: 65% base on
the core four, and — crucially — the *exact* same over-correction personality as its big
sibling (34% false corrections), which is precisely the failure the dataset was built to
fix. If the recipe transfers, E2B becomes the tutor for the 6–8 GB tier. Same data, same
QLoRA recipe, one line changed to swap the base model. On paper a fifteen-minute job. It
was not.

**The pod lottery.** The RTX 3090 that trained E4B (and its two experimental siblings)
turned out not to be the constant I'd treated it as. This time nothing in the cheap 24 GB
tier was available, so the run landed on an **RTX 4000 Ada (20 GB) at $0.23/hr** — ample
VRAM for a QLoRA of a 2B-class model, but a card I hadn't used, on a barer image.

**Friction one, minor: a bare CUDA image.** The E4B pod had been a managed PyTorch
template; this one shipped an externally-managed system Python, so `pip install unsloth`
refused outright (PEP 668) until `--break-system-packages`. Thirty seconds, once you
recognize it.

**Friction two, the real one: an out-of-memory kill that had nothing to do with the GPU.**
The run died at 91% of the tokenizing pass with a single word — `Killed` — and no
traceback. The instinct is to blame the GPU, but the GPU was idle at 8 of its 20 GB; this
was the *kernel's* OOM killer reaping the process for system RAM. The trap: the pod
advertised 48 vCPUs and `free` cheerfully reported 251 GB of RAM — except that 251 GB is
the *host's*. The container's actual cgroup limit was **28.9 GB, with zero swap**.
Unsloth's response-only tokenizer, like most of the Hugging Face data stack, scales its
worker count to the visible CPU count — so it forked **52 parallel workers**, each copying
its shard of the dataset plus the tokenizer, and sailed straight past 29 GB into an
instant SIGKILL.

The fix is one line — pin `dataset_num_proc` to 2 instead of letting it default to all
cores — and RAM dropped from OOM to a steady 12 GB. But the lesson generalizes past this
pod: on rented GPUs the dangerous configuration is *many vCPUs paired with a small RAM
cap*, because the data-pipeline libraries autoscale to cores and every worker is a full
copy. Read the container's cgroup limit (`/sys/fs/cgroup/memory/memory.limit_in_bytes`),
never `free`. E4B's pod had simply happened to sit on the safe side of that ratio. The
single most time-consuming problem of the entire E2B run was infrastructure — not the
model, not the data, not one line of German.

Past that wall the run was boring in the good way: the same 1,447 examples, the same
Gemma-4 turn markers auto-detected (`<|turn>user` / `<|turn>model`), the same 362 steps.
E2B is 5.1B raw parameters — ~2B "effective" via the E-series' per-layer-embedding trick —
of which QLoRA trained 12.7M (0.25%) at rank 8. The slower Ada card ran ~4 s/step for a
~26-minute run, against the 3090's 19 minutes for E4B. Training loss eased from 0.57 into
the low 0.2s (E4B: 0.39 → 0.22); held-out eval loss sat flat around 0.75 (E4B: 0.67) — a
hair higher, as you'd expect from a smaller model, and just as stable: no overfitting.

### The answer: the 2B teeters on the edge

Converted to 4-bit (`mlx_vlm`, clean on a spot-check), scored on the same two suites. The
result is the most interesting negative of the project — because it isn't the 1B's clean
fall. Core accuracy nudged *up* (65% → 68%), and the model got measurably better at
catching real errors (miss rate 28% → 19%). But the metric that actually matters for a
tutor went the wrong way, hard: **false corrections nearly doubled, 34% → 59%.**

The tuned E2B "fixes" a majority of the sentences that were already correct — and invents
grammar to justify each one. `Sie wartet auf ihren Freund` (perfect) comes back
"corrected" to the identical sentence with the note *"'warten auf' is inseparable; no 'zu'
is needed."* Asked about `Kannst du bitte das Fenster zumachen?` it swaps *zumachen* for
*zuschlagen* — "close" for "slam," changing the meaning — and asserts *"'zumachen' is
inseparable."* Several of its rules are just false (*aufstehen* is separable; the tune
calls it inseparable). That's the capacity cliff in slow motion: the model absorbed the
FIX-producing *behavior*, and even some knowledge (misses dropped), but at 2B it can't
hold the grammar firmly enough to know *when not to fire* — so it fires constantly and
backfills a reason.

Line the three fine-tunes up by size and the "cliff" resolves into a **gradient — with
false-correction rate as the thing that slides off it first:**

| Base params | Core (base → tuned) | False corrections (base → tuned) |
|---|---|---|
| Gemma 3 1B | 58% → **32%** | 0% → **56%** |
| Gemma 4 E2B (~2B eff.) | 65% → 68% | 34% → **59%** |
| Gemma 4 E4B (~4B eff.) | 72% → **85%** | 34% → **22%** |

The 4B cashes the data in as a real gain on every axis. The 1B is destroyed by it. The 2B
lands between — it *gains* knowledge but *loses* judgment, a split a single accuracy number
would hide entirely and only the behavioral rate exposes. So the same call the 1B forced,
one tier up: the low/mid tier ships **stock E2B** (its 34% false-correction rate beats the
tune's 59%), and the fine-tune stays a private reference artifact rather than a public
model that would mislead anyone who downloaded it. "Base core ≥ 55%" turns out to be
necessary but not sufficient — E2B cleared it at 65% and still shouldn't ship. For small
models, the honest gate is the post-tune false-correction rate, not the headline score.

Whether more data could rescue it is the obvious question, and the controlled evidence
says probably not: this *same* dataset lifts the 4B models cleanly, so it isn't the data —
it's 2B of capacity trying to hold German grammar and a strict output behavior at once,
and dropping the grammar. A small-model-specific mix (far more "this is already correct"
examples) might rein the over-correction in, but the confabulated rules suggest a low
ceiling, and it risks flipping the model into the opposite failure. Not worth it against
a stock E2B that already behaves better.

## The floor — and who's still below it

The bake-off found the ceiling: iOS caps one app's memory near 8 GB, 12B-class models
won't load, and a ~5 GB 4-bit E4B is about the largest thing that still leaves room for
the KV cache and the app around it. What this project mapped almost by accident is the
*floor* — and it sits higher than I'd hoped.

Every model small enough to leave real headroom on a modest phone fails the task, by one
of two routes. Some can't do it at baseline — Llama 3.2 1B waved through all 69 errors as
fine; EuroLLM-1.7B couldn't hold the output format. Others are made *worse* by the same
fine-tune that lifts the big models: Gemma 3 1B collapsed, and Gemma 4 E2B teetered
(better at catching errors, but "fixing" 59% of already-correct sentences). The smallest
model I found that is a genuinely *trustworthy* tutor — fixes real mistakes, doesn't
invent fake ones — is Gemma 4 E4B.

> **Correction (2026-07-30).** The stock-Gemma-3-1B numbers in this section were wrong, and
> flattering. My scorer credited a reply that opens `OK` *and then* appends a `FIX:` line —
> which is what that model emits on essentially every input. The app shows the learner
> nothing for those replies. Scored the way the app actually behaves, stock Gemma 3 1B is
> **34%, not 58%**, and its real miss rate is **100%, not 55%**. It is not "safe but
> limited"; it is silent. Everything below about the 4 GB floor is revised accordingly, and
> the Gemma 4 numbers are unaffected — they emit a clean `OK` or a clean `FIX`.

Is that just "bigger is better"? Roughly, but the precise version is more useful. The task
needs three things at once: German grammar *knowledge* (hundreds of specific
verb-preposition, case, and separability facts), the *judgment* to know when a sentence
needs nothing, and strict *format* compliance. Small models manage the format and can be
pushed into the correction behavior — but they lack the room to hold the knowledge and
exercise the judgment at the same time, so training the behavior in crowds the judgment
out, and they over-correct. And because these are English-first models, the slice of an
already-small budget that actually speaks German is smaller still — which is why Gemma,
with its unusually heavy multilingual pretraining, is the only family that clears the bar
at all, and why even the best-substrate 1B available (Gemma 3) still fell off. The cliff
isn't at a fixed parameter count; it's wherever "knowledge + judgment for this task"
outgrows the model. For German correction, empirically, that's between ~2B effective
parameters (E2B, teetering) and ~4B (E4B, comfortable).

Line that up against the hardware and the deployment story writes itself. E4B's ~5 GB,
against that ~8 GB per-app ceiling, wants a device with roughly 8 GB of RAM — an iPhone 15
Pro-class phone or newer. Below that you can still put *a* tutor on the device — the app
falls back to a stock small model — but not *the* tutor. And that fallback is a worse
downgrade than I originally reported: stock Gemma 3 1B isn't cautious, it's mute, wrapping
a real correction inside a reply the app discards. Stock E2B is merely mediocre (a third of
its "corrections" are spurious). The one thing that doesn't help is the obvious thing —
fine-tuning those small models to close the gap — because that is exactly what tips them
over the cliff.

So the honest headline is narrower than "on-device German tutoring works": *good*
on-device German tutoring, today, is a recent-device feature. A 4 GB phone can run a small
model that won't actively mislead you, but the tutor actually worth using needs hardware
from about the last two years — and none of the training in this piece moved that line.
That's simply where the edge sits right now, and I pushed on it from both sides: every
phone-sized open model through the same eval, and the same fine-tune down the entire size
ladder, until it stopped giving.

The consolation is that the edge is moving, and quickly. Gemma's E-series roughly doubled
its usable quality in a year at the same footprint. The model that barely defines the
floor today may be comfortably mid-range next year, and whatever plays E2B's role a
generation out may clear the bar this one just missed. On-device German tutoring is viable
now on a recent phone; "recent" is the only word in that sentence I expect to expire.

## Round three: 40,000 examples at the floor, and why it still doesn't clear

The floor section above ends on a guess — that more data might rescue a small model. I
built the data and tested it. The answer is interesting enough to be worth the detour.

The second dataset is ~40,000 validated examples generated by a 26B teacher, against
~1,400 in the first. Two students got the same corpus: Gemma 3 1B, which has the best
German substrate available under a gigabyte, and IBM's Granite 3.3 2B, which has the
worst German of anything I'd consider but a very different shape.

```
                          stock    tuned on 40k
Gemma 3 1B                 34%   →   26%    (worse, again)
Granite 3.3 2B             55%   →   72%
────────────────────────────────────────────
Gemma 4 E2B (6 GB tier)              84%
Gemma 4 E4B (8 GB tier)              91%
```

Granite absorbed the data cleanly and more than doubled what the app ships to a 4 GB
phone. It also stopped well short of the 6 GB model, and a rank test says that isn't a
tuning problem: quadrupling the adapter's trainable parameters drove validation loss down
hard (0.89 → 0.71) and moved the actual benchmark by four items out of 82, which on an
exact McNemar test is p = 0.42. Nothing. The model had already extracted what it could.

### Two ways to spend a small budget, neither of which works

The split between those two students is the whole story, and it's architectural.

A language model's parameters go into two pots: the vocabulary table that maps text to
tokens, and the body that does the thinking. In a large model the table is a rounding
error. In a small one it's the dominant cost, and the two families made opposite bets:

| | Gemma 3 1B | Granite 3.3 2B |
|---|---|---|
| vocabulary | 262,144 | 49,159 |
| body params | 396M (~40%) | 2,399M (~96%) |
| bet | know German | be able to learn |

Gemma buys a huge multilingual vocabulary, which is exactly why it starts ahead on German
and why the family dominates this entire project. But at 1B that table consumes most of
the model, leaving a body too small to hold grammar knowledge *and* the judgment to know
when a sentence needs nothing. Train the correction behavior into it and the judgment gets
crowded out. That's the collapse, and it's why the same data that lifts a 4B model breaks
a 1B one.

Granite spends almost everything on body. It learns well, as the +17 points show. What it
can't do is read German efficiently:

```
"Ich habe gestern das Buch gelesen."

Gemma 4  (7)  ['Ich', '▁habe', '▁gestern', '▁das', '▁Buch', '▁gelesen', '.']
Granite (13)  ['I','ch','Ġh','abe','Ġgest','ern','Ġdas','ĠB','uch','Ġge','les','en','.']
```

Roughly twice the tokens for the same sentence, because a 49k vocabulary trained mostly on
English and code has no room to store German words whole. `habe`, `gestern`, `Buch`,
`gelesen` all arrive in pieces. That costs generation speed on the slowest hardware in the
lineup, halves the effective context, and plausibly spends body capacity on reassembling
words that Gemma simply reads. I can measure the first two; the third is inference.

So: a model that knows German but can't learn, or a model that can learn but reads German
in fragments. Under 4 GB those were the only two options I found, and the ceiling sits at
72% either way.

### Why nobody is building the model that would fix this

The obvious fix is a small model with Gemma's multilingual vocabulary and Granite's body
ratio. It doesn't exist, and the reason is economic rather than technical.

German is around 2% of the world's speakers. It's a much larger share of European software
spending, but that's not the number a frontier lab optimizes against — they optimize a
benchmark average across many languages, and multilingual capacity is bought with
vocabulary and data mix, both of which cost English performance at small sizes. A German-
first 1B is a rounding error in every market a lab measures. TII's Falcon models are the
clean illustration: a well-funded lab producing genuinely capable open models, aimed
squarely at Arabic and English because that's who funded them. Nobody is wrong here, and
nothing in the incentives points at German.

What exists instead is community and academic work, and I tested it: BübleLM 2B, SauerkrautLM
gemma-2-2b, Salamandra 2B, EuroLLM. They lift general German *fluency* and none of them
survive contact with this task, because a German chat tune is not a German grammar-
correction model. They lose the instruction discipline that makes the verdict format work
at all.

### Where the 4 GB tier lands

It doubles, and stops. Granite 3.3 2B tuned on the v2 corpus is the best 4 GB result this
project produced, and it's a real one: 34% → 72% against what the app ships today. It is
also slower per German word than anything else here, unshipped pending a real device
memory measurement, and short of the 84% a 6 GB phone already gets.

I've paused it there rather than pushing further. The remaining lever was on-policy
distillation, and that turns out to need a redesign for this pairing anyway: teacher and
student have incompatible vocabularies, so there's no token-level distribution to distill
against without a cross-tokenizer method the plan never scoped. The cost-benefit stopped
making sense against a shrinking population of 4 GB devices.

The floor section above said the edge is moving quickly, and that remains the most useful
thing to know. Every result here is a statement about one generation of small models. The
next one gets to reset it.

## Whose German? The tutor meets a Semmel

I learned standard German for four years, then spent three months in Vienna and found out
what "standard" means. At the supermarket bakery counter the roll is a *Semmel*, not a
*Brötchen*. And the past tense works differently: an Austrian has *ist gesessen* — sein
where Germany uses haben — and that isn't slang or dialect. German is **pluricentric**:
Germany, Austria, and Switzerland each have a codified national standard, with their own
dictionaries. *Jänner* for January is correct standard German in Austria the way *color*
is correct English in Boston.

For most apps this is trivia. For a tutor with a **correction mode** it's a liability
with a specific failure: a student who says something correct in Austrian standard and
gets "fixed" into Bundesdeutsch is being taught that their German is wrong. Every eval
item in this project was written in Germany-standard German, so nothing I'd measured so
far could catch it. So I built a variety audit: a 35-marker inventory of codified
Austrian and Swiss forms (each paired with its Germany-standard counterpart and regex
traps documented — *Semmelbrösel* is not a *Semmel*), a scan over every corpus version,
and a 51-item probe battery run against both the stock Gemma 4 E4B and my v4 fine-tune.

**The training corpus turned out to be Bundesdeutsch by omission.** Not one generation
prompt in the whole pipeline ever names a variety — no "Hochdeutsch", no "wie in
Deutschland üblich" — and the teachers defaulted to Germany-standard essentially
completely. In 3.6M assistant-side tokens of the v4 corpus, the fourteen Austrian
lexical markers appear **twice** (their German counterparts: 1,434 times); the eight
Swiss markers appear **zero** times against 1,383. The only regional voice the corpus
has is northern German: *Moin* opens 313 conversation rows, seven times more than
*Servus* and *Grüß Gott* combined. And exactly five genuine Austrian-style
sein-perfects hide in the conversation data ("Mit wem bist du denn die ganze Zeit im Zug
gesessen?") — leakage from the teacher, not policy.

Then I put valid Austrian and Swiss sentences through the app's real correction contract:

| student says (all correct) | stock E4B | v4 fine-tune |
|---|---|---|
| Ich bin gestern lange im Café gesessen. | FIX → "Ich **saß** …" | OK |
| Wir sind eine Stunde an der Bushaltestelle gestanden. | FIX → "Wir **haben** … **gewartet**." | OK |
| Heuer im Jänner war es besonders kalt. | FIX (reordered) | OK |
| Ich bin mit dem Velo zur Arbeit gefahren. | FIX → "**Fahrrad**" | OK |
| Er hat das Auto vor dem Haus parkiert. | FIX → "**geparkt**" | FIX → "**geparkt**" |

**The stock model flags five of eight correct Austrian/Swiss sentences as errors** — the
frontier open model, out of the box, tells an Austrian that *ist gesessen* should be
*saß*. The fine-tune passes seven of eight. Before I claim credit: the controls show
part of that tolerance is the v4's known permissiveness (it also waved through a
genuinely broken *"eine Semmeln"* — the miss-rate trade-off from earlier sections,
wearing an Austrian coat). But part is real: handed a sentence with a genuine word-order
error *and* an Austrian perfect, v4 fixed the error and left *bin … gesessen* alone,
where the stock model rewrote the whole thing into Germany-standard Präteritum.

The rest of the battery is humbling in the other direction. Neither model can *produce*
the Austrian perfect when explicitly asked ("Setze ins Perfekt, wie es in Österreich
üblich ist" → *habe gesessen*, both models), and both confidently state wrong facts —
"Der Monat Januar heißt auch in Österreich Januar," says my fine-tune, in a complete
sentence, about a country whose newspapers print *Jänner* on every front page each
winter. And the fine-tune paid a price the stock model didn't: **variety attrition**.
Stock E4B can improvise passable Bavarian ("I mog di vü und mia gsehn uns morgn") and
Swiss German; the v4 answers every dialect-production request in flat Standard German,
and its "five Austrian food words with German equivalents" include the invented
*Servusknödel*, translated as *Servusknödel*. The loss is robust to decoding: sampled at
temperature, the stock model says *Erdäpfel* under a Graz framing in three of three
generations; the fine-tune in zero of three. Forty-two thousand rows of unmarked
"German" quietly narrowed the model's German to one country's.

The 4 GB tier tells the same story with a twist. On Granite 3.3 2B the frozen battery
mostly measures the capability floor — neither stock nor tuned can perform the Perfekt
transformation at all, and stock "fixes" *Paradeiser* into *Spargel*, which isn't a
variety opinion, just a small model failing at words (its 3B sibling hallucinates
*Erdbeeren* into the same Gulasch). The twist is that the Granite bases keep beating
both Gemmas at variety: stock 2B is the only model in the whole study that says
*Jänner* unprompted when framed in Innsbruck, and stock Granite 4.1 3B is the only one
that actually produces the Austrian perfect on request ("Die Katze **ist** auf dem Sofa
**gelegen**.") and Swiss lexis in open elicitation ("Dort **parkiere** ich in der …
Tiefgarage"). IBM's multilingual bases carry variety associations neither Gemma has —
and the fine-tune erodes most of it, though the tuned 3B also delivered the study's
only fully correct fix of a broken Austrian sentence: *"eine Semmeln"* → "**eine
Semmel**", agreement fixed, variety kept. Base substrate sets the variety ceiling too.

The takeaway generalizes past this app: **a monolingual fine-tune is not
variety-neutral.** If the data pipeline never says which German it means, it means
Bundesdeutsch — the teachers see to that — and the fine-tune both inherits the default
and erodes what the base model knew about everyone else's German. The fix is cheap at
data-generation time (tag a slice of the prompts with a variety, add Austrian-standard
items to the eval) and nearly impossible to notice after the fact unless you go
looking. Full inventory, corpus tables, and probe transcripts:
[`DIALECT_EVAL.md`](DIALECT_EVAL.md).

## The same question, in pixels: on-device image generation

The tutor isn't the only model on the phone. Short Stories can illustrate themselves and
flashcards can draw their vocabulary — both through a second on-device model, a CoreML Stable
Diffusion pipeline that today runs **SD 2.1 base** (~1.2 GB). The moment I went looking for
something better, the exact lesson from the language bake-off reappeared wearing different
clothes: the internet's "best model" advice is written for desktops, and the phone has its own
physics.

Every current image-gen recommendation thread points at FLUX, Wan, or Chroma — eight-to-
twenty-four-billion-parameter models that assume a 16–24 GB desktop GPU. On an iPhone, FLUX.1
isn't one file but four (a U-Net, a 3.6 GB T5 text encoder, a VAE, a CLIP), ~12.7 GB on disk
even at 5-bit, and it runs at all only by streaming half its weights off flash. It *can*
generate on an 8 GB iPhone in Draw Things — the best published number is ~35 seconds for a
two-step image on an iPhone 17 Pro; an independent test at default settings measured **44
minutes**. Both are real. That spread is the signature of a model that doesn't fit.

This app adds a constraint even Draw Things doesn't carry: the illustration model loads *after*
the 5 GB tutor is evicted from memory (they can't coexist on a 6 GB phone), it has to run on the
GPU the background task is actually granted rather than the Neural Engine, and it has to abort
cleanly mid-diffusion the instant the user hits Stop. That trio quietly eliminates most of the
field before image quality is ever discussed.

So the image track becomes the same exercise as the language track: ignore the leaderboards and
measure the small models that actually fit. The shortlist that survives is the *distilled*
SD-class — BK-SDM (a block-removed, knowledge-distilled SD1.4 at half the parameters) and SDXS
(a one-step model: a single diffusion step instead of twenty-five). Both are ~1 GB CoreML
converts, both live in the memory budget SD 2.1 already occupies, and one of them collapses a
multi-second generation into one step. There's a subtlety the survey turned up, too: BK-SDM's
public CoreML build ships tuned for the Neural Engine, which is exactly the processor the
background task *doesn't* get — so even the "drop-in" option has to be re-converted for the GPU
path before it's honestly usable here.

[TODO: converted-model results — disk, peak RAM after the LLM unload, seconds/image, and a
side-by-side of illustration quality vs SD 2.1, once BK-SDM-Tiny and SDXS-512 are converted and
benched on-device.]

There's a familiar coda. Just as Gemma's E-series is redrawing the language floor every year,
Apple quietly moved the image goalposts: the library the app converts against
(`ml-stable-diffusion`) has been frozen since 2024, and its iOS-27 successor ships an official
on-device export of FLUX.2 Klein — a four-billion-parameter, four-step model at 512px, under a
genuinely open license. The frontier model that's impossible on the phone today already has a
name and a ship vehicle for next year. On both tracks — words and pixels — "what runs on a
phone" is a line that moves in only one direction, and faster than you'd guess.

## Where it stands

The fine-tuned model is live in the app as **"Gemma 4 E4B German Tutor"**, and the 4-bit
weights are public on Hugging Face (`kessenma/gemma4-e4b-german-tutor-4bit`) for anyone
who wants to poke at them. Total cost of the project: about a dollar of GPU time, zero
API spend, and a lot of reading synthetic German.

Next up:

- The four grammar areas become selectable focus topics in the app's conversation settings.
- A second data wave targeting reflexives — the one area that resisted the first pass.
- A smaller tier for older devices: **superseded**. The E2B tune looked like a runaway
  over-corrector (false corrections 34% → 59%) until the echo decomposition showed 18 of
  its 19 false corrections were the app already discarding them. Scored the way the app
  behaves it's **83%**, and it shipped on 2026-07-22 as the 6 GB tier. The v2 corpus took
  it to 84% and E4B to 91%.
- The 4 GB tier: **paused at 72%** with a tuned Granite 3.3 2B (see "Round three"). Real,
  unshipped, and waiting on a better small base rather than more training.
- On-device latency numbers for this article. [TODO]

[TODO: App Store link.]
