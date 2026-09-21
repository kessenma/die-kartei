# Data gap plan — closing the thin tail (v5)

Status: **proposed, nothing spent.** Written 2026-08-17 while the packed-v4 training run was in
flight. Step 0 is to read that run's eval before generating anything.

Companion docs: [`TEACHER_GENERATION_FIX.md`](TEACHER_GENERATION_FIX.md) (teacher selection and the
gates), [`runpod/bakeoff/README.md`](runpod/bakeoff/README.md) (the runbook), [`training-v3.md`](training-v3.md)
(how v4 was packed).

---

## 1. Where the corpus actually stands

`data/packed-v4/meta.json`, correction slice = **13,758 rows**. All 14 phenomena are represented —
the coverage hole that flattened v3 is closed. What remains is a 45:1 imbalance.

| phenomenon | fix | ok kept | **total** | fix share | v3 eval (holdout / ext) | note |
|---|---:|---:|---:|---:|---|---|
| `vmp` | 4,227 | 1,812 | **6,039** | 70% | 10/10 / — | at ceiling, over-supplied |
| `dawo` | 2,149 | 921 | **3,070** | 70% | 9/10 / — | at ceiling |
| `refl` | 814 | 320 | **1,134** | 71.8% | 9/10 / — | at ceiling |
| `sep` | 689 | 295 | **984** | 70% | 10/10 / — | fixed in v4 (was 471) |
| `relpron` | 273 | 117 | **390** | 70% | 4/6 / 5/6 | first coverage in v4 |
| `wechsel` | 226 | 97 | **323** | 70% | 4/5 / 6/6 | first coverage in v4 |
| `k2` | 201 | 86 | **287** | 70% | 3/4 / 4/6 | first coverage in v4 |
| `ndekl` | 179 | 77 | **256** | 70% | 5/5 / 6/6 | base model already strong |
| `adjend` | 160 | 69 | **229** | 70% | 5/6 / 7/7 | |
| `artikel` | 155 | 66 | **221** | 70% | 5/5 / 7/8 | |
| `aux` | 159 | **47** | **206** | **77.2%** | 5/6 / 5/6 | ⚠️ `ok`-starved, see §3 |
| `wo` | 146 | 63 | **209** | 70% | 4/5 / 8/8 | |
| `negation` | 118 | 51 | **169** | 70% | — / 4/4 | |
| `imperativ` | 93 | 40 | **133** | 70% | — / **1/4** | worst cell in the suite |

**The shape of the problem:** two mechanically-simple phenomena (`vmp`, `dawo`) are 66% of the
correction slice. The three worst eval cells (`imperativ` 1/4, `relpron` 4/6, `k2` 3/4) are three of
the four thinnest slices. Those scores are from **v3**, which had zero rows for all three — v4 is
the first run where they exist at all, so the v4 eval is the first real read on whether 133–390 rows
is enough.

---

## 2. Step 0 — do not generate anything yet

The packed-v4 run answers the only question that sizes this plan: **is the thin tail thin enough to
hurt?**

```bash
for EV in grammar_eval_v0:guarded-v0 \
          grammar_eval_v1_extra:guarded-v1ext \
          grammar_eval_v2_holdout:guarded-v2; do
  ...   # the v3 §5 loop, unchanged
done
```

Read `imperativ`, `relpron`, `k2` first. Three outcomes, three different plans:

| v4 eval outcome | reading | action |
|---|---|---|
| tail cells **improve** (e.g. `imperativ` 1/4 → 3/4) | volume works; 133 rows was just too few | §3 — top up the tail, gemma-31B, ~$3 |
| tail cells **flat** (`imperativ` still 1/4) | 133 rows changed nothing, but so few that it proves little | §3 first, then re-read. Only if a *well-fed* phenomenon stays stuck is a teacher ceiling in play |
| tail cells improve, **`vmp`/`dawo` regress** | the 66% skew was load-bearing | rebalance at pack time before generating; `--fix-frac` won't do it, needs a per-phenomenon cap |

Recording the v4 numbers into this table is step 0's real deliverable.

---

## 3. The generation round, if step 0 says go

