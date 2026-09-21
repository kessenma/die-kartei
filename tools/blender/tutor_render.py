"""tutor_render.py — three candidate scenes for the onboarding tutor pitch.

Run headless:
    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/blender/tutor_render.py -- --all

Three competing answers to one question: what does "download a teacher" look like when the
copy is forbidden from saying model, LLM or inference (see OnboardingWizardView's header)?

SHIPPED: `fuellen` only. The other three lost the comparison and their assets are deleted; they
are kept buildable here because a rejected option is worth being able to re-see.

  fuellen  Die Figur zeichnet sich und füllt sich — the one that ships. An outline is drawn
           stroke by stroke, fills solid from the feet up, then stretches, jumps and waves.
  aufbau   Der Lehrer baut sich auf — a second, taller figure assembles from parts beside the
           learner and raises an arm to teach. The download made physical; the six parts are
           left addressable so the app can land them on real progress instead of on a clock.
  sockel   Alles auf einem Sockel — the whole cast stands on one plinth with a raised rim.
           A positive picture of "it stays on your phone", rather than a crossed-out cloud:
           PREPOSITION_3D.md already learned that absence has no honest picture (`ohne`).
  gewicht  Das Gewicht — one large block descends and lands on the plinth, which dips and
           recovers. Says big, says once, says it stays.

Everything is built out of figur.py: same primitives, same charcoal, same camera rake, same
key/rim/fill, so a candidate that wins here already matches the shipped cast.

Two contracts inherited from the figure rig, and they are why the names below look the way
they do:

  - **Prim names carry no dots.** The learner keeps `figur_*`; the teacher is re-prefixed to
    `lehrer_*` *after* its keyframes are written, because `keyframe_aufbau`-style tables key
    off the built-in names. Building the teacher first keeps Blender from ever appending a
    `.001` that USD would mangle.
  - **Parts stay flat and named.** No parenting, so the app can address one part at a time —
    which is the whole point of the aufbau candidate, and what lets Swift tint the teacher
    accent while the learner stays charcoal.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

# figur.py sits beside this file; Blender does not reliably put a --python script's directory
# on sys.path. Same insert prep_render.py does, for the same reason.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import figur  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
RESOURCES = os.path.join(ROOT, "german-ai-flashcards", "Resources")

# The cast, and why these two numbers differ.
#
# A teacher that is the learner's figure in another colour reads as "a copy of me", not as
# someone who knows more — die Figur is already the learner's mascot (the placement quiz intro).
# So the teacher is a different *kind* of figure: schlank proportions, visibly taller. Tint is
# the app's job at runtime and cannot be the only difference.
LERNER = ("standard", 1.80)
LEHRER = ("schlank", 2.20)

# The teacher gestures with its LEFT arm, which is not a quirk: the right-arm `zeig` in
# figur.POSES throws the gesture toward +X, and the learner stands at -X. Mirrored, the arm
# points at the person it is talking to and sits in clean profile to the camera.
ZEIG_LINKS = (0, 105, 0)


# MARK: - Small forms


def box(size, at, mat, name, rot=(0, 0, 0)):
    """A named box. figur.add_box names only the object; USD writes the mesh datablock too, and
    the app matches prim names by substring at whichever level it reaches first."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    obj = bpy.context.active_object
    obj.scale = Vector(size)
    obj.rotation_euler = [math.radians(a) for a in rot]
    obj.data.materials.append(mat)
    figur.name_part(obj, name)
    return obj


def build_pult(mat, at=(2.55, -0.35), prefix="pult"):
    """A lectern: column plus a tilted top. First pass was 0.98 tall with a 0.74 top and read
    as a stool — a prop only says "lectern" when the top is wide enough to be a surface and
    high enough to stand at."""
    x, y = at
    box((0.30, 0.30, 1.12), (x, y, 0.56), mat, f"{prefix}_saeule")
    box((0.92, 0.56, 0.10), (x, y, 1.17), mat, f"{prefix}_platte", rot=(-22, 0, 0))


def build_tafel(mat, at=(2.45, 0.70), prefix="tafel"):
    """A board on a foot. The competing answer to the lectern, and the one that should survive
    small: it is a single large rectangle, where a lectern is a thin column the eye loses."""
    x, y = at
    box((1.75, 0.12, 1.30), (x, y, 0.78), mat, f"{prefix}_platte", rot=(7, 0, 0))
    box((1.20, 0.34, 0.13), (x, y - 0.06, 0.065), mat, f"{prefix}_fuss")


