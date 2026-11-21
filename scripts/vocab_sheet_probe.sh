#!/bin/sh
# Compiles the real parser sources against a PDF and prints how each page read.
# See the usage comment in scripts/vocab_sheet_probe.swift. Uses Xcode's toolchain, like
# scripts/sync_core_test.sh: a swiftly toolchain on PATH can't link the macOS SDK here.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
# Top-level code needs the file to be called main.swift when more than one file is compiled.
cp "$root/scripts/vocab_sheet_probe.swift" "$out/main.swift"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swiftc -O \
    -o "$out/probe" \
    "$root/german-ai-flashcards/Services/VocabListParser.swift" \
    "$root/german-ai-flashcards/Services/CardKind.swift" \
    "$root/german-ai-flashcards/Services/OCRTableLayout.swift" \
    "$root/german-ai-flashcards/Services/PDFTextExtractor.swift" \
    "$out/main.swift"
"$out/probe" "$@"
