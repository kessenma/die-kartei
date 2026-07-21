#!/usr/bin/env python3
"""Quality gate for synthetic training data (correction task, v1).

Input: JSONL, one candidate per line:
  {"task":"correction","phenomenon":"vmp|sep|refl|dawo|aux|verdict|adjend|artikel",
   "level":"A1..C1","formality":"du|Sie","partner":null|str,
   "student":str,           # what the learner said
   "verdict":"ok"|"fix",
   "fix":str|null,"why":str|null,
   "meta":{...}}            # optional: verb, prep, aux, subtype

Checks (hard → reject; soft → warn but keep):
  - schema completeness, fix!=student, WHY <= 20 words          [hard]
  - no overlap with any eval item (data/eval/*.json)            [hard]
  - exact dedup on normalized (student, fix)                    [hard]
  - LanguageTool: the GOOD sentence (fix, or student when verdict=ok)
    must have 0 matches — LT guards surface quality of the gold side;
    it can NOT verify our target error types (tested 2026-07-08)  [hard]
  - spaCy structural presence of the phenomenon in the good side [hard]
  - case-government / pronoun-case details                       [soft]

Usage: .venv/bin/python scripts/validate_data.py <in.jsonl> [--out-dir data/generated]
Writes <stem>.valid.jsonl, <stem>.rejected.jsonl, prints stats.
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REFL_PRONOUNS = {"mich", "mir", "dich", "dir", "sich", "uns", "euch"}
SEIN_FORMS = {"bin", "bist", "ist", "sind", "seid", "war", "warst", "waren", "wart"}
HABEN_FORMS = {"habe", "hast", "hat", "haben", "habt", "hatte", "hattest", "hatten", "hattet"}
DAWO_RE = re.compile(
    r"\b(da|dar|wo|wor)(an|auf|aus|bei|durch|für|gegen|hinter|in|mit|nach|neben|über|um|unter|von|vor|zu|zwischen)\b",
    re.I,
)
PHENOMENA = {"vmp", "sep", "refl", "dawo", "aux", "verdict", "adjend", "artikel"}


def norm(s: str) -> str:
    return re.sub(r"[^a-zäöüß ]", "", (s or "").lower()).strip()


def load_eval_texts() -> set:
    texts = set()
    for f in (ROOT / "data" / "eval").glob("*.json"):
        for item in json.loads(f.read_text())["items"]:
            texts.add(norm(item["input"]))
    return texts


def structural_check(cand: dict, doc, good: str) -> tuple:
    """Returns (hard_error or None, [soft_warnings]). doc = spaCy doc of the good sentence."""
    phen = cand["phenomenon"]
    meta = cand.get("meta") or {}
    lemmas = {t.lemma_.lower() for t in doc}
    words = {t.text.lower() for t in doc}
    soft = []

    if phen == "vmp":
        prep = meta.get("prep")
        contractions = {"zu": {"zum", "zur"}, "an": {"am", "ans"}, "in": {"im", "ins"},
                        "von": {"vom"}, "bei": {"beim"}, "auf": {"aufs"}, "um": {"ums"},
                        "über": {"übers"}, "unter": {"unters"}, "für": {"fürs"}, "vor": {"vorm", "vors"}}
        if prep and prep not in words and not (contractions.get(prep, set()) & words):
            return f"vmp: prep '{prep}' missing in good sentence", soft
        verb = meta.get("verb")
        if verb and verb not in lemmas:
            # separated prefixes make lemma checks fuzzy; soft-fail only
            soft.append(f"vmp: verb lemma '{verb}' not found (may be separated/conjugated)")
    elif phen == "refl":
        if not (words & REFL_PRONOUNS):
            return "refl: no reflexive pronoun in good sentence", soft
    elif phen == "sep":
        if meta.get("subtype") == "separated" and not any(t.dep_ == "svp" for t in doc):
            soft.append("sep: no separated-prefix (svp) parse in good sentence")
    elif phen == "dawo":
        has_compound = bool(DAWO_RE.search(good))
        has_prep_pron = bool(re.search(
            r"\b(an|auf|mit|von|über|um|für|zu|nach|vor|bei|gegen|aus|in|unter) (ihn|ihm|ihr|sie|ihnen|dich|dir|mich|mir|euch|uns|wen|wem)\b",
            good, re.I))
        if not (has_compound or has_prep_pron):
            return "dawo: neither da/wo-compound nor prep+pronoun in good sentence", soft
    elif phen == "aux":
        want = meta.get("aux")
        if want == "sein" and not (words & SEIN_FORMS):
            return "aux: expected sein-form missing", soft
        if want == "haben" and not (words & HABEN_FORMS):
            return "aux: expected haben-form missing", soft
    # 'verdict', 'adjend', 'artikel': no structural requirement beyond LT
    return None, soft


def validate_conversation(cand: dict, nlp, lt) -> tuple:
    """Returns (hard_error or None, [warnings]) for task=conversation dialogues."""
    msgs = cand.get("messages")
    if not isinstance(msgs, list) or len(msgs) < 5:
        return "conv: too few messages", []
    roles = [m.get("role") for m in msgs]
    if roles[0] != "assistant" or roles[-1] != "assistant" or any(
            roles[i] == roles[i + 1] for i in range(len(roles) - 1)):
        return "conv: roles must alternate, starting/ending with assistant", []
    assistant_text = " ".join(m["content"] for m in msgs if m["role"] == "assistant")
    for m in msgs:
        if m["role"] == "assistant":
            matches = [x for x in lt.check(m["content"])
                       if "umgangssprachlich" not in x.message and not x.rule_id.startswith("EMPFOHLENE_")]
            if matches:
                return f"conv: LT on assistant turn: {matches[0].rule_id}: {m['content'][:60]}", []
    soft = []
    phen = cand.get("phenomenon")
    words = {t.lower() for t in re.findall(r"[a-zäöüß]+", assistant_text.lower())}
    if phen == "refl" and not (words & REFL_PRONOUNS):
        return "conv: no reflexive pronoun in any assistant turn", soft
    if phen == "dawo" and not DAWO_RE.search(assistant_text):
        return "conv: no da/wo-compound in any assistant turn", soft
    if phen == "vmp" and not (words & {"auf", "an", "über", "mit", "von", "um", "für", "nach", "zu", "vor", "aus", "bei", "unter", "gegen"}):
        return "conv: no preposition in assistant turns", soft
    if phen == "aux" and not (words & (SEIN_FORMS | HABEN_FORMS)):
        return "conv: no Perfekt auxiliary in assistant turns", soft
    if phen == "sep":
        doc = nlp(assistant_text)
        if not any(t.dep_ == "svp" for t in doc) and not re.search(r"\b\w+zu\w+en\b", assistant_text):
            soft.append("conv: no separated prefix or zu-infix found (check manually)")
    return None, soft


def validate_flashcards(cand: dict, lt) -> tuple:
    """Returns (hard_error or None, [warnings]) for task=flashcards examples."""
    cards = (cand.get("response") or {}).get("cards")
    if not isinstance(cards, list) or not cards:
        return "cards: missing/empty response.cards", []
    req = cand.get("request") or {}
    seen_words, seen_en = set(), set()
    for c in cards:
        for k in ("germanWord", "englishTranslation", "wordType", "article", "exampleSentence", "conjugations"):
            if k not in c:
                return f"cards: missing key {k} in card {c.get('germanWord')}", []
        if c["wordType"] not in ("verb", "noun", "adjective"):
            return f"cards: bad wordType {c['wordType']}", []
        if c["article"] not in ("der", "die", "das", None):
            return f"cards: bad article {c['article']}", []
        if c["wordType"] == "noun" and req.get("includeGender") and not c["article"]:
            return f"cards: noun {c['germanWord']} missing article", []
        if c["germanWord"].lower() in seen_words or c["englishTranslation"].lower() in seen_en:
            return f"cards: duplicate word/translation {c['germanWord']}", []
        seen_words.add(c["germanWord"].lower()); seen_en.add(c["englishTranslation"].lower())
        if c["conjugations"] is not None:
            for conj in c["conjugations"]:
                if not all(p in conj for p in ("tense", "ich", "du", "erSieEs", "wir", "ihr", "sieSie")):
                    return f"cards: incomplete conjugation for {c['germanWord']}", []
        if c["exampleSentence"]:
            matches = [x for x in lt.check(c["exampleSentence"]) if "umgangssprachlich" not in x.message]
            if matches:
                return f"cards: LT on example: {matches[0].rule_id}: {c['exampleSentence'][:60]}", []
    return None, []


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("infile")
    ap.add_argument("--out-dir", default=str(ROOT / "data" / "generated"))
    args = ap.parse_args()

    import spacy
    import language_tool_python as ltp

    nlp = spacy.load("de_core_news_sm", disable=["ner"])
    lt = ltp.LanguageTool("de-DE")
    eval_texts = load_eval_texts()

    infile = Path(args.infile)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    valid_f = open(out_dir / f"{infile.stem}.valid.jsonl", "w", encoding="utf-8")
    rej_f = open(out_dir / f"{infile.stem}.rejected.jsonl", "w", encoding="utf-8")

    seen = set()
    stats = {"total": 0, "valid": 0, "soft_warned": 0}
    reject_reasons = {}

    def reject(cand, reason):
        reject_reasons[reason.split(":")[0]] = reject_reasons.get(reason.split(":")[0], 0) + 1
        rej_f.write(json.dumps({"reason": reason, **cand}, ensure_ascii=False) + "\n")

    for line in infile.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        stats["total"] += 1
        try:
            cand = json.loads(line)
        except json.JSONDecodeError:
            reject({"raw": line[:200]}, "json: parse error")
            continue

        # route by task
        task = cand.get("task")
        if task == "conversation":
            key = norm(cand["messages"][0]["content"]) if isinstance(cand.get("messages"), list) and cand["messages"] else ""
            if key in seen:
                reject(cand, "duplicate"); continue
            seen.add(key)
            hard, soft = validate_conversation(cand, nlp, lt)
            if hard:
                reject(cand, hard); continue
            if soft:
                cand["_warnings"] = soft; stats["soft_warned"] += 1
            stats["valid"] += 1
            valid_f.write(json.dumps(cand, ensure_ascii=False) + "\n"); continue
        if task == "flashcards":
            key = norm(cand.get("topic", "") + (cand.get("response", {}).get("cards") or [{}])[0].get("germanWord", ""))
            if key in seen:
                reject(cand, "duplicate"); continue
            seen.add(key)
            hard, _ = validate_flashcards(cand, lt)
            if hard:
                reject(cand, hard); continue
            stats["valid"] += 1
            valid_f.write(json.dumps(cand, ensure_ascii=False) + "\n"); continue

        # schema (correction task)
        if task != "correction" or cand.get("phenomenon") not in PHENOMENA:
            reject(cand, "schema: bad task/phenomenon"); continue
        student, verdict, fix = cand.get("student"), cand.get("verdict"), cand.get("fix")
        if not student or verdict not in ("ok", "fix"):
            reject(cand, "schema: missing student/verdict"); continue
        if verdict == "fix":
            if not fix or not cand.get("why"):
                reject(cand, "schema: fix/why required"); continue
            if norm(fix) == norm(student):
                reject(cand, "content: fix identical to student"); continue
            if len(cand["why"].split()) > 20:
                reject(cand, "content: WHY too long"); continue
        good = fix if verdict == "fix" else student

        # fix must be a complete sentence, not a corrected fragment
        if verdict == "fix" and (fix.rstrip()[-1] not in ".!?…" or len(fix.split()) < 3):
            reject(cand, "content: fix is not a full sentence"); continue

        # eval overlap + dedup
        if norm(student) in eval_texts or norm(good) in eval_texts:
            reject(cand, "eval-overlap"); continue
        key = (norm(student), norm(good))
        if key in seen:
            reject(cand, "duplicate"); continue
        seen.add(key)

        # LanguageTool on the good side. Colloquial-register flags are fine —
        # the app corrects spoken conversation, not formal writing.
        matches = [m for m in lt.check(good) if "umgangssprachlich" not in m.message]
        if matches:
            reject(cand, f"languagetool: {matches[0].rule_id}: {matches[0].message[:80]}"); continue

        # structural presence
        doc = nlp(good)
        hard, soft = structural_check(cand, doc, good)
        if hard:
            reject(cand, f"structural: {hard}"); continue
        if soft:
            cand["_warnings"] = soft
            stats["soft_warned"] += 1

        stats["valid"] += 1
        valid_f.write(json.dumps(cand, ensure_ascii=False) + "\n")

    valid_f.close(); rej_f.close(); lt.close()
    stats["reject_reasons"] = reject_reasons
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
