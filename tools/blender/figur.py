"""figur.py — the Bauhaus figure rig.

Run headless:
    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/blender/figur.py -- --contact

A figure made of the five primitives the app already speaks: two cylinder legs, a cube torso,
two cone arms (wide end at the shoulder, point at the hand), a sphere head. Same charcoal, same
camera rake, same key/rim/fill as `prep_render.py`, so the figure and every existing prop read
as one world.

Like the preposition rig, this is a *parameter sweep*, not a model: every dimension is a
fraction of total height in PRESETS, so `--height` rescales the whole figure and the three
presets differ only in ratios. Judge them with `--contact`, then edit one table.

Two contracts the app depends on:

  - **Names carry no dots.** USD mangles `figur.leg.l` into `figur_leg_l`, and the runtime
    matches prim names by substring, so the underscored name is authored here directly.
  - **Origins sit at joints, not centroids** — hip, hip line, shoulder, neck. Every part rests
    at rotation identity, so an animation is a pure offset from rest and a part rotates about
    the joint it actually hangs from. That, plus six named rigid parts, *is* the rig; a Bauhaus
    figure has nothing that bends (see tools/genprops/animate_gift.py for the same idiom).

One flat charcoal material shared by all six parts, so the app can re-tint at runtime exactly
like every prop in tools/genprops. Renders carry alpha (`film_transparent`) and composite onto
any AppTheme ground.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

# MARK: - Palette
#
# The neutral charcoal every non-subject form in the app wears (prep_render.py PALETTE).
# Deliberately not a case color and not a gender color: the figure must never contradict the
# der/die/das coding the app teaches everywhere else.

REFERENCE = 0x33383D

# Inks a figure may wear in a scene, for telling two people apart (die Figur and der Freund).
# The app already means something by nearly every hue: der blue, die red, das green, plural gold,
# the case colors (graphite, orange, teal, brown, violet, slate) and the question side's light
# grey. So a second ink can differ in warmth and value, never in hue. Scene USDZs keep the color
# they were exported with (only the subject is re-tinted at runtime), so an ink needs no app code.
INKS = {"charcoal": REFERENCE, "warmgrau": 0x625A52, "kreide": 0xE4DDCF}

# The Grundform light ground (AppTheme.screenBackground), used only as the contact-sheet
# backdrop so alpha renders can be judged against the theme they will sit on.
GROUND = 0xF3EFE6


def srgb_to_linear(c: float) -> float:
    """Blender works in linear light; the view transform is forced to Standard below, so a
    linearized sRGB hex round-trips to that exact hex in the PNG."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(hex_value: int, alpha: float = 1.0):
    r = ((hex_value >> 16) & 0xFF) / 255
    g = ((hex_value >> 8) & 0xFF) / 255
    b = (hex_value & 0xFF) / 255
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), alpha)


def make_material(name: str, hex_value: int):
    """The rig's `dim` look: matte Principled, the same roughness and specular level the
    preposition props wear, so a figure beside a dog looks like the same material."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = rgba(hex_value)
    shader.inputs["Roughness"].default_value = 0.62
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.25
    links.new(shader.outputs[0], out.inputs["Surface"])
    return mat


# MARK: - Proportions
#
# Every value is a fraction of total height H. The four stacked spans must sum to exactly 1.0
# (leg + torso + neck + head diameter), which is what keeps `--height` honest: the figure is
# always exactly as tall as it claims, so it can be scale-matched against the story cast
# (hund 1.4, hütte 1.5, baum 1.9) without measuring a render.

PRESETS = {
    # Closest to Schlemmer's Triadic figures: long legs, thin limbs, a small head.
    "schlank": {
        "leg_len": 0.400, "leg_r": 0.050, "leg_gap": 0.140,
        "torso_w": 0.290, "torso_d": 0.200, "torso_h": 0.334,
        "neck": 0.050, "head_r": 0.108,
        "arm_r": 0.072, "arm_len": 0.330, "arm_tilt": 10.0, "arm_blunt": 0.30,
    },
    # The default. Reads as a figure at rest without tipping into either caricature.
    "standard": {
        "leg_len": 0.355, "leg_r": 0.065, "leg_gap": 0.160,
        "torso_w": 0.340, "torso_d": 0.230, "torso_h": 0.330,
        "neck": 0.055, "head_r": 0.130,
        "arm_r": 0.085, "arm_len": 0.310, "arm_tilt": 12.0, "arm_blunt": 0.30,
    },
    # Toy-blocky: short legs, thick limbs, a big head. The one that survives at 40pt.
    "staemmig": {
        "leg_len": 0.270, "leg_r": 0.082, "leg_gap": 0.185,
        "torso_w": 0.390, "torso_d": 0.265, "torso_h": 0.338,
        "neck": 0.060, "head_r": 0.166,
        "arm_r": 0.098, "arm_len": 0.280, "arm_tilt": 15.0, "arm_blunt": 0.30,
    },
}

# `neck` is a real gap, not a joint: the head floats clear of the torso rather than sitting in
# it. A sphere resting on a cube's top face reads as a head sunk into the shoulders — and the
# app's own `figure.stand` symbols already detach the head, so the gap is the house idiom.

# Keys that are ratios or angles, not lengths — `scaled()` must leave them alone.
RATIOS = {"arm_tilt", "arm_blunt"}

# Render quality vs. shipped-geometry size, the same trade `prep_render.py` records for its
# sphere: a dense mesh is right for a still and wasteful in a USDZ, where the silhouette on
# screen is identical. `--usdz` forces "low".
LOD = {
    "high": {"sphere": (96, 48), "radial": 64},
    "low": {"sphere": (32, 16), "radial": 24},
}
_LOD = "high"

PART_NAMES = ("leg_l", "leg_r", "torso", "arm_l", "arm_r", "head")


def part_role(obj):
    """Which of the six parts an object is, whatever figure it belongs to.

    A scene with two figures names the second one's parts `freund_leg_l` and so on, and
    Blender suffixes a clashing name (`figur_leg_l.001`) before anything can rename it. Poses
    and clips are keyed by role, so they work on either figure through all of that.
    """
    base = obj.name.split(".")[0]
    for role in PART_NAMES:
        if base == role or base.endswith("_" + role):
            return role
    return None


# MARK: - Object helpers


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def bake_transform(obj):
    """Fold rotation and scale into the mesh so the part rests at identity.

    This is what makes the joint origins useful: at rest every part is
    (location = its joint, rotation = 0, scale = 1), so an assembly keyframe is a pure offset
    from rest rather than a delta from some authored tilt nobody can see in the file.
    """
    _activate(obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def set_origin(obj, at):
    """Move the object's origin to a joint. The 3D-cursor idiom from animate_gift.py."""
    _activate(obj)
    bpy.context.scene.cursor.location = Vector(at)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)


def name_part(obj, name):
    """Name the object *and* its mesh datablock.

    USD writes each part as `def Xform "<object>" { def Mesh "<mesh data>" }`, so leaving the
    datablock as Blender's default puts `figur_leg_l` on the Xform and `Cylinder` on the mesh.
    The app finds parts by walking descendants for a name substring, and lands on whichever
    level it reaches first — so both levels carry the name and the match cannot depend on which.
    """
    obj.name = name
    obj.data.name = name


def smooth(obj, auto=True):
    """Spheres shade fully smooth; cylinders and cones need the cap crease kept, or the rim
    of a leg smears into the floor and the arm loses its point."""
    _activate(obj)
    if auto:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    else:
        bpy.ops.object.shade_smooth()


# MARK: - The parts
#
# Each builder returns its objects already named, materialled, baked to identity, and
# origin-set to the joint it hangs from. Feet sit on z = 0 and the figure is centred in x/y —
# the grounding contract every converted prop follows (convert_prop.py).


def build_legs(p, mat):
    """Two cylinders side by side. Origin at the hip, so a leg swings from the top."""
    out = []
    for side, name in ((-1, "figur_leg_l"), (1, "figur_leg_r")):
        x = side * p["leg_gap"] / 2
        bpy.ops.mesh.primitive_cylinder_add(
            radius=p["leg_r"], depth=p["leg_len"], vertices=LOD[_LOD]["radial"],
            location=(x, 0, p["leg_len"] / 2),
        )
        obj = bpy.context.active_object
        name_part(obj, name)
        obj.data.materials.append(mat)
        smooth(obj)
        bake_transform(obj)
        set_origin(obj, (x, 0, p["leg_len"]))
        out.append(obj)
    return out


def build_torso(p, mat):
    """The cube sitting across both legs. Origin at the hip line, so the upper body leans
    from the waist rather than pivoting around its own middle."""
    hip = p["leg_len"]
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, hip + p["torso_h"] / 2))
    obj = bpy.context.active_object
    name_part(obj, "figur_torso")
    obj.scale = Vector((p["torso_w"], p["torso_d"], p["torso_h"]))
    obj.data.materials.append(mat)
    bake_transform(obj)
    set_origin(obj, (0, 0, hip))
    return [obj]


def build_arms(p, mat):
    """Two cones, wide end at the shoulder and narrow end at the hand, tilted out from vertical.

    Built by aiming the cone's local +Z (which runs base → tip) down the arm direction with
    `to_track_quat`, rather than by composing a 180° flip with an outward tilt — one rotation,
    and the same trick the camera uses to look at its target.

    `arm_blunt` stops the taper short of a true apex. A cone that closes to a point reads as a
    blade rather than a limb — the tip is the thinnest thing in the figure and the eye lands on
    it — so the hand end keeps a fraction of the shoulder radius.
    """
    hip = p["leg_len"]
    shoulder_z = hip + p["torso_h"] - p["arm_r"]
    out = []
    for side, name in ((-1, "figur_arm_l"), (1, "figur_arm_r")):
        shoulder = Vector((side * (p["torso_w"] / 2 + p["arm_r"] * 0.35), 0, shoulder_z))
        tilt = math.radians(p["arm_tilt"])
        direction = Vector((side * math.sin(tilt), 0, -math.cos(tilt)))
        bpy.ops.mesh.primitive_cone_add(
            radius1=p["arm_r"], radius2=p["arm_r"] * p["arm_blunt"], depth=p["arm_len"],
            vertices=LOD[_LOD]["radial"],
            location=shoulder + direction * (p["arm_len"] / 2),
            # radius1 sits at local -Z and radius2 at +Z, so aiming local +Z along the arm puts
            # the wide end at the shoulder and the narrow end at the hand.
            rotation=direction.to_track_quat("Z", "Y").to_euler(),
        )
        obj = bpy.context.active_object
        name_part(obj, name)
        obj.data.materials.append(mat)
        smooth(obj)
        bake_transform(obj)
        set_origin(obj, shoulder)
        out.append(obj)
    return out