PROPS = {"pult": build_pult, "tafel": build_tafel, "keins": None}


def build_sockel(mat, size=(5.60, 2.90, 0.26), rim=True, prefix="sockel"):
    """The plinth: a 2:1 slab with a raised lip. The proportion is what says "device"; the lip
    is what turns a stage into a tray, and a tray is the picture of "nothing leaves"."""
    w, d, h = size
    box((w, d, h), (0, 0, -h / 2), mat, f"{prefix}_platte")
    if not rim:
        return
    t = 0.08
    for i, (sx, sy, px, py) in enumerate([
        (w, t, 0, d / 2 - t / 2),
        (w, t, 0, -(d / 2 - t / 2)),
        (t, d, w / 2 - t / 2, 0),
        (t, d, -(w / 2 - t / 2), 0),
    ]):
        box((sx, sy, t * 1.6), (px, py, t * 0.8), mat, f"{prefix}_rand{i}")


def figure(kind, at, yaw=0.0, pose="steh", mat=None, prefix=None, override=None):
    """Build one cast member, posed and placed. `prefix` renames the six parts afterwards, so
    two figures can share a scene without either one's prim names colliding."""
    preset, height = kind
    objects, p = figur.build_figure(preset, height, mat=mat, override=override)
    figur.apply_pose(objects, p, pose)
    figur.place(objects, (at[0], at[1], 0.0), yaw=yaw)
    if prefix:
        reprefix(objects, prefix)
    return objects, p


def reprefix(objects, prefix):
    """`figur_leg_l` → `lehrer_leg_l`. The split on "." is defensive: if a name ever does
    collide, Blender appends `.001`, and a dot in a prim name is the one thing USD mangles."""
    for obj in objects:
        stem = obj.name.split(".")[0]
        figur.name_part(obj, prefix + stem[len("figur"):])


def gesture(objects, spec=ZEIG_LINKS, part="arm_l"):
    for obj in objects:
        if obj.name.endswith(part):
            obj.rotation_mode = "XYZ"
            obj.rotation_euler = [math.radians(a) for a in spec]


# MARK: - Candidate A: der Lehrer baut sich auf
#
# The same overlapping build order as figur.AUFBAU — legs, torso onto them, arms, head — with
# one beat added on the end: the left arm swings up into the teaching gesture. That beat is the
# whole argument of the scene. Parts arriving is a download; a figure that then starts teaching
# is a *teacher* arriving, which is the only thing the onboarding copy is allowed to say.

LEHRER_BEATS = {
    "figur_leg_l": (1, 18),
    "figur_leg_r": (5, 22),
    "figur_torso": (18, 36),
    "figur_arm_l": (32, 48),
    "figur_arm_r": (35, 51),
    "figur_head": (44, 60),
}
ZEIG_FROM, ZEIG_TO, LEHRER_HOLD = 66, 82, 94

# The teacher assembles ALONE, centred, in a tight frame — and that is a correction, not a
# simplification. The first pass staged the learner beside it, which forced the frame wide
# enough that the parts had nowhere off-stage to wait: figur.aufbau_entry parks each arm 1.5
# units out to its own side, and the teacher's left arm spent the opening two seconds hanging
# in the learner's face. Widening the gap only moved the collision. One figure in a portrait
# frame is what the shipped figur-aufbau already does, for exactly this reason.
#
# The pair belongs in the sockel scene, where nothing is flying in.
LEHRER_AT = (0.0, 0.0)
ARM_ENTRY_X = 1.55


