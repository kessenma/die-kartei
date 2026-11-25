#!/usr/bin/env bash
#
# Land rendered Bauhaus icons in the asset catalog. The renders and the app were previously
# joined by hand, which is exactly the kind of step that silently half-happens.
#
#   tools/blender/install_icons.sh                  # every rendered icon
#   tools/blender/install_icons.sh wegweiser …      # just these slugs
#
# Each icon becomes one `pyramid-icon-<slug>` image set with an Any + Dark appearance pair, the
# structure `BauhausIcon` expects. An icon with no image set falls back to its SF Symbol, so a
# partial install is safe — and deleting an image set is a full rollback.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/tools/blender/renders/icons"
DEST="$ROOT/german-ai-flashcards/Assets.xcassets"

if [ $# -gt 0 ]; then
  slugs=("$@")
else
  slugs=()
  for f in "$SRC"/pyramid-icon-*-light.png; do
    name="$(basename "$f")"; name="${name#pyramid-icon-}"
    slugs+=("${name%-light.png}")
  done
fi

installed=0
for slug in "${slugs[@]}"; do
  light="$SRC/pyramid-icon-$slug-light.png"
  dark="$SRC/pyramid-icon-$slug-dark.png"
  if [ ! -f "$light" ] || [ ! -f "$dark" ]; then
    echo "  skip $slug (missing light and/or dark render)"
    continue
  fi

  set_dir="$DEST/pyramid-icon-$slug.imageset"
  mkdir -p "$set_dir"
  cp "$light" "$set_dir/light.png"
  cp "$dark" "$set_dir/dark.png"
  cat > "$set_dir/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "light.png",
      "idiom" : "universal"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "dark.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
  echo "  $slug"
  installed=$((installed + 1))
done

echo
echo "Installed $installed image set(s) into Assets.xcassets."
