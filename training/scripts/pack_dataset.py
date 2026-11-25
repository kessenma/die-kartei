#!/usr/bin/env python3
"""Pack validated training data into chat-format JSONL for Unsloth fine-tuning.

- Loads all data/generated/*.valid.jsonl (correction / conversation / flashcards)
- Global cross-batch dedup
- Renders each example with the app's EXACT prompt strings (ConversationPrompts.swift,
  MLXGenerationService.buildJSONPrompt, ConversationConfig prompt instructions)
- Blends in general-German mix-in (alpaca-gpt4-deutsch + sharegpt-deutsch, Apache 2.0)
- Writes data/packed/train.jsonl + val.jsonl as
  {"messages":[{role,content},...], "meta":{...}}

The `meta` block (v2, 2026-07-28) carries the labels the source .valid.jsonl files already
had and this script used to discard: task, phenomenon, level, formality, plus a derived
`template_family` used for the *grouped* train/val split. Without it every downstream
question — rebalancing, per-slice eval, leakage-safe splitting — needs a regeneration.

The split is grouped on `template_family`, so every example built from the same verb /
preposition / scenario lands on the same side. A random split puts `warten auf` in train and
`warten auf` in val, and val stops measuring generalisation. See DATA_V2_DISTILL_PLAN.md.

Usage:
  .venv/bin/python scripts/pack_dataset.py [--mixin-frac 0.35] [--val-frac 0.05] [--seed 7]
  .venv/bin/python scripts/pack_dataset.py --no-mixin --out-dir data/packed-nomixin
    → the 1B-student build: the machine-translated Alpaca mix-in is regularisation a 4B-class
      model absorbs and a 1B cannot afford. See DATA_V2_DISTILL_PLAN.md finding 3.
"""

import argparse
import json
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "packed"

sys.path.insert(0, str(Path(__file__).resolve().parent))
# The app's prompt strings, parsed out of the Swift at import time. These used to be hand-copied
# here and had silently drifted to the 2026-07-09 shape — see app_prompts.py's module docstring
# and DATA_V2_DISTILL_PLAN.md. `scripts/check_prompt_sync.py` fails the build if they diverge again.
import app_prompts as ap

SCENARIO_KEYS = set(ap.SCENARIOS)

# v1 data overloaded `scenario`: it is a ROLE the assistant plays for these exact strings, and a
# mere generation TOPIC ("morning routine", "fixing a bike") for the other ~73 values, which
# rendered as plain Lena chats. Keep the list so v1 rows still render byte-identically.
# v2 data should set `role_scenario` to an app scenario key instead of relying on this.
LEGACY_ROLE_SCENARIOS = {
    "waiter in a restaurant", "doctor in a medical practice", "receptionist at a hotel front desk",
    "sales assistant in a clothing boutique", "landlord discussing an apartment with a new tenant",
    "pharmacist at a pharmacy counter", "train conductor checking tickets on a train",
    "hairdresser with a regular customer at a hair salon", "personal trainer with a regular client at a gym",
    "vendor at a local market with a regular customer", "neighbor chatting with someone who just moved in",
    "instructor leading an evening course", "apartment viewing with a landlord", "bank appointment",
    "job fair", "course registration", "hotel reception chat", "taxi ride conversation",
    "official appointment at a government office", "parent-teacher meeting", "neighborly introduction",
}


def clean_focus(focus_areas) -> list:
    """Keep only real GrammarFocus keys.

    The teacher invents its own values — 152 distinct ones in the v2 run ('Wochenendpläne',
    'Präteritum/Perfekt', 'Wortschatz Freizeit'). They are topic labels, not the app's enum, and
    they have no steering hint, so rendering them raises KeyError. Drop silently: the row is still
    good training data, it just carries no focus steering.
    """
    return [f for f in (focus_areas or []) if f in ap.FOCUS_HINTS]


def correction_system(level: str, formality: str, strictness: str,
                      focus_areas=None, feedback_style: str = "tellMe") -> str:
    return ap.correction_system({"level": level, "formality": formality,
                                 "strictness": strictness,
                                 "focus_areas": clean_focus(focus_areas),
                                 "feedback_style": feedback_style})


def correction_user(partner, student: str) -> str:
    return ap.correction_user(partner, student)


