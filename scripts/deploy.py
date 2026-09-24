#!/usr/bin/env python3
"""Deploy Die Kartei via the App Store Connect CLI (`asc`), teeing all output to
a dated, auto-pruned log.

Usage:
  python3 scripts/deploy.py            # -> TestFlight
  python3 scripts/deploy.py release    # -> App Store (uploaded, NOT submitted)

Logs are written to:
  build-logs/<deploy-beta|deploy-release>/YYYY-MM-DD/<type>-HH-MM-SS.log
Only the 10 most recent logs per type are retained (older ones, and any empty
date folders, are pruned before each run).

Setup (first run on a machine): see docs/DEPLOY_SETUP.md.

Auto-versioning — both deploy modes version themselves against App Store
Connect so uploads can't collide:
  - Marketing version is bumped until strictly greater than the highest LIVE
    App Store version (fixes "train closed" / "version must be higher").
    Step size via BUMP=patch|minor|major (default: minor).
  - It is also bumped past any BURNED version: one App Store Connect has already
    rejected an upload for with ITMS-90186 (train closed) or ITMS-90062 (not
    above the last approved version). Those rejections are read back from
    `asc builds uploads list`, which keeps failed attempts that never became
    builds; nothing in the app's version list reveals a closed train, so the
    rejection is the only record. Burned is permanent for that version string.
  - Build number is set from `asc builds next-build-number`, which considers
    in-flight uploads as well as processed builds — so it is safe even when a
    previous upload is still processing.
  - Before archiving, an interactive run asks whether to keep building on the
    current marketing version or move to a new one (e.g. 1.4 -> 1.5), showing
    the recent uploads for context. Enter keeps the current version. Set
    VERSION=x.y to answer non-interactively; without a TTY the current version
    is kept. Whatever is chosen must still be above the live App Store version.

Toolchain guard: archiving aborts if a BETA Xcode is selected. App Store Connect
accepts beta-built binaries on upload but rejects them at submission
("Unsupported SDK or Xcode version"). Override for a run with
XCODE_PATH=/Applications/Xcode.app.

Host-OS guard: App Store Connect also rejects binaries whose Info.plist says
they were built ON a beta macOS (BuildMachineOSBuild), under the same
ITMS-90111 code, even when Xcode and the SDK are release builds. On a beta
host the "Stamp release macOS build" phase in the Xcode target
(scripts/stamp-release-os.sh) rewrites that key before code signing. This
script refuses to archive on a beta host if that phase is missing, and reads
the stamps back out of the exported IPA afterwards.

What's New: release notes live in german-ai-flashcards/Resources/whats_new.json
(see scripts/whats_new.py and /CLAUDE.md). Once the marketing version is settled,
both modes rename the file's `unreleased` entry to that version — or merge it into
the entry an earlier TestFlight of the same version already claimed — and archive
with the stamped file. The rendered entry is the TestFlight "What to Test" text;
`release` refuses to ship a version with no entry, refreshes its date to today,
and after the upload writes the same text into App Store Connect's What's New
(en-US). Commit the stamped file afterwards.

Product page: everything the App Store shows lives under AppStore/ — the description,
keywords and URLs as one file per field in AppStore/metadata/<locale>/
(scripts/metadata.py), and the screenshots in AppStore/screenshots/<locale>/<display
type>/ (scripts/screenshots.py). `release` pushes both to the version after the build
lands, skipping any empty file or set. What's New is the exception: it is generated
from Resources/whats_new.json so the app can ship the same text. TestFlight has none
of this, so `beta` never touches it.

Environment:
  VERSION             marketing version to ship as, e.g. 1.5 (skips the prompt)
  BUMP                patch|minor|major       (default: minor)
  CHANGELOG           TestFlight "What to Test" text; overrides the notes rendered
                      from whats_new.json for one run
  WHATS_NEW_ONLY      1 stops right after whats_new.json is stamped (no archive,
                      no upload) — a rehearsal of the notes step
  TESTFLIGHT_GROUP    beta group name or ID   (default: internal-die-Kartei)
  XCODE_PATH          developer dir or Xcode.app to pin for this run
  SKIP_METADATA       1 to skip the description/keywords push (release only)
  SKIP_SCREENSHOTS    1 to skip the App Store screenshot upload (release only)
  NOTIFY_TESTERS      true to notify testers after distribution
"""

import json
import os
import plistlib
import re
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path

import metadata  # scripts/ is sys.path[0] when run as `python3 scripts/deploy.py`
import screenshots
import whats_new

ROOT = Path(__file__).resolve().parent.parent  # repo root (.xcodeproj lives here)
MAX_LOGS = 10
ARTIFACTS = ROOT / ".asc" / "artifacts"  # where `asc publish` leaves the .xcarchive/.ipa
STAMP_SCRIPT = ROOT / "scripts" / "stamp-release-os.sh"  # run by the target's last build phase

