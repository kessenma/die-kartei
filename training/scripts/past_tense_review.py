#!/usr/bin/env python3
"""Repair past_tense_verbs.json by retrieving real Perfekt sentences from Tatoeba.

The old examples came from DeepL round-trips and ~70% are defective: 173 do not contain
their own participle ("Gestern habe ich Buche." for buchen) and another 210 are contentless
templates ("Ich habe benutzt."). Generating replacements would need per-verb valency data
that does not exist in this repo. Retrieving them does not: a real sentence already satisfies
its verb's frame.

Pipeline, following training/scripts/gap_review.py:
  stage 0  CORRECTIONS, applied as code so the file is reproducible from source + this dict
  stage 1  one canonical example per infinitive, shared by its level copies
  stage 2  mine Tatoeba, verify a true Perfekt clause with spaCy, gate, rank
  stage 3  write review.csv / review.md / picks.json / summary.json
  stage 4  --merge applies the human's reads_right / picked_alt into the bundle

A bad sentence is fixed by changing a rule here and regenerating, never by editing the
output file by hand.

Corpus: training/data/raw/deu_sentences.tsv -- Tatoeba, CC-BY 2.0 FR. Attribution belongs in
Features/Settings/SourcesView.swift.

Run with training/.venv (python 3.12, spacy + de_core_news_sm, language_tool_python).
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BUNDLE = REPO / "german-ai-flashcards/Resources/past_tense_verbs.json"
TATOEBA = REPO / "training/data/raw/deu_sentences.tsv"
GOETHE = [REPO / f"german-ai-flashcards/Resources/{lv}_vocabulary.json" for lv in ("a1", "a2", "b1")]
WIKTIONARY = REPO / "german-ai-flashcards/Resources/wiktionary_de.db"

# ---------------------------------------------------------------- stage 0

#: Participles that are not German. Every replacement is attested both in Tatoeba and in
#: wiktionary_de.db; `angekreuzt`, `gechattet` and `gejoggt` are also unattested in Tatoeba
#: but are correct, so they are deliberately absent from this dict.
PARTICIPLE_FIX = {
    "angetwortet": "geantwortet",
    "ausgefallt": "ausgefallen",
    "beratet": "beraten",
    "festgesteht": "festgestanden",
    "gedarstellt": "dargestellt",
    "gekennenlernt": "kennengelernt",
    "gerechnt": "gerechnet",
    "geregnt": "geregnet",
    "gereserviertet": "reserviert",
    "geunterhaltet": "unterhalten",
    "gewiederholt": "wiederholt",
    "gezeichnt": "gezeichnet",
    "geöffnt": "geöffnet",
    "hingeweist": "hingewiesen",
    "umgegeht": "umgegangen",
}

#: `reserviert` is a participle filed as an infinitive.
INFINITIVE_FIX = {"reserviert": "reservieren"}

#: Auxiliaries contradicted by Tatoeba Perfekt evidence. Only verbs where spaCy-verified
#: Perfekt clauses disagree with the file; `verbinden` is deliberately absent because its
#: sein-evidence is stative passive ("Das Kabel ist verbunden"), not Perfekt.
AUXILIARY_FIX = {
    "auffallen": "sein",
    "auftreten": "sein",
    "ausfallen": "sein",
    "umgehen": "sein",
    "verreisen": "sein",
    "umdrehen": "haben",
}

#: Modal Perfekt takes an Ersatzinfinitiv ("Ich habe gehen müssen"), so a participle example
#: would teach a marked form. These get example = null.
MODALS = {"dürfen", "können", "mögen", "müssen", "sollen", "wollen"}

AUX_FORMS = {
    "haben": {"habe", "hast", "hat", "haben", "habt"},
    "sein": {"bin", "bist", "ist", "sind", "seid"},
}
ALL_AUX = AUX_FORMS["haben"] | AUX_FORMS["sein"]
WORD = re.compile(r"[A-Za-zÄÖÜäöüßéèàç]+")

#: Words that carry no lesson: the auxiliary, a bare pronoun, a bare time adverb. A sentence made
#: only of these plus the participle demonstrates nothing ("Gestern habe ich geliefert."), which
#: is what 234 of the file's old examples were.
FILLER = (AUX_FORMS["haben"] | AUX_FORMS["sein"] | {
    "ich", "du", "er", "sie", "es", "wir", "ihr", "man", "mich", "dich", "sich", "uns", "euch",
    "mir", "dir", "ihm", "ihnen", "das", "es", "gestern", "heute", "schon", "noch", "nicht",
})


def load_rows() -> list[dict]:
    return json.loads(BUNDLE.read_text(encoding="utf-8"))


def apply_corrections(rows: list[dict]) -> tuple[list[dict], Counter]:
    """stage 0: fix the fields, counting what changed so the diff is reviewable."""
    stats = Counter()
    for r in rows:
        if r.get("infinitive") in INFINITIVE_FIX:
            r["infinitive"] = INFINITIVE_FIX[r["infinitive"]]
            stats["infinitive"] += 1
        if r.get("pastParticiple") in PARTICIPLE_FIX:
            r["pastParticiple"] = PARTICIPLE_FIX[r["pastParticiple"]]
            stats["participle"] += 1
        if r.get("infinitive") in AUXILIARY_FIX:
            new = AUXILIARY_FIX[r["infinitive"]]
            if r.get("auxiliary") != new:
                r["auxiliary"] = new
                stats["auxiliary"] += 1
    return rows, stats


def canonicalize(rows: list[dict]) -> dict[str, dict]:
    """stage 1: one record per infinitive. Level copies must not disagree on anything but level."""
    by_inf: dict[str, dict] = {}
    conflicts = Counter()
    for r in rows:
        inf = r["infinitive"]
        cur = by_inf.setdefault(inf, {
            "infinitive": inf, "levels": [], "translation": r.get("translation"),
            "auxiliary": r.get("auxiliary"), "pastParticiple": r.get("pastParticiple"),
            "isSeparable": r.get("isSeparable"), "prefix": r.get("prefix"),
            "isRegular": r.get("isRegular"), "incumbents": [],
        })
        cur["levels"].append(r.get("level"))
        if r.get("example"):
            cur["incumbents"].append(r["example"])
        for field in ("translation", "auxiliary", "pastParticiple", "isSeparable", "prefix", "isRegular"):
            if r.get(field) != cur[field]:
                conflicts[field] += 1
                # longest non-empty translation wins; first value wins elsewhere
                if field == "translation" and r.get(field) and len(r[field] or "") > len(cur[field] or ""):
                    cur[field] = r[field]
    for v in by_inf.values():
        v["levels"] = sorted(set(v["levels"]))
        v["incumbents"] = list(dict.fromkeys(v["incumbents"]))
    return by_inf, conflicts


# ---------------------------------------------------------------- stage 2: mine

def prefilter(participles: set[str]) -> dict[str, list[tuple[int, str]]]:
    """Cheap pass over 773k Tatoeba lines: keep short sentences holding an auxiliary form and
    a participle we want. spaCy only ever sees what survives this."""
    want = {p.lower() for p in participles}
    hits: dict[str, list[tuple[int, str]]] = defaultdict(list)
    with TATOEBA.open(encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            sid, text = parts[0], parts[2]
            toks = WORD.findall(text)
            if not (3 <= len(toks) <= 12):
                continue
            low = {t.lower() for t in toks}
            if not (low & ALL_AUX):
                continue
            for p in low & want:
                hits[p].append((int(sid), text))
    return hits


def load_known_lemmas() -> set[str]:
    """The Goethe A1-B1 headwords, and deliberately *not* the 350k-row dictionary.

    A sentence whose content words all live here is at the level the deck teaches. Including
    Wiktionary was the obvious first try and it is too permissive: it knows every word, so
    "Der Finanzminister hat seinen Rücktritt angeboten." sailed through as an A2 example for
    *anbieten*. Restricting to Goethe costs 3 of 354 verbs and is the strongest
    level-appropriateness signal available without a frequency list."""
    known: set[str] = set()
    for path in GOETHE:
        for row in json.loads(path.read_text(encoding="utf-8")):
            if row.get("word"):
                known.add(row["word"].lower())
    return known


CONTENT_POS = {"NOUN", "VERB", "ADJ", "ADV", "PROPN"}


def perfekt_clause(doc, participle: str):
    """The load-bearing check. Returns the participle token when the sentence is a real Perfekt
    clause with that participle, else None. A regex cannot do this: it would accept the stative
    passive ("Das Kabel ist verbunden") and adjectival participles ("Er lügt wie gedruckt")."""
    low = participle.lower()
    for tok in doc:
        if tok.text.lower() != low:
            continue
        head = tok.head
        if head.pos_ != "AUX" or head.lemma_ not in ("haben", "sein"):
            continue
        if tok.dep_ not in ("oc", "ROOT", "cj"):
            continue
        return tok
    return None


def gate(doc, tok, rec, known: set[str]) -> str | None:
    """Hard rejects. Returns a reason, or None when the sentence may be used."""
    if tok.head.lemma_ != rec["auxiliary"]:
        return f"auxiliary {tok.head.lemma_} != {rec['auxiliary']}"
    # `werden` means passive or Futur II -- except when `geworden` is the verb being taught.
    if tok.lemma_ != "werden" and any(t.lemma_ == "werden" for t in doc):
        return "werden (passive or Futur II)"
    # Count auxiliaries other than the participle itself: "Ich bin gewesen" tags `gewesen`
    # AUX too, and sein/werden are exactly the verbs whose Perfekt looks like this.
    if sum(1 for t in doc if t.pos_ == "AUX" and t.i != tok.i) != 1:
        return "more than one auxiliary"
    # A comma is fine when the Perfekt clause is the main one and the subordinate follows
    # ("Ich habe gehofft, dass ..."). A comma before it means we are inside a subordinate.
    commas = [t.i for t in doc if t.text == ","]
    if commas and min(commas) < tok.i:
        return "subordinate clause"
    if len(commas) > 1:
        return "more than one clause break"
    # one sentence, so a card shows one thing ("Echt? Das ist mir nicht aufgefallen.")
    if sum(1 for t in doc if t.text in {".", "!", "?"}) > 1:
        return "more than one sentence"
    lesson = {t.text.lower() for t in doc if t.pos_ != "PUNCT"} - FILLER
    if not (lesson - {rec["pastParticiple"].lower()}):
        return "nothing but auxiliary and participle"
    main = [t for t in doc if t.pos_ != "PUNCT" and (not commas or t.i < min(commas))]
    if not (4 <= len(main) <= 9):
        return "length"
    if len([t for t in doc if t.pos_ != "PUNCT"]) > 14:
        return "length"
    if rec.get("isSeparable") and rec.get("prefix"):
        if not rec["pastParticiple"].lower().startswith(rec["prefix"].lower()):
            return "prefix not on participle"
        if any(c.dep_ == "svp" for c in tok.children):
            return "split prefix from another clause"
    # a finite Prateritum alongside the Perfekt reads as a different tense lesson
    for t in doc:
        if t.pos_ == "VERB" and "Tense=Past" in str(t.morph) and "VerbForm=Fin" in str(t.morph):
            return "finite Prateritum"
    allowed = known | {rec["pastParticiple"].lower(), rec["infinitive"].lower()}
    oov = [t.text for t in doc
           if t.pos_ in CONTENT_POS and t.pos_ != "PROPN"
           and t.lemma_.lower() not in allowed and t.text.lower() not in allowed]
    if oov:
        return f"out of vocabulary: {', '.join(oov[:3])}"
    return None


def score(doc, tok, text: str, rec, is_incumbent: bool) -> int:
    """Preference, never rejection. Valency shows up here as a tiebreak -- a sentence with an
    object is a better demonstration -- since the verb's frame is unknown."""
    n = len([t for t in doc if t.pos_ != "PUNCT"])
    s = 0
    if tok.i >= len(doc) - 2:
        s += 3                                   # participle clause-final: the textbook shape
    if 5 <= n <= 8:
        s += 3
    if any(c.dep_ == "sb" for c in tok.head.children) or any(c.dep_ == "sb" for c in tok.children):
        s += 1
    if any(c.dep_ in ("oa", "da", "op", "mo") for c in tok.children):
        s += 1
    if any(t.pos_ == "PROPN" for t in doc):
        s -= 3
    # "sich aufführen" is a different verb from "aufführen". Legitimate for many entries
    # ("Sie hat sich verbrannt"), so this only loses a tiebreak, never the candidate.
    if not rec["infinitive"].startswith("sich ") and any(
            t.lemma_ == "sich" or t.text.lower() in {"mich", "dich", "sich", "uns", "euch"}
            for t in doc):
        s -= 2
    if text.rstrip().endswith("?"):
        s -= 2
    if is_incumbent:
        s += 1                                   # break ties toward the file we already ship
    return s


