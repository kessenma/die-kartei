#!/bin/sh
# Compiles the real worksheet parser against a PDF and prints how each page read.
# See the usage comment in scripts/worksheet_probe.swift. Uses Xcode's toolchain, like
# scripts/vocab_sheet_probe.sh.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
cp "$root/scripts/worksheet_probe.swift" "$out/main.swift"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swiftc -O \
    -o "$out/probe" \
    "$root/german-ai-flashcards/Services/Worksheet/WorksheetParser.swift" \
    "$root/german-ai-flashcards/Services/Worksheet/WorksheetPDFReader.swift" \
    "$root/german-ai-flashcards/Services/Worksheet/WorksheetKeyReader.swift" \
    "$root/german-ai-flashcards/Services/Worksheet/KeyPhraseExtractor.swift" \
    "$root/german-ai-flashcards/Services/CardKind.swift" \
    "$out/main.swift"
"$out/probe" "$@"