Target: bring every phenomenon to a **600-row floor**. That number is a stated assumption, not a
measured threshold — it's roughly where `sep` (984) and `refl` (1,134) sit, both of which score at
ceiling. Revise it once the v4 eval gives a real dose-response point.

| phenomenon | now | target | **rows to generate** | teacher | why this teacher |
|---|---:|---:|---:|---|---|
| `imperativ` | 133 | 600 | **+467** | Sonnet | lowest score in the suite, high judgment, low volume |
| `negation` | 169 | 600 | **+431** | Sonnet | scope/placement errors need judgment |
| `aux` | 206 | 600 | **+394** | gemma-31B | ⚠️ needs `ok` rows specifically — see below |
| `wo` | 209 | 600 | **+391** | gemma-31B | mechanically simple |
| `artikel` | 221 | 600 | **+379** | gemma-31B | dictionary-checkable |
| `adjend` | 229 | 600 | **+371** | gemma-31B | mechanical |
| `ndekl` | 256 | 600 | **+344** | gemma-31B | mechanical |
| `k2` | 287 | 600 | **+313** | Sonnet | Konjunktiv II is judgment-heavy |
| `wechsel` | 323 | 600 | **+277** | gemma-31B | prep + case, mechanical |
| `relpron` | 390 | 600 | **+210** | Sonnet | agreement chain, high judgment |
| | | | **≈ 3,577** | | |

Split: **≈2,156 rows gemma-31B**, **≈1,421 rows Sonnet**. `vmp`, `dawo`, `refl`, `sep` get **zero**
new rows — they are at ceiling and already over-weighted.

### Yield and cost

gemma-31B measured at 3.8% no-op and ~92% validation pass, so raw ≈ target / 0.885:

| item | number |
|---|---|
| gemma-31B raw rows to request | ~2,440 |
| throughput (A100 80 GB, bf16, `--batch 6`) | ~30 rows/min |
| GPU time | **~1.4 h** |
| GPU cost @ $1.39/hr | **~$2.00** |
| Sonnet rows (~1,200/hr via subagents) | ~1.2 h, no GPU |
| retrain (A40 48 GB, ~4 h @ $0.44) | **~$2.20** |
| **total** | **≈ $4–5** |

### The `aux` exception

`aux` is the one phenomenon that could not hit the 70% target — `ok_available: 47`, `ok_kept: 47`,
landing at 77.2% fix. Every available `ok` row was already consumed. So the `aux` request must ask
for **`ok` rows specifically**, not the usual 70/30 mix. Everywhere else, request ~65/35 and expect
~51/49 back (the 31B under-delivers `fix`; correct at pack time with `--fix-frac`).

### Gates — unchanged, both, every batch

```
refl case-change >= 60%        sep pure-reorder <= 5%
python scripts/check_hard_case_share.py --strict <batch>
python scripts/validate_data.py <batch>
```

Plus the composition check that v3 added, because a pass-rate gate cannot see class collapse:
`scripts/check_batch_composition.py`.

### Known prompt bug to fix first

`training-v3.md` §3: the generation prompt **under-produces separable-verb errors** (379 `fix` vs
1,605 `ok` in the v2 corpus). `sep` is fine in v4 via rebalancing, but the prompt is still wrong and
will re-introduce the skew on any new `sep` request. Fix before generating, even though `sep` is not
in this round's table.

---

## 4. Apertus-70B — how to test it without wasting money

