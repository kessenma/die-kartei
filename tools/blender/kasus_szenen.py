"""
kasus_szenen.py — die Figur in the Grammatik lessons (Verstehen · Lektion).

Run headless:
    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/blender/kasus_szenen.py -- --sheet

A case is a role in an event, so the lessons get the event: the model sentence acted out
(„Der Mann gibt dem Kind einen Ball.“) and a helper with the Dativ partner („Die Nachbarin hilft
dem Kind mit der Hausaufgabe.“). It reuses the verb-scene rig wholesale (verben.py: camera,
lights, props, die Figur, baked motion, the export check), and adds:

  - der Kind: a second, smaller Figur (the `staemmig` preset at 1.1, the toy-blocky one with the
    big head), so a grown-up and a child read at a glance.
  - Case colors on the cast, which is what makes a picture teach a case: the doer stays the plain
    charcoal Figur (the Nominativ is graphite, the dictionary form, nothing changed), the Dativ
    partner wears a teal torso, and the subject the app tints is the Akkusativ ball (orange) or
    the Dativ homework (teal). The lesson's sentence above the scene uses the same colors.
  - A few gestures and clips of their own (geben, nehmen, zeigen, leine) registered into figur
    at import, built so the hands hold still while the head moves: a thing passed between two
    hands has to arrive where the hand is.
  - Der Hund and die Katze from the story cast (tools/genprops/samples), for the chase rendered
    both ways round: `jagen-hund` (der Hund jagt die Katze) and `jagen-katze` (die Katze jagt den
    Hund). The chased one is the subject, so it takes the Akkusativ orange; the pair is the
    picture choice in „Wer macht was?“, where only the ending says which picture is right.
  - die Leine, a leash from the child's hand to the dog, as the Genitiv link in „der Hund des
    Kindes“: the owner wears the Genitiv brown torso and the leash is the tinted subject.

Modes (as verben.py):
  --sheet [IDS]       each scene's key frame, labelled
  --scene ID          one still (--state dat|neutral, --frame N)
  --preview [IDS]     low-quality frame sequences + an mp4 per scene, for judging motion
  --ship [IDS]        kasus3d-<id>.usdz, the dat and neutral stills, kasus3d-manifest.json,
                      all into Resources/
"""

import argparse
import json
import math
import os
import subprocess
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import figur
import prep_render as pr
import verben

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCES = verben.RESOURCES
OUT = os.path.join(HERE, "renders", "kasus")

G = verben.G
FH = pr.FIGUR_HEIGHT
P, L, F = verben.P, verben.L, verben.F

KIND_PRESET, KIND_HEIGHT = "staemmig", 1.1
DATIV = 0x0E8794          # CasePalette.dativ, light mode
AKKUSATIV = 0xE2701A      # CasePalette.akkusativ
GENITIV = 0x8A5A2B        # CasePalette.genitiv
# prep_render's own Genitiv is an older slate; the lessons use the app's brown, so a still and
# the live tint (GrammarCase.genitiv) agree.
pr.PALETTE["genitiv"] = GENITIV

# The story cast's samples face +X at these yaws (probed 2026-10-06), so yaw = heading + this.
HUND_FACE_X, KATZE_FACE_X = 140.0, 90.0


# MARK: - Gestures and clips
#
# Registered into figur's tables, so prep_render's `figur` reference can play them by name.

figur.GESTEN.update({
    # geben: the near arm held out level, palm up, a slight bow toward the receiver.
    "geben": {"torso": (-6, 0, 0), "head": (-6, 0, 0), "arm_r": (90, 0, 4)},
    "geben_nick": {"base": "geben", "head": (-16, 0, 0)},
    # nehmen: both hands forward and together, ready to catch.
    "nehmen": {"torso": (-2, 0, 0), "head": (2, 0, 0), "arm_l": (66, 0, -16), "arm_r": (66, 0, 16)},
    "nehmen_freude": {"base": "nehmen", "head": (16, 0, 0)},
    # zeigen: the helper bends over the desk and points at the sheet.
    "zeigen": {"torso": (-28, 0, 0), "head": (-22, 0, 0), "arm_r": (66, 0, 6), "arm_l": (8, 0, 0)},
    "zeigen_tipp": {"base": "zeigen", "arm_r": (58, 0, 6)},
    "zeigen_nick": {"base": "zeigen", "head": (-10, 0, 0)},
    # schauen: the child at the desk, looking down at the sheet, hands resting on it.
    "schauen": {"torso": (-12, 0, 0), "head": (-26, 0, 0), "arm_l": (54, 0, -8), "arm_r": (54, 0, 8)},
    "schauen_auf": {"base": "schauen", "head": (6, 0, 0)},
    # leine: holding the dog's leash low and forward, looking down at the dog.
    "leine": {"torso": (-4, 0, 0), "head": (-14, 0, 0), "arm_r": (34, 0, 2)},
    "leine_lacht": {"base": "leine", "head": (6, 0, 0)},
})

