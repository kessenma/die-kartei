#!/usr/bin/env python3
"""
Calibration harness for the placement probe.

Replicates PlacementSession's two staircases and PlacementService's scoring exactly, then runs
simulated learners of KNOWN ability through them many times. The question this answers:
does the probe report the level the learner actually is?

No corpus needed — the sim works in probabilities, so nothing here depends on any dataset.

The constants below MIRROR `Services/PlacementService.swift`. Change one there, change it here,
re-run, and check the diagonal still holds:

    python3 tools/placement_calibration.py

This is how the shipped cutoffs were chosen, and it caught two bugs no code review would have:
uncorrected guessing credited a *true beginner* 210 of 585 A1 words, and using the conservative
credit estimator for classification made a true B1 read as A1 83 % of the time. Hence the split —
raw hit rates classify, guess-corrected and block-shrunk figures credit.
"""
import random
from collections import Counter

LEVELS = ["A1", "A2", "B1"]                 # GoetheLevel — vocabulary's reach
GRAMMAR_LADDER = ["A1", "A2", "B1", "B2"]   # PlacementService.grammarLadder

# ── Tuning under test (mirrors PlacementService) ──────────────────────────────
ANCHOR_ITEMS = 2
VOCAB_ITEMS = 8
GENDER_ITEMS = 5
PREP_ITEMS = 3
GRAMMAR_ITEMS = 8
CLOZE_GAPS = 3
CLOZE_PASS = 2
VOCAB_RESCUE_FLOOR = 0.50
START_LEVEL = "A2"
GRAMMAR_START = "A2"      # provisional; the anchors overwrite it
STEP_UP = 2
STEP_DOWN = 2
LEVEL_PASS_RATE = 0.65
SUPPORT_FLOOR = 0.50
MIN_ITEMS_PER_LEVEL = 2
VOCAB_CHOICES = 4
GENDER_CHOICES = 3
GRAMMAR_CHOICES = 3
PRIOR_ITEMS = 3           # sample-size shrinkage: few items => little credit
DEADBAND = 0.20           # below this, treat as noise and credit nothing (matches Swift)


# ── Simulated learners ────────────────────────────────────────────────────────
# knows[L]   = fraction of level L's word list this learner genuinely knows.
# grammar[L] = probability they genuinely hold a construct introduced at level L
#              (also the per-gap hit probability of a cloze paragraph at L).
PROFILES = {
    "true beginner": dict(knows={"A1": 0.03, "A2": 0.01, "B1": 0.00}, gender=0.05, prep=0.05,
                          grammar={"A1": 0.10, "A2": 0.03, "B1": 0.00, "B2": 0.00}),
    "true A1":       dict(knows={"A1": 0.85, "A2": 0.25, "B1": 0.05}, gender=0.60, prep=0.35,
                          grammar={"A1": 0.80, "A2": 0.30, "B1": 0.10, "B2": 0.02}),
    "true A2":       dict(knows={"A1": 0.97, "A2": 0.80, "B1": 0.30}, gender=0.75, prep=0.65,
                          grammar={"A1": 0.92, "A2": 0.78, "B1": 0.30, "B2": 0.10}),
    "true B1":       dict(knows={"A1": 0.99, "A2": 0.95, "B1": 0.75}, gender=0.87, prep=0.82,
                          grammar={"A1": 0.96, "A2": 0.90, "B1": 0.75, "B2": 0.30}),
    "true B2":       dict(knows={"A1": 1.00, "A2": 0.99, "B1": 0.92}, gender=0.93, prep=0.90,
                          grammar={"A1": 0.98, "A2": 0.95, "B1": 0.88, "B2": 0.75}),
}


def answers_correct(p_known, choices):
    """Knows it outright, or guesses among `choices`."""
    if random.random() < p_known:
        return True
    return random.random() < (1.0 / choices)


# ── The vocabulary staircase (mirrors PlacementSession.updateStaircase) ───────
def run_vocab_block(profile):
    level = START_LEVEL
    correct_streak = wrong_streak = 0
    seen = {L: [0, 0] for L in LEVELS}   # [correct, asked]

    for _ in range(VOCAB_ITEMS):
        ok = answers_correct(profile["knows"][level], VOCAB_CHOICES)
        seen[level][1] += 1
        if ok:
            seen[level][0] += 1
        i = LEVELS.index(level)
        if ok:
            correct_streak += 1
            wrong_streak = 0
            if correct_streak >= STEP_UP and i + 1 < len(LEVELS):
                level = LEVELS[i + 1]
                correct_streak = 0
        else:
            wrong_streak += 1
            correct_streak = 0
            if wrong_streak >= STEP_DOWN and i > 0:
                level = LEVELS[i - 1]
                wrong_streak = 0
    return seen


