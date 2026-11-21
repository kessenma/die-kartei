#!/bin/bash
# Builds kasus-cli: the app's Kasus story planner, prompt and check as a Mac command-line tool,
# for training data (training/KASUS_STORY_DATA.md). Compiles the app's own sources (sources.txt)
# with the app target's Swift settings, and links the resources the lexicon reads next to the
# binary, where Bundle.main finds them.
#
#   training/kasus_cli/build.sh            # -> training/kasus_cli/build/kasus-cli
#   training/kasus_cli/build/kasus-cli selftest
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

# The app target's settings: Swift 5 mode, MainActor default isolation, approachable concurrency,
# member import visibility. DEBUG compiles the Lab record and the validator fixtures; nothing on
# the check's path depends on it.
xcrun --sdk macosx swiftc -O -swift-version 5 -target arm64-apple-macos26.2 \
  -default-isolation MainActor \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferSendableFromCaptures \
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
  -enable-upcoming-feature DisableOutwardActorInference \
  -D DEBUG \
  -module-name KasusCLI \
  "${SOURCES[@]}" "$HERE/Stubs.swift" "$HERE/concepts.swift" "$HERE/gaps.swift" "$HERE/endings.swift" "$HERE/main.swift" \
  -o "$OUT/kasus-cli"

for resource in wiktionary_de.db a1_vocabulary.json a2_vocabulary.json b1_vocabulary.json \
                kasus_stories.json kasus_concepts.json gap_choice_items.json kasus_triggers.json prepositions.json verb_prepositions.json; do
  ln -sf "$APP/Resources/$resource" "$OUT/$resource"
done
echo "built $OUT/kasus-cli"
