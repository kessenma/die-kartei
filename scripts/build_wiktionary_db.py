#!/usr/bin/env python3
"""
Converts a Kaikki Wiktionary German JSONL dump into a compact SQLite database
for use as a flashcard validation dictionary.

Usage:
    python3 build_wiktionary_db.py \
        --input /path/to/kaikki.org-dictionary-German.jsonl \
        --output /path/to/wiktionary_de.db
"""

import argparse
import json
import re
import sqlite3
import sys
from typing import Optional

# POS types we care about for flashcard validation
VALID_POS = {"noun", "verb", "adj", "adv"}

# Regex to extract gender from head_templates expansion
# Matches patterns like "Haus n (strong, ...)" or "Katze f (weak, ...)"
GENDER_RE = re.compile(r"(?:^|\s)([mfn])\s")


def extract_gender(entry: dict) -> Optional[str]:
    """Extract grammatical gender from a noun entry."""
    for ht in entry.get("head_templates", []):
        expansion = ht.get("expansion", "")
        match = GENDER_RE.search(expansion)
        if match:
            return match.group(1)

    # Fallback: check sense tags
    for sense in entry.get("senses", []):
        tags = sense.get("tags", [])
        for tag in tags:
            if tag == "masculine":
                return "m"
            elif tag == "feminine":
                return "f"
            elif tag == "neuter":
                return "n"

    return None


def extract_translation(entry: dict) -> Optional[str]:
    """Extract the primary English translation from senses."""
    for sense in entry.get("senses", []):
        glosses = sense.get("glosses", [])
        if glosses:
            gloss = glosses[0]
            # Skip meta-glosses like "inflection of X:" or "Alternative form of X"
            if gloss.startswith("inflection of ") or gloss.startswith("Alternative"):
                continue
            return gloss
    # If all senses were skipped, return the first one anyway
    for sense in entry.get("senses", []):
        glosses = sense.get("glosses", [])
        if glosses:
            return glosses[0]
    return None


def build_database(input_path: str, output_path: str) -> None:
    conn = sqlite3.connect(output_path)
    cur = conn.cursor()

    cur.execute("PRAGMA journal_mode=DELETE")
    cur.execute("PRAGMA synchronous=OFF")

    cur.execute("""
        CREATE TABLE IF NOT EXISTS words (
            id INTEGER PRIMARY KEY,
            word TEXT NOT NULL,
            word_lower TEXT NOT NULL,
            pos TEXT NOT NULL,
            gender TEXT,
            translation TEXT
        )
    """)

    inserted = 0
    skipped = 0
    errors = 0

    with open(input_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                errors += 1
                continue

            # Only process German entries
            if entry.get("lang_code") != "de":
                skipped += 1
                continue

            pos = entry.get("pos", "")
            if pos not in VALID_POS:
                skipped += 1
                continue

            word = entry.get("word", "").strip()
            if not word:
                skipped += 1
                continue

            gender = extract_gender(entry) if pos == "noun" else None
            translation = extract_translation(entry)

            cur.execute(
                "INSERT INTO words (word, word_lower, pos, gender, translation) VALUES (?, ?, ?, ?, ?)",
                (word, word.lower(), pos, gender, translation),
            )
            inserted += 1

            if line_num % 50000 == 0:
                conn.commit()
                print(f"  Processed {line_num:,} lines, inserted {inserted:,}...")

    conn.commit()

    print(f"\nCreating indexes...")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_word_lower ON words(word_lower)")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_word_lower_pos ON words(word_lower, pos)")

    print("Running VACUUM and ANALYZE...")
    cur.execute("VACUUM")
    cur.execute("ANALYZE")

    conn.commit()
    conn.close()

    print(f"\nDone!")
    print(f"  Inserted: {inserted:,}")
    print(f"  Skipped:  {skipped:,}")
    print(f"  Errors:   {errors:,}")
    print(f"  Output:   {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Build Wiktionary SQLite database for German flashcard validation")
    parser.add_argument("--input", required=True, help="Path to kaikki.org-dictionary-German.jsonl")
    parser.add_argument("--output", required=True, help="Path to output SQLite database")
    args = parser.parse_args()

    print(f"Building dictionary database...")
    print(f"  Input:  {args.input}")
    print(f"  Output: {args.output}")
    print()

    build_database(args.input, args.output)


if __name__ == "__main__":
    main()