def build_head(p, mat):
    """The sphere. Origin at the neck — its own underside — so a nod or a tilt pivots where a
    head actually joins a body instead of orbiting the centre of the skull."""
    neck_z = p["leg_len"] + p["torso_h"] + p["neck"]
    segments, rings = LOD[_LOD]["sphere"]
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=p["head_r"], segments=segments, ring_count=rings,
        location=(0, 0, neck_z + p["head_r"]),
    )
    obj = bpy.context.active_object
    name_part(obj, "figur_head")
    obj.data.materials.append(mat)
    smooth(obj, auto=False)
    bake_transform(obj)
    set_origin(obj, (0, 0, neck_z))
    return [obj]


BUILDERS = {"leg": build_legs, "torso": build_torso, "arm": build_arms, "head": build_head}


def scaled(preset: str, height: float, override=None):
    """The proportion table in scene units. Fractions live in PRESETS; nothing downstream
    knows they were fractions."""
    table = dict(PRESETS[preset])
    table.update(override or {})
    return {k: (v if k in RATIOS else v * height) for k, v in table.items()}


def build_figure(preset, height, part="all", mat=None, override=None):
    """Six top-level objects, no parenting.

    Flat on purpose: the app's scene loader only walks direct children when it collects the
    pieces it flies into place, so a nested rig would be invisible to it. Keeping the figure
    flat means it can later ride the existing preposition runtime unchanged.
    """
    p = scaled(preset, height, override)
    mat = mat or make_material("figur", REFERENCE)
    kinds = BUILDERS.keys() if part == "all" else [part]
    objects = []
    for kind in kinds:
        objects += BUILDERS[kind](p, mat)
    return objects, p


# MARK: - Poses (die Figur führt vor)
#
# Static stances for the preposition scenes: the figure acts in the relational words (walks
# with the dog, waits by the clock, sits at the table) and demonstrates in the spatial ones
# (stands at its mark, arm raised toward the subject). A pose is rotations about the joints
# the part origins already sit at, plus a derived root drop — data, not new geometry, so the
# whole vocabulary is judged with `--pose <name>` renders and tuned in one table.
#
# Angles are (x, y, z) degrees, in the figure's own frame: the hip line runs along X, so the
# figure faces ±Y and a stride swings about X. A scene whose travel runs along world X yaws
# the walker ±90° via `place` so it faces where it is going — swinging the legs along the
# hip line instead just scissors them into each other (first geh probe, 2026-08-12).

POSES = {
    # Rest — exactly what build_figure produces.
    "steh": {},
    # Mid-stride: legs counter-swung fore/aft, arms swinging opposite. The runtime slides the
    # whole figure (movers: "figur"); this pose is what keeps the slide reading as a walk.
    "geh": {"figur_leg_l": (18, 0, 0), "figur_leg_r": (-18, 0, 0),
            "figur_arm_l": (-15, 0, 0), "figur_arm_r": (15, 0, 0)},
    # Seated, legs straight out toward +Y — the rig has no knees, and a Bauhaus figure sits
    # like a doll on a ledge. The hips drop most of a leg length (see apply_pose).
    "sitz": {"figur_leg_l": (82, 0, 0), "figur_leg_r": (82, 0, 0)},
    # The demonstrator: right arm raised toward the action (+X), the museum-guide gesture.
    "zeig": {"figur_arm_r": (0, -105, 0)},
}


def apply_pose(objects, p, pose, mirror=False, held=None):
    """Rotate parts about their joints into a named stance.

    Location changes derive from the pose rather than living in the table: sitz drops every
    part by most of the leg length, because the legs no longer hold the body up. Applied
    before `place`, while the figure still stands at the origin.

    A name from GESTEN (below) is solved through the joint-space rig instead, so a scene can
    hold any frame-0 gesture as a static pose.
    """
    if pose in GESTEN:
        return pose_gesture(objects, p, resolve(pose), mirror=mirror, held=held)
    rotations = POSES[pose]
    for obj in objects:
        if spec := rotations.get("figur_" + (part_role(obj) or "")):
            obj.rotation_mode = "XYZ"
            obj.rotation_euler = [math.radians(a) for a in spec]
    if pose == "sitz":
        for obj in objects:
            obj.location.z -= p["leg_len"] * 0.88
    return objects


def place(objects, at, yaw=0.0):
    """Move a built figure to a scene position, yawed about its own vertical axis.

    The parts are flat on purpose (no parent — see build_figure), so the yaw spins each
    part's joint location around the figure's axis and composes onto its own rotation;
    a parent empty would hide the parts from the runtime's piece walk.
    """
    spin = Matrix.Rotation(math.radians(yaw), 4, "Z")
    offset = Vector(at)
    for obj in objects:
        obj.location = spin @ obj.location + offset
        obj.rotation_euler = (spin @ obj.rotation_euler.to_matrix().to_4x4()).to_euler()
    return objects


def report(preset, height, p):
    """Print the built dimensions — the stack has to add up to `height`, and a render can't
    prove that. A sweep over one of the four stacked spans will break the sum on purpose; the
    flag is there so a broken sum is never mistaken for a rendering difference."""
    stack = p["leg_len"] + p["torso_h"] + p["neck"] + 2 * p["head_r"]
    if abs(stack - height) > 1e-4:
        print(f"  ⚠ stack {stack:.4f} ≠ height {height:.3f} — this figure is not {height} tall")
    print(f"FIGUR {preset} h={height:.3f} stack={stack:.4f} "
          f"leg={p['leg_len']:.3f}r{p['leg_r']:.3f} "
          f"torso={p['torso_w']:.3f}x{p['torso_d']:.3f}x{p['torso_h']:.3f} "
          f"head_r={p['head_r']:.3f} arm={p['arm_len']:.3f}r{p['arm_r']:.3f}@{p['arm_tilt']:.0f}°")


# MARK: - The world (camera, lights, render) — prep_render.py's `dim` look
#
# Same rake, new framing. The azimuth/elevation/distance are the preposition rig's, so a figure
# render and a preposition render are recognisably the same picture; only `ortho_scale` and the
# look-at height change, because a 1.8-unit standing figure wants a portrait frame and a table
# scene wants a landscape one.

VIEWS = {"front": (0.0, 0.0), "dim": (21.0, 17.0), "side": (90.0, 0.0)}

LIGHT_SCALE = 0.55