# --- App identity ----------------------------------------------------------
# NOTE: the numeric App Store Connect ID is required. `asc` accepts a bundle ID
# for some subcommands (builds) but NOT others (versions, testflight groups),
# so the numeric ID is used everywhere for consistency.
APP_ID = "6770390331"
BUNDLE_ID = "kyle-essenmacher.german-ai-flashcards"
PROJECT = "german-ai-flashcards.xcodeproj"
SCHEME = "german-ai-flashcards"
TARGET = "Die Kartei"
# Embedded app extensions. `asc xcode version edit` is scoped to ONE target, so every nested
# bundle has to be stamped explicitly: App Store Connect rejects an upload whose .appex carries a
# different CFBundleShortVersionString / CFBundleVersion than the app containing it.
EXTENSION_TARGETS = ["Die Kartei Keyboard"]
TEAM_ID = "RHPLRY9X9P"
CONFIGURATION = "Release"

DEFAULT_GROUP = "internal-die-Kartei"  # also: external-die-Kartei

# --- Code signing ----------------------------------------------------------
# AUTOMATIC signing, deliberately. The only App Store profile that exists for
# this app is "iOS Team Store Provisioning Profile: ...", which is *Xcode
# managed* — and an Xcode-managed profile cannot be used with manual signing
# ("is Xcode managed, but signing settings require a manually managed profile").
# There are no manually-managed profiles in App Store Connect for this app, so
# manual signing would first require creating one.
#
# Equally important: signing settings must NOT be passed as global xcodebuild
# build settings. They apply to every target, including SPM package targets
# (encuda, CudaBuild, swift-crypto_Crypto, ...) that don't support provisioning
# profiles at all, which fails the build. The project's own pbxproj already
# specifies CODE_SIGN_STYLE=Automatic and DEVELOPMENT_TEAM, so the correct move
# is to override nothing and let the target settings apply.
#
# The archive is signed for development and re-signed for distribution at
# export; the resulting IPA is authenticated by "Apple Distribution: Kyle
# Essenmacher (RHPLRY9X9P)" with an App Store profile (no devices).
EXPORT_OPTIONS = ROOT / "ExportOptions.plist"

# Xcode's automatic signing normally needs a signed-in Apple ID account. The
# GUI can't be launched on macOS 27 beta, so authenticate with the same App
# Store Connect API key `asc` uses instead.
ASC_KEY_PATH = Path(os.environ.get("ASC_KEY_PATH", Path.home() / ".asc" / "AuthKey_24JDJGBV9T.p8"))
ASC_KEY_ID = "24JDJGBV9T"
ASC_ISSUER_ID = "5e67a835-18f8-47a8-aa06-e1a43e9c5c44"

mode = sys.argv[1] if len(sys.argv) > 1 else "beta"
if mode not in ("beta", "release"):
    sys.exit(f"Unknown mode {mode!r} — expected 'beta' or 'release'.")
log_dir_name = "deploy-release" if mode == "release" else "deploy-beta"

_logf = None      # run log handle, set in main()
_log_path = None  # run log path, set in main()


# --- logging ---------------------------------------------------------------

def emit(text):
    """Write to console and the run log."""
    sys.stdout.write(text)
    sys.stdout.flush()
    if _logf:
        _logf.write(text)
        _logf.flush()


def log(emoji, msg):
    emit(f"{emoji} {msg}\n")


def die(msg):
    log("❌", msg)
    if _log_path:
        log("📄", f"Full log: {_log_path}")
    sys.exit(1)


# --- asc plumbing ----------------------------------------------------------

def asc(*args, parse=True, check=True):
    """Run `asc` capturing stdout (JSON) with stderr teed to the log.

    Returns parsed JSON when parse=True, else the raw stdout string.
    """
    cmd = ["asc", *args]
    emit(f"$ {' '.join(cmd)}\n")
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    if proc.stderr.strip():
        emit(proc.stderr if proc.stderr.endswith("\n") else proc.stderr + "\n")
    if check and proc.returncode != 0:
        emit(proc.stdout)
        die(f"`{' '.join(cmd)}` failed with exit {proc.returncode}")
    if not parse:
        return proc.stdout
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        if check:
            emit(proc.stdout)
            die(f"`{' '.join(cmd)}` did not return JSON")
        return None


def asc_stream(*args):
    """Run a long `asc` command, teeing merged output live. Returns exit code."""
    cmd = ["asc", *args]
    emit(f"$ {' '.join(cmd)}\n")
    proc = subprocess.Popen(
        cmd,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,  # merge so the log preserves ordering
        bufsize=1,
        text=True,
    )
    for line in proc.stdout:
        emit(line)
    return proc.wait()


# --- guards ----------------------------------------------------------------

