#!/usr/bin/env python3
"""Android icons: one `<sf-name>.symbolset` per SF Symbol name the app uses, drawn from
Material Symbols Rounded (Apache-2.0) and, where the audit found a better match, Phosphor (MIT),
Lucide (ISC) or Tabler (MIT). Never SF Symbols themselves: Apple's licence keeps them on Apple
platforms (docs/android-parity/icons.md §2).

SkipUI's `Image(systemName:)` looks for `<name>.symbolset` in the app's asset catalogs before its
own small Material table, so the iOS names work unchanged on Android.

    python3 scripts/android_symbols.py              # (re)generate every symbolset
    python3 scripts/android_symbols.py --only checklist,house.fill
    python3 scripts/android_symbols.py --preview /tmp/sheet.html   # contact sheet, NonZero fill
    python3 scripts/android_symbols.py --check      # guard: every symbol literal has a symbolset

Needs `picosvg` (pip install picosvg) for the Phosphor/Lucide/Tabler wraps: it turns Lucide and
Tabler strokes into filled outlines and every path into NonZero winding, which is the only fill
rule SkipUI uses. Downloads are cached in $ICONS_CACHE (default ~/.hermes/cache/scratch/icons-cache).

How SkipUI reads the template (skip-ui Image.swift, RenderSymbolImage): it takes the `d` of the
direct `<path>` children of `<g id="Symbols">/<g id="<Weight>-<S|M|L>">`, ignores every
`transform`, centres the union of the path bounds, and sizes the glyph from the `Baseline-M` and
`Capline-M` guide lines (cap height = 0.7046 em). So wrapped paths are written in the Google
template's own coordinates (24-unit grid = 120 units, glyph centre at y = -35.23 from the baseline)
with the transform already applied.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import csv
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSV = ROOT / "docs/android-parity/icon-map.csv"
PKG = ROOT / "DieKarteiAndroid"
OUT = Path(os.environ.get("SYMBOLS_OUT", PKG / "Sources/DieKartei/Resources/Module.xcassets/Symbols"))
CACHE = Path(os.environ.get("ICONS_CACHE", Path.home() / ".hermes/cache/scratch/icons-cache"))

MATERIAL_URL = ("https://raw.githubusercontent.com/google/material-design-icons/master/symbols/ios/"
                "{n}/materialsymbolsrounded/{n}{v}_symbol.svg")
PHOSPHOR_URL = "https://raw.githubusercontent.com/phosphor-icons/core/main/assets/{w}/{n}{s}.svg"
LUCIDE_URL = "https://raw.githubusercontent.com/lucide-icons/lucide/main/icons/{n}.svg"
TABLER_URL = "https://raw.githubusercontent.com/tabler/tabler-icons/main/icons/{k}/{n}.svg"

# Weight groups kept from Google's 27 (Medium scale only; SkipUI falls back across weights).
KEEP = ["Light-M", "Regular-M", "Semibold-M", "Bold-M"]
# Phosphor's regular stroke is 16/256 of the box (1.5 on a 24 grid), lighter than Material
# Rounded 400 (2.0); bold (24/256 = 2.25) is the closer match for Regular.
PHOSPHOR_WEIGHTS = {"Light-M": "regular", "Regular-M": "bold", "Semibold-M": "bold", "Bold-M": "bold"}
# Lucide/Tabler stroke widths on their 24 grid per template weight.
STROKE_WIDTHS = {"Light-M": 1.5, "Regular-M": 2.0, "Semibold-M": 2.25, "Bold-M": 2.5}

# Google template geometry (Medium): baseline y=1126, capline y=1055.54; a 24-unit icon box is
# 120 units wide with its centre at (60, -35.23) relative to the baseline origin.
BASELINE_M, CAPLINE_M = 1126.0, 1055.54
BOX, CENTRE_Y = 120.0, -35.23
GROUP_X = {"Light-M": 1098.18, "Regular-M": 1394.06, "Semibold-M": 1689.91, "Bold-M": 1985.97}

RANK = {"exact": 0, "close": 1, "concept": 2, "none": 3}
LIBS = {"Phosphor (MIT)": "phosphor", "Lucide (ISC)": "lucide", "Tabler (MIT)": "tabler"}

# Names where the CSV has no usable match, or where its suggestion needs a fix-up.
OVERRIDES = {
    "apple.intelligence": ("material", "auto_awesome", False),  # iOS-only path; generic sparkle
    "circle.square": ("tabler", "square-dot", False),           # pending custom Bauhaus drawing
    # `laptop` is only a codepoint alias; Google's iOS templates have `computer` (same glyph).
    "laptopcomputer": ("material", "computer", False),
    "macbook": ("material", "computer", False),
}
# Lucide/Tabler names that have a Tabler `filled` drawing, used for the `.fill` SF names.
TABLER_FILLED = {"circle-letter-a", "circle-letter-d", "circle-letter-e", "square-letter-a",
                 "zoom-exclamation", "square-dot"}
# icons.md §4: the custom Bauhaus set. Shipped with the best library match for now.
PENDING_CUSTOM = ["rectangle.stack", "rectangle.stack.fill", "brain.head.profile",
                  "brain.head.profile.fill", "figure.stairs", "pyramid.fill", "hare.fill",
                  "circle.square", "square.on.circle", "circle.lefthalf.striped.horizontal",
                  "square.grid.3x3.topleft.filled", "square.grid.3x3.bottomleft.filled"]
# Names the app uses (Android UI module) that the iOS audit didn't list.
EXTRA = {
    "list.bullet": ("material", "format_list_bulleted", False),
    "person.fill": ("material", "person", True),
    "star.fill": ("material", "star", True),
}


def is_fill_name(sf: str) -> bool:
    return sf.endswith(".fill") or ".fill." in sf or sf.endswith(".filled")


def choose(row: dict) -> tuple[str, str, bool, str]:
    """(library, icon name, filled, reason) for one CSV row."""
    sf = row["sf_symbol"]
    if sf in OVERRIDES:
        lib, name, fill = OVERRIDES[sf]
        return lib, name, fill, "override"
    mat, mq = row["material_symbol"], row["match_quality"] or "none"
    fill = "FILL1" in row["material_style"] or is_fill_name(sf)
    alt_lib = LIBS.get(row["alternate_library"], "")
    m = re.match(r"alt match=(\w+)", row["notes"])
    aq = m.group(1) if m else "close"
    if alt_lib and (RANK.get(aq, 1) < RANK.get(mq, 3) or not mat):
        name = row["alternate_name"]
        if fill and alt_lib in ("lucide", "tabler"):
            if name in TABLER_FILLED:
                return "tabler", name, True, f"alt {aq} > material {mq}"
            if mat:  # stroke-only alternate: keep the filled Material glyph for the .fill name
                return "material", mat, True, f"stroke-only alt {alt_lib}:{name} has no fill"
            return alt_lib, name, False, "outline stands in for fill"
        return alt_lib, name, fill, f"alt {aq} > material {mq}"
    if not mat:
        raise SystemExit(f"no source for {sf}")
    return "material", mat, fill, ""


# ---------------------------------------------------------------- downloads

def fetch(url: str, dest: Path) -> str:
    if dest.exists() and dest.stat().st_size > 0:
        return dest.read_text()
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=60) as r:
        data = r.read().decode()
    dest.write_text(data)
    return data


def material_template(name: str, fill: bool) -> str:
    v = "_fill1" if fill else ""
    return fetch(MATERIAL_URL.format(n=name, v=v), CACHE / "material" / f"{name}{v}_symbol.svg")


def phosphor_svg(name: str, weight: str) -> str:
    s = "" if weight == "regular" else f"-{weight}"
    return fetch(PHOSPHOR_URL.format(w=weight, n=name, s=s), CACHE / "phosphor" / weight / f"{name}{s}.svg")


def lucide_svg(name: str) -> str:
    return fetch(LUCIDE_URL.format(n=name), CACHE / "lucide" / f"{name}.svg")


def tabler_svg(name: str, filled: bool) -> str:
    k = "filled" if filled else "outline"
    return fetch(TABLER_URL.format(k=k, n=name), CACHE / "tabler" / k / f"{name}.svg")


# ---------------------------------------------------------------- template output

def strip_material(svg: str) -> str:
    """Keep the six Baseline/Capline guides (Xcode's actool rejects a template without all of
    them, and the Darwin side of the Skip build runs actool) and the KEEP weight groups; drop
    Notes, the H-reference glyphs and the other 23 weight groups."""
    lines = "".join(re.findall(r'<line id="(?:Baseline|Capline)-[SML]"[^>]*/>', svg))
    groups = []
    for gid in KEEP:
        m = re.search(r'<g id="%s"[^>]*>.*?</g>' % re.escape(gid), svg, re.S)
        if m:
            groups.append(m.group(0))
    if "Regular-M" not in "".join(groups) or "Capline-M" not in lines:
        raise ValueError("template without Regular-M / guides")
    return wrap_svg(lines, "".join(groups))


def wrap_svg(guides: str, groups: str) -> str:
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="3300" height="2000">'
            f'<g id="Guides">{guides}</g><g id="Symbols">{groups}</g></svg>\n')


# Google's guide lines (baseline, capline) per scale; actool needs all six.
GUIDE_Y = {"S": (696, 625.541), "M": (BASELINE_M, CAPLINE_M), "L": (1556, 1485.54)}
GUIDES_M = "".join(
    f'<line id="{kind}-{sc}" style="fill:none;stroke:#27AAE1;stroke-width:0.577;" x1="263" x2="3036" '
    f'y1="{y:g}" y2="{y:g}"/>'
    for sc, ys in GUIDE_Y.items() for kind, y in zip(("Baseline", "Capline"), ys))


def nonzero_path(svg_text: str, box: float, stroke_width: float | None = None) -> str:
    """One NonZero path `d` in template coordinates from a 24- or 256-unit icon SVG."""
    from picosvg.svg import SVG
    from picosvg.svg_pathops import remove_overlaps, transform, skia_path, svg_commands
    from picosvg.svg_transform import Affine2D
    from picosvg.svg_types import SVGPath
    import pathops

    if stroke_width is not None:
        svg_text = re.sub(r'stroke-width="[\d.]+"', f'stroke-width="{stroke_width}"', svg_text)
    # Tabler draws an invisible bounding rect `<path stroke="none" d="M0 0h24v24H0z" fill="none"/>`.
    svg_text = re.sub(r'<path[^>]*stroke="none"[^>]*/>', "", svg_text)
    pico = SVG.fromstring(svg_text).topicosvg()
    union = pathops.Path()
    for shape in pico.shapes():
        p = shape.as_path()
        clean = skia_path(remove_overlaps(p.as_cmd_seq(), p.fill_rule), "nonzero")
        union = pathops.op(union, clean, pathops.PathOp.UNION, fix_winding=True)
    s = BOX / box
    cmds = transform(svg_commands(union), Affine2D(s, 0, 0, s, 0, CENTRE_Y - BOX / 2))
    path = SVGPath.from_commands(cmds).round_floats(2)
    return path.d


def wrapped_template(paths: dict[str, str]) -> str:
    groups = "".join(f'<g id="{gid}" transform="matrix(1 0 0 1 {GROUP_X[gid]:g} {BASELINE_M:g})">'
                     f'<path d="{d}"/></g>' for gid, d in paths.items())
    return wrap_svg(GUIDES_M, groups)


def build_svg(lib: str, name: str, fill: bool) -> str:
    if lib == "material":
        return strip_material(material_template(name, fill))
    if lib == "phosphor":
        if fill:
            d = nonzero_path(phosphor_svg(name, "fill"), 256)
            return wrapped_template({gid: d for gid in KEEP})
        cache: dict[str, str] = {}
        for w in set(PHOSPHOR_WEIGHTS.values()):
            cache[w] = nonzero_path(phosphor_svg(name, w), 256)
        return wrapped_template({gid: cache[PHOSPHOR_WEIGHTS[gid]] for gid in KEEP})
    if lib == "tabler" and fill:
        d = nonzero_path(tabler_svg(name, True), 24)
        return wrapped_template({gid: d for gid in KEEP})
    src = lucide_svg(name) if lib == "lucide" else tabler_svg(name, False)
    return wrapped_template({gid: nonzero_path(src, 24, STROKE_WIDTHS[gid]) for gid in KEEP})


CONTENTS = '{"symbols":[{"filename":"%s.svg","idiom":"universal"}],"info":{"author":"xcode","version":1}}\n'


def write_symbolset(sf: str, svg: str) -> None:
    d = OUT / f"{sf}.symbolset"
    d.mkdir(parents=True, exist_ok=True)
    for old in d.glob("*.svg"):
        if old.name != f"{sf}.svg":
            old.unlink()
    (d / f"{sf}.svg").write_text(svg)
    (d / "Contents.json").write_text(CONTENTS % sf)


def plan() -> dict[str, tuple[str, str, bool, str]]:
    with open(CSV, newline="") as f:
        rows = list(csv.DictReader(f))
    out = {r["sf_symbol"]: choose(r) for r in rows}
    for sf, (lib, name, fill) in EXTRA.items():
        out.setdefault(sf, (lib, name, fill, "android-only name"))
    return out


# ---------------------------------------------------------------- guard

SYMBOL_CONTEXT = re.compile(r'(?:systemName|systemImage|selectedIcon|icon|symbol|image)\s*:\s*"([a-z0-9.]+)"')
BARE_LITERAL = re.compile(r'"([a-z0-9]+(?:\.[a-z0-9]+)+|[a-z]+[0-9]*)"')


def symbol_literals() -> dict[str, set[str]]:
    """Every SF-Symbol-looking literal in the Android UI module and the shared core files.

    Literals in a symbol context (`systemName:` …) are always taken. Other literals are taken when
    they are a known SF name from the audit's map (enum `var systemImage` switches return bare
    strings), so English words that happen to be symbol names only count where the map has them.
    """
    known = set(plan())
    files = list((PKG / "Sources/DieKartei").glob("*.swift"))
    files += [p for p in (PKG / "Sources/DieKarteiCore").rglob("*.swift")]
    found: dict[str, set[str]] = {}
    for f in files:
        text = f.read_text(errors="ignore")
        for m in SYMBOL_CONTEXT.finditer(text):
            found.setdefault(m.group(1), set()).add(f.name)
        for m in BARE_LITERAL.finditer(text):
            if m.group(1) in known and "." in m.group(1):
                found.setdefault(m.group(1), set()).add(f.name)
        # `var systemImage/icon: String { switch … case .x: "name" }` bodies
        for body in re.findall(r'var (?:systemImage|icon|symbol|symbolName|iconName)\s*:\s*String\s*\{(.*?)\n    \}', text, re.S):
            for lit in re.findall(r'"([a-z0-9.]+)"', body):
                found.setdefault(lit, set()).add(f.name)
    return found


def check() -> int:
    have = {p.name[: -len(".symbolset")] for p in OUT.glob("*.symbolset")}
    missing = {n: fs for n, fs in symbol_literals().items() if n not in have}
    if missing:
        for n, fs in sorted(missing.items()):
            print(f"missing symbolset: {n}  ({', '.join(sorted(fs))})")
        return 1
    print(f"ok: every symbol literal has a symbolset ({len(have)} shipped)")
    return 0


# ---------------------------------------------------------------- preview

def preview(path: Path, names: list[str]) -> None:
    """HTML contact sheet of the Regular-M paths, centred on their bounds and filled NonZero the
    way SkipUI draws them. Open it in a browser to spot inverted cut-outs and odd sizes."""
    cells = []
    for sf in names:
        f = OUT / f"{sf}.symbolset" / f"{sf}.svg"
        if not f.exists():
            continue
        svg = f.read_text()
        m = re.search(r'<g id="Regular-M"[^>]*>(.*?)</g>', svg, re.S)
        ds = re.findall(r'<path[^>]* d="([^"]+)"', m.group(1)) if m else []
        p = "".join(f'<path fill-rule="nonzero" d="{d}"/>' for d in ds)
        cells.append(f'<div class="c"><svg viewBox="-10 -105 140 140" width="56" height="56">{p}</svg>'
                     f'<span>{sf}</span></div>')
    path.write_text("<html><style>body{font:9px sans-serif;display:flex;flex-wrap:wrap}"
                    ".c{width:96px;height:84px;text-align:center;overflow:hidden}"
                    "svg{display:block;margin:0 auto;background:#eef}</style><body>"
                    + "".join(cells) + "</body></html>")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated SF names")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--preview")
    ap.add_argument("--report", help="write the chosen source per name as JSON")
    a = ap.parse_args()
    if a.check:
        return check()
    p = plan()
    names = a.only.split(",") if a.only else sorted(p)
    if a.preview:
        preview(Path(a.preview), names)
        return 0

    def one(sf: str):
        lib, name, fill, why = p[sf]
        try:
            write_symbolset(sf, build_svg(lib, name, fill))
            return sf, lib, name, fill, why, None
        except Exception as e:  # report and carry on; the guard catches what's missing
            return sf, lib, name, fill, why, f"{type(e).__name__}: {e}"

    with cf.ThreadPoolExecutor(8) as ex:
        results = list(ex.map(one, names))
    errors = [r for r in results if r[5]]
    for r in errors:
        print("FAILED", r)
    if a.report:
        Path(a.report).write_text(json.dumps(
            [dict(sf=r[0], lib=r[1], name=r[2], fill=r[3], why=r[4], error=r[5],
                  pending_custom=r[0] in PENDING_CUSTOM) for r in results], indent=1))
    by = {}
    for r in results:
        if not r[5]:
            by[r[1]] = by.get(r[1], 0) + 1
    print("written:", by, "failed:", len(errors))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
