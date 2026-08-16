#!/usr/bin/env python3
"""Naturalness proxies for the conversation bench — the second axis next to grammar.

Answers "is this model more human-sounding than that one?" with numbers instead of a vibe, so
the trade in DATA_V2_DISTILL_PLAN.md Phase 2 ("slightly worse grammar but more natural") is a
decision made on evidence.

WHAT THESE ARE: proxies for variety and spoken register. A model can score well here and still
read like a textbook — high opening variety with stilted sentences is entirely possible. They
are reliable for A/B and regression detection on a FIXED bench (same prompts, same temperature,
old model vs new), which is the job. They are not a naturalness certificate; native review
(Phase 5) is. Never tune against them directly.

Metrics
  opening_variety      distinct first-3-token prefixes / n replies. Catches "Das ist interessant!"
                       on repeat — the single most robotic tic in a tutor.
  modal_particle_rate  doch/mal/eigentlich/ja/eben/halt/schon/denn/wohl per 100 tokens. The
                       clearest spoken-vs-written German marker; textbook models emit almost none.
  followup_rate        share of replies ending in a question. The app's prompt explicitly asks
                       for this, so it doubles as instruction-following.
  repeat_4gram_share   share of replies containing one of the top-5 repeated 4-grams. High =
                       the model has a handful of canned phrases it recycles.
  sentences_per_reply  mean + spread. The prompt asks for one to three; both under- and
                       over-shooting are failures.
  type_token_ratio     lexical variety across the whole run (length-normalised via MSTTR-50).
  english_leakage      share of replies containing English function words. Should be ~0 —
                       conversation mode forbids English outright.
  question_variety     distinct question-word openings, so followup_rate can't be gamed by
                       ending every reply with the same "Und du?".

Usage (from training/):
  .venv/bin/python scripts/naturalness_metrics.py results/conv_e4b-v1_*.responses.json
  # compare two models side by side:
  .venv/bin/python scripts/naturalness_metrics.py --compare \
      results/conv_v1_gemma4-e4b-german-tutor-4bit.responses.json \
      results/conv_v2_gemma4-e4b-german-tutor-4bit.responses.json
"""

import argparse
import json
import re
import statistics
from collections import Counter
from pathlib import Path

# Spoken-German flavouring particles. `denn`/`ja`/`doch` are also ordinary words, so this
# over-counts slightly — consistently, across every model, which is what a comparison needs.
MODAL_PARTICLES = ["doch", "mal", "eigentlich", "ja", "eben", "halt", "schon", "denn", "wohl"]

# English function words that would never appear in a German-only reply. Deliberately short and
# unambiguous: no "die"/"war"/"was"/"also"/"hat", which are all real German words.
ENGLISH_MARKERS = ["the", "and", "you", "your", "with", "that", "this", "have", "would",
                   "there", "about", "what", "which", "could", "should", "because"]

QUESTION_OPENERS = ["was", "wie", "wo", "wann", "warum", "wer", "wen", "wem", "wessen",
                    "welche", "welcher", "welches", "welchen", "welchem",
                    "wohin", "woher", "wieso", "weshalb"]

# wo-compounds (worauf, woran, wofür, womit, wonach, …) are interrogatives too. Listing them by
# hand missed woran/wofür and understated E4B's wh-share ~5x, so match them structurally instead —
# same shape as validate_data.py's DAWO_RE. Anchored, so "wir"/"wird"/"will"/"war" can't match.
WO_COMPOUND_RE = re.compile(
    r"^wo(r)?(an|auf|aus|bei|durch|für|gegen|hin|in|mit|nach|neben|über|um|unter|von|vor|zu|zwischen)$"
)


def is_wh(token: str) -> bool:
    return token in QUESTION_OPENERS or bool(WO_COMPOUND_RE.match(token))


def tokens(text: str) -> list:
    return re.findall(r"[a-zA-ZäöüßÄÖÜ]+", text.lower())


def sentences(text: str) -> list:
    return [s for s in re.split(r"[.!?…]+", text) if s.strip()]


