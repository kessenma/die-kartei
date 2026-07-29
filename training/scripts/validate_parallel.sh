#!/bin/zsh
# Run validate_data.py across N workers and merge the results.
#
# validate_data.py is ~0.5 rows/sec — LanguageTool is an HTTP round-trip per row, and spaCy parses
# every gold sentence. Serial validation of a 61k-row corpus is ~34 hours; six workers bring that
# to ~6. Each worker starts its own LanguageTool JVM (~1.5 GB), so keep WORKERS well under
# RAM_GB/2.
#
# Cross-chunk duplicates survive (each worker has its own `seen` set), which is fine:
# pack_dataset.py does a global dedup pass anyway.
#
# Usage: scripts/validate_parallel.sh <input.jsonl> <out-dir> [workers]
set -u
IN="$1"; OUT="$2"; WORKERS="${3:-6}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STEM="$(basename "${IN%.jsonl}")"
WORK="$OUT/_chunks"
mkdir -p "$WORK"

TOTAL=$(wc -l < "$IN" | tr -d ' ')
PER=$(( (TOTAL + WORKERS - 1) / WORKERS ))
echo "$(date) splitting $TOTAL rows into $WORKERS chunks of $PER"
split -l "$PER" "$IN" "$WORK/part_"

pids=()
for f in "$WORK"/part_*; do
  [ -f "$f" ] || continue
  mv "$f" "$f.jsonl"
  "$ROOT/.venv/bin/python" "$ROOT/scripts/validate_data.py" "$f.jsonl" --out-dir "$WORK" \
      > "$f.log" 2>&1 &
  pids+=($!)
  echo "  worker $! -> $(basename $f).jsonl"
done

echo "$(date) waiting for ${#pids[@]} workers..."
for p in $pids; do wait $p; done

echo "$(date) merging"
cat "$WORK"/part_*.valid.jsonl    > "$OUT/$STEM.valid.jsonl"    2>/dev/null
cat "$WORK"/part_*.rejected.jsonl > "$OUT/$STEM.rejected.jsonl" 2>/dev/null
V=$(wc -l < "$OUT/$STEM.valid.jsonl" | tr -d ' ')
R=$(wc -l < "$OUT/$STEM.rejected.jsonl" | tr -d ' ')
echo "$(date) DONE valid=$V rejected=$R  pass_rate=$(( V * 100 / (V + R) ))%"
echo "VALIDATION_COMPLETE"
