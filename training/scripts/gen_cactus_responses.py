#!/usr/bin/env python3
"""Generate eval responses from a Cactus bundle via `cactus serve`, in the exact
`{"results":[{"id","response"}]}` shape that run_baseline_eval.py --responses and
behavior_metrics.py consume — the same seam used for Apple Intelligence.

Prompts come from run_baseline_eval.build_messages (imported, not copied) so the Cactus
runtime sees byte-identical system/user turns to the MLX run: only the runtime differs.

Prereq — start the server first (loads the bundle once), fully local, greedy:
  HF_HUB_OFFLINE=1 cactus serve "$PWD/convert/e2b-cur-cq4" \
      --no-cloud-handoff --no-access-log --backend metal --port 8899

Then (from training/):
  .venv/bin/python scripts/gen_cactus_responses.py --port 8899 --out-prefix cactus_e2b_cq4
"""
import argparse
import json
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_baseline_eval import build_messages  # identical prompts to the MLX harness

SUITES = {
    "core": ROOT / "data/eval/grammar_eval_v0.json",
    "ext": ROOT / "data/eval/grammar_eval_v1_extra.json",
}


def post(base, model, messages, max_tokens, retries=3):
    body = json.dumps({
        "model": model,
        "messages": messages,
        "temperature": 0,          # greedy — match the MLX harness
        "top_p": 1,
        "max_tokens": max_tokens,
        "stream": False,
    }).encode()
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(base + "/v1/chat/completions", data=body,
                                         headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=600) as r:
                data = json.load(r)
            return data["choices"][0]["message"]["content"], data.get("cloud_handoff")
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}: {e.read().decode()[:200]}"
        except Exception as e:  # noqa: BLE001
            last = repr(e)
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"request failed after {retries} tries: {last}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8899)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--out-prefix", default="cactus_e2b_cq4")
    ap.add_argument("--runtime", default="cactus-cq4",
                    help="label stamped into the responses file (e.g. litertlm-int4)")
    args = ap.parse_args()
    base = f"http://{args.host}:{args.port}"

    with urllib.request.urlopen(base + "/v1/models", timeout=30) as r:
        model = json.load(r)["data"][0]["id"]
    print(f"server {base} | model={model}")

    (ROOT / "results").mkdir(exist_ok=True)
    handoffs = 0
    for suite, path in SUITES.items():
        items = json.loads(Path(path).read_text())["items"]
        results = []
        t0 = time.time()
        for i, it in enumerate(items, 1):
            max_tokens = 150 if it["mode"] == "cloze" else 400
            resp, handoff = post(base, model, build_messages(it), max_tokens)
            if handoff:
                handoffs += 1
            results.append({"id": it["id"], "response": resp})
            print(f"[{suite} {i}/{len(items)}] {it['id']}: {resp[:70]!r}")
        out = ROOT / "results" / f"{args.out_prefix}_{suite}.responses.json"
        out.write_text(json.dumps({"model": model, "runtime": args.runtime, "results": results},
                                  ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"wrote {out}  ({len(items)} items, {time.time()-t0:.0f}s)")
    if handoffs:
        print(f"WARNING: {handoffs} responses reported a cloud handoff — not fully local!")
    else:
        print("all responses fully on-device (no cloud handoff).")


if __name__ == "__main__":
    main()