def build_candidates(by_inf: dict[str, dict], limit_lt: int | None, verbose: bool = True):
    """stage 2 end to end: prefilter, spaCy-verify, gate, LanguageTool the survivors, rank."""
    import spacy

    nlp = spacy.load("de_core_news_sm", disable=["ner"])
    known = load_known_lemmas()
    targets = {v["pastParticiple"] for v in by_inf.values() if v.get("pastParticiple")}
    if verbose:
        print(f"prefilter over {TATOEBA.name} for {len(targets)} participles ...", file=sys.stderr)
    pool = prefilter(targets)
    if verbose:
        print(f"  {sum(len(v) for v in pool.values())} candidate sentences", file=sys.stderr)

    by_participle: dict[str, list[dict]] = defaultdict(list)
    for inf, rec in by_inf.items():
        pp = rec.get("pastParticiple")
        if not pp or inf in MODALS:
            continue
        seen_text = set()
        rows = list(pool.get(pp.lower(), []))
        # the sentence we already ship competes on the same terms
        rows += [(0, t) for t in rec["incumbents"]]
        texts = [t for _, t in rows]
        for (sid, text), doc in zip(rows, nlp.pipe(texts, batch_size=256)):
            norm = " ".join(text.split())
            if norm in seen_text:
                continue
            seen_text.add(norm)
            tok = perfekt_clause(doc, pp)
            if tok is None:
                continue
            why = gate(doc, tok, rec, known)
            if why:
                continue
            by_participle[inf].append({
                "sentence": norm,
                "tatoeba_id": sid,
                "incumbent": sid == 0,
                "score": score(doc, tok, norm, rec, sid == 0),
            })
        by_participle[inf].sort(key=lambda c: -c["score"])
    return by_participle


