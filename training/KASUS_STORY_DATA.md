# Kasus story data — teaching the tutor to write to a plan

Status: **steps 1–2 done (2026-10-04).** Step 2's bake-off (≈ $4.15) kept gemma-31B as the teacher and
found planner and check fixes to make before any bulk run. Results and next steps:
[`KOLIBRI_BAKEOFF.md`](KOLIBRI_BAKEOFF.md). Step 3 waits on those fixes.

Companion docs: [`../docs/KASUS.md`](../docs/KASUS.md) (the case path, the planner, the check, the
2026-09-25 Mac probe), [`TEACHER_GENERATION_FIX.md`](TEACHER_GENERATION_FIX.md) (teacher selection
and the dense-only rule), [`DATA_GAP_PLAN.md`](DATA_GAP_PLAN.md) (the correction slice's thin tail),
[`runpod/bakeoff/README.md`](runpod/bakeoff/README.md) (the GPU runbook).

---

## 1. Why

The Grammatik case path can have the tutor write a story: the app plans 5–8 case phrases, the tutor
writes prose around them, and `KasusStoryCheck` proves every graded answer before a story is shown.
Markieren and Endungen come from the validator, not the model, so **the tutor's only job is the
story**, and that's the job the corpus never trained. The v1–v4 rounds trained corrections and
conversation only.

The Mac probe measured the gap ([`../docs/KASUS.md`](../docs/KASUS.md#mac-probe-2026-09-25)):

- About a third of planned phrases survive verbatim; Dativ-verb and receiver phrases about 1 in 12–16.
- Tutors swap the article for a possessive („der Bruder“ → „Mein Bruder“) or drop the preposition.
- After the review fixes, 32 of 69 contract-A attempts pass.

This is the cleanest data-generation setup the project has had, because the verifier already exists
and is the app's own code:

| piece | what it gives |
|---|---|
| `KasusStoryPlanner` (seeded) | unlimited distinct plans; a seed always gives the same plan |
| `KasusStoryPrompt` | the exact prompt the app sends, so train and serve match |
| `KasusStoryCheck` | a hard gate with loud failures (lesson 3) and a verbatim score to rank by |
| the Mac probe | a before/after eval that already has a baseline |

The second use of the same pod session is the correction slice's thin tail (§4b), and the third is
measuring whether Kolibri-1 is a usable teacher at all.

---

## 2. Step 1 — the check as a command-line tool ✅

`kasus_cli/` builds `kasus-cli`, a Mac binary that compiles **the app's own sources**
([`kasus_cli/sources.txt`](kasus_cli/sources.txt), 31 files) with the app target's Swift settings.
No copies of the planner, prompt or check.

```bash
training/kasus_cli/build.sh                         # ~50 s; -> training/kasus_cli/build/kasus-cli
training/kasus_cli/build/kasus-cli selftest         # resources + validator fixtures + golden numbers
training/kasus_cli/build/kasus-cli prompts dativ:A2:1003 all:B1:1-200 [--governed] [--contract B]
training/kasus_cli/build/kasus-cli check outputs.jsonl > records.jsonl   # summary on stderr
```

- **`prompts`** writes one JSON line per plan: `id`, `plan`, `system`, `user`, `maxTokens`,
  `temperature`, `casesLine`.
- **`check`** reads `{plan, raw}` lines (plus optional `id`, `model`, `run`, `attempt`, `endedEarly`,
  `tokens`, `seconds`, `system`, `user`, `error`) and writes the app's `KasusLabRecord` per line, plus
  `id`, `run`, `promptDrift`. The Lab's per-model table goes to stderr. It trims a contract-A write
  to its last full sentence first, the same as the app. `promptDrift` flags a story written to a
  prompt this build doesn't make, so a stale prompt file can't get into the corpus unnoticed.
- **`selftest`** exits 1 if any resource is missing (a missing `wiktionary_de.db` changes verdicts
  without an error) or any validator fixture or golden number is off.

**What it took in the app** (no behavior change, so the tool can compile the pure parts without MLX
or SwiftData):

| new file | moved out of |
|---|---|
| `Services/Grammar/Tutor/KasusStoryPrompt.swift` | `KasusStoryGenerator.swift`: the prompt, request/attempt/result, `completeSentences` |
| `Services/StoryStudyService+Prompt.swift` | `StoryStudyService.swift`: `storyPrompt`, `parseStory`, `wordCount` |
| `Services/Grammar/Prepositions/PrepositionService+Content.swift` | `PrepositionService.swift`: the bundled lookups |
| — | `GoetheVocabService.words(in:)` moved next to `WortschatzScope` |

`kasus_cli/Stubs.swift` stands in for the few app types the sources name but the check never runs.
It also has a six-line `VerbPrepositionService.all()` that reads the same JSON through the app's
decoder type. That file was mid-edit in another session, so it wasn't split. Split it the same way
later and drop the stub.

**Verified 2026-10-04:**

| check | result |
|---|---|
| `selftest` | ✅ wiktionary on, Goethe 585/1,209/2,358, 36 prepositions, 42 verb pairs, 7 stories; fixtures 11/11 · 12/12 · 23/23; golden numbers ✓; 184 table cells round-trip |
| the probe's 81 raw outputs re-checked | 31 of 69 contract-A attempts pass. The doc's post-fix rescore said 32; the check has gained rules since (verb-pair objects). All 81 flagged `promptDrift`, which is correct: their plans are format v1 |
| `prompts all:{A1,A2,B1}:1-200` | 3,000 plans in 7 s, 3,000 distinct phrase sets, none empty |

When an app change breaks `build.sh`, add the file that now defines the missing type to
`sources.txt`, or split the pure part of a heavy file out as above.

---

## 3. The pipeline

```
kasus-cli prompts ──► prompts.jsonl ──► [pod] teacher writes ──► raw.jsonl ──► kasus-cli check ──► records.jsonl
                                                                                     │
                                         select (passes, verbatim share, dedupe) ◄───┘
                                                     │
                                       SFT rows: app system + user → raw story ──► pack with the v4 corpus
```

Generation on the pod, checking on the Mac. The tool is a Mac binary, and the split keeps the pod's
job small (prompts in, text out), so a pod that dies mid-run loses only text.

**Sampling: use the teacher's settings, not the app's.** The app samples the tutor at 0.75. A
teacher should sample at whatever writes its best German (Kolibri's card: temperature 1.0, top_p
0.97, top_k 128). Record the settings per batch.

---

## 4. Step 2 — one pod session, three bake-offs

No numeric pass bars are set in advance. Each bake-off produces a table, and the decision is made
from it.

### 4a. Stories: Kolibri-1 vs gemma-4-31B

| teacher | why it's in | serving |
|---|---|---|
| `google/gemma-4-31B-it` | dense, the proven correction teacher | transformers batched (`generate_bulk.py` pattern). **vLLM can't load Gemma 4** (runbook) |
| `Aleph-Alpha/Kolibri-1`, thinking off | German-first, 24% German pretraining, Apache 2.0 | vLLM + `aleph-alpha-inference>=1`, `--reasoning-parser kolibri1`, `--kv-cache-dtype fp8`; FP8 needs 1× H200 or 2× A100 80 GB |
| Kolibri-1, `reasoning_effort: medium` | tests whether reasoning makes up for 3.46B active params | same; log reasoning tokens separately (lesson 4) |

**Kolibri-1 is a 78B MoE with 3.46B active**, fewer than the retired gemma-26B-A4B. The dense-only
rule (lesson 1) says no. The bake-off is allowed because the check here is a hard gate, unlike the
shape heuristics that missed the 26B's bad rows. But its blind spots (§6) are exactly where a weak
teacher would get fluent, wrong German through. So the decision rests on a **hand read of passing
stories**, not the pass rate alone.

Plans: the probe's six specs (`nominativ:A1:1001`, `akkusativ:A1:1002`, `dativ:A2:1003`,
`dativ:A2:1004`, `genitiv:B1:1005`, `alleFaelle:B1:1006`) for comparability, plus `all:{A1,A2,B1}:`
20 new seeds each (300 plans) per teacher.

Read per teacher: the Lab table (pass rate, verbatim / altered / missing, gradable per case, error
codes), tokens and seconds per story, and 20 passing stories read by hand for German the check can't
see. Cost: well under the $5 bulk figure. Price the H200 hour before creating the pod.

### 4b. Correction tail: Kolibri-1 vs gemma-4-31B

The existing bake-off ([`runpod/bakeoff/README.md`](runpod/bakeoff/README.md)) on the thin phenomena
in [`DATA_GAP_PLAN.md`](DATA_GAP_PLAN.md): `imperativ` (133 rows), `k2`, `negation` (the three it
assigns to Sonnet for judgment) and `aux` (short on `ok` rows). Gates: `validate_data.py`,
`check_batch_composition.py`, the no-op rate (`check_hard_case_share.py` gates `refl`/`sep`, which
aren't in this set). Read v4's tail cells in [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md) before
sizing a bulk run.

### 4c. Optional: Kolibri's expert routing

Log the router's picks over the eval suites and a corpus sample on the same pod. If a few dozen
experts per layer carry most of the routing weight for German tutoring, pruning it for this domain
becomes a real experiment. If routing is spread out, the idea is dead for almost nothing. A note,
not a plan: nothing here depends on it.

### GPU rules

`runpodctl pod list` must print an empty table afterwards. `remove`, not `stop`. The failsafe has
failed three times on this project.

### The 2026-10-04 run

| piece | what |
|---|---|
| inputs | `data/bakeoff/kasus-2026-10/story_prompts.jsonl` (the six probe specs + `all:{A1,A2,B1}:2001-2020`, 306) and `tail_jobs.jsonl` (`scripts/build_tail_jobs.py --per 12`: imperativ, k2, negation, aux; 48 jobs × 8 rows asked) |
| generator | `runpod/bakeoff/generate_chat.py`: openai backend (vLLM, Kolibri) or transformers backend (gemma-31B). Output lines are check input |
| session | `runpod/bakeoff/kasus_bakeoff.sh`: install → Kolibri via vLLM (stories thinking off, stories `reasoning_effort: medium`, tail) → gemma-31B via transformers (stories, tail). Uploads after every phase to the private dataset `kessenma/kasus-bakeoff-2026-10`, checks every file's bytes, then `pod_terminate.sh` |
| secrets | written over SSH into `/workspace/.env.run` (mode 600), not pod env: the HF token and a restricted RunPod key (GraphQL read/write, no serverless) for self-termination |
| backstop | `sleep 14400; pod_terminate.sh deadline`, armed before the run |
| pod | 1× H200 SXM, **Secure Cloud $4.59/hr** (EUR-IS-4). vLLM 0.29.0 pins torch 2.13 (CUDA 13.0 runtime), so the host needs a CUDA ≥ 13.0 driver, and no community H200/H100/A100 had one that evening |
| report | `scripts/kasus_bakeoff_report.py <drop>`: `kasus-cli check` per teacher, the comparison table, `hand_read_<label>.md`, tail rows for `validate_data.py` / `check_batch_composition.py` |

Not run: 4c (routing). Kolibri serves only through vLLM's plugin, so logging its router means hooking
the plugin's MoE layer. That isn't worth doing until 4a says Kolibri is worth keeping.

Dry run before renting (local, $0): the generator against the hero tutor through `mlx_lm.server`, then
the check. The plumbing worked, but `mlx_lm.server` sampled deterministically (two calls at
temperature 0.75 gave identical text) and 3 of 6 stories looped. **Re-probe the student with the
probe's own mlx_lm harness, never `mlx_lm.server`.**

---

## 5. Step 3 — bulk, pack, train, re-probe

1. Bulk-generate with the winner of each bake-off. They don't have to be the same model.
2. **Select:** passes the check, no `promptDrift`, ranked by verbatim share (`placements` with
   status placed / triggerMissing / shadowed). Dedupe on plan id; cap stories per topic (§6).
3. **Pack:** the app's system + user → the raw story, as a new slice beside correction and
   conversation. Size it against the correction slice; a new task is new breadth.
4. **Train E4B only.** The E2B capacity-dilution result says breadth breaks the small tune.
5. **Score core first** (v3's lesson). Bars: beat 54/60; below 48/60 the tune is harmful.
6. **Re-run the Mac probe** on the student: same six specs and seeds, through `kasus-cli check`.
   This is the number the slice exists for.

---

## 6. Open questions and risks

- **Training to the verifier.** The student learns what passes the check, including its blind spots:
  „wartet auf unserem Freund“ (prepositional objects off the 42 pairs), „die hohen Anteil“ (nouns off
  the Goethe lists), adjective endings (unchecked). Mitigations: the hand read in 4a, and possibly
  LanguageTool over passing stories as a second gate (as `validate_data.py` does for corrections).
- **Topic diversity.** `kasus_triggers.json` has 18 topics and one genre (Alltag). 3,000 plans means
  ~170 stories per topic. Widen the topic list before bulk, or cap per topic.
- **Governed plans** (memory saver: A2 max, 6 phrases) and **contract B** (self-labelling) are out
  of scope. The tutors can't label in that format yet, and E4B is the target.
- **Learner nouns** aren't passed in the app yet either, so the data matches the app as it is.