def setup_camera(azimuth=21.0, elevation=17.0, ortho=2.6, target_z=0.9, distance=11.0):
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)

    target = Vector((0, 0, target_z))
    az, el = math.radians(azimuth), math.radians(elevation)
    cam.location = (
        distance * math.sin(az) * math.cos(el),
        -distance * math.cos(az) * math.cos(el),
        target.z + distance * math.sin(el),
    )
    cam.rotation_euler = (Vector(cam.location) - target).to_track_quat("Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def setup_lights():
    """Verbatim from prep_render.py: contrast comes from the ~7:1 key:fill ratio, not from
    absolute level — turning the level up instead drags the charcoal toward grey."""
    key_data = bpy.data.lights.new("key", type="AREA")
    key_data.energy = 2600 * LIGHT_SCALE
    key_data.size = 3.0
    key = bpy.data.objects.new("key", key_data)
    key.location = (-4.6, -4.2, 6.4)
    key.rotation_euler = (math.radians(42), 0, math.radians(-42))
    bpy.context.collection.objects.link(key)

    rim_data = bpy.data.lights.new("rim", type="AREA")
    rim_data.energy = 1700 * LIGHT_SCALE
    rim_data.size = 1.6
    rim = bpy.data.objects.new("rim", rim_data)
    rim.location = (4.8, 4.4, 2.6)
    rim.rotation_euler = (math.radians(74), 0, math.radians(133))
    bpy.context.collection.objects.link(rim)

    fill_data = bpy.data.lights.new("fill", type="AREA")
    fill_data.energy = 360 * LIGHT_SCALE
    fill_data.size = 9
    fill = bpy.data.objects.new("fill", fill_data)
    fill.location = (4.2, -6.4, 0.6)
    fill.rotation_euler = (math.radians(84), 0, math.radians(36))
    bpy.context.collection.objects.link(fill)


def setup_render(size):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    # Standard, NOT AgX: a film-emulation transform would shift the charcoal off-palette.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 256
        scene.eevee.use_shadows = True
        scene.eevee.shadow_ray_count = 4
        scene.eevee.shadow_step_count = 8
        scene.eevee.shadow_resolution_scale = 2.0


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# MARK: - Export


def export_usdz(path, animated=False):
    """Geometry only. A camera smuggled inside a shipped asset can hijack or crash the device
    renderer — three of them inside prep3d-story-fuer trapped RealityKit on iPhone,
    2026-07-30 — so they are removed here as well as defensively in Swift.

    `animated` writes the keyframes as USD TimeSamples, one per frame over the scene range.
    RealityKit finds them as an entity animation and the app plays it on load, so the whole
    choreography costs the runtime nothing beyond pressing play.
    """
    for obj in [o for o in bpy.data.objects if o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(obj, do_unlink=True)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.wm.usd_export(
        filepath=path,
        export_materials=True,
        export_animation=animated,
        # RealityKit expects Y-up; Blender authors Z-up.
        convert_orientation=True,
    )


# MARK: - Der Aufbau (the self-assembly clip)
#
# Built the order you would actually build it: legs, then the torso onto them, then the arms,
# then the head. The beats overlap by design — a strictly sequential build reads as a queue
# rather than a construction.
#
# Baked here rather than driven in Swift because the app's runtime motion path is
# translation-only (it writes positions, never rotations), and the arms swinging down onto the
# shoulders is the beat that makes this read as assembly instead of as parts sliding together.

# part → (frame it starts moving, frame it lands)
AUFBAU = {
    "figur_leg_l": (1, 18),
    "figur_leg_r": (5, 22),
    "figur_torso": (18, 36),
    "figur_arm_l": (32, 48),
    "figur_arm_r": (35, 51),
    "figur_head": (44, 60),
}
# Assembled and still for the last three quarters of a second, so the *storyboard* ends on the
# figure rather than on the last thing that moved.
#
# The exported clip runs 1..60, not 1..78, and that is correct rather than a truncation: the
# 60→78 samples are all identical, and USD holds the final sample forever, so the exporter drops
# the flat tail. Played once, the figure simply stays assembled.
AUFBAU_HOLD = 78


def fcurves_of(action):
    """Every F-curve in an action, on either API.

    Blender 5.0 removed `action.fcurves` outright — layered actions keep their curves at
    `action.layers[].strips[].channelbags[].fcurves`. The legacy path is still tried first so
    this keeps working on an older Blender.
    """
    legacy = getattr(action, "fcurves", None)
    if legacy:
        return list(legacy)
    curves = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                curves.extend(bag.fcurves)
    return curves


def aufbau_entry(name, p):
    """Where a part waits before its beat: (offset from its rest position, rotation in degrees).

    Each part enters along the axis its own joint implies — legs rise from underneath, the torso
    and head drop from above, the arms come in from the side already raised and rotate down onto
    the shoulder. Every start is far enough out to sit outside a portrait frame, so a part that
    has not had its beat yet is simply not on screen.
    """
    if name.startswith("figur_leg"):
        return Vector((0, 0, -(p["leg_len"] + 0.9))), (0, 0, 0)
    if name == "figur_torso":
        return Vector((0, 0, 1.9)), (0, 0, 0)
    if name.startswith("figur_arm"):
        side = 1 if name.endswith("_r") else -1
        # Rotating about +Y carries the arm's rest direction (roughly -Z) toward -X, so the sign
        # is flipped to raise each arm on its own side rather than across the body.
        return Vector((side * 1.5, 0, 0.35)), (0, -side * 80, 0)
    return Vector((0, 0, 1.6)), (0, 0, 0)


def keyframe_aufbau(objects, p):
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, AUFBAU_HOLD
    scene.render.fps = 24

    for obj in objects:
        enter, land = AUFBAU[obj.name]
        offset, rotation = aufbau_entry(obj.name, p)
        rest = obj.location.copy()
        obj.rotation_mode = "XYZ"

        obj.location = rest + offset
        obj.rotation_euler = [math.radians(a) for a in rotation]
        obj.keyframe_insert("location", frame=enter)
        obj.keyframe_insert("rotation_euler", frame=enter)

        obj.location = rest
        obj.rotation_euler = (0, 0, 0)
        for frame in (land, AUFBAU_HOLD):
            obj.keyframe_insert("location", frame=frame)
            obj.keyframe_insert("rotation_euler", frame=frame)

        # A keyframe's interpolation governs the segment *after* it, so this shapes the travel
        # leg; the land → hold segment is flat whatever it says. BACK/EASE_OUT overshoots
        # slightly and settles back, which is the difference between a part that lands and a
        # part that merely arrives.
        for curve in fcurves_of(obj.animation_data.action):
            for point in curve.keyframe_points:
                point.interpolation = "BACK"
                point.easing = "EASE_OUT"
                point.back = 0.9

    print(f"AUFBAU {len(objects)} parts, frames 1..{AUFBAU_HOLD} @24fps "
          f"({AUFBAU_HOLD / 24:.2f}s)")


def usda_animation(path):
    """Read the TimeSamples out of a plain-text USD file: {prim: {ops}}, and the frame range.

    This exists because the round-trip cannot answer the question. Blender's USD *importer*
    does not rebuild transform animation as keyframes, so a re-imported clip looks static — an
    animated asset and a broken one are indistinguishable that way, and the check would report
    a pass for a file with no motion in it. The exported text is the evidence.
    """
    prim, op, ops, frames = None, None, {}, set()
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith('def Xform "'):
                prim = stripped.split('"')[1]
            elif ".timeSamples" in stripped and "{" in stripped:
                op = stripped.split(":")[-1].split(".")[0]
                ops.setdefault(prim, set()).add(op)
            elif op and stripped.startswith("}"):
                op = None
            elif op:
                head = stripped.split(":")[0].strip()
                if head.lstrip("-").isdigit():
                    frames.add(int(head))
    return ops, (min(frames), max(frames)) if frames else None


def verify_animation(path, expect_parts=True):
    ops, span = usda_animation(path)
    animated = {p: sorted(v) for p, v in ops.items() if p and p != "root"}
    print(f"  animation: {len(animated)} prims, frames {span[0]}..{span[1]}" if span
          else "  animation: NONE — the clip carries no TimeSamples")
    for prim in sorted(animated):
        print(f"    {prim:24s} {','.join(animated[prim])}")
    missing = [f"figur_{n}" for n in PART_NAMES if f"figur_{n}" not in animated]
    if expect_parts:
        print("  animated parts:", "all six" if not missing else f"MISSING {missing}")
    return bool(span) and not missing


def verify(path):
    """Re-import an export and print what actually landed in it.

    `merge_parent_xform=False` on purpose: the default collapses each `Xform{Mesh}` pair into
    one Blender object and names it after the *Mesh*, which reports `Cylinder` for a part
    authored as `figur_leg_l` and hides the very names the app matches on. Importing unmerged
    shows the prim tree the way RealityKit will walk it. (Reading the names out of the .usdz
    with `strings` is not a substitute — the crate compresses its token table, so most names
    are simply invisible there.)

    A render proves the picture; only this proves the file.
    """
    clear_scene()
    bpy.ops.wm.usd_import(filepath=os.path.abspath(path), merge_parent_xform=False)
    print(f"VERIFY {path} ({os.path.getsize(path)} bytes)")

    present, stowaways = set(), []
    for obj in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        present.add(obj.name)
        detail = ""
        if obj.type == "MESH":
            detail = f" verts={len(obj.data.vertices)} polys={len(obj.data.polygons)}"
        action = obj.animation_data.action if obj.animation_data else None
        if action:
            curves = fcurves_of(action)
            frames = sorted({int(kp.co[0]) for fc in curves for kp in fc.keyframe_points})
            channels = sorted({fc.data_path for fc in curves})
            detail += f" keys={len(frames)} frames={frames[0]}..{frames[-1]} {','.join(channels)}"
        flag = ""
        if obj.type in ("CAMERA", "LIGHT"):
            stowaways.append(obj.name)
            flag = "  ← STOWAWAY"
        print(f"  {obj.name:24s} {obj.type:8s}{detail}{flag}")

    missing = [f"figur_{n}" for n in PART_NAMES if f"figur_{n}" not in present]
    print("  parts:", "all six present" if not missing else f"MISSING {missing}")
    print("  stowaways:", "none" if not stowaways else stowaways)

    # Motion is checked against the plain-text twin, never against this import — see
    # `usda_animation`. Say so out loud when there is no twin, so a silent "no keyframes here"
    # is never read as "this clip is static".
    twin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders", "figur",
                        os.path.splitext(os.path.basename(path))[0] + ".usda")
    if os.path.exists(twin):
        verify_animation(twin)
    else:
        print("  animation: not checked (no .usda twin; Blender's importer drops USD "
              "transform animation, so this import cannot tell you)")
    return not missing and not stowaways


# MARK: - Contact sheet
#
# One image instead of nine, because proportions are judged by *comparison* — three presets
# against each other, three angles against each other. The cells are also written out
# individually so any one of them can be re-examined at full resolution.


def contact_sheet(cell_paths, cols, out_path, ground=GROUND):
    """Composite rendered cells onto the theme ground.

    Every image is handled as Non-Color so no colour management touches the paste path: the
    bytes that came out of the renderer are the bytes that go into the sheet.
    """
    import numpy as np

    images = []
    for path in cell_paths:
        img = bpy.data.images.load(path)
        img.colorspace_settings.name = "Non-Color"
        img.alpha_mode = "STRAIGHT"
        images.append(img)

    width, height = images[0].size
    rows = math.ceil(len(images) / cols)
    canvas = np.zeros((rows * height, cols * width, 4), dtype=np.float32)
    canvas[:, :, 0] = ((ground >> 16) & 0xFF) / 255
    canvas[:, :, 1] = ((ground >> 8) & 0xFF) / 255
    canvas[:, :, 2] = (ground & 0xFF) / 255
    canvas[:, :, 3] = 1.0

    for i, img in enumerate(images):
        buf = np.array(img.pixels[:], dtype=np.float32).reshape(height, width, 4)
        row, col = divmod(i, cols)
        # Blender image buffers are bottom-up, so row 0 of the grid is the top band.
        y0 = (rows - 1 - row) * height
        x0 = col * width
        alpha = buf[:, :, 3:4]
        target = canvas[y0:y0 + height, x0:x0 + width, 0:3]
        canvas[y0:y0 + height, x0:x0 + width, 0:3] = buf[:, :, 0:3] * alpha + target * (1 - alpha)
        bpy.data.images.remove(img)

    out = bpy.data.images.new("contact", width=cols * width, height=rows * height, alpha=True)
    out.colorspace_settings.name = "Non-Color"
    out.pixels = canvas.ravel()
    out.filepath_raw = os.path.abspath(out_path)
    out.file_format = "PNG"
    out.save()
    print(f"CONTACT {out_path} {cols * width}x{rows * height} ({len(images)} cells)")


# MARK: - Scenes


def stage(size, azimuth, elevation, ortho, target_z):
    setup_render(size)
    setup_camera(azimuth, elevation, ortho, target_z)
    setup_lights()


def import_prop(name, height, at, mat):
    """Bring a converted prop from tools/genprops/samples in as a charcoal reference — the
    same path prep_render.py's `mesh` kind uses. Only for the scale check; nothing imported
    here is ever exported."""
    path = os.path.normpath(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "genprops", "samples", name + ".usdz"))
    before = set(bpy.context.scene.objects)
    bpy.ops.wm.usd_import(filepath=path)
    for stray in [o for o in bpy.context.scene.objects
                  if o not in before and o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(stray, do_unlink=True)
    imported = [o for o in bpy.context.scene.objects
                if o not in before and o.type == "MESH"]
    if not imported:
        raise ValueError(f"nothing imported from {path}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in imported:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = imported[0]
    if len(imported) > 1:
        bpy.ops.object.join()
    prop = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    corners = [prop.matrix_world @ Vector(c) for c in prop.bound_box]
    span = max(v.z for v in corners) - min(v.z for v in corners)
    prop.scale = (height / span if span > 0 else 1.0,) * 3
    bpy.ops.object.transform_apply(scale=True)
    corners = [prop.matrix_world @ Vector(c) for c in prop.bound_box]
    centre = sum(corners, Vector()) / 8
    x, y, z = at
    prop.location += Vector((x - centre.x, y - centre.y, z - min(v.z for v in corners)))
    bpy.ops.object.transform_apply(location=True)
    prop.data.materials.clear()
    prop.data.materials.append(mat)
    prop.name = f"reference_{name}"
    return prop


def add_box(size, at, mat, name):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    obj = bpy.context.active_object
    obj.scale = Vector(size)
    obj.data.materials.append(mat)
    obj.name = name
    return obj


def build_table(mat, at=(0, 0, 0), size=(2.5, 1.5, 1.25)):
    """prep_render.py's `table` reference, so the scale check measures the figure against a
    form whose size is already settled in the shipped scenes."""
    w, d, h = size
    x, y, z = at
    top_t, leg = 0.22, 0.17
    add_box((w, d, top_t), (x, y, z), mat, "reference_top")
    for i, (dx, dy) in enumerate([(-1, -1), (1, -1), (-1, 1), (1, 1)]):
        add_box((leg, leg, h),
                (x + dx * (w / 2 - leg), y + dy * (d / 2 - leg), z - top_t / 2 - h / 2),
                mat, f"reference_leg{i}")


def scene_contact(args, out_dir):
    """Three presets × three angles. Rows are presets top to bottom in PRESETS order; columns
    are front, dim, side."""
    cells = []
    for preset in PRESETS:
        for view, (az, el) in VIEWS.items():
            clear_scene()
            stage(args.size, az, el, args.ortho, args.target_z)
            _, p = build_figure(preset, args.height)
            report(preset, args.height, p)
            path = os.path.join(out_dir, f"figur-{preset}-{view}.png")
            render_to(path)
            cells.append(path)
    contact_sheet(cells, len(VIEWS), os.path.join(out_dir, "figur-contact.png"))
    print("LAYOUT rows=" + ",".join(PRESETS) + " cols=" + ",".join(VIEWS))


def scene_sweep(args, out_dir):
    """One proportion varied across a row, every angle in a column — the probe habit the
    preposition rig already has (`--refprobe`), pointed at a number instead of a shape. Tuning
    by comparison beats tuning by guessing, and a sweep is one render call."""
    key, _, raw = args.sweep.partition("=")
    if key not in PRESETS[args.preset]:
        raise SystemExit(f"unknown proportion {key!r}; pick from {sorted(PRESETS[args.preset])}")
    values = [float(v) for v in raw.split(",") if v]
    cells = []
    for value in values:
        for view, (az, el) in VIEWS.items():
            clear_scene()
            stage(args.size, az, el, args.ortho, args.target_z)
            _, p = build_figure(args.preset, args.height, override={key: value})
            path = os.path.join(out_dir, f"figur-sweep-{key}-{value:g}-{view}.png")
            render_to(path)
            cells.append(path)
        report(f"{args.preset}[{key}={value:g}]", args.height, p)
    contact_sheet(cells, len(VIEWS), os.path.join(out_dir, f"figur-sweep-{key}.png"))
    print(f"LAYOUT rows={key}=" + ",".join(f"{v:g}" for v in values)
          + " cols=" + ",".join(VIEWS))


def scene_parts(args, out_dir):
    """Each part alone, rendered and exported. Silhouette check plus something to open in
    QuickLook — parts are scratch, only the assembled figure ships."""
    for kind in BUILDERS:
        clear_scene()
        stage(args.size, *VIEWS["dim"], args.ortho, args.target_z)
        build_figure(args.preset, args.height, part=kind)
        render_to(os.path.join(out_dir, f"figur-part-{kind}.png"))
        export_usdz(os.path.join(out_dir, f"figur-part-{kind}.usdz"))
        print(f"PART {kind}")
    cells = [os.path.join(out_dir, f"figur-part-{k}.png") for k in BUILDERS]
    contact_sheet(cells, 2, os.path.join(out_dir, "figur-parts.png"))


def scene_aufbau(args, out_dir):
    """The clip, plus a storyboard to judge it by.

    Built twice on purpose: the storyboard renders at high LOD so faceting can never be
    mistaken for a choreography problem, and the export rebuilds at low LOD because that is
    what ships. Same table, same keyframes — only the mesh density differs.
    """
    global _LOD

    _LOD = "high"
    clear_scene()
    stage(args.size, *VIEWS["dim"], args.ortho, args.target_z)
    objects, p = build_figure(args.preset, args.height)
    keyframe_aufbau(objects, p)
    cells = []
    for frame in range(1, AUFBAU_HOLD + 1, 7):
        bpy.context.scene.frame_set(frame)
        path = os.path.join(out_dir, f"aufbau-f{frame:02d}.png")
        render_to(path)
        cells.append(path)
    contact_sheet(cells, 4, os.path.join(out_dir, "figur-aufbau.png"))

    _LOD = "low"
    clear_scene()
    setup_render(args.size)
    objects, p = build_figure(args.preset, args.height)
    keyframe_aufbau(objects, p)
    out = os.path.normpath(args.out or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..",
        "german-ai-flashcards", "Resources", "figur-aufbau.usdz"))

    # The plain-text twin, written from this same scene before the .usdz so the two cannot
    # disagree. It is the only thing that can prove the clip carries motion — see
    # `usda_animation` for why the round-trip can't.
    twin = os.path.join(out_dir, os.path.splitext(os.path.basename(out))[0] + ".usda")
    bpy.ops.wm.usd_export(filepath=twin, export_materials=True, export_animation=True,
                          convert_orientation=True)
    export_usdz(out, animated=True)
    print(f"AUFBAU export {out}")
    verify_animation(twin)


# MARK: - Der Gang (the walk-cycle clip)
#
# A seamless in-place stride: legs swing about the hip line, arms counter-swing, torso and head
# ride a slight bob (highest at the passing position, like a real gait — and it puts motion on
# all six parts, so `verify_animation`'s all-parts check keeps meaning something). The first
# frame equals the last, so RealityKit's `.repeat()` loops without a hitch.
#
# Translation is deliberately NOT baked. The runtime slides the figure (the prep scenes'
# contract: the app writes positions, never rotations), which keeps one clip reusable at any
# walking speed — and keeps the loop seamless, since an in-place cycle has nothing to rewind.
# The walker must still be yawed ±90° toward its direction of travel (see POSES["geh"]): the
# swing is authored about X, along the hip line.

GEHEN_SWING = 18        # degrees of leg swing, matching POSES["geh"]
GEHEN_ARM_SWING = 11    # arms counter-swing a touch less
GEHEN_BOB = 0.022       # torso/head lift at the passing position, in scene units
GEHEN_CYCLE = 24        # frames at 24 fps — one full stride pair per second


def keyframe_gehen(objects):
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, GEHEN_CYCLE + 1
    scene.render.fps = 24
    quarter = GEHEN_CYCLE // 4

    def key_swing(obj, frame, degrees):
        obj.rotation_mode = "XYZ"
        obj.rotation_euler = (math.radians(degrees), 0, 0)
        obj.keyframe_insert("rotation_euler", frame=frame)

    def key_lift(obj, frame, base, lift):
        obj.location.z = base + lift
        obj.keyframe_insert("location", frame=frame)

    swings = {
        "figur_leg_l": GEHEN_SWING,
        "figur_leg_r": -GEHEN_SWING,
        "figur_arm_l": -GEHEN_ARM_SWING,   # counter-swing: opposite its own side's leg
        "figur_arm_r": GEHEN_ARM_SWING,
    }
    for obj in objects:
        if swing := swings.get(obj.name):
            for step, value in enumerate([swing, 0, -swing, 0, swing]):
                key_swing(obj, 1 + step * quarter, value)
        elif obj.name in ("figur_torso", "figur_head"):
            base = obj.location.z
            for step, lift in enumerate([0, GEHEN_BOB, 0, GEHEN_BOB, 0]):
                key_lift(obj, 1 + step * quarter, base, lift)


def scene_gehen(args, out_dir):
    """The walk-cycle clip, plus a storyboard strip to judge the stride by.

    Same two-build structure as `scene_aufbau`: the storyboard renders at high LOD so faceting
    can never be mistaken for a gait problem; the export rebuilds at low LOD because that is
    what ships. Same keyframes both times.
    """
    global _LOD

    _LOD = "high"
    clear_scene()
    stage(args.size, *VIEWS["dim"], args.ortho, args.target_z)
    objects, p = build_figure(args.preset, args.height)
    keyframe_gehen(objects)
    cells = []
    for frame in range(1, GEHEN_CYCLE + 2, 3):
        bpy.context.scene.frame_set(frame)
        path = os.path.join(out_dir, f"gehen-f{frame:02d}.png")
        render_to(path)
        cells.append(path)
    contact_sheet(cells, 3, os.path.join(out_dir, "figur-gehen.png"))

    _LOD = "low"
    clear_scene()
    setup_render(args.size)
    objects, p = build_figure(args.preset, args.height)
    keyframe_gehen(objects)
    out = os.path.normpath(args.out or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..",
        "german-ai-flashcards", "Resources", "figur-gehen.usdz"))

    # The plain-text twin, written from this same scene before the .usdz so the two cannot
    # disagree — the only thing that can prove the clip carries motion (see `usda_animation`).
    twin = os.path.join(out_dir, os.path.splitext(os.path.basename(out))[0] + ".usda")
    bpy.ops.wm.usd_export(filepath=twin, export_materials=True, export_animation=True,
                          convert_orientation=True)
    export_usdz(out, animated=True)
    print(f"GEHEN export {out}")
    verify_animation(twin)