def ensure_release_xcode():
    """Abort if a BETA Xcode is selected.

    App Store Connect accepts beta-built binaries on upload but rejects them at
    submission. `asc xcode` shells out to whatever `xcode-select -p` returns and
    performs no toolchain check of its own, so this guard is ours to keep.
    """
    dev_dir = os.environ.get("XCODE_PATH", "").strip()
    if dev_dir:
        # Accept either an Xcode.app or a full Developer dir.
        if dev_dir.endswith(".app"):
            dev_dir = f"{dev_dir}/Contents/Developer"
        os.environ["DEVELOPER_DIR"] = dev_dir
    else:
        dev_dir = os.environ.get("DEVELOPER_DIR", "").strip()
        if not dev_dir:
            dev_dir = subprocess.run(
                ["xcode-select", "-p"], capture_output=True, text=True
            ).stdout.strip()

    version = subprocess.run(
        ["xcodebuild", "-version"], capture_output=True, text=True
    ).stdout.splitlines()
    version = version[0].strip() if version else "unknown"
    log("🛠", f"Toolchain: {version} ({dev_dir})")

    if re.search(r"beta", dev_dir, re.IGNORECASE):
        die(
            f"A BETA Xcode is selected ({dev_dir}). App Store submissions must be built "
            "with a released Xcode. Re-run with XCODE_PATH=/Applications/Xcode.app, or "
            "switch the system default via `sudo xcode-select -s /Applications/Xcode.app`."
        )


def _is_seed_build(build):
    """Apple seed (beta) builds end in a lowercase letter: 26A5421a. Releases and RCs don't: 25G83."""
    return bool(re.search(r"[a-z]$", build or ""))


def ensure_release_host_stamp():
    """Abort if the host macOS is a beta and the target lacks the restamp phase.

    ASC rejects binaries whose BuildMachineOSBuild names an unreleased macOS
    and reports it as ITMS-90111, exactly like a beta Xcode. The Xcode target's
    last build phase runs scripts/stamp-release-os.sh to rewrite that key
    before code signing; without it, a beta host yields an unsubmittable build
    that still uploads and processes fine, so nothing else would catch it.
    """
    host = subprocess.run(["sw_vers", "-buildVersion"], capture_output=True, text=True).stdout.strip()
    if not _is_seed_build(host):
        log("🖥", f"Host macOS {host} (release build)")
        return
    pbxproj = ROOT / PROJECT / "project.pbxproj"
    wired = STAMP_SCRIPT.exists() and STAMP_SCRIPT.name in pbxproj.read_text()
    if not wired:
        die(
            f"Host macOS {host} is a beta and the '{STAMP_SCRIPT.name}' build phase is missing from "
            f"{PROJECT}. App Store Connect rejects binaries built on a beta macOS (ITMS-90111). "
            "Restore the 'Stamp release macOS build' phase, or archive on a release macOS."
        )
    log("🩹", f"Host macOS {host} is a beta; {STAMP_SCRIPT.name} will restamp BuildMachineOSBuild before signing")


def report_binary_stamps(version, build):
    """Read the toolchain stamps back out of the exported IPA and flag any beta.

    This inspects the bytes that were actually uploaded. A beta value here
    means ASC will reject the build at submission even though the upload and
    processing succeeded. Diagnostics only; never fails the deploy.
    """
    ipas = sorted(ARTIFACTS.glob(f"*-{version}-{build}.ipa"))
    if not ipas:
        log("⚠️", f"No IPA for {version} ({build}) under {ARTIFACTS}; skipping stamp check.")
        return
    ipa = ipas[-1]
    # The app's own Info.plist AND every embedded extension's. An .appex is stamped by its own
    # target's copy of the phase, so it can go wrong independently of the app — checking only the
    # top-level plist would report green on a build ASC is about to reject.
    wanted = re.compile(r"Payload/[^/]+\.app/(?:(?:Extensions|PlugIns)/[^/]+\.appex/)?Info\.plist")
    try:
        with zipfile.ZipFile(ipa) as z:
            names = sorted(n for n in z.namelist() if wanted.fullmatch(n))
            app_name = next(n for n in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n))
            infos = {n: plistlib.loads(z.read(n)) for n in names}
    except Exception as e:  # noqa: BLE001 - diagnostics only
        log("⚠️", f"Couldn't read Info.plist from {ipa.name} ({e}); skipping stamp check.")
        return

    app_info = infos[app_name]

    for name, info in infos.items():
        # "Die Kartei.app" for the app, "Die Kartei Keyboard.appex" for an extension.
        bundle = name.rsplit("/", 2)[-2]
        stamps = {k: str(info.get(k, "?")) for k in ("DTXcodeBuild", "DTSDKBuild", "BuildMachineOSBuild")}
        summary = ", ".join(f"{k}={v}" for k, v in stamps.items())
        # The seed-suffix rule holds for Xcode and macOS builds, but NOT for SDK builds:
        # release Xcode 26.6 ships iOS SDK 23F81a. A beta SDK only comes with a beta
        # Xcode anyway, which DTXcodeBuild catches, so DTSDKBuild is shown, not judged.
        beta = [k for k in ("DTXcodeBuild", "BuildMachineOSBuild") if _is_seed_build(stamps[k])]
        if beta:
            log("❌", f"{bundle} carries beta stamp(s) {', '.join(beta)} ({summary}). "
                      "ASC will reject this build at submission with ITMS-90111.")
        else:
            log("✅", f"{bundle} toolchain stamps are all release builds ({summary})")

        # Version parity, checked on the bytes that were actually uploaded — the cheapest place to
        # catch a sync_extension_versions() that silently missed a target.
        if bundle.endswith(".appex"):
            for key in ("CFBundleShortVersionString", "CFBundleVersion"):
                if str(info.get(key, "?")) != str(app_info.get(key, "?")):
                    log("❌", f"{bundle} {key}={info.get(key)} does not match the app's "
                              f"{app_info.get(key)}. ASC rejects mismatched nested bundles — "
                              "check EXTENSION_TARGETS.")


