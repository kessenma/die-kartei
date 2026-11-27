#!/usr/bin/env python3
"""Publish the tutors' GGUF files to Hugging Face (one repo per tutor, next to its MLX repo).

For each tutor: copy the chosen quants under the app's file names with a clean `general.name`,
write a short model card, record size + SHA-256 (the app checks them after a download), upload.

    ~/ws/llama.cpp/.venv/bin/python training/scripts/publish_gguf.py            # all four
    ~/ws/llama.cpp/.venv/bin/python training/scripts/publish_gguf.py --only granite33 --dry-run

Writes training/releases/gguf_release.json (repo, file, bytes, sha256) for the app catalog.
Needs `hf auth login` (a write token).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
SRC = HOME / "ws/models/gguf"
OUT = HOME / "ws/models/gguf-release"
LLAMA = HOME / "ws/llama.cpp"
REPO_ROOT = Path(__file__).resolve().parents[2]
RESULTS = REPO_ROOT / "training/releases/gguf_release.json"

# App-guarded scores out of 203 (core + ext + holdout), see training/ANDROID_GGUF.md.
TUTORS = {
    "e4b": dict(
        src="e4b-v4", repo="kessenma/gemma4-e4b-german-tutor-v4-gguf",
        mlx="kessenma/gemma4-e4b-german-tutor-v4-4bit", stem="gemma4-e4b-german-tutor-v4",
        name="Gemma 4 E4B German Tutor v4", license="gemma", base="google/gemma-4-e4b-it",
        scores={"MLX 4-bit": 182, "Q4_K_M": 185, "Q4_0": 184}, app="Q4_0",
    ),
    "e2b": dict(
        src="e2b-v1", repo="kessenma/gemma4-e2b-german-tutor-gguf",
        mlx="kessenma/gemma4-e2b-german-tutor-4bit", stem="gemma4-e2b-german-tutor",
        name="Gemma 4 E2B German Tutor", license="apache-2.0", base="kessenma/gemma4-e2b-german-tutor",
        scores={"MLX 4-bit": 171, "Q4_K_M": 173, "Q4_0": 169}, app="Q4_K_M",
    ),
    "granite41": dict(
        src="granite41-v4", repo="kessenma/granite41-3b-german-tutor-v4-gguf",
        mlx="kessenma/granite41-3b-german-tutor-v4-4bit", stem="granite41-3b-german-tutor-v4",
        name="Granite 4.1 3B German Tutor v4", license="apache-2.0", base="ibm-granite/granite-4.1-3b",
        scores={"MLX 4-bit": 164, "Q4_K_M": 164, "Q4_0": 160}, app="Q4_K_M",
    ),
    "granite33": dict(
        src="granite33-v4", repo="kessenma/granite33-2b-german-tutor-v4-gguf",
        mlx="kessenma/granite33-2b-german-tutor-v4-4bit", stem="granite33-2b-german-tutor-v4",
        name="Granite 3.3 2B German Tutor v4", license="apache-2.0", base="ibm-granite/granite-3.3-2b-instruct",
        scores={"MLX 4-bit": 153, "Q4_K_M": 153, "Q4_0": 148}, app="Q4_K_M",
    ),
}
QUANTS = ["Q4_K_M", "Q4_0"]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 24), b""):
            h.update(block)
    return h.hexdigest()


def release_scores(key: str) -> dict | None:
    """Scores from a release_model.py run, when there is one: {label: total}."""
    path = REPO_ROOT / f"training/releases/release_{key}.json"
    if not path.exists():
        return None
    scores = json.loads(path.read_text())["scores"]
    return {("MLX 4-bit" if k == "MLX" else k): v["total"] for k, v in scores.items()}


def card(t: dict, files: list[dict], from_master: bool) -> str:
    rows = "\n".join(
        f"| `{f['file']}` | {f['bytes'] / 1e9:.1f} GB | {t['scores'][f['quant']]} |"
        + (" used by the app |" if f["quant"] == t["app"] else " |")
        for f in files
    )
    provenance = (
        "The GGUF and MLX files were built from the same bf16 master (training/scripts/release_model.py)."
        if from_master else
        "The GGUF files were made from the 4-bit MLX weights (dequantized to bf16, then quantized) "
        "and scored about the same as MLX."
    )
    return f"""---
