#!/usr/bin/env python3
"""Pack validated training data into chat-format JSONL for Unsloth fine-tuning.

- Loads all data/generated/*.valid.jsonl (correction / conversation / flashcards)
- Global cross-batch dedup
- Renders each example with the app's EXACT prompt strings (ConversationPrompts.swift,
  MLXGenerationService.buildJSONPrompt, ConversationConfig prompt instructions)
- Blends in general-German mix-in (alpaca-gpt4-deutsch + sharegpt-deutsch, Apache 2.0)
- Writes data/packed/train.jsonl + val.jsonl as {"messages":[{role,content},...]}

Usage: .venv/bin/python scripts/pack_dataset.py [--mixin-frac 0.35] [--val-frac 0.02] [--seed 7]
"""

import argparse
import json
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "packed"

# ---- exact strings from the app ----

LEVEL_INSTR = {
    "A1": "The learner is a beginner (A1). Use only the most common words and short, simple sentences in the present tense. Keep each reply to one or two short sentences.",
    "A2": "The learner is at A2 (elementary). Use simple everyday vocabulary and mostly short sentences. You may use basic past tense (Perfekt) occasionally.",
    "B1": "The learner is at B1 (intermediate). Use everyday vocabulary and a natural mix of tenses, but keep sentences reasonably clear.",
    "B2": "The learner is at B2 (upper-intermediate). Use natural German with varied sentence structures and richer vocabulary.",
    "C1": "The learner is at C1 (advanced). Use fluent, idiomatic German with complex structures and nuanced vocabulary.",
}
FORMALITY_INSTR = {
    "du": 'Address the learner informally using the "du" form.',
    "Sie": 'Address the learner formally using the "Sie" form.',
}
STRICTNESS = {
    "gentle": "Only point out mistakes that genuinely obscure meaning or are clear grammatical errors. Ignore minor style or punctuation issues.",
    "balanced": "Point out grammar, case, word-order, and clear vocabulary mistakes. Ignore tiny stylistic issues.",
    "strict": "Point out every grammatical, case, word-order, spelling, and word-choice mistake, even small ones.",
}


def correction_system(level: str, formality: str, strictness: str) -> str:
    s = "You are a meticulous German teacher reviewing one line a student said during a spoken conversation. "
    s += f"The student's level is {level}. "
    s += STRICTNESS[strictness] + " "
    s += f"The student uses the {formality} form. "
    s += "They may have mixed in an English word they didn't know — in your correction, replace it with the correct German word.\n\n"
    s += "If the sentence is already correct and natural German, reply with exactly:\nOK\n\n"
    s += "Otherwise reply in EXACTLY this format and nothing else:\n"
    s += "FIX: <the full corrected sentence in natural German>\n"
    s += "WHY: <one short explanation in English, at most 18 words>"
    return s


def correction_user(partner, student: str) -> str:
    if partner:
        return f'The conversation partner just said: "{partner}"\nThe student replied: "{student}"\n\nEvaluate only the student\'s reply.'
    return f'The student said: "{student}"\n\nEvaluate the student\'s sentence.'


def conversation_system(d: dict) -> str:
    parts = []
    scenario = (d.get("scenario") or "").strip()
    # exact scenario strings where the assistant plays a character (not Lena)
    ROLE_SCENARIOS = {
        "waiter in a restaurant", "doctor in a medical practice", "receptionist at a hotel front desk",
        "sales assistant in a clothing boutique", "landlord discussing an apartment with a new tenant",
        "pharmacist at a pharmacy counter", "train conductor checking tickets on a train",
        "hairdresser with a regular customer at a hair salon", "personal trainer with a regular client at a gym",
        "vendor at a local market with a regular customer", "neighbor chatting with someone who just moved in",
        "instructor leading an evening course", "apartment viewing with a landlord", "bank appointment",
        "job fair", "course registration", "hotel reception chat", "taxi ride conversation",
        "official appointment at a government office", "parent-teacher meeting", "neighborly introduction",
    }
    if scenario.lower() in ROLE_SCENARIOS:
        parts.append(f"You are role-playing the following situation with a German learner: {scenario}. Stay fully in character and set the scene.")
    else:
        parts.append("You are Lena, a warm and patient German conversation partner helping someone practice spoken German.")
    parts.append("Speak ONLY in German. " + LEVEL_INSTR[d["level"]] + " " + FORMALITY_INSTR[d["formality"]])
    parts.append("Keep your replies short — usually one to three sentences — and end most replies with a question so the conversation keeps flowing.")
    parts.append("The learner is speaking out loud, so their words may contain small transcription glitches and they may mix in an English word when they don't know the German one. Understand them charitably and simply continue the conversation in natural German.")
    parts.append("Do NOT correct the learner, and do NOT add translations, explanations, or any English in your replies. Just have a natural conversation.")
    if d.get("deck_words"):
        sample = ", ".join(d["deck_words"])
        parts.append(f"The learner is studying these German words; weave a few of them naturally into your questions and replies, and encourage the learner to use them: {sample}.")
    return "\n\n".join(parts)


