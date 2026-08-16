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
  - Build number is set from `asc builds next-build-number`, which considers
    in-flight uploads as well as processed builds — so it is safe even when a
    previous upload is still processing.

Toolchain guard: archiving aborts if a BETA Xcode is selected. App Store Connect
accepts beta-built binaries on upload but rejects them at submission
("Unsupported SDK or Xcode version"). Override for a run with
XCODE_PATH=/Applications/Xcode.app.

Environment:
  BUMP                patch|minor|major       (default: minor)
  CHANGELOG           TestFlight "What to Test" text; overrides changelog.txt
  TESTFLIGHT_GROUP    beta group name or ID   (default: internal-die-Kartei)
  XCODE_PATH          developer dir or Xcode.app to pin for this run
  NOTIFY_TESTERS      true to notify testers after distribution
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # repo root (.xcodeproj lives here)
MAX_LOGS = 10

# --- App identity ----------------------------------------------------------
# NOTE: the numeric App Store Connect ID is required. `asc` accepts a bundle ID
# for some subcommands (builds) but NOT others (versions, testflight groups),
# so the numeric ID is used everywhere for consistency.
APP_ID = "6770390331"
BUNDLE_ID = "kyle-essenmacher.german-ai-flashcards"
PROJECT = "german-ai-flashcards.xcodeproj"
SCHEME = "german-ai-flashcards"
TARGET = "Die Kartei"
TEAM_ID = "RHPLRY9X9P"
CONFIGURATION = "Release"

CHANGELOG_FILE = ROOT / "fastlane" / "changelog.txt"  # TestFlight "What to Test"
DEFAULT_GROUP = "internal-die-Kartei"  # also: external-die-Kartei

# --- Code signing ----------------------------------------------------------
# Manual, pinned by SHA-1. Two distribution certs share the common name
# "Apple Distribution: Kyle Essenmacher (RHPLRY9X9P)", so selecting by name is
# ambiguous and can pick the wrong one. This SHA-1 is the cert the App Store
# profile below was minted for (their expiry timestamps match exactly).
#
# Manual is also the only reliable style on a machine whose Xcode GUI cannot
# launch (macOS 27 beta blocks Xcode 26.5's GUI), because automatic signing
# depends on an Apple ID account that can no longer be added or refreshed.
SIGNING_STYLE = os.environ.get("SIGNING_STYLE", "manual")
SIGNING_IDENTITY = os.environ.get(
    "SIGNING_IDENTITY", "F7140E42E2581B6280A45649513A244FCAF480D7"
)
PROVISIONING_PROFILE = os.environ.get(
    "PROVISIONING_PROFILE",
    "iOS Team Store Provisioning Profile: kyle-essenmacher.german-ai-flashcards",
)

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


def ensure_signing():
    """Fail early if the pinned signing identity isn't usable.

    Cheap up-front check: without it, a missing identity surfaces only after a
    full archive, minutes later.
    """
    if SIGNING_STYLE != "manual":
        log("🔏", f"Signing style: {SIGNING_STYLE} (identity resolved by Xcode)")
        return

    found = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True, text=True,
    ).stdout
    if SIGNING_IDENTITY not in found:
        die(
            f"Signing identity {SIGNING_IDENTITY} is not in the keychain.\n"
            "   Import the distribution .p12 (see docs/DEPLOY_SETUP.md), or override with "
            "SIGNING_IDENTITY=<sha1>, or fall back to SIGNING_STYLE=automatic."
        )
    log("🔏", f"Signing: manual, identity {SIGNING_IDENTITY[:8]}…, profile '{PROVISIONING_PROFILE}'")


def signing_args():
    """asc flags pinning the archive + export to a specific identity and profile."""
    args = ["--signing-style", SIGNING_STYLE, "--team-id", TEAM_ID]
    if SIGNING_STYLE == "manual":
        for setting in (
            "CODE_SIGN_STYLE=Manual",
            f"CODE_SIGN_IDENTITY={SIGNING_IDENTITY}",
            f"PROVISIONING_PROFILE_SPECIFIER={PROVISIONING_PROFILE}",
        ):
            args += ["--archive-xcodebuild-flag", setting]
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


def ensure_version_ahead():
    """Bump MARKETING_VERSION until strictly greater than the live App Store version."""
    live = live_app_store_version()
    if live is None:
        log("⚠️", "No live App Store version found; skipping version-ahead guard.")
        return

    bump = os.environ.get("BUMP", "minor")
    local, _ = local_version()
    log("🔎", f"Local marketing version {local}; live App Store version {live}")

    for _ in range(20):  # backstop against a pathological bump loop
        if _vtuple(local) > _vtuple(live):
            break
        asc(
            "xcode", "version", "bump",
            "--type", bump,
            "--project", PROJECT,
            "--target", TARGET,
            "--configuration", CONFIGURATION,
            "--output", "json",
        )
        local, _ = local_version()
        log("⬆️", f"Marketing version -> {local} (live App Store is {live})")
    else:
        die(
            f"BUMP={bump} cannot overtake the live version {live} (stuck at {local} after 20 bumps). "
            f"A patch bump can never pass a higher minor — re-run with BUMP=minor or BUMP=major."
        )


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
    return version, build


# --- changelog -------------------------------------------------------------

def testflight_changelog():
    """CHANGELOG env -> fastlane/changelog.txt -> interactive prompt (TTY)."""
    env_notes = os.environ.get("CHANGELOG", "").strip()
    if env_notes:
        return env_notes

    if CHANGELOG_FILE.exists():
        text = CHANGELOG_FILE.read_text().strip()
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
    notes = testflight_changelog()
    ensure_release_xcode()
    ensure_signing()
    ensure_version_ahead()
    version, build = set_next_build()
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
    return asc_stream(*args)


def deploy_release():
    ensure_release_xcode()
    ensure_signing()
    ensure_version_ahead()
    version, build = set_next_build()

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
    if code != 0:
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
        log("🔍", f"Validating version {version} ({version_id})...")
        asc_stream("validate", "--app", APP_ID, "--version-id", version_id, "--output", "table")
    else:
        log("⚠️", f"Could not resolve a version id for {version}; skipping validation.")

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
