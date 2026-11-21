#!/usr/bin/env python3
"""Strip PDF-extraction debris out of the Goethe vocabulary example sentences.

The A2 list's `example` field was scraped from the Goethe Wortliste PDFs and carries the
wreckage: a Perfekt form that belongs in a different column prepended to the sentence
("hat abgeholt Wir müssen noch meinen Bruder abholen."), a stray "(pl.)" or "(sich),",
bare fragments ("ich Zeit.", "anderen.") and page furniture ("9WORTLISTE").

These are not German errors, so no amount of grammar checking finds them. The rule here is
to ship honest emptiness rather than visible garbage: a sentence is repaired when the damage
is a removable prefix, and dropped otherwise. B1 is already empty, which is the target state.

    python3 scripts/clean_vocab_examples.py --dry-run
    python3 scripts/clean_vocab_examples.py
"""
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
RES = REPO / "german-ai-flashcards/Resources"

#: "hat abgeholt Wir müssen ..." / "ist gefahren Er ist ..." -- a column from the PDF table
#: glued onto the front of the example. Only strip when a real sentence follows.
PARTICIPLE_PREFIX = re.compile(r"^(?:hat|ist)\s+[a-zäöüß]+\s+(?=[A-ZÄÖÜ])")
#: "(pl.) Meine Eltern ..." / "(sich), Ich möchte ..." -- a grammar marker from the headword.
MARKER_PREFIX = re.compile(r"^\((?:pl\.|sich)\)(?:\s*\([^)]*\))?,?\s+")
#: "9WORTLISTE", "14 WORTLISTE" -- running heads from the PDF.
PAGE_FURNITURE = re.compile(r"^\d*\s*WORTLISTE\b", re.I)
#: The rest of the headword, glued on in front of the sentence: "an" is listed as "an sein",
#: "Rad" as "Rad fahren", "der" as "der, die, das". Strip the lowercase run up to the first
#: capitalised word -- but only when what remains is a real sentence (MIN_WORDS), so
#: "aber: ich Zeit." stays a fragment and gets dropped instead of becoming "Zeit.".
HEADWORD_TAIL = re.compile(r"^[a-zäöüß][^.!?]*?\s(?=[A-ZÄÖÜ])")
MIN_WORDS = 4
#: The *next* entry spliced into the middle: the headword's own example, then that headword's
#: successor and its example, all in one string. "Fahren Sie ins Ausland? ausländisch Leider habe
#: ich nur ausländisches Geld." Keep what belongs to this entry, drop the rest.
NEXT_ENTRY = re.compile(
    r"(?<=[.!?])\s+(?:[–-]\s*)?[a-zäöüß][A-Za-zÄÖÜäöüß/()-]*(?:\s+(?:sein|haben))?\s+(?=[A-ZÄÖÜ])"
    # ... or the successor arrives wearing the list's bracket notation: "mittel (pl.) Lebensmittel
    # ...", "(Kredit)-Karte, -n Kann ich ...", "Damen (an der Toilette) Sehr geehrte ..."
    r"|(?<=[.!?])\s+[A-Za-zÄÖÜäöüß()/-]+(?:\s*,\s*[-–][A-Za-zÄÖÜäöüß]*)?\s*\([^)]*\)[-–]?[A-Za-zÄÖÜäöüß]*(?:\s*,\s*[-–][A-Za-zÄÖÜäöüß]*)?\s+(?=[A-ZÄÖÜ])")

#: A bracketed form list parked in front of the example: "(an-)/(aus)ziehen, Ich ziehe ...",
#: "(fahren, geben, Wann muss ich ...". Strip up to where the sentence actually starts.
PAREN_FORMS = re.compile(r"^\([A-Za-zÄÖÜäöüß\-,/()\s]*?(?:,|\))\s*(?=[A-ZÄÖÜ])")
#: An inflection marker parked in front: "Bekannte, -n Ein Bekannter ...", "-ä, e Dieser Satz ...".
INFLECTION_LEAD = re.compile(
    r"^(?:\(?[A-Za-zÄÖÜäöüß()/-]+\)?[-–]?\s*,\s*)?[-–][A-Za-zÄÖÜäöüß]+\s*,?\s*[a-zäöüß]?\s*(?=[A-ZÄÖÜ])"
    r"|^[A-ZÄÖÜ][A-Za-zÄÖÜäöüß()/-]*\s*,\s*[-–][A-Za-zÄÖÜäöüß]*\s+(?=[A-ZÄÖÜ])")