def ensure_signing():
    """Fail early if a distribution identity or the export options are missing.

    Cheap up-front checks: without them, the problem surfaces only after a full
    archive, many minutes later.
    """
    found = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True, text=True,
    ).stdout
    if "Apple Distribution" not in found:
        die(
            "No 'Apple Distribution' identity in the keychain — archiving will fail.\n"
            "   Import the distribution .p12; see docs/DEPLOY_SETUP.md section 4."
        )
    if not EXPORT_OPTIONS.exists():
        die(f"Missing {EXPORT_OPTIONS.name} — required to stop Xcode rewriting the build number.")
    if not ASC_KEY_PATH.exists():
        die(f"App Store Connect API key not found at {ASC_KEY_PATH}; see docs/DEPLOY_SETUP.md.")
    log("🔏", f"Signing: automatic (team {TEAM_ID}), export options {EXPORT_OPTIONS.name}")


def signing_args():
    """asc flags for archive + export.

    Nothing here overrides the project's own signing settings — see the note by
    EXPORT_OPTIONS. Both phases are given API-key credentials so automatic
    signing can refresh profiles without a signed-in Xcode GUI account.

    Export needs them just as much as archive, and for a harsher reason. Archive
    signs for development, where the team's wildcard profile (RHPLRY9X9P.*)
    covers a bundle ID that was never registered — so a new app extension
    archives green. Export signs for distribution, which has no wildcard: it
    wants an App Store profile for that exact bundle ID, and without credentials
    it can neither create one nor register the App ID, failing with "No Accounts"
    and "No profiles for <bundle id> were found" after the full archive.
    """
    args = ["--export-options", str(EXPORT_OPTIONS)]
    for flag in (
        "-allowProvisioningUpdates",
        "-authenticationKeyPath", str(ASC_KEY_PATH),
        "-authenticationKeyID", ASC_KEY_ID,
        "-authenticationKeyIssuerID", ASC_ISSUER_ID,
    ):
        args += ["--archive-xcodebuild-flag", flag]
        args += ["--export-xcodebuild-flag", flag]
    return args


# --- versioning ------------------------------------------------------------

def _vtuple(v):
    """'1.10.2' -> (1, 10, 2); non-numeric fragments sort as 0."""
    parts = []
    for chunk in str(v).split("."):
        m = re.match(r"\d+", chunk)
        parts.append(int(m.group()) if m else 0)
    return tuple(parts)


def local_version():
    """(marketing_version, build_number) as currently written in the pbxproj."""
    info = asc(
        "xcode", "version", "view",
        "--project", PROJECT,
        "--target", TARGET,
        "--configuration", CONFIGURATION,
        "--output", "json",
    )
    return info["version"], info.get("buildNumber")


def live_app_store_version():
    """Highest version string ASC reports as READY_FOR_SALE, or None.

    Several past versions can retain READY_FOR_SALE simultaneously, so this
    takes the maximum rather than trusting response order. Best-effort: a None
    result skips the version-ahead guard rather than failing the deploy.
    """
    try:
        payload = asc(
            "versions", "list",
            "--app", APP_ID,
            "--state", "READY_FOR_SALE",
            "--output", "json",
            check=False,
        )
        versions = [
            item["attributes"]["versionString"]
            for item in (payload or {}).get("data", [])
            if item.get("attributes", {}).get("versionString")
        ]
        return max(versions, key=_vtuple) if versions else None
    except Exception as e:  # noqa: BLE001 - non-fatal by design
        log("⚠️", f"Couldn't read the live App Store version ({e}); skipping version-ahead guard.")
        return None


# Upload-rejection codes that mean "this marketing version can never be used
# again": the pre-release train is closed, or the version isn't above the last
# version Apple approved. Both are permanent for that version string — the only
# cure is a higher CFBundleShortVersionString.
BURNED_TRAIN_CODES = {"90186", "90062"}