def keyframe_lehrer(objects, p):
    """Assemble, then teach. Written here rather than reusing `figur.keyframe_aufbau` because
    the gesture beat has to overwrite the arm's landed rotation, and re-keying a curve another
    function already shaped is harder to read than one table that owns the whole clip."""
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, LEHRER_HOLD
    scene.render.fps = 24

    for obj in objects:
        enter, land = LEHRER_BEATS[obj.name]
        offset, rotation = figur.aufbau_entry(obj.name, p)
        if obj.name.startswith("figur_arm"):
            offset.x = math.copysign(ARM_ENTRY_X, offset.x)
        rest = obj.location.copy()
        obj.rotation_mode = "XYZ"

        obj.location = rest + offset
        obj.rotation_euler = [math.radians(a) for a in rotation]
        obj.keyframe_insert("location", frame=enter)
        obj.keyframe_insert("rotation_euler", frame=enter)

        obj.location = rest
        obj.rotation_euler = (0, 0, 0)
        obj.keyframe_insert("location", frame=land)
        obj.keyframe_insert("rotation_euler", frame=land)
        obj.keyframe_insert("location", frame=LEHRER_HOLD)

        if obj.name.endswith("arm_l"):
            obj.keyframe_insert("rotation_euler", frame=ZEIG_FROM)
            obj.rotation_euler = [math.radians(a) for a in ZEIG_LINKS]
            for frame in (ZEIG_TO, LEHRER_HOLD):
                obj.keyframe_insert("rotation_euler", frame=frame)
        else:
            obj.keyframe_insert("rotation_euler", frame=LEHRER_HOLD)

        # BACK/EASE_OUT overshoots and settles: the difference between a part that lands and a
        # part that merely arrives. A keyframe's interpolation governs the segment after it, so
        # the flat land→hold tail is unaffected whatever this says.
        for curve in figur.fcurves_of(obj.animation_data.action):
            for point in curve.keyframe_points:
                point.interpolation = "BACK"
                point.easing = "EASE_OUT"
                point.back = 0.9

    print(f"LEHRER {len(objects)} parts, frames 1..{LEHRER_HOLD} @24fps "
          f"({LEHRER_HOLD / 24:.2f}s), gesture {ZEIG_FROM}..{ZEIG_TO}")


def build_aufbau(animated, prop="keins"):
    """Teacher first: it is renamed to `lehrer_*`, which leaves `figur_*` free for the learner
    and keeps Blender from ever deduplicating a name into something with a dot in it."""
    mat = figur.make_material("ink", figur.REFERENCE)
    teacher, p = figur.build_figure(*LEHRER, mat=mat)
    figur.place(teacher, (LEHRER_AT[0], LEHRER_AT[1], 0.0))
    if animated:
        keyframe_lehrer(teacher, p)
    else:
        gesture(teacher)
    reprefix(teacher, "lehrer")

    if builder := PROPS[prop]:
        builder(mat)
    return teacher


# MARK: - Candidate B: alles auf einem Sockel


def build_sockel_scene(rim=True, prop="tafel"):
    mat = figur.make_material("ink", figur.REFERENCE)
    build_sockel(mat, rim=rim)
    teacher, _ = figure(LEHRER, (1.15, 0.25), mat=mat, prefix="lehrer")
    gesture(teacher)
    figure(LERNER, (-1.50, 0.05), yaw=34, mat=mat)
    if builder := PROPS[prop]:
        builder(mat, at=(1.85, 0.62) if prop == "tafel" else (2.30, -0.30))
    # A book, flat on the plinth at the learner's feet: the third thing that stays on the phone.
    # At 0.62×0.44×0.10 it was a sliver on the floor; a book has to have a spine to be a book.
    box((0.90, 0.64, 0.22), (-0.45, -0.85, 0.11), mat, "buch", rot=(0, 0, -18))


# MARK: - Candidate D: die Figur füllt sich
#
# The one the other three were circling. A wireframe of the figure stands there from the first
# frame — the whole shape of what is coming, present before any of it has arrived — and fills
# solid from the feet up as the bytes land.
#
# Why this beats parts flying in: assembly says "something is being built", which is a metaphor
# for a download. A wire shell filling to a line IS a progress bar, drawn in the shape of the
# thing being downloaded. Nobody has to be taught to read it, and it cannot lie about progress.
#
# Nothing here is keyframed. The fill is authored as horizontal SLABS of the solid figure, one
# prim each, and the app turns them on: band k is visible once progress passes (k+1)/BANDS.
# That is deliberate, not a shortcut — a baked clip would run on a clock, and a clock is exactly
# what a download is not. It also dodges the thing that would otherwise force a custom Metal
# shader, since RealityKit cannot clip a mesh to a plane without one.

BANDS = 24
WIRE_THICKNESS = 0.0065

# The shell is built at its own density, well below even the shipped low LOD, and that is the
# whole difference between a wireframe and a black blob. At the export LOD — 32 meridians on the
# head, 24 sides on a leg — the wires land closer together than they are thick and an early pass
# rendered a solid figure wearing a cage for a torso. A wire mesh has to be able to be seen
# through, so the geometry it is made from has to be coarse on purpose.
WIRE_LOD = {"sphere": (12, 6), "radial": 8}

