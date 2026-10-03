"""
verben.py — the Verben-mit-Präpositionen scenes (prototype).

Run headless:
    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/blender/verben.py -- --sheet

Built as a prototype apart from the shipped preposition set (Kyle, 2026-10-02), then joined to
the app's preposition hub (docs/VERB_PREPOSITIONS.md). The data is the app's own
Resources/verb_prepositions.json, so a scene and its sentence come from one file. Judging output
lands in tools/blender/renders/verben/ (gitignored); only `--ship` writes to Resources/.

It reuses the preposition rig wholesale (camera, lights, palette, props, die Figur) through
prep_render.build_relation, and adds what the verb scenes need on top:

  - More props (bus, pokal, kiste, äpfel, leiter, käfer, rahmen, ball, rudel) and two held ones
    (hammer, lupe), registered into prep_render's tables at import.
  - Baked motion. The shipped scenes move their subject at runtime (the manifest's `motion`
    kinds). Here every motion is baked into the USDZ instead, so Quick Look shows a scene
    exactly as the app would, and the runtime would only have to tint it and press play. A
    moving thing is re-parented under a still holder, which is what the runtime positions; the
    clip moves the child inside it. For the subject the holder keeps the name `subject` (the
    runtime finds and positions that) and the tinted mesh inside becomes `<scene>_bewegt`,
    a name without "subject" in it, so `--verify`'s never-animate-the-subject rule still holds
    for the prim the runtime writes.

Modes:
  --sheet             every scene's key frame, resolved, labelled with its verbs and sentence
  --scene ID          one still (--state dat|neutral)
  --usdz [IDS]        verb3d-<id>.usdz + .usda twin per scene, each checked like --verify
  --preview [IDS]     low-quality frame sequences + one looping grid video
  --ship [IDS]        what the app loads: verb3d-<id>.usdz (dog meshes slimmed), the neutral and
                      resolved stills, and verb3d-manifest.json, all into Resources/
"""

import argparse
import json
import math
import os
import subprocess
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import figur
import prep_render as pr

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCES = os.path.normpath(os.path.join(HERE, "..", "..", "german-ai-flashcards", "Resources"))
# The app owns the data; the rig renders from the same file, so a scene and its sentence
# cannot drift apart.
DATA = os.path.normpath(os.path.join(HERE, "..", "..", "german-ai-flashcards", "Resources",
                                    "verb_prepositions.json"))
OUT = os.path.join(HERE, "renders", "verben")

G = -0.75                       # the figure ground every preposition scene stands on
FH = pr.FIGUR_HEIGHT
P, L, F = (figur.STAGING_YAW[k] for k in ("profil", "profil_links", "front"))
# The hund sample faces +X at yaw 140 (mit, nach), so these turn it to face left / the camera.
HUND_LINKS, HUND_KAMERA = -40.0, 71.0


# MARK: - Props
#
# Same rules as prep_render's VERB_PROPS: primitives in the one charcoal, each joined into one
# object, `at` the base point, faces toward -Y and turned by `yaw`.


def _ball_ref(spec, mat):
    x, y, z = spec["at"]
    r = spec.get("r", 0.25)
    return [pr._merge([pr._ball((x, y, z + r), r, mat, "ball")], "reference.ball", (x, y, z))]


def _bus(spec, mat):
    """Der Bus, side-on, front toward -X (toward the stop). warten auf."""
    base = Vector(spec["at"])
    x, y, z = base
    s = spec.get("scale", 1.0)
    length, depth, height, clear = 2.2 * s, 0.95 * s, 1.05 * s, 0.18 * s
    body_z = z + clear + height / 2
    parts = [pr.add_box((length, depth, height), (x, y, body_z), mat, "bus")]
    # Window panes proud of the near side, and a taller windscreen at the front end.
    for i in range(4):
        parts.append(pr.add_box((0.34 * s, 0.05 * s, 0.32 * s),
                                (x - length / 2 + 0.62 * s + i * 0.45 * s, y - depth / 2 - 0.02 * s,
                                 body_z + height * 0.16), mat, "bus"))
    parts.append(pr.add_box((0.05 * s, depth * 0.8, 0.45 * s),
                            (x - length / 2 - 0.02 * s, y, body_z + height * 0.1), mat, "bus"))
    for wx in (-0.3, 0.3):
        for wy in (-1, 1):
            bpy.ops.mesh.primitive_cylinder_add(radius=0.2 * s, depth=0.12 * s,
                                                vertices=16 if pr._LOD == "low" else 32,
                                                location=(x + wx * length, y + wy * depth / 2, z + 0.2 * s),
                                                rotation=(math.radians(90), 0, 0))
            wheel = bpy.context.active_object
            wheel.data.materials.append(mat)
            parts.append(wheel)
    return [pr._merge(parts, "reference.bus", base, spec.get("yaw", 0.0))]


def _pokal(spec, mat):
    """Der Pokal: base, stem, a flared cup and two handles. freuen auf/über, angeben mit,
    träumen von."""
    base = Vector(spec["at"])
    x, y, z = base
    s = spec.get("scale", 1.0)
    segs = 24 if pr._LOD == "low" else 48
    parts = [pr.add_box((0.34 * s, 0.34 * s, 0.08 * s), (x, y, z + 0.04 * s), mat, "pokal")]
    bpy.ops.mesh.primitive_cylinder_add(radius=0.05 * s, depth=0.16 * s, vertices=segs,
                                        location=(x, y, z + 0.16 * s))
    parts.append(bpy.context.active_object)
    bpy.ops.mesh.primitive_cone_add(radius1=0.09 * s, radius2=0.25 * s, depth=0.34 * s, vertices=segs,
                                    location=(x, y, z + 0.41 * s))
    parts.append(bpy.context.active_object)
    for side in (-1, 1):
        bpy.ops.mesh.primitive_torus_add(location=(x + side * 0.25 * s, y, z + 0.44 * s),
                                         rotation=(math.radians(90), 0, 0),
                                         major_radius=0.1 * s, minor_radius=0.026 * s,
                                         major_segments=24, minor_segments=8)
        parts.append(bpy.context.active_object)
    for obj in parts[1:]:
        obj.data.materials.append(mat)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    return [pr._merge(parts, "reference.pokal", base, spec.get("yaw", pr.FACE_CAMERA))]


