#!/usr/bin/env python3
"""Release one tutor from its bf16/fp16 master: MLX 4-bit (iOS) and GGUF (Android) from the same
weights, both scored on the app's eval with the app's guard, compared item by item.

    ~/ws/llama.cpp/.venv/bin/python training/scripts/release_model.py --tutor granite33 \\
        --master kessenma/granite33-2b-german-v4-fp16 [--upload]

Steps (each skipped when its output already exists in the work dir, so a rerun resumes):
  1. fetch the master (HF repo or local dir)
  2. MLX 4-bit, group 64 (mlx_vlm for Gemma 4, which keeps the vision/audio towers like the
     published repos; mlx_lm otherwise), compared tensor by tensor with the published MLX repo
  3. GGUF: bf16, then each quant (publish_gguf.QUANTS), named for the catalog
  4. eval: every format on core + ext + holdout (/203); GGUF through llama-server, MLX in-process
  5. gate: fails when a GGUF quant is clearly worse than MLX (McNemar p < 0.05 against it, or
     more than 6 items behind), or any format has format errors
  6. writes releases/release_<tutor>.json and a row in MODEL_SCOREBOARD.md
  7. --upload: the GGUFs (publish_gguf.py), and the MLX build only if it differs from the
     published one; prints the catalog entry for MLXModel+Catalog.swift

Needs: ~/ws/llama.cpp (built, with its convert venv), ~/ws/models/.venv-mlx, `hf auth login`.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
TRAINING = HERE.parent
sys.path.insert(0, str(HERE))
import publish_gguf  # noqa: E402  (TUTORS, QUANTS, sha256)
from run_baseline_eval import apply_app_guard, score, strip_channels, summarize  # noqa: E402

HOME = Path.home()
LLAMA = HOME / "ws/llama.cpp"
CONVERT_PY = LLAMA / ".venv/bin/python"
MLX_PY = HOME / "ws/models/.venv-mlx/bin/python"
WORK_ROOT = HOME / "ws/models/release"
SUITES = {
    "core": TRAINING / "data/eval/grammar_eval_v0.json",
    "ext": TRAINING / "data/eval/grammar_eval_v1_extra.json",
    "holdout": TRAINING / "data/eval/grammar_eval_v2_holdout.json",
}
PORT = 8899
MAX_BEHIND = 6


def run(cmd: list, **kw) -> None:
    print("$ " + " ".join(str(c) for c in cmd), flush=True)
    subprocess.run([str(c) for c in cmd], check=True, **kw)


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# ---------------------------------------------------------------- 1-3: builds

def fetch_master(master: str, work: Path) -> Path:
    if Path(master).expanduser().is_dir():
        return Path(master).expanduser()
    from huggingface_hub import snapshot_download
    dest = work / "master"
    log(f"fetching {master}")
    snapshot_download(master, local_dir=dest,
                      allow_patterns=["*.json", "*.jinja", "*.safetensors", "*.model", "*.txt"])
    return dest


def prepare_master(master: Path, work: Path, published_mlx: str) -> Path:
    """The master as the converters need it. Masters saved by transformers 5 keep RoPE only in
    `rope_parameters`; mlx_lm's Granite (and older llama.cpp paths) read `rope_theta`. Keys the
    published MLX config has and the master lacks are filled in from it, in a copy of the config
    next to symlinked weights; the master itself is never changed."""
    from huggingface_hub import hf_hub_download
    config = json.loads((master / "config.json").read_text())
    published = json.loads(Path(hf_hub_download(published_mlx, "config.json")).read_text())
    missing = {k: v for k, v in published.items()
               if k not in config and not k.startswith("quantization")}
    rope = config.get("rope_parameters") or {}
    if "rope_theta" not in config and "rope_theta" in rope:
        missing["rope_theta"] = rope["rope_theta"]
    if not missing:
        return master
    log(f"master config: adding {sorted(missing)} ({missing.get('rope_theta', '')})")
    fixed = work / "master-config-fixed"
    fixed.mkdir(exist_ok=True)
    for f in master.iterdir():
        link = fixed / f.name
        if f.name != "config.json" and not link.exists():
            link.symlink_to(f.resolve())
    (fixed / "config.json").write_text(json.dumps({**config, **missing}, indent=2))
    return fixed


def model_type(master: Path) -> str:
    return json.loads((master / "config.json").read_text()).get("model_type", "")


def build_mlx(master: Path, work: Path, published_mlx: str) -> Path:
    """4-bit, group 64, the way the published repo was quantized. Newer mlx_lm keeps Granite's
    o_proj/down_proj at 8 bits by default (5.8 bits per weight); when the published config has no
    per-layer overrides, every layer is forced to 4 bits so the build matches what iOS ships."""
    out = work / "mlx-4bit"
    if (out / "config.json").exists():
        return out
    from huggingface_hub import hf_hub_download
    published = json.loads(Path(hf_hub_download(published_mlx, "config.json")).read_text())
    uniform = not any(isinstance(v, dict) for v in published.get("quantization", {}).values())
    tool = "mlx_vlm" if model_type(master).startswith("gemma") else "mlx_lm"
    log(f"MLX 4-bit with {tool}{', every layer 4-bit' if uniform else ''}")
    tmp = work / "mlx-4bit.partial"
    shutil.rmtree(tmp, ignore_errors=True)
    if tool == "mlx_lm":
        predicate = "(lambda *a, **k: True)" if uniform else "None"
        run([MLX_PY, "-c", "from mlx_lm import convert; "
             f"convert(hf_path={str(master)!r}, mlx_path={str(tmp)!r}, quantize=True, q_bits=4, "
             f"q_group_size=64, quant_predicate={predicate})"])
    else:
        run([MLX_PY, "-m", "mlx_vlm", "convert", "--hf-path", master, "--mlx-path", tmp,
             "-q", "--q-bits", "4", "--q-group-size", "64"])
    tmp.rename(out)
    return out


def compare_mlx(built: Path, published_repo: str) -> dict:
    """Tensor-by-tensor comparison with the published MLX repo (run in the MLX venv)."""
    code = f"""
