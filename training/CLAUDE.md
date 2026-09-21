# training/ — orientation

Fine-tuning a small German grammar tutor that runs on-device in the iOS app. Teacher models
generate correction data on rented GPUs; a student LoRA is trained and converted to MLX 4-bit.

**The hero model is `gemma-4-E4B` fine-tuned.** Everything here exists to make that student better,
or to prove some alternative base is not worth switching to.

---

## Which doc is authoritative for what

Docs accumulated by round, not by topic. When two disagree, the one lower in this table is newer.

| topic | doc |
|---|---|
| Every model ever measured, per-phenomenon, with verdicts | [`MODEL_SCOREBOARD.md`](MODEL_SCOREBOARD.md) ← **start here for "is model X any good"** |
| Original project plan, v1 corpus, the Qwen3-4B track | [`PLAN.md`](PLAN.md) |
| On-device runtime search (Cactus, LiteRT) — **CLOSED** | [`RUNTIME_EXPLORATION.md`](RUNTIME_EXPLORATION.md) |
| Sub-3B base search for the 4 GB tier | [`BUDGET_BASE_SEARCH.md`](BUDGET_BASE_SEARCH.md) |
| German-first model families (LLäMmlein, ELMOD, BübleLM) | [`data/german-first-models-writeups/`](data/german-first-models-writeups/) |
| E2B-specific fine-tuning notes | [`GEMMA_E2B_FINETUNING.md`](GEMMA_E2B_FINETUNING.md) |
| v2 corpus build, the mix-in ablation, packing | [`training-v2.md`](training-v2.md) |
| v3 verdict rebalance + v4 teacher replacement | [`training-v3.md`](training-v3.md) |
| **Teacher selection and why** — bake-offs, MoE failure | [`TEACHER_GENERATION_FIX.md`](TEACHER_GENERATION_FIX.md) |
| Copy-paste GPU runbook for bulk generation | [`runpod/bakeoff/README.md`](runpod/bakeoff/README.md) |
| What to generate next and why | [`DATA_GAP_PLAN.md`](DATA_GAP_PLAN.md) |
| **RL round** — GRPO on verdict calibration: plan, worklog, results, article draft in one file | [`REINFORCEMENT_LEARNING.md`](REINFORCEMENT_LEARNING.md) |
| Regional-variety audit of corpus + models (AT/CH markers, dialect probes) | [`DIALECT_EVAL.md`](DIALECT_EVAL.md) |
| Long-form writeup for publication | [`ARTICLE.md`](ARTICLE.md) |

`german-tutor-cactus-retrain-plan.md` and `DATA_V2_DISTILL_PLAN.md` are historical — superseded by
`RUNTIME_EXPLORATION.md` and `training-v2.md` respectively. Read them only for provenance.

---

## The lineage

Each round changed exactly one variable so the eval delta is attributable.

| round | corpus | train rows | what changed | holdout (82) | ext (61) |
|---|---|---:|---|---|---|
| v1 | `data/packed/` | 1,403 | the shipped baseline, Sonnet-generated | 85.4% | **93.4%** |
| v2 | `data/packed-v2/` | 31,546 | 22× volume, gemma-26B-A4B teacher | **91.5%** | 90.2% |
| v3 | `data/packed-v2-balanced/` | 44,211 | verdict rebalance only, same rows | 89.0% | 86.9% |
| v4 | `data/packed-v4/` | 42,841 | **teacher replaced** with dense gemma-4-31B | *pending* | *pending* |

`packed-v2-nomixin` / `packed-nomixin` are ablation twins — identical minus the general-chat mix-in.

**v2→v3 is the composition experiment and it did nothing** (1 improved / 8 flat / 3 regressed on the
holdout). Denominators are 82 and 61, so a 2-item move is noise — treat ±2 as flat.

**Coverage, not volume, is the usual bottleneck.** v3 had *zero* rows for 7 of 15 phenomena and
scored `imperativ` 1/4. v4 covers all 14 but is 66% `vmp`+`dawo`, with `imperativ` at 133 rows
against `vmp`'s 6,039. Check `data/packed-v4/meta.json` (`fix_balance`) before theorizing about a
model ceiling — **do not** infer phenomenon coverage by grepping the packed JSONL, that mis-reads.

---

## Eval suites — always guarded

"Guarded" = scored the way the app actually behaves, where a reply the app renders as nothing counts
as nothing. Ungentle but honest; unguarded numbers flatter models that emit unparseable output.

