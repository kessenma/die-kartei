#!/usr/bin/env python3
"""Release notes for Die Kartei, kept in one JSON file.

`german-ai-flashcards/Resources/whats_new.json` is read by the app (Settings ▸ About ▸
What's New, and once at launch after an update) and stamped by `scripts/deploy.py`,
which renames the top `"unreleased"` entry to the shipping marketing version and sends
the same text to TestFlight ("What to Test") and to the App Store's What's New field.
Nobody types version numbers or dates into the file by hand — see /CLAUDE.md.

CLI (all commands take --file PATH to work on a copy):
  python3 scripts/whats_new.py check
  python3 scripts/whats_new.py render 1.5
  python3 scripts/whats_new.py stamp 1.5 [--live 1.4] [--refresh-date] [--require] [--dry-run]

This module is self-contained on purpose: deploy.py imports it, and deploy.py itself has
module-level side effects that make it unimportable. Python 3.9 compatible.
"""

import argparse
import difflib
import json
import re
import sys
from datetime import date
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PATH = ROOT / "german-ai-flashcards" / "Resources" / "whats_new.json"
UNRELEASED = "unreleased"
VERSION_RE = re.compile(r"^\d+(\.\d+){0,2}$")  # 1, 1.5, 1.5.2 — what App Store Connect accepts
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
MAX_CHARS = 4000  # App Store Connect caps whatsNew and TestFlight test notes here

RELEASE_KEYS = ("version", "date", "highlights")
HIGHLIGHT_KEYS = ("title", "detail", "symbol")


class WhatsNewError(Exception):
    """The file is missing, unreadable, or structurally unusable."""


# --- versions ---------------------------------------------------------------

def vtuple(version: str) -> Tuple[int, ...]:
    """'1.10' -> (1, 10), so 1.10 sorts above 1.9. Never compare version strings directly."""
    return tuple(int(part) for part in version.split("."))


def _norm(title: str) -> str:
    """Case- and whitespace-insensitive key for de-duplicating highlight titles."""
    return " ".join(str(title).split()).casefold()


# --- file I/O ---------------------------------------------------------------

def load(path=None) -> dict:
    """Read and minimally validate the file. `None` means `DEFAULT_PATH` — resolved at call time,
    not definition time, so tests can point the module at a copy."""
    path = Path(path or DEFAULT_PATH)
    if not path.exists():
        raise WhatsNewError(f"{path} does not exist")
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise WhatsNewError(f"{path} is not valid JSON: {e}")
    if not isinstance(doc, dict) or not isinstance(doc.get("releases"), list):
        raise WhatsNewError(f"{path} must be an object with a 'releases' array")
    return doc


def _ordered_highlight(h: dict) -> dict:
    out = {"title": h.get("title", "")}
    if h.get("detail"):
        out["detail"] = h["detail"]
    if h.get("symbol"):
        out["symbol"] = h["symbol"]
    return out


def _ordered_release(r: dict) -> dict:
    out = {"version": r.get("version")}
    if r.get("date"):
        out["date"] = r["date"]
    out["highlights"] = [_ordered_highlight(h) for h in r.get("highlights", [])]
    return out


def dumps(doc: dict) -> str:
    """Stable key order, 2-space indent, real umlauts, trailing newline — one field per line
    keeps concurrent edits to plain merge conflicts."""
    ordered = {"releases": [_ordered_release(r) for r in doc["releases"]]}
    return json.dumps(ordered, indent=2, ensure_ascii=False) + "\n"


def save(path, doc: dict) -> None:
    Path(path).write_text(dumps(doc), encoding="utf-8")


# --- queries ----------------------------------------------------------------

def find(doc: dict, version: str) -> Optional[dict]:
    for r in doc["releases"]:
        if isinstance(r, dict) and r.get("version") == version:
            return r
    return None


def versioned(doc: dict) -> List[dict]:
    """Every entry except `unreleased`."""
    return [r for r in doc["releases"] if r.get("version") != UNRELEASED]


def sort_releases(doc: dict) -> None:
    """`unreleased` first, then newest version first. Assumes `check()` passed."""
    head = [r for r in doc["releases"] if r.get("version") == UNRELEASED]
    tail = sorted(versioned(doc), key=lambda r: vtuple(r["version"]), reverse=True)
    doc["releases"] = head + tail


# --- validation -------------------------------------------------------------