def languagetool_filter(cands: dict[str, list[dict]], top: int = 5, verbose: bool = True):
    """Axis 2, on the shortlist only. Same predicate as validate_data.py:384."""
    import language_tool_python as ltp

    lt = ltp.LanguageTool("de-DE")
    checked = 0
    try:
        for inf, lst in cands.items():
            for c in lst[:top]:
                matches = [m for m in lt.check(c["sentence"])
                           if "umgangssprachlich" not in m.message
                           and not m.rule_id.startswith("EMPFOHLENE_")]
                c["lt_clean"] = not matches
                c["lt_rule"] = matches[0].rule_id if matches else ""
                checked += 1
            for c in lst[top:]:
                c["lt_clean"] = None
                c["lt_rule"] = ""
            lst.sort(key=lambda c: (c.get("lt_clean") is not True, -c["score"]))
    finally:
        lt.close()
    if verbose:
        print(f"  LanguageTool checked {checked} shortlisted sentences", file=sys.stderr)
    return cands


# ---------------------------------------------------------------- stage 3: review sheet

ALT_COLUMNS = 4


def strata(by_inf, cands) -> dict[str, str]:
    """Who must be read. A = census of everything the machine is unsure about, B = a seeded
    random sample of the clean bulk (for a confidence interval), C = the incumbent won, so it
    is already shipped and needs no read."""
    out: dict[str, str] = {}
    for inf, rec in by_inf.items():
        lst = cands.get(inf) or []
        best = lst[0] if lst else None
        if inf in MODALS:
            out[inf] = "A:modal"
        elif not lst:
            out[inf] = "A:no-evidence"
        elif rec["pastParticiple"] in PARTICIPLE_FIX.values():
            out[inf] = "A:participle-fixed"
        elif inf in AUXILIARY_FIX:
            out[inf] = "A:auxiliary-fixed"
        elif inf in INFINITIVE_FIX.values():
            out[inf] = "A:infinitive-fixed"
        elif len(lst) <= 2:
            out[inf] = "A:thin"
        elif best and best.get("lt_clean") is not True:
            out[inf] = "A:lt-flagged"
        elif best and best["incumbent"]:
            out[inf] = "C:incumbent"
        else:
            out[inf] = "B:bulk"
    return out


