#!/bin/bash
# Is the code iOS and Android share still shared? Run before pushing (the pre-push hook does).
#
#   scripts/check_android.sh          core files portable, core builds for Android, shared tests
#   scripts/check_android.sh --full   also the Android store's host tests (KarteiStoreTests)
#
# Checks, in order:
#   1. every file in DieKarteiCore/core_files.txt is still Foundation-only (core_sync.py --check),
#      and reads settings through SharedDefaults.store (on Android the package's own
#      UserDefaults.standard is a separate file the app never writes)
#   2. DieKarteiCore cross-compiles for Android
#   3. DieKarteiCore tests on the Mac: the sync golden contract (SyncRecordTests), the study-day
#      rules, the tutor session
#   4. KarteiSyncCore tests (the merge engine)
#   5. with --full: KarteiStore tests (records in SQLite, the study log)
# The iOS side of the contract (SyncGoldenTests, StudyDayParityTests) runs with the iOS tests.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f "$HOME/.zprofile" ] && source "$HOME/.zprofile" >/dev/null 2>&1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDK="${CORE_SWIFT_SDK:-swift-6.4.3-RELEASE_android}"
TRIPLE="${CORE_TRIPLE:-aarch64-unknown-linux-android28}"
LOG="${TMPDIR:-/tmp}/check_android.$$.log"
FULL=0; [ "${1:-}" = "--full" ] && FULL=1

if ! swift sdk list 2>/dev/null | grep -q "$SDK"; then
  echo "check_android: the Swift SDK for Android ($SDK) isn't installed here; skipping."
  exit 0
fi

step() {  # step "label" command...
  local label="$1"; shift
  local t0=$SECONDS
  if "$@" >"$LOG" 2>&1; then
    echo "  ok    $label ($((SECONDS - t0))s)"
  else
    echo "  FAIL  $label"
    sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -E '\.swift:[0-9]+:[0-9]+: error|✘|error:|no longer|  [A-Za-z].*: (imports|has a|listed)|SharedDefaults' | grep -v ' -o /' | head -25
    echo "  (full log: $LOG)"
    exit 1
  fi
}

echo "check_android: shared iOS/Android code"
step "core files are portable" python3 scripts/core_sync.py --check
shared_defaults() {  # no UserDefaults.standard in shared code but SharedDefaults itself
  local bad
  bad=$( { sed 's|^|german-ai-flashcards/|' DieKarteiCore/core_files.txt; find DieKarteiCore/Sources -type f -name '*.swift'; } \
    | grep -v 'SharedDefaults.swift' | while read -r f; do [ -f "$f" ] && grep -l 'UserDefaults\.standard' "$f"; done | sort -u)
  if [ -n "$bad" ]; then
    echo "$bad" | sed 's|$|: uses UserDefaults.standard; use SharedDefaults.store|'
    return 1
  fi
}
step "shared settings go through SharedDefaults" shared_defaults
step "core builds for Android" swift build --package-path DieKarteiCore --swift-sdk "$SDK" --triple "$TRIPLE" --static-swift-stdlib
step "core tests (golden contract, study days, tutor)" swift test --package-path DieKarteiCore
step "sync engine tests" swift test --package-path KarteiSyncCore
if [ $FULL = 1 ]; then
  step "Android store tests" bash -c "cd DieKarteiAndroid && swift test --disable-keychain --filter KarteiStoreTests"
fi
rm -f "$LOG"
echo "check_android: all good"