import json, glob, mlx.core as mx
from huggingface_hub import snapshot_download
pub = snapshot_download({published_repo!r}, allow_patterns=["*.safetensors"])
def load(d):
    out = {{}}
    for f in sorted(glob.glob(d + "/*.safetensors")):
        out.update(mx.load(f))
    return out
a, b = load({str(built)!r}), load(pub)
diff = [k for k in a if k not in b or a[k].shape != b[k].shape or not mx.array_equal(a[k], b[k]).item()]
print(json.dumps({{"tensors": len(a), "published_tensors": len(b),
                  "only_published": len([k for k in b if k not in a]), "differing": len(diff),
                  "examples": diff[:5]}}))
"""
    out = subprocess.run([str(MLX_PY), "-c", code], check=True, capture_output=True, text=True).stdout
    result = json.loads(out.strip().splitlines()[-1])
    result["identical"] = result["differing"] == 0 and result["only_published"] == 0
    return result


def build_gguf(master: Path, work: Path, t: dict) -> dict[str, Path]:
    bf16 = work / f"{t['stem']}-bf16.gguf"
    if not bf16.exists():
        log("GGUF bf16")
        tmp = bf16.with_suffix(".partial")   # an interrupted run never leaves a half file behind
        run([CONVERT_PY, LLAMA / "convert_hf_to_gguf.py", master, "--outtype", "bf16",
             "--model-name", t["name"], "--outfile", tmp])
        tmp.rename(bf16)
    files = {}
    for quant in publish_gguf.QUANTS:
        out = work / f"{t['stem']}-{quant}.gguf"
        if not out.exists():
            log(f"GGUF {quant}")
            tmp = out.with_suffix(".partial")
            run([LLAMA / "build/bin/llama-quantize", bf16, tmp, quant], stdout=subprocess.DEVNULL)
            tmp.rename(out)
        files[quant] = out
    return files


# ---------------------------------------------------------------- 4: eval

def items(suite: str) -> list[dict]:
    return json.loads(SUITES[suite].read_text())["items"]


def score_responses(responses: dict[str, str]) -> dict:
    results = []
    for suite in SUITES:
        for item in items(suite):
            raw = strip_channels(responses.get(item["id"], ""))
            r = score(item, apply_app_guard(raw, item))
            r["response"] = raw
            results.append(r)
    s = summarize(results)
    return {"total": sum(1 for r in results if r["pass"]), "of": len(results),
            "format_errors": s["format_errors"],
            "passed": {r["id"]: bool(r["pass"]) for r in results}}


def eval_gguf(path: Path, label: str, work: Path) -> dict:
    cache = work / f"eval_{label}.json"
    if cache.exists():
        return json.loads(cache.read_text())
    log(f"eval {label}")
    server = subprocess.Popen(
        [str(LLAMA / "build/bin/llama-server"), "-m", str(path), "--host", "127.0.0.1", "--port", str(PORT),
         "-c", "4096", "-ngl", "99", "--jinja", "--parallel", "1"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(120):
            try:
                with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
                    if r.status == 200:
                        break
            except Exception:
                time.sleep(1)
        prefix = f"release_{work.name}_{label}"
        run([sys.executable, HERE / "gen_cactus_responses.py", "--port", PORT, "--out-prefix", prefix,
             "--runtime", f"llama.cpp-{label}", "--suites", ",".join(SUITES)], stdout=subprocess.DEVNULL)
    finally:
        server.terminate()
        server.wait()
    responses = {}
    for suite in SUITES:
        payload = json.loads((TRAINING / f"results/{prefix}_{suite}.responses.json").read_text())
        responses.update({r["id"]: r["response"] for r in payload["results"]})
    result = score_responses(responses)
    cache.write_text(json.dumps(result, indent=1))
    return result


def eval_mlx(path: Path, work: Path) -> dict:
    """Generates with the same prompts and greedy decoding as run_baseline_eval.py's MLX path."""
    cache = work / "eval_mlx.json"
    if cache.exists():
        return json.loads(cache.read_text())
    log("eval MLX")
    out = work / "mlx_responses.json"
    code = f"""
import json, sys
sys.path.insert(0, {str(HERE)!r})
from transformers import AutoTokenizer
_reg = AutoTokenizer.register
def _safe(*a, **k):
    try: _reg(*a, **k)
    except Exception: pass
AutoTokenizer.register = _safe
from mlx_lm import load, generate
from run_baseline_eval import build_messages, strip_channels
model, tok = load({str(path)!r})
out = {{}}
for suite in {[str(p) for p in SUITES.values()]!r}:
    for item in json.load(open(suite))["items"]:
        m = build_messages(item)
        try:
            prompt = tok.apply_chat_template(m, add_generation_prompt=True, enable_thinking=False)
        except Exception:
            merged = [{{"role": "user", "content": m[0]["content"] + "\\n\\n" + m[1]["content"]}}]
            prompt = tok.apply_chat_template(merged, add_generation_prompt=True, enable_thinking=False)
        n = 150 if item["mode"] == "cloze" else 400
        out[item["id"]] = strip_channels(generate(model, tok, prompt=prompt, max_tokens=n, verbose=False))
        print(item["id"], flush=True)
json.dump(out, open({str(out)!r}, "w"), ensure_ascii=False, indent=1)
"""
    subprocess.run([str(MLX_PY), "-c", code], check=True, stdout=subprocess.DEVNULL)
    result = score_responses(json.loads(out.read_text()))
    cache.write_text(json.dumps(result, indent=1))
    return result