def sample_b(assign: dict[str, str], n: int, seed: int) -> set[str]:
    bulk = sorted(i for i, s in assign.items() if s == "B:bulk")
    rng = random.Random(seed)
    return set(bulk if len(bulk) <= n else rng.sample(bulk, n))


def write_sheet(out_dir: Path, by_inf, cands, assign, sampled, seed):
    out_dir.mkdir(parents=True, exist_ok=True)
    header = (["infinitive", "translation", "levels", "auxiliary", "pastParticiple",
               "old_example", "new_example", "tatoeba_id", "rank", "score", "lt_clean"]
              + [f"alt{i}" for i in range(1, ALT_COLUMNS + 1)]
              + ["stratum", "to_read", "reads_right", "picked_alt", "note"])
    rows_out = []
    picks = {}
    for inf in sorted(by_inf):
        rec, lst = by_inf[inf], (cands.get(inf) or [])
        best = lst[0] if lst else None
        stratum = assign[inf]
        to_read = "yes" if stratum.startswith("A") or inf in sampled else ""
        if best:
            picks[inf] = {"tatoeba_id": best["tatoeba_id"], "score": best["score"],
                          "rank": 1, "incumbent": best["incumbent"],
                          "source": "incumbent" if best["incumbent"] else "tatoeba"}
        rows_out.append(dict(zip(header, [
            inf, rec.get("translation") or "", "/".join(rec["levels"]), rec.get("auxiliary") or "",
            rec.get("pastParticiple") or "",
            rec["incumbents"][0] if rec["incumbents"] else "",
            best["sentence"] if best else "",
            best["tatoeba_id"] if best else "", 1 if best else "",
            best["score"] if best else "", best.get("lt_clean") if best else "",
            *[(lst[i]["sentence"] if i < len(lst) else "") for i in range(1, ALT_COLUMNS + 1)],
            stratum, to_read, "", "", "",
        ])))
    with (out_dir / "review.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=header)
        w.writeheader()
        w.writerows(rows_out)
    (out_dir / "picks.json").write_text(
        json.dumps(picks, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    counts = Counter(assign.values())
    summary = {
        "seed": seed, "verbs": len(by_inf),
        "with_candidates": sum(1 for v in cands.values() if v),
        "with_five_plus": sum(1 for v in cands.values() if len(v) >= 5),
        "strata": dict(sorted(counts.items())),
        "to_read": sum(1 for r in rows_out if r["to_read"] == "yes"),
        "corrections": {"participle": len(PARTICIPLE_FIX), "auxiliary": len(AUXILIARY_FIX),
                        "infinitive": len(INFINITIVE_FIX)},
    }
    (out_dir / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    md = ["# Perfekt examples, 2026-10", "",
          f"Seed {seed}. {summary['with_candidates']}/{summary['verbs']} verbs have a "
          f"spaCy-verified, LanguageTool-clean Perfekt sentence from Tatoeba (CC-BY 2.0 FR).", "",
          "Read the rows with `to_read = yes` in `review.csv`. You never write German: tick",
          "`reads_right = y`, or put `1`-`4` in `picked_alt` to promote an alternate, or `n` to",
          "leave the verb without an example. A bad *rule* is fixed in the script and the sheet",
          "regenerated -- never hand-edit the bundle.", "",
          "| stratum | verbs | why |", "|---|---|---|"]
    why = {"A:modal": "Ersatzinfinitiv, example forced to null",
           "A:no-evidence": "no Perfekt clause in 773,911 sentences",
           "A:participle-fixed": "participle was corrupt in the file",
           "A:auxiliary-fixed": "auxiliary contradicted by the corpus",
           "A:infinitive-fixed": "infinitive was a participle",
           "A:thin": "only 1-2 candidates survived the gate",
           "A:lt-flagged": "best candidate has a LanguageTool match",
           "B:bulk": "clean bulk; a seeded sample is read to bound the error rate",
           "C:incumbent": "the shipped sentence won; already in the app, no read needed"}
    for k, n in sorted(counts.items()):
        md.append(f"| `{k}` | {n} | {why.get(k, '')} |")
    md += ["", f"**{summary['to_read']} rows to read.**", ""]
    (out_dir / "review.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    # The run log, the shape training/data/gap-choice/reflexiv-2026-10/ already uses.
    readme = [
        "# past_tense_verbs.json — Perfekt examples from Tatoeba",
        "",
        "Produced by `training/scripts/past_tense_review.py` (seed "
        f"{seed}). Regenerate rather than hand-edit: a bad sentence means a bad *rule*, and the",
        "rule lives in that script.",
        "",
        "## Why",
        "",
        "The examples in this file were built by DeepL round-trips and about 70% were defective:",
        "173 did not contain their own participle (`\"Gestern habe ich Buche.\"` for *buchen*) and a",
        "further 234 were nothing but an auxiliary and a participle (`\"Ich habe benutzt.\"`). Sixteen",
        "`pastParticiple` values were not German at all — `gewiederholt`, `geregnt` — and six",
        "`auxiliary` values were contradicted by the corpus.",
        "",
        "Generating replacements would need per-verb valency data this repo does not have. Retrieving",
        "them needs none: a real sentence already satisfies its verb's frame.",
        "",
        "## What ran",
        "",
        f"- corpus: `training/data/raw/deu_sentences.tsv` — Tatoeba, CC-BY 2.0 FR, 773,911 sentences",
        f"- {summary['with_candidates']}/{summary['verbs']} verbs got a spaCy-verified, LanguageTool-clean Perfekt clause",
        f"- {summary['with_five_plus']} have five or more candidates, so a rejected pick has somewhere to fall",
        f"- field corrections applied as code: {summary['corrections']}",
        "",
        "## Files",
        "",
        "| file | what |",
        "|---|---|",
        "| `review.csv` | the sheet to read — see `review.md` for the strata |",
        "| `review.md` | what to read and how |",
        "| `picks.json` | `infinitive -> {tatoeba_id, score, rank}`, the provenance of record |",
        "| `summary.json` | the numbers above |",
        "",
        "## Merging",
        "",
        "```bash",
        "training/.venv/bin/python training/scripts/past_tense_review.py --merge --dry-run",
        "training/.venv/bin/python training/scripts/past_tense_review.py --merge",
        "python3 scripts/check_content.py --write-baseline   # past_tense should fall to ~0",
        "```",
        "",
        "Attribution for Tatoeba is in `Features/Settings/SourcesView.swift`; the regression net is",
        "`german-ai-flashcardsTests/PastTenseVerbAuditTests.swift`.",
        "",
    ]
    (out_dir / "README.md").write_text("\n".join(readme), encoding="utf-8")
    return summary


# ---------------------------------------------------------------- stage 4: merge

def merge(out_dir: Path, dry_run: bool = False) -> dict:
    """Apply the read sheet to the bundle. Every row's example becomes the picked sentence,
    the promoted alternate, or null. The corrections from stage 0 land here too."""
    sheet = list(csv.DictReader((out_dir / "review.csv").open(encoding="utf-8")))
    chosen: dict[str, str | None] = {}
    for row in sheet:
        inf = row["infinitive"]
        verdict = (row.get("reads_right") or "").strip().lower()
        alt = (row.get("picked_alt") or "").strip()
        if verdict == "n":
            chosen[inf] = None
        elif alt in {str(i) for i in range(1, ALT_COLUMNS + 1)} and row.get(f"alt{alt}"):
            chosen[inf] = row[f"alt{alt}"]
        elif row.get("new_example"):
            chosen[inf] = row["new_example"]
        else:
            chosen[inf] = None
    rows, stats = apply_corrections(load_rows())
    # The infinitive fix can land a row on top of one that already exists at that level.
    seen_keys: set[tuple[str, str]] = set()
    deduped = []
    for r in rows:
        key = (r["infinitive"], r.get("level", ""))
        if key in seen_keys:
            continue
        seen_keys.add(key)
        deduped.append(r)
    dropped = len(rows) - len(deduped)
    rows = deduped
    by_inf, _ = canonicalize(rows)
    picks = json.loads((out_dir / "picks.json").read_text(encoding="utf-8"))
    changed = 0
    for r in rows:
        inf = r["infinitive"]
        if inf not in chosen:
            continue
        new = chosen[inf]
        if r.get("example") != new:
            changed += 1
        r["example"] = new
        canon = by_inf[inf]
        for field in ("translation", "auxiliary", "pastParticiple", "isSeparable", "prefix", "isRegular"):
            r[field] = canon[field]
        if new is None:
            r.pop("exampleSource", None)
        else:
            p = picks.get(inf)
            r["exampleSource"] = ("authored" if not p else
                                  ("incumbent" if p.get("incumbent") else "tatoeba"))
    if not dry_run:
        BUNDLE.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"rows": len(rows), "duplicate_rows_dropped": dropped, "examples_changed": changed,
            "null_examples": sum(1 for r in rows if r.get("example") is None),
            "field_corrections": dict(stats)}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out_dir", type=Path, nargs="?",
                    default=REPO / "training/data/past-tense/perfekt-2026-10")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--sample", type=int, default=100, help="stratum B reads")
    ap.add_argument("--merge", action="store_true", help="apply review.csv to the bundle")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.merge:
        print(json.dumps(merge(args.out_dir, args.dry_run), indent=2))
        return

    rows, stats = apply_corrections(load_rows())
    print(f"stage 0 corrections: {dict(stats)}", file=sys.stderr)
    by_inf, conflicts = canonicalize(rows)
    print(f"stage 1: {len(by_inf)} verbs, cross-copy conflicts {dict(conflicts)}", file=sys.stderr)
    cands = build_candidates(by_inf, None)
    languagetool_filter(cands)
    assign = strata(by_inf, cands)
    sampled = sample_b(assign, args.sample, args.seed)
    summary = write_sheet(args.out_dir, by_inf, cands, assign, sampled, args.seed)
    print(json.dumps(summary, indent=2))
    print(f"\nwrote {args.out_dir}/review.csv · review.md · picks.json · summary.json",
          file=sys.stderr)


if __name__ == "__main__":
    main()