def check(doc: dict) -> List[str]:
    """Structural problems, as messages. Empty list means the file is usable."""
    problems: List[str] = []
    seen = set()
    previous: Optional[str] = None

    for i, r in enumerate(doc["releases"]):
        if not isinstance(r, dict):
            problems.append(f"releases[{i}] is not an object")
            continue
        version = r.get("version")
        where = f"releases[{i}] ({version!r})"
        if not isinstance(version, str) or not version:
            problems.append(f"{where}: missing 'version'")
            continue
        if version in seen:
            problems.append(f"{where}: duplicate version")
        seen.add(version)

        unknown = sorted(set(r) - set(RELEASE_KEYS))
        if unknown:
            problems.append(f"{where}: unknown keys {unknown}")

        highlights = r.get("highlights")
        if not isinstance(highlights, list):
            problems.append(f"{where}: 'highlights' must be an array")
            highlights = []
        titles = set()
        for j, h in enumerate(highlights):
            if not isinstance(h, dict) or not isinstance(h.get("title"), str) or not h["title"].strip():
                problems.append(f"{where}: highlights[{j}] needs a non-empty 'title'")
                continue
            key = _norm(h["title"])
            if key in titles:
                problems.append(f"{where}: duplicate highlight title {h['title']!r}")
            titles.add(key)
            for field in ("detail", "symbol"):
                if field in h and h[field] is not None and not isinstance(h[field], str):
                    problems.append(f"{where}: highlights[{j}].{field} must be a string")
            unknown = sorted(set(h) - set(HIGHLIGHT_KEYS))
            if unknown:
                problems.append(f"{where}: highlights[{j}] has unknown keys {unknown}")

        if version == UNRELEASED:
            if i != 0:
                problems.append(f"{where}: 'unreleased' must be the first entry")
            if r.get("date"):
                problems.append(f"{where}: 'unreleased' must not carry a date (deploy stamps it)")
            continue

        if not VERSION_RE.match(version):
            problems.append(f"{where}: version must look like 1.5 or 1.5.2 (or be 'unreleased')")
            continue
        stamped = r.get("date")
        if not isinstance(stamped, str) or not DATE_RE.match(stamped):
            problems.append(f"{where}: needs a 'date' like 2026-09-05")
        if not highlights:
            problems.append(f"{where}: needs at least one highlight")
        if previous is not None and vtuple(version) >= vtuple(previous):
            problems.append(f"{where}: versions must be strictly descending (comes after {previous})")
        previous = version

    return problems


def warnings(doc: dict) -> List[str]:
    """Things worth knowing that don't block a deploy."""
    out: List[str] = []
    unreleased = find(doc, UNRELEASED)
    if unreleased is not None:
        n = len(unreleased.get("highlights") or [])
        out.append(f"'unreleased' has {n} highlight{'' if n == 1 else 's'}; deploy will stamp it")
    for r in versioned(doc):
        text = render(doc, r["version"])
        if len(text) > MAX_CHARS:
            out.append(f"{r['version']} renders to {len(text)} chars; App Store Connect caps it at {MAX_CHARS}")
    return out


# --- rendering --------------------------------------------------------------

def render(doc: dict, version: str) -> str:
    """The exact text shipped to TestFlight and the App Store for one version, one bullet per
    line. Empty string when the version has no entry."""
    r = find(doc, version)
    if r is None:
        return ""
    lines = []
    for h in r.get("highlights", []):
        title = " ".join(str(h.get("title", "")).split())
        detail = " ".join(str(h.get("detail") or "").split())
        lines.append(f"• {title} — {detail}" if detail else f"• {title}")
    return "\n".join(lines)


# --- stamping ---------------------------------------------------------------

def merge_into(target: dict, source: dict) -> int:
    """Append `source`'s highlights whose title `target` doesn't already have. Returns how many."""
    existing = {
        _norm(h["title"])
        for h in target.get("highlights", [])
        if isinstance(h, dict) and h.get("title")
    }
    added = 0
    for h in source.get("highlights", []):
        key = _norm(h.get("title", "")) if isinstance(h, dict) else ""
        if not key or key in existing:
            continue
        target.setdefault("highlights", []).append(h)
        existing.add(key)
        added += 1
    return added