# Rings and rungs before the strokes are traced: a cylinder is N verts around and *one* segment
# tall, so its edge graph has vertical bars and no ladder.
WIRE_CUTS = {"figur_torso": 2, "figur_leg_l": 3, "figur_leg_r": 3,
             "figur_arm_l": 2, "figur_arm_r": 2, "figur_head": 0}

# The shell ships a lighter ink than the fill so the two are legible apart in a judge render.
# The app overrides both by prim name, so this is a tuning convenience, not a contract.
WIRE_INK = 0xB9BEC4

# How much of the download's progress the outline gets before the fill starts. The two phases no
# longer overlap: the figure is drawn, *then* it fills. An overlapping lead read as one event
# with a fringe on it; separated, they read as two — a sketch, then the thing itself arriving.
# Mirrored in TutorSceneLab.swift.
DRAW_SHARE = 0.35

# Longest run of edges that becomes one stroke prim, in scene units. This is the pen's stride:
# a whole trail as one prim pops a complete circle into existence, and one prim per edge is a
# few hundred prims for no visible gain. Tuned so the count lands near 150.
STRICH_MAX_LEN = 0.42
# Draw order, bottom of the figure up. Within a part the strokes follow the trail they belong
# to, which is what keeps the pen travelling rather than jumping.
STRICH_ORDER = ("figur_leg_l", "figur_leg_r", "figur_torso",
                "figur_arm_l", "figur_arm_r", "figur_head")


def wire_parts(preset, height, mat):
    """The figure at wire density, subdivided but NOT wireframed — what is wanted here is the
    edge graph, and the Wireframe modifier throws it away in favour of tube geometry."""
    figur.LOD["draht"] = WIRE_LOD
    previous, figur._LOD = figur._LOD, "draht"
    objects, _ = figur.build_figure(preset, height, mat=mat)
    figur._LOD = previous
    for obj in objects:
        if cuts := WIRE_CUTS.get(obj.name, 0):
            figur._activate(obj)
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.mesh.subdivide(number_cuts=cuts)
            bpy.ops.object.mode_set(mode="OBJECT")
    return objects


def trails(points, edges):
    """Decompose an edge graph into long continuous polylines — the strokes a pen would make.

    Greedy and Eulerian-ish: start at the lowest vertex that still has an unused edge and walk
    until stuck. The one refinement that matters is *which* unused edge to take next: always the
    straightest continuation. Picking arbitrarily produces zig-zags that wander across the
    surface, where following the direction of travel keeps a sphere's ring a ring and its
    meridian a meridian. A UV sphere has all-even vertex degrees, so it decomposes into very few
    trails — most of a head is drawn in one unbroken line.
    """
    adjacency = {}
    for a, b in edges:
        adjacency.setdefault(a, set()).add(b)
        adjacency.setdefault(b, set()).add(a)
    unused = {frozenset((a, b)) for a, b in edges if a != b}

    out = []
    while unused:
        live = {v for edge in unused for v in edge}
        start = min(live, key=lambda v: (round(points[v].z, 4), points[v].x, points[v].y))
        trail, current, heading = [start], start, None
        while True:
            options = [n for n in adjacency[current] if frozenset((current, n)) in unused]
            if not options:
                break
            if heading is None:
                nxt = min(options, key=lambda n: (round(points[n].z, 4), points[n].x))
            else:
                nxt = max(options, key=lambda n: (points[n] - points[current]).normalized()
                          .dot(heading))
            unused.discard(frozenset((current, nxt)))
            heading = (points[nxt] - points[current]).normalized()
            trail.append(nxt)
            current = nxt
        if len(trail) > 1:
            out.append([points[v] for v in trail])
    return out


def split_trail(points, max_len):
    """Cut a trail into pen-stride chunks. Consecutive chunks share their joint vertex, so the
    tubes meet rather than leaving a gap at every seam."""
    chunks, current, run = [], [points[0]], 0.0
    for a, b in zip(points, points[1:]):
        run += (b - a).length
        current.append(b)
        if run >= max_len:
            chunks.append(current)
            current, run = [b], 0.0
    if len(current) > 1:
        chunks.append(current)
    return chunks