def conversation_system(d: dict) -> str:
    """Build the app's conversation system prompt for a generated example.

    Role resolution, most specific first:
      1. `role_scenario` = an app scenario key (`bakery`, `doctor`, …) → the typed roleInstruction
         the app actually sends. This is what v2 data uses.
      2. `scenario` in LEGACY_ROLE_SCENARIOS → the generic `.custom` role-play sentence, as v1 did.
      3. anything else (including a free-text topic) → Lena.

    Case 3 matters: v1's `scenario` is a topic for ~73 of its 94 conversations, and those trained
    as ordinary Lena chats. Routing them through the role-play sentence would silently rewrite 73
    existing training examples.
    """
    cfg = {"level": d["level"], "formality": d["formality"],
           "deck_words": d.get("deck_words"), "focus_areas": clean_focus(d.get("focus_areas"))}
    role_key = (d.get("role_scenario") or "").strip()
    scenario = (d.get("scenario") or "").strip()
    if role_key:
        if role_key not in SCENARIO_KEYS:
            raise KeyError(f"role_scenario {role_key!r} is not an app scenario; "
                           f"known: {sorted(SCENARIO_KEYS)}")
        cfg["scenario"] = role_key
    elif scenario.lower() in LEGACY_ROLE_SCENARIOS:
        cfg["custom_scenario"] = scenario
    return ap.conversation_system(cfg)


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


def template_family(d: dict) -> str:
    """The group an example belongs to for splitting purposes.

    Two examples share a family when they drill the same underlying item — the same verb, the
    same preposition, the same role-play scenario. Those must not straddle train and val, or
    val measures memorisation instead of generalisation.

    Falls back to a per-phenomenon bucket when there's no finer label (notably the 245 `verdict`
    items, which carry empty meta). That is coarse but safe: a coarser group can only ever keep
    *more* related examples together.
    """
    task = d.get("task")
    meta = d.get("meta") or {}
    phen = d.get("phenomenon") or "none"

    if task == "correction":
        if meta.get("verb"):
            return f"{phen}:verb:{norm(meta['verb'])}"
        if meta.get("prep"):
            return f"{phen}:prep:{norm(meta['prep'])}"
        if meta.get("aux"):
            return f"{phen}:aux:{norm(meta['aux'])}"
        if meta.get("subtype"):
            return f"{phen}:sub:{norm(str(meta['subtype']))}"
        return f"{phen}:general"
    if task == "conversation":
        return f"conv:{norm(d.get('scenario') or 'lena')}"
    if task == "flashcards":
        return f"cards:{norm(d.get('topic') or 'none')}"
    return f"mixin:{d.get('_mixin_source', 'unknown')}"


