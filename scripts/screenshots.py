#!/usr/bin/env python3
"""App Store screenshots for Die Kartei, kept in one folder and pushed with `asc`.

Screenshots live under `AppStore/screenshots/<locale>/<DISPLAY_TYPE>/NN-name.jpg`:

    AppStore/screenshots/
      en-US/
        APP_IPHONE_67/           1320x2868  (6.9" — what Apple wants now)
        APP_IPHONE_65/           1284x2778  (6.5" — the older set, still served)
        APP_IPAD_PRO_3GEN_129/   2048x2732  (13" iPad)

The folder name is the App Store display type, so nothing has to be inferred from
a file name. Order on the product page follows the sorted file name, which is why
they are zero-padded: `10-…` must not sort between `01-…` and `02-…`.

CLI:
  python3 scripts/screenshots.py check              # validate sizes, show the plan
  python3 scripts/screenshots.py push [--version 1.6] [--force]
  python3 scripts/screenshots.py pull [--version 1.6]   # download what ASC has

`push` is additive by design: it uploads by MD5 with `--skip-existing`, so running
it twice is free and it never deletes anything already on the version. A set whose
folder is empty is skipped, not emptied — the iPad set can stay unfinished while
the iPhone sets ship.

deploy.py calls push() on `release` runs, after the build is uploaded. TestFlight
has no screenshots, so `beta` runs never touch them.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHOTS_DIR = ROOT / "AppStore" / "screenshots"
APP_ID = "6770390331"
MAX_PER_SET = 10  # App Store Connect's cap per display type

# Accepted pixel sizes per display type, portrait only — we never ship landscape.
# Straight from `asc screenshots sizes --all`; a file that is not exactly one of
# these is rejected by App Store Connect on upload.
EXPECTED = {
    "APP_IPHONE_67": [(1320, 2868), (1290, 2796), (1260, 2736)],
    "APP_IPHONE_65": [(1284, 2778), (1242, 2688)],
    "APP_IPAD_PRO_3GEN_129": [(2064, 2752), (2048, 2732)],
}

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}


def emit(text):
    sys.stdout.write(text)
    sys.stdout.flush()


def log(emoji, msg):
    emit(f"{emoji} {msg}\n")


def asc(*args, check=True):
    """Run `asc`, streaming merged output. Returns the exit code."""
    cmd = ["asc", *args]
    emit(f"$ {' '.join(cmd)}\n")
    proc = subprocess.Popen(
        cmd, cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        bufsize=1, text=True,
    )
    for line in proc.stdout:
        emit(line)
    code = proc.wait()
    if check and code != 0:
        raise RuntimeError(f"`{' '.join(cmd)}` failed with exit {code}")
    return code


def dimensions(path):
    """(width, height) via sips, or None when the file isn't a readable image."""
    out = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        capture_output=True, text=True,
    ).stdout
    w = re.search(r"pixelWidth:\s*(\d+)", out)
    h = re.search(r"pixelHeight:\s*(\d+)", out)
    return (int(w.group(1)), int(h.group(1))) if w and h else None


def sets_on_disk():
    """[(locale, display_type, [image paths sorted])] for every set folder present."""
    found = []
    if not SHOTS_DIR.exists():
        return found
    for locale_dir in sorted(p for p in SHOTS_DIR.iterdir() if p.is_dir()):
        for set_dir in sorted(p for p in locale_dir.iterdir() if p.is_dir()):
            images = sorted(
                p for p in set_dir.iterdir()
                if p.suffix.lower() in IMAGE_SUFFIXES and not p.name.startswith(".")
            )
            found.append((locale_dir.name, set_dir.name, images))
    return found


def check(verbose=True):
    """Validate every set against Apple's accepted sizes. Returns a list of problems."""
    problems = []
    any_images = False
    for locale, display_type, images in sets_on_disk():
        label = f"{locale}/{display_type}"
        if display_type not in EXPECTED:
            problems.append(
                f"{label}: unknown display type. Name the folder after an App Store "
                f"display type ({', '.join(sorted(EXPECTED))}) — see `asc screenshots sizes --all`."
            )
            continue
        if not images:
            if verbose:
                log("⏭", f"{label}: empty, will be skipped (nothing is deleted)")
            continue
        any_images = True
        if len(images) > MAX_PER_SET:
            problems.append(
                f"{label}: {len(images)} images; App Store Connect takes at most {MAX_PER_SET}."
            )
        for img in images:
            dim = dimensions(img)
            if dim is None:
                problems.append(f"{label}/{img.name}: not a readable image.")
            elif dim not in EXPECTED[display_type]:
                accepted = ", ".join(f"{w}x{h}" for w, h in EXPECTED[display_type])
                problems.append(
                    f"{label}/{img.name}: {dim[0]}x{dim[1]} — {display_type} accepts {accepted}."
                )
        if verbose:
            log("🖼", f"{label}: {len(images)} image(s) — " + ", ".join(i.name for i in images))
    if not any_images and not problems:
        problems.append(f"No screenshots found under {SHOTS_DIR.relative_to(ROOT)}.")
    return problems


