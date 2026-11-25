#!/usr/bin/env python3
"""LLäMmlein (LSX-UniWue, Uni Würzburg) against the core suite — base and chat, six prompt modes.

Why this exists rather than reusing `prompt_variants_elmod.py`: that script hardcodes a 2048-token
window and reaches for `apply_chat_template` unconditionally. Both are wrong here.

  * `LLaMmlein_1B` / `LLaMmlein_7B` are **pretrained-only**. Their `tokenizer_config.json` has no
    `chat_template` at all, so `apply_chat_template` raises — and the ELMOD script's fallback calls
    it a second time, so a base model crashes instead of scoring. Base models get a raw *completion*
    prompt here (`base_*` modes), which is the only format they have ever seen.
  * The windows differ: 1B = 2048, 7B base = 4096, `7B_chat` = 32768 via YaRN. Read it from the
    config; a hardcoded 2048 would falsely reject valid 7B few-shot prompts.

Modes (all scored with the identical items / scorer / --app-guard as every other candidate):

  chat models (need a chat_template)
    english         the app's real prompt, unchanged        <- the SHIP criterion
    german          the same contract translated to German
    fewshot         English contract + 3 worked examples
    german_fewshot  German contract + 3 German examples     <- best case for a German-first tune

  base models (raw completion, no template)
    base_english    English contract + 3 examples, plain text
    base_german     German contract + 3 German examples     <- the BASE-SELECTION criterion

The split follows the ELMOD finding (data/german-first-models-writeups/elmod.md banner): a German-first model scored with
the app's English prompt measures English instruction-following, not German grammar — there it cost
a 2% -> 100% swing in format adherence. LLäMmlein is trained on *German only* (RedPajama V2 de), so
that correction applies here more strongly than it did to ELMOD, which was German+English.

Usage (from training/):
  .venv/bin/python scripts/eval_llammlein.py --model models/llammlein-7b-chat-4bit --mode english
  .venv/bin/python scripts/eval_llammlein.py --model models/llammlein-1b-4bit --mode base_german
"""
import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import run_baseline_eval as rbe  # noqa: E402
from mlx_lm import generate, load  # noqa: E402
from prompt_variants_elmod import (  # noqa: E402
    GERMAN_CORRECTION_SYSTEM,
    SHOTS,
    fewshot_messages,
    german_messages,
)

# German twins of prompt_variants_elmod.SHOTS. Same three items, same both-verdict balance (one OK,
# two FIX) — a fix-only demo set teaches "always fix", the exact way packed-v2 regressed.
GERMAN_SHOTS = [
    ('Der Lernende hat gesagt: "Ich habe gestern einen Film gesehen."\n\n'
     "Bewerte den Satz des Lernenden.", "OK"),
    ('Der Lernende hat gesagt: "Ich interessiere für Musik."\n\nBewerte den Satz des Lernenden.',
     "FIX: Ich interessiere mich für Musik.\nWHY: interessieren ist reflexiv und braucht mich."),
    ('Der Lernende hat gesagt: "Er ruft seine Mutter an jeden Sonntag."\n\n'
     "Bewerte den Satz des Lernenden.",
     "FIX: Er ruft seine Mutter jeden Sonntag an.\nWHY: Das trennbare Präfix an steht am Satzende."),
]


def german_fewshot_messages(item: dict) -> list[dict]:
    base = german_messages(item)
    if item["mode"] != "correction":
        return base
    msgs = [base[0]]
    for u, a in GERMAN_SHOTS:
        msgs += [{"role": "user", "content": u}, {"role": "assistant", "content": a}]
    return msgs + [base[1]]


CHAT_BUILDERS = {
    "english": rbe.build_messages,
    "german": german_messages,
    "fewshot": fewshot_messages,
    "german_fewshot": german_fewshot_messages,
}

# ---------------------------------------------------------------- base (completion) prompts

# A base model has never seen a chat turn. It has seen German prose with repeated structure, so the
# prompt is a plain continuation pattern and the "answer" is whatever follows the final label.
BASE_LABELS = {
    "base_english": ("Sentence", "Answer"),
    "base_german": ("Satz", "Antwort"),
}