def burned_versions():
    """Marketing versions App Store Connect has permanently rejected uploads for.

    `asc builds uploads list` keeps every upload attempt, including the ones that
    never became builds. A train can close without anything in the app's version
    list saying so (a version record deleted after approval, a version approved
    and then withdrawn), so the rejections themselves are the only reliable
    record. Best-effort: an empty set on any failure, never a dead deploy.
    """
    try:
        payload = asc(
            "builds", "uploads", "list",
            "--app", APP_ID,
            "--output", "json",
            check=False,
        )
        burned = {}
        for item in (payload or {}).get("data", []):
            attrs = item.get("attributes", {})
            if attrs.get("platform") not in (None, "IOS"):
                continue
            version = attrs.get("cfBundleShortVersionString")
            state = attrs.get("state") or {}
            if not version or state.get("state") != "FAILED":
                continue
            codes = {str(e.get("code")) for e in state.get("errors", [])}
            if codes & BURNED_TRAIN_CODES:
                burned.setdefault(version, sorted(codes & BURNED_TRAIN_CODES))
        for version, codes in sorted(burned.items(), key=lambda kv: _vtuple(kv[0])):
            log("🚫", f"Version {version} is burned — App Store Connect rejected an upload with {', '.join(codes)}")
        return set(burned)
    except Exception as e:  # noqa: BLE001 - non-fatal by design
        log("⚠️", f"Couldn't read past build uploads ({e}); skipping the burned-train guard.")
        return set()


def diagnose_upload_failure(version, build):
    """After a failed publish, say plainly whether the version itself is the problem.

    The upload record carries Apple's error codes; the publish output only shows
    them once, buried in a long log. Prints the remedy rather than leaving the
    next run to rediscover it. Best-effort and always silent on success paths.
    """
    try:
        payload = asc("builds", "uploads", "list", "--app", APP_ID, "--output", "json", check=False)
        for item in (payload or {}).get("data", []):
            attrs = item.get("attributes", {})
            state = attrs.get("state") or {}
            if (
                attrs.get("cfBundleShortVersionString") != version
                or str(attrs.get("cfBundleVersion")) != str(build)
                or state.get("state") != "FAILED"
            ):
                continue
            codes = {str(e.get("code")) for e in state.get("errors", [])}
            for err in state.get("errors", []):
                log("📛", f"ITMS-{err.get('code')}: {err.get('description')}")
            if codes & BURNED_TRAIN_CODES:
                log(
                    "🔁",
                    f"Version {version} can never accept another build. Re-run with a higher "
                    f"version — e.g. VERSION={_next_minor(version)} python3 scripts/deploy.py {mode} "
                    f"— or just re-run: the burned-train guard now bumps past it automatically.",
                )
            return
    except Exception:  # noqa: BLE001 - diagnosis must never mask the real failure
        pass


def ensure_version_ahead():
    """Bump MARKETING_VERSION past the live App Store version and any burned train.

    Returns (live version string or None, burned version set) so the version
    prompt can validate against both without a second round-trip.
    """
    burned = burned_versions()
    live = live_app_store_version()
    if live is None:
        log("⚠️", "No live App Store version found; skipping version-ahead guard.")
        if not burned:
            return None, burned

    bump = os.environ.get("BUMP", "minor")
    local, _ = local_version()
    log("🔎", f"Local marketing version {local}; live App Store version {live or 'unknown'}")

    def why_blocked(v):
        if live and _vtuple(v) <= _vtuple(live):
            return f"not above the live App Store version {live}"
        if v in burned:
            return "a closed train — App Store Connect rejects every build on it"
        return None

    for _ in range(20):  # backstop against a pathological bump loop
        reason = why_blocked(local)
        if reason is None:
            break
        asc(
            "xcode", "version", "bump",
            "--type", bump,
            "--project", PROJECT,
            "--target", TARGET,
            "--configuration", CONFIGURATION,
            "--output", "json",
        )
        previous, local = local, local_version()[0]
        log("⬆️", f"Marketing version -> {local} ({previous} is {reason})")
    else:
        die(
            f"BUMP={bump} cannot get past {live or 'the burned trains'} (stuck at {local} after 20 bumps). "
            f"A patch bump can never pass a higher minor — re-run with BUMP=minor or BUMP=major."
        )
    return live, burned


VERSION_RE = re.compile(r"^\d+(\.\d+){0,2}$")  # 1, 1.5, 1.5.2 — what App Store Connect accepts


def _next_minor(v):
    """'1.4' -> '1.5'; '1.4.2' -> '1.5'; '2' -> '2.1'."""
    t = _vtuple(v)
    return f"{t[0]}.{t[1] + 1}" if len(t) >= 2 else f"{t[0]}.1"


def recent_uploads(limit=6):
    """[(marketing_version, build_number), ...] newest first. Best-effort, [] on any failure."""
    payload = asc(
        "builds", "list",
        "--app", APP_ID,
        "--sort", "-uploadedDate",
        "--limit", str(limit),
        "--processing-state", "all",
        "--output", "json",
        check=False,
    )
    if not payload:
        return []
    pre_release = {
        item["id"]: item.get("attributes", {}).get("version", "?")
        for item in payload.get("included", [])
        if item.get("type") == "preReleaseVersions"
    }
    uploads = []
    for build in payload.get("data", []):
        rel = build.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}
        uploads.append((pre_release.get(rel.get("id"), "?"), build.get("attributes", {}).get("version", "?")))
    return uploads


