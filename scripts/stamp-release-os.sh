#!/bin/bash
# Rewrite BuildMachineOSBuild in the ARCHIVED app so App Store Connect accepts
# archives made on a beta macOS.
#
# Why: ASC rejects binaries whose Info.plist says they were built ON an
# unreleased macOS, and reports it as ITMS-90111 ("Unsupported SDK or Xcode
# version") - the same code it uses for a beta Xcode. Xcode stamps the host OS
# build into every Info.plist it processes: the app's and the SPM resource
# bundles' (Cmlx, Crypto, Hub). The Xcode/SDK stamps (DTXcodeBuild, DTSDKBuild)
# are left alone; those are what the rule is really about.
#
# Scope: ARCHIVES ONLY. Xcode runs this phase on every build, but a Debug or
# simulator build never goes near App Store Connect, and day-to-day work on a
# beta macOS may well happen in a beta Xcode. Outside an archive this script
# prints a note and exits 0. It must never fail a dev build.
#
# Wired as the LAST build phase of the "Die Kartei" target ("Stamp release
# macOS build"): after Copy Bundle Resources, before Xcode's code-sign step, so
# the signature seals the rewritten plists. scripts/deploy.py refuses to
# archive on a beta host if this phase goes missing, and reads the stamps back
# out of the exported IPA afterwards.
#
# Env knobs (all optional):
#   RELEASE_MACOS_BUILD  stamp with this exact build instead of auto-picking
set -euo pipefail

note() { echo "note: stamp-release-os: $*"; }

# 1. Only archives matter. `xcodebuild archive` runs the "install" action;
#    everything else (build, test, GUI runs) is "build".
if [[ "${ACTION:-build}" != "install" ]]; then
  note "not an archive (ACTION=${ACTION:-build}); nothing to do"
  exit 0
fi

# 2. Nothing to do on a release macOS. Apple seed builds end in a lowercase
#    letter (26A5421a); releases and RCs don't (25G83, 26A335).
host_build="$(sw_vers -buildVersion)"
if [[ ! "$host_build" =~ [a-z]$ ]]; then
  note "host macOS ${host_build} is a release build; nothing to do"
  exit 0
fi

# 3. A beta Xcode can't produce a submittable archive anyway (DTXcodeBuild is
#    checked too), so don't pretend otherwise. Xcode build numbers follow the
#    same seed convention (27A5194q vs 17F113).
xcode_build="${XCODE_PRODUCT_BUILD_VERSION:-}"
if [[ -z "$xcode_build" ]]; then
  xcode_build="$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')"
fi
if [[ "$xcode_build" =~ [a-z]$ ]]; then
  echo "error: archiving with a beta Xcode (${xcode_build}). App Store Connect will reject this archive regardless of BuildMachineOSBuild. Archive with the release Xcode instead (scripts/deploy.py does)." >&2
  exit 1
fi

# 4. Pick the stamp. Prefer the macOS build that shipped with this (release)
#    Xcode's own macOS SDK, so it tracks Xcode updates by itself. Fall back to a
#    pinned public release if that's missing or itself carries a seed suffix.
release_build="${RELEASE_MACOS_BUILD:-}"
if [[ -z "$release_build" ]]; then
  release_build="$(xcrun --sdk macosx --show-sdk-build-version 2>/dev/null || true)"
fi
if [[ -z "$release_build" || "$release_build" =~ [a-z]$ ]]; then
  fallback="25G83"  # macOS 26.6.2, the latest public release as of 2026-09-07
  note "macOS SDK build '${release_build:-none}' unusable as a stamp; using pinned ${fallback}"
  release_build="$fallback"
fi

app="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
if [[ ! -d "$app" ]]; then
  echo "error: built product not found at ${app}" >&2
  exit 1
fi

count=0
while IFS= read -r -d '' plist; do
  if /usr/libexec/PlistBuddy -c 'Print :BuildMachineOSBuild' "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :BuildMachineOSBuild ${release_build}" "$plist"
    count=$((count + 1))
  fi
done < <(find "$app" -name Info.plist -print0)

echo "stamped BuildMachineOSBuild ${host_build} -> ${release_build} in ${count} Info.plist(s) under ${WRAPPER_NAME} (Xcode ${xcode_build})"
