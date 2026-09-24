#!/usr/bin/env python3
"""App Store product-page text for Die Kartei, kept in files and pushed with `asc`.

One file per field, under `AppStore/metadata/<locale>/`:

    description.md         the long description        (<= 4000 chars)
    keywords.txt           comma-separated             (<= 100 chars)
    promotional_text.txt   the line above the fold     (<= 170 chars)
    marketing_url.txt      a URL
    support_url.txt        a URL
    name.txt               the App Store name          (<= 30 chars)
    subtitle.txt           under the name              (<= 30 chars)
    privacy_url.txt        a URL

The first five belong to the *version* (they can differ per release and are
editable until the version is approved). The last three belong to *app info*,
which is app-wide and not version-scoped — `asc` calls that `--type app-info`.

WHAT'S NEW IS NOT HERE. It is generated from
`german-ai-flashcards/Resources/whats_new.json` because the app ships the same
text in-app (Settings ▸ About ▸ What's New), and deploy.py pushes it from there.
Two sources for one field is how they drift, so this script never writes it.

CLI:
  python3 scripts/metadata.py check                     # lengths and content, locally
  python3 scripts/metadata.py push [--version 1.6] [--dry-run]
  python3 scripts/metadata.py pull [--version 1.6]      # overwrite the files from ASC

An empty or missing file means "leave that field alone", never "clear it" — the
safe direction for a page that is already live. Clear a field in App Store Connect.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META_DIR = ROOT / "AppStore" / "metadata"
APP_ID = "6770390331"

# file -> (asc flag, asc attribute, scope, max chars). None = no documented limit.
FIELDS = {
    "description.md":       ("--description",      "description",      "version",  4000),
    "keywords.txt":         ("--keywords",         "keywords",         "version",  100),
    "promotional_text.txt": ("--promotional-text", "promotionalText",  "version",  170),
    "marketing_url.txt":    ("--marketing-url",    "marketingUrl",     "version",  255),
    "support_url.txt":      ("--support-url",      "supportUrl",       "version",  255),
    "name.txt":             ("--name",             "name",             "app-info", 30),
    "subtitle.txt":         ("--subtitle",         "subtitle",         "app-info", 30),
    "privacy_url.txt":      ("--privacy-policy-url", "privacyPolicyUrl", "app-info", 255),
}

# Markdown that would be pushed to Apple as literal characters. description.md is
# named for the editor's benefit; App Store Connect renders none of it.
MARKDOWN_HINT = re.compile(r"^(#{1,6}\s|[-*+]\s|>\s)|\*\*|__|\[.+\]\(.+\)", re.MULTILINE)


def emit(text):
    sys.stdout.write(text)
    sys.stdout.flush()


def log(emoji, msg):
    emit(f"{emoji} {msg}\n")


def asc_json(*args):
    """Run `asc` and parse its JSON stdout. None when it fails or returns non-JSON."""
    proc = subprocess.run(["asc", *args], cwd=str(ROOT), capture_output=True, text=True)
    if proc.returncode != 0:
        if proc.stderr.strip():
            emit(proc.stderr.rstrip() + "\n")
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def read_field(locale_dir, filename):
    """The file's text with the trailing newline stripped, or '' when absent/empty."""
    path = locale_dir / filename
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def locales_on_disk():
    if not META_DIR.exists():
        return []
    return sorted(p for p in META_DIR.iterdir() if p.is_dir())


def check(verbose=True):
    """Validate every field file. Returns a list of problems (warnings are printed)."""
    problems = []
    locale_dirs = locales_on_disk()
    if not locale_dirs:
        return [f"No locale folders under {META_DIR.relative_to(ROOT)}."]

    for locale_dir in locale_dirs:
        locale = locale_dir.name
        unknown = [
            p.name for p in locale_dir.iterdir()
            if p.is_file() and p.name not in FIELDS and not p.name.startswith(".")
        ]
        for name in unknown:
            problems.append(
                f"{locale}/{name}: not a field this script knows. Expected one of "
                f"{', '.join(sorted(FIELDS))}."
            )
        for filename, (_flag, _attr, scope, limit) in FIELDS.items():
            text = read_field(locale_dir, filename)
            if not text:
                if verbose:
                    log("⏭", f"{locale}/{filename}: empty, field left as it is")
                continue
            if limit and len(text) > limit:
                problems.append(
                    f"{locale}/{filename}: {len(text)} chars; App Store Connect caps it at {limit}."
                )
            if filename == "description.md" and MARKDOWN_HINT.search(text):
                log("⚠️", f"{locale}/{filename} contains Markdown syntax. The App Store shows it "
                          "literally — it renders nothing. Use plain text and blank lines.")
            if verbose:
                cap = f"/{limit}" if limit else ""
                log("📄", f"{locale}/{filename}: {len(text)}{cap} chars ({scope})")
    return problems


