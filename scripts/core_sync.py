#!/usr/bin/env python3
"""Rebuild DieKarteiCore's symlinks to the app's portable Swift files.

A file is a candidate when it imports only Foundation (or CryptoKit behind canImport) and holds no SwiftData @Model.
With --prune, the script cross-compiles for Android and drops every file the compiler
rejects (an Apple-only API, or a type from a file that is not portable), repeating until
the package builds. The final list is written to DieKarteiCore/core_files.txt.

    python3 scripts/core_sync.py            # relink from core_files.txt
    python3 scripts/core_sync.py --prune    # rediscover from scratch against Android
"""
import os, re, subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "german-ai-flashcards"
PKG = ROOT / "DieKarteiCore"
SRC = PKG / "Sources" / "DieKarteiCore"
LIST = PKG / "core_files.txt"
TRIPLE = os.environ.get("CORE_TRIPLE", "aarch64-unknown-linux-android28")
SDK = os.environ.get("CORE_SWIFT_SDK", "swift-6.4.3-RELEASE_android")
IMPORT = re.compile(r"^[ \t]*(?:@\w+(?:\(.*?\))?[ \t]+)*import[ \t]+(?:(?:struct|class|enum|protocol|func|var|let|typealias)[ \t]+)?(\w+)", re.M)


def candidates():
    out = []
    for p in sorted(APP.rglob("*.swift")):
        s = p.read_text(errors="ignore")
        allowed = {"Foundation", "Observation"}
        if "canImport(CryptoKit)" in s:  # CryptoKit on Apple, swift-crypto elsewhere
            allowed |= {"CryptoKit", "Crypto"}
        if set(IMPORT.findall(s)) <= allowed and "@Model" not in s:
            out.append(p.relative_to(APP).as_posix())
    return out


def link(files):
    if SRC.exists():
        for f in SRC.rglob("*"):
            if f.is_symlink():
                f.unlink()
    for rel in files:
        dst = SRC / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.symlink_to(os.path.relpath(APP / rel, dst.parent))
    for d in sorted(SRC.rglob("*"), reverse=True):
        if d.is_dir() and not any(d.iterdir()):
            d.rmdir()


def build():
    cmd = ["swift", "build", "--package-path", str(PKG), "--swift-sdk", SDK,
           "--triple", TRIPLE, "--static-swift-stdlib"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


ANSI = re.compile(r"\x1b\[[0-9;]*m")
MISSING = {}


def failing(log, files):
    log = ANSI.sub("", log)
    for m in re.finditer(r"error: cannot find (?:type )?'(\w+)' in scope", log):
        MISSING[m.group(1)] = MISSING.get(m.group(1), 0) + 1
    bad = set()
    for m in re.finditer(r"^(/[^:\n]+\.swift):\d+:\d+: error:", log, re.M):
        path = pathlib.Path(m.group(1))
        try:
            rel = path.resolve().relative_to(APP.resolve()).as_posix()
        except ValueError:
            try:
                rel = path.relative_to(SRC).as_posix()
            except ValueError:
                continue
        if rel in files:
            bad.add(rel)
    return bad


def main():
    if "--prune" in sys.argv:
        files = candidates()
        print(f"{len(files)} candidates")
        for round_ in range(1, 60):
            link(files)
            code, log = build()
            if code == 0:
                break
            bad = failing(log, files)
            if not bad:
                print(log[-4000:])
                sys.exit("build failed without a file to drop")
            print(f"round {round_}: dropping {len(bad)}: {', '.join(sorted(bad))[:300]}")
            files = [f for f in files if f not in bad]
        LIST.write_text("\n".join(files) + "\n")
        print(f"{len(files)} files build for {TRIPLE}")
        top = sorted(MISSING.items(), key=lambda kv: -kv[1])[:25]
        print("most-missed types:", ", ".join(f"{k}×{v}" for k, v in top))
    else:
        files = [l for l in LIST.read_text().split() if l]
        link(files)
        print(f"linked {len(files)} files")


if __name__ == "__main__":
    main()