# ── The grammar staircase (mirrors PlacementSession.updateGrammarStaircase) ───
def run_grammar_blocks(profile):
    """Anchors pick the start; then 2-item blocks — 2/2 up, 0/2 down, split asks a same-level
    tiebreaker whose miss demotes and whose hit holds. Returns per-level [correct, asked]."""
    seen = {L: [0, 0] for L in GRAMMAR_LADDER}

    anchors_correct = 0
    for _ in range(ANCHOR_ITEMS):        # both anchors probe A2 constructs
        ok = answers_correct(profile["grammar"]["A2"], GRAMMAR_CHOICES)
        seen["A2"][1] += 1
        if ok:
            seen["A2"][0] += 1
            anchors_correct += 1
    level = {ANCHOR_ITEMS: "B1", 0: "A1"}.get(anchors_correct, GRAMMAR_START)

    block, awaiting_tiebreaker = [], False
    for _ in range(GRAMMAR_ITEMS):
        ok = answers_correct(profile["grammar"][level], GRAMMAR_CHOICES)
        seen[level][1] += 1
        if ok:
            seen[level][0] += 1
        i = GRAMMAR_LADDER.index(level)

        if awaiting_tiebreaker:
            awaiting_tiebreaker = False
            block = []
            if not ok and i > 0:
                level = GRAMMAR_LADDER[i - 1]
            continue

        block.append(ok)
        if len(block) < 2:
            continue
        rights = sum(block)
        if rights == 2:
            block = []
            if i + 1 < len(GRAMMAR_LADDER):
                level = GRAMMAR_LADDER[i + 1]
        elif rights == 0:
            block = []
            if i > 0:
                level = GRAMMAR_LADDER[i - 1]
        else:
            awaiting_tiebreaker = True
    return seen


# ── Scoring (mirrors PlacementService) ────────────────────────────────────────
def knowledge(correct, asked, choices, total_asked=None):
    """Observed hit rate -> fraction actually KNOWN.

    Two corrections, both biased conservative on purpose. Over-crediting fills the pyramid with
    words the learner can't produce, which is the failure this whole feature exists to prevent;
    under-crediting only means they earn it for real a bit sooner.

      1. correction for guessing: k-choice guessing floors the hit rate at 1/k, so strip it out.
      2. shrinkage: a 2-item sample is not evidence about 585 words, so pull toward 0 (not 0.5).
    """
    if asked <= 0:
        return 0.0
    raw = correct / asked
    chance = 1.0 / choices
    corrected = max(0.0, (raw - chance) / (1.0 - chance))
    if corrected < DEADBAND:
        return 0.0
    # Shrink on the size of the WHOLE block, not this level's slice. The staircase deliberately
    # spends its items where the learner is marginal, so a strong learner sees few A1 items
    # precisely because they climbed past A1 — penalising that would invert the measurement.
    n = total_asked if total_asked is not None else asked
    confidence = n / (n + PRIOR_ITEMS)
    return corrected * confidence


def vocab_known_by_level(seen):
    total = sum(n for _, n in seen.values())
    smoothed = {L: knowledge(c, n, VOCAB_CHOICES, total) for L, (c, n) in seen.items() if n > 0}
    if not smoothed:
        return {}

    filled, carried = {}, None
    for L in LEVELS:                       # forward fill
        if L in smoothed:
            carried = smoothed[L]
        if carried is not None:
            filled[L] = carried
    carried = None
    for L in reversed(LEVELS):             # backward fill
        if L in filled:
            carried = filled[L]
        elif carried is not None:
            filled[L] = carried

    out, ceiling = {}, 1.0                 # monotonic clamp
    for L in LEVELS:
        v = min(filled.get(L, 0.0), ceiling)
        out[L] = v
        ceiling = v
    return out


def grammar_peak(grammar_seen):
    peak = None
    for L in GRAMMAR_LADDER:
        c, n = grammar_seen.get(L, (0, 0))
        if n >= MIN_ITEMS_PER_LEVEL and (c / n) >= LEVEL_PASS_RATE:
            peak = L
    return peak