def version_id(version):
    payload = asc_json("versions", "list", "--app", APP_ID, "--output", "json")
    return next(
        (
            item["id"]
            for item in (payload or {}).get("data", [])
            if item.get("attributes", {}).get("versionString") == version
        ),
        None,
    )


def push(version, dry_run=False):
    """Write every non-empty field to App Store Connect. Returns True when nothing failed."""
    problems = check(verbose=False)
    if problems:
        log("❌", "Metadata is not pushable:")
        emit("".join(f"    {p}\n" for p in problems))
        return False

    vid = version_id(version)
    if not vid:
        log("❌", f"No App Store version {version} in App Store Connect.")
        return False

    ok = True
    for locale_dir in locales_on_disk():
        locale = locale_dir.name
        # One call per scope, carrying every field for it: `asc localizations update`
        # takes several field flags at once, and one call means one chance to fail.
        for scope in ("version", "app-info"):
            args = []
            shown = []
            for filename, (flag, _attr, field_scope, _limit) in FIELDS.items():
                if field_scope != scope:
                    continue
                text = read_field(locale_dir, filename)
                if text:
                    args += [flag, text]
                    shown.append(filename)
            if not args:
                continue
            base = (
                ["localizations", "update", "--version", vid, "--locale", locale]
                if scope == "version"
                else ["localizations", "update", "--app", APP_ID, "--type", "app-info",
                      "--locale", locale]
            )
            log("📝", f"{locale} {scope}: {', '.join(shown)}")
            if dry_run:
                printable = " ".join(
                    f"{a[:40]}…" if len(a) > 40 else a for a in [*base, *args]
                )
                emit(f"    would run: asc {printable}\n")
                continue
            if asc_json(*base, *args, "--output", "json") is None:
                ok = False
                log("⚠️", f"{locale} {scope} did not update.")
    return ok


def pull(version):
    """Overwrite the local files with what App Store Connect currently has."""
    vid = version_id(version)
    if not vid:
        log("❌", f"No App Store version {version} in App Store Connect.")
        return 1
    ver = asc_json("localizations", "list", "--version", vid, "--output", "json") or {}
    info = asc_json("localizations", "list", "--app", APP_ID, "--type", "app-info",
                    "--output", "json") or {}

    live = {}
    for payload, scope in ((ver, "version"), (info, "app-info")):
        for item in payload.get("data", []):
            attrs = item.get("attributes", {})
            locale = attrs.get("locale")
            if locale:
                live.setdefault(locale, {}).update(
                    {k: v for k, v in attrs.items() if k != "locale"}
                )

    for locale, attrs in sorted(live.items()):
        locale_dir = META_DIR / locale
        locale_dir.mkdir(parents=True, exist_ok=True)
        for filename, (_flag, attr, _scope, _limit) in FIELDS.items():
            text = attrs.get(attr) or ""
            path = locale_dir / filename
            before = read_field(locale_dir, filename)
            path.write_text((text.rstrip("\n") + "\n") if text else "", encoding="utf-8")
            mark = "=" if before == text.strip() else "~"
            log(mark, f"{locale}/{filename}: {len(text)} chars")
    return 0


def current_version():
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
    sub.add_parser("check", help="validate lengths and content")
    p_push = sub.add_parser("push", help="write the fields to App Store Connect")
    p_push.add_argument("--version")
    p_push.add_argument("--dry-run", action="store_true")
    p_pull = sub.add_parser("pull", help="overwrite the files from App Store Connect")
    p_pull.add_argument("--version")
    args = parser.parse_args()

    if args.command == "check":
        problems = check()
        if problems:
            log("❌", "Problems:")
            emit("".join(f"    {p}\n" for p in problems))
            return 1
        log("✅", "Metadata is within App Store limits.")
        return 0

    version = args.version or os.environ.get("VERSION") or current_version()
    if not version:
        log("❌", "Could not determine a marketing version; pass --version.")
        return 1
    if args.command == "push":
        return 0 if push(version, dry_run=args.dry_run) else 1
    return pull(version)


if __name__ == "__main__":
    sys.exit(main())
