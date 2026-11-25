#!/usr/bin/env bash
# Convert every pulled raw GLB into judge render + USDZ, at the heights from PROPS_PLAN.md.
#
#   tools/genprops/convert_all.sh <dir-with-raw-glbs>
#
# Seed variants (name-sNN-raw.glb) convert under their tagged name; pick the winner by its
# judge render, then rename the chosen one to the plain prop name before rigging.
set -euo pipefail

BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${1:?usage: convert_all.sh <dir>}"

height() {
  case "$1" in
    katze*)   echo 1.2 ;;
    vogel*)   echo 0.7 ;;
    knochen*) echo 0.5 ;;
    napf*)    echo 0.45 ;;
    kissen*)  echo 0.4 ;;
    sofa*)    echo 1.1 ;;
    huette*)  echo 1.5 ;;
    baum*)    echo 1.9 ;;
    hund*|dog*) echo 1.4 ;;
    gift*|geschenk*) echo 1.2 ;;
    *)        echo 1.4 ;;
  esac
}

for glb in "$DIR"/*-raw.glb; do
  name="$(basename "$glb" -raw.glb)"
  "$BLENDER" --background --python "$ROOT/tools/genprops/convert_prop.py" -- \
    --glb "$glb" --name "$name" --height "$(height "$name")" --out-dir "$DIR" \
    2>&1 | grep -E "CONVERTED|Traceback" | head -2
done
echo "ALL_CONVERTED"