#: Entries whose successor is spliced in after a comma rather than a sentence end. A comma rule
#: would fire on half the corpus, and the salvageable part ("Liebe Susanne, lieber Hans,") is a
#: fragment, so this ships empty rather than inventing punctuation.
DROP_EXACT = {
    "Liebe Susanne, lieber Hans, lieben Ich liebe dich! lieber Sie fährt lieber mit der Bahn.",
    # a fragment with a stray space, not a sentence
    "Morgen schwimmen .",
}

#: Outright errors in the shipped strings, each verified against LanguageTool. Exact-match only,
#: so a rule can never fire on a sentence it was not written for.
TYPOS = {
    "WiIlst du diese Jacke? – Nein, ich möchte die andere.":
        "Willst du diese Jacke? – Nein, ich möchte die andere.",
    "Zur dieser Hochzeit kommen mehr als fünfzig Gäste.":
        "Zu dieser Hochzeit kommen mehr als fünfzig Gäste.",
    "Heute abend gehen wir in die Disco tanzen.":
        "Heute Abend gehen wir in die Disco tanzen.",
    "Sie bekommt viele Anrufe auf ihrem Handy. beantworter den Anrufbeantworter.":
        "Sie bekommt viele Anrufe auf ihrem Handy.",
    # the list's own gloss, in front of the example
    "Damen (an der Toilette) Sehr geehrte Damen und Herren!":
        "Sehr geehrte Damen und Herren!",
    # the next entry arrives as "(Kredit)-Karte, -n", a bracket straight after the sentence end
    "Ich schreibe meinen Bekannten eine Karte aus dem Urlaub. Wollen wir Karten spielen? "
    "Ich möchte auch etwas essen. Bringen Sie mir die Karte, bitte. (Kredit)-Karte, -n "
    "Kann ich auch mit Karte (be-) zahlen?":
        "Ich schreibe meinen Bekannten eine Karte aus dem Urlaub. Wollen wir Karten spielen? "
        "Bringen Sie mir die Karte, bitte.",
}


def repair(text: str) -> tuple[str | None, str]:
    """Returns (cleaned sentence or None, reason)."""
    s = (text or "").strip()
    if not s:
        return None, "empty"
    if PAGE_FURNITURE.match(s):
        return None, "dropped:page-furniture"
    if s in DROP_EXACT:
        return None, "dropped:unrepairable"
    if s in TYPOS:
        return TYPOS[s], "repaired:typo"
    before = s
    # ‘ is a quotation mark; German uses ’ as the apostrophe ("geht’s", not "geht‘s").
    s = s.replace("\u2018", "\u2019")
    s = PARTICIPLE_PREFIX.sub("", s, count=1)
    s = MARKER_PREFIX.sub("", s, count=1)
    s = INFLECTION_LEAD.sub("", s, count=1)
    s = PAREN_FORMS.sub("", s, count=1)
    # keep only this entry's own sentences
    cut = NEXT_ENTRY.search(s)
    if cut:
        s = s[:cut.start()].strip()
    if s[:1].islower():
        candidate = HEADWORD_TAIL.sub("", s, count=1).strip()
        if len(candidate.split()) >= MIN_WORDS and candidate.endswith((".", "!", "?")):
            s = candidate
    s = s.strip()
    repaired = s != before
    if not s or s[:1].islower():
        return None, "dropped:fragment"
    if not s.endswith((".", "!", "?")):
        return None, "dropped:truncated"
    return s, ("repaired:prefix-stripped" if repaired else "kept")


def run(level: str, dry_run: bool) -> Counter:
    path = RES / f"{level}_vocabulary.json"
    rows = json.loads(path.read_text(encoding="utf-8"))
    stats: Counter = Counter()
    samples: dict[str, list[str]] = {}
    for r in rows:
        if not (r.get("example") or "").strip():
            stats["already-empty"] += 1
            continue
        cleaned, reason = repair(r["example"])
        stats[reason] += 1
        if reason != "kept":
            samples.setdefault(reason, []).append(f'{r["word"]}: {r["example"][:58]!r}')
        if reason != "kept":
            r["example"] = cleaned if cleaned else ""
    if not dry_run:
        path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\n{level}_vocabulary.json  ({len(rows)} rows)")
    for reason, n in sorted(stats.items(), key=lambda kv: -kv[1]):
        print(f"   {reason:<28}{n:>5}")
        for ex in samples.get(reason, [])[:3]:
            print(f"      {ex}")
    return stats


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--levels", nargs="*", default=["a1", "a2"])
    args = ap.parse_args()
    for level in args.levels:
        run(level, args.dry_run)
    if args.dry_run:
        print("\n(dry run -- nothing written)")


if __name__ == "__main__":
    main()