def _kiste(spec, mat):
    """Die Umzugskiste: a closed carton, taped across the top. helfen bei."""
    base = Vector(spec["at"])
    x, y, z = base
    w, d, h = spec.get("size", (0.62, 0.5, 0.45))
    return [pr._merge([pr.add_box((w, d, h), (x, y, z + h / 2), mat, "kiste"),
                       pr.add_box((w + 0.02, 0.12, 0.02), (x, y, z + h + 0.01), mat, "kiste"),
                       pr.add_box((0.02, d + 0.02, h * 0.5), (x - w / 2 - 0.005, y, z + h * 0.75), mat, "kiste"),
                       pr.add_box((0.02, d + 0.02, h * 0.5), (x + w / 2 + 0.005, y, z + h * 0.75), mat, "kiste")],
                      "reference.kiste", base, spec.get("yaw", 0.0))]


def _aepfel(spec, mat):
    """Äpfel: a handful of apples with stems, placed at `points` (offsets from `at`). Hung on the
    tree's crown in ernähren von."""
    c = Vector(spec["at"])
    r = spec.get("r", 0.12)
    parts = []
    for point in spec["points"]:
        p = c + Vector(point)
        parts += [pr._ball(p, r, mat, "apfel", coarse=True),
                  pr._rod(p + Vector((0, 0, r * 0.8)), p + Vector((0.02, 0, r * 1.45)), r * 0.15, mat, "apfel")]
    return [pr._merge(parts, "reference.aepfel", c)]


def _leiter(spec, mat):
    """Die Leiter, leaning back against a wall, one rung gone and one hanging crooked: a ladder
    worth doubting. zweifeln an."""
    base = Vector(spec["at"])
    x, y, z = base
    h, lean, half = spec.get("height", 2.3), math.radians(spec.get("lean", 14)), 0.27
    up = Vector((0, math.sin(lean), math.cos(lean)))
    parts = []
    for side in (-1, 1):
        foot = Vector((x + side * half, y, z))
        parts.append(pr._rod(foot, foot + up * h, 0.045, mat, "leiter"))
    for i in range(1, 7):
        if i == 3:
            continue                                   # the missing rung
        a = Vector((x - half, y, z)) + up * (h * i / 7.2)
        b = Vector((x + half, y, z)) + up * (h * i / 7.2)
        if i == 5:
            b += Vector((0, 0, -0.16))                 # the crooked one
        parts.append(pr._rod(a, b, 0.035, mat, "leiter"))
    return [pr._merge(parts, "reference.leiter", base, spec.get("yaw", 0.0))]


def _kaefer(spec, mat):
    """Der Käfer: a domed shell, a head, six legs and two feelers. Front is -Y. interessieren für."""
    base = Vector(spec["at"])
    x, y, z = base
    s = spec.get("scale", 1.0)
    parts = [pr._ball((x, y + 0.03 * s, z + 0.12 * s), 0.2 * s, mat, "kaefer", squash=(0.9, 1.3, 0.62)),
             pr._ball((x, y - 0.25 * s, z + 0.1 * s), 0.085 * s, mat, "kaefer", coarse=True)]
    for side in (-1, 1):
        for dy in (-0.12, 0.02, 0.16):
            hip = Vector((x + side * 0.12 * s, y + dy * s, z + 0.09 * s))
            parts.append(pr._rod(hip, Vector((x + side * 0.3 * s, y + dy * 1.4 * s, z)), 0.018 * s, mat, "kaefer"))
        head = Vector((x + side * 0.04 * s, y - 0.3 * s, z + 0.13 * s))
        parts.append(pr._rod(head, head + Vector((side * 0.08, -0.14, 0.12)) * s, 0.012 * s, mat, "kaefer"))
    return [pr._merge(parts, "reference.kaefer", base, spec.get("yaw", 0.0))]


def _rahmen(spec, mat):
    """Ein Bilderrahmen hanging on a wall, facing the camera, with a backing board: the memory in
    erinnern an. `at` is its centre."""
    c = Vector(spec["at"])
    x, y, z = c
    w, h = spec.get("size", (1.0, 0.8))[:2]
    bar = 0.08
    parts = [pr.add_box((w, 0.06, bar), (x, y, z - h / 2 + bar / 2), mat, "rahmen"),
             pr.add_box((w, 0.06, bar), (x, y, z + h / 2 - bar / 2), mat, "rahmen"),
             pr.add_box((bar, 0.06, h), (x - w / 2 + bar / 2, y, z), mat, "rahmen"),
             pr.add_box((bar, 0.06, h), (x + w / 2 - bar / 2, y, z), mat, "rahmen"),
             pr.add_box((w - 0.04, 0.02, h - 0.04), (x, y + 0.03, z), mat, "rahmen")]
    return [pr._merge(parts, "reference.rahmen", c, spec.get("yaw", 0.0))]


def _rudel(spec, mat):
    """Das Rudel: several hund samples joined into one, so the pack can be the tinted object
    (gehören zum Rudel). `dogs` is [(dx, dy, yaw, height)] from `at`."""
    x, y, z = spec["at"]
    parts = []
    for dx, dy, yaw, height in spec["dogs"]:
        parts += pr.build_reference("mesh", {"file": "hund", "at": (x + dx, y + dy, z),
                                             "height": height, "yaw": yaw}, mat)
    return [pr._merge(parts, "reference.rudel", (x, y, z))]


