#!/usr/bin/env python3
"""Interactive release menu for Die Kartei: every deploy option in one place.

  python3 scripts/release_menu.py        (VS Code: Cmd+Opt+Shift+R)

Pick what to do, which platforms, whether to sync the Affinity export first (see
sync_screenshots.py), and whether screenshot sets are replaced; the menu
prints the exact command it is about to run and asks before anything uploads. It only
calls the existing scripts (release_all.py, screenshots.py, metadata.py), so anything
it does can also be run by hand.
"""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PY = sys.executable

ACTIONS = [
    ("TestFlight build", "beta"),
    ("App Store release: build + What's New + description + screenshots (not submitted)", "release"),
    ("Product page only: description + screenshots, no build", "page"),
    ("Dry run: check everything and show the upload plan", "dry"),
    ("Sync screenshots from the Affinity export (Desktop/kartei-export)", "sync"),
    ("Preflight: auth, toolchain, signing, versions", "preflight"),
    ("Open the latest deploy log", "log"),
]
PLATFORMS = [("iOS + macOS", None), ("iOS only (iPhone + iPad)", "ios"), ("macOS only", "mac")]


def ask(prompt, options, default=1):
    print(f"\n{prompt}")
    for i, (label, _) in enumerate(options, 1):
        print(f"  {i}) {label}{'   (default)' if i == default else ''}")
    while True:
        raw = input(f"Choose 1-{len(options)} [{default}], q to quit: ").strip().lower()
        if raw in ("q", "quit", "exit"):
            sys.exit(0)
        if not raw:
            return options[default - 1][1]
        if raw.isdigit() and 1 <= int(raw) <= len(options):
            return options[int(raw) - 1][1]
        print("  Not an option.")


def yes(prompt, default=False):
    raw = input(f"{prompt} [{'Y/n' if default else 'y/N'}]: ").strip().lower()
    return default if not raw else raw in ("y", "yes")


def run(cmds):
    for cmd in cmds:
        print("\n$ " + " ".join(cmd), flush=True)
        code = subprocess.call(cmd, cwd=str(ROOT))
        if code != 0:
            print(f"\n❌ exited {code}")
            return code
    return 0


def main():
    print("🗂  Die Kartei · release menu")
    action = ask("What do you want to do?", ACTIONS)

    if action == "log":
        logs = sorted(ROOT.glob("build-logs/deploy-*/*/*.log"), key=lambda p: p.stat().st_mtime)
        if not logs:
            print("No deploy logs yet.")
            return 0
        return subprocess.call(["code", str(logs[-1])])
    if action == "preflight":
        return run([["asc", "auth", "status", "--validate"],
                    ["asc", "doctor"],
                    ["xcrun", "metal", "--version"],
                    ["security", "find-identity", "-v"]])

    if action == "sync":
        return run([[PY, "scripts/sync_screenshots.py"]])

    platform = ask("Which platforms?", PLATFORMS)
    sync_first = False
    if action in ("release", "page", "dry"):
        print("\nScreenshots come from Affinity: Scripts ▸ Export App Store screenshots writes "
              "~/Desktop/kartei-export.")
        sync_first = yes("Sync that export into AppStore/screenshots first?", default=True)
    replace = False
    if action in ("release", "page", "dry"):
        replace = yes("Replace each screenshot set on the store with the folder's images "
                      "(deletes the old ones)?", default=True)
    version = input("Version [the project's]: ").strip()

    if action == "page":
        targets = ["IOS", "MAC_OS"] if platform is None else (["IOS"] if platform == "ios" else ["MAC_OS"])
        ver = ["--version", version] if version else []
        cmds = []
        for t in targets:
            cmds.append([PY, "scripts/metadata.py", "push", "--platform", t, *ver])
            cmds.append([PY, "scripts/screenshots.py", "push", "--platform", t, *ver,
                         *(["--replace"] if replace else [])])
    else:
        cmd = [PY, "scripts/release_all.py"]
        if action == "beta":
            cmd.append("--beta")
        if action == "dry":
            cmd.append("--dry-run")
        if platform:
            cmd += ["--only", platform]
        if replace:
            cmd.append("--replace-screenshots")
        if version:
            cmd += ["--version", version]
        if action != "dry":
            cmd.append("--yes")  # the menu asks below instead
        cmds = [cmd]

    if sync_first:
        sync = [PY, "scripts/sync_screenshots.py"] + (["--check"] if action == "dry" else [])
        cmds.insert(0, sync)

    print("\nWill run:")
    for c in cmds:
        print("  " + " ".join(c[1:] if c[0] == PY else c))
    if action != "dry" and not yes("Go?"):
        print("Cancelled.")
        return 1
    return run(cmds)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled.")
        sys.exit(1)