# MARK: - Gesten (joint-space poses and clips for the verb scenes)
#
# The verb + preposition scenes are mostly feelings (Angst vor, sich freuen auf, leiden unter),
# and die Figur has no face, so its body has to say all of it. POSES above rotates parts in
# place, which holds while the torso stands upright. Once it leans, the arms and head have to
# travel with it, and six flat parts have no hierarchy to do that for them. So a Geste is
# authored in *joint space* and solved to part transforms by forward kinematics (`solve`): the
# torso carries the arms and head, the root carries everything. The parts stay flat and
# unparented, so the contracts above (names, joint origins, the runtime's piece walk) hold.
#
# Joint table. Angles are degrees, offsets from rest. The figure faces +Y; its right is +X.
#   root   (x, y, z)  whole-body shift, in fractions of the figure's height
#   turn   (x, y, z)  whole-body rotation about the feet (lying down, turning to show off)
#   torso  (x, y, z)  about the hip line, carrying arms + head: +x leans BACK, -x forward;
#                     +y leans to its right; +z twists its front toward its left (-X)
#   head   (x, y, z)  about the neck: +x looks up, -x down; +y tilts to its right
#   arm_*  (x, y, z)  about the shoulder: +x raises it forward, then y raises it sideways
#                     (arm_r -y, arm_l +y), then z swings it across (inward: arm_r +z, arm_l -z)
#   leg_*  (x, y, z)  about the hip: +x swings it forward, then y splays it (leg_r -y, leg_l +y)
#
# Two things the table can't show:
#   - The head is a sphere, so *turning* it is invisible. Only nods and tilts read. Looking
#     somewhere is a torso twist or a whole-body turn.
#   - A lean swings the arms with the torso. An arm that should point ahead of a stooped figure
#     needs the lean added to its own x.

