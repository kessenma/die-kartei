#!/usr/bin/env bash
#
# Regenerate the Bauhaus figure: every judge render, every scratch part, and the one asset that
# ships. One command, so the shipped USDZ can never drift from `figur.py` without someone
# noticing.
#
#   tools/blender/figur_all.sh
#
# What goes where, and why:
#   - Judge renders and per-part USDZs land in tools/blender/renders/figur/ — scratch, for
#     tuning proportions and for opening a single part in QuickLook. Nothing there ships.
#   - Only the assembled rest pose reaches Resources/, exported at low LOD. Parts do not ship:
#     the app loads one figure and addresses its six named prims inside it.
#   - The renders are the tuning surface. Edit the PRESETS table in figur.py, re-run this, look
#     at figur-contact.png. To isolate one number instead, use --sweep (see figur.py).
#
# This clears only `figur-*`. render_all.sh clears only `prep3d-*`, so the two asset sets can be
# regenerated in any order without touching each other.

set -euo pipefail

BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RIG="$ROOT/tools/blender/figur.py"
SCRATCH="$ROOT/tools/blender/renders/figur"
DEST="$ROOT/german-ai-flashcards/Resources"
PRESET="${PRESET:-standard}"
HEIGHT="${HEIGHT:-1.8}"

run() { "$BLENDER" --background --python "$RIG" -- "$@" >/dev/null 2>&1; }

echo "Clearing old figure assets…"
rm -rf "$SCRATCH"
rm -f "$DEST"/figur-*.usdz "$DEST"/figur.usdz

echo "  contact sheet (3 presets × 3 angles)"
run --contact --height "$HEIGHT"

echo "  parts (silhouettes + per-part USDZ)"
run --parts --preset "$PRESET" --height "$HEIGHT"

# Against the cast it would join, not against a ruler: the story props are composed rather than
# real-world scaled (the dog sits at 1.4), so the only honest scale test is a lineup.
echo "  scale check vs hund + tisch"
run --scale-check --preset "$PRESET" --height "$HEIGHT" --size 768

echo "  rest pose → Resources/figur.usdz"
run --usdz --preset "$PRESET" --height "$HEIGHT" --out "$DEST/figur.usdz"

# Storyboard + the baked self-assembly clip, plus the plain-text twin the animation check reads.
echo "  aufbau clip → Resources/figur-aufbau.usdz"
run --aufbau --preset "$PRESET" --height "$HEIGHT"

echo
for asset in figur figur-aufbau; do
  "$BLENDER" --background --python "$RIG" -- --verify "$DEST/$asset.usdz" 2>/dev/null \
    | grep -E "^(VERIFY|  )"
  echo
done
echo "Renders: $(ls "$SCRATCH"/*.png | wc -l | tr -d ' ')  ($SCRATCH)"
echo "Shipped: $(du -h "$DEST/figur.usdz" | cut -f1)  $DEST/figur.usdz"
