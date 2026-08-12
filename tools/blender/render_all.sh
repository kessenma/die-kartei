#!/usr/bin/env bash
#
# Regenerate every preposition asset the app ships. One command, so the rendered set can never
# drift from `prep_render.py` without someone noticing.
#
#   tools/blender/render_all.sh
#
# What ships, and why it is only this:
#   - `dim` renders only. `flat` existed for 34pt row icons, which we never built — dimensional
#     shading muds below ~40pt, so small surfaces use SF Symbols instead.
#   - two-way prepositions get neutral + akk + dat (the card back shows both poses side by side).
#   - fixed-case prepositions get neutral + dat only; they have one pose, so an `akk` render
#     would be a byte-for-byte duplicate.
#   - one USDZ per relation, carrying the resting pose; the app lifts and tints it at runtime.

set -euo pipefail

BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RIG="$ROOT/tools/blender/prep_render.py"
DEST="$ROOT/german-ai-flashcards/Resources"
SIZE="${SIZE:-512}"

# `wohinwo` is the synthetic rules-sheet demo — not a real preposition, but it ships
# three states like the two-way words it explains.
TWO_WAY=(auf in unter über neben zwischen an vor hinter entlang wohinwo)
FIXED=(durch um gegen bis aus bei mit nach zu von gegenüber für ohne außer seit statt trotz während wegen innerhalb außerhalb oberhalb unterhalb diesseits jenseits beiderseits)

ascii() { printf '%s' "$1" | sed 's/ü/ue/g; s/ö/oe/g; s/ä/ae/g; s/ß/ss/g'; }

render() { # word state
  local out; out="$DEST/prep3d-$(ascii "$1")-$2-dim.png"
  "$BLENDER" --background --python "$RIG" -- \
    --prep "$1" --state "$2" --look dim --size "$SIZE" --out "$out" >/dev/null 2>&1
}

echo "Clearing old assets…"
rm -f "$DEST"/prep3d-*

for word in "${TWO_WAY[@]}"; do
  echo "  $word (neutral, akk, dat)"
  for state in neutral akk dat; do render "$word" "$state"; done
done

for word in "${FIXED[@]}"; do
  echo "  $word (neutral, dat)"
  for state in neutral dat; do render "$word" "$state"; done
done

# Exported from the *neutral* pose, which means no arrow geometry. Arrows are a still-image
# affordance — a picture that can't move has to say "moving" somehow — but the live scene shows
# motion by actually moving. Baking one in would also leak a motion cue (and so the Akkusativ)
# onto the question side, where the whole point is that the case is withheld.
echo "Exporting USDZ…"
for word in "${TWO_WAY[@]}" "${FIXED[@]}"; do
  "$BLENDER" --background --python "$RIG" -- \
    --prep "$word" --state neutral --look dim --usdz \
    --out "$DEST/prep3d-$(ascii "$word").usdz" >/dev/null 2>&1
done

"$BLENDER" --background --python "$RIG" -- \
  --manifest --out "$DEST/prep3d-manifest.json" >/dev/null 2>&1

# A render proves the picture; only this proves the file. Subject prim present, zero
# stowaway cameras/lights, and any baked animation restricted to whitelisted ambient prims
# (checked against the .usda twin — see verify() in prep_render.py).
echo "Verifying USDZ…"
failures=0
for word in "${TWO_WAY[@]}" "${FIXED[@]}"; do
  if ! "$BLENDER" --background --python-exit-code 1 --python "$RIG" -- \
      --verify "$DEST/prep3d-$(ascii "$word").usdz" 2>/dev/null \
      | grep -E "^(VERIFY|  result)"; then
    failures=$((failures + 1))
  fi
done

echo
echo "PNG:  $(ls "$DEST"/prep3d-*.png | wc -l | tr -d ' ')"
echo "USDZ: $(ls "$DEST"/prep3d-*.usdz | wc -l | tr -d ' ')"
echo "Size: $(du -ch "$DEST"/prep3d-* | tail -1 | cut -f1)"
if [ "$failures" -gt 0 ]; then
  echo "VERIFY: $failures scene(s) FAILED (full detail: re-run --verify without the grep)"
  exit 1
fi
