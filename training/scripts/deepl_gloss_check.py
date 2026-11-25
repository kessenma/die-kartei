#!/usr/bin/env python3
"""Cross-check the English glosses in verb_praep_table.json against DeepL.

For each entry, builds a dictionary-style German probe phrase (infinitive phrase,
e.g. "sich auf etwas freuen"), translates it DE->EN with DeepL, and flags entries
whose translation shares no content word with the table gloss. Flags mean
"human, look at this" — not "wrong".

Needs DEEPL key in training/.env (accepts `deepL=` or `DEEPL_API_KEY=`).
Writes results/deepl_gloss_check.json and prints flagged entries.
"""

import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "data" / "verb_praep_table.json"
OUT = ROOT / "results" / "deepl_gloss_check.json"
API = "https://api-free.deepl.com/v2"

# Entries whose generic infinitive probe would be unidiomatic (impersonal es-verbs etc.)
SPECIAL_PROBES = {
    ("ankommen", "auf"): "Es kommt auf etwas an.",
    ("gehen", "um"): "Es geht um etwas.",
    ("sich handeln", "um"): "Es handelt sich um etwas.",
    ("sich drehen", "um"): "Es dreht sich um etwas.",
    ("liegen", "an"): "Es liegt an etwas.",
    ("mangeln", "an"): "Es mangelt an etwas.",
    ("fehlen", "an"): "Es fehlt an etwas.",
    ("aussehen", "nach"): "Es sieht nach Regen aus.",
    ("halten", "von"): "Was hältst du von der Idee?",
    ("halten", "für"): "jemanden für klug halten",
    ("verstehen", "unter"): "Was verstehst du unter diesem Begriff?",
    ("sich vorstellen", "unter"): "Ich kann mir unter diesem Begriff nichts vorstellen.",
    ("werden", "aus"): "Was ist aus dem Plan geworden?",
}

STOPWORDS = {"to", "be", "being", "a", "an", "the", "something", "someone", "somebody",
             "sth", "sb", "oneself", "one", "ones", "one's", "s", "in", "on"}


def load_key() -> str:
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            if k.strip().lower() in ("deepl", "deepl_api_key"):
                return v.strip()
    raise SystemExit("no DeepL key found in training/.env")


def probe(entry: dict) -> str:
    special = SPECIAL_PROBES.get((entry["verb"], entry["prep"]))
    if special:
        return special
    refl = entry["verb"].startswith("sich ")
    bare = entry["verb"].removeprefix("sich ")
    if entry["da"]:
        pronoun = "etwas"
    else:
        pronoun = "jemanden" if entry["case"] == "Akk" else "jemandem"
    return ("sich " if refl else "") + f"{entry['prep']} {pronoun} {bare}"


def deepl_post(path: str, payload: dict, key: str) -> dict:
    req = urllib.request.Request(
        f"{API}{path}",
        data=json.dumps(payload).encode() if payload else None,
        headers={"Authorization": f"DeepL-Auth-Key {key}", "Content-Type": "application/json"},
        method="POST" if payload else "GET",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def content_words(text: str) -> set:
    text = re.sub(r"\([^)]*\)", " ", text.lower())  # drop parentheticals
    return {w for w in re.findall(r"[a-z']+", text) if w not in STOPWORDS}


def main() -> None:
    key = load_key()
    usage = deepl_post("/usage", None, key)
    print(f"DeepL usage before: {usage['character_count']:,}/{usage['character_limit']:,} chars")

    entries = json.loads(TABLE.read_text())["entries"]
    probes = [probe(e) for e in entries]
    print(f"{len(entries)} probes, ~{sum(len(p) for p in probes):,} chars")

    translations = []
    for i in range(0, len(probes), 50):
        batch = probes[i:i + 50]
        data = deepl_post("/translate", {"text": batch, "source_lang": "DE", "target_lang": "EN-US"}, key)
        translations.extend(t["text"] for t in data["translations"])
        print(f"  translated {len(translations)}/{len(probes)}")

    results = []
    for entry, p, trans in zip(entries, probes, translations):
        overlap = content_words(entry["english"]) & content_words(trans)
        results.append({
            "verb": entry["verb"], "prep": entry["prep"], "gloss": entry["english"],
            "probe": p, "deepl": trans, "overlap": sorted(overlap), "flagged": not overlap,
        })

    flagged = [r for r in results if r["flagged"]]
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps({"flagged_count": len(flagged), "results": results},
                              ensure_ascii=False, indent=1), encoding="utf-8")

    print(f"\n{len(flagged)}/{len(results)} entries flagged for review:")
    for r in flagged:
        print(f"  {r['verb']} {r['prep']}: gloss='{r['gloss']}' | deepl='{r['deepl']}' (probe: {r['probe']})")

    usage = deepl_post("/usage", None, key)
    print(f"\nDeepL usage after: {usage['character_count']:,}/{usage['character_limit']:,} chars")
    print(f"full results: {OUT}")


if __name__ == "__main__":
    main()
