#!/bin/bash
# Builds hoeren-cli: the app's Worum geht's? judge prompt and parser as a Mac tool, for the gist
# probe (training/GIST_PROBE.md). Compiles the app's own sources (sources.txt) with the app
# target's Swift settings. FoundationModels is linked, so `fm-run` judges with Apple Intelligence.
#
#   training/hoeren_cli/build.sh            # -> training/hoeren_cli/build/hoeren-cli
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/../../german-ai-flashcards" && pwd)"
OUT="$HERE/build"
mkdir -p "$OUT"

SOURCES=()
while IFS= read -r line; do
  line="${line%%#*}"; line="$(echo "$line" | xargs)"
  [ -n "$line" ] && SOURCES+=("$APP/$line")
done < "$HERE/sources.txt"

xcrun --sdk macosx swiftc -O -swift-version 5 -target arm64-apple-macos26.2 \
  -default-isolation MainActor \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -module-name HoerenCLI \
  "${SOURCES[@]}" "$HERE/main.swift" \
  -o "$OUT/hoeren-cli"
echo "built $OUT/hoeren-cli"