def set_marketing_version(version):
    asc(
        "xcode", "version", "edit",
        "--version", version,
        "--project", PROJECT,
        "--target", TARGET,
        "--configuration", CONFIGURATION,
        "--output", "json",
    )


def choose_marketing_version(live, burned=frozenset()):
    """Decide which marketing version this deploy ships as. Returns it.

    Without this, every deploy keeps stacking builds onto the same version
    (1.4 (2), (3), (4)...) until that version goes live, because the
    version-ahead guard only ever bumps when forced to.

      VERSION env set -> use it, no questions asked (CI / scripted runs)
      interactive     -> "Continue on 1.4? [Y/n]", then a new version if not
      no TTY          -> keep the current version

    Whatever is chosen must still be above the live App Store version.
    """
    local, _ = local_version()

    def problem_with(v):
        if not VERSION_RE.match(v):
            return f"'{v}' is not a version like 1.5 or 1.5.1"
        if live and _vtuple(v) <= _vtuple(live):
            return f"{v} is not above the live App Store version {live}"
        if v in burned:
            return f"{v} is a closed train — App Store Connect rejects every build on it"
        return None

    wanted = os.environ.get("VERSION", "").strip()
    if wanted:
        problem = problem_with(wanted)
        if problem:
            die(f"VERSION={wanted}: {problem}")
        log("🏷", f"VERSION={wanted} given; skipping the version prompt")
    elif sys.stdin.isatty():
        uploads = recent_uploads()
        if uploads:
            by_version = {}
            for v, b in uploads:
                by_version.setdefault(v, []).append(b)
            log("📜", "Recent uploads: " + "; ".join(f"{v} ({', '.join(bs)})" for v, bs in by_version.items()))
        answer = input(f"Continue building on version {local}? [Y/n]: ").strip().lower()
        if answer in ("n", "no"):
            suggested = _next_minor(local)
            while True:
                wanted = input(f"New marketing version [{suggested}]: ").strip() or suggested
                problem = problem_with(wanted)
                if not problem:
                    break
                emit(f"   {problem}\n")
        else:
            wanted = local
        emit(f"   -> {wanted}\n")  # the answers themselves don't reach the log
    else:
        log("ℹ️", f"No TTY; keeping marketing version {local} (set VERSION=x.y to override).")
        wanted = local

    if wanted != local:
        set_marketing_version(wanted)
        local, _ = local_version()
        log("🏷", f"Marketing version -> {local}")
    else:
        log("🏷", f"Continuing on marketing version {local}")
    return local


def set_next_build():
    """Set CFBundleVersion from ASC, counting in-flight uploads as well as processed builds."""
    version, _ = local_version()
    asc(
        "xcode", "version", "edit",
        "--next-build-number",
        "--app", APP_ID,
        "--platform", "IOS",
        "--project", PROJECT,
        "--target", TARGET,
        "--configuration", CONFIGURATION,
        "--output", "json",
    )
    version, build = local_version()
    log("📦", f"Versioned as {version} ({build})")
    sync_extension_versions(version, build)
    return version, build


def sync_extension_versions(version, build):
    """Copy the app's version and build onto every embedded extension target.

    `set_marketing_version`, `set_next_build` and the `ensure_version_ahead` bump are all scoped
    with `--target TARGET`, so they only ever touch the app. An extension left at Xcode's default
    1.0 (1) inside an app at 1.7 (14) fails ASC validation after a full archive and upload — the
    slowest possible way to find out. Called from `set_next_build`, the single point every deploy
    path passes through once the version is final.
    """
    for target in EXTENSION_TARGETS:
        asc(
            "xcode", "version", "edit",
            "--version", version,
            "--build-number", str(build),
            "--project", PROJECT,
            "--target", target,
            "--configuration", CONFIGURATION,
            "--output", "json",
        )
        log("🔗", f"{target} synced to {version} ({build})")


# --- what's new --------------------------------------------------------------

def stamp_whats_new(version, live):
    """Turn the `unreleased` entry of Resources/whats_new.json into `version`.

    Runs AFTER choose_marketing_version(), so the version can no longer move, and
    BEFORE the archive, so the stamped file is what ships inside the app. An
    earlier TestFlight of the same version already claimed the entry? New bullets
    merge into it. Release refreshes the date (that's the ship date) and refuses
    to ship a version that has nothing to say.
    """
    release = mode == "release"
    rel_path = whats_new.DEFAULT_PATH.relative_to(ROOT)
    try:
        doc = whats_new.load()
        problems = whats_new.check(doc)
        if problems:
            die(f"{rel_path} has problems:\n  " + "\n  ".join(problems))
        result = whats_new.stamp(doc, version, live=live, refresh_date=release)
        if result["changed"]:
            whats_new.save(whats_new.DEFAULT_PATH, doc)
    except whats_new.WhatsNewError as e:
        die(f"{rel_path}: {e}")

    if result["folded"]:
        log("🧲", f"Folded never-released {', '.join(result['folded'])} into {version}")
    if result["entry"] is None:
        if release:
            die(
                f"No What's New entry for {version}. Add highlights to the 'unreleased' entry in "
                f"{rel_path} — a release with nothing to say is not a release."
            )
        log("⚠️", f"No What's New entry for {version}; TestFlight notes will be prompted for.")
        return

    text = whats_new.render(doc, version)
    if len(text) > whats_new.MAX_CHARS:
        die(f"What's New for {version} is {len(text)} chars; App Store Connect caps it at {whats_new.MAX_CHARS}.")
    if result["created"]:
        verb = "created"
    elif result["merged"]:
        verb = f"merged {result['merged']} new highlight(s) into"
    else:
        verb = "unchanged for"
    log("📝", f"{rel_path} {verb} {version} — commit it")
    emit("".join(f"    {line}\n" for line in text.splitlines()))