[`swiss-ai/Apertus-70B-Instruct-2509`](https://huggingface.co/swiss-ai/Apertus-70B-Instruct-2509) is
the only new teacher candidate that passes this project's own filters:

- **Dense** (80 layers, 64 heads) — not MoE. This is the decisive filter: `gemma-4-26B-A4B` at ~4B
  active scored 12% refl case-change vs dense 31B's 100%, and cost two training runs. It also rules
  out **gpt-oss-120b (5.1B active) and gpt-oss-20b (3.6B active)** — same architecture regime that
  already failed here, so they are not on this list.
- Trained by a German-speaking consortium (EPFL / ETH / CSCS), 15T tokens, 40% non-English, explicit
  German and Swiss-German coverage — rather than incidentally multilingual.
- Fully open weights *and* training data, OSI license — no license question for a distilled student.

**Do not** hand it the tail directly. Qwen3.8-27B looked appealing on paper too, and the measurement
showed its lexical contribution was indistinguishable from resampling gemma (14.5% novel vocab vs
gemma-vs-itself at 13.8%, Jaccard 0.203 vs a 0.249 same-teacher control).

### 4a. Bake-off first — ~$1

Same protocol as the 2026-08-14 bake-off, so results are directly comparable:

| | |
|---|---|
| jobs | the same 50 stratified `refl`+`sep` jobs |
| script | `runpod/bakeoff/generate_hardcase.py --load-8bit` |
| pod | A40 48 GB @ $0.44/hr (70B at 8-bit ≈ 35 GB — verify it fits before renting) |
| gates | `refl case-change >= 60%`, `sep pure-reorder <= 5%`, no-op rate |
| bar | must match gemma-31B's 100% / 0% / 3.8%, or it is a fallback at best |

⚠️ **Repo selection is the trap here — full survey in
[`TEACHER_GENERATION_FIX.md`](TEACHER_GENERATION_FIX.md) §5a.** In short: use the **`2509` v1.0**
build, not `Apertus-v1.5-70B`. v1.5 is `model_type: apertus1p5`, multimodal, HF-gated, and needs a
custom `transformers` branch. Every pre-quantized 70B build carries its own trap (`w4a16`
dequantizes on load — the same failure that OOM'd a 48 GB A40; FP8 needs Ada sm_89+; GGUF is the
wrong harness), so **bf16 on 2×A100 80 GB** is the only path that reuses `generate_bulk.py`
unchanged.

⚠️ Volume: 70B bf16 ≈ 140 GB. A single 150 GB volume holds it **or** gemma-31B (62.5 GB), not both
comfortably. Free the other cache first.

### 4b. Only if it passes — the actual diversity experiment

The mistake to avoid is generating the tail with Apertus and mixing it in, because then teacher and
phenomenon are confounded and no eval delta can be attributed. Instead:

1. Generate the **same** §3 tail twice — once gemma-31B, once Apertus-70B. Tag rows by teacher.
2. Pack two corpora identical except for the tail's origin: `packed-v5-gemma`, `packed-v5-apertus`.
3. Train both (A40, ~4 h, $2.20 each) and score both on core + extension.

Total ≈ **$12–15** including the bake-off. That buys a real answer to "does teacher diversity help,"
which no corpus statistic can provide — the Qwen analysis established that vocabulary and Jaccard
measurements cannot detect a teacher ceiling, because a phenomenon a teacher never constructs leaves
no lexical trace.

**Kill criteria.** Drop Apertus if: it fails either shape gate; its no-op rate exceeds ~20% (Qwen's
39% was the disqualifier); or the v5-apertus student does not beat v5-gemma by more than the eval's
noise floor (~2 items on 82, so require ≥3).

---

## 5. Order of operations

| # | step | gate to proceed | cost |
|---|---|---|---|
| 0 | Read the packed-v4 eval; fill in §1's eval column | — | $0 |
| 1 | Fix the `sep` generation prompt | — | $0 |
| 2 | Generate the §3 tail with gemma-31B + Sonnet | both shape gates pass per batch | ~$2 |
| 3 | Pack `packed-v5`, cap `vmp`/`dawo` so the tail is not drowned | composition check passes | $0 |
| 4 | Train + score v5 | beat v1's 54/60; below stock's 48/60 the tune is harmful | ~$2.20 |
| 5 | **Only if a well-fed phenomenon is still stuck** — Apertus bake-off | gates match gemma-31B | ~$1 |
| 6 | Only if 5 passes — the paired v5-gemma / v5-apertus experiment | ≥3-item improvement | ~$9 |

Steps 0–4 are the known-good path and cost about $4. Steps 5–6 are the diversity experiment, and
they are only justified by evidence from step 4.

---

## 6. Failsafe

Non-negotiable last step of every GPU run — the failsafe family has failed three times on this
project (stopped a healthy pod; never fired and idled ~6 h; killed the generator but not the pod):

```bash
runpodctl pod list        # must print an empty table
```

If a pod survived: `runpodctl remove pod <id>` — *remove*, not *stop*.