def estimate(vocab_seen, grammar_seen, article, prep, grammar_overall,
             cloze_level=None, cloze_correct=None):
    """Classification, deliberately NOT the same computation as credit.

    Uses RAW hit rates per level, not the shrunk credit figure. Order matters and mirrors Swift:
    vocab base -> grammar's one road to B2 -> support floor demotes -> cloze gate demotes.
    """
    reached, cleared = "A1", False
    for L in LEVELS:
        c, n = vocab_seen.get(L, (0, 0))
        if n >= MIN_ITEMS_PER_LEVEL and (c / n) >= LEVEL_PASS_RATE:
            reached, cleared = L, True
    candidate = reached if cleared else "A1"
    peak = grammar_peak(grammar_seen)

    # Rescue at the margin: the next list narrowly missed (raw >= rescue floor) while the grammar
    # staircase held that level or better. Pooled evidence, like telc counting Sprachbausteine
    # toward the written total; grammar alone still can't promote.
    if candidate in ("A1", "A2"):
        nxt = "A2" if candidate == "A1" else "B1"
        c, n = vocab_seen.get(nxt, (0, 0))
        if n >= MIN_ITEMS_PER_LEVEL and (c / n) >= VOCAB_RESCUE_FLOOR and peak is not None \
           and GRAMMAR_LADDER.index(peak) >= GRAMMAR_LADDER.index(nxt):
            candidate = nxt

    if candidate == "B1" and peak == "B2":
        candidate = "B2"

    support = [article, prep]
    if grammar_overall is not None:
        support.append(grammar_overall)
    if (sum(support) / len(support)) < SUPPORT_FLOOR:
        i = GRAMMAR_LADDER.index(candidate)
        if i > 0:
            candidate = GRAMMAR_LADDER[i - 1]

    if cloze_level is not None and cloze_correct is not None and cloze_correct < CLOZE_PASS:
        i = GRAMMAR_LADDER.index(candidate)
        if i > 0:
            candidate = GRAMMAR_LADDER[i - 1]
    return candidate


def run_once(profile):
    vocab_seen = run_vocab_block(profile)
    grammar_seen = run_grammar_blocks(profile)
    vocab = vocab_known_by_level({L: tuple(v) for L, v in vocab_seen.items()})

    article = sum(answers_correct(profile["gender"], GENDER_CHOICES) for _ in range(GENDER_ITEMS)) / GENDER_ITEMS
    prep = sum(answers_correct(profile["prep"], 4) for _ in range(PREP_ITEMS)) / PREP_ITEMS
    g_correct = sum(c for c, _ in grammar_seen.values())
    g_asked = sum(n for _, n in grammar_seen.values())
    grammar_overall = (g_correct / g_asked) if g_asked else None

    vocab_pairs = {L: tuple(v) for L, v in vocab_seen.items()}
    grammar_pairs = {L: tuple(v) for L, v in grammar_seen.items()}

    # The finale is asked at the pre-cloze estimate, exactly like the session does it.
    cloze_level = estimate(vocab_pairs, grammar_pairs, article, prep, grammar_overall)
    cloze_correct = sum(
        answers_correct(profile["grammar"][cloze_level], GRAMMAR_CHOICES) for _ in range(CLOZE_GAPS)
    )

    final = estimate(vocab_pairs, grammar_pairs, article, prep, grammar_overall,
                     cloze_level, cloze_correct)
    return final, vocab


def main(trials=4000):
    random.seed(20260815)
    print(f"pass rate {LEVEL_PASS_RATE:.0%} · support floor {SUPPORT_FLOOR:.0%} · cloze pass {CLOZE_PASS}/{CLOZE_GAPS} · "
          f"{ANCHOR_ITEMS} anchors / {VOCAB_ITEMS} vocab / {GENDER_ITEMS} gender / "
          f"{PREP_ITEMS} prep / {GRAMMAR_ITEMS} grammar / {CLOZE_GAPS}-gap cloze\n")
    header = f"{'learner':<16}" + "".join(f"{L:>8}" for L in GRAMMAR_LADDER) + "     mean vocabKnown(A1/A2/B1)"
    print(header)
    print("-" * len(header))
    for name, profile in PROFILES.items():
        counts = Counter()
        acc = {L: 0.0 for L in LEVELS}
        for _ in range(trials):
            est, vocab = run_once(profile)
            counts[est] += 1
            for L in LEVELS:
                acc[L] += vocab.get(L, 0)
        row = f"{name:<16}" + "".join(f"{counts[L]/trials:>7.0%} " for L in GRAMMAR_LADDER)
        means = " / ".join(f"{acc[L]/trials:.2f}" for L in LEVELS)
        print(f"{row}    {means}")


if __name__ == "__main__":
    main()