def _hund_krank(spec, mat):
    """Der kranke Hund: the hund sample in a vet's cone, which says "sick" at a glance. The cone
    is found from the mesh itself (the head is the top of the sitting dog), so it follows the
    sample at any height and yaw. sich sorgen um."""
    yaw, height = spec.get("yaw", HUND_LINKS), spec.get("height", 0.95)
    dog = pr.build_reference("mesh", {"file": "hund", "at": spec["at"], "height": height, "yaw": yaw}, mat)[0]
    verts = [dog.matrix_world @ v.co for v in dog.data.vertices]
    top = max(v.z for v in verts)
    head = [v for v in verts if v.z > top - 0.22 * height]
    centre = sum(head, Vector()) / len(head)
    facing = math.radians(yaw - 140)          # the sample faces +X at yaw 140
    ahead = Vector((math.cos(facing), math.sin(facing), -0.25)).normalized()
    bpy.ops.mesh.primitive_cone_add(radius1=0.09 * height, radius2=0.26 * height, depth=0.24 * height,
                                    vertices=24 if pr._LOD == "low" else 48,
                                    location=centre - ahead * 0.04 * height,
                                    rotation=ahead.to_track_quat("Z", "Y").to_euler())
    cone = bpy.context.active_object
    # Chalk, in a second material slot. Tinted with the dog it vanished into the head; and the
    # runtime re-tints only a subject's first material, so this one stays chalk on both sides.
    cone.data.materials.append(pr._inked(mat, "kreide"))
    return [pr._merge([dog, cone], "reference.hund_krank", Vector(spec["at"]))]


# Held props: authored around figur.grip, +Z running on from the arm, +Y the figure's forward.

def _hammer(mat):
    handle = pr._rod((0, 0, -0.04), (0, 0, 0.42), 0.032, mat, "hammer")
    head = pr.add_box((0.09, 0.3, 0.11), (0, 0.03, 0.42), mat, "hammer")
    return pr._merge([handle, head], "hammer", (0, 0, 0))


def _lupe(mat):
    handle = pr._rod((0, 0, -0.02), (0, 0, 0.2), 0.026, mat, "lupe")
    bpy.ops.mesh.primitive_torus_add(location=(0, 0, 0.35), rotation=(math.radians(90), 0, 0),
                                     major_radius=0.15, minor_radius=0.026,
                                     major_segments=32, minor_segments=8)
    ring = bpy.context.active_object
    ring.data.materials.append(mat)
    return pr._merge([handle, ring], "lupe", (0, 0, 0))


VERB_PROPS = {"ball": _ball_ref, "bus": _bus, "hund_krank": _hund_krank, "pokal": _pokal, "kiste": _kiste, "aepfel": _aepfel,
              "leiter": _leiter, "kaefer": _kaefer, "rahmen": _rahmen, "rudel": _rudel}
pr.VERB_PROPS.update(VERB_PROPS)
pr.SUBJECT_BUILDERS.update({kind: pr._prop_subject(kind) for kind in VERB_PROPS})
pr.HELD_PROPS.update({"hammer": _hammer, "lupe": _lupe})


# MARK: - The cast


def mann(**spec):
    return ("figur", {"height": FH, **spec})


def freund(**spec):
    """Der Freund: a second Figur, told apart by its chalk torso (Kyle's pick, 2026-10-02)."""
    return ("figur", {"name": "freund", "accent": "kreide", "height": FH, **spec})


def hand(at, yaw, pose, role="arm_r", mirror=False):
    return figur.hand_position(at, yaw, pose, role, mirror, height=FH)


def between_hands(at, yaw, pose, mirror=False):
    a, b = hand(at, yaw, pose, "arm_r", mirror), hand(at, yaw, pose, "arm_l", mirror)
    return (a + b) / 2


def crown(tree_at, scale, offsets):
    """Points on a tree crown's camera-facing side (prep_render's `tree`: trunk 0.9·s, crown
    radius 0.72·s), as offsets from the crown centre."""
    centre = Vector(tree_at) + Vector((0, 0, 0.9 * scale + 0.5 * scale))
    toward = Vector((math.sin(math.radians(pr.FACE_CAMERA)), -math.cos(math.radians(pr.FACE_CAMERA)), 0))
    radius = 0.72 * scale + 0.04
    return centre, [tuple((toward * 0.85 + Vector(o)).normalized() * radius) for o in offsets]


def circle(center, radius, laps, steps=24):
    """Keys for a run around a circle, as (t, offset from the start point) and (t, spin)."""
    keys, spin = [], []
    for i in range(steps * laps + 1):
        t = i / (steps * laps)
        a = 2 * math.pi * laps * t
        keys.append((t, (radius * math.cos(a) - radius, radius * math.sin(a), 0), "linear"))
        spin.append((t, math.degrees(a)))
    return keys, spin


# MARK: - The scenes
#
# One entry per asset; verb_prepositions.json says which verbs each one serves. Keys are prep_render's
# relation keys (`ref`, `subject_build`/`subject_mesh`, `subject_spec`), plus:
#   at      where the subject stands (its base, or its centre for a cloud)
#   motion  [(target, keys[, {"spin": keys, "scale": keys}])]: baked, see the module docstring.
#           A key is (t, (dx, dy, dz)[, ease]) with t from 0 to 1 over the loop.
#   period  the loop length in frames; defaults to the first figure's clip, and every other
#           clip in the scene is stretched to it.

_DENK = {"style": "denk", "at": (0.75, 0.15, 1.45), "size": (1.75, 1.15), "tail_to": (-1.3, 0.2, 0.95)}
_SPRECH = {"style": "sprech", "at": (-0.05, 0.25, 1.45), "size": (1.5, 0.95), "tail_to": (-1.55, 0, 0.9)}
_TRAUM = {"style": "denk", "at": (-0.35, 0.3, 0.95), "size": (1.5, 1.0), "tail_to": (-1.6, 0.3, -0.4)}