def stroke(points, mat, name):
    """One polyline as a bevelled tube, converted to mesh so it exports as ordinary geometry.

    Curve-and-bevel rather than the Wireframe modifier: the modifier makes one welded cage out
    of a whole part, and a cage cannot be drawn line by line. It is also lighter — round tubes
    at bevel_resolution 1 cost about half what the modifier's mitred junctions did.
    """
    curve = bpy.data.curves.new(name, type="CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = WIRE_THICKNESS
    curve.bevel_resolution = 1
    curve.fill_mode = "FULL"
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, point in enumerate(points):
        spline.points[i].co = (point.x, point.y, point.z, 1.0)
    curve.materials.append(mat)

    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    figur._activate(obj)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.view_layer.objects.active
    figur.name_part(obj, name)
    return obj


def draw_strokes(parts, mat):
    """Every part's edge graph as ordered stroke prims, `strich_000` upward in draw order."""
    ordered = sorted(parts, key=lambda o: STRICH_ORDER.index(o.name)
                     if o.name in STRICH_ORDER else len(STRICH_ORDER))
    index = 0
    for part in ordered:
        points = [part.matrix_world @ vertex.co for vertex in part.data.vertices]
        edges = [tuple(edge.vertices) for edge in part.data.edges]
        for trail in trails(points, edges):
            for chunk in split_trail(trail, STRICH_MAX_LEN):
                stroke(chunk, mat, f"strich_{index:03d}")
                index += 1
    return index


def join_all(objects, name):
    """Collapse a list of objects into one named prim. Bands cut across every part, so per-part
    names buy nothing inside a band and cost the app a walk."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    figur.name_part(joined, name)
    return joined


def slab(source, z0, z1, name, mat):
    """One horizontal band of ONE part, cut with a Boolean rather than with
    `bpy.ops.mesh.bisect`: bisect wants a 3D viewport and Blender has none in --background, so
    the tidier-looking call is the one that cannot run headless.

    One part at a time, and that is the load-bearing word. Cutting the *joined* figure looked
    equivalent and silently produced garbage — the arms overlap the torso, so the joined mesh
    self-intersects, and the EXACT solver answers a self-intersecting input with nonsense: one
    band came back holding the entire torso (z 0.75..1.23 for a 0.075 slab) and the four above
    it came back empty."""
    cutter = box((6.0, 6.0, z1 - z0), (0, 0, (z0 + z1) / 2), mat, f"{name}_cutter")
    band_obj = source.copy()
    band_obj.data = source.data.copy()
    bpy.context.collection.objects.link(band_obj)

    mod = band_obj.modifiers.new("band", "BOOLEAN")
    mod.operation = "INTERSECT"
    mod.object = cutter
    mod.solver = "EXACT"
    figur._activate(band_obj)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)

    if not band_obj.data.vertices:
        bpy.data.objects.remove(band_obj, do_unlink=True)
        return None
    figur.name_part(band_obj, name)
    return band_obj


def band(parts, k, step, prefix, mat):
    """One horizontal band across every part, as a single joined prim."""
    pieces = []
    for part in parts:
        piece = slab(part, k * step, (k + 1) * step, f"stueck_{prefix}_{k:02d}_{part.name}", mat)
        if piece:
            pieces.append(piece)
    if not pieces:
        return None
    return join_all(pieces, f"{prefix}_{k:02d}")


# MARK: - Aufwachen (the clip that plays once the fill completes)
#
# Stretch, jump, wave. It runs on the SIX-part figure, not on the bands — which is why the asset
# carries both: at 100 % the app hides all 48 slabs and shows `figur_*` underneath, geometrically
# identical, and presses play. A slab stack cannot move a limb.
#
# The jump is where the joints come apart. Each part's origin already sits at the joint it hangs
# from (hip, hip line, shoulder, neck), so drifting a part along Z opens a real gap without
# touching its size — the legs hang a little lower at the apex, the head floats a little higher.
# That is the whole organic trick, and it costs six numbers.

WACH_END = 134

# (frame, lift) for the whole body. The crouch is shallow and the apex is not: a Bauhaus figure
# with no knees can only say "jump" with air time.
WACH_LIFT = [(1, 0.0), (46, 0.0), (54, -0.07), (64, 0.38), (74, 0.0), (79, -0.045),
             (86, 0.0), (WACH_END, 0.0)]
# Extra lift per part AT THE APEX ONLY — the gaps open on the way up and close on the way down,
# because the bracketing keys at 54 and 74 carry no extra.
WACH_SPREAD = {"figur_leg_l": -0.05, "figur_leg_r": -0.05, "figur_head": 0.055,
               "figur_arm_l": 0.02, "figur_arm_r": 0.02, "figur_torso": 0.0}

# Rotations, in the figure's own frame. Arms rotate about Y (POSES["zeig"]'s axis: -105 takes the
# right arm from hanging to horizontal, so -160 is a stretch above the shoulder), swing fore/aft
# about X, and wave by yawing about Z.
WACH_ROT = {
    "figur_arm_r": [(1, (0, 0, 0)), (22, (0, -160, 0)), (30, (0, -160, 0)), (42, (0, 0, 0)),
                    (54, (28, 0, 0)), (64, (-40, -30, 0)), (74, (0, 0, 0)), (88, (0, 0, 0)),
                    (96, (0, -135, 0)), (102, (0, -135, -26)), (108, (0, -135, 26)),
                    (114, (0, -135, -26)), (120, (0, -135, 18)), (128, (0, -130, 0)),
                    (WACH_END, (0, -130, 0))],
    "figur_arm_l": [(1, (0, 0, 0)), (22, (0, 160, 0)), (30, (0, 160, 0)), (42, (0, 0, 0)),
                    (54, (28, 0, 0)), (64, (-40, 30, 0)), (74, (0, 0, 0)),
                    (WACH_END, (0, 0, 0))],
    "figur_leg_l": [(1, (0, 0, 0)), (54, (0, 0, 0)), (64, (15, 0, 0)), (74, (0, 0, 0)),
                    (WACH_END, (0, 0, 0))],
    "figur_leg_r": [(1, (0, 0, 0)), (54, (0, 0, 0)), (64, (15, 0, 0)), (74, (0, 0, 0)),
                    (WACH_END, (0, 0, 0))],
}


def keyframe_wach(objects):
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, WACH_END
    scene.render.fps = 24

    for obj in objects:
        obj.rotation_mode = "XYZ"
        rest = obj.location.copy()
        spread = WACH_SPREAD.get(obj.name, 0.0)
        for frame, lift in WACH_LIFT:
            extra = spread if frame == 64 else 0.0
            obj.location = rest + Vector((0, 0, lift + extra))
            obj.keyframe_insert("location", frame=frame)
        obj.location = rest

        for frame, angles in WACH_ROT.get(obj.name, [(1, (0, 0, 0)), (WACH_END, (0, 0, 0))]):
            obj.rotation_euler = [math.radians(a) for a in angles]
            obj.keyframe_insert("rotation_euler", frame=frame)
        obj.rotation_euler = (0, 0, 0)

    print(f"WACH 6 parts, frames 1..{WACH_END} @24fps ({WACH_END / 24:.2f}s): "
          f"stretch 1-42, jump 46-86, wave 88-{WACH_END}")


def build_fuellen(preset="standard", height=1.80):
    """The shell, then the fill it will take. Both built from the same PRESETS row at the same
    height, which is the only reason the solid lands inside its own outline."""
    mat = figur.make_material("ink", figur.REFERENCE)
    step = height / BANDS

    # The outline is traced as individual strokes rather than sliced into height bands, so it
    # can be *drawn* line by line instead of swept by a rising edge. A page that starts blank is
    # the whole point: a wire figure already standing there is a placeholder, where one being
    # drawn is something arriving.
    #
    # Built and consumed first so the six `figur_*` names are free again for the solid below —
    # Blender would otherwise dedupe them into `figur_leg_l.001`, and a dot is the one thing USD
    # mangles in a prim name.
    shell = wire_parts(preset, height, figur.make_material("draht", WIRE_INK))
    drawn = draw_strokes(shell, figur.make_material("draht2", WIRE_INK))
    for part in shell:
        bpy.data.objects.remove(part, do_unlink=True)

    parts, _ = figur.build_figure(preset, height, mat=mat)
    filled = sum(1 for k in range(BANDS) if band(parts, k, step, "fuell", mat))
    # The six parts stay in the scene rather than being deleted: they are what the wake-up clip
    # moves, and what the app swaps to the moment the last band lands.
    keyframe_wach(parts)
    print(f"FUELLEN {drawn} strokes + {filled}/{BANDS} fill bands, "
          f"step {step:.4f} over height {height}, draw share {DRAW_SHARE}")


# MARK: - Candidate C: das Gewicht
#
# One block, one landing. The plinth dips on impact and recovers — the only motion that can say
# "heavy" without a number, and the reason this is animated rather than a still.

BLOCK = 1.45
FALL_FROM, FALL_LAND, DIP_BOTTOM, DIP_BACK, GEWICHT_HOLD = 1, 28, 33, 44, 58
DIP = 0.10
# The plinth dip alone was invisible at 0.055. What actually says "heavy" is the bystander:
# a figure kicked off the deck and landing again is mass, where a slab moving a hair is noise.
KICK = 0.085


def build_gewicht(animated):
    mat = figur.make_material("ink", figur.REFERENCE)
    build_sockel(mat, size=(4.20, 2.60, 0.26), rim=False)
    figure(LERNER, (-1.45, 0.05), yaw=34, mat=mat)

    block = box((BLOCK, BLOCK, BLOCK), (0.95, -0.10, BLOCK / 2), mat, "block")
    if not animated:
        return

    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, GEWICHT_HOLD
    scene.render.fps = 24

    rest = block.location.copy()
    block.location = rest + Vector((0, 0, 6.0))
    block.keyframe_insert("location", frame=FALL_FROM)
    block.location = rest
    for frame in (FALL_LAND, GEWICHT_HOLD):
        block.keyframe_insert("location", frame=frame)
    for curve in figur.fcurves_of(block.animation_data.action):
        for point in curve.keyframe_points:
            point.interpolation = "QUAD"
            point.easing = "EASE_IN"

    # The dip is on the plinth, not the block: a block that squashes is cartoon, a plinth that
    # takes the weight is mass.
    platte = bpy.data.objects["sockel_platte"]
    base = platte.location.z
    for frame, z in ((FALL_LAND, base), (DIP_BOTTOM, base - DIP),
                     (DIP_BACK, base), (GEWICHT_HOLD, base)):
        platte.location.z = z
        platte.keyframe_insert("location", frame=frame)
    for curve in figur.fcurves_of(platte.animation_data.action):
        for point in curve.keyframe_points:
            point.interpolation = "SINE"
            point.easing = "EASE_IN_OUT"

    for obj in [o for o in bpy.data.objects if o.name.startswith("figur_")]:
        base = obj.location.z
        for frame, z in ((FALL_LAND, base), (DIP_BOTTOM, base + KICK),
                         (DIP_BACK, base), (GEWICHT_HOLD, base)):
            obj.location.z = z
            obj.keyframe_insert("location", frame=frame)
        for curve in figur.fcurves_of(obj.animation_data.action):
            for point in curve.keyframe_points:
                point.interpolation = "SINE"
                point.easing = "EASE_IN_OUT"

    print(f"GEWICHT block {BLOCK} falls {FALL_FROM}..{FALL_LAND}, dip {DIP} "
          f"{DIP_BOTTOM}..{DIP_BACK}, frames 1..{GEWICHT_HOLD}")


# MARK: - Drivers

SCENES = {
    # name: (builder, ortho, target_z, animated, last frame)
    "tutor-aufbau": (build_aufbau, 3.35, 1.15, True, LEHRER_HOLD),
    "tutor-sockel": (build_sockel_scene, 7.4, 1.00, False, 1),
    "tutor-gewicht": (build_gewicht, 6.4, 1.00, True, GEWICHT_HOLD),
    # No clip and no last frame: the app owns this one's timeline, because the download does.
    "tutor-fuellen": (build_fuellen, 2.55, 0.92, True, WACH_END),
}


def build_scene(name, animated, prop="tafel"):
    if name == "tutor-aufbau":
        # The prop is a sockel-scene question; this one is judged on the assembly alone.
        build_aufbau(animated, prop="keins")
    elif name == "tutor-fuellen":
        build_fuellen()
    elif name == "tutor-sockel":
        build_sockel_scene(prop=prop)
    else:
        build_gewicht(animated)


def storyboard(name, args, out_dir):
    """High LOD on purpose: faceting must never be mistaken for a composition problem. Same
    two-build split scene_aufbau makes — this pass is judged, the export pass ships."""
    _, ortho, target_z, animated, last = SCENES[name]
    figur._LOD = "high"
    figur.clear_scene()
    figur.stage(args.size, *figur.VIEWS["dim"], ortho, target_z)
    build_scene(name, animated, prop=args.prop)

    if name == "tutor-fuellen":
        # A still of this scene is just a solid figure — every band is on, and the six parts the
        # clip moves are sitting inside them. Two honest judge renders instead: the ladder of
        # fill levels the app steps through, and the clip that plays when it reaches the top.
        fill = sorted((o for o in bpy.data.objects if o.name.startswith("fuell_")),
                      key=lambda o: o.name)
        wire = sorted((o for o in bpy.data.objects if o.name.startswith("strich_")),
                      key=lambda o: o.name)
        solid = [o for o in bpy.data.objects if o.name.startswith("figur_")]

        for part in solid:
            part.hide_render = True
        cells = []
        for frac in (0.0, 0.10, 0.22, 0.35, 0.5, 0.68, 0.85, 1.0):
            drawn = min(1.0, frac / DRAW_SHARE)
            poured = max(0.0, (frac - DRAW_SHARE) / (1 - DRAW_SHARE))
            for group, progress in ((fill, poured), (wire, drawn)):
                for k, slice_ in enumerate(group):
                    slice_.hide_render = (k + 1) > progress * len(group)
            path = os.path.join(out_dir, f"{name}-p{int(frac * 100):03d}.png")
            figur.render_to(path)
            cells.append(path)
        figur.contact_sheet(cells, 4, os.path.join(out_dir, f"{name}{args.tag}.png"))

        for slice_ in fill + wire:
            slice_.hide_render = True
        for part in solid:
            part.hide_render = False
        cells = []
        for frame in range(1, WACH_END + 1, max(1, WACH_END // 15)):
            bpy.context.scene.frame_set(frame)
            path = os.path.join(out_dir, f"{name}-wach-f{frame:03d}.png")
            figur.render_to(path)
            cells.append(path)
        figur.contact_sheet(cells, 4, os.path.join(out_dir, f"{name}-wach{args.tag}.png"))
        return

    if not animated:
        figur.render_to(os.path.join(out_dir, f"{name}{args.tag}.png"))
        return
    step = max(1, last // 11)
    cells = []
    for frame in range(1, last + 1, step):
        bpy.context.scene.frame_set(frame)
        path = os.path.join(out_dir, f"{name}-f{frame:02d}.png")
        figur.render_to(path)
        cells.append(path)
    figur.contact_sheet(cells, 4, os.path.join(out_dir, f"{name}{args.tag}.png"))


def export_scene(name, args, out_dir):
    _, _, _, animated, _ = SCENES[name]
    figur._LOD = "low"
    figur.clear_scene()
    figur.setup_render(args.size)
    build_scene(name, animated, prop=args.prop)

    dest = os.path.join(RESOURCES, f"{name}.usdz")
    if animated:
        # The plain-text twin, written from this same scene before the .usdz so the two cannot
        # disagree. It is the only thing that proves the clip carries motion: Blender's USD
        # importer does not rebuild transform animation, so a re-import cannot tell an animated
        # asset from a broken one (figur.usda_animation says it at length).
        twin = os.path.join(out_dir, f"{name}.usda")
        bpy.ops.wm.usd_export(filepath=twin, export_materials=True,
                              export_animation=True, convert_orientation=True)
    figur.export_usdz(dest, animated=animated)
    print(f"EXPORT {dest}")
    if animated:
        figur.verify_animation(twin, expect_parts=False)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    default_out = os.path.join(ROOT, "tools", "blender", "renders", "tutor")

    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", choices=sorted(SCENES), action="append")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--size", type=int, default=640)
    ap.add_argument("--out-dir", default=default_out)
    ap.add_argument("--prop", default="tafel", choices=sorted(PROPS),
                    help="what stands beside the teacher: a lectern, a board, or nothing")
    ap.add_argument("--tag", default="", help="suffix for judge renders, to compare variants")
    ap.add_argument("--no-export", action="store_true", help="judge renders only")
    ap.add_argument("--verify", help="re-import a USDZ and print what is actually in it")
    args = ap.parse_args(argv)

    if args.verify:
        figur.verify(args.verify)
        return

    os.makedirs(args.out_dir, exist_ok=True)
    # Only the surviving candidate by default. The other three were the comparison that made the
    # case for it and are no longer shipped — `--all`, or `--scene <name>`, still builds them, but
    # a bare run must not quietly put 240 KB of rejected assets back into Resources/.
    if args.scene:
        names = args.scene
    elif args.all:
        names = sorted(SCENES)
    else:
        names = ["tutor-fuellen"]
    for name in names:
        storyboard(name, args, args.out_dir)
        if not args.no_export:
            export_scene(name, args, args.out_dir)


if __name__ == "__main__":
    main()
