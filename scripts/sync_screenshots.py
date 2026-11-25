#!/usr/bin/env python3
"""Copy the Affinity exports into AppStore/screenshots, ready for upload.

Affinity can't be driven from here (no CLI; its scripts run inside the app and can only
write to the Desktop). So the hand-off is:

  1. Affinity ▸ Scripts ▸ "Export App Store screenshots"  -> ~/Desktop/kartei-export/{iphone,ipad,mac}/
  2. python3 scripts/sync_screenshots.py                  -> AppStore/screenshots/en-US/<display type>/

  python3 scripts/sync_screenshots.py --check   # only report what's stale or would change

Step 2 warns when the exports are older than the Affinity file (you saved changes but didn't
re-export), copies only files whose content changed, fits the 6.9" iPhone artboard (1320x2868)
into the 6.5" set (1284x2778, scale + centre crop, no distortion), and then runs the same size
check as screenshots.py.
"""

import argparse
import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import screenshots  # noqa: E402

EXPORT_DIR = Path.home() / "Desktop" / "kartei-export"
AF_FILE = ROOT.parent / "screenshots" / "die-kartei-screenshots.af"
SETS = {"iphone": "APP_IPHONE_65", "ipad": "APP_IPAD_PRO_3GEN_129", "mac": "APP_DESKTOP"}
LOCALE = "en-US"


def md5(path):
    return hashlib.md5(path.read_bytes()).hexdigest()


def fit_iphone(src, dst):
    """1320x2868 -> 1284x2778: scale to 1284 wide, then crop the middle 2778 rows."""
    if shutil.which("sips"):
        subprocess.run(["sips", "--resampleWidth", "1284", str(src), "--out", str(dst)],
                       check=True, capture_output=True)
        subprocess.run(["sips", "--cropToHeightWidth", "2778", "1284", str(dst)],
                       check=True, capture_output=True)
        return
    from PIL import Image  # fallback off macOS
    im = Image.open(src)
    h = round(im.height * 1284 / im.width)
    im = im.resize((1284, h), Image.LANCZOS)
    top = (h - 2778) // 2
    im.crop((0, top, 1284, top + 2778)).save(dst, quality=95)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="report only; copy nothing")
    args = ap.parse_args()

    if not EXPORT_DIR.exists():
        print(f"❌ {EXPORT_DIR} doesn't exist. In Affinity: Scripts ▸ Export App Store screenshots.")
        return 1

    exports = sorted(EXPORT_DIR.glob("*/*.jpg"))
    if AF_FILE.exists() and exports:
        af_time = AF_FILE.stat().st_mtime
        stale = [p for p in exports if p.stat().st_mtime < af_time]
        if stale:
            print(f"⚠️  {len(stale)} export(s) are older than {AF_FILE.name}: you saved changes in "
                  "Affinity after exporting. Re-run Scripts ▸ Export App Store screenshots first.")
            if not args.check:
                answer = input("Sync the older exports anyway? [y/N] ").strip().lower() if sys.stdin.isatty() else "n"
                if answer not in ("y", "yes"):
                    return 1

    changed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for folder, display_type in SETS.items():
            dest_dir = screenshots.SHOTS_DIR / LOCALE / display_type
            for src in sorted((EXPORT_DIR / folder).glob("*.jpg")):
                candidate = src
                dim = screenshots.dimensions(src)
                if folder == "iphone" and dim == (1320, 2868):
                    candidate = Path(tmp) / src.name
                    fit_iphone(src, candidate)
                dest = dest_dir / src.name
                if dest.exists() and md5(dest) == md5(candidate):
                    continue
                changed += 1
                print(f"{'would update' if args.check else 'updated'}: {display_type}/{src.name}")
                if not args.check:
                    dest_dir.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(candidate, dest)

    print(f"{'🔎' if args.check else '✅'} {changed} file(s) {'differ' if args.check else 'copied'}; "
          "the rest already match.")
    problems = screenshots.check(verbose=False)
    if problems:
        print("❌ Size check:")
        for p in problems:
            print("    - " + p)
        return 1
    print("✅ All sets are valid App Store sizes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