| file | items | tag | role |
|---|---:|---|---|
| `data/eval/grammar_eval_v0.json` | 60 | `guarded-v0` | **core** — the headline number ("54/60") |
| `data/eval/grammar_eval_v1_extra.json` | 61 | `guarded-v1ext` | extension — rarer phenomena |
| `data/eval/grammar_eval_v2_holdout.json` | 82 | `guarded-v2` | holdout — never trained on |
| `data/eval/conversation_v0.json` | 50 | — | naturalness proxy, not grammar |

Results land in `results/<tag>_<model>.json`. Prefixes: `baseline_` = stock, `finetuned_` = tuned,
`rescored_` = re-run through a corrected scorer, `-extra` = the v1ext suite.

**Score core first, always.** v3's whole lesson was that a good holdout number can hide a core
regression. Bars: beat v1's **54/60**; below stock's **48/60** the fine-tune is actively harmful.

Two scoring dimensions matter as much as the total, and they fail in opposite directions:
- **false-correction rate** — "fixes" sentences that were already correct (Gemma's failure mode)
- **miss rate** — rubber-stamps broken German as OK (Qwen/Phi/Llama's failure mode)

The second is fatal for a tutor; a student cannot learn from a model that waves errors through.

---

## Expensive lessons — each of these cost real money

1. **Dense teachers only.** `gemma-4-26B-A4B` (~4B active MoE) produced 12% correctly-shaped `refl`
   rows where dense 31B produced 100%. It poisoned two training runs before anyone noticed, because
   the bad rows were fluent, plausible, and correctly labelled. This rule also rules out
   `gpt-oss-120b` (5.1B active) and `gpt-oss-20b` (3.6B active).
2. **Shape gates, not just pass rates.** LanguageTool and spaCy answer "is this correct German?"
   They cannot answer "does this teach the skill the eval measures." Run
   `scripts/check_hard_case_share.py --strict` **and** `scripts/validate_data.py` on every batch.
   Gates: `refl case-change >= 60%`, `sep pure-reorder <= 5%`.
3. **Prefer loud failures.** The 31B's no-op rows (`student == fix`) are trivially filterable. The
   26B's reordered `sep` rows were silent. Accept worse yield for louder failure.
4. **Thinking mode eats the whole token budget.** Qwen3.x templates default to it and emit zero
   JSON — looks exactly like a capability failure. Pass `enable_thinking=False`. Reasoning-native
   formats (gpt-oss harmony channels) have the same hazard without a clean toggle.
5. **Delivered ratio ≠ requested ratio.** Asked the 31B for 65/35 fix/ok, got 51/49. Measure every
   batch and correct at pack time with `pack_dataset.py --fix-frac`.
6. **Capacity cliff below ~2B.** The same dataset gave E4B +13 pts, Qwen3-4B +14, and Gemma-3-1B
   **−26** — the 1B learned to produce fixes without the knowledge to aim them.
7. **Base substrate sets the ceiling.** Tuned Qwen3-4B (62%) still lost to *stock* Gemma E4B (72%).
   Fine-tuning does not buy German knowledge the base lacks.
8. **A teacher's vocabulary is not its personality.** Qwen3.8-27B looked lexically diverse until a
   same-teacher control: gemma-vs-gemma Jaccard 0.249 vs gemma-vs-Qwen 0.203, and Qwen's novel-word
   rate (14.5%) sat inside gemma's own resampling range (13.8%, 6.9–21.1%). Corpus statistics cannot
   detect a teacher ceiling — only a trained student's eval can.

---

## GPU work

Full runbook in [`runpod/bakeoff/README.md`](runpod/bakeoff/README.md). Non-negotiable:

```bash
runpodctl pod list        # must print an empty table
```

The auto-shutdown failsafe has failed **three** times on this project (stopped a healthy pod; never
fired and idled ~6 h; killed the generator but not the pod). Verify manually, every run. `remove`,
not `stop` — disk bills while stopped.

Typical costs: bulk generation ~$5 (A100 80 GB, ~3 h), a training run ~$2.20 (A40 48 GB, ~4 h), a
50-row bake-off ~$0.30.

---

## Concurrency

Several Claude sessions work this repo simultaneously. **Re-read a file immediately before editing
it** — another session may have rewritten it minutes ago. Check `git status` before any bulk move;
staged deletes you did not make mean someone else is mid-refactor.