EXAMPLE_CARD = {
    "verbs": '{{"germanWord":"kochen","englishTranslation":"to cook","wordType":"verb","article":null,"exampleSentence":{ex},"conjugations":null}}',
    "adjectives": '{{"germanWord":"heiß","englishTranslation":"hot","wordType":"adjective","article":null,"exampleSentence":{ex},"conjugations":null}}',
    "default": '{{"germanWord":"der Tisch","englishTranslation":"the table","wordType":"noun","article":"der","exampleSentence":{ex},"conjugations":null}}',
}
WORDTYPE_INSTR = {
    "all": "Include a mix of nouns, verbs, and adjectives.",
    "nouns": 'Only generate nouns. Set wordType to "noun" for each.',
    "verbs": 'Only generate verbs (action words like kochen, backen, braten). Set wordType to "verb" for each.',
    "adjectives": 'Only generate adjectives. Set wordType to "adjective" for each.',
}
EX_SENT = {"verbs": '"Ich koche gerne."', "adjectives": '"Das Wasser ist heiß."', "default": '"Der Tisch ist groß."'}


def flashcards_user(d: dict) -> str:
    req = d["request"]
    wt = req["wordTypeFilter"]
    key = wt if wt in ("verbs", "adjectives") else "default"
    ex = EX_SENT[key] if req.get("includeExamples") else "null"
    example = EXAMPLE_CARD[key].format(ex=ex)
    noun_word = "verbs" if wt == "verbs" else "words"
    p = f'Generate exactly {req["count"]} different German {noun_word} related to "{d["topic"]}".\n'
    p += WORDTYPE_INSTR[wt] + "\n"
    p += 'Respond with a JSON object: {"cards":[' + example + ", ...]}\n"
    p += "Each card MUST be a different German word. Do NOT repeat any word.\n"
    p += "Each card MUST have a unique English translation — no two cards may share the same englishTranslation.\n"
    p += 'Use the most precise, literal English translation for each word (e.g. "to see" for sehen, "to look" for schauen, not both "to watch"). '
    p += 'You may add parenthetical context to disambiguate similar words (e.g. "to watch (a film)", "to look (at something)").'
    if req.get("includeGender") and wt in ("nouns", "all"):
        p += "\nFor nouns, include the article (der/die/das). Non-nouns have article:null."
    else:
        p += "\nSet article to null."
    if not req.get("includeExamples"):
        p += "\nSet exampleSentence to null."
    if wt == "verbs" and req.get("includeConjugations") and req.get("tenses"):
        p += ('\nFor verbs, include conjugations: '
              '[{"tense":"...","ich":"...","du":"...","erSieEs":"...","wir":"...","ihr":"...","sieSie":"..."}] '
              f'for: {", ".join(req["tenses"])}. Non-verbs have conjugations:null.')
    else:
        p += "\nSet conjugations to null."
    return p


def norm(s: str) -> str:
    return re.sub(r"[^a-zäöüß ]", "", (s or "").lower()).strip()


