#!/usr/bin/env python3
"""Score ELMOD's saved responses a second, deliberately generous way.

Same two-reading approach as scripts/eval_bueble.py, for the same reason: ELMOD is
instruction-tuned on general German chat, not on the app's FIX:/WHY: contract, so the strict
number answers "can it be dropped in as-is?" and tells you nothing about whether the German
underneath is worth fine-tuning into the format. That second question is the one that decides
§6's "fine-tune base" branch against the ~55% substrate floor.

  strict  — run_baseline_eval.py's real scorer, with --app-guard. Already reported.
  lenient — pull every sentence ELMOD quoted anywhere in its prose and pass the item if ANY
            candidate satisfies the same require_all / require_any / forbid_any checks.

BübleLM's extractor took the first line, because BübleLM answered with a bare sentence. ELMOD
buries its proposal mid-essay ("The corrected sentence should be: \"Ich stehe ... auf.\"") and
then rambles, so first-line extraction would score it at zero for the wrong reason.

LENIENT IS AN UPPER BOUND, not a score. "Any quoted span passes" credits a model that lists
five conjugations and happens to include the right one. That generosity is deliberate — if a
model cannot clear the floor even when scored this charitably, the floor question is settled.

Usage (from training/):
  .venv/bin/python scripts/score_elmod_lenient.py \
      results/baseline_elmod-2.7b-it-4bit.json results/baseline-extra_elmod-2.7b-it-4bit.json
"""
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_baseline_eval import _guard_normalize, matches, score, strip_channels  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
EVALS = [ROOT / "data/eval/grammar_eval_v0.json", ROOT / "data/eval/grammar_eval_v1_extra.json"]
CORE_IDS = {it["id"] for it in json.loads(EVALS[0].read_text())["items"]}

SPECIALS = re.compile(r"<unk>|<eos>|<pad>|<\|im_end\|>|<\|im_start\|>|<s>|</s>")
QUOTED = re.compile(r"[\"“”„«»]([^\"“”„«»\n]{2,200})[\"“”„«»]")


def clean(text: str) -> str:
    text = strip_channels(text)
    return SPECIALS.split(text)[0].strip()


def candidates(resp: str) -> list[str]:
    """Every sentence the model quoted, plus a FIX: line if it happened to use the format."""
    out = []
    m = re.search(r"FIX:\s*(.+)", resp)
    if m:
        out.append(m.group(1).strip().strip('"“”„«»'))
    out.extend(s.strip() for s in QUOTED.findall(resp))
    if not out:  # no quotes at all — fall back to the first line
        out.append(resp.strip().split("\n")[0].strip())
    return [c for c in out if c]


def lenient_pass(item: dict, resp: str) -> bool:
    if item["mode"] == "cloze":
        return score(item, resp)["pass"]  # cloze is already format-agnostic
    body = clean(resp)
    said_ok = body.upper().rstrip(".!") == "OK" or body.upper().startswith("OK")
    cands = candidates(body)
    norm_in = _guard_normalize(item["input"])

    if item.get("expect_ok"):
        # Accepted the sentence = said OK, or never proposed anything different from the input.
        # ELMOD's habit of saying "correct, but unnatural" and then re-quoting the same sentence
        # counts as an accept, because that is what the app's guard would render: nothing.
        #
        # Only multi-word candidates count as *proposals*. ELMOD constantly quotes single words
        # it is discussing ('The verb "warten" is not commonly used'), and counting those as
        # proposed rewrites scored a clean accept as a false correction.
        proposals = [c for c in cands if len(c.split()) >= 3]
        return said_ok or all(_guard_normalize(c) == norm_in for c in proposals)

    if said_ok:
        return False  # waved a real error through
    req_all = item.get("require_all", [])
    req_any = item.get("require_any", [])
    forbid = item.get("forbid_any", [])
    return any(
        all(matches(n, c) for n in req_all)
        and (not req_any or any(matches(n, c) for n in req_any))
        and not any(matches(n, c) for n in forbid)
        for c in cands
    )


def format_ok(resp: str) -> bool:
    """Did it produce the contract at all — a bare OK or a FIX: line?"""
    body = clean(resp)
    up = body.upper()
    return up.rstrip(".!") == "OK" or up.startswith("OK\n") or re.search(r"FIX:\s*\S", body) is not None


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("usage: score_elmod_lenient.py <results.json> [more ...]")

    items = {}
    for f in EVALS:
        for it in json.loads(f.read_text())["items"]:
            items[it["id"]] = it

    resp = {}
    for f in sys.argv[1:]:
        for r in json.loads(Path(f).read_text())["results"]:
            resp[r["id"]] = r["response"]

    scored = [i for i in items if i in resp]
    core = [i for i in scored if i in CORE_IDS]
    ext = [i for i in scored if i not in CORE_IDS]
    corr = [i for i in scored if items[i]["mode"] == "correction"]
    ok_ids = [i for i in corr if items[i].get("expect_ok")]
    err_ids = [i for i in corr if not items[i].get("expect_ok")]

    def rate(ids, fn):
        n = sum(fn(items[i], resp[i]) for i in ids)
        return n, len(ids)

    print(f"scored {len(scored)} items ({len(core)} core, {len(ext)} extension)\n")

    fmt = sum(format_ok(resp[i]) for i in corr)
    print(f"format adherence (bare OK or FIX: line): {fmt}/{len(corr)} "
          f"({fmt / len(corr) * 100:.0f}%)   <- the drop-in question\n")

    c = rate(core, lenient_pass)
    e = rate(ext, lenient_pass)
    fc = sum(not lenient_pass(items[i], resp[i]) for i in ok_ids)
    ms = sum(not lenient_pass(items[i], resp[i]) for i in err_ids)
    print("LENIENT (German substrate — upper bound, see module docstring)")
    print(f"  core       {c[0]}/{c[1]} ({c[0] / c[1] * 100:.0f}%)")
    print(f"  extension  {e[0]}/{e[1]} ({e[0] / e[1] * 100:.0f}%)")
    print(f"  false-corr {fc}/{len(ok_ids)} ({fc / len(ok_ids) * 100:.0f}%)")
    print(f"  miss       {ms}/{len(err_ids)} ({ms / len(err_ids) * 100:.0f}%)")

    # Composition, per the standing lesson: an aggregate that clears a bar while one
    # phenomenon collapses is the class-collapse failure that pass-rate gates miss.
    print("\nlenient by phenomenon (core+ext):")
    for phen in sorted({items[i]["phenomenon"] for i in scored}):
        sub = [i for i in scored if items[i]["phenomenon"] == phen]
        n, d = rate(sub, lenient_pass)
        print(f"  {phen:9s} {n:3d}/{d:<3d} ({n / d * 100:3.0f}%)")


if __name__ == "__main__":
    main()