def _stop_if_whats_new_only():
    if os.environ.get("WHATS_NEW_ONLY") == "1":
        log("🛑", "WHATS_NEW_ONLY=1: stopping before the archive.")
        sys.exit(0)


def push_app_store_whats_new(version, version_id):
    """Write the rendered notes into the App Store version's What's New (en-US).

    Non-fatal: the build is uploaded either way, and the field can be pasted by
    hand in App Store Connect. Fails when the version is no longer editable
    (already waiting for review), which is exactly when a paste is the answer.
    """
    text = whats_new.render(whats_new.load(), version)
    if not text:
        return
    log("📝", f"Setting App Store What's New for {version} (en-US)...")
    out = asc(
        "localizations", "update",
        "--version", version_id,
        "--locale", "en-US",
        "--whats-new", text,
        "--output", "json",
        check=False,
    )
    if out is None:
        log("⚠️", "Couldn't set What's New; paste it into App Store Connect before submitting:")
        emit("".join(f"    {line}\n" for line in text.splitlines()))


def push_metadata(version):
    """Write AppStore/metadata (description, keywords, URLs, name) to the version.

    Non-fatal, like What's New and screenshots. Never touches What's New itself —
    that field is owned by whats_new.json and written by push_app_store_whats_new(),
    and two writers for one field is how they drift.

    Set SKIP_METADATA=1 to leave the product-page text alone for a run.
    """
    if os.environ.get("SKIP_METADATA") == "1":
        log("⏭", "SKIP_METADATA=1: leaving the App Store description and keywords untouched.")
        return
    problems = metadata.check(verbose=False)
    if problems:
        log("⚠️", "Metadata not pushed:")
        emit("".join(f"    {p}\n" for p in problems))
        return
    metadata.emit = emit  # tee into the run log; see push_screenshots
    try:
        if not metadata.push(version):
            log("⚠️", "Some metadata did not update; check it in App Store Connect.")
    except Exception as e:  # noqa: BLE001 - never lose an uploaded build to this
        log("⚠️", f"Metadata push failed ({e}); edit it in App Store Connect.")


def push_screenshots(version):
    """Upload AppStore/screenshots to the App Store version.

    Non-fatal, like What's New: the build is already uploaded, and a screenshot can
    always be dragged into App Store Connect by hand. Additive and MD5-skipping, so
    an unchanged set costs one API round-trip and nothing on the product page moves.
    Sets with an empty folder are skipped — the iPad set can stay unfinished without
    blocking a release, which also means a missing set is never reported as an error
    here. `asc validate` below is what flags a version Apple won't accept.

    Set SKIP_SCREENSHOTS=1 to leave the product page alone for a run.
    """
    if os.environ.get("SKIP_SCREENSHOTS") == "1":
        log("⏭", "SKIP_SCREENSHOTS=1: leaving App Store screenshots untouched.")
        return
    problems = screenshots.check(verbose=False)
    if problems:
        log("⚠️", "Screenshots not uploaded:")
        emit("".join(f"    {p}\n" for p in problems))
        return
    log("🖼", f"Uploading App Store screenshots for {version}...")
    # Tee the module's own output into the run log; on its own it only writes to
    # stdout, and a deploy log that stops short of the upload is the one you want
    # when a screenshot lands in the wrong set.
    screenshots.emit = emit
    try:
        if not screenshots.push(version):
            log("⚠️", "Some screenshots did not upload; check them in App Store Connect.")
    except Exception as e:  # noqa: BLE001 - never lose an uploaded build to this
        log("⚠️", f"Screenshot upload failed ({e}); upload them in App Store Connect.")


# --- changelog -------------------------------------------------------------

def testflight_changelog(version):
    """CHANGELOG env -> rendered whats_new.json entry -> interactive prompt (TTY)."""
    env_notes = os.environ.get("CHANGELOG", "").strip()
    if env_notes:
        return env_notes

    text = whats_new.render(whats_new.load(), version)
    if text:
        return text

    if sys.stdin.isatty():
        return input("TestFlight 'What to Test' notes for this build: ").strip()
    return ""


# --- log housekeeping ------------------------------------------------------

def _rm_empty_date_dirs(base):
    for d in base.iterdir():
        if d.is_dir() and not any(d.iterdir()):
            d.rmdir()


