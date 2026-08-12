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
from mathutils import Vector

# MARK: - Palette
#
# The neutral charcoal every non-subject form in the app wears (prep_render.py PALETTE).
# Deliberately not a case color and not a gender color: the figure must never contradict the
# der/die/das coding the app teaches everywhere else.

REFERENCE = 0x33383D

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

    global _LOD
    if args.usdz:
        _LOD = "low"
    clear_scene()
    stage(args.size, *VIEWS[args.view], args.ortho, args.target_z)
    _, p = build_figure(args.preset, args.height, part=args.part)
    report(args.preset, args.height, p)
    if args.usdz:
        export_usdz(args.out or os.path.join(args.out_dir, "figur.usdz"))
    else:
        render_to(args.out or os.path.join(args.out_dir, f"figur-{args.preset}-{args.view}.png"))


if __name__ == "__main__":
    main()
