#!/usr/bin/env python3
"""Bridge the grammar eval to a LiteRT-LM `.litertlm` bundle, via the C-API driver in
`litertlm_runner.c`.

Same runtime-agnostic seam as `gen_cactus_responses.py`, but over a file pipe instead of
HTTP: the released `litert_lm_main` CLI binaries ship without their Bazel runfiles shared
libs and won't load, so we drive `libCLiteRTLM_mac.dylib` directly.

Prompts come from run_baseline_eval.build_messages (imported, not copied), so the system
and user turns are identical to the MLX run. One deliberate difference: the chat template
is applied by the runtime, not by us. The Conversation API templates internally using the
bundle's own template, so we pass the system text and user turn separately instead of a
pre-rendered string — the same shape the iOS app would use. Responses are saved RAW;
`run_baseline_eval.py --responses` applies strip_channels itself.

Usage:
  # 1. render prompts for the driver
  .venv/bin/python scripts/gen_litertlm_responses.py prep \
      --suite core --out /tmp/core.in.bin

  # 2. run the driver (see litertlm_runner.c header for the build line)
  ./litertlm_runner model.litertlm cpu /tmp/core.in.bin /tmp/core.out.bin

  # 3. fold the driver output into the harness shape
  .venv/bin/python scripts/gen_litertlm_responses.py collect \
      --suite core --in /tmp/core.out.bin --out-prefix litertlm_e2b_int4
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_baseline_eval import build_messages  # identical prompts to the MLX harness

SUITES = {
    "core": ROOT / "data/eval/grammar_eval_v0.json",
    "ext": ROOT / "data/eval/grammar_eval_v1_extra.json",
}


def load_items(suite: str) -> list[dict]:
    return json.loads(SUITES[suite].read_text())["items"]


def cmd_prep(args):
    """Emit the driver's NUL-delimited input.

    The chat template is NOT applied here: the LiteRT-LM Conversation API applies the
    bundle's own template internally, so we hand it the system text and the user turn
    separately — the same shape the iOS app would use. System text goes over as a PLAIN
    string (the C API silently ignores a JSON-object system message).
    """
    items = load_items(args.suite)
    out = Path(args.out)
    with out.open("wb") as f:
        for it in items:
            msgs = build_messages(it)
            system_text = msgs[0]["content"]
            user_json = json.dumps({"role": "user", "content": msgs[1]["content"]},
                                   ensure_ascii=False)
            max_tokens = 150 if it["mode"] == "cloze" else 400  # same budgets as MLX harness
            for field in (it["id"], str(max_tokens), system_text, user_json):
                f.write(field.encode("utf-8") + b"\x00")
    print(f"wrote {out} — {len(items)} prompts from {args.suite}")
    m = build_messages(items[0])
    print(f"--- system ({len(m[0]['content'])} chars) ---\n{m[0]['content'][:220]}")
    print(f"--- user ---\n{m[1]['content'][:220]}")


def extract_text(raw: str) -> str:
    """Pull assistant text out of the Conversation API's JSON response.

    Shape: {"role":"assistant","content":[{"type":"text","text":"..."}]}
    """
    if not raw:
        return ""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return raw  # keep whatever came back rather than silently dropping it
    content = payload.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(p.get("text", "") for p in content
                       if isinstance(p, dict) and p.get("type", "text") == "text")
    return ""


def cmd_collect(args):
    blob = Path(args.inp).read_bytes()
    parts = blob.split(b"\x00")
    if parts and parts[-1] == b"":
        parts.pop()
    if len(parts) % 2:
        print(f"warning: odd record count ({len(parts)}) — driver may have been cut short")
        parts = parts[: len(parts) // 2 * 2]
    got = {
        parts[i].decode("utf-8", "replace"): extract_text(parts[i + 1].decode("utf-8", "replace"))
        for i in range(0, len(parts), 2)
    }

    items = load_items(args.suite)
    results = [{"id": it["id"], "response": got.get(it["id"], "")} for it in items]
    missing = [r["id"] for r in results if not r["response"]]

    (ROOT / "results").mkdir(exist_ok=True)
    dest = ROOT / "results" / f"{args.out_prefix}_{args.suite}.responses.json"
    dest.write_text(
        json.dumps({"model": args.model_label, "runtime": args.runtime, "results": results},
                   ensure_ascii=False, indent=1),
        encoding="utf-8",
    )
    print(f"wrote {dest} — {len(results)} items, {len(missing)} empty")
    if missing:
        print(f"  empty ids: {missing[:8]}{' ...' if len(missing) > 8 else ''}")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("prep")
    p.add_argument("--suite", choices=SUITES, required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_prep)

    c = sub.add_parser("collect")
    c.add_argument("--suite", choices=SUITES, required=True)
    c.add_argument("--in", dest="inp", required=True)
    c.add_argument("--out-prefix", default="litertlm_e2b_int4")
    c.add_argument("--runtime", default="litertlm-int4")
    c.add_argument("--model-label", default="gemma4-e2b-german-tutor")
    c.set_defaults(func=cmd_collect)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