def mcnemar(a: dict[str, bool], b: dict[str, bool]) -> tuple[int, int, float]:
    """Exact two-sided McNemar: (only a passes, only b passes, p)."""
    only_a = sum(1 for k in a if a[k] and not b.get(k))
    only_b = sum(1 for k in a if b.get(k) and not a[k])
    n = only_a + only_b
    if n == 0:
        return 0, 0, 1.0
    tail = sum(math.comb(n, i) for i in range(0, min(only_a, only_b) + 1)) / 2 ** n
    return only_a, only_b, min(1.0, 2 * tail)


# ---------------------------------------------------------------- 5-7

def scoreboard_row(t: dict, master: str, scores: dict, mlx_check: dict | None) -> None:
    board = TRAINING / "MODEL_SCOREBOARD.md"
    text = board.read_text()
    heading = "## Release runs (scripts/release_model.py)"
    if heading not in text:
        text = text.rstrip() + (
            f"\n\n{heading}\n\nOne master, every format, the app's guard, /203 (core + ext + holdout). "
            "p is McNemar against MLX.\n\n| date | tutor | master | MLX | "
            + " | ".join(publish_gguf.QUANTS) + " | MLX same as published |\n|---|---|---|---|"
            + "---|" * len(publish_gguf.QUANTS) + "---|\n")
    cells = [f"{scores['MLX']['total']}"]
    for q in publish_gguf.QUANTS:
        s = scores[q]
        cells.append(f"{s['total']} (p={s['p_vs_mlx']:.2f})")
    same = "—" if mlx_check is None else ("yes" if mlx_check["identical"] else f"no ({mlx_check['differing']} tensors)")
    text = text.rstrip() + f"\n| {date.today()} | {t['name']} | `{master}` | " + " | ".join(cells) + f" | {same} |\n"
    board.write_text(text)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tutor", required=True, choices=list(publish_gguf.TUTORS))
    ap.add_argument("--master", required=True, help="HF repo id or local dir of the bf16/fp16 master")
    ap.add_argument("--upload", action="store_true")
    args = ap.parse_args()

    t = publish_gguf.TUTORS[args.tutor]
    work = WORK_ROOT / args.tutor
    work.mkdir(parents=True, exist_ok=True)

    master = prepare_master(fetch_master(args.master, work), work, t["mlx"])
    mlx = build_mlx(master, work, t["mlx"])
    mlx_check_file = work / "mlx_vs_published.json"
    if not mlx_check_file.exists():
        log(f"comparing the MLX build with {t['mlx']}")
        mlx_check_file.write_text(json.dumps(compare_mlx(mlx, t["mlx"]), indent=1))
    mlx_check = json.loads(mlx_check_file.read_text())
    log(f"MLX build vs published: {'identical' if mlx_check['identical'] else mlx_check}")
    ggufs = build_gguf(master, work, t)

    scores = {"MLX": eval_mlx(mlx, work)}
    for quant, path in ggufs.items():
        scores[quant] = eval_gguf(path, quant, work)

    failures = []
    for label, s in scores.items():
        if s["format_errors"]:
            failures.append(f"{label}: {s['format_errors']} format errors")
    for quant in ggufs:
        only_mlx, only_gguf, p = mcnemar(scores["MLX"]["passed"], scores[quant]["passed"])
        scores[quant]["p_vs_mlx"] = p
        behind = scores["MLX"]["total"] - scores[quant]["total"]
        log(f"{quant}: {scores[quant]['total']}/203 vs MLX {scores['MLX']['total']} "
            f"(only MLX {only_mlx}, only GGUF {only_gguf}, p={p:.3f})")
        if behind > MAX_BEHIND or (p < 0.05 and only_mlx > only_gguf):
            failures.append(f"{quant} is clearly worse than MLX ({behind} behind, p={p:.3f})")

    report = {
        "tutor": args.tutor, "master": args.master, "date": str(date.today()),
        "mlx_vs_published": mlx_check,
        "scores": {k: {kk: vv for kk, vv in v.items() if kk != "passed"} for k, v in scores.items()},
        "failures": failures,
    }
    (TRAINING / f"releases/release_{args.tutor}.json").write_text(json.dumps(report, indent=1) + "\n")
    scoreboard_row(t, args.master, scores, mlx_check)
    if failures:
        log("GATE FAILED: " + "; ".join(failures))
        return 1
    log("gate passed")

    if args.upload:
        run([sys.executable, HERE / "publish_gguf.py", "--only", args.tutor, "--src-dir", work])
        if not mlx_check["identical"]:
            from huggingface_hub import HfApi
            log(f"uploading the MLX build to {t['mlx']} (it differs from the published one)")
            HfApi().upload_folder(repo_id=t["mlx"], folder_path=str(mlx),
                                  commit_message=f"{t['name']}: rebuilt from {args.master}")
        release = json.loads(publish_gguf.RESULTS.read_text())
        f = release[f"{t['stem']}-{t['app']}.gguf"]
        print("\nCatalog entry (MLXModel+Catalog.swift):\n"
              f'GGUFRelease(repoID: "{f["repo"]}",\n'
              f'            fileName: "{f["file"]}", quant: "{f["quant"]}", bytes: {f["bytes"]:_},\n'
              f'            sha256: "{f["sha256"]}")')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