GESTEN = {
    # Angst haben vor / sich fürchten vor: flinched back from something in front, hands up.
    "schreck": {"root": (0, -0.04, 0), "torso": (14, 0, 0), "head": (6, 0, 0),
                "arm_l": (112, 0, -24), "arm_r": (112, 0, 24),
                "leg_l": (10, 0, 0), "leg_r": (-8, 0, 0)},
    "schreck_weit": {"base": "schreck", "root": (0, -0.08, 0), "torso": (20, 0, 0),
                     "arm_l": (128, 0, -24), "arm_r": (128, 0, 24)},
    # sich ekeln vor: turned away, one arm out to fend it off.
    "ekel": {"turn": (0, 0, 22), "torso": (10, 0, 28), "head": (-4, -14, 0),
             "arm_r": (85, 0, -50), "arm_l": (-12, 8, 0), "leg_l": (6, 0, 0), "leg_r": (-6, 0, 0)},
    "ekel_weg": {"base": "ekel", "turn": (0, 0, 30), "torso": (14, 0, 34), "head": (-6, -20, 0),
                 "arm_r": (92, 0, -62)},
    # sich freuen über: arms up, chin up.
    "jubel": {"torso": (6, 0, 0), "head": (14, 0, 0), "arm_l": (10, 150, 0), "arm_r": (10, -150, 0)},
    "jubel_hocke": {"root": (0, 0, -0.02), "torso": (-10, 0, 0), "head": (-4, 0, 0),
                    "arm_l": (20, 118, 0), "arm_r": (20, -118, 0)},
    "jubel_sprung": {"root": (0, 0, 0.09), "torso": (8, 0, 0), "head": (16, 0, 0),
                     "arm_l": (10, 165, 0), "arm_r": (10, -165, 0),
                     "leg_l": (-8, 5, 0), "leg_r": (-8, -5, 0)},
    # sich freuen auf / hoffen auf: anticipation. Hands together at the chest, bouncing.
    "vorfreude": {"torso": (-4, 0, 0), "head": (8, 0, 0), "arm_l": (70, 0, -38), "arm_r": (70, 0, 38)},
    "vorfreude_hoch": {"base": "vorfreude", "root": (0, 0, 0.03), "head": (12, 0, 0)},
    # leiden unter / sich sorgen um: slumped, head hung.
    "kummer": {"root": (0, 0, -0.012), "torso": (-16, 0, 0), "head": (-32, 0, 0),
               "arm_l": (20, -4, 0), "arm_r": (20, 4, 0)},
    "kummer_tief": {"base": "kummer", "root": (0, 0, -0.018), "torso": (-21, 0, 0),
                    "head": (-38, 0, 0), "arm_l": (25, -4, 0), "arm_r": (25, 4, 0)},
    # arbeiten an: the hammer raised, the other hand steadying the work.
    # Cocked back behind the head: straight up, the near arm lands on top of the head in profile.
    "hammer": {"torso": (-8, 0, 0), "head": (-20, 0, 0), "arm_r": (222, 0, 6),
               "arm_l": (58, 0, -16), "leg_l": (10, 0, 0), "leg_r": (-8, 0, 0)},
    "hammer_schlag": {"base": "hammer", "torso": (-24, 0, 0), "head": (-28, 0, 0),
                      "arm_r": (112, 0, 8)},
    # helfen bei: both hands forward under a load.
    "heben": {"torso": (5, 0, 0), "head": (-6, 0, 0), "arm_l": (80, 0, -12), "arm_r": (80, 0, 12)},
    "heben_hoch": {"base": "heben", "root": (0, 0, 0.015), "torso": (8, 0, 0),
                   "arm_l": (95, 0, -12), "arm_r": (95, 0, 12)},
    # sich kümmern um: stooped over something small, one hand patting it.
    "pflegen": {"torso": (-30, 0, 0), "head": (-18, 0, 0), "arm_r": (78, 0, 8),
                "arm_l": (40, 0, -6), "leg_l": (8, 0, 0), "leg_r": (-10, 0, 0)},
    "pflegen_klaps": {"base": "pflegen", "arm_r": (64, 0, 8)},
    # aufpassen auf: hands behind the back, watching something move about.
    "wache": {"torso": (-4, 0, 0), "head": (-8, 0, 0), "arm_l": (-32, 0, 22), "arm_r": (-32, 0, -22)},
    "wache_links": {"base": "wache", "turn": (0, 0, 14), "torso": (-4, 0, 12)},
    "wache_rechts": {"base": "wache", "turn": (0, 0, -14), "torso": (-4, 0, -12)},
    # warten auf: peering down the road, a hand shading the eyes, up on its toes; between looks,
    # weight back on its heels and a foot tapping. The first pass keyed a plain stance and a
    # glance at the wrist, and without an elbow the glance read as pointing.
    "ausschau": {"root": (0, 0.01, 0.02), "torso": (-12, 0, 0), "head": (10, 0, 0),
                 "arm_r": (152, 0, 40), "arm_l": (-8, 6, 0), "leg_r": (-6, 0, 0)},
    "warten": {"torso": (3, 3, 0), "head": (-4, 4, 0), "arm_l": (-14, 10, 0), "arm_r": (-14, -10, 0),
               "leg_r": (0, -5, 0)},
    "warten_tipp": {"base": "warten", "leg_r": (20, -5, 0)},
    # sich vorbereiten auf: side stretches before the start.
    "dehnen_l": {"torso": (0, -18, 0), "head": (0, -10, 0), "arm_r": (0, -160, 0), "arm_l": (0, 14, 0)},
    "dehnen_r": {"torso": (0, 18, 0), "head": (0, 10, 0), "arm_l": (0, 160, 0), "arm_r": (0, -14, 0)},
    "dehnen_mitte": {"root": (0, 0, 0.01), "head": (8, 0, 0), "arm_l": (0, 165, 0), "arm_r": (0, -165, 0)},
    # antworten auf: winding up to throw it back, and the throw. Overhand and in profile: the
    # throwing arm cocked up behind the head, the other one aimed at the target. (A twisting
    # wind-up turned the chest to the camera and read as "ta-da".)
    "werfen_aus": {"torso": (14, 0, -6), "head": (8, 0, 0), "arm_r": (-152, -8, 0),
                   "arm_l": (82, 0, -6), "leg_l": (18, 0, 0), "leg_r": (-14, 0, 0)},
    "werfen": {"torso": (-16, 0, 6), "head": (-2, 0, 0), "arm_r": (96, 0, 8),
               "arm_l": (-24, 8, 0), "leg_l": (18, 0, 0), "leg_r": (-16, 0, 0)},
    # sprechen über / reden über / sprechen mit / erzählen von: conversational hands.
    "reden": {"torso": (-4, 0, 0), "head": (4, 6, 0), "arm_r": (78, -34, 0), "arm_l": (30, 10, 0)},
    "reden_b": {"torso": (-9, 0, -4), "head": (-10, -2, 0), "arm_r": (52, -16, 10), "arm_l": (46, 16, 0)},
    "reden_c": {"base": "reden", "torso": (-2, 0, 0), "head": (6, -6, 0), "arm_r": (98, -40, 0),
                "arm_l": (58, 0, -16)},
    # nachdenken über / denken an / sich erinnern an: hand to chin, head tilted. No elbow, so
    # the straight arm is aimed to end just in front of the chin rather than bent to it.
    "gruebeln": {"torso": (-4, 0, 0), "head": (-6, 14, 0), "arm_r": (128, 0, 66), "arm_l": (45, 0, -55)},
    "gruebeln_b": {"base": "gruebeln", "torso": (-6, 0, 0), "head": (-6, -8, 0)},
    # sich ärgern über / sich beschweren über: stamping, fists down.
    "stampfen_r": {"torso": (-8, 0, 0), "head": (-12, 0, 0), "arm_l": (-14, 22, 0),
                   "arm_r": (-14, -22, 0), "leg_r": (30, 0, 0)},
    "stampfen_l": {"base": "stampfen_r", "leg_r": (0, 0, 0), "leg_l": (30, 0, 0)},
    "stampfen": {"root": (0, 0, -0.008), "torso": (-12, 0, 0), "head": (-16, 0, 0),
                 "arm_l": (-10, 26, 0), "arm_r": (-10, -26, 0)},
    # schimpfen mit / sich streiten über: the wagging finger.
    "schimpfen": {"torso": (-10, 0, 0), "head": (-8, 0, 0), "arm_r": (128, 0, 14), "arm_l": (8, 32, 0)},
    # The wag pumps up and down rather than side to side: sideways would point into the lens in
    # profile, which is how this clip is staged.
    "schimpfen_l": {"base": "schimpfen", "torso": (-13, 0, 0), "arm_r": (152, 0, 14)},
    "schimpfen_r": {"base": "schimpfen", "torso": (-8, 0, 0), "arm_r": (102, 0, 14)},
    # sich wundern über / zweifeln an: the shrug.
    "staunen": {"root": (0, 0, 0.008), "torso": (4, 0, 0), "head": (0, 16, 0),
                "arm_l": (30, 42, 0), "arm_r": (30, -42, 0)},
    "staunen_hoch": {"base": "staunen", "root": (0, 0, 0.02), "head": (2, 22, 0),
                     "arm_l": (34, 55, 0), "arm_r": (34, -55, 0)},
    # bitten um / fragen nach: a hand held out.
    "bitten": {"torso": (-10, 0, 0), "head": (-8, 0, 0), "arm_r": (88, 0, 6), "arm_l": (14, 0, 0)},
    "bitten_vor": {"base": "bitten", "root": (0, 0.02, 0), "torso": (-15, 0, 0), "arm_r": (100, 0, 6)},
    # sich sehnen nach / verlangen nach: both arms after something far off, up on its toes.
    "sehnen": {"root": (0, 0, 0.015), "torso": (-8, 0, 0), "head": (14, 0, 0),
               "arm_l": (118, 0, -8), "arm_r": (118, 0, 8)},
    "sehnen_weit": {"base": "sehnen", "root": (0, 0.02, 0.03), "torso": (-13, 0, 0),
                    "arm_l": (128, 0, -8), "arm_r": (128, 0, 8)},
    # angeben mit: the trophy held high, chest out, turning to show it off.
    "stolz": {"torso": (8, 0, 0), "head": (16, 0, 0), "arm_r": (14, -168, 0), "arm_l": (12, 34, 0)},
    "stolz_l": {"base": "stolz", "turn": (0, 0, 26)},
    "stolz_r": {"base": "stolz", "turn": (0, 0, -26)},
    # träumen von: lying on its back, head toward -X so it reads along the frame. The root
    # shift centres the body over the feet's old spot, and the lift rests the head on the
    # ground (its radius is 0.13 of the height).
    "schlafen": {"turn": (90, 0, -90), "root": (0.5, 0, 0.13), "arm_l": (0, 6, 0), "arm_r": (0, -6, 0)},
    "schlafen_atem": {"base": "schlafen", "torso": (-3, 0, 0)},
    # erzählen von / handeln von: a book held open at the chest, head bent to it.
    "lesen": {"torso": (-4, 0, 0), "head": (-26, 0, 0), "arm_l": (62, 0, -30), "arm_r": (62, 0, 30)},
    "lesen_blatt": {"base": "lesen", "arm_r": (70, 0, 58)},
    # sich interessieren für: leaning in close, one hand forward (a magnifier), one behind.
    "neugier": {"root": (0, 0.02, 0), "torso": (-24, 0, 0), "head": (-10, 0, 0),
                "arm_r": (100, 0, 12), "arm_l": (-6, 10, 0), "leg_l": (10, 0, 0), "leg_r": (-12, 0, 0)},
    "neugier_nah": {"base": "neugier", "root": (0, 0.04, 0), "torso": (-32, 0, 0),
                    "head": (-14, 0, 0), "arm_r": (108, 0, 12)},

    # Added for the verb scenes themselves (2026-10-02).
    # Seated, as POSES["sitz"] but in joint space so a clip can work from it: the hips drop most
    # of a leg length and the legs stick straight out. A scene raises the figure onto its stool.
    "sitzen": {"root": (0, 0, -0.312), "leg_l": (82, 0, 0), "leg_r": (82, 0, 0)},
    # schreiben an / antworten auf: bent over a desk, the near hand writing.
    "schreiben": {"base": "sitzen", "torso": (-14, 0, 0), "head": (-26, 0, 0),
                  "arm_r": (80, 0, 16), "arm_l": (66, 0, -24)},
    "schreiben_zug": {"base": "schreiben", "arm_r": (74, 0, 30)},
    "schreiben_auf": {"base": "schreiben", "torso": (-8, 0, 0), "head": (-8, 0, 0)},
    # sich ernähren von: reaching up into the tree, then the apple to the mouth.
    "pfluecken": {"root": (0, 0, 0.02), "torso": (2, 0, 0), "head": (16, 0, 0),
                  "arm_r": (140, 0, 8), "arm_l": (10, 0, 0)},
    "beissen": {"torso": (-4, 0, 0), "head": (-6, 0, 0), "arm_r": (128, 0, 66), "arm_l": (0, 0, 0)},
    # hoffen auf: hands together at the chest, looking up.
    "hoffen": {"torso": (4, 0, 0), "head": (22, 0, 0), "arm_l": (72, 0, -38), "arm_r": (72, 0, 38)},
    "hoffen_hoch": {"base": "hoffen", "root": (0, 0, 0.012), "head": (26, 6, 0)},
    # sich gewöhnen an: a flinch that relaxes. Half the schreck, then loose arms.
    "schreck_halb": {"base": "schreck", "root": (0, -0.02, 0), "torso": (7, 0, 0), "head": (3, 0, 0),
                     "arm_l": (72, 0, -24), "arm_r": (72, 0, 24), "leg_l": (5, 0, 0), "leg_r": (-4, 0, 0)},
    "locker": {"head": (2, 0, 0), "arm_l": (6, 4, 0), "arm_r": (6, -4, 0)},
    # zweifeln an: hand at the chin like gruebeln, but leaning back from the thing, not into it.
    "zweifeln": {"root": (0, -0.02, 0), "torso": (8, 0, 0), "head": (-4, 12, 0),
                 "arm_r": (128, 0, 66), "arm_l": (40, 0, -50)},
    "zweifeln_b": {"base": "zweifeln", "torso": (10, 0, 0), "head": (-4, -10, 0)},
    # angeben mit: chest out, chin up, the near arm presenting the thing.
    "angeben": {"torso": (9, 0, 0), "head": (16, 0, 0), "arm_r": (78, -28, 0), "arm_l": (12, 34, 0)},
    "angeben_dreh": {"base": "angeben", "turn": (0, 0, 20), "head": (20, 0, 0)},
    # Pointing behind itself, for a figure facing the camera that shows the way (fragen nach).
    "weisen": {"head": (0, -8, 0), "arm_l": (0, 100, 0)},
}

