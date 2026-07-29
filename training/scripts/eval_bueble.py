#!/usr/bin/env python3
"""Evaluate BübleLM-SFT (a German-specialised Gemma 2-2B) on the app's grammar suites.

BübleLM is trans-tokenised (custom 20k German vocab) and SFT'd on general German instruction
data — NOT on the app's FIX:/WHY: correction format. So it's scored two ways:

  strict  — the app's real scorer (needs FIX:/OK). Answers "can it be dropped in as-is?"
  lenient — extract whatever German sentence the model proposed, however phrased, and apply the
            same require/forbid token checks. Answers "is its German good enough to be worth
            fine-tuning into the format?" — the same question EuroLLM failed (great German, no
            format → 13%).

Writes a harness-format responses file so run_baseline_eval.py --responses can re-score strict.
"""
import json, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from transformers import AutoTokenizer
_o = AutoTokenizer.register
def _s(*a, **k):
    try: _o(*a, **k)
    except Exception: pass
AutoTokenizer.register = _s

from run_baseline_eval import (build_messages, strip_channels, score, matches,
                               apply_app_guard, _guard_normalize, ROOT)

MODEL = sys.argv[1] if len(sys.argv) > 1 else "models/bueble-lm-2b-sft-4bit"
EVALS = [ROOT/"data/eval/grammar_eval_v0.json", ROOT/"data/eval/grammar_eval_v1_extra.json"]
CORE_IDS = {it["id"] for it in json.loads(EVALS[0].read_text())["items"]}
OUTDIR = ROOT/"results"

SPECIALS = re.compile(r"<unk>|<eos>|<pad>|<\|im_end\|>|<\|im_start\|>|<s>|</s>")

def clean(text: str) -> str:
    text = strip_channels(text)
    text = SPECIALS.split(text)[0]            # cut at the first residual special token
    return text.strip()

def extract_sentence(resp: str) -> str:
    """The German sentence the model proposed, stripped of the framing it adds instead of FIX:."""
    s = resp.strip()
    m = re.search(r"FIX:\s*(.+)", s)          # if it did use the format, honour it
    if m: s = m.group(1)
    s = s.lstrip(":").strip()                 # BübleLM opens with ': "..."'
    s = s.strip('"“”„«»\'')
    return s.split("\n")[0].strip()

def lenient_pass(item: dict, resp: str) -> bool:
    """Same criteria as the strict scorer, but tolerant of the model's free-form framing."""
    if item["mode"] == "cloze":
        return score(item, resp)["pass"]      # cloze is already format-agnostic
    body = resp.strip()
    said_ok = body.upper().rstrip(".!") == "OK" or body.upper().startswith("OK")
    sentence = extract_sentence(body)
    if item.get("expect_ok"):
        # correct verdict = accepted, or the "fix" just restates the input (echo)
        return said_ok or _guard_normalize(sentence) == _guard_normalize(item["input"])
    if said_ok:
        return False                          # a real error waved through
    req_all = item.get("require_all", []); req_any = item.get("require_any", [])
    forbid = item.get("forbid_any", [])
    return (all(matches(n, sentence) for n in req_all)
            and (not req_any or any(matches(n, sentence) for n in req_any))
            and not any(matches(n, sentence) for n in forbid))


def main():
    from mlx_lm import load, generate
    print(f"loading {MODEL}")
    model, tok = load(MODEL)
    tok.eos_token_ids = {0, 2, 24}            # <eos>/<unk>=0, gen-config eos=2, <|im_end|>=24

    items = {}
    for f in EVALS:
        for it in json.loads(f.read_text())["items"]:
            items[it["id"]] = it

    responses = {}
    for i, (iid, it) in enumerate(items.items(), 1):
        msgs = build_messages(it)
        p = tok.apply_chat_template(msgs, add_generation_prompt=True)
        mx = 150 if it["mode"] == "cloze" else 200
        responses[iid] = clean(generate(model, tok, prompt=p, max_tokens=mx, verbose=False))
        if i % 20 == 0: print(f"  {i}/{len(items)}")

    # persist harness-format responses (both suites) for strict re-scoring
    for f in EVALS:
        suite = json.loads(f.read_text())["items"]
        tag = "core" if f == EVALS[0] else "ext"
        out = {"model": MODEL, "results": [{"id": it["id"], "response": responses[it["id"]]} for it in suite]}
        (OUTDIR/f"bueble_{tag}.responses.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))

    # score both ways
    def rate(ids, fn):
        n = sum(fn(items[i], responses[i]) for i in ids); return n, len(ids)
    strict = lambda it, r: score(it, apply_app_guard(r, it))["pass"]
    corr = [i for i in items if items[i]["mode"] == "correction"]
    okids = [i for i in corr if items[i].get("expect_ok")]
    erids = [i for i in corr if not items[i].get("expect_ok")]
    extids = [i for i in items if i not in CORE_IDS]

    print("\n================ BübleLM-SFT (Gemma 2-2B, German-specialised) ================")
    for label, fn in [("STRICT (app FIX/WHY format)", strict), ("LENIENT (German substrate)", lenient_pass)]:
        c = rate(CORE_IDS, fn); e = rate(extids, fn)
        fc = sum(not fn(items[i], responses[i]) for i in okids)
        ms = sum(not fn(items[i], responses[i]) for i in erids)
        print(f"\n{label}")
        print(f"  core       {c[0]}/{c[1]} ({c[0]/c[1]*100:.0f}%)")
        print(f"  extension  {e[0]}/{e[1]} ({e[0]/e[1]*100:.0f}%)")
        print(f"  false-corr {fc}/{len(okids)} ({fc/len(okids)*100:.0f}%)")
        print(f"  miss       {ms}/{len(erids)} ({ms/len(erids)*100:.0f}%)")

    # sample outputs
    print("\n--- sample outputs ---")
    for iid in ["vmp-e1", "refl-e1", "dawo-e3", "sep-e2", "refl-c1"]:
        if iid in responses:
            print(f"[{iid}] in={items[iid]['input']!r}\n        out={responses[iid][:110]!r}")


if __name__ == "__main__":
    main()
