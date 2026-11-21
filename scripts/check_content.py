#!/usr/bin/env python3
"""Lint every bundled German corpus.

Three independent axes decide whether shipped German is good, and none subsumes another:

  1. self-consistency -- does an item agree with its own metadata?  Cheap, deterministic,
     100% coverage.  This file, default mode.
  2. grammaticality   -- is the German well formed?  `--languagetool`, plus KasusValidator
     on the Swift side (training/kasus_cli).
  3. naturalness      -- would a German actually say this?  No tool catches it; a human
     reads a stratified sample (training/scripts/*_review.py).

Axis 1 is the one that pays: it found 32% of past_tense_verbs' examples missing their own
participle, where LanguageTool flagged 4%.  "Gestern habe ich gekundigt." filed under
*anbieten* is flawless German and completely wrong.

Default mode is stdlib only, so it runs anywhere.  `--languagetool` needs training/.venv.

    python3 scripts/check_content.py              # fail on anything new
    python3 scripts/check_content.py --report     # the per-corpus table, exit 0
    python3 scripts/check_content.py --write-baseline
    training/.venv/bin/python scripts/check_content.py --languagetool
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
RES = REPO / "german-ai-flashcards/Resources"
BASELINE = REPO / "scripts/content_baseline.json"
WIKTIONARY = RES / "wiktionary_de.db"

#: Nouns where wiktionary_de.db is the unreliable side, so a disagreement is not an app bug:
#: plurale tantum filed under a singular, genuinely dual-gender words, or a Wiktextract slip
#: (`Konsulat` is das, the DB says m). `Virus` is das in the standard and der colloquially;
#: the app teaches der, which is defensible, so it is excluded rather than "fixed".
GENDER_EXCEPTIONS = {"Geschwister", "Leute", "Möbel", "Tram", "Tropfen", "Eltern", "Ferien",
                     "Konsulat", "Virus"}

#: A plural or gerund row carries the *lemma's* gender, which says nothing about the form in
#: hand ("Äpfel: nominative plural of Apfel", "Steuern: gerund of steuern"). Rows glossed
#: "inflection of" / "female equivalent of" are kept: for an adjectival noun like `Beamte`
#: they are the only evidence that `der Beamte` exists alongside `die Beamte`.
INFLECTED_GLOSS = re.compile(r"\b(plural|gerund) of\b", re.I)

ARTICLE_TO_GENDER = {"der": "m", "die": "f", "das": "n"}
GENDER_WORD = {"maskulin": "m", "feminin": "f", "neutrum": "n", "m": "m", "f": "f", "n": "n"}

SENTENCE_END = (".", "!", "?", "…", "“", "”", "»", "«")
#: PDF-extraction debris seen in the Goethe vocab examples.
JUNK_PREFIX = re.compile(r"^(\(pl\.\)|\(sich\),?|\d*WORTLISTE|hat\s+[a-zäöüß]+\s|ist\s+[a-zäöüß]+\s)")


class Findings:
    def __init__(self) -> None:
        self.rows: list[tuple[str, str, str, str]] = []

    def add(self, corpus: str, rule: str, item: str, detail: str) -> None:
        self.rows.append((corpus, rule, item, detail))

    def by_corpus_rule(self) -> Counter:
        return Counter((c, r) for c, r, _, _ in self.rows)


def load(name: str):
    return json.loads((RES / name).read_text(encoding="utf-8"))


class Lexicon:
    """The bundled dictionary, used to cross-check every gender claim in the app."""

    def __init__(self) -> None:
        # One pass over the 350k rows into a dict. The table is indexed on `word_lower`, not
        # `word`, so per-word lookups would each be a full scan.
        self.by_word: dict[str, set[str]] = defaultdict(set)
        if not WIKTIONARY.exists():
            return
        con = sqlite3.connect(WIKTIONARY)
        for word, gender, gloss in con.execute(
                "select word, gender, translation from words where gender is not null"):
            if not INFLECTED_GLOSS.search(gloss or ""):
                self.by_word[word].add(gender)
        con.close()

    def genders(self, word: str) -> set[str]:
        """Genders the dictionary files for this exact surface form, ignoring rows that merely
        describe it as a plural or a gerund of something else."""
        return self.by_word.get(word, set())

    def check(self, f: Findings, corpus: str, item: str, word: str, claimed: str) -> None:
        # a plural claim says nothing about the lemma's gender, which is all the dictionary has
        if not word or claimed == "pl" or word in GENDER_EXCEPTIONS:
            return
        known = self.genders(word)
        if known and claimed not in known:
            f.add(corpus, "gender-conflict", item, f"{word}: says {claimed}, dictionary {sorted(known)}")


# ------------------------------------------------------------------ shared rules

def text_hygiene(f: Findings, corpus: str, item: str, text: str, *, allow_multi=False) -> None:
    if text is None:
        return
    s = text.strip()
    if not s:
        return
    if s != text:
        f.add(corpus, "whitespace", item, repr(text[:50]))
    if JUNK_PREFIX.match(s):
        f.add(corpus, "junk-prefix", item, repr(s[:60]))
    elif s[:1].islower():
        f.add(corpus, "starts-lowercase", item, repr(s[:60]))
    if not s.endswith(SENTENCE_END):
        f.add(corpus, "no-final-punctuation", item, repr(s[:60]))
    if not allow_multi and len(re.findall(r"[.!?]", s)) > 1:
        f.add(corpus, "multiple-sentences", item, repr(s[:60]))


def answer_in_options(f: Findings, corpus: str, item: str, answer, options) -> None:
    if answer is None or not options:
        return
    if answer not in options:
        f.add(corpus, "answer-not-in-options", item, f"{answer!r} not in {options}")


def blanks_match(f: Findings, corpus: str, item: str, sentence: str, expected: int,
                 marker: str = "______") -> None:
    found = sentence.count(marker)
    if found != expected:
        f.add(corpus, "blank-count", item, f"{found} × {marker!r}, expected {expected}")


# ------------------------------------------------------------------ per corpus

def check_past_tense(f: Findings, lex: Lexicon) -> None:
    corpus = "past_tense_verbs.json"
    rows = load(corpus)
    seen_level: set[tuple[str, str]] = set()
    AUX = {"haben": {"habe", "hast", "hat", "haben", "habt"},
           "sein": {"bin", "bist", "ist", "sind", "seid"}}
    for r in rows:
        inf = r.get("infinitive", "?")
        key = (inf, r.get("level"))
        if key in seen_level:
            f.add(corpus, "duplicate-infinitive-level", inf, f"level {r.get('level')}")
        seen_level.add(key)
        ex, pp, aux = r.get("example"), r.get("pastParticiple"), r.get("auxiliary")
        if r.get("isSeparable") and r.get("prefix") and pp and not pp.lower().startswith(r["prefix"].lower()):
            f.add(corpus, "prefix-not-on-participle", inf, f"{pp} vs prefix {r['prefix']}")
        if not ex:
            continue
        text_hygiene(f, corpus, inf, ex)
        if pp and pp.lower() not in ex.lower():
            f.add(corpus, "participle-missing", inf, f"{pp!r} not in {ex!r}")
        words = {w.lower() for w in re.findall(r"[A-Za-zÄÖÜäöüß]+", ex)}
        if aux in AUX:
            other = "sein" if aux == "haben" else "haben"
            if not (words & AUX[aux]) and (words & AUX[other]):
                f.add(corpus, "auxiliary-mismatch", inf, f"says {aux}, example uses {other}: {ex!r}")
        # a contentless template teaches nothing: "Ich habe benutzt."
        filler = AUX["haben"] | AUX["sein"] | {"ich", "du", "er", "sie", "es", "wir", "ihr",
                                               "gestern", "heute", "das", "mich", "mir"}
        if pp:
            content = words - filler - {pp.lower()}
            if not content:
                f.add(corpus, "contentless-example", inf, repr(ex))


def check_vocabulary(f: Findings, lex: Lexicon) -> None:
    for level in ("a1", "a2", "b1"):
        corpus = f"{level}_vocabulary.json"
        for r in load(corpus):
            word = r.get("word", "?")
            art = (r.get("article") or "").lower()
            if art in ARTICLE_TO_GENDER:
                lex.check(f, corpus, word, word, ARTICLE_TO_GENDER[art])
            # A1 deliberately ships two-sentence examples; A2/B1 do not.
            text_hygiene(f, corpus, word, r.get("example"), allow_multi=(level == "a1"))


def check_grammar_exercises(f: Findings, lex: Lexicon) -> None:
    corpus = "grammar_exercises.json"
    data = load(corpus)
    for cat in data["categories"]:
        for e in cat["exercises"]:
            eid = e.get("id", "?")
            answer_in_options(f, corpus, eid, e.get("correctAnswer"), e.get("options") or cat.get("options"))
            blanks_match(f, corpus, eid, e.get("sentence", ""), 1)
            g = GENDER_WORD.get((e.get("gender") or "").lower())
            if g:
                lex.check(f, corpus, eid, e.get("noun", ""), g)


def check_placement(f: Findings, lex: Lexicon) -> None:
    corpus = "placement_grammar.json"
    data = load(corpus)
    for i in data["items"]:
        answer_in_options(f, corpus, i.get("id", "?"), i.get("correct"), i.get("options"))
        blanks_match(f, corpus, i.get("id", "?"), i.get("sentence", ""), 1)
    for c in data.get("cloze", []):
        for n, g in enumerate(c["gaps"]):
            answer_in_options(f, corpus, f"{c['id']}#{n}", g.get("correct"), g.get("options"))
            if "{%d}" % n not in c["text"]:
                f.add(corpus, "blank-count", c["id"], f"no placeholder {{{n}}} in text")


def check_gap_choice(f: Findings, lex: Lexicon) -> None:
    corpus = "gap_choice_items.json"
    for i in load(corpus)["items"]:
        iid = i.get("id", "?")
        for n, g in enumerate(i["gaps"], start=1):
            answer_in_options(f, corpus, iid, g.get("answer"), g.get("options"))
            if "{%d}" % n not in i["sentence"]:
                f.add(corpus, "blank-count", iid, f"no placeholder {{{n}}}")
        obj = i.get("secondObject") or {}
        art = {"der": "m", "die": "f", "das": "n"}.get((obj.get("genus") or "").lower())
        if art and obj.get("number") != "pl":
            lex.check(f, corpus, iid, obj.get("lemma", ""), art)


def check_verb_prepositions(f: Findings, lex: Lexicon) -> None:
    corpus = "verb_prepositions.json"
    data = load(corpus)
    for v in data["verbs"]:
        for ex in v["examples"]:
            vid = v.get("verb", "?")
            for field in ("gap", "object"):
                if ex.get(field) and ex[field] not in ex["german"]:
                    f.add(corpus, "fragment-not-in-sentence", vid, f"{field}={ex[field]!r}")
            if ex.get("gap") and ex["gap"] in (ex.get("wrong") or []):
                f.add(corpus, "answer-listed-as-wrong", vid, ex["gap"])
            text_hygiene(f, corpus, vid, ex.get("german"))
            if ex.get("gender"):
                lex.check(f, corpus, vid, ex.get("noun", ""), ex["gender"])
    for t in data.get("falle", []):
        answer_in_options(f, corpus, t.get("id", "?"), t.get("answer"), t.get("options"))
        blanks_match(f, corpus, t.get("id", "?"), t.get("sentence", ""), 1)


def check_kasus(f: Findings, lex: Lexicon) -> None:
    """These pass today -- the rules are a regression guard on the gated corpora."""
    for corpus, key in (("kasus_concepts.json", "items"), ("kasus_stories.json", "stories")):
        for it in load(corpus)[key]:
            iid = it.get("id", "?")
            text = " ".join(p["de"] for p in it["paragraphs"])
            for t in it.get("targets", []):
                if t.get("phrase") and t["phrase"] not in text:
                    f.add(corpus, "target-not-in-text", iid, t["phrase"])
                if t.get("genus") in ("m", "f", "n") and t.get("lemma"):
                    lex.check(f, corpus, iid, t["lemma"], t["genus"])


def check_prepositions(f: Findings, lex: Lexicon) -> None:
    corpus = "prepositions.json"
    for p in load(corpus)["prepositions"]:
        for ex in p.get("examples", []):
            text_hygiene(f, corpus, p.get("word", "?"), ex.get("german"))


WRITING_LEVEL_RANGE = {"A1": (30, 60), "A2": (60, 110), "B1": (110, 180), "B2": (180, 280)}
WRITING_FOCI = {"perfekt", "praeteritum", "futur", "konjunktiv2", "artikel", "akkusativ", "dativ",
                "genitiv", "modalverben", "praepositionen", "wechselpraepositionen",
                "adjektivendungen", "verbenPraepositionen", "reflexivverben"}
#: Introduced at (index into A1 < A2 < B1 < B2), mirrors GrammarFocus.introducedAt.
WRITING_FOCUS_LEVEL = {"artikel": 0, "akkusativ": 0, "modalverben": 0, "perfekt": 0, "praepositionen": 0,
                       "dativ": 1, "praeteritum": 1, "futur": 1, "wechselpraepositionen": 1, "reflexivverben": 1,
                       "genitiv": 2, "konjunktiv2": 2, "adjektivendungen": 2, "verbenPraepositionen": 2}


def check_writing_prompts(f: Findings, lex: Lexicon) -> None:
    """The Schreiben room's prompt bank (docs/SCHREIBEN.md). Mirrors WritingPromptBank.validate."""
    corpus = "writing_prompts.json"
    seen: set[str] = set()
    levels = list(WRITING_LEVEL_RANGE)
    for p in load(corpus)["prompts"]:
        pid = p.get("id", "?")
        if pid in seen:
            f.add(corpus, "duplicate-id", pid, "")
        seen.add(pid)
        text_hygiene(f, corpus, pid, p.get("de"), allow_multi=True)
        if len(re.findall(r"[.!?](\s|$)", p.get("de", ""))) > 2:
            f.add(corpus, "too-many-sentences", pid, repr(p["de"][:60]))
        if not (p.get("en") or "").strip():
            f.add(corpus, "empty-en", pid, "")
        if not p.get("topics"):
            f.add(corpus, "no-topics", pid, "")
        level = p.get("level")
        if level not in WRITING_LEVEL_RANGE:
            f.add(corpus, "bad-level", pid, repr(level))
            continue
        focus = p.get("focus")
        if focus is not None:
            if focus not in WRITING_FOCI:
                f.add(corpus, "unknown-focus", pid, repr(focus))
            elif WRITING_FOCUS_LEVEL[focus] > levels.index(level):
                f.add(corpus, "focus-above-level", pid, f"{focus} at {level}")
        target = p.get("targetWords")
        if p.get("kind") == "aufsatz":
            if not target:
                f.add(corpus, "missing-target", pid, "")
            else:
                lo, hi = WRITING_LEVEL_RANGE[level]
                if target["min"] >= target["max"]:
                    f.add(corpus, "target-order", pid, repr(target))
                if target["min"] < lo or target["max"] > hi:
                    f.add(corpus, "target-outside-level", pid, f"{target} outside {lo}-{hi}")
        elif target:
            f.add(corpus, "tagebuch-with-target", pid, repr(target))
        if len(p.get("scaffold") or []) > 4:
            f.add(corpus, "too-much-scaffold", pid, "")


