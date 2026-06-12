#!/usr/bin/env python3
"""
Validates Goethe vocabulary JSON translations against DeepL.

Batches German words through the DeepL API and flags entries where the stored
translation has no word overlap with DeepL's suggestion — indicating a likely
error (like "ich" → "ego" instead of "I").

Results are cached in .translation_cache.json so re-runs don't consume quota.

Usage:
    python3 validate_translations.py --api-key YOUR_KEY
    python3 validate_translations.py --api-key YOUR_KEY --level a1
    python3 validate_translations.py --api-key YOUR_KEY --no-cache
"""

import argparse
import json
import re
import sys
import time
import urllib.request
import urllib.parse
from pathlib import Path

VOCAB_DIR = Path(__file__).parent.parent / "german-ai-flashcards" / "Resources"
CACHE_FILE = Path(__file__).parent / ".translation_cache.json"
DEEPL_URL = "https://api-free.deepl.com/v2/translate"
BATCH_SIZE = 50  # DeepL max per request

LEVELS = ["a1", "a2", "b1"]

# Words that are inherently ambiguous or multi-sense — skip strict checking
SKIP_WORDS = {"sein", "haben", "werden", "können", "dürfen", "mögen", "müssen", "sollen", "wollen"}


def load_vocab(level: str) -> list[dict]:
    path = VOCAB_DIR / f"{level}_vocabulary.json"
    with open(path) as f:
        return json.load(f)


def load_cache() -> dict:
    if CACHE_FILE.exists():
        with open(CACHE_FILE) as f:
            return json.load(f)
    return {}


def save_cache(cache: dict) -> None:
    with open(CACHE_FILE, "w") as f:
        json.dump(cache, f, ensure_ascii=False, indent=2)


def deepl_translate(words: list, contexts: list, api_key: str) -> list:
    """Translate a batch of German words to English via DeepL."""
    data = urllib.parse.urlencode(
        [("source_lang", "DE"), ("target_lang", "EN-US")]
        + [("text", w) for w in words],
        encoding="utf-8",
    ).encode()
    req = urllib.request.Request(DEEPL_URL, data=data, method="POST")
    req.add_header("Authorization", f"DeepL-Auth-Key {api_key}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            return [t["text"] for t in result["translations"]]
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        raise RuntimeError(f"DeepL HTTP {e.code}: {body}") from e


def normalize(text: str) -> set[str]:
    """Lowercase words, strip punctuation, split on whitespace and commas."""
    text = text.lower()
    text = re.sub(r"[^\w\s]", " ", text)
    return {w for w in text.split() if len(w) > 1}


def translations_overlap(stored: str, deepl: str) -> bool:
    """Return True if the two translations share at least one meaningful word."""
    s, d = normalize(stored), normalize(deepl)
    # Common filler words that don't indicate a match
    fillers = {"to", "a", "an", "the", "be", "is", "are", "of", "in", "on", "at", "it"}
    s -= fillers
    d -= fillers
    return bool(s & d)


def validate_level(level: str, api_key: str, cache: dict, use_cache: bool) -> list[dict]:
    entries = load_vocab(level)
    suspects = []
    to_fetch: list[tuple[int, dict]] = []  # (index, entry) pairs needing DeepL

    # Separate cached from uncached
    for i, entry in enumerate(entries):
        word = entry["word"]
        if not entry.get("translation"):
            continue
        if use_cache and word in cache:
            continue
        to_fetch.append((i, entry))

    # Batch API calls
    if to_fetch:
        print(f"  Fetching {len(to_fetch)} translations from DeepL for {level.upper()}...", flush=True)
        for batch_start in range(0, len(to_fetch), BATCH_SIZE):
            batch = to_fetch[batch_start: batch_start + BATCH_SIZE]
            words = [e["word"] for _, e in batch]
            contexts = [e.get("example") for _, e in batch]
            try:
                results = deepl_translate(words, contexts, api_key)
            except RuntimeError as e:
                print(f"  ERROR: {e}", file=sys.stderr)
                sys.exit(1)
            for (_, entry), deepl_text in zip(batch, results):
                cache[entry["word"]] = deepl_text
            if batch_start + BATCH_SIZE < len(to_fetch):
                time.sleep(1.5)  # stay well under DeepL free-tier rate limit
        save_cache(cache)
    else:
        print(f"  All {len(entries)} {level.upper()} entries loaded from cache.")

    # Compare
    for entry in entries:
        word = entry["word"]
        stored = entry.get("translation", "")
        if not stored or word in SKIP_WORDS:
            continue
        deepl_text = cache.get(word)
        if not deepl_text:
            continue
        if not translations_overlap(stored, deepl_text):
            suspects.append({
                "level": level.upper(),
                "word": word,
                "article": entry.get("article"),
                "wordType": entry.get("wordType"),
                "stored_translation": stored,
                "deepl_translation": deepl_text,
                "example": entry.get("example"),
            })

    return suspects


def print_report(suspects: list[dict]) -> None:
    if not suspects:
        print("\n✓ No translation mismatches found.")
        return

    print(f"\nFound {len(suspects)} suspect translation(s):\n")
    by_level: dict[str, list] = {}
    for s in suspects:
        by_level.setdefault(s["level"], []).append(s)

    for level, items in sorted(by_level.items()):
        print(f"── {level} ({len(items)} issues) " + "─" * 40)
        for s in items:
            word = f"{s['article']} {s['word']}" if s.get("article") else s["word"]
            print(f"  {word:<30} stored: {s['stored_translation']!r:<30}  deepl: {s['deepl_translation']!r}")
            if s.get("example"):
                print(f"  {'':30}  example: {s['example']}")
            print()


def main():
    parser = argparse.ArgumentParser(description="Validate Goethe vocab translations via DeepL")
    parser.add_argument("--api-key", required=True, help="DeepL API key")
    parser.add_argument("--level", choices=LEVELS, help="Validate one level only (default: all)")
    parser.add_argument("--no-cache", action="store_true", help="Ignore cached results and re-fetch all")
    args = parser.parse_args()

    levels = [args.level] if args.level else LEVELS
    cache = {} if args.no_cache else load_cache()

    all_suspects = []
    for level in levels:
        print(f"\nValidating {level.upper()}...")
        suspects = validate_level(level, args.api_key, cache, use_cache=not args.no_cache)
        print(f"  {len(suspects)} suspect(s) found in {level.upper()}")
        all_suspects.extend(suspects)

    print_report(all_suspects)

    if all_suspects:
        out_path = Path(__file__).parent / "translation_issues.json"
        with open(out_path, "w") as f:
            json.dump(all_suspects, f, ensure_ascii=False, indent=2)
        print(f"Full report saved to: {out_path}")


if __name__ == "__main__":
    main()