def _base_shots(mode: str) -> list[tuple[str, str]]:
    """Reduce the chat shots to bare sentence/answer pairs — no role scaffolding."""
    if mode == "base_german":
        return [("Ich habe gestern einen Film gesehen.", "OK"),
                ("Ich interessiere für Musik.",
                 "FIX: Ich interessiere mich für Musik.\nWHY: interessieren ist reflexiv und braucht mich."),
                ("Er ruft seine Mutter an jeden Sonntag.",
                 "FIX: Er ruft seine Mutter jeden Sonntag an.\nWHY: Das trennbare Präfix an steht am Satzende.")]
    return [("Ich habe gestern einen Film gesehen.", "OK"),
            ("Ich interessiere für Musik.",
             "FIX: Ich interessiere mich für Musik.\nWHY: interessieren is reflexive and needs mich."),
            ("Er ruft seine Mutter an jeden Sonntag.",
             "FIX: Er ruft seine Mutter jeden Sonntag an.\nWHY: The separable prefix an goes to the end.")]


def base_prompt(item: dict, mode: str) -> str:
    sent, ans = BASE_LABELS[mode]
    if item["mode"] == "cloze":
        # The cloze prompt is already German and already a completion; keep it verbatim.
        header = (rbe.CLOZE_SYSTEM if mode == "base_german" else rbe.CLOZE_SYSTEM)
        return f"{header}\n\n{item['input']}\n"
    header = GERMAN_CORRECTION_SYSTEM if mode == "base_german" else rbe.CORRECTION_SYSTEM
    parts = [header, ""]
    for s, a in _base_shots(mode):
        parts.append(f"{sent}: {s}\n{ans}: {a}\n")
    src = item["input"]
    if item.get("partner"):
        # Keep the partner turn visible; the suite's context items depend on it.
        src = f'[{item["partner"]}] {src}'
    parts.append(f"{sent}: {src}\n{ans}:")
    return "\n".join(parts)


# A base model does not emit EOS on a task it was never tuned for — it runs to max_tokens and starts
# inventing the next example. Cut at whatever marks the start of a new one.
def truncate_base(text: str, mode: str) -> str:
    sent, ans = BASE_LABELS[mode]
    stops = [f"\n{sent}:", f"\n{ans}:", "\nThe student said", "\nDer Lernende", "\n\n\n", "<|im_end|>"]
    cut = len(text)
    for s in stops:
        i = text.find(s)
        if i != -1:
            cut = min(cut, i)
    return text[:cut].strip()


