#!/usr/bin/env python3
"""Merge plural and verb forms from Wortkiste into the bundled Goethe word lists.

Wortkiste (https://github.com/matchaDataHub/wortkiste, MIT) ships ~550 curated A1–B1 words with
plural endings for nouns ("-en", "¨-e", "-") and present/Perfekt forms for verbs
("meldet sich an · hat sich angemeldet"). Our JSON lists lack both. This script copies those two
fields onto every level entry whose headword matches, and touches nothing else.

    python3 scripts/merge_wortkiste_forms.py --check   # report matches, write nothing
    python3 scripts/merge_wortkiste_forms.py           # write plural / verbForms keys

Idempotent: re-running rewrites the same values. Existing keys are never changed or removed.
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JSX = ROOT / "examples" / "wortkiste" / "wortkiste.jsx"
RESOURCES = ROOT / "german-ai-flashcards" / "Resources"
LEVELS = ["a1", "a2", "b1"]


def parse_vocab(text: str) -> list[dict]:
    """Pull the `VOCAB` array's objects out of the JSX source without a JS parser."""
    start = text.index("const VOCAB = [")
    end = text.index("];", start)
    block = text[start:end]
    rows = []
    for match in re.finditer(r"\{d:\"([^\"]*)\"(.*?)\}", block):
        d, rest = match.group(1), match.group(2)

        def field(key: str):
            m = re.search(r"\b" + key + r":\"([^\"]*)\"", rest)
            return m.group(1) if m else None

        rows.append({"d": d, "a": field("a"), "p": field("p"), "f": field("f"), "t": field("t")})
    return rows


def headword(d: str) -> str:
    """`sich bewerben um + A` → `bewerben`; `Hemd (das)` → `Hemd`."""
    d = re.sub(r"\s*\(.*?\)", "", d)
    d = re.sub(r"\s*\+.*$", "", d)
    d = re.sub(r"^sich\s+", "", d)
    return d.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="report only, write nothing")
    args = parser.parse_args()

    rows = parse_vocab(JSX.read_text(encoding="utf-8"))
    forms: dict[str, dict] = {}
    for row in rows:
        key = headword(row["d"])
        entry = forms.setdefault(key, {})
        if row["t"] == "n" and row["p"]:
            entry.setdefault("plural", row["p"])
        if row["t"] == "v" and row["f"]:
            entry.setdefault("verbForms", row["f"])
    forms = {k: v for k, v in forms.items() if v}

    matched_words: set[str] = set()
    written = {"plural": 0, "verbForms": 0}
    for level in LEVELS:
        path = RESOURCES / f"{level}_vocabulary.json"
        original = path.read_text(encoding="utf-8")
        entries = json.loads(original)
        changed = False
        for entry in entries:
            extra = forms.get(entry["word"])
            if not extra:
                continue
            matched_words.add(entry["word"])
            for key, value in extra.items():
                if entry.get(key) != value:
                    entry[key] = value
                    written[key] += 1
                    changed = True
        if changed and not args.check:
            path.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"{level}: {len(entries)} entries, {sum(1 for e in entries if forms.get(e['word']))} with Wortkiste forms")

    unmatched = sorted(k for k in forms if k not in matched_words)
    print(f"Wortkiste words with forms: {len(forms)} · matched headwords: {len(matched_words)} · unmatched: {len(unmatched)}")
    print(f"{'would write' if args.check else 'wrote'}: plural {written['plural']} · verbForms {written['verbForms']}")
    if unmatched:
        print("unmatched sample:", ", ".join(unmatched[:12]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