CHECKS = [check_past_tense, check_vocabulary, check_grammar_exercises, check_placement,
          check_gap_choice, check_verb_prepositions, check_kasus, check_prepositions,
          check_writing_prompts]


# ------------------------------------------------------------------ axis 2

def german_sentences() -> dict[str, list[str]]:
    """Every German string a learner can read, per corpus, with gaps filled in."""
    out: dict[str, list[str]] = defaultdict(list)
    for level in ("a1", "a2", "b1"):
        name = f"{level}_vocabulary.json"
        out[name] = [r["example"] for r in load(name) if (r.get("example") or "").strip()]
    out["past_tense_verbs.json"] = [r["example"] for r in load("past_tense_verbs.json")
                                    if (r.get("example") or "").strip()]
    out["kasus_concepts.json"] = [p["de"] for it in load("kasus_concepts.json")["items"]
                                  for p in it["paragraphs"]]
    out["kasus_stories.json"] = [p["de"] for s in load("kasus_stories.json")["stories"]
                                 for p in s["paragraphs"]]
    out["gap_choice_items.json"] = [
        i["sentence"].replace("{1}", i["gaps"][0]["answer"])
        for i in load("gap_choice_items.json")["items"] if len(i["gaps"]) == 1]
    ge = load("grammar_exercises.json")
    out["grammar_exercises.json"] = [e["sentence"].replace("______", e["correctAnswer"])
                                     for c in ge["categories"] for e in c["exercises"]]
    out["placement_grammar.json"] = [i["sentence"].replace("______", i["correct"])
                                     for i in load("placement_grammar.json")["items"]]
    vp = load("verb_prepositions.json")
    out["verb_prepositions.json"] = ([ex["german"] for v in vp["verbs"] for ex in v["examples"]]
                                     + [t["sentence"].replace("______", t["answer"])
                                        for t in vp.get("falle", [])])
    out["prepositions.json"] = [ex["german"] for p in load("prepositions.json")["prepositions"]
                                for ex in p.get("examples", [])]
    out["writing_prompts.json"] = [p["de"] for p in load("writing_prompts.json")["prompts"]]
    return out