# A clip is a list of beats: (frame, pose[, ease]). A pose is a GESTEN name, "steh", or a dict
# that may extend a name through "base". The ease shapes the segment *arriving* at that beat.
#
# Staging, because a figure with no face only reads from the right side:
#   - `view` says how the clip reads. Forward gestures (a reach, a stoop) read only in profile;
#     sideways ones (arms up in a V, a shrug, a side stretch) only from the front. Profile is
#     the default; see STAGING_YAW for the yaws.
#   - One-armed gestures use arm_r. Facing screen-right, that is the arm nearer the camera.
#     A figure facing screen-left plays the clip with `mirror`, which swaps sides, so the
#     active arm is still the near one.
#
# Frame 0 is the key pose and every clip ends where it began, for two reasons the app imposes:
# clips only play on the reveal (`playsClips`), so frame 0 is what the question side holds and
# what a still shows; and the runtime plays every clip on `.repeat()`, so a clip that ended
# anywhere else would snap at the seam.
CLIPS = {
    "schreck": {"verbs": "Angst haben vor · sich fürchten vor", "beats": [
        (0, "schreck"), (4, {"base": "schreck", "torso": (15, 2.5, 0)}),
        (8, {"base": "schreck", "torso": (15, -2.5, 0)}), (12, {"base": "schreck", "torso": (15, 2.5, 0)}),
        (16, "schreck"), (26, "schreck_weit", "out"), (40, "schreck_weit"), (56, "schreck")]},
    "ekel": {"verbs": "sich ekeln vor", "beats": [
        (0, "ekel"), (14, "ekel_weg", "out"), (34, "ekel_weg"), (52, "ekel")]},
    "kummer": {"verbs": "leiden unter · sich sorgen um", "beats": [
        (0, "kummer"), (36, "kummer_tief"), (72, "kummer")]},
    "hammer": {"verbs": "arbeiten an", "beats": [
        (0, "hammer"), (6, "hammer_schlag", "in"),
        (9, {"base": "hammer_schlag", "arm_r": (124, 0, 8)}, "out"), (12, "hammer_schlag"), (24, "hammer")]},
    "heben": {"verbs": "helfen bei", "beats": [(0, "heben"), (24, "heben_hoch"), (48, "heben")]},
    "pflegen": {"verbs": "sich kümmern um", "beats": [
        (0, "pflegen"), (7, "pflegen_klaps"), (14, "pflegen"), (21, "pflegen_klaps"),
        (28, "pflegen"), (56, "pflegen")]},
    "wache": {"verbs": "aufpassen auf", "beats": [
        (0, "wache"), (30, "wache_links"), (54, "wache_links"), (84, "wache_rechts"),
        (108, "wache_rechts"), (132, "wache")]},
    "warten": {"verbs": "warten auf", "beats": [
        (0, "ausschau"), (24, "ausschau"), (36, "warten"), (41, "warten_tipp", "out"),
        (46, "warten", "in"), (51, "warten_tipp", "out"), (56, "warten", "in"),
        (61, "warten_tipp", "out"), (66, "warten", "in"), (80, "ausschau")]},
    "vorfreude": {"verbs": "sich freuen auf · hoffen auf", "beats": [
        (0, "vorfreude"), (5, "vorfreude_hoch", "out"), (10, "vorfreude", "in"),
        (15, "vorfreude_hoch", "out"), (20, "vorfreude", "in"), (40, "vorfreude")]},
    "jubel": {"view": "front", "verbs": "sich freuen über", "beats": [
        (0, "jubel"), (5, "jubel_hocke"), (11, "jubel_sprung", "out"), (17, "jubel", "in"),
        (22, "jubel_hocke"), (28, "jubel_sprung", "out"), (34, "jubel", "in"), (52, "jubel")]},
    "dehnen": {"view": "front", "verbs": "sich vorbereiten auf", "beats": [
        (0, "dehnen_l"), (22, "dehnen_l"), (40, "dehnen_mitte"), (58, "dehnen_r"),
        (80, "dehnen_r"), (98, "dehnen_mitte"), (116, "dehnen_l")]},
    "werfen": {"verbs": "antworten auf", "beats": [
        (0, "werfen_aus"), (8, "werfen_aus"), (13, "werfen", "out"), (28, "werfen"), (44, "werfen_aus")]},
    "reden": {"verbs": "sprechen über · reden über · sprechen mit · erzählen von", "beats": [
        (0, "reden"), (14, "reden_b"), (28, "reden"), (40, "reden_c"), (56, "reden")]},
    "gruebeln": {"verbs": "nachdenken über · denken an · sich erinnern an", "beats": [
        (0, "gruebeln"), (40, "gruebeln_b"), (80, "gruebeln")]},
    "stampfen": {"verbs": "sich ärgern über · sich beschweren über", "beats": [
        (0, "stampfen_r"), (5, "stampfen", "in"), (12, "stampfen"), (18, "stampfen_l"),
        (23, "stampfen", "in"), (30, "stampfen"), (36, "stampfen_r")]},
    "schimpfen": {"verbs": "schimpfen mit · sich streiten über", "beats": [
        (0, "schimpfen"), (4, "schimpfen_l"), (8, "schimpfen_r"), (12, "schimpfen_l"),
        (16, "schimpfen_r"), (20, "schimpfen"), (40, "schimpfen")]},
    "staunen": {"view": "front", "verbs": "sich wundern über · zweifeln an", "beats": [
        (0, "staunen"), (10, "staunen_hoch", "out"), (24, "staunen_hoch"), (36, "staunen"), (56, "staunen")]},
    "bitten": {"verbs": "bitten um · fragen nach", "beats": [
        (0, "bitten"), (16, "bitten_vor"), (30, "bitten_vor"), (48, "bitten")]},
    "sehnen": {"verbs": "sich sehnen nach · verlangen nach", "beats": [
        (0, "sehnen"), (36, "sehnen_weit"), (72, "sehnen")]},
    "stolz": {"view": "front", "verbs": "angeben mit", "beats": [
        (0, "stolz"), (30, "stolz_l"), (48, "stolz_l"), (84, "stolz_r"), (102, "stolz_r"), (132, "stolz")]},
    "schlafen": {"view": "front", "verbs": "träumen von", "beats": [
        (0, "schlafen"), (40, "schlafen_atem"), (80, "schlafen")]},
    "lesen": {"verbs": "erzählen von · handeln von · sich vorbereiten auf", "beats": [
        (0, "lesen"), (30, "lesen"), (40, "lesen_blatt"), (50, "lesen"), (80, "lesen")]},
    "neugier": {"verbs": "sich interessieren für", "beats": [
        (0, "neugier"), (36, "neugier_nah"), (72, "neugier")]},
    "schreiben": {"verbs": "schreiben an · antworten auf", "beats": [
        (0, "schreiben"), (6, "schreiben_zug"), (12, "schreiben"), (18, "schreiben_zug"),
        (24, "schreiben"), (30, "schreiben_zug"), (36, "schreiben"), (50, "schreiben_auf"),
        (62, "schreiben_auf"), (72, "schreiben")]},
    "essen": {"verbs": "sich ernähren von", "beats": [
        (0, "pfluecken"), (18, "pfluecken"), (34, "beissen"), (44, {"base": "beissen", "head": (-10, 0, 0)}),
        (54, "beissen"), (72, "pfluecken")]},
    "hoffen": {"verbs": "hoffen auf", "beats": [(0, "hoffen"), (30, "hoffen_hoch"), (60, "hoffen")]},
    "gewoehnen": {"verbs": "sich gewöhnen an", "beats": [
        (0, "schreck_halb"), (20, "locker"), (50, "locker"), (64, "schreck_halb")]},
    "zweifeln": {"verbs": "zweifeln an", "beats": [
        (0, "zweifeln"), (20, "zweifeln_b"), (40, "zweifeln"), (60, "zweifeln_b"), (80, "zweifeln")]},
    "angeben": {"verbs": "angeben mit", "beats": [
        (0, "angeben"), (24, "angeben_dreh"), (48, "angeben"),
        (72, {"base": "angeben", "root": (0, 0, 0.01), "head": (20, 0, 0)}), (96, "angeben")]},
}

