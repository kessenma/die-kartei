#!/usr/bin/env python3
"""Fetch German verb inventories from de.wiktionary category listings.

Downloads all page titles in:
  - Kategorie:Verb trennbar (Deutsch)   -> data/raw/separable_verbs.json
  - Kategorie:Verb reflexiv (Deutsch)   -> data/raw/reflexive_verbs.json

Content is CC-BY-SA 3.0 (de.wiktionary.org). Only stdlib is used.
"""

import json
import time
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

API = "https://de.wiktionary.org/w/api.php"
HEADERS = {
    # Wikimedia API etiquette: identify the client.
    "User-Agent": "german-ai-flashcards-training/0.1 (personal language-learning project)"
}

CATEGORIES = {
    "separable_verbs": "Kategorie:Verb trennbar (Deutsch)",
    "reflexive_verbs": "Kategorie:Verb reflexiv (Deutsch)",
}

OUT_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"


def api_get(params: dict) -> dict:
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=HEADERS)
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code in (429, 503) and attempt < 5:
                wait = int(e.headers.get("Retry-After") or 0) or 10 * (attempt + 1)
                print(f"  rate-limited ({e.code}), waiting {wait}s ...")
                time.sleep(wait)
            else:
                raise
    raise RuntimeError("unreachable")


def fetch_category_members(category: str) -> list[str]:
    members: list[str] = []
    cmcontinue = None
    while True:
        params = {
            "action": "query",
            "list": "categorymembers",
            "cmtitle": category,
            "cmlimit": "500",
            "cmnamespace": "0",  # main namespace only (skip sub-categories, templates)
            "format": "json",
        }
        if cmcontinue:
            params["cmcontinue"] = cmcontinue
        data = api_get(params)
        batch = [m["title"] for m in data["query"]["categorymembers"]]
        members.extend(batch)
        print(f"  {category}: {len(members)} so far")
        cont = data.get("continue", {})
        cmcontinue = cont.get("cmcontinue")
        if not cmcontinue:
            break
        time.sleep(3)
    return members


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, category in CATEGORIES.items():
        print(f"Fetching {category} ...")
        verbs = fetch_category_members(category)
        out = {
            "source": f"https://de.wiktionary.org/wiki/{urllib.parse.quote(category.replace(' ', '_'))}",
            "license": "CC-BY-SA 3.0 (de.wiktionary.org contributors)",
            "fetched": date.today().isoformat(),
            "category": category,
            "count": len(verbs),
            "verbs": sorted(verbs),
        }
        path = OUT_DIR / f"{name}.json"
        path.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"  wrote {path} ({len(verbs)} verbs)")


if __name__ == "__main__":
    main()