figur.CLIPS.update({
    # Head only after frame 0, so the hand holding out the ball never moves.
    "geben": {"verbs": "geben (Kasus-Lektion)", "beats": [
        (0, "geben"), (10, "geben_nick"), (22, "geben"), (72, "geben")]},
    "nehmen": {"verbs": "geben (Kasus-Lektion)", "beats": [
        (0, "nehmen"), (12, "nehmen"), (22, "nehmen_freude", "out"), (44, "nehmen_freude"), (60, "nehmen"),
        (72, "nehmen")]},
    "zeigen": {"verbs": "helfen (Kasus-Lektion)", "beats": [
        (0, "zeigen"), (8, "zeigen_tipp"), (16, "zeigen"), (24, "zeigen_tipp"), (32, "zeigen"),
        (52, "zeigen_nick"), (72, "zeigen")]},
    "schauen": {"verbs": "helfen (Kasus-Lektion)", "beats": [
        (0, "schauen"), (36, "schauen"), (46, "schauen_auf", "out"), (58, "schauen_auf"), (72, "schauen")]},
    "leine": {"verbs": "des Kindes (Kasus-Lektion)", "beats": [
        (0, "leine"), (20, "leine"), (32, "leine_lacht", "out"), (48, "leine_lacht"), (60, "leine"),
        (72, "leine")]},
})


# MARK: - The cast


def mann(**spec):
    return ("figur", {"height": FH, **spec})


def kind(**spec):
    """Das Kind: smaller and blockier, its torso in the case color it plays."""
    return ("figur", {"name": "kind", "preset": KIND_PRESET, "height": KIND_HEIGHT, **spec})


def hand(at, yaw, pose, role="arm_r", mirror=False, preset="standard", height=FH):
    return figur.hand_position(at, yaw, pose, role, mirror, preset=preset, height=height)


# MARK: - The scenes

# Der Mann gibt dem Kind einen Ball: the ball leaves his hand, arcs over, lands in the child's,
# vanishes, and is back in his hand. t = 0 is mid-flight, so a still shows it on its way.
_MANN_AT, _KIND_AT = (-1.0, 0.0, G), (0.8, 0.0, G)
_BALL_R = 0.15
_GIBT = hand(_MANN_AT, P, "geben") + Vector((0, 0, 0.02))
_NIMMT = (hand(_KIND_AT, L, "nehmen", "arm_r", True, KIND_PRESET, KIND_HEIGHT)
          + hand(_KIND_AT, L, "nehmen", "arm_l", True, KIND_PRESET, KIND_HEIGHT)) / 2
_FLUG = (_GIBT + _NIMMT) / 2 + Vector((0, 0, 0.42))


def _ball_base(center):
    return tuple(center - Vector((0, 0, _BALL_R)))


def _rel(point):
    start = Vector(_ball_base(_FLUG))
    return tuple(Vector(_ball_base(point)) - start)


_GEBEN_KEYS = [
    (0, (0, 0, 0)),
    (0.14, _rel(_NIMMT), "in"),
    (0.52, _rel(_NIMMT)),
    (0.62, _rel(_NIMMT)),
    (0.66, _rel(_GIBT)),
    (0.86, _rel(_GIBT)),
    (1.0, (0, 0, 0), "out"),
]
_GEBEN_SCALE = [(0, 1), (0.52, 1), (0.6, 0, "in"), (0.68, 0), (0.78, 1, "out"), (1, 1)]