# Top surface at 0.05: low enough that a level swing (hand ~0.2, hammer head reaching 0.12 below
# it, 0.42 past the hand) lands on it rather than in it.
_TISCH_AN = (0.45, 0.0, -0.06)
_HEBEN_MITTE = between_hands((-0.8, 0, G), P, "heben")
_BALL_HALT = between_hands((1.2, 0, G), L, "vorfreude", mirror=True)
_KRONE, _AEPFEL = crown((0.45, 0.25, G), 0.95, [(-0.55, 0, 0.35), (0.45, 0, 0.45), (0.15, 0, -0.35),
                                              (-0.35, 0, -0.05), (0.5, 0, -0.05)])
_RUNDE, _DREHUNG = circle((0.55, 0.15), 0.55, laps=2)
_BUCH = {"style": "offen", "at": (0.55, 0.15, G), "size": (0.9, 1.2), "lean": 40, "pages": 0.12}

SCENES = {
    # Angst haben vor · sich fürchten vor: the spider edges closer and the flinch deepens.
    "angst": {
        "ref": [mann(at=(-1.55, 0.2, G), clip="schreck", yaw=P)],
        "subject_build": "spinne", "subject_spec": {"scale": 1.15, "yaw": -90},
        "at": (1.0, 0, G),
        "motion": [("subject", [(0, (0, 0, 0)), (0.46, (-0.3, 0, 0), "out"), (0.72, (-0.3, 0, 0)),
                                (1, (0, 0, 0))])],
    },
    "ekel": {
        "ref": [mann(at=(-1.45, 0.2, G), clip="ekel", yaw=P)],
        "subject_build": "spinne", "subject_spec": {"scale": 1.0, "yaw": -90},
        "at": (0.95, 0, G),
    },
    # leiden unter: under it, and it stays over him.
    "leiden": {
        "ref": [mann(at=(-0.1, 0.1, G), clip="kummer", yaw=P)],
        "subject_build": "wolke", "subject_spec": {"rain": True, "scale": 0.8},
        "at": (0.05, 0.1, 2.05),
        "motion": [("subject", [(0, (0, 0, 0)), (0.5, (0.2, 0, 0)), (1, (0, 0, 0))])],
    },
    "arbeiten": {
        "ref": [mann(at=(-1.2, 0.2, G), clip="hammer", yaw=P, hold={"prop": "hammer"})],
        "subject_build": "ref", "subject_spec": {"kind": "table", "size": (1.4, 0.9, 0.58)},
        "at": _TISCH_AN,
    },
    # helfen bei: the carton rides the lift.
    "helfen": {
        "ref": [mann(at=(-0.8, 0, G), clip="heben", yaw=P),
                freund(at=(0.8, 0, G), clip="heben", yaw=L, mirror=True)],
        "subject_build": "kiste", "subject_spec": {"size": (0.62, 0.5, 0.45)},
        "at": (0, 0, _HEBEN_MITTE.z - 0.22),
        "motion": [("subject", [(0, (0, 0, 0)), (0.5, (0, 0, 0.07)), (1, (0, 0, 0))])],
    },
    "ernaehren": {
        "ref": [("tree", {"at": (0.45, 0.25, G), "scale": 0.95}),
                mann(at=(-0.6, 0.05, G), clip="essen", yaw=P)],
        "subject_build": "aepfel", "subject_spec": {"points": _AEPFEL, "r": 0.14},
        "at": tuple(_KRONE),
    },
    # gehören zu · zählen zu: the pack is the object; the little one hops among them.
    "rudel": {
        "ref": [mann(at=(-1.95, 0.6, G), pose="zeig", yaw=24),
                ("mesh", {"file": "hund", "name": "hund_klein", "at": (0.6, -0.45, G), "height": 0.6,
                          "yaw": HUND_KAMERA})],
        "subject_build": "rudel",
        "subject_spec": {"dogs": [(-0.6, 0.1, 100, 0.95), (0.05, 0.5, 70, 0.95), (0.65, 0.05, 40, 0.95)]},
        "at": (0.6, 0.2, G),
        "period": 48,
        "motion": [("hund_klein", [(0, (0, 0, 0)), (0.12, (0, 0, 0.2), "out"), (0.24, (0, 0, 0), "in"),
                                   (0.36, (0, 0, 0.2), "out"), (0.48, (0, 0, 0), "in"), (1, (0, 0, 0))])],
    },
    # abhängen von: the game waits on the weather, and the weather won't settle.
    "abhaengen": {
        "ref": [mann(at=(-1.35, 0.1, G), clip="staunen", yaw=F),
                ("ball", {"at": (-0.6, -0.4, G), "r": 0.22})],
        "subject_build": "wolke", "subject_spec": {"scale": 0.7},
        "at": (0.95, 0.3, 1.55),
        "motion": [("subject", [(0, (0, 0, 0)), (0.5, (-0.3, 0, 0.1)), (1, (0, 0, 0))])],
    },
    # schreiben an: the friend is the object; the letter flies to him and vanishes on arrival,
    # and the next one leaves the desk. t=0 is mid-flight, so a still shows a letter on its way.
    "schreiben": {
        "ref": [("table", {"size": (1.0, 0.7, 0.69), "at": (-0.85, 0, 0.05)}),
                ("slab", {"size": (0.5, 0.5, 0.54), "at": (-1.75, 0, -0.48)}),
                mann(at=(-1.75, 0, -0.28), clip="schreiben", yaw=P),
                ("brief", {"at": (-0.55, -0.1, 0.17), "size": (0.5, 0.34, 0.04)})],
        "subject_build": "freund", "subject_spec": {"pose": "vorfreude", "yaw": L, "mirror": True},
        "at": (1.6, 0, G),
        "motion": [("reference.brief",
                    [(0, (1.0, 0.05, 0.75)), (0.22, (1.95, 0.1, 0.45), "in"), (0.3, (1.95, 0.1, 0.45)),
                     (0.45, (0, 0, 0)), (0.7, (0, 0, 0)), (1, (1.0, 0.05, 0.75))],
                    {"scale": [(0, 1), (0.22, 1), (0.3, 0, "in"), (0.45, 0), (0.55, 1, "out"), (1, 1)]})],
    },
    "antworten": {
        "ref": [("table", {"size": (1.0, 0.7, 0.69), "at": (-0.6, 0, 0.05)}),
                ("slab", {"size": (0.5, 0.5, 0.54), "at": (-1.5, 0, -0.48)}),
                mann(at=(-1.5, 0, -0.28), clip="schreiben", yaw=P)],
        "subject_build": "brief", "subject_spec": {"size": (0.6, 0.42, 0.04)},
        "at": (-0.35, 0.12, 0.17),
    },
    "kuemmern": {
        "ref": [mann(at=(-0.5, 0.1, G), clip="pflegen", yaw=P)],
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": HUND_LINKS},
        "at": (0.45, 0.05, G),
    },
    # sich sorgen um: the dog lies on its side on a cushion, and the man can't stop looking.
    "sorgen": {
        "ref": [("mesh", {"file": "kissen", "at": (0.6, 0.1, G), "height": 0.4}),
                mann(at=(-0.75, 0.15, G), clip="kummer", yaw=P)],
        "subject_build": "hund_krank", "subject_spec": {"height": 0.95, "yaw": HUND_LINKS},
        "at": (0.6, 0.05, G + 0.22),
    },
    # aufpassen auf: the dog runs circles and the man keeps him in view.
    "aufpassen": {
        "ref": [mann(at=(-1.75, 0.45, G), clip="wache", yaw=P)],
        "subject_mesh": {"file": "hund", "height": 0.85, "yaw": -130},
        "at": (1.1, 0.15, G),
        "motion": [("subject", _RUNDE, {"spin": _DREHUNG})],
    },
    # warten auf: the bus is the object, and it does not come. Akkusativ, and nothing moves.
    "warten": {
        "ref": [("schild", {"variant": "haltestelle", "at": (-1.9, 0.35, G)}),
                ("path", {"at": (0.55, -0.1, G), "length": 4.0, "count": 8}),
                mann(at=(-1.05, 0, G), clip="warten", yaw=P)],
        "subject_build": "bus", "subject_spec": {"scale": 0.55},
        "at": (2.3, 0.3, G),
    },
    # sich freuen auf: still to come, so the trophy is over there, up on its podium.
    "freuen_auf": {
        "ref": [("slab", {"size": (0.7, 0.7, 0.6), "at": (1.5, 0.3, G + 0.3)}),
                mann(at=(-1.2, 0, G), clip="vorfreude", yaw=P)],
        "subject_build": "pokal", "subject_spec": {"scale": 1.1},
        "at": (1.5, 0.3, G + 0.6),
    },
    # sich freuen über: already here, right beside him.
    "freuen_ueber": {
        "ref": [("slab", {"size": (0.55, 0.55, 0.3), "at": (0.45, -0.05, G + 0.15)}),
                mann(at=(-0.55, 0.05, G), clip="jubel", yaw=F)],
        "subject_build": "pokal", "subject_spec": {"scale": 1.1},
        "at": (0.45, -0.05, G + 0.3),
    },
    "hoffen": {
        "ref": [mann(at=(-0.9, 0.1, G), clip="hoffen", yaw=-40)],
        "subject_build": "wolke", "subject_spec": {"scale": 0.75},
        "at": (0.9, 0.3, 1.7),
        "motion": [("subject", [(0, (0, 0, 0)), (0.5, (-0.25, 0, 0)), (1, (0, 0, 0))])],
    },
    "vorbereiten": {
        "ref": [mann(at=(-1.6, 0.3, G), clip="dehnen", yaw=F)],
        "subject_build": "ref", "subject_spec": {"kind": "goal", "length": 2.6, "count": 5},
        "at": (0.55, 0, G + 0.05),
    },
    # sprechen über · reden über: both talking, the topic in the bubble (Akkusativ)...
    "sprechen_ueber": {
        "ref": [mann(at=(-1.8, 0, G), clip="reden", yaw=P),
                freund(at=(1.8, 0, G), clip="reden", yaw=L, mirror=True),
                ("blase", _SPRECH)],
        "subject_mesh": {"file": "hund", "height": 0.55, "yaw": 20},
        "at": pr.bubble_slot(_SPRECH, 0.55),
    },
    # ...and erzählen von: the same picture on purpose, in the Dativ, with the friend listening.
    "erzaehlen": {
        "ref": [mann(at=(-1.8, 0, G), clip="reden", yaw=P),
                freund(at=(1.8, 0, G), pose="wache", yaw=L, mirror=True),
                ("blase", _SPRECH)],
        "subject_mesh": {"file": "hund", "height": 0.55, "yaw": 20},
        "at": pr.bubble_slot(_SPRECH, 0.55),
    },
    "nachdenken": {
        "ref": [mann(at=(-1.0, 0.25, G), clip="gruebeln", yaw=P)],
        "subject_build": "schild", "subject_spec": {"variant": "wegweiser"},
        "at": (0.9, 0.25, G),
    },
    # sich ärgern über: the dog knocked the bowl over.
    "aergern": {
        "ref": [mann(at=(-1.35, 0.25, G), clip="stampfen", yaw=P),
                ("mesh", {"file": "napf", "at": (1.45, -0.3, G), "height": 0.2, "roll": 75})],
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": HUND_LINKS},
        "at": (0.65, 0, G),
    },
    "beschweren": {
        "ref": [mann(at=(-1.7, 0, G), clip="schimpfen", yaw=P),
                freund(at=(1.7, 0, G), pose="wache", yaw=L, mirror=True),
                ("blase", _SPRECH)],
        "subject_mesh": {"file": "hund", "height": 0.55, "yaw": 20},
        "at": pr.bubble_slot(_SPRECH, 0.55),
    },
    "streiten": {
        "ref": [mann(at=(-1.4, 0.1, G), clip="schimpfen", yaw=P),
                freund(at=(1.4, 0.1, G), clip="schimpfen", yaw=L, mirror=True)],
        "subject_mesh": {"file": "hund", "height": 0.85, "yaw": HUND_KAMERA},
        "at": (0, -0.35, G),
    },
    # sich wundern über: a dog sitting on the table.
    "wundern": {
        "ref": [("table", {"size": (1.4, 0.9, 0.62), "at": (0.8, 0.1, -0.02)}),
                mann(at=(-1.25, 0.2, G), clip="staunen", yaw=F)],
        "subject_mesh": {"file": "hund", "height": 0.85, "yaw": HUND_LINKS},
        "at": (0.8, 0.1, 0.09),
    },
    "denken": {
        "ref": [mann(at=(-1.6, 0.2, G), clip="gruebeln", yaw=P), ("blase", _DENK)],
        "subject_mesh": {"file": "hund", "height": 0.6, "yaw": 20},
        "at": pr.bubble_slot(_DENK, 0.6),
    },
    # sich erinnern an: the dog in a picture on the wall.
    "erinnern": {
        "ref": [("slab", {"size": (2.6, 0.2, 2.3), "at": (0.85, 1.0, 0.4)}),
                ("rahmen", {"at": (0.85, 0.86, 0.75), "size": (1.05, 0.85, 0.08)}),
                mann(at=(-1.35, 0.0, G), clip="gruebeln", yaw=-50)],
        "subject_mesh": {"file": "hund", "height": 0.55, "yaw": 20},
        "at": (0.85, 0.74, 0.47),
    },
    "gewoehnen": {
        "ref": [mann(at=(-1.3, 0.2, G), clip="gewoehnen", yaw=P)],
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": HUND_LINKS},
        "at": (0.7, 0, G),
    },
    "zweifeln": {
        "ref": [("slab", {"size": (2.2, 0.2, 2.6), "at": (1.05, 0.95, 0.55)}),
                mann(at=(-1.25, 0.1, G), clip="zweifeln", yaw=P)],
        "subject_build": "leiter", "subject_spec": {"height": 2.3, "lean": 14},
        "at": (1.0, 0.25, G),
    },
    "bitten": {
        "ref": [mann(at=(-1.3, 0, G), clip="bitten", yaw=P),
                freund(at=(1.2, 0, G), pose="vorfreude", yaw=L, mirror=True)],
        "subject_build": "ball", "subject_spec": {"r": 0.2},
        "at": (_BALL_HALT.x - 0.08, _BALL_HALT.y, _BALL_HALT.z - 0.2),
    },
    "sprechen_mit": {
        "ref": [mann(at=(-1.2, 0, G), clip="reden", yaw=P)],
        "subject_build": "freund", "subject_spec": {"pose": "reden_b", "yaw": L, "mirror": True},
        "at": (1.2, 0, G),
    },
    "schimpfen": {
        "ref": [mann(at=(-1.2, 0.2, G), clip="schimpfen", yaw=P)],
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": HUND_LINKS},
        "at": (0.75, 0, G),
    },
    "angeben": {
        "ref": [("slab", {"size": (0.7, 0.7, 0.5), "at": (0.1, 0, G + 0.25)}),
                mann(at=(-0.9, 0.1, G), clip="angeben", yaw=P),
                freund(at=(1.65, 0.35, G), pose="staunen", yaw=L, mirror=True)],
        "subject_build": "pokal", "subject_spec": {"scale": 1.2},
        "at": (0.1, 0, G + 0.5),
    },
    # träumen von: asleep on a cushion, the trophy in the dream.
    "traeumen": {
        "ref": [("mesh", {"file": "kissen", "at": (-1.75, 0.3, G), "height": 0.3}),
                mann(at=(-0.95, 0.3, G), clip="schlafen", yaw=0), ("blase", _TRAUM)],
        "subject_build": "pokal", "subject_spec": {"scale": 0.9},
        "at": pr.bubble_slot(_TRAUM, 0.6),
    },
    # handeln von: a dog standing up out of the open book.
    "handeln": {
        "ref": [("buch", _BUCH), mann(at=(-1.6, 0.4, G), pose="zeig", yaw=24)],
        "subject_mesh": {"file": "hund", "height": 0.72, "yaw": HUND_KAMERA},
        "at": (0.55, 0.15 - 0.6 + 0.2 * 1.2 * math.cos(math.radians(40)),
               G + 0.2 * 1.2 * math.sin(math.radians(40)) + 0.12),
    },
    # fragen nach: the friend shows the way; the signpost is the way.
    "fragen": {
        "ref": [mann(at=(-1.9, 0, G), clip="bitten", yaw=P),
                freund(at=(-0.25, 0, G), pose="weisen", yaw=F)],
        "subject_build": "schild", "subject_spec": {"variant": "wegweiser"},
        "at": (1.55, 0.3, G),
    },
    # sich sehnen nach: the friend on the far bank.
    "sehnen": {
        # The river runs past both frame edges, so it reads as water and not as a plank.
        "ref": [("slab", {"size": (7.6, 1.0, 0.12), "at": (0, 0.45, -0.72)}),
                mann(at=(-1.3, -0.8, -0.9), clip="sehnen", yaw=P)],
        "subject_build": "freund", "subject_spec": {"pose": "sehnen", "yaw": L, "mirror": True},
        "at": (1.3, 1.5, -0.85),
    },
    # verlangen nach: the dog wants the ball on the shelf.
    "verlangen": {
        "ref": [("shelf", {"at": (0.9, 0.2, G), "height": 1.5}),
                ("mesh", {"file": "hund", "at": (2.0, -0.2, G), "height": 0.95, "yaw": HUND_LINKS}),
                mann(at=(-1.95, 0.6, G), pose="zeig", yaw=24)],
        "subject_build": "ball", "subject_spec": {"r": 0.22},
        "at": (1.55, 0.2, G + 1.57),
    },
    "interesse": {
        "ref": [mann(at=(-0.75, 0.15, G), clip="neugier", yaw=P, hold={"prop": "lupe"})],
        "subject_build": "kaefer", "subject_spec": {"scale": 1.2, "yaw": 90},
        "at": (0.35, 0.1, G),
    },
}