def window_of(model_path: str) -> int:
    """Real context window, from the model's own config — never a hardcoded constant."""
    p = Path(model_path)
    cfg = p / "config.json"
    if not cfg.exists():  # HF repo id: mlx_lm will have cached it, but fall back conservatively
        return 2048
    d = json.loads(cfg.read_text())
    return int(d.get("max_position_embeddings", 2048))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--mode", required=True,
                    choices=sorted(set(CHAT_BUILDERS) | set(BASE_LABELS)))
    ap.add_argument("--eval-file", default=str(ROOT / "data/eval/grammar_eval_v0.json"))
    ap.add_argument("--tag", default=None)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    items = json.loads(Path(args.eval_file).read_text())["items"]
    if args.limit:
        items = items[: args.limit]

    print(f"loading {args.model} ...")
    model, tokenizer = load(args.model)
    is_base_mode = args.mode in BASE_LABELS
    has_template = getattr(tokenizer, "chat_template", None) is not None

    if not is_base_mode and not has_template:
        sys.exit(f"{args.model} has no chat_template — use a base_* mode, not --mode {args.mode}")
    if is_base_mode and has_template:
        print("note: model HAS a chat template but is being scored in raw-completion mode")

    def encode(item):
        if is_base_mode:
            return tokenizer.encode(base_prompt(item, args.mode))
        msgs = CHAT_BUILDERS[args.mode](item)
        try:
            return tokenizer.apply_chat_template(msgs, add_generation_prompt=True)
        except Exception:
            merged = [{"role": "user",
                       "content": msgs[0]["content"] + "\n\n" + msgs[1]["content"]}]
            return tokenizer.apply_chat_template(merged, add_generation_prompt=True)

    win = window_of(args.model)
    longest = max(len(encode(it)) for it in items)
    print(f"longest prompt: {longest} tok (+400 generation) against a {win} window")
    if longest + 400 > win:
        sys.exit("prompt exceeds the window — this would measure the window, not the model")

    results = []
    for i, item in enumerate(items, 1):
        prompt = encode(item)
        max_tokens = 150 if item["mode"] == "cloze" else 400
        raw = rbe.strip_channels(
            generate(model, tokenizer, prompt=prompt, max_tokens=max_tokens, verbose=False))
        if is_base_mode:
            raw = truncate_base(raw, args.mode)
        guarded = rbe.apply_app_guard(raw, item)
        r = rbe.score(item, guarded)
        # Keep both: `raw` is what the model emitted (needed to tell echo from refusal), `guarded`
        # is what the app would actually display — the BübleLM diagnostic has to read the latter,
        # or an echoed FIX: (which the app renders as nothing) is miscounted as a real correction.
        r["response"] = raw
        r["guarded"] = guarded
        results.append(r)
        print(f"[{i}/{len(items)}] {item['id']}: {'PASS' if r['pass'] else 'FAIL'}")

    # The mode is always in the filename, never only in --tag: two modes run under one --tag would
    # otherwise silently overwrite each other and the second result would masquerade as the first.
    short = args.model.rstrip("/").split("/")[-1]
    stem = f"llammlein_{args.mode}_{short}" if not args.tag else f"llammlein_{args.tag}_{args.mode}_{short}"
    out = ROOT / "results" / f"{stem}.json"
    out.write_text(json.dumps(
        {"model": args.model, "app_guard": True, "prompt_mode": args.mode,
         "eval_file": Path(args.eval_file).name, "window": win, "longest_prompt": longest,
         "summary": rbe.summarize(results), "results": results},
        ensure_ascii=False, indent=1), encoding="utf-8")

    by_id = {it["id"]: it for it in items}
    corr = [r for r in results if r["mode"] == "correction"]
    ok = [r for r in corr if by_id[r["id"]].get("expect_ok")]
    err = [r for r in corr if not by_id[r["id"]].get("expect_ok")]
    fmt = sum(bool(re.search(r"FIX:\s*\S", r["response"]))
              or r["response"].strip().upper().rstrip(".!") == "OK" for r in corr)
    # Both read the GUARDED text — see the note at the scoring site.
    bare_ok = sum(r["guarded"].strip().upper().rstrip(".!") == "OK" for r in corr)
    echoed = sum(r["guarded"].strip().upper() == "OK"
                 and r["response"].strip().upper().rstrip(".!") != "OK" for r in corr)
    strict = sum(r["pass"] for r in results)

    print("\n" + "=" * 64)
    print(f"{args.mode.upper()} — {Path(args.eval_file).name} ({len(items)} items), guarded")
    print(f"  strict            {strict}/{len(items)} ({strict / len(items) * 100:.0f}%)")
    print(f"  false-correction  {sum(not r['pass'] for r in ok)}/{len(ok)}")
    print(f"  miss              {sum(not r['pass'] for r in err)}/{len(err)}")
    print(f"  format adherence  {fmt}/{len(corr)} ({fmt / len(corr) * 100:.0f}%)")
    print(f"  displays as OK    {bare_ok}/{len(corr)}   <- 0 here is the BübleLM failure mode")
    print(f"    of which echo   {echoed}/{len(corr)}   <- emitted a FIX: that just repeats the input")
    print("\n  per phenomenon (pass/total):")
    for phen, v in rbe.summarize(results).items():
        if isinstance(v, dict):
            print(f"    {phen:12s} corr {v['correction']:>7s}  cloze {v['cloze']:>7s}")
    print(f"\nsaved: {out}")


if __name__ == "__main__":
    main()
