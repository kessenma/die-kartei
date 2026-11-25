#!/usr/bin/env python3
"""Extract the final JSONL batch from a generation subagent's transcript file.

Usage: extract_batch.py <agent-transcript.jsonl> <out.jsonl>
Takes the last assistant text block, keeps lines that parse as JSON objects.
"""

import json
import sys
from pathlib import Path


def main() -> None:
    transcript, out = Path(sys.argv[1]), Path(sys.argv[2])
    last_text = None
    for line in transcript.read_text().splitlines():
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = obj.get("message") or {}
        if msg.get("role") == "assistant":
            for block in msg.get("content", []):
                if isinstance(block, dict) and block.get("type") == "text":
                    last_text = block["text"]
    if not last_text:
        sys.exit("no assistant text found in transcript")

    rows, bad = [], 0
    for line in last_text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            json.loads(line)
            rows.append(line)
        except json.JSONDecodeError:
            bad += 1
    out.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"wrote {len(rows)} lines to {out}" + (f" ({bad} unparseable dropped)" if bad else ""))


if __name__ == "__main__":
    main()