# MARK: - Data


def load_data():
    with open(DATA, encoding="utf-8") as handle:
        verbs = json.load(handle)["verbs"]
    by_scene = {}
    for verb in verbs:
        by_scene.setdefault(verb["scene"], []).append(verb)
    missing = set(by_scene) - set(SCENES)
    unused = set(SCENES) - set(by_scene)
    if missing or unused:
        raise SystemExit(f"verb_prepositions.json and SCENES disagree: no scene for {sorted(missing)}, "
                         f"no verb for {sorted(unused)}")
    return by_scene


BY_SCENE = load_data()


def label_for(scene_id):
    verbs = BY_SCENE[scene_id]
    case = "Akk" if verbs[0]["case"] == "akkusativ" else "Dat"
    return (" · ".join(v["verb"] for v in verbs) + f"  ({case})\n"
            + verbs[0]["examples"][0]["german"])


# MARK: - Building


def _refs(spec):
    refs = spec["ref"]
    return refs if isinstance(refs, list) else [refs]


def scene_period(spec):
    if "period" in spec:
        return spec["period"]
    clips = [s["clip"] for kind, s in _refs(spec) if kind == "figur" and s.get("clip")]
    return figur.clip_length(clips[0]) if clips else 48


def relation(scene_id):
    """A SCENES entry as a prep_render relation: case from the data, every clip on one period."""
    spec = SCENES[scene_id]
    period = scene_period(spec)
    rel = {k: v for k, v in spec.items() if k not in ("at", "motion", "period")}
    rel["governs"] = BY_SCENE[scene_id][0]["case"]
    rel["dat"] = {"subject": spec["at"]}
    rel["ref"] = [(kind, {**s, "period": period}) if kind == "figur" and s.get("clip") else (kind, s)
                  for kind, s in _refs(spec)]
    return rel, period