def push(version, force=False, dry_run=False, fatal=False):
    """Upload every non-empty set for `version`. Returns True when nothing failed.

    Additive: `--skip-existing` compares MD5 against what the set already holds, so
    an unchanged image is a no-op and a re-run after a partial failure is safe.
    Never deletes — an image removed from the folder stays on the version until it
    is removed in App Store Connect by hand, which is the safe direction for a
    product page that is already live.
    """
    problems = check(verbose=False)
    if problems:
        log("❌", "Screenshots are not uploadable:")
        emit("".join(f"    {p}\n" for p in problems))
        return False

    # One upload per display type, not per locale: `asc` fans out across the locale
    # folders itself, and it requires --path to be the folder whose immediate
    # children ARE the locales. Point it at a locale folder and that folder's
    # children are read as locale codes ("no matching ... localizations found for
    # locales: APP-IPHONE-67").
    by_type = {}
    for locale, display_type, images in sets_on_disk():
        if images:
            by_type.setdefault(display_type, []).append((locale, images))

    ok = True
    for locale, display_type, images in sets_on_disk():
        if not images:
            log("⏭", f"{locale}/{display_type}: empty, skipped")

    for display_type, entries in sorted(by_type.items()):
        where = ", ".join(f"{loc} ({len(imgs)})" for loc, imgs in entries)
        args = [
            "screenshots", "upload",
            "--app", APP_ID,
            "--version", version,
            "--path", str(SHOTS_DIR.relative_to(ROOT)),
            "--device-type", display_type,
            "--output", "json",
        ]
        if not force:
            args.append("--skip-existing")
        if dry_run:
            args.append("--dry-run")
        log("⬆️", f"{display_type}: {where} -> {version}")
        if asc(*args, check=False) != 0:
            ok = False
            log("⚠️", f"{display_type} did not upload cleanly.")
    if not ok and fatal:
        raise RuntimeError("screenshot upload failed")
    return ok


def asc_json(*args):
    """Run `asc` and parse its JSON stdout. None when it fails or returns non-JSON."""
    proc = subprocess.run(["asc", *args], cwd=str(ROOT), capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def localizations(version):
    """[(locale, version_localization_id)] for a marketing version, or [] if unknown.

    `asc screenshots download` takes neither an app nor a version — only a
    localization ID — so the two lookups that `upload` does internally have to be
    done by hand here.
    """
    payload = asc_json("versions", "list", "--app", APP_ID, "--output", "json")
    version_id = next(
        (
            item["id"]
            for item in (payload or {}).get("data", [])
            if item.get("attributes", {}).get("versionString") == version
        ),
        None,
    )
    if not version_id:
        return []
    payload = asc_json("localizations", "list", "--version", version_id, "--output", "json")
    return [
        (item["attributes"]["locale"], item["id"])
        for item in (payload or {}).get("data", [])
        if item.get("attributes", {}).get("locale")
    ]


def pull(version, out_dir=None):
    """Download what App Store Connect currently has, to compare against the folder.

    Lands in AppStore/downloaded/<version>/<locale>/ — deliberately NOT in
    AppStore/screenshots/, so a download can never quietly become the thing the
    next deploy uploads. What comes back is Apple's re-encoded rendition, not the
    file that was uploaded: it will not match the original's checksum, and it is
    for looking at, never for re-uploading.
    """
    locales = localizations(version)
    if not locales:
        log("❌", f"No App Store version {version} with localizations found.")
        return 1
    base = Path(out_dir or (ROOT / "AppStore" / "downloaded" / version))
    code = 0
    for locale, loc_id in locales:
        out = base / locale
        out.mkdir(parents=True, exist_ok=True)
        log("⬇️", f"{version} {locale} -> {out.relative_to(ROOT)}")
        code |= asc(
            "screenshots", "download",
            "--version-localization", loc_id,
            "--output-dir", str(out),
            "--overwrite",
            check=False,
        )
    return code


def current_version():
    """The marketing version in the pbxproj, so `push` matches what deploy.py ships."""
    out = subprocess.run(
        ["asc", "xcode", "version", "view",
         "--project", "german-ai-flashcards.xcodeproj",
         "--target", "Die Kartei",
         "--configuration", "Release",
         "--output", "json"],
        cwd=str(ROOT), capture_output=True, text=True,
    ).stdout
    m = re.search(r'"version"\s*:\s*"([^"]+)"', out)
    return m.group(1) if m else None


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("check", help="validate sizes and show what would be uploaded")

    p_push = sub.add_parser("push", help="upload the sets to an App Store version")
    p_push.add_argument("--version", help="marketing version (default: the project's)")
    p_push.add_argument("--force", action="store_true",
                        help="re-upload images even when an identical one is already there")
    p_push.add_argument("--dry-run", action="store_true", help="show the plan, change nothing")

    p_pull = sub.add_parser("pull", help="download the version's screenshots from ASC")
    p_pull.add_argument("--version", help="marketing version (default: the project's)")
    p_pull.add_argument("--output-dir")

    args = parser.parse_args()

    if args.command == "check":
        problems = check()
        if problems:
            log("❌", "Problems:")
            emit("".join(f"    {p}\n" for p in problems))
            return 1
        log("✅", "All sets are valid App Store sizes.")
        return 0

    version = getattr(args, "version", None) or os.environ.get("VERSION") or current_version()
    if not version:
        log("❌", "Could not determine a marketing version; pass --version.")
        return 1

    if args.command == "push":
        return 0 if push(version, force=args.force, dry_run=args.dry_run) else 1
    if args.command == "pull":
        return pull(version, args.output_dir)
    return 1


if __name__ == "__main__":
    sys.exit(main())
