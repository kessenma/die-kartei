#!/usr/bin/env python3
"""Re-score every model the app ships, guarded (app-equivalent), from its SAVED raw responses.

Why this exists
---------------
The app's copy quotes guarded scores for the two tutors and raw scores for every stock model, in
the same sentences, as if they were comparable. They aren't: the guard mirrors
`ConversationPrompts.parseCorrection`, and for a model that answers "OK\\nFIX: ..." it is the
difference between a scored pass and the learner being shown nothing at all. Gemma 3 1B's shipped
"58%" was exactly that artifact.

No GPU, no model loads, no downloads. Raw generations are the durable artifact; scores are derived
and must be treated as cache (training-v2.md §3.2).

Match the suite by item ID, never by filename
---------------------------------------------
`results/baseline_gemma-4-e4b-it-4bit.json` holds 61 items beginning at `wo-e1` — i.e. *extension*
results under a filename that reads like core. Scoring a responses file against the wrong suite
does not fail loudly: unmatched IDs become empty strings, the guard turns an empty string into
"OK", and the model silently scores as if it had rubber-stamped everything. So this script
identifies each file's suite from its own IDs and refuses anything that doesn't cover one exactly.

Usage:  .venv/bin/python scripts/rescore_app_models.py
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from run_baseline_eval import apply_app_guard, score, strip_channels, summarize  # noqa: E402

ROOT = Path(__file__).parent.parent
RESULTS = ROOT / "results"
SUITES = {
    "v0": ROOT / "data/eval/grammar_eval_v0.json",
    "v1ext": ROOT / "data/eval/grammar_eval_v1_extra.json",
    "v2": ROOT / "data/eval/grammar_eval_v2_holdout.json",
}

# Every model the app can actually select, plus the two reference points the copy compares against
# (stock E4B, stock Granite). Value is the display name used in the output table.
APP_MODELS = {
    "gemma4-e4b-german-v2-4bit": "E4B German Tutor (v2, shipping)",
    "gemma4-e4b-german-tutor-4bit": "E4B German Tutor (v1, shipped)",
    "gemma4-e2b-german-tutor-4bit": "E2B German Tutor (shipped)",
    "granite33-2b-r32-4bit": "Granite 3.3 2B (tuned r=32)",
    "gemma-4-e4b-it-4bit": "Gemma 4 E4B (stock, untuned)",
    "gemma-3-1b-it-qat-4bit": "Gemma 3 1B",
    "Qwen3-8B-4bit": "Qwen3 8B",
    "Qwen3-4B-4bit": "Qwen3 4B",
    "Phi-4-mini-instruct-4bit": "Phi-4 Mini",
    "Mistral-7B-Instruct-v0.3-4bit": "Mistral 7B",
    "Llama-3.2-1B-Instruct-4bit": "LLaMA 3.2 1B",
    "apple-intelligence": "Apple Intelligence",
    "granite-3.3-2b-instruct-4bit": "Granite 3.3 2B (stock)",
}


def load_suites():
    out = {}
    for key, path in SUITES.items():
        items = json.loads(path.read_text())["items"]
        out[key] = {"items": items, "ids": {i["id"] for i in items}}
    return out


def identify_suite(resp_ids, suites):
    """Which suite this responses file covers, or None. Requires the file to contain a response
    for every item in the suite — a partial overlap is a mismatch, not a suite."""
    for key, suite in suites.items():
        if suite["ids"] <= resp_ids:
            return key
    return None


def main():
    suites = load_suites()
    # model -> suite -> (passed, total, format_errors, results)
    scored: dict[str, dict[str, tuple]] = {}
    skipped = []

    for path in sorted(RESULTS.glob("*.json")):
        if path.name.startswith("guarded-"):
            continue  # our own output
        try:
            payload = json.loads(path.read_text())
        except Exception:
            continue
        if not isinstance(payload, dict) or "results" not in payload:
            continue
        rows = payload["results"]
        if not isinstance(rows, list) or not rows or "response" not in rows[0]:
            continue

        shortname = next((m for m in APP_MODELS if path.stem.endswith(m)), None)
        if shortname is None:
            continue

        resp_map = {r["id"]: r["response"] for r in rows}
        suite_key = identify_suite(set(resp_map), suites)
        if suite_key is None:
            skipped.append((path.name, len(resp_map)))
            continue

        items = suites[suite_key]["items"]
        results = []
        for item in items:
            raw = strip_channels(resp_map[item["id"]])
            r = score(item, apply_app_guard(raw, item))
            r["response"] = raw
            results.append(r)

        summary = summarize(results)
        passed, total = map(int, summary["overall"].split("/"))
        prev = scored.setdefault(shortname, {})
        # A model can have several files per suite (re-runs). Keep the one with the most items
        # scored; on a tie keep the first, which is deterministic across runs.
        if suite_key not in prev or total > prev[suite_key][1]:
            prev[suite_key] = (passed, total, summary.get("format_errors", 0), results, path.name)
            out = RESULTS / f"guarded-{suite_key}_{shortname}.json"
            out.write_text(json.dumps(
                {"model": shortname, "app_guard": True, "suite": suite_key,
                 "source_responses": path.name, "summary": summary, "results": results},
                ensure_ascii=False, indent=1), encoding="utf-8")

    # ---- report ----
    print(f"{'model':32s} {'core (v0)':>14s} {'ext (v1)':>14s} {'holdout (v2)':>14s}")
    print("-" * 78)
    for shortname, label in APP_MODELS.items():
        s = scored.get(shortname, {})

        def cell(k):
            if k not in s:
                return "-"
            p, t, _, _, _ = s[k]
            return f"{p}/{t} ({round(100 * p / t)}%)"

        print(f"{label:32s} {cell('v0'):>14s} {cell('v1ext'):>14s} {cell('v2'):>14s}")

    print("\nsources used:")
    for shortname, s in scored.items():
        for k, v in sorted(s.items()):
            print(f"  {shortname:32s} {k:6s} <- {v[4]}")

    if skipped:
        print("\nskipped (IDs match no suite completely):")
        for name, n in skipped:
            print(f"  {name} ({n} responses)")


if __name__ == "__main__":
    main()