def _sample(keys, t):
    """Value at t from [(t, value[, ease])], eased per segment like figur's clips."""
    for (t0, v0, *_), (t1, v1, *ease) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            u = figur.EASES[ease[0] if ease else "smooth"]((t - t0) / (t1 - t0) if t1 > t0 else 1)
            if isinstance(v0, tuple):
                return tuple(a + (b - a) * u for a, b in zip(v0, v1))
            return v0 + (v1 - v0) * u
    return keys[-1][1]


def _base_origin(obj):
    """Origin to the bottom centre of the bounds, so a spin turns a thing about itself."""
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    base = Vector((sum(c.x for c in corners) / 8, sum(c.y for c in corners) / 8, min(c.z for c in corners)))
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.context.scene.cursor.location = base
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)


def bake_motion(scene_id, motions, period):
    """Key every scene motion under a still holder (see the module docstring). Returns the names
    of the prims that now carry TimeSamples, for the export check's whitelist."""
    moved = []
    for target, keys, *extra in motions:
        opts = extra[0] if extra else {}
        obj = bpy.data.objects[target]
        if target == "subject":
            obj.name = obj.data.name = f"{scene_id}_bewegt"
            holder_name = "subject"
        else:
            # USD turns dots into underscores, so name it the way the export (and the twin
            # check) will see it.
            obj.name = obj.data.name = target.replace(".", "_")
            holder_name = obj.name + "_halter"
        _base_origin(obj)
        holder = bpy.data.objects.new(holder_name, None)
        bpy.context.collection.objects.link(holder)
        holder.location = obj.matrix_world.translation.copy()
        obj.parent = holder
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.location = (0, 0, 0)
        obj.rotation_mode = "XYZ"
        for frame in range(period + 1):
            t = frame / period
            obj.location = _sample(keys, t)
            obj.keyframe_insert("location", frame=frame + 1)
            if spin := opts.get("spin"):
                obj.rotation_euler.z = math.radians(_sample(spin, t))
                obj.keyframe_insert("rotation_euler", frame=frame + 1)
            if scale := opts.get("scale"):
                obj.scale = (max(_sample(scale, t), 0.001),) * 3
                obj.keyframe_insert("scale", frame=frame + 1)
        for curve in figur.fcurves_of(obj.animation_data.action):
            for point in curve.keyframe_points:
                point.interpolation = "LINEAR"
        moved.append(obj.name)
    return moved


