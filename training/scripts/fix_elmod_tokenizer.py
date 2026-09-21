#!/usr/bin/env python3
"""Repair ELMOD-2.7B's tokenizer: register <|im_start|> (5) and <|im_end|> (6) as special.

THE BUG (in fraunhofer-iis/elmod-2.7b-it itself, not in mlx_lm)
--------------------------------------------------------------
`tokenizer.json` registers 1515 added tokens — ids 0-4 and 7 onward. Ids **5 and 6 are
missing**, and those two are the *only* control tokens the model's own
`chat_template.jinja` emits.

Both tokens do exist in the base vocab (`decode([6]) == '<|im_end|>'`), which is why
`convert_tokens_to_ids('<|im_end|>')` returns 6 and the check looks fine. But because they
are not *added* tokens, the encoder never produces them from text:

    encode('<|im_end|>')  ->  [1537, 1601, 2085, 15761, 1601, 1539]   # six literal pieces

So `apply_chat_template` renders correct ChatML text and then tokenizes it into literal
characters. The model is fed a prompt in a format it was never trained on, generation never
emits id 6, and every completion runs to max_tokens and rolls into unrelated pretraining
documents (verified: ELMOD's own default system prompt, then a vape-pen listicle).

Measuring the model in that state measures the tokenizer bug. This script registers the two
tokens at their existing vocab ids so the rendered template encodes to real control tokens.
No vocab entries are added and no ids shift — `vocab_size` is unchanged at 65024.

Usage (from training/):
  .venv/bin/python scripts/fix_elmod_tokenizer.py models/elmod-2.7b-it-4bit
"""
import json
import shutil
import sys
from pathlib import Path

MISSING = [(5, "<|im_start|>"), (6, "<|im_end|>")]


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().splitlines()[-1])
    model_dir = Path(sys.argv[1])
    tj_path = model_dir / "tokenizer.json"
    if not tj_path.exists():
        sys.exit(f"no tokenizer.json in {model_dir}")

    backup = tj_path.with_suffix(".json.orig")
    if not backup.exists():
        shutil.copy2(tj_path, backup)
        print(f"backed up original -> {backup.name}")

    tj = json.loads(backup.read_text())
    added = tj.get("added_tokens", [])
    have = {a["id"] for a in added}
    vocab = tj["model"]["vocab"]

    for tid, content in MISSING:
        if tid in have:
            print(f"id {tid} ({content}) already registered — nothing to do")
            continue
        # The token must already occupy this vocab slot; we are only marking it special.
        assert vocab.get(content) == tid, (
            f"expected {content!r} at vocab id {tid}, found {vocab.get(content)!r} — "
            "the checkpoint is not the one this fix was written for"
        )
        added.append({
            "id": tid,
            "content": content,
            "single_word": False,
            "lstrip": False,
            "rstrip": False,
            "normalized": False,
            "special": True,
        })
        print(f"registered id {tid} as special: {content}")

    tj["added_tokens"] = sorted(added, key=lambda a: a["id"])
    tj_path.write_text(json.dumps(tj, ensure_ascii=False))

    # Verify by round-tripping through the real tokenizer.
    from transformers import AutoTokenizer

    AutoTokenizer.register = lambda *a, **k: None
    tok = AutoTokenizer.from_pretrained(str(model_dir))
    for tid, content in MISSING:
        ids = tok.encode(content, add_special_tokens=False)
        status = "OK" if ids == [tid] else "STILL BROKEN"
        print(f"  encode({content!r}) -> {ids}   [{status}]")
        if ids != [tid]:
            sys.exit(1)
    print(f"  vocab_size still {tok.vocab_size} (unchanged)")


if __name__ == "__main__":
    main()
