#!/usr/bin/env python3
"""
Repairs truncated translations in the bundled Goethe vocabulary lists.

The lists were generated with hard character caps (60 for the B1 list, various
for A1/A2), which cut glosses mid-word and left parentheticals unclosed —
"to use, apply, utilize or deploy (to put to use for a purpos". Those strings
render verbatim in the placement quiz and anywhere else a translation shows.

Two-step repair, in place:
  1. Restore: if the truncated string is a prefix of a fuller gloss for the
     same word in the bundled wiktionary_de.db, adopt the DB gloss. (The DB
     itself caps at 80 chars, so a restored gloss can still be truncated.)
  2. Trim: whatever is still ragged gets cut back to a clean boundary —
     a dangling "(..." fragment is dropped at the unbalanced paren, a stray
     ")" without an opener is removed, and a mid-word cap cut is trimmed to
     the last comma (or space) so the gloss ends on a complete word.

Run from the repo root:
    python3 scripts/repair_vocab_translations.py
"""

import json
import re
import sqlite3
from pathlib import Path

RESOURCES = Path(__file__).resolve().parent.parent / "german-ai-flashcards" / "Resources"
LISTS = ["a1_vocabulary.json", "a2_vocabulary.json", "b1_vocabulary.json"]
DB = RESOURCES / "wiktionary_de.db"

# Known generation caps: the B1 list was cut at 60, the DB glosses at 80.
# A string at a cap is assumed truncated unless it ends at a natural boundary.
CAPS = {60, 80}


def unbalanced_open(text: str) -> int:
    """Index of the '(' that never closes, or -1 if parens are balanced."""
    depth = 0
    open_at = -1
    for i, ch in enumerate(text):
        if ch == "(":
            if depth == 0:
                open_at = i
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
            if depth == 0:
                open_at = -1
    return open_at if depth > 0 else -1


def has_stray_close(text: str) -> bool:
    depth = 0
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            if depth == 0:
                return True
            depth -= 1
    return False


def ends_complete(text: str) -> bool:
    """A cap-length gloss that closes on punctuation was cut exactly at its own
    end — a truncation landing on a perfect close is vanishingly unlikely."""
    return bool(re.search(r'[)\].!?”"’\']$', text))


def looks_truncated(text: str) -> bool:
    if text.count("(") != text.count(")"):
        return True
    if len(text) in CAPS and not ends_complete(text):
        return True
    return False


def last_boundary_outside_parens(text: str) -> int:
    """Position of the last comma at paren depth 0 — a gloss-list boundary —
    falling back to the last depth-0 space. Never points inside a group."""
    last_comma = last_space = -1
    depth = 0
    for i, ch in enumerate(text):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        elif depth == 0:
            if ch == ",":
                last_comma = i
            elif ch == " ":
                last_space = i
    return last_comma if last_comma > 0 else last_space


def trim_clean(text: str) -> str:
    """Cut a truncated gloss back to a clean boundary."""
    t = text
    # Stray ')' with no opener: just delete it.
    while has_stray_close(t):
        depth = 0
        for i, ch in enumerate(t):
            if ch == "(":
                depth += 1
            elif ch == ")":
                if depth == 0:
                    t = t[:i] + t[i + 1 :]
                    break
                depth -= 1
    # Dangling '(...' fragment: drop from the unclosed paren.
    open_at = unbalanced_open(t)
    if open_at >= 0:
        t = t[:open_at]
        t = t.rstrip(" ,;:-–—")
    # A cap-length string that survived paren repair still ends mid-word:
    # back up to the last gloss boundary outside any paren group.
    elif len(text) in CAPS:
        cut = last_boundary_outside_parens(t)
        if cut > 0:
            t = t[:cut]
        t = t.rstrip(" ,;:-–—")
        # The boundary cut can leave a group open ("..., (gathering among" →
        # cut may still sit past an opener); close the loop if so.
        open_at = unbalanced_open(t)
        if open_at >= 0:
            t = t[:open_at].rstrip(" ,;:-–—")
    else:
        t = t.rstrip(" ,;:-–—")
    return t


def main() -> None:
    conn = sqlite3.connect(DB)
    cur = conn.cursor()

    def db_glosses(word: str) -> list[str]:
        rows = cur.execute(
            "SELECT translation FROM words WHERE word = ? AND translation IS NOT NULL",
            (word,),
        )
        return [r[0] for r in rows]

    for name in LISTS:
        path = RESOURCES / name
        entries = json.loads(path.read_text(encoding="utf-8"))
        restored = trimmed = 0

        for entry in entries:
            gloss = entry.get("translation") or ""
            if not looks_truncated(gloss):
                # Still normalize stray trailing separators on intact glosses.
                if gloss != gloss.rstrip(" ,;"):
                    entry["translation"] = gloss.rstrip(" ,;")
                    trimmed += 1
                continue

            # Step 1: restore a fuller gloss from the DB by prefix match.
            stem = gloss.rstrip()[:40].lower()
            candidate = next(
                (g for g in db_glosses(entry["word"]) if g.lower().startswith(stem) and len(g) > len(gloss)),
                None,
            )
            if candidate:
                gloss = candidate
                restored += 1

            # Step 2: trim whatever is still ragged.
            if looks_truncated(gloss):
                gloss = trim_clean(gloss)
                trimmed += 1

            # DB glosses occasionally carry their own trailing comma; drop it.
            entry["translation"] = gloss.rstrip(" ,;")

        path.write_text(
            json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"{name}: restored {restored} from DB, trimmed {trimmed}")

    # Verify: nothing left with unbalanced parens or a cap-length mid-word cut.
    bad = 0
    for name in LISTS:
        for entry in json.loads((RESOURCES / name).read_text(encoding="utf-8")):
            t = entry.get("translation") or ""
            if t.count("(") != t.count(")"):
                print(f"  STILL UNBALANCED [{name}] {entry['word']}: {t!r}")
                bad += 1
    print("verify:", "clean" if bad == 0 else f"{bad} entries still broken")


if __name__ == "__main__":
    main()