# Die Nachbarin hilft dem Kind mit der Hausaufgabe: a desk at the child's height, the sheet on
# it, the child looking down; the neighbour bends over and taps the sheet, nods, taps again.
_TISCH_TOP = -0.24          # the desk's top surface, a little under the child's hands
_TISCH = {"size": (1.05, 0.72, _TISCH_TOP - 0.11 - G), "at": (0.05, 0.0, _TISCH_TOP - 0.11)}
_BLATT_AT = (0.02, -0.06, _TISCH_TOP + 0.01)

# Der Hund jagt die Katze / die Katze jagt den Hund: both run one lap of a circle in front of
# the camera, the chaser a little behind, both bounding. t = 0 has them crossing the front of the
# circle left to right, chaser on the left, so a still reads as a chase.
_RUNDE_MITTE, _RUNDE_R = Vector((0.15, 0.9, G)), 1.45
_VORNE, _ABSTAND = -62.0, 64.0           # where the chased starts (deg), and the chaser's lag


def _auf_runde(angle):
    a = math.radians(angle)
    return _RUNDE_MITTE + Vector((_RUNDE_R * math.cos(a), _RUNDE_R * math.sin(a), 0))


def _runde(start_angle, hops=6, hop=0.13, steps=48):
    """Keys for one lap counter-clockwise from `start_angle`, bounding `hops` times, and the turn
    that keeps the animal facing the way it runs."""
    keys, spin = [], []
    origin = _auf_runde(start_angle)
    for i in range(steps + 1):
        t = i / steps
        angle = start_angle + 360 * t
        lift = hop * abs(math.sin(math.pi * hops * t))
        offset = _auf_runde(angle) - origin + Vector((0, 0, lift))
        keys.append((t, tuple(offset), "linear"))
        spin.append((t, 360 * t))
    return keys, spin


def _heading(angle, face_x):
    """The yaw that faces an animal along the lap (counter-clockwise tangent) at `angle`."""
    return angle + 90 + face_x


def _jagd(chaser, chased):
    """The chase with `chaser` behind and `chased` (the subject, Akkusativ) ahead."""
    heights = {"hund": 0.82, "katze": 0.62}
    faces = {"hund": HUND_FACE_X, "katze": KATZE_FACE_X}
    vorne, hinten = _VORNE, _VORNE - _ABSTAND
    jaeger_keys, jaeger_spin = _runde(hinten, hops=6)
    beute_keys, beute_spin = _runde(vorne, hops=7)
    return {
        "governs": "akkusativ",
        "ref": [("mesh", {"file": chaser, "name": "jaeger", "at": tuple(_auf_runde(hinten)),
                          "height": heights[chaser], "yaw": _heading(hinten, faces[chaser])})],
        "subject_mesh": {"file": chased, "height": heights[chased], "yaw": _heading(vorne, faces[chased])},
        "at": tuple(_auf_runde(vorne)),
        "period": 96,
        "motion": [("jaeger", jaeger_keys, {"spin": jaeger_spin}),
                   ("subject", beute_keys, {"spin": beute_spin})],
    }


# Der Hund des Kindes: the child holds the dog on a leash; the dog bounces, the leash with it.
_LEINE_KIND = (-0.75, 0.05, G)
_LEINE_HAND = hand(_LEINE_KIND, P, "leine", "arm_r", False, KIND_PRESET, KIND_HEIGHT)
_HUND_AT = (0.55, 0.1, G)
_HUPF = [(0, (0, 0, 0)), (0.12, (0, 0, 0.09), "out"), (0.24, (0, 0, 0), "in"),
         (0.36, (0, 0, 0.09), "out"), (0.48, (0, 0, 0), "in"), (1, (0, 0, 0))]


def _leine(at, mat, ref_mat=None, spec=None):
    """Die Leine: a thin rod from the child's hand to the dog's collar, which is read off the dog
    already in the scene (its front, at 70 % of its height). Joined as the subject."""
    dog = bpy.data.objects[spec["dog"]]
    corners = [dog.matrix_world @ Vector(c) for c in dog.bound_box]
    zmin, zmax = min(v.z for v in corners), max(v.z for v in corners)
    front = min(corners, key=lambda v: v.x)
    collar = Vector((front.x + 0.12, sum(v.y for v in corners) / 8, zmin + 0.7 * (zmax - zmin)))
    start = Vector(at)
    span = collar - start
    # A slight sag: two segments meeting below the straight line.
    mid = (start + collar) / 2 + Vector((0, 0, -0.12))
    parts = []
    for a, b in ((start, mid), (mid, collar)):
        d = b - a
        bpy.ops.mesh.primitive_cylinder_add(radius=0.022, depth=d.length, vertices=12,
                                            location=(a + b) / 2)
        rod = bpy.context.active_object
        rod.rotation_mode = "QUATERNION"
        rod.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
        rod.data.materials.append(mat)
        parts.append(rod)
    del span
    return pr._join_as_subject(parts, at)