def grouped_split(rows: list, val_frac: float, rng) -> tuple:
    """Split whole families, not rows, so no family straddles train and val.

    Families are shuffled and drawn until the val quota is met; a family that would overshoot
    the quota by more than one row is skipped rather than split. Mix-in rows are singleton
    families, so they distribute freely and fill any remainder.
    """
    by_family = {}
    for r in rows:
        by_family.setdefault(r["meta"]["template_family"], []).append(r)

    families = sorted(by_family)          # sort first so the shuffle is seed-reproducible
    rng.shuffle(families)
    target = int(len(rows) * val_frac)

    val, val_families = [], set()
    for fam in families:
        if len(val) >= target:
            break
        group = by_family[fam]
        if len(val) + len(group) > target + 1 and val:
            continue                      # would overshoot — leave this family in train
        val.extend(group)
        val_families.add(fam)

    train = [r for r in rows if r["meta"]["template_family"] not in val_families]
    return train, val, len(val_families)


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
            src = name.split("/")[-1]
            out.append({
                "messages": msgs,
                "_source": src,
                "meta": {
                    "task": "mixin",
                    "phenomenon": None,
                    "level": None,
                    "formality": None,
                    "source": src,
                    "template_family": f"mixin:{src}:{len(out)}",
                },
            })
            taken += 1
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mixin-frac", type=float, default=0.35)
    ap.add_argument("--val-frac", type=float, default=0.05)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--no-mixin", action="store_true",
                    help="omit the translated general-German mix-in (1B-student build)")
    ap.add_argument("--out-dir", default=None,
                    help="output directory (default data/packed)")
    ap.add_argument("--source", action="append", default=None,
                    help="validated .jsonl to pack (repeatable). Default: data/generated/*.valid.jsonl")
    ap.add_argument("--slice-mix", default=None,
                    help='subsample to a target mix, e.g. '
                         '"correction=0.40,conversation=0.30,flashcards=0.15,recovery=0.10,'
                         'native_instruction=0.05". Slices generate at very different yields — the '
                         'v2 correction slice over-produced 83%% against target — so without this '
                         'the corpus is skewed toward whatever generated most easily.')
    ap.add_argument("--fix-frac", type=float, default=None,
                    help="target share of verdict=fix rows WITHIN EACH correction phenomenon "
                         "(e.g. 0.70). Surplus `ok` rows are dropped; `fix` rows are always kept. "
                         "Unset = take whatever the generator produced, which is how v2 shipped "
                         "at 44%% fix against v1's 69%% and taught the model to answer OK. See the "
                         "2026-08-12 entry in training-v2.md — sep arrived at 19%% fix and "
                         "regressed hardest on the core suite.")
    ap.add_argument("--nudge-ok-frac", type=float, default=0.25,
                    help="share of verdict=ok rows rendered under the nudgeMe system prompt, so "
                         "the model learns OK is still a valid nudgeMe reply (default 0.25)")
    args = ap.parse_args()
    rng = random.Random(args.seed)
    out_dir = Path(args.out_dir) if args.out_dir else OUT
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir

    sources = ([Path(s) if Path(s).is_absolute() else ROOT / s for s in args.source]
               if args.source else sorted((ROOT / "data" / "generated").glob("*.valid.jsonl")))

    # Optional subsample to a target slice mix. Applied to the RAW rows before rendering, so the
    # dedup and grouped-split logic below sees the final population.
    raw = []
    for f in sources:
        for line in f.read_text().splitlines():
            if line.strip():
                raw.append(json.loads(line))

    if args.slice_mix:
        want = {}
        for part in args.slice_mix.split(","):
            k, v = part.split("=")
            want[k.strip()] = float(v)
        by_slice = {}
        for d in raw:
            s = (d.get("_gen") or {}).get("slice") or d.get("task")
            by_slice.setdefault(s, []).append(d)
        # The binding slice is the one furthest below its share; scale everything to it so we
        # keep as much data as possible without inventing any.
        total_cap = min((len(by_slice.get(s, [])) / frac
                         for s, frac in want.items() if frac > 0 and by_slice.get(s)),
                        default=0)
        picked, mix_stats = [], {}
        for s, frac in want.items():
            pool = by_slice.get(s, [])
            take = min(len(pool), int(round(total_cap * frac)))
            rng.shuffle(pool)
            picked.extend(pool[:take])
            mix_stats[s] = {"available": len(pool), "taken": take}
        for s, pool in by_slice.items():          # slices with no target keep everything
            if s not in want:
                picked.extend(pool)
                mix_stats[s] = {"available": len(pool), "taken": len(pool), "no_target": True}
        stats_mix = mix_stats
        raw = picked
    else:
        stats_mix = None

    # Verdict balance, per phenomenon.
    #
    # The generator decides how many of its correction rows carry a real error, and it is not
    # uniform: for v2 it produced 60% fix on `vmp` but only 19% on `sep`. Packed as-is that is what
    # the model learns — under a "separable verb" prompt, four out of five examples said nothing was
    # wrong — and E4B v2 duly answered a bare OK to textbook separable-verb errors, dropping the
    # core suite 54/60 -> 42/60 (p=0.004) with the miss rate going 9% -> 28%.
    #
    # Balancing per phenomenon rather than globally is the point: a global ratio would still let a
    # well-covered phenomenon supply all the fixes while a thin one stayed almost entirely `ok`.
    # `fix` rows are never dropped — they're the scarce half — so this only ever discards surplus
    # `ok` rows, and a phenomenon that can't reach the target simply contributes what it has.
    stats_fix = None
    if args.fix_frac is not None:
        by_phen = {}
        for d in raw:
            if d.get("task") == "correction" and d.get("phenomenon") != "verdict":
                by_phen.setdefault(d.get("phenomenon", "?"), []).append(d)
        drop = set()
        stats_fix = {}
        for phen, rows in by_phen.items():
            fix = [d for d in rows if d.get("verdict") == "fix"]
            ok = [d for d in rows if d.get("verdict") != "fix"]
            if not fix:
                continue                      # nothing to balance against; leave the slice alone
            keep_ok = min(len(ok), round(len(fix) * (1 - args.fix_frac) / args.fix_frac))
            rng.shuffle(ok)
            drop.update(id(d) for d in ok[keep_ok:])
            stats_fix[phen] = {"fix": len(fix), "ok_available": len(ok), "ok_kept": keep_ok,
                               "fix_share": round(len(fix) / (len(fix) + keep_ok), 3)}
        raw = [d for d in raw if id(d) not in drop]

    seen, examples, stats = set(), [], {}
    if stats_mix:
        stats["slice_mix"] = stats_mix
    if stats_fix:
        stats["fix_balance"] = stats_fix
    for _src in [None]:
        for d in raw:
            task = d["task"]
            if task == "correction":
                key = ("c", norm(d["student"]), norm(d.get("fix") or ""))
            elif task == "conversation":
                key = ("v", norm(d["messages"][0]["content"]))
            elif task == "native_instruction":
                key = ("n", norm(d["messages"][0]["content"]))
            else:
                key = ("f", norm(d["topic"] + d["response"]["cards"][0]["germanWord"]))
            if key in seen:
                stats["deduped"] = stats.get("deduped", 0) + 1
                continue
            seen.add(key)

            if task == "correction":
                strictness = rng.choices(["balanced", "gentle", "strict"], weights=[60, 20, 20])[0]
                # FeedbackStyle.nudgeMe asks for a third HINT: line. A row that carries a validated
                # `hint` trains that format. `ok` rows are ALSO sampled into nudgeMe at the same
                # rate — otherwise the model only ever sees the nudgeMe system prompt alongside a
                # FIX and learns that nudgeMe means "always correct something".
                hint = d.get("hint") if d["verdict"] == "fix" else None
                if hint:
                    style = "nudgeMe"
                elif d["verdict"] == "ok" and rng.random() < args.nudge_ok_frac:
                    style = "nudgeMe"
                else:
                    style = "tellMe"
                sys_p = correction_system(d["level"], d["formality"], strictness,
                                          focus_areas=d.get("focus_areas"), feedback_style=style)
                usr = correction_user(d.get("partner"), d["student"])
                if d["verdict"] == "ok":
                    asst = "OK"
                else:
                    asst = f"FIX: {d['fix']}\nWHY: {d['why']}"
                    if hint:
                        asst += f"\nHINT: {hint}"
                stats["nudgeMe"] = stats.get("nudgeMe", 0) + (style == "nudgeMe")
                msgs = [{"role": "system", "content": sys_p}, {"role": "user", "content": usr},
                        {"role": "assistant", "content": asst}]
            elif task == "native_instruction":
                # No system prompt: this slice exists purely to keep general German ability alive
                # during fine-tuning, the role the machine-translated Alpaca mix-in used to play
                # badly. Bare user→assistant, same shape the mix-in had.
                msgs = [{"role": m["role"], "content": m["content"]} for m in d["messages"]]
            elif task == "conversation":
                # the app sends a hidden user seed turn that prompts the model's opener
                # (ConversationPrompts.openerSeed) — required for user/assistant alternation
                opener = {"role": "user", "content": "Beginne jetzt das Gespräch auf Deutsch mit einer kurzen, freundlichen Begrüßung und einer Frage an mich."}
                msgs = [{"role": "system", "content": conversation_system(d)}, opener] + d["messages"]
            else:
                usr = flashcards_user(d)
                asst = json.dumps({"cards": d["response"]["cards"]}, ensure_ascii=False, separators=(",", ":"))
                msgs = [{"role": "user", "content": usr}, {"role": "assistant", "content": asst}]
            examples.append({
                "messages": msgs,
                "_source": task,
                "meta": {
                    "task": task,
                    "phenomenon": d.get("phenomenon"),
                    "level": d.get("level"),
                    "formality": d.get("formality"),
                    "source": "synthetic",
                    "template_family": template_family(d),
                },
            })
            stats[task] = stats.get(task, 0) + 1

    if args.no_mixin:
        mixin = []
        stats["mixin"] = 0
    else:
        n_mixin = int(len(examples) * args.mixin_frac / (1 - args.mixin_frac))
        mixin = load_mixin(n_mixin, rng)
        stats["mixin"] = len(mixin)
    all_ex = examples + mixin
    rng.shuffle(all_ex)

    train, val, n_val_families = grouped_split(all_ex, args.val_frac, rng)
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, rows in (("train", train), ("val", val)):
        with open(out_dir / f"{name}.jsonl", "w", encoding="utf-8") as fh:
            for r in rows:
                fh.write(json.dumps({"messages": r["messages"], "meta": r["meta"]},
                                    ensure_ascii=False) + "\n")

    # A family present on both sides means the split leaked; there is no valid reason for it.
    tf = lambda rows: {r["meta"]["template_family"] for r in rows}
    straddling = tf(train) & tf(val)
    assert not straddling, f"template_family straddles the split: {sorted(straddling)[:5]}"

    stats.update(train=len(train), val=len(val), total=len(all_ex),
                 val_families=n_val_families,
                 train_families=len(tf(train)), no_mixin=args.no_mixin)
    (out_dir / "meta.json").write_text(json.dumps(stats, indent=2))
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