JOINT_KEYS = ("root", "turn", "torso", "head", "arm_l", "arm_r", "leg_l", "leg_r")

EASES = {
    "smooth": lambda t: t * t * t * (t * (6 * t - 15) + 10),   # smootherstep: settles at both ends
    "out": lambda t: 1 - (1 - t) ** 3,                          # fast start, soft landing (a flinch)
    "in": lambda t: t ** 3,                                     # slow start, hard arrival (a strike)
    "linear": lambda t: t,
}


def resolve(spec):
    """A Geste as a joint dict: by name, "steh" for rest, or a dict extending a name via "base"."""
    if isinstance(spec, str):
        return {} if spec == "steh" else resolve(GESTEN[spec])
    out = resolve(spec["base"]) if "base" in spec else {}
    out.update({k: v for k, v in spec.items() if k != "base"})
    return out


SIDES = {"arm_l": "arm_r", "arm_r": "arm_l", "leg_l": "leg_r", "leg_r": "leg_l"}


def mirrored(joints):
    """The same gesture across the figure's own centre plane (x → -x).

    Conjugating an XYZ rotation by that reflection keeps its x angle and negates y and z, and a
    translation loses its x; the left and right limbs trade places.
    """
    out = {}
    for key, (x, y, z) in joints.items():
        if key == "root":
            out[key] = (-x, y, z)
        else:
            out[SIDES.get(key, key)] = (x, -y, -z)
    return out


def figure_height(p):
    return p["leg_len"] + p["torso_h"] + p["neck"] + 2 * p["head_r"]


def rest_of(objects):
    """Joint positions by role. Origins sit at joints, so at rest a part's location *is* one."""
    return {part_role(o): o.location.copy() for o in objects}


def _rotation(degrees):
    return Euler([math.radians(a) for a in degrees], "XYZ").to_matrix().to_4x4()


def solve(rest, height, joints):
    """Forward kinematics: a joint dict → a figure-local matrix per part role.

    The torso pivots at the hip line and carries the shoulders and the neck with it; the legs
    hang from the root. Figure-local means relative to the feet at the origin, which is also
    what a part's transform is relative to inside a prep scene's `figur` group.
    """
    zero = (0.0, 0.0, 0.0)
    root = (Matrix.Translation(Vector(joints.get("root", zero)) * height)
            @ _rotation(joints.get("turn", zero)))
    hip = rest["torso"]
    torso = root @ Matrix.Translation(hip) @ _rotation(joints.get("torso", zero))
    out = {"torso": torso}
    for role in ("head", "arm_l", "arm_r"):
        out[role] = (torso @ Matrix.Translation(rest[role] - hip)
                     @ _rotation(joints.get(role, zero)))
    for role in ("leg_l", "leg_r"):
        out[role] = root @ Matrix.Translation(rest[role]) @ _rotation(joints.get(role, zero))
    return out


def _put(obj, matrix):
    obj.rotation_mode = "XYZ"
    obj.location = matrix.to_translation()
    # Compatible with the previous value, so per-frame keys never flip through ±180°.
    obj.rotation_euler = matrix.to_euler("XYZ", obj.rotation_euler)


def grip(p, role):
    """Where a held prop sits, in the frame of the arm it hangs from: at the cone's tip, +Z
    continuing the arm and +Y the figure's forward. A held prop is authored around that grip,
    so a hammer's handle simply runs on along +Z and its head sits at the far end."""
    side = 1 if role.endswith("_r") else -1
    tilt = math.radians(p["arm_tilt"])
    z = Vector((side * math.sin(tilt), 0, -math.cos(tilt)))
    x = Vector((0, 1, 0)).cross(z).normalized()
    y = z.cross(x)
    frame = Matrix((x, y, z)).transposed().to_4x4()
    frame.translation = z * p["arm_len"]
    return frame


def _held_matrices(solved, p, held, mirror):
    """(object, matrix) for each held prop. A mirrored figure holds it in the other hand."""
    out = []
    for obj, role in held or []:
        role = SIDES.get(role, role) if mirror else role
        out.append((obj, solved[role] @ grip(p, role) if role.startswith("arm") else solved[role]))
    return out


def pose_gesture(objects, p, joints, rest=None, mirror=False, held=None):
    solved = solve(rest or rest_of(objects), figure_height(p), mirrored(joints) if mirror else joints)
    for obj in objects:
        _put(obj, solved[part_role(obj)])
    for obj, matrix in _held_matrices(solved, p, held, mirror):
        _put(obj, matrix)
    return objects


def rest_joints(p):
    """The joint positions build_figure would produce, without building it: for placing things
    against a figure's hand before the scene exists (a ball held out, a letter in reach)."""
    return {
        "torso": Vector((0, 0, p["leg_len"])),
        "head": Vector((0, 0, p["leg_len"] + p["torso_h"] + p["neck"])),
        "leg_l": Vector((-p["leg_gap"] / 2, 0, p["leg_len"])),
        "leg_r": Vector((p["leg_gap"] / 2, 0, p["leg_len"])),
        **{f"arm_{s}": Vector((sign * (p["torso_w"] / 2 + p["arm_r"] * 0.35), 0,
                               p["leg_len"] + p["torso_h"] - p["arm_r"]))
           for s, sign in (("l", -1), ("r", 1))},
    }


def hand_position(at, yaw, pose, role="arm_r", mirror=False, preset="standard", height=1.8):
    """World position of a hand for a figure standing at `at`, turned by `yaw`, in a GESTEN
    pose. Analytic, so a scene can place a held ball before anything is built."""
    p = scaled(preset, height)
    joints = resolve(pose)
    solved = solve(rest_joints(p), height, mirrored(joints) if mirror else joints)
    role = SIDES.get(role, role) if mirror else role
    hand = (solved[role] @ grip(p, role)).translation
    return Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ hand


def clip_length(name):
    return CLIPS[name]["beats"][-1][0]


def sample_clip(name, frame):
    """The joint dict at a clip frame: beats interpolated in joint space, eased per segment."""
    beats = CLIPS[name]["beats"]
    for (f0, s0, *_), (f1, s1, *ease) in zip(beats, beats[1:]):
        if f0 <= frame <= f1:
            t = EASES[ease[0] if ease else "smooth"]((frame - f0) / (f1 - f0))
            a, b = resolve(s0), resolve(s1)
            return {key: tuple(Vector(a.get(key, (0, 0, 0))).lerp(Vector(b.get(key, (0, 0, 0))), t))
                    for key in JOINT_KEYS}
    return resolve(beats[-1][1])


def keyframe_clip(objects, p, name, mirror=False, held=None, period=None):
    """Bake a clip as per-frame keys on every part, and leave the figure on its key pose.

    Every frame, not just the beats: the arms and head ride the torso through FK, and letting
    Blender interpolate their *solved* transforms between beats would let a hand drift off its
    shoulder mid-move. USD writes a TimeSample per frame anyway, so dense keys cost the file
    nothing. Clip frame f lands on scene frame f + 1, because Blender counts from 1.

    `held` is [(object, role)]: a prop that rides a hand (see `grip`). `period` stretches the
    clip to that many frames, so every clip and motion in one scene loops on the same beat.

    Returns the last scene frame, so a caller can size the scene range.
    """
    beats = CLIPS[name]["beats"]
    if resolve(beats[0][1]) != resolve(beats[-1][1]):
        print(f"  ⚠ clip {name} ends on a different pose than it starts; .repeat() will snap")
    rest = rest_of(objects)
    height = figure_height(p)
    length = clip_length(name)
    last = period or length
    for frame in range(last + 1):
        joints = sample_clip(name, frame * length / last)
        solved = solve(rest, height, mirrored(joints) if mirror else joints)
        placed = [(obj, solved[part_role(obj)]) for obj in objects]
        for obj, matrix in placed + _held_matrices(solved, p, held, mirror):
            _put(obj, matrix)
            obj.keyframe_insert("location", frame=frame + 1)
            obj.keyframe_insert("rotation_euler", frame=frame + 1)
    for obj in objects + [obj for obj, _ in held or []]:
        for curve in fcurves_of(obj.animation_data.action):
            for point in curve.keyframe_points:
                point.interpolation = "LINEAR"
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = max(scene.frame_end if scene.get("clip_end") else 1, last + 1)
    scene["clip_end"] = scene.frame_end
    scene.frame_set(1)
    return last + 1