pr.SUBJECT_BUILDERS["leine"] = _leine

SCENES = {
    "jagen-hund": {"sentence": "Der Hund jagt die Katze.", **_jagd("hund", "katze")},
    "jagen-katze": {"sentence": "Die Katze jagt den Hund.", **_jagd("katze", "hund")},
    "leine": {
        "sentence": "Der Hund des Kindes spielt.",
        "governs": "genitiv",
        "ref": [kind(at=_LEINE_KIND, clip="leine", yaw=P, accent=GENITIV),
                ("mesh", {"file": "hund", "name": "hund", "at": _HUND_AT, "height": 0.82,
                          "yaw": 180 + HUND_FACE_X})],
        "subject_build": "leine", "subject_spec": {"dog": "hund"},
        "at": tuple(_LEINE_HAND),
        "period": 72,
        "motion": [("hund", _HUPF), ("subject", _HUPF)],
    },
    "geben": {
        "sentence": "Der Mann gibt dem Kind einen Ball.",
        "governs": "akkusativ",
        "ref": [mann(at=_MANN_AT, clip="geben", yaw=P),
                kind(at=_KIND_AT, clip="nehmen", yaw=L, mirror=True, accent=DATIV)],
        "subject_build": "ball", "subject_spec": {"r": _BALL_R},
        "at": _ball_base(_FLUG),
        "period": 72,
        "motion": [("subject", _GEBEN_KEYS, {"scale": _GEBEN_SCALE})],
    },
    "helfen": {
        "sentence": "Die Nachbarin hilft dem Kind mit der Hausaufgabe.",
        "governs": "dativ",
        "ref": [("table", _TISCH),
                kind(at=(-0.85, 0.05, G), clip="schauen", yaw=P, accent=DATIV),
                mann(at=(0.95, 0.12, G), clip="zeigen", yaw=L, mirror=True)],
        "subject_build": "ref", "subject_spec": {"kind": "slab", "size": (0.46, 0.34, 0.025)},
        "at": _BLATT_AT,
        "period": 72,
    },
}


# MARK: - Building


def relation(scene_id):
    spec = SCENES[scene_id]
    period = spec["period"]
    rel = {k: v for k, v in spec.items() if k not in ("at", "motion", "period", "sentence")}
    rel["dat"] = {"subject": spec["at"]}
    rel["ref"] = [(k, {**s, "period": period}) if k == "figur" and s.get("clip") else (k, s)
                  for k, s in spec["ref"]]
    return rel, period


def build_scene(scene_id, state="dat", size=512, samples=None):
    rel, period = relation(scene_id)
    pr.build_relation(rel, state, "dim", size)
    # USD turns a hyphen into an underscore, so name the moved prim the way the export (and
    # the twin check) will see it.
    moved = verben.bake_motion(scene_id.replace("-", "_"), SCENES[scene_id].get("motion", []), period)
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = period + 1
    scene.frame_set(1)
    if samples:
        scene.eevee.taa_render_samples = samples
    return rel, moved


def asset(scene_id):
    return f"kasus3d-{scene_id}"


# MARK: - Modes


def report():
    """The analytic hand points, so a pass over the numbers comes before a render."""
    print(f"GEBEN hand {tuple(round(v, 3) for v in _GIBT)} → child {tuple(round(v, 3) for v in _NIMMT)}, "
          f"flight {tuple(round(v, 3) for v in _FLUG)}")
    a = hand(_KIND_AT, L, "nehmen", "arm_r", True, KIND_PRESET, KIND_HEIGHT)
    b = hand(_KIND_AT, L, "nehmen", "arm_l", True, KIND_PRESET, KIND_HEIGHT)
    print(f"GEBEN child hands {(a - b).length:.3f} apart (ball ⌀ {2 * _BALL_R:.2f})")