def stamp(doc: dict, version: str, live: Optional[str] = None,
          refresh_date: bool = False, today: Optional[str] = None) -> Dict[str, object]:
    """Turn `unreleased` into `version`, in place.

    - `unreleased` + no entry for `version`  -> rename it, date = today.
    - `unreleased` + an entry for `version`  -> merge new bullets into it (an earlier TestFlight
      of the same version already claimed the entry), drop `unreleased`.
    - Entries above `live` (the highest version on the App Store) other than `version` never
      reached anyone: a TestFlight-only 1.5 when 1.6 is what ships. They are folded into
      `version` rather than left as phantom releases.
    - `refresh_date` moves the entry's date to today (release mode: the ship date).

    Idempotent: with nothing pending, nothing changes. Assumes `check()` passed.
    """
    if not VERSION_RE.match(version):
        raise WhatsNewError(f"{version!r} is not a marketing version")
    today = today or date.today().isoformat()
    result: Dict[str, object] = {"entry": None, "created": False, "merged": 0, "folded": [], "changed": False}
    releases = doc["releases"]

    entry = find(doc, version)
    unreleased = find(doc, UNRELEASED)
    if unreleased is not None and not unreleased.get("highlights"):
        releases.remove(unreleased)  # an empty stub is as good as absent
        unreleased = None
        result["changed"] = True

    if unreleased is not None:
        if entry is not None:
            result["merged"] = int(result["merged"]) + merge_into(entry, unreleased)
            releases.remove(unreleased)
        else:
            unreleased["version"] = version
            unreleased["date"] = today
            entry = unreleased
            result["created"] = True
        result["changed"] = True

    if live:
        orphans = [
            r for r in versioned(doc)
            if r.get("version") != version and vtuple(r["version"]) > vtuple(live)
        ]
        for r in orphans:
            result["folded"].append(r["version"])  # type: ignore[union-attr]
            if entry is None:
                r["version"] = version
                r["date"] = today
                entry = r
                result["created"] = True
            else:
                result["merged"] = int(result["merged"]) + merge_into(entry, r)
                releases.remove(r)
            result["changed"] = True

    if entry is not None:
        if refresh_date and entry.get("date") != today:
            entry["date"] = today
            result["changed"] = True
        if not entry.get("date"):
            entry["date"] = today
            result["changed"] = True

    sort_releases(doc)
    result["entry"] = entry
    return result


# --- CLI --------------------------------------------------------------------

def _print_problems(problems: List[str]) -> None:
    for p in problems:
        print(f"✗ {p}")


def _cmd_check(args) -> int:
    doc = load(args.file)
    problems = check(doc)
    if problems:
        _print_problems(problems)
        return 1
    for w in warnings(doc):
        print(f"⚠ {w}")
    n = len(versioned(doc))
    print(f"OK: {n} released version{'' if n == 1 else 's'} in {args.file}")
    return 0


def _cmd_render(args) -> int:
    doc = load(args.file)
    text = render(doc, args.version)
    if not text:
        print(f"No entry for {args.version}", file=sys.stderr)
        return 1
    print(text)
    return 0


def _cmd_stamp(args) -> int:
    doc = load(args.file)
    problems = check(doc)
    if problems:
        _print_problems(problems)
        return 1
    before = dumps(doc)
    result = stamp(doc, args.version, live=args.live, refresh_date=args.refresh_date)
    after = dumps(doc)

    entry = result["entry"]
    if result["folded"]:
        print(f"Folded never-released {', '.join(result['folded'])} into {args.version}")  # type: ignore[arg-type]
    if entry is None:
        print(f"No What's New entry for {args.version} (nothing pending in 'unreleased')")
    elif result["created"]:
        print(f"Created {args.version} ({len(entry['highlights'])} highlights)")
    elif result["merged"]:
        print(f"Merged {result['merged']} new highlight(s) into {args.version}")
    else:
        print(f"{args.version} unchanged")

    if args.dry_run:
        diff = difflib.unified_diff(
            before.splitlines(keepends=True), after.splitlines(keepends=True),
            fromfile=str(args.file), tofile=f"{args.file} (stamped)",
        )
        text = "".join(diff)
        print(text if text else "(no changes)")
    elif result["changed"]:
        save(args.file, doc)
        print(f"Wrote {args.file}")

    if args.require and entry is None:
        return 1
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("check", help="validate the file")
    p.add_argument("--file", default=DEFAULT_PATH, type=Path)
    p.set_defaults(func=_cmd_check)

    p = sub.add_parser("render", help="print one version's notes as shipped")
    p.add_argument("version")
    p.add_argument("--file", default=DEFAULT_PATH, type=Path)
    p.set_defaults(func=_cmd_render)

    p = sub.add_parser("stamp", help="turn 'unreleased' into a version (what deploy.py does)")
    p.add_argument("version")
    p.add_argument("--live", help="highest version on the App Store; folds never-released entries above it")
    p.add_argument("--refresh-date", action="store_true", help="set the entry's date to today (release)")
    p.add_argument("--require", action="store_true", help="exit 1 if the version ends up with no entry")
    p.add_argument("--dry-run", action="store_true", help="print the diff instead of writing")
    p.add_argument("--file", default=DEFAULT_PATH, type=Path)
    p.set_defaults(func=_cmd_stamp)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except WhatsNewError as e:
        print(f"✗ {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