def load_mixin(n: int, rng) -> list:
    """Sample n chat examples from the Apache-2.0 German mix-in datasets."""
    from datasets import load_dataset
    out = []
    for name, frac in (("FreedomIntelligence/alpaca-gpt4-deutsch", 0.75),
                       ("FreedomIntelligence/sharegpt-deutsch", 0.25)):
        want = int(n * frac)
        ds = load_dataset(name, split="train")
        idxs = rng.sample(range(len(ds)), min(want * 2, len(ds)))  # oversample, filter below
        taken = 0
        for i in idxs:
            if taken >= want:
                break
            row = ds[i]
            msgs = []
            if "conversations" in row and row["conversations"]:
                role_map = {"human": "user", "gpt": "assistant", "user": "user", "assistant": "assistant"}
                for turn in row["conversations"]:
                    r = role_map.get(turn.get("from"))
                    if r is None:
                        msgs = []; break
                    msgs.append({"role": r, "content": turn.get("value", "")})
            elif "instruction" in row:
                user = (row["instruction"] + ("\n\n" + row["input"] if row.get("input") else "")).strip()
                msgs = [{"role": "user", "content": user}, {"role": "assistant", "content": row.get("output", "")}]
            while msgs and msgs[-1]["role"] != "assistant":
                msgs.pop()  # trailing user turn has no training signal
            if not msgs or msgs[0]["role"] != "user" or len(msgs) < 2:
                continue
            total_len = sum(len(m["content"]) for m in msgs)
            if total_len > 4000 or total_len < 40:
                continue
            out.append({"messages": msgs, "_source": name.split("/")[-1]})
            taken += 1
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mixin-frac", type=float, default=0.35)
    ap.add_argument("--val-frac", type=float, default=0.02)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    seen, examples, stats = set(), [], {}
    for f in sorted((ROOT / "data" / "generated").glob("*.valid.jsonl")):
        for line in f.read_text().splitlines():
            d = json.loads(line)
            task = d["task"]
            if task == "correction":
                key = ("c", norm(d["student"]), norm(d.get("fix") or ""))
            elif task == "conversation":
                key = ("v", norm(d["messages"][0]["content"]))
            else:
                key = ("f", norm(d["topic"] + d["response"]["cards"][0]["germanWord"]))
            if key in seen:
                stats["deduped"] = stats.get("deduped", 0) + 1
                continue
            seen.add(key)

            if task == "correction":
                strictness = rng.choices(["balanced", "gentle", "strict"], weights=[60, 20, 20])[0]
                sys_p = correction_system(d["level"], d["formality"], strictness)
                usr = correction_user(d.get("partner"), d["student"])
                asst = "OK" if d["verdict"] == "ok" else f"FIX: {d['fix']}\nWHY: {d['why']}"
                msgs = [{"role": "system", "content": sys_p}, {"role": "user", "content": usr},
                        {"role": "assistant", "content": asst}]
            elif task == "conversation":
                # the app sends a hidden user seed turn that prompts the model's opener
                # (ConversationPrompts.openerSeed) — required for user/assistant alternation
                opener = {"role": "user", "content": "Beginne jetzt das Gespräch auf Deutsch mit einer kurzen, freundlichen Begrüßung und einer Frage an mich."}
                msgs = [{"role": "system", "content": conversation_system(d)}, opener] + d["messages"]
            else:
                usr = flashcards_user(d)
                asst = json.dumps({"cards": d["response"]["cards"]}, ensure_ascii=False, separators=(",", ":"))
                msgs = [{"role": "user", "content": usr}, {"role": "assistant", "content": asst}]
            examples.append({"messages": msgs, "_source": task})
            stats[task] = stats.get(task, 0) + 1

    n_mixin = int(len(examples) * args.mixin_frac / (1 - args.mixin_frac))
    mixin = load_mixin(n_mixin, rng)
    stats["mixin"] = len(mixin)
    all_ex = examples + mixin
    rng.shuffle(all_ex)

    n_val = max(1, int(len(all_ex) * args.val_frac))
    val, train = all_ex[:n_val], all_ex[n_val:]
    OUT.mkdir(parents=True, exist_ok=True)
    for name, rows in (("train", train), ("val", val)):
        with open(OUT / f"{name}.jsonl", "w", encoding="utf-8") as fh:
            for r in rows:
                fh.write(json.dumps({"messages": r["messages"]}, ensure_ascii=False) + "\n")
    stats.update(train=len(train), val=len(val), total=len(all_ex))
    (OUT / "meta.json").write_text(json.dumps(stats, indent=2))
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