def sheet(ids, size, samples):
    os.makedirs(OUT, exist_ok=True)
    cells = []
    for scene_id in ids:
        build_scene(scene_id, "dat", size, samples)
        figur.add_label(SCENES[scene_id]["sentence"], size=0.03)
        path = os.path.join(OUT, f"{scene_id}.png")
        pr.render_to(path)
        cells.append(path)
        print(f"SHEET {scene_id}")
    if len(cells) > 1:
        figur.contact_sheet(cells, len(cells), os.path.join(OUT, "kasus-szenen.png"))


def export(ids, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    results = {}
    for scene_id in ids:
        pr._LOD = "low"
        rel, moved = build_scene(scene_id, "dat", 256)
        verben.slim()
        out = os.path.join(out_dir, f"{asset(scene_id)}.usdz")
        twin = os.path.join(OUT, f"{asset(scene_id)}.usda")
        pr.export_usdz(out, animated=True, twin=twin)
        results[scene_id] = pr.check_export(out, rel, twin, extra_allowed=moved)
    failed = [k for k, ok in results.items() if not ok]
    print(f"EXPORT {len(results) - len(failed)}/{len(results)} OK" + (f" — FAILED {failed}" if failed else ""))
    return not failed


def ship(ids, size=512, samples=128):
    """Stills (full detail) into Resources/, then the slimmed, checked USDZs, then the manifest,
    every entry `baked` so PrepositionSceneView plays the clips."""
    for scene_id in ids:
        pr._LOD = "high"
        for state in ("neutral", "dat"):
            build_scene(scene_id, state, size, samples)
            pr.render_to(os.path.join(RESOURCES, f"{asset(scene_id)}-{state}-dim.png"))
        print(f"STILLS {scene_id}")
    ok = export(ids, RESOURCES)
    manifest = {"relations": {asset(s): {"asset": asset(s), "akkOffset": [0, 0, 0], "baked": True}
                              for s in SCENES}}
    with open(os.path.join(RESOURCES, "kasus3d-manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
    print(f"SHIP {len(ids)} scenes → {RESOURCES}" + ("" if ok else " — EXPORT CHECK FAILED"))
    return ok


def preview(ids, size, samples, step):
    for scene_id in ids:
        frames_dir = os.path.join(OUT, "preview", scene_id)
        os.makedirs(frames_dir, exist_ok=True)
        for old in os.listdir(frames_dir):
            os.remove(os.path.join(frames_dir, old))
        build_scene(scene_id, "dat", size, samples)
        scene = bpy.context.scene
        for i, frame in enumerate(range(scene.frame_start, scene.frame_end, step)):
            scene.frame_set(frame)
            pr.render_to(os.path.join(frames_dir, f"f{i:04d}.png"))
        mp4 = os.path.join(OUT, "preview", f"{scene_id}.mp4")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(24 // step),
                        "-i", os.path.join(frames_dir, "f%04d.png"),
                        "-vf", "format=rgba,split[a][b];[b]drawbox=c=0xF3EFE6:t=fill[bg];[bg][a]overlay,format=yuv420p",
                        mp4], check=True)
        print(f"PREVIEW {mp4}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", nargs="*", metavar="ID")
    ap.add_argument("--scene", choices=sorted(SCENES))
    ap.add_argument("--state", default="dat", choices=["dat", "neutral"])
    ap.add_argument("--frame", type=int, default=0)
    ap.add_argument("--preview", nargs="*", metavar="ID")
    ap.add_argument("--ship", nargs="*", metavar="ID")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--samples", type=int, default=64)
    ap.add_argument("--step", type=int, default=3)
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)
    report()
    if args.sheet is not None:
        sheet(args.sheet or list(SCENES), args.size, args.samples)
    elif args.scene:
        build_scene(args.scene, args.state, args.size, args.samples)
        bpy.context.scene.frame_set(args.frame + 1)
        pr.render_to(args.out or os.path.join(OUT, f"{args.scene}-{args.state}-f{args.frame}.png"))
    elif args.preview is not None:
        preview(args.preview or list(SCENES), min(args.size, 320), min(args.samples, 16), args.step)
    elif args.ship is not None:
        if not ship(args.ship or list(SCENES)):
            sys.exit(1)


if __name__ == "__main__":
    main()
