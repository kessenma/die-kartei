#!/usr/bin/env python3
"""Mine Tatoeba German sentences for the four target grammar phenomena.

Reads data/raw/deu_sentences.tsv (id<TAB>lang<TAB>text, CC-BY 2.0 FR — attribution:
https://tatoeba.org) and writes per-phenomenon JSONL seed files to data/raw/tatoeba/:

  mined_vmp.jsonl   verb + fixed preposition (matched against verb_praep_table.json)
  mined_sep.jsonl   separable verbs (subtype "separated" = prefix split off [gold],
                    "attached" = infinitive/participle form)
  mined_refl.jsonl  reflexive constructions (sich, or person-agreeing mich/dir/uns/euch)
  mined_dawo.jsonl  da-/wo-compounds (darauf, womit, ...)

Uses spaCy de_core_news_sm for lemmas/deps. Runtime: ~10 min for ~700k sentences.
"""

import json
import re
from collections import Counter
from pathlib import Path

import spacy

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
OUT_DIR = RAW / "tatoeba"

MAX_PER_KEY = 200          # cap examples per (type, key) so common verbs don't dominate
MIN_TOKENS, MAX_TOKENS = 3, 16  # flashcard/conversation-appropriate lengths

PREPS = {"an", "auf", "aus", "bei", "für", "gegen", "in", "mit", "nach", "um",
         "über", "von", "vor", "zu", "unter", "durch", "hinter", "neben", "zwischen"}
DAWO_RE = re.compile(
    r"^(da|dar|wo|wor)(an|auf|aus|bei|durch|für|gegen|hinter|in|mit|nach|neben|über|um|unter|von|vor|zu|zwischen)$"
)
REFL_AGREE = {"mich": "ich", "mir": "ich", "dich": "du", "dir": "du", "uns": "wir", "euch": "ihr"}


def load_resources():
    table = json.loads((ROOT / "data" / "verb_praep_table.json").read_text())["entries"]
    # (bare verb lemma, prep) -> entry
    vmp = {}
    for e in table:
        bare = e["verb"].removeprefix("sich ").lower()
        if " " in bare:  # skip multi-word ("lustig machen")
            continue
        vmp[(bare, e["prep"])] = e
    sep_raw = json.loads((RAW / "separable_verbs.json").read_text())["verbs"]
    separable = {v.lower() for v in sep_raw if " " not in v and re.fullmatch(r"[a-zäöüß]+n", v.lower())}
    refl_raw = json.loads((RAW / "reflexive_verbs.json").read_text())["verbs"]
    reflexive = {v.lower() for v in refl_raw if " " not in v and re.fullmatch(r"[a-zäöüß]+n", v.lower())}
    reflexive |= {e["verb"].removeprefix("sich ").lower() for e in table if e["verb"].startswith("sich ")}
    return vmp, separable, reflexive


def sentences():
    with open(RAW / "deu_sentences.tsv", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            sid, _, text = parts
            n = text.count(" ") + 1
            if MIN_TOKENS <= n <= MAX_TOKENS:
                yield sid, text


def main() -> None:
    vmp_table, separable, reflexive = load_resources()
    print(f"resources: {len(vmp_table)} vmp patterns, {len(separable)} separable, {len(reflexive)} reflexive")

    nlp = spacy.load("de_core_news_sm", disable=["ner"])
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    files = {k: open(OUT_DIR / f"mined_{k}.jsonl", "w", encoding="utf-8") for k in ("vmp", "sep", "refl", "dawo")}
    counts = Counter()
    per_key = Counter()

    def emit(kind: str, key: str, sid: str, text: str, extra: dict):
        if per_key[(kind, key)] >= MAX_PER_KEY:
            return
        per_key[(kind, key)] += 1
        counts[kind] += 1
        files[kind].write(json.dumps({"id": sid, "text": text, "key": key, **extra}, ensure_ascii=False) + "\n")

    data = sentences()
    pairs = ((text, sid) for sid, text in data)
    for i, (doc, sid) in enumerate(nlp.pipe(pairs, as_tuples=True, batch_size=500), 1):
        text = doc.text
        subj_persons = {t.text.lower() for t in doc if t.dep_ == "sb"}
        for tok in doc:
            low = tok.text.lower()
            # da-/wo-compounds
            if DAWO_RE.fullmatch(low):
                emit("dawo", low, sid, text, {})
            # separable: separated prefix (svp dep) — the gold pattern
            if tok.dep_ == "svp":
                combined = low + tok.head.lemma_.lower()
                if combined in separable:
                    emit("sep", combined, sid, text, {"subtype": "separated", "verb": combined})
            # separable: attached form (infinitive/participle/zu-form)
            elif tok.pos_ == "VERB" and tok.lemma_.lower() in separable and tok.lemma_.lower() != low:
                emit("sep", tok.lemma_.lower(), sid, text, {"subtype": "attached", "verb": tok.lemma_.lower()})
            # reflexive
            if low == "sich" or (low in REFL_AGREE and REFL_AGREE[low] in subj_persons):
                head = tok.head
                if head.pos_ in ("VERB", "AUX") and head.lemma_.lower() in reflexive:
                    emit("refl", head.lemma_.lower(), sid, text, {"pronoun": low, "verb": head.lemma_.lower()})
            # verb + fixed preposition
            if tok.pos_ == "ADP" and low in PREPS:
                noun = tok.head
                verb = noun.head if noun is not tok else None
                if verb is not None and verb.pos_ in ("VERB", "AUX"):
                    key = (verb.lemma_.lower(), low)
                    if key in vmp_table:
                        emit("vmp", f"{key[0]}+{low}", sid, text,
                             {"verb": key[0], "prep": low, "level": vmp_table[key]["level"]})
        if i % 100_000 == 0:
            print(f"  {i:,} sentences processed; matches so far: {dict(counts)}")

    for f in files.values():
        f.close()
    stats = {
        "source": "Tatoeba deu_sentences.tsv (CC-BY 2.0 FR, https://tatoeba.org)",
        "processed": i,
        "matches": dict(counts),
        "distinct_keys": {k: len({key for (kind, key) in per_key if kind == k}) for k in files},
        "cap_per_key": MAX_PER_KEY,
    }
    (OUT_DIR / "mining_stats.json").write_text(json.dumps(stats, indent=2, ensure_ascii=False))
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
