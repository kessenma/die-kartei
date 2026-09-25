#!/bin/sh
# Runs the pure iCloud-sync logic tests (merge engine, PN counters, drift simulations).
# KarteiSyncCore/Sources/KarteiSyncCore is a symlink to german-ai-flashcards/Services/Sync/Core,
# which the app target compiles directly. Uses Xcode's toolchain: the swiftly toolchain on PATH
# can't link against the macOS 27 Command Line Tools SDK.
set -e
cd "$(dirname "$0")/../KarteiSyncCore"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift test "$@"