def prune_old_logs():
    """Keep only the MAX_LOGS most recent .log files (by mtime) across all date dirs."""
    base = ROOT / "build-logs" / log_dir_name
    if not base.exists():
        return

    logs = [
        (f, f.stat().st_mtime)
        for d in base.iterdir() if d.is_dir()
        for f in d.iterdir() if f.suffix == ".log"
    ]

    if len(logs) <= MAX_LOGS:
        _rm_empty_date_dirs(base)
        return

    logs.sort(key=lambda t: t[1], reverse=True)  # newest first
    to_delete = logs[MAX_LOGS:]

    freed = 0
    for f, _ in to_delete:
        try:
            freed += f.stat().st_size
            f.unlink()
        except FileNotFoundError:
            pass

    _rm_empty_date_dirs(base)
    n = len(to_delete)
    log("🧹", f"Pruned {n} old log{'' if n == 1 else 's'} (freed {freed / 1024 / 1024:.1f} MB)")


def setup_build_log():
    now = datetime.now()
    d = ROOT / "build-logs" / log_dir_name / now.strftime("%Y-%m-%d")
    d.mkdir(parents=True, exist_ok=True)
    return d / f"{log_dir_name}-{now.strftime('%H-%M-%S')}.log"


# --- deploy modes ----------------------------------------------------------

def deploy_beta():
    ensure_release_xcode()
    ensure_release_host_stamp()
    ensure_signing()
    live, burned = ensure_version_ahead()
    choose_marketing_version(live, burned)
    version, build = set_next_build()
    stamp_whats_new(version, live)
    notes = testflight_changelog(version)
    _stop_if_whats_new_only()
    group = os.environ.get("TESTFLIGHT_GROUP", DEFAULT_GROUP)

    args = [
        "publish", "testflight",
        "--app", APP_ID,
        "--project", PROJECT,
        "--scheme", SCHEME,
        "--configuration", CONFIGURATION,
        "--version", version,
        "--group", group,
        *signing_args(),
        "--clean",
        "--wait", "--poll-interval", "15s",
        "--output", "json", "--pretty",
    ]
    if notes:
        args += ["--test-notes", notes, "--locale", "en-US"]
    if os.environ.get("NOTIFY_TESTERS") == "true":
        args.append("--notify")

    log("🚀", f"Building {version} ({build}) and publishing to TestFlight group '{group}'...")
    code = asc_stream(*args)
    report_binary_stamps(version, build)
    if code != 0:
        diagnose_upload_failure(version, build)
    return code


def deploy_release():
    ensure_release_xcode()
    ensure_release_host_stamp()
    ensure_signing()
    live, burned = ensure_version_ahead()
    choose_marketing_version(live, burned)
    version, build = set_next_build()
    stamp_whats_new(version, live)
    _stop_if_whats_new_only()

    log("🚀", f"Building {version} ({build}) and uploading to the App Store (no submission)...")
    code = asc_stream(
        "publish", "appstore",
        "--app", APP_ID,
        "--project", PROJECT,
        "--scheme", SCHEME,
        "--configuration", CONFIGURATION,
        "--version", version,
        *signing_args(),
        "--clean",
        "--wait", "--poll-interval", "15s",
        "--output", "json", "--pretty",
    )
    report_binary_stamps(version, build)
    if code != 0:
        diagnose_upload_failure(version, build)
        return code

    # Readiness check on the version we just populated. Non-fatal: the build is
    # already uploaded, and submission is a deliberate manual step in ASC.
    payload = asc("versions", "list", "--app", APP_ID, "--output", "json", check=False)
    version_id = next(
        (
            item["id"]
            for item in (payload or {}).get("data", [])
            if item.get("attributes", {}).get("versionString") == version
        ),
        None,
    )
    if version_id:
        # Notes and screenshots first, so the readiness report below sees them populated.
        push_app_store_whats_new(version, version_id)
        push_metadata(version)
        push_screenshots(version)
        log("🔍", f"Validating version {version} ({version_id})...")
        asc_stream("validate", "--app", APP_ID, "--version-id", version_id, "--output", "table")
    else:
        log("⚠️", f"Could not resolve a version id for {version}; skipping validation and What's New.")

    log("ℹ️", "Build uploaded but NOT submitted for review — submit from App Store Connect.")
    return 0


def main():
    global _logf, _log_path

    destination = "App Store" if mode == "release" else "TestFlight"
    print(f"🚀 Deploying Die Kartei to {destination}...", flush=True)

    prune_old_logs()
    _log_path = setup_build_log()
    print(f"📄 Log: {_log_path}", flush=True)

    with open(_log_path, "w") as logf:
        _logf = logf
        code = deploy_release() if mode == "release" else deploy_beta()

    print("")
    if code == 0:
        print("✅ Deploy completed successfully!", flush=True)
    else:
        print("❌ Deploy failed!", flush=True)
    print(f"📄 Full log: {_log_path}", flush=True)
    sys.exit(0 if code == 0 else 1)


if __name__ == "__main__":
    main()