def msttr(toks: list, window: int = 50) -> float:
    """Mean segmental type-token ratio. Plain TTR falls as text grows, so a chattier model would
    look less varied purely for being longer; MSTTR averages TTR over fixed-size windows instead."""
    if len(toks) < window:
        return len(set(toks)) / len(toks) if toks else 0.0
    chunks = [toks[i:i + window] for i in range(0, len(toks) - window + 1, window)]
    return statistics.mean(len(set(c)) / len(c) for c in chunks)


def ngrams(toks: list, n: int) -> list:
    return [tuple(toks[i:i + n]) for i in range(len(toks) - n + 1)]


# Words German legitimately repeats without it being a defect, plus clause-level noise.
_STUTTER_SKIP = {"ja", "nein", "so", "sehr", "nur", "auch", "noch", "mal", "doch",
                 "und", "die", "der", "das", "sie", "du", "wir", "ich"}
_REAL_WORD = re.compile(r"^[a-zäöüß]{2,}$")
# Clause boundaries, NOT just sentence boundaries. German repeats words across a comma constantly —
# "eingefügt wird, wird es platziert", "entwerfen würde, würde ich", "Meinst du, du schaffst es" —
# and a splitter that only breaks on .!? reports all of those as stutters. That false-positive rate
# was ~100%: it made the training corpus look 8.6% defective when the real rate is ~0.
_CLAUSE = re.compile(r"[.!?:;,\n]+|```|\bund\b|\baber\b|\bdass\b|\bweil\b|\bwenn\b")


def stutters(text: str) -> list:
    """Adjacent word repeats WITHIN a clause — the 'erst mal erst mal' defect class.

    Measured separately from `repeat_4gram_share`, which compares ACROSS replies and therefore
    cannot see a reply that stutters internally. E4B v2 had exactly one (1/50) and the bench
    scored it clean, which is what prompted adding this.
    """
    out = []
    for clause in _CLAUSE.split(text or ""):
        toks = [t for t in re.findall(r"[a-zäöüßA-ZÄÖÜ]+", (clause or "").lower())]
        for n in (1, 2, 3):
            for i in range(len(toks) - 2 * n + 1):
                a, b = toks[i:i + n], toks[i + n:i + 2 * n]
                if a == b and all(_REAL_WORD.match(t) for t in a) \
                        and not (n == 1 and a[0] in _STUTTER_SKIP):
                    out.append(" ".join(a + b))
    return out


def compute(results: list) -> dict:
    replies = [r["response"].strip() for r in results if r.get("response", "").strip()]
    n = len(replies)
    if not n:
        return {"n": 0}

    all_toks = [t for r in replies for t in tokens(r)]

    openings = [" ".join(tokens(r)[:3]) for r in replies]
    opening_variety = len(set(openings)) / n

    particles = sum(1 for t in all_toks if t in MODAL_PARTICLES)
    modal_rate = particles / len(all_toks) * 100 if all_toks else 0.0

    ends_question = sum(1 for r in replies if r.rstrip().endswith("?"))
    followup_rate = ends_question / n

    # Question variety: the actual first word of every question asked. An earlier version bucketed
    # anything not in QUESTION_OPENERS as "_other", which collapsed every yes/no question (they are
    # verb-initial in German) into a single bucket and understated variety ~6x. Use the real token.
    q_openers = []
    for r in replies:
        for q in re.split(r"(?<=[.!?])\s+", r):
            if q.strip().endswith("?"):
                tk = tokens(q)
                if tk:
                    q_openers.append(tk[0])
    question_variety = len(set(q_openers)) / len(q_openers) if q_openers else 0.0
    q_counts = Counter(q_openers)
    top_opener_share = (q_counts.most_common(1)[0][1] / len(q_openers)) if q_openers else 0.0
    wh_share = (sum(1 for o in q_openers if is_wh(o)) / len(q_openers)) if q_openers else 0.0

    four = Counter(g for r in replies for g in ngrams(tokens(r), 4))
    top5 = [g for g, c in four.most_common(5) if c > 1]
    repeat_share = (sum(1 for r in replies
                        if any(g in set(ngrams(tokens(r), 4)) for g in top5)) / n) if top5 else 0.0

    sent_counts = [len(sentences(r)) for r in replies]
    leak = sum(1 for r in replies if any(t in ENGLISH_MARKERS for t in tokens(r))) / n
    stut = [r for r in replies if stutters(r)]

    return {
        "n": n,
        "opening_variety": round(opening_variety, 3),
        "modal_particle_rate": round(modal_rate, 2),
        "followup_rate": round(followup_rate, 3),
        "question_variety": round(question_variety, 3),
        "top_opener_share": round(top_opener_share, 3),
        "wh_question_share": round(wh_share, 3),
        "repeat_4gram_share": round(repeat_share, 3),
        "sentences_per_reply": round(statistics.mean(sent_counts), 2),
        "sentences_stdev": round(statistics.pstdev(sent_counts), 2),
        "mean_tokens_per_reply": round(len(all_toks) / n, 1),
        "type_token_ratio": round(msttr(all_toks), 3),
        "english_leakage": round(leak, 3),
        "stutter_rate": round(len(stut) / n, 3),
        "_stutters": [f"{stutters(r)[0]!r} in: {r[:70]}" for r in stut[:3]],
        "_top_repeated_4grams": [" ".join(g) + f" ×{c}" for g, c in four.most_common(5) if c > 1],
    }


