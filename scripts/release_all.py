#!/usr/bin/env python3
"""One-shot release of Die Kartei to every platform: iOS (iPhone + iPad, with the
keyboard extension inside the app) and then macOS, on the same marketing version.

Usage:
  python3 scripts/release_all.py --dry-run              # verify everything, upload nothing
  python3 scripts/release_all.py                        # App Store: iOS, then macOS (not submitted)
  python3 scripts/release_all.py --beta                 # TestFlight only: iOS, then macOS
  python3 scripts/release_all.py --version 1.7          # pin the version (else: the project's)
  python3 scripts/release_all.py --only ios|mac         # one platform, same checks
  python3 scripts/release_all.py --replace-screenshots  # swap each store set for this folder's

What each platform gets (release mode, via scripts/deploy.py):
  iOS    build + What's New + description/keywords + APP_IPHONE_65 and APP_IPAD_PRO_3GEN_129
  macOS  build + What's New + description/keywords + APP_DESKTOP
Beta mode uploads the builds with the What's New text as "What to Test" and touches no
product page, same as deploy.py.

The version is decided once, here, and passed to both runs as VERSION, so the two
platforms can't drift onto different marketing versions (deploy.py's own prompt is
skipped). Build numbers still come from deploy.py: each run takes the next number above
both platforms' builds.

--dry-run runs the offline checks (What's New, metadata limits, screenshot sizes) and then
the dry-run upload plans for both platforms against App Store Connect. A platform whose App
Store version doesn't exist yet (the macOS version is created by its first release) is
reported, not failed: the real run creates it.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import metadata      # noqa: E402
import screenshots   # noqa: E402
import whats_new     # noqa: E402

PLATFORMS = {"ios": "IOS", "mac": "MAC_OS"}


def say(emoji, msg):
    print(f"{emoji} {msg}", flush=True)


def run(cmd, env=None):
    """Run with the terminal attached (deploy.py may prompt). Returns the exit code."""
    print(f"$ {' '.join(cmd)}", flush=True)
    return subprocess.call(cmd, cwd=str(ROOT), env=env)


# --- checks -----------------------------------------------------------------

def mac_signing_check():
    """The Mac upload is a .pkg, which needs an installer certificate with its private key."""
    if not shutil.which("security"):
        return []
    out = subprocess.run(["security", "find-identity", "-v"], capture_output=True, text=True).stdout
    if any(n in out for n in ("Mac Installer Distribution", "3rd Party Mac Developer Installer")):
        say("  ✅", "Mac Installer Distribution certificate")
        return []
    return ["No Mac Installer Distribution certificate in the keychain: the macOS .pkg export "
            "would fail. Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Mac Installer "
            "Distribution (and accept any pending agreement at developer.apple.com/account)."]


def offline_checks(version, mode, platforms=("ios", "mac")):
    """Everything that can be verified without App Store Connect. Returns a list of problems."""
    problems = []

    say("🔎", "Tools")
    for tool in ("asc", "xcodebuild"):
        if shutil.which(tool):
            say("  ✅", tool)
        else:
            problems.append(f"`{tool}` is not on PATH.")
    # MLX compiles Metal kernels at archive time, and newer Xcodes ship the Metal compiler
    # as a separate download that an Xcode update can leave missing.
    if shutil.which("xcrun"):
        metal = subprocess.run(["xcrun", "metal", "--version"], capture_output=True, text=True)
        if metal.returncode == 0:
            say("  ✅", "Metal toolchain")
        else:
            problems.append("Metal toolchain missing (the archive would fail in mlx-swift): "
                            "run `xcodebuild -downloadComponent MetalToolchain`.")

    if "mac" in platforms:
        problems += mac_signing_check()

    say("🔎", f"What's New for {version}")
    chk = subprocess.run([sys.executable, str(SCRIPTS / "whats_new.py"), "check"],
                         cwd=str(ROOT), capture_output=True, text=True)
    if chk.returncode != 0:
        problems.append("whats_new.json does not pass `whats_new.py check`: "
                        + (chk.stderr or chk.stdout).strip().splitlines()[-1:][0] if (chk.stderr or chk.stdout).strip() else "")
    notes = subprocess.run([sys.executable, str(SCRIPTS / "whats_new.py"), "render", version],
                           cwd=str(ROOT), capture_output=True, text=True)
    unreleased = subprocess.run([sys.executable, str(SCRIPTS / "whats_new.py"), "render", "unreleased"],
                                cwd=str(ROOT), capture_output=True, text=True)
    text = (notes.stdout if notes.returncode == 0 and notes.stdout.strip() else unreleased.stdout).strip()
    if text:
        say("  ✅", f"{len(text)}/{whats_new.MAX_CHARS} chars")
    elif mode == "release":
        problems.append(f"No What's New entry for {version} (and no `unreleased` entry): "
                        "`release` refuses to ship without one.")
    else:
        say("  ⚠️", "No notes; TestFlight will prompt or ship without What to Test.")

    if mode == "release":
        say("🔎", "Product page text")
        problems += [f"metadata: {p}" for p in metadata.check(verbose=False)]
        if not any(p.startswith("metadata") for p in problems):
            say("  ✅", "description, keywords and URLs within App Store limits")

        say("🔎", "Screenshots")
        shot_problems = screenshots.check(verbose=False)
        problems += [f"screenshots: {p}" for p in shot_problems]
        if not shot_problems:
            for locale, display_type, images in screenshots.sets_on_disk():
                say("  ✅", f"{locale}/{display_type}: {len(images)} "
                           f"-> {screenshots.platform_of(display_type)}")
    return problems


def online_plan(version, platforms):
    """Dry-run upload plans against App Store Connect. Returns a list of problems."""
    problems = []
    for key in platforms:
        platform = PLATFORMS[key]
        say("🧪", f"{platform}: dry-run plan for {version}")
        if not metadata.version_id(version, platform):
            say("  ⚠️", f"No {platform} App Store version {version} yet. The release run creates "
                       "it; its metadata and screenshots go up after the build lands.")
            continue
        if not metadata.push(version, dry_run=True, platform=platform):
            problems.append(f"{platform}: metadata dry run failed.")
        if not screenshots.push(version, dry_run=True, platform=platform):
            problems.append(f"{platform}: screenshot dry run failed.")
    return problems


# --- main -------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true", help="verify only; upload nothing")
    ap.add_argument("--beta", action="store_true", help="TestFlight builds only, no product page")
    ap.add_argument("--version", help="marketing version for both platforms (default: the project's)")
    ap.add_argument("--only", choices=sorted(PLATFORMS), help="release one platform")
    ap.add_argument("--yes", action="store_true", help="don't ask before uploading")
    ap.add_argument("--replace-screenshots", action="store_true",
                    help="replace each screenshot set on the store instead of adding to it")
    ap.add_argument("--keep-going", action="store_true",
                    help="release macOS even if the iOS run failed")
    args = ap.parse_args()

    mode = "beta" if args.beta else "release"
    if args.replace_screenshots:
        os.environ["REPLACE_SCREENSHOTS"] = "1"  # read by screenshots.push, here and in deploy.py
    platforms = [args.only] if args.only else ["ios", "mac"]
    version = args.version or os.environ.get("VERSION") or screenshots.current_version()
    if not version:
        say("❌", "Could not read the marketing version from the project; pass --version.")
        return 1

    say("🚀", f"Die Kartei {version} · {mode} · {' + '.join(PLATFORMS[p] for p in platforms)}"
              f"{' · DRY RUN' if args.dry_run else ''}")
    problems = offline_checks(version, mode, platforms)
    if args.dry_run and mode == "release":
        problems += online_plan(version, platforms)

    if problems:
        say("❌", "Not ready:")
        for p in problems:
            print(f"    - {p}")
        return 1
    if args.dry_run:
        say("✅", "Dry run passed. Nothing was uploaded.")
        return 0

    if not args.yes:
        if not sys.stdin.isatty():
            say("❌", "Not a terminal; pass --yes to upload without the confirmation prompt.")
            return 1
        answer = input(f"Upload {version} ({mode}) for {', '.join(platforms)}? [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            say("⏹", "Cancelled.")
            return 1

    env = dict(os.environ, VERSION=version)
    results = {}
    for key in platforms:
        cmd = [sys.executable, str(SCRIPTS / "deploy.py")]
        if mode == "release":
            cmd.append("release")
        if key == "mac":
            cmd.append("--mac")
        say("▶️", f"{PLATFORMS[key]} {mode}")
        results[key] = run(cmd, env)
        if results[key] != 0 and not args.keep_going:
            break

    print("")
    for key in platforms:
        code = results.get(key)
        mark = "✅" if code == 0 else ("⏭ not run" if code is None else f"❌ exit {code}")
        say("•", f"{PLATFORMS[key]}: {mark}")
    if mode == "release" and all(results.get(k) == 0 for k in platforms):
        tail = "" if os.environ.get("REPLACE_SCREENSHOTS") == "1" else " Remove outdated screenshots and"
        say("ℹ️", f"Uploaded, NOT submitted.{tail} Submit in App Store Connect.")
        say("ℹ️", "Commit german-ai-flashcards/Resources/whats_new.json (deploy.py stamps it).")
    return 0 if all(results.get(k) == 0 for k in platforms) else 1


if __name__ == "__main__":
    sys.exit(main())
