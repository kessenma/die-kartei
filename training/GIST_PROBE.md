# Gist judge probe — can a tutor check a listening summary?

Hören ▸ Worum geht's? (`docs/HOEREN.md`) asks the learner to sum up a story they heard, in
English, then compares the summary with the story's 3–4 key points. In Release the learner ticks
each point themselves. This probe measures whether a tutor could do the ticking instead, before
anything is gated on it (roadmap item 3: "measure first"). **No thresholds are set here.**

Run 2026-11-20, on this Mac.

## Method

- **Fixtures**: `data/gist_probe/fixtures.json`. 8 stories (the 7 bundled Kasus stories and one
  news report), each with 4 English key points and 7 learner-style summaries: full, partial, vague,
  wrong detail, off topic, in German, one point copied. 56 judged summaries, 224 points. One more
  summary ("train late") is under four words, so the app never sends it (`GistPrompts.isJudgeable`).
- **Gold labels** (ja / teilweise / nein per point) were **drafted by Claude and not yet reviewed
  by Kyle.** "Vague" golds are the most subjective (mostly teilweise).
- **Prompt and parser are the app's own**: `hoeren_cli/` compiles `Services/Hoeren/GistPrompts.swift`.
  The judge sees the numbered points and the summary, never the story, as in the app.
- **Sampling as in the app**: `generateText` at temperature 0.1, 160 max tokens, one run each.
  MLX tutors through `scripts/kasus_concept_probe.py` (unchanged); Apple Intelligence through
  `hoeren-cli fm-run` (FoundationModels).

```bash
cd training
hoeren_cli/build.sh
hoeren_cli/build/hoeren-cli prompts data/gist_probe/fixtures.json ../german-ai-flashcards/Resources/kasus_stories.json > results/gist-probe/prompts.jsonl
.venv/bin/python scripts/kasus_concept_probe.py --model all --prompts results/gist-probe/prompts.jsonl --out results/gist-probe
hoeren_cli/build/hoeren-cli fm-run results/gist-probe/prompts.jsonl results/gist-probe/raw_apple.jsonl
hoeren_cli/build/hoeren-cli score data/gist_probe/fixtures.json results/gist-probe/raw_*.jsonl
```

## Columns

- **Agree**: the model's verdict equals the gold one, per point.
- **False yes**: gold nein, model ja (credit for a point the summary does not have). The
  trust-killer in the sense of the correction tutor's false-correction rate.
- **Over-credit**: the model gave more than gold (nein → teilweise, teilweise → ja, nein → ja).
- **False no**: gold ja, model nein.
- **Unparseable**: no readable verdict for the point (missing line, echoed format). Shown as unsure.
- **Score error**: mean |model score − gold score| per summary, in points (ja 1, teilweise ½).

## Results

| Model | Points | Agree | False yes | Over-credit | False no | Unparseable | Score error (pts) | s / answer |
|---|---|---|---|---|---|---|---|---|
| Gemma 4 E4B tutor (v4) | 224 | 79% | 1% | 10% | 1% | 3% | 0.29 | 1.6 |
| Gemma 4 E2B tutor | 224 | 66% | 1% | 9% | 1% | 11% | 0.35 | 0.8 |
| Granite 4.1 3B tutor (v4) | 224 | 52% | 0% | 4% | 10% | 22% | 0.82 | 1.6 |
| Granite 3.3 2B tutor (v4) | 224 | 54% | 5% | 19% | 13% | 3% | 0.66 | 1.4 |
| Apple Intelligence | 224 | 58% | 12% | 33% | 2% | 4% | 0.87 | 1.7 |

Agreement by summary type:

| Type | E4B | E2B | Granite 3B | Granite 2B | Apple |
|---|---|---|---|---|---|
| full | 100% | 97% | 81% | 53% | 91% |
| partial | 81% | 66% | 50% | 53% | 59% |
| vague | 44% | 41% | 19% | 31% | 19% |
| wrong_detail | 72% | 56% | 41% | 41% | 59% |
| off_topic | 100% | 100% | 62% | 100% | 56% |
| german | 75% | 59% | 53% | 50% | 66% |
| copied_point | 81% | 41% | 56% | 50% | 53% |

### The prompt changed once, during the probe

The first judge prompt gave the format as `<number>: ja | teilweise | nein ; <why>`. Apple
Intelligence copied that line back for most points (25% agreement, 55% unreadable). Two fixes, both
now in the app: the prompt shows three example answer lines instead of the alternation, and the
parser treats an answer containing `|` or `/` as unreadable rather than as its first word (a test
pins this). Apple Intelligence with the new prompt: the row above. The MLX tutors only ran on the
new prompt.

## What it says (for Kyle to judge)

- **E4B is close to usable as a judge**: 79% agreement, false yes 1%, score off by about a third of
  a point per summary. It is weakest on vague summaries, where the gold labels are softest anyway.
- **E2B is cautious, not wrong**: false yes 1%, but 11% of points unreadable, and it misses the
  one-point-copied case.
- **Both Granites and Apple Intelligence are not judges**: half the points wrong, and Apple
  Intelligence gives credit for missing points 12% of the time (a third over-credited).

Options, none chosen:

1. Keep self-ticks only (what ships now).
2. Offer "Ask the tutor" on E4B only, shown beside the learner's own ticks as a second opinion, never
   replacing them.
3. Before deciding, review the gold labels (especially vague and German), rerun with 3 repeats to
   see how stable each verdict is, and add real summaries Kyle writes while testing (each gist
   round stores its summary and ticks in `HoerenRound.items`).

## Files

- `data/gist_probe/fixtures.json` — stories, key points, summaries, gold labels.
- `hoeren_cli/` — the Mac tool (`prompts`, `fm-run`, `score`).
- `results/gist-probe/` (git-ignored) — prompts and raw answers per model.
