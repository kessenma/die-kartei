#!/usr/bin/env python3
"""Deploy Die Kartei via fastlane, teeing all output to a dated, auto-pruned log.

Usage:
  python3 scripts/deploy.py            # -> fastlane beta    (TestFlight)
  python3 scripts/deploy.py release    # -> fastlane release (App Store)

Logs are written to:
  build-logs/<deploy-beta|deploy-release>/YYYY-MM-DD/<type>-HH-MM-SS.log
Only the 10 most recent logs per type are retained (older ones, and any empty
date folders, are pruned before each run).

Tip: edit fastlane/changelog.txt before a beta run so the TestFlight
"What to Test" notes are picked up non-interactively.
"""

import sys
import subprocess
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # repo root (Gemfile + .xcodeproj live here)
MAX_LOGS = 10

mode = sys.argv[1] if len(sys.argv) > 1 else "beta"
lane = "release" if mode == "release" else "beta"
log_dir_name = "deploy-release" if mode == "release" else "deploy-beta"


def log(emoji, msg):
    print(f"{emoji} {msg}", flush=True)


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


def main():
    destination = "App Store" if mode == "release" else "TestFlight"
    log("🚀", f"Deploying Die Kartei to {destination}...")

    prune_old_logs()
    log_path = setup_build_log()
    log("📄", f"Log: {log_path}")

    # stdin is inherited (not piped) so fastlane's changelog prompt still works in a TTY.
    proc = subprocess.Popen(
        ["bundle", "exec", "fastlane", lane],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,  # merge so the single log file preserves ordering
        bufsize=1,
        text=True,
    )

    with open(log_path, "w") as logf:
        for line in proc.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            logf.write(line)
            logf.flush()

    code = proc.wait()

    print("")
    if code == 0:
        log("✅", "Deploy completed successfully!")
    else:
        log("❌", "Deploy failed!")
    log("📄", f"Full log: {log_path}")
    sys.exit(0 if code == 0 else 1)


if __name__ == "__main__":
    main()