def build_scene(scene_id, state="dat", size=512, samples=None):
    rel, period = relation(scene_id)
    pr.build_relation(rel, state, "dim", size)
    moved = bake_motion(scene_id, SCENES[scene_id].get("motion", []), period)
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = max(period + 1, scene.get("clip_end", 1))
    scene.frame_set(1)
    if samples:
        scene.eevee.taa_render_samples = samples
    return rel, moved


# MARK: - Modes


def sheet(ids, size, samples):
    out_dir = os.path.join(OUT, "sheet")
    os.makedirs(out_dir, exist_ok=True)
    cells = []
    for scene_id in ids:
        build_scene(scene_id, "dat", size, samples)
        figur.add_label(label_for(scene_id), size=0.03)
        path = os.path.join(out_dir, f"{scene_id}.png")
        pr.render_to(path)
        cells.append(path)
        print(f"SHEET {scene_id}")
    figur.contact_sheet(cells, 6, os.path.join(OUT, "verben-szenen.png"))


def slim(ratio=0.25, above=5000):
    """Decimate the heavy meshes before an export. The hund sample is ~18k faces and rides in
    16 scenes, which made the set 24 MB; at a quarter of that it reads the same at drill size.
    Stills keep full detail, because they are rendered from a separate build."""
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH" or len(obj.data.polygons) <= above:
            continue
        mod = obj.modifiers.new("slim", "DECIMATE")
        mod.ratio = ratio
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)