license: {t['license']}
base_model: {t['mlx']}
language:
- de
- en
library_name: gguf
tags:
- gguf
- llama.cpp
- german
- language-learning
---

# {t['name']} (GGUF)

The tutor model from the Die Kartei app, for llama.cpp. Same weights as
[`{t['mlx']}`](https://huggingface.co/{t['mlx']}); read that card for what it was trained on
and how the app filters its output.

| File | Size | Score (of 203) | |
|---|---|---|---|
{rows}
| MLX 4-bit, for comparison | | {t['scores']['MLX 4-bit']} | |

Scores are the app's own eval suite (core, extension and held-out sentences), with the app's
output filter on. {provenance}

## Use

The chat template is in the file:

```
llama-server -m {files[0]['file']} --jinja
```

The model expects the app's system prompts; without them it answers like a plain chat model.
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=list(TUTORS), action="append")
    ap.add_argument("--dry-run", action="store_true", help="prepare files and cards, don't upload")
    ap.add_argument("--src-dir", type=Path,
                    help="take <stem>-<quant>.gguf from here (a release_model.py work dir), replacing what's there")
    ap.add_argument("--app-only", action="store_true",
                    help="upload only the quant the app uses (the rest in a later run)")
    args = ap.parse_args()

    from huggingface_hub import HfApi
    api = HfApi()
    release = json.loads(RESULTS.read_text()) if RESULTS.exists() else {}

    for key in args.only or list(TUTORS):
        t = dict(TUTORS[key])
        scores = release_scores(key) if args.src_dir else None
        if scores:
            t["scores"] = scores
        folder = OUT / t["repo"].split("/")[1]
        folder.mkdir(parents=True, exist_ok=True)
        files = []
        for quant in QUANTS:
            dst = folder / f"{t['stem']}-{quant}.gguf"
            if args.src_dir:
                src = args.src_dir / dst.name
                if not dst.exists() or not os.path.samefile(src, dst):
                    print(f"{key}: taking {src}", flush=True)
                    dst.unlink(missing_ok=True)
                    os.link(src, dst)   # same disk: no copy
                    release.pop(dst.name, None)
            elif not dst.exists():
                src = SRC / f"{t['src']}-{quant}.gguf"
                print(f"{key}: writing {dst.name}", flush=True)
                subprocess.run(
                    [sys.executable, str(LLAMA / "gguf-py/gguf/scripts/gguf_new_metadata.py"),
                     "--force", "--general-name", t["name"], str(src), str(dst)],
                    check=True, stdout=subprocess.DEVNULL,
                )
            entry = release.get(dst.name)
            if not entry or entry["bytes"] != dst.stat().st_size:
                print(f"{key}: hashing {dst.name}", flush=True)
                entry = dict(repo=t["repo"], file=dst.name, quant=quant,
                             bytes=dst.stat().st_size, sha256=sha256(dst))
                release[dst.name] = entry
                RESULTS.write_text(json.dumps(release, indent=2) + "\n")
            files.append(entry)
        (folder / "README.md").write_text(card(t, files, from_master=bool(args.src_dir)))
        if args.dry_run:
            print(f"{key}: ready in {folder} (dry run)")
            continue
        api.create_repo(t["repo"], repo_type="model", exist_ok=True)
        if args.app_only:
            files = [f for f in files if f["quant"] == t["app"]]
        print(f"{key}: uploading {', '.join(f['file'] for f in files)} to {t['repo']}", flush=True)
        api.upload_folder(repo_id=t["repo"], folder_path=str(folder),
                          allow_patterns=["README.md"] + [f["file"] for f in files],
                          commit_message=f"{t['name']}: GGUF {', '.join(f['quant'] for f in files)}")
        # Check what landed: sizes and hashes as Hugging Face reports them.
        info = {s.rfilename: s for s in api.model_info(t["repo"], files_metadata=True).siblings}
        for f in files:
            s = info.get(f["file"])
            ok = s and s.size == f["bytes"] and s.lfs and s.lfs.sha256 == f["sha256"]
            print(f"{key}: {f['file']} {'verified' if ok else 'MISMATCH'}", flush=True)
            if not ok:
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