# Direction each metric should move to be *more* human. `None` = no target, report only.
BETTER = {
    "opening_variety": "up", "modal_particle_rate": "up", "question_variety": "up",
    "top_opener_share": "down", "repeat_4gram_share": "down", "english_leakage": "down",
    "followup_rate": None, "wh_question_share": None, "sentences_per_reply": None,
    "type_token_ratio": "up", "stutter_rate": "down",
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--compare", action="store_true",
                    help="print a side-by-side delta table instead of one block per file")
    ap.add_argument("--by-kind", action="store_true",
                    help="also break the metrics down by item kind (opener/reply/multi/edge_*)")
    args = ap.parse_args()

    loaded = []
    for f in args.files:
        payload = json.loads(Path(f).read_text())
        loaded.append((Path(f).stem, payload.get("model", "?"), payload["results"]))

    if args.compare and len(loaded) >= 2:
        stats = [(name, compute(res)) for name, _, res in loaded]
        keys = [k for k in stats[0][1] if not k.startswith("_") and k != "n"]
        w = max(len(k) for k in keys) + 2
        print(f"{'metric':<{w}}" + "".join(f"{n[:26]:>28}" for n, _ in stats) + "   better")
        print("-" * (w + 28 * len(stats) + 10))
        for k in keys:
            row = f"{k:<{w}}" + "".join(f"{s.get(k, '-'):>28}" for _, s in stats)
            print(row + f"   {BETTER.get(k) or '-'}")
        return

    for name, model, res in loaded:
        print(f"\n=== {name}  ({model}) ===")
        s = compute(res)
        for k, v in s.items():
            if k.startswith("_"):
                continue
            arrow = f"  [{BETTER[k]} is better]" if BETTER.get(k) else ""
            print(f"  {k:<24} {v}{arrow}")
        if s.get("_top_repeated_4grams"):
            print(f"  most repeated 4-grams: {s['_top_repeated_4grams']}")
        if s.get("_stutters"):
            print("  within-clause stutters:")
            for x in s["_stutters"]:
                print(f"    {x}")
        if args.by_kind:
            kinds = sorted({r.get("kind", "?") for r in res})
            print("  --- by kind ---")
            for kind in kinds:
                sub = compute([r for r in res if r.get("kind") == kind])
                if sub.get("n"):
                    print(f"  {kind:<14} n={sub['n']:<3} open_var={sub['opening_variety']:<6} "
                          f"particles={sub['modal_particle_rate']:<6} "
                          f"followup={sub['followup_rate']:<6} eng={sub['english_leakage']}")


if __name__ == "__main__":
    main()