def run_languagetool(f: Findings) -> None:
    try:
        import language_tool_python as ltp
    except ImportError:
        sys.exit("--languagetool needs training/.venv: "
                 "training/.venv/bin/python scripts/check_content.py --languagetool")
    lt = ltp.LanguageTool("de-DE")
    try:
        for corpus, sentences in german_sentences().items():
            for s in sentences:
                # same predicate as training/scripts/validate_data.py:384
                m = [x for x in lt.check(s)
                     if "umgangssprachlich" not in x.message
                     and not x.rule_id.startswith("EMPFOHLENE_")]
                if m:
                    f.add(corpus, f"lt:{m[0].rule_id}", s[:60], m[0].message[:90])
    finally:
        lt.close()


# ------------------------------------------------------------------ baseline

def load_baseline() -> Counter:
    if not BASELINE.exists():
        return Counter()
    raw = json.loads(BASELINE.read_text(encoding="utf-8"))
    return Counter({(c, r): n for c, rules in raw.items() for r, n in rules.items()})


def write_baseline(counts: Counter, with_languagetool: bool) -> None:
    """Axis 1 and axis 2 are baselined independently, because axis 2 needs training/.venv and
    most runs will not have it. A plain `--write-baseline` keeps whatever `lt:` rows are already
    recorded instead of silently dropping them."""
    merged = Counter(counts)
    if not with_languagetool:
        for key, n in load_baseline().items():
            if key[1].startswith("lt:"):
                merged[key] = n
    out: dict[str, dict[str, int]] = defaultdict(dict)
    for (corpus, rule), n in sorted(merged.items()):
        out[corpus][rule] = n
    BASELINE.write_text(json.dumps(out, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--languagetool", action="store_true", help="also run axis 2 (needs training/.venv)")
    ap.add_argument("--report", action="store_true", help="print the table and exit 0")
    ap.add_argument("--write-baseline", action="store_true")
    ap.add_argument("--show", metavar="RULE", help="print every finding for one rule")
    args = ap.parse_args()

    f = Findings()
    lex = Lexicon()
    for check in CHECKS:
        check(f, lex)
    if args.languagetool:
        run_languagetool(f)

    counts = f.by_corpus_rule()

    if args.show:
        for corpus, rule, item, detail in f.rows:
            if args.show in rule:
                print(f"{corpus}  {rule}  {item}: {detail}")
        return 0

    if args.write_baseline:
        write_baseline(counts, args.languagetool)
        print(f"baseline written: {sum(counts.values())} accepted findings "
              f"across {len({c for c, _ in counts})} corpora -> {BASELINE.relative_to(REPO)}")
        return 0

    width = max((len(c) for c, _ in counts), default=20) + 2
    by_corpus: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for (corpus, rule), n in counts.items():
        by_corpus[corpus].append((rule, n))
    for corpus in sorted(by_corpus):
        rules = sorted(by_corpus[corpus], key=lambda kv: -kv[1])
        total = sum(n for _, n in rules)
        print(f"{corpus:<{width}} {total:>5}  " + ", ".join(f"{r}×{n}" for r, n in rules[:4]))
    print(f"\n{sum(counts.values())} findings in {len(by_corpus)} corpora")

    if args.report:
        return 0

    baseline = load_baseline()
    if not args.languagetool:
        baseline = Counter({k: n for k, n in baseline.items() if not k[1].startswith("lt:")})
    regressions = {k: n for k, n in counts.items() if n > baseline.get(k, 0)}
    if regressions:
        print("\nNEW since the baseline:", file=sys.stderr)
        for (corpus, rule), n in sorted(regressions.items()):
            print(f"  {corpus}  {rule}: {n} (baseline {baseline.get((corpus, rule), 0)})",
                  file=sys.stderr)
        print("\nFix them, or re-baseline with --write-baseline.", file=sys.stderr)
        return 1
    print("\nno regressions against the baseline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