def add_label(text, size=0.05):
    """A caption in the bottom-left of the frame, for judging sheets only (never exported).

    Pinned to the camera rather than placed in the world, so it lands in the same spot
    whatever the framing. Emission, so the scene lights can't grey it out.
    """
    # A camera built with bpy.data.objects.new has no evaluated matrix until the view layer
    # updates; without this the label is placed against identity and lands off-frame.
    bpy.context.view_layer.update()
    cam = bpy.context.scene.camera
    half = cam.data.ortho_scale / 2
    m = cam.matrix_world
    right, up, back = (m.col[i].to_3d().normalized() for i in range(3))
    bpy.ops.object.text_add()
    label = bpy.context.active_object
    label.data.body = text
    label.data.size = cam.data.ortho_scale * size
    # Lines run downward from the anchor, so a multi-line label starts higher.
    lift = (text.count("\n")) * label.data.size * 1.2
    label.location = (cam.location - back * 1.0 - right * half * 0.92 - up * (half * 0.92 - lift))
    label.rotation_euler = cam.rotation_euler
    mat = bpy.data.materials.new("label")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = rgba(REFERENCE)
    out = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(emit.outputs[0], out.inputs["Surface"])
    label.data.materials.append(mat)
    return label


# Yaws that stage the figure squarely for the dim camera (azimuth 21°, so screen-right is
# (0.934, 0.358)). The figure's front is +Y; these turn it onto screen-right, screen-left and
# the camera. Reaches only read in profile: at -120 (three-quarter) and even -100 a forward arm
# points mostly into the lens and lands across the torso, which is what the first two passes
# showed. prep_render.py's scenes use the same numbers.
STAGING_YAW = {"profil": -69.0, "profil_links": 111.0, "front": -159.0}


def storyboard_frames(name, limit=7):
    """The beat frames, thinned evenly to `limit` (a tremble has more beats than it has looks)."""
    frames = sorted({beat[0] for beat in CLIPS[name]["beats"]})[:-1]   # the last repeats frame 0
    if len(frames) <= limit:
        return frames
    step = (len(frames) - 1) / (limit - 1)
    return sorted({frames[round(i * step)] for i in range(limit)})


def scene_gesten(args, out_dir):
    """Per clip: a labelled storyboard of its beats, and a looping USDZ (+ .usda twin) to open
    in Quick Look, which plays baked clips. Then one catalog of every key pose.

    Same two-build structure as `scene_aufbau`. Nothing here ships: the clips reach the app
    inside a scene's export (prep_render.py's `figur` kind takes a `clip`), not as files.
    """
    global _LOD
    names = list(CLIPS) if args.geste == "all" else args.geste.split(",")
    gesten_dir = os.path.join(out_dir, "gesten")
    os.makedirs(gesten_dir, exist_ok=True)
    catalog = []
    for name in names:
        _LOD = "high"
        clear_scene()
        # Wider and taller than the rest-pose framing: arms go overhead and the jubel clip leaves
        # the ground, and none of it may clip at the frame edge.
        stage(args.size, *VIEWS["dim"], 3.3, 1.0)
        if args.fast:
            bpy.context.scene.eevee.taa_render_samples = 48
        objects, p = build_figure(args.preset, args.height)
        keyframe_clip(objects, p, name)
        # The figure faces +Y, away from this camera, so unturned its gestures happen behind its
        # own torso. A parent empty carries the yaw (see STAGING_YAW), the same arrangement
        # as a prep scene's `figur` group, so the baked part keys are untouched.
        bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
        group = bpy.context.active_object
        for obj in objects:
            obj.parent = group
        group.rotation_euler = (0, 0, math.radians(STAGING_YAW[CLIPS[name].get("view", "profil")]))
        label = add_label(name)
        cells = []
        for frame in storyboard_frames(name):
            bpy.context.scene.frame_set(frame + 1)
            label.data.body = name if frame == 0 else f"{name} · {frame}"
            path = os.path.join(gesten_dir, f"{name}-f{frame:03d}.png")
            render_to(path)
            cells.append(path)
        catalog.append(cells[0])
        contact_sheet(cells, len(cells), os.path.join(gesten_dir, f"geste-{name}.png"))

        _LOD = "low"
        clear_scene()
        setup_render(args.size)
        objects, p = build_figure(args.preset, args.height)
        keyframe_clip(objects, p, name)
        out = os.path.join(gesten_dir, f"geste-{name}.usdz")
        twin = os.path.splitext(out)[0] + ".usda"
        bpy.ops.wm.usd_export(filepath=twin, export_materials=True, export_animation=True,
                              convert_orientation=True)
        export_usdz(out, animated=True)
        print(f"GESTE {name} {clip_length(name) + 1} frames ({(clip_length(name) + 1) / 24:.1f}s) "
              f"— {CLIPS[name]['verbs']}")
        verify_animation(twin)
    if len(names) > 1:
        contact_sheet(catalog, 6, os.path.join(out_dir, "gesten-katalog.png"))
        print("LAYOUT katalog=" + ",".join(names))


def scene_scale(args, out_dir):
    """The figure standing with the cast it will join: the dog at its shipped 1.4 and the
    table at its shipped 2.5×1.5×1.25. Scale is a relationship, not a number — the question
    this render answers is whether a 1.8 figure belongs in a scene sized for those two.

    A lineup on one ground line at one depth, wider than the scene framing so nothing clips:
    three things to compare, nothing overlapping, no foreshortening to argue about (the camera
    is orthographic, so on-screen height is exactly proportional to real height).
    """
    clear_scene()
    stage(args.size, *VIEWS["dim"], ortho=7.2, target_z=0.6)
    mat = make_material("figur", REFERENCE)
    build_figure(args.preset, args.height, mat=mat)
    for obj in bpy.context.scene.objects:
        if obj.name.startswith("figur_"):
            obj.location.x -= 2.3
    import_prop("hund", 1.4, (-0.2, 0, 0.0), mat)
    build_table(mat, at=(2.0, 0, 0.0))
    print(f"SCALE figur({args.height}) hund(1.4) tisch(1.25) @ortho 7.2")
    render_to(os.path.join(out_dir, f"figur-scale-{args.height:g}.png"))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    default_out = os.path.join(root, "tools", "blender", "renders", "figur")

    ap = argparse.ArgumentParser()
    ap.add_argument("--preset", default="standard", choices=sorted(PRESETS))
    ap.add_argument("--height", type=float, default=1.8, help="total height in scene units")
    ap.add_argument("--part", default="all", choices=["all"] + sorted(BUILDERS))
    ap.add_argument("--view", default="dim", choices=sorted(VIEWS))
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--ortho", type=float, default=2.6, help="ortho width; 5.7 = scene framing")
    ap.add_argument("--target-z", type=float, default=0.9, help="look-at height")
    ap.add_argument("--out", default=None)
    ap.add_argument("--out-dir", default=default_out)
    ap.add_argument("--usdz", action="store_true", help="export instead of rendering")
    ap.add_argument("--contact", action="store_true", help="3 presets × 3 angles, one sheet")
    ap.add_argument("--sweep", help="vary one proportion, e.g. arm_r=0.06,0.08,0.10")
    ap.add_argument("--parts", action="store_true", help="every part alone, rendered + exported")
    ap.add_argument("--scale-check", action="store_true", help="beside hund.usdz and the table")
    ap.add_argument("--aufbau", action="store_true", help="bake the self-assembly clip")
    ap.add_argument("--gehen", action="store_true", help="bake the looping walk-cycle clip")
    ap.add_argument("--geste", metavar="NAME[,NAME]|all",
                    help="storyboard + Quick Look USDZ per gesture clip (see CLIPS), into "
                         "renders/figur/gesten/; `all` also writes gesten-katalog.png")
    ap.add_argument("--fast", action="store_true", help="48 render samples instead of 256")
    ap.add_argument("--pose", default="steh", choices=sorted(POSES) + sorted(GESTEN),
                    help="stance for the default render/export path (probe with --pose sitz)")
    ap.add_argument("--color", default=None, metavar="RRGGBB",
                    help="override the charcoal REFERENCE ink, e.g. ECE7DA for the dark-theme "
                         "still. Only the shipped flat stills need this: the live canvas re-tints "
                         "the USDZ at runtime, so an exported asset stays charcoal.")
    ap.add_argument("--verify", help="re-import a USDZ and print what is actually in it")
    args = ap.parse_args(argv)

    os.makedirs(args.out_dir, exist_ok=True)

    if args.verify:
        verify(args.verify)
        return
    if args.contact:
        scene_contact(args, args.out_dir)
        return
    if args.sweep:
        scene_sweep(args, args.out_dir)
        return
    if args.parts:
        scene_parts(args, args.out_dir)
        return
    if args.scale_check:
        scene_scale(args, args.out_dir)
        return
    if args.aufbau:
        scene_aufbau(args, args.out_dir)
        return
    if args.gehen:
        scene_gehen(args, args.out_dir)
        return
    if args.geste:
        scene_gesten(args, args.out_dir)
        return

    global _LOD
    if args.usdz:
        _LOD = "low"
    clear_scene()
    stage(args.size, *VIEWS[args.view], args.ortho, args.target_z)
    ink = make_material("figur", int(args.color, 16)) if args.color else None
    objects, p = build_figure(args.preset, args.height, part=args.part, mat=ink)
    apply_pose(objects, p, args.pose)
    report(args.preset, args.height, p)
    pose_tag = "" if args.pose == "steh" else f"-{args.pose}"
    if args.usdz:
        export_usdz(args.out or os.path.join(args.out_dir, "figur.usdz"))
    else:
        render_to(args.out or os.path.join(
            args.out_dir, f"figur-{args.preset}{pose_tag}-{args.view}.png"))


if __name__ == "__main__":
    main()