def export(ids, out_dir=OUT):
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    results = {}
    for scene_id in ids:
        pr._LOD = "low"
        rel, moved = build_scene(scene_id, "dat", 256)
        slim()
        out = os.path.join(out_dir, f"verb3d-{scene_id}.usdz")
        # The twin is judging evidence, not an asset: it always stays in the gitignored renders.
        twin = os.path.join(OUT, f"verb3d-{scene_id}.usda")
        pr.export_usdz(out, animated=True, twin=twin)
        results[scene_id] = pr.check_export(out, rel, twin, extra_allowed=moved)
    failed = [k for k, ok in results.items() if not ok]
    print(f"EXPORT {len(results) - len(failed)}/{len(results)} OK" + (f" — FAILED {failed}" if failed else ""))
    return not failed


def ship(ids, size=512, samples=128):
    """Everything the app reads, into Resources/: stills first (full detail), then the slimmed,
    checked USDZs, then the manifest. The manifest marks every entry `baked`, which is what
    tells PrepositionSceneView the scene animates although it carries no runtime motion."""
    for scene_id in ids:
        pr._LOD = "high"
        for state in ("neutral", "dat"):
            build_scene(scene_id, state, size, samples)
            pr.render_to(os.path.join(RESOURCES, f"verb3d-{scene_id}-{state}-dim.png"))
        print(f"STILLS {scene_id}")
    ok = export(ids, out_dir=RESOURCES)
    manifest = {"relations": {f"verb3d-{scene_id}": {"asset": f"verb3d-{scene_id}", "akkOffset": [0, 0, 0],
                                                     "baked": True}
                              for scene_id in SCENES}}
    with open(os.path.join(RESOURCES, "verb3d-manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
    print(f"SHIP {len(ids)} scenes → {RESOURCES}" + ("" if ok else " — EXPORT CHECK FAILED"))
    return ok


def preview(ids, size, samples, step):
    """Every `step`-th frame of every scene at low quality, one mp4 per scene, then one grid
    that loops them all for eight seconds. For judging motion, which a still can't show."""
    clips = []
    for scene_id in ids:
        frames_dir = os.path.join(OUT, "preview", scene_id)
        os.makedirs(frames_dir, exist_ok=True)
        for old in os.listdir(frames_dir):
            os.remove(os.path.join(frames_dir, old))
        build_scene(scene_id, "dat", size, samples)
        figur.add_label(label_for(scene_id).split("\n")[0], size=0.045)
        scene = bpy.context.scene
        for i, frame in enumerate(range(scene.frame_start, scene.frame_end, step)):
            scene.frame_set(frame)
            pr.render_to(os.path.join(frames_dir, f"f{i:04d}.png"))
        mp4 = os.path.join(OUT, "preview", f"{scene_id}.mp4")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(24 // step),
                        "-i", os.path.join(frames_dir, "f%04d.png"),
                        "-vf", "format=rgba,split[a][b];[b]drawbox=c=0xF3EFE6:t=fill[bg];[bg][a]overlay,format=yuv420p",
                        mp4], check=True)
        clips.append(mp4)
        print(f"PREVIEW {scene_id}")
    if len(clips) > 1:
        cols = min(6, len(clips))
        total = cols * math.ceil(len(clips) / cols)
        pad = total - len(clips)
        inputs, labels, prefix = [], [f"[{i}:v]" for i in range(len(clips))], ""
        for clip in clips:
            inputs += ["-stream_loop", "-1", "-i", clip]
        if pad:
            inputs += ["-f", "lavfi", "-i", f"color=c=0xF3EFE6:s={size}x{size}:r={24 // step}"]
            blanks = [f"[p{j}]" for j in range(pad)]
            prefix = f"[{len(clips)}:v]split={pad}" + "".join(blanks) + ";"
            labels += blanks
        layout = "|".join(f"{(i % cols) * size}_{(i // cols) * size}" for i in range(total))
        grid = os.path.join(OUT, "verben-vorschau.mp4")
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *inputs, "-filter_complex",
                        f"{prefix}{''.join(labels)}xstack=inputs={total}:layout={layout},format=yuv420p",
                        "-t", "8", grid], check=True)
        print(f"GRID {grid}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", nargs="*", metavar="ID", help="labelled stills (all scenes if no ids)")
    ap.add_argument("--scene", choices=sorted(SCENES), help="one still")
    ap.add_argument("--state", default="dat", choices=["dat", "neutral"])
    ap.add_argument("--usdz", nargs="*", metavar="ID", help="export + check (all if no ids)")
    ap.add_argument("--preview", nargs="*", metavar="ID", help="motion preview (all if no ids)")
    ap.add_argument("--ship", nargs="*", metavar="ID", help="assets + manifest into Resources/ (all if no ids)")
    ap.add_argument("--size", type=int, default=384)
    ap.add_argument("--samples", type=int, default=64)
    ap.add_argument("--step", type=int, default=2, help="preview: render every n-th frame")
    ap.add_argument("--frame", type=int, default=0, help="--scene: which loop frame to show")
    ap.add_argument("--out", default=None)
    args = ap.parse_args(argv)

    if args.sheet is not None:
        sheet(args.sheet or list(SCENES), args.size, args.samples)
    elif args.scene:
        build_scene(args.scene, args.state, args.size, args.samples)
        bpy.context.scene.frame_set(args.frame + 1)
        figur.add_label(label_for(args.scene), size=0.03)
        pr.render_to(args.out or os.path.join(OUT, f"{args.scene}-{args.state}.png"))
    elif args.usdz is not None:
        if not export(args.usdz or list(SCENES)):
            sys.exit(1)
    elif args.ship is not None:
        if not ship(args.ship or list(SCENES)):
            sys.exit(1)
    elif args.preview is not None:
        preview(args.preview or list(SCENES), min(args.size, 256), min(args.samples, 16), args.step)


if __name__ == "__main__":
    main()
