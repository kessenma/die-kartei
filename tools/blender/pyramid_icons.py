#!/usr/bin/env python3
"""
pyramid_icons.py — Bauhaus icon stills for the Lernpyramide screen.

Nine icons in the preposition scenes' vocabulary (charcoal structure + one accent, flat
Bauhaus forms, EEVEE + Standard view transform, transparent film): one per pyramid layer,
plus three section marks (Wo du stehst / Bauplan / Weiterbauen).

    tools/blender/pyramid_icons.py            # via Blender:
    /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/pyramid_icons.py

Output: tools/blender/renders/icons/pyramid-icon-<slug>-<mode>.png (512px, alpha),
mode = light | dark. The two modes are separately *lit*, not tinted: light mode carries the
prep rig's key-heavy wash over charcoal; dark mode lifts the structure grey and leans on the
rim so edges separate from a dark ground. The app lands them in Assets.xcassets as one image
set per icon with an Any + Dark appearance pair.

Caveat carried over from render_all.sh: dimensional shading muds below ~40pt, which is why the
prep *row* icons stayed SF Symbols. These icons are deliberately chunkier (2–4 bold forms, no
figures) to survive a 38pt chip — review them at real size before adopting; the app falls back
to SF Symbols wherever an asset is missing, so shipping without any of them stays safe.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

# MARK: - Palette

def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(hex_value: int, alpha: float = 1.0):
    r = ((hex_value >> 16) & 0xFF) / 255
    g = ((hex_value >> 8) & 0xFF) / 255
    b = (hex_value & 0xFF) / 255
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), alpha)


# Structure per mode: charcoal on light grounds; lifted grey on dark ones, where charcoal
# would sink into the background no matter how it is lit. The dark grey sits mid-range on
# purpose — 0x9AA2AB rendered nearly white under the rim-heavy dark rig.
STRUCTURE = {"light": 0x33383D, "dark": 0x6E7680}

# Accent per icon, (light, dark) — dark variants are brighter, matching how the app's own
# Color(light:dark:) pairs behave. Layer accents follow PyramidLayerID.tint.
ACCENTS = {
    "fundament":     {"light": 0xE8890C, "dark": 0xFFA82E},   # orange
    "wortschatzA1":  {"light": 0x0A7AFF, "dark": 0x409CFF},   # blue
    "geschichtenA1": {"light": 0xE8355C, "dark": 0xFF6482},   # pink
    "grammatikKern": {"light": 0x9A44D8, "dark": 0xBF6AF2},   # purple
    "vertiefungA2":  {"light": 0x5856D6, "dark": 0x7D7AFF},   # indigo
    "spitze":        {"light": 0x27A245, "dark": 0x30D158},   # green
    "wo-du-stehst":  {"light": 0x2098AC, "dark": 0x40C8E0},   # teal — the surveyor's mark
    "bauplan":       {"light": 0x2D6FD1, "dark": 0x5E97E8},   # blueprint blue
    "weiterbauen":   {"light": 0xE8890C, "dark": 0xFFA82E},   # builder orange
    # Journey ("Dein Weg") milestone marks:
    "grundstein":    {"light": 0xE8890C, "dark": 0xFFA82E},   # foundation orange
    "gemeistert":    {"light": 0x27A245, "dark": 0x30D158},   # green
    "zurueckgeholt": {"light": 0x5856D6, "dark": 0x7D7AFF},   # indigo — the comeback
    "sitzt-noch":    {"light": 0x2098AC, "dark": 0x40C8E0},   # teal — still standing
    "flamme":        {"light": 0xE8890C, "dark": 0xFFA82E},   # streak orange
    "rang":          {"light": 0xB8860B, "dark": 0xC9A227},   # rank gold (LearnerRank meister)
    # Journey milestones with no earlier mark of their own:
    "schicht-fertig":      {"light": 0x27A245, "dark": 0x30D158},   # green — a course closed
    "zurueck-im-training": {"light": 0xE8890C, "dark": 0xFFA82E},   # orange — back on the bench
    "wegweiser":           {"light": 0x2098AC, "dark": 0x40C8E0},   # teal — the empty-state signpost
    # Abzeichen. Slug = "abzeichen-<Achievement.id>", so the catalog and the render set can only
    # drift by someone renaming an id — and a missing icon still falls back to its SF Symbol.
    "abzeichen-first-steps":     {"light": 0x0A7AFF, "dark": 0x409CFF},   # blue
    "abzeichen-streak-7":        {"light": 0xE8890C, "dark": 0xFFA82E},   # orange
    "abzeichen-streak-30":       {"light": 0xE8890C, "dark": 0xFFA82E},   # orange
    "abzeichen-streak-100":      {"light": 0xE0A400, "dark": 0xFFD426},   # yellow (Achievement .yellow)
    "abzeichen-words-100":       {"light": 0x0A7AFF, "dark": 0x409CFF},   # blue
    "abzeichen-words-500":       {"light": 0x5856D6, "dark": 0x7D7AFF},   # indigo
    "abzeichen-words-1000":      {"light": 0x9A44D8, "dark": 0xBF6AF2},   # purple
    "abzeichen-reviews-500":     {"light": 0x0A7AFF, "dark": 0x409CFF},   # blue
    "abzeichen-perfect-match":   {"light": 0x27A245, "dark": 0x30D158},   # green
    "abzeichen-perfect-article": {"light": 0x9A44D8, "dark": 0xBF6AF2},   # purple
    "abzeichen-perfect-case":    {"light": 0xE8890C, "dark": 0xFFA82E},   # orange
    "abzeichen-story-first":     {"light": 0xE8355C, "dark": 0xFF6482},   # pink
    "abzeichen-story-perfect":   {"light": 0xE8355C, "dark": 0xFF6482},   # pink
    "abzeichen-chat-10":         {"light": 0x27A245, "dark": 0x30D158},   # green
    "abzeichen-grammar-solid":   {"light": 0x9A44D8, "dark": 0xBF6AF2},   # purple
    "abzeichen-pyramid-base":    {"light": 0xE8890C, "dark": 0xFFA82E},   # orange
}

MODES = ("light", "dark")
SIZE = 512
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders", "icons")


# MARK: - Scene plumbing (prep_render.py idioms)

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, hex_value):
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


def add_box(size, at, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = Vector(size)
    obj.data.materials.append(mat)
    return obj


def add_sphere(radius, at, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=64, ring_count=32, location=at)
    obj = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    return obj


def add_cylinder(radius, depth, at, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=48,
                                        location=at, rotation=rot)
    obj = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    return obj


def add_cone(radius, depth, at, mat, rot=(0, 0, 0), vertices=48, point_down=False):
    rotation = (rot[0] + (math.pi if point_down else 0), rot[1], rot[2])
    bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=0, depth=depth, vertices=vertices,
                                    location=at, rotation=rotation)
    obj = bpy.context.active_object
    obj.data.materials.append(mat)
    return obj


def setup_camera():
    """The prep scenes' raked three-quarter framing, tightened to icon scale. Orthographic,
    so the same form reads identically wherever it sits in frame."""
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    # Tight framing on purpose: these show bare (no chip) at ~40–52pt, so empty margin in the
    # render is size the row never sees.
    cam_data.ortho_scale = 2.35
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)

    target = Vector((0, 0, 0.72))
    azimuth, elevation, distance = math.radians(21), math.radians(15), 11.0
    cam.location = (
        distance * math.sin(azimuth) * math.cos(elevation),
        -distance * math.cos(azimuth) * math.cos(elevation),
        target.z + distance * math.sin(elevation),
    )
    cam.rotation_euler = (Vector(cam.location) - target).to_track_quat("Z", "Y").to_euler()
    bpy.context.scene.camera = cam


LIGHT_SCALE = 0.55


def setup_lights(mode):
    """Two deliberate rigs, not a tint swap. Light mode is the prep wash (key-heavy, ~7:1).
    Dark mode trades key for rim: the edge light is what separates a form from a dark ground,
    and the fill is lifted so the shadow side never reads as background."""

    def area(name, energy, size, location, rotation):
        data = bpy.data.lights.new(name, type="AREA")
        data.energy = energy
        data.size = size
        light = bpy.data.objects.new(name, data)
        light.location = location
        light.rotation_euler = rotation
        bpy.context.collection.objects.link(light)

    if mode == "light":
        area("key", 2600 * LIGHT_SCALE, 3.0, (-4.6, -4.2, 6.4),
             (math.radians(42), 0, math.radians(-42)))
        area("rim", 1700 * LIGHT_SCALE, 1.6, (4.8, 4.4, 2.6),
             (math.radians(74), 0, math.radians(133)))
        area("fill", 360 * LIGHT_SCALE, 9, (4.2, -6.4, 0.6),
             (math.radians(84), 0, math.radians(36)))
    else:
        area("key", 1900 * LIGHT_SCALE, 3.0, (-4.6, -4.2, 6.4),
             (math.radians(42), 0, math.radians(-42)))
        area("rim", 2600 * LIGHT_SCALE, 1.6, (4.8, 4.4, 2.6),
             (math.radians(74), 0, math.radians(133)))
        area("fill", 520 * LIGHT_SCALE, 9, (4.2, -6.4, 0.6),
             (math.radians(84), 0, math.radians(36)))


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    # Standard, NOT AgX — a film transform would shift every hex off the palette.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 256
        scene.eevee.use_shadows = True
        scene.eevee.shadow_ray_count = 4
        scene.eevee.shadow_step_count = 8
        scene.eevee.shadow_resolution_scale = 2.0


# MARK: - The icons
#
# Each builder gets (structure_mat, accent_mat) and composes 2–4 primitives inside a ~2-unit
# box on the ground plane. Bold silhouettes only: these have to survive a 38pt chip.

def icon_fundament(s, a):
    """The gate: two pillars carrying an accent lintel — every sentence stands on its case."""
    add_box((0.4, 0.4, 1.05), (-0.55, 0, 0.525), s)
    add_box((0.4, 0.4, 1.05), (0.55, 0, 0.525), s)
    add_box((1.95, 0.5, 0.38), (0, 0, 1.24), a)


def icon_wortschatz(s, a):
    """The Bauhaus trio as building blocks: words are the pieces everything is built from."""
    add_box((0.62, 0.62, 0.62), (-0.5, 0.15, 0.31), s)
    add_cone(0.4, 0.75, (0.05, -0.3, 0.375), s, vertices=48)
    add_sphere(0.34, (0.62, 0.2, 0.34), a)


def icon_geschichten(s, a):
    """The standing open book: two accent pages fanning up from a charcoal spine block."""
    add_box((0.24, 0.88, 0.22), (0, 0, 0.13), s)
    add_box((0.82, 0.85, 0.07), (-0.18, 0, 0.58), a, rot=(0, math.radians(65), 0))
    add_box((0.82, 0.85, 0.07), (0.18, 0, 0.58), a, rot=(0, math.radians(-65), 0))


def icon_grammatik(s, a):
    """The grid with the fitting piece: three sockets hold, the accent ball takes its slot."""
    add_box((0.55, 0.55, 0.55), (-0.36, 0, 0.275), s)
    add_box((0.55, 0.55, 0.55), (0.36, 0, 0.275), s)
    add_box((0.55, 0.55, 0.55), (-0.36, 0, 0.92), s)
    add_sphere(0.3, (0.36, 0, 0.92), a)


def icon_vertiefung(s, a):
    """The steps: each course set back on the last, the newest still in accent."""
    add_box((1.7, 0.7, 0.34), (0.1, 0, 0.17), s)
    add_box((1.15, 0.7, 0.34), (-0.175, 0, 0.51), s)
    add_box((0.6, 0.7, 0.34), (-0.45, 0, 0.85), a)


def icon_spitze(s, a):
    """The conversation: two voices facing, tails down — the peak is speaking."""
    add_sphere(0.46, (-0.42, 0, 1.0), s)
    add_cone(0.16, 0.34, (-0.56, 0, 0.42), s, point_down=True)
    add_sphere(0.33, (0.52, 0, 0.62), a)
    add_cone(0.13, 0.28, (0.42, 0, 0.18), a, point_down=True)


def icon_wo_du_stehst(s, a):
    """The plumb line: bar, string, accent bob over its ground mark — an honest measurement."""
    add_box((1.5, 0.34, 0.14), (0, 0, 1.62), s)
    add_cylinder(0.025, 0.75, (0, 0, 1.18), s)
    add_cone(0.24, 0.5, (0, 0, 0.62), a, point_down=True)
    add_box((0.62, 0.34, 0.08), (0, 0, 0.04), s)


def icon_bauplan(s, a):
    """The blueprint mid-unroll: the accent sheet flat on the table, the roll still holding
    its far edge, the set square lying where the drafting stopped."""
    add_box((1.5, 1.0, 0.05), (0.12, 0, 0.03), a)
    add_cylinder(0.21, 1.04, (-0.66, 0, 0.21), a, rot=(math.radians(90), 0, 0))
    add_cone(0.5, 0.06, (0.42, -0.12, 0.09), s, rot=(0, 0, math.radians(15)), vertices=3)


def icon_weiterbauen(s, a):
    """The crane over the site: mast, jib, cable, and the accent block still in the air."""
    add_box((1.25, 0.55, 0.2), (0.3, 0, 0.1), s)
    add_box((0.17, 0.17, 1.65), (-0.55, 0, 0.825), s)
    add_box((1.45, 0.15, 0.15), (0.05, 0, 1.58), s)
    add_cylinder(0.02, 0.45, (0.6, 0, 1.28), s)
    add_box((0.4, 0.4, 0.4), (0.6, 0, 0.85), a)


def icon_grundstein(s, a):
    """The cornerstone: the first accent block set on a bare charcoal ground plate."""
    add_box((1.6, 1.05, 0.14), (0.1, 0, 0.07), s)
    add_box((0.66, 0.66, 0.66), (-0.42, -0.08, 0.47), a)


def icon_gemeistert(s, a):
    """The peg seated in its socket: the form fits, the struggle is over."""
    add_box((1.15, 0.9, 0.6), (0, 0, 0.3), s)
    add_cylinder(0.23, 0.55, (0, 0, 0.75), a)


def icon_zurueckgeholt(s, a):
    """The comeback: a block arcing back to its landing pad, trajectory dotted behind it."""
    add_box((0.95, 0.65, 0.16), (0.42, 0, 0.08), s)
    add_sphere(0.075, (-0.62, 0, 0.42), s)
    add_sphere(0.075, (-0.3, 0, 0.85), s)
    add_sphere(0.075, (0.08, 0, 1.05), s)
    add_box((0.5, 0.5, 0.5), (0.48, 0, 0.75), a, rot=(0, math.radians(-14), 0))


def icon_sitzt_noch(s, a):
    """Still standing: the mastered block up on its museum plinth, months later."""
    add_box((0.55, 0.55, 0.85), (0, 0, 0.425), s)
    add_box((0.78, 0.78, 0.1), (0, 0, 0.9), s)
    add_box((0.44, 0.44, 0.44), (0, 0, 1.17), a)


def icon_flamme(s, a):
    """The streak flame: an accent cone burning out of a charcoal dish."""
    add_cylinder(0.48, 0.2, (0, 0, 0.1), s)
    add_cone(0.35, 0.95, (0, 0, 0.675), a)
    add_sphere(0.09, (0.02, 0, 1.28), a)


def icon_rang(s, a):
    """The rank flag: a gold banner flying from a charcoal pole. A rectangle, not a triangle —
    a 3-vert cone's vertex orientation is luck, and the flag has to visibly touch the pole."""
    add_cylinder(0.35, 0.12, (-0.35, 0, 0.06), s)
    add_cylinder(0.05, 1.75, (-0.35, 0, 0.995), s)
    add_sphere(0.09, (-0.35, 0, 1.9), s)
    add_box((0.72, 0.05, 0.42), (0.06, 0, 1.6), a)


# MARK: - „Dein Weg" marks
#
# Everything below was authored for the journey timeline, where the row icon is 44pt and the
# empty state ~52pt. Same rules as above: 2–5 primitives, one accent, bold silhouette.

def icon_schicht_fertig(s, a):
    """A course closed: three blocks fill a base plate, the last one accent and flush — the
    layer is finished, not merely started."""
    add_box((1.75, 0.8, 0.16), (0, 0, 0.08), s)
    add_box((0.5, 0.7, 0.44), (-0.55, 0, 0.38), s)
    add_box((0.5, 0.7, 0.44), (0, 0, 0.38), s)
    add_box((0.5, 0.7, 0.44), (0.55, 0, 0.38), a)


def icon_zurueck_im_training(s, a):
    """Back at the foot of the ramp: the block has the climb to make again. `zurueckgeholt` is
    the flight back; this is the work resuming — and the diagonal is a silhouette nothing else
    on the timeline owns."""
    add_box((1.85, 0.85, 0.14), (0, 0, 0.07), s)
    add_box((1.7, 0.7, 0.14), (0.2, 0, 0.62), s, rot=(0, math.radians(24), 0))
    add_box((0.54, 0.54, 0.54), (-0.66, 0, 0.41), a)


def icon_wegweiser(s, a):
    """The signpost of the empty timeline: nothing walked yet, but the way is marked. The accent
    arm points forward, a charcoal arm points back the way you came."""
    add_cylinder(0.4, 0.16, (0, 0, 0.08), s)
    add_cylinder(0.09, 1.62, (0, 0, 0.89), s)
    add_box((0.72, 0.12, 0.28), (-0.42, 0, 0.95), s)
    add_box((0.98, 0.12, 0.34), (0.53, 0, 1.42), a)


# MARK: - Abzeichen
#
# One form per badge — the timeline shows badge rows next to milestone rows, so a generic medal
# for all sixteen would have said only "a badge". Each is built from what the badge is *for*:
# the silhouette has to be told apart from its neighbours at 44pt, which is why near-twins
# (three word tiers, two story badges) deliberately use unrelated objects rather than a shared
# form with a count on it.

def icon_abz_first_steps(s, a):
    """The first step taken: a footprint on the ground, the next one already up on the step."""
    add_box((1.8, 0.95, 0.22), (0, 0, 0.11), s)
    add_cylinder(0.32, 0.24, (-0.52, 0.14, 0.34), s)
    add_box((1.0, 0.8, 0.42), (0.36, -0.06, 0.43), s)
    add_cylinder(0.34, 0.26, (0.3, -0.08, 0.77), a)
    add_cylinder(0.14, 0.22, (0.64, -0.16, 0.75), a)


def icon_abz_streak_7(s, a):
    """A week alight: one candle, still burning. The 30-day badge answers it with a medal, so
    the two streak marks can't be mistaken for each other."""
    add_cylinder(0.46, 0.16, (0, 0, 0.08), s)
    add_cylinder(0.25, 0.86, (0, 0, 0.59), s)
    add_cone(0.23, 0.62, (0, 0, 1.33), a)


def icon_abz_streak_30(s, a):
    """Monatsmeisterschaft: the medal on its ribbon — a month held is a competition won."""
    add_box((0.92, 0.14, 0.16), (0, 0, 1.78), s)
    add_box((0.46, 0.16, 0.6), (0, 0, 1.44), s)
    add_cylinder(0.52, 0.2, (0, 0, 0.76), a, rot=(math.radians(90), 0, 0))
    add_cylinder(0.19, 0.28, (0, 0, 0.76), s, rot=(math.radians(90), 0, 0))


def icon_abz_streak_100(s, a):
    """Unaufhaltsam: the bolt, in two struck segments over a charcoal plate."""
    add_box((1.0, 0.6, 0.14), (0, 0, 0.07), s)
    add_box((0.32, 0.2, 0.85), (0.2, 0, 0.55), a, rot=(0, math.radians(32), 0))
    add_box((0.32, 0.2, 0.85), (0.2, 0, 1.27), a, rot=(0, math.radians(-32), 0))


def icon_abz_words_100(s, a):
    """Wortsammler: the collecting tray, two words already in it."""
    add_box((1.5, 0.9, 0.16), (0, 0, 0.08), s)
    add_box((1.5, 0.12, 0.3), (0, -0.39, 0.31), s)
    add_sphere(0.26, (-0.36, 0.08, 0.42), a)
    add_sphere(0.26, (0.26, 0.12, 0.42), a)


def icon_abz_words_500(s, a):
    """Wortschmied: the anvil, with the hammer mid-swing. Words stop being collected and start
    being made."""
    add_box((0.5, 0.42, 0.34), (0, 0, 0.17), s)
    add_box((1.2, 0.55, 0.32), (0, 0, 0.5), s)
    add_box((0.5, 0.3, 0.3), (-0.12, 0, 0.86), a)
    add_cylinder(0.075, 0.9, (0.44, 0, 1.15), s, rot=(0, math.radians(52), 0))


def icon_abz_words_1000(s, a):
    """Lexikon: a shelf of volumes, one pulled proud of the rest."""
    add_box((1.75, 0.75, 0.14), (0, 0, 0.07), s)
    add_box((0.24, 0.62, 0.88), (-0.55, 0, 0.58), s)
    add_box((0.24, 0.62, 1.0), (-0.2, 0, 0.64), a)
    add_box((0.24, 0.62, 0.84), (0.26, 0, 0.56), s, rot=(0, math.radians(-15), 0))


def icon_abz_reviews_500(s, a):
    """Karteikasten: the review box, one card standing up out of it."""
    add_box((1.35, 0.95, 0.14), (0, 0, 0.07), s)
    add_box((1.35, 0.14, 0.5), (0, -0.42, 0.25), s)
    add_box((1.35, 0.14, 0.68), (0, 0.42, 0.34), s)
    add_box((0.95, 0.08, 0.8), (0, 0.06, 0.62), a, rot=(math.radians(-10), 0, 0))


def icon_abz_perfect_match(s, a):
    """Fehlerfrei: the check itself, cut in two accent strokes across a charcoal tile."""
    add_box((1.4, 1.0, 0.14), (0, 0, 0.07), s)
    add_box((0.44, 0.22, 0.22), (-0.38, 0, 0.34), a, rot=(0, math.radians(-58), 0))
    add_box((1.1, 0.22, 0.22), (0.14, 0, 0.66), a, rot=(0, math.radians(38), 0))


def icon_abz_perfect_article(s, a):
    """Der Perfektionist: three sockets, one ball — der/die/das, and the right one taken."""
    add_box((1.75, 0.6, 0.28), (0, 0, 0.14), s)
    add_box((0.3, 0.5, 0.42), (-0.62, 0, 0.49), s)
    add_box((0.3, 0.5, 0.42), (0, 0, 0.49), s)
    add_box((0.3, 0.5, 0.42), (0.62, 0, 0.49), s)
    add_sphere(0.27, (0.31, 0, 0.55), a)


def icon_abz_perfect_case(s, a):
    """Fall gelöst: the case splits two ways and the accent lands on the right arm."""
    add_box((0.24, 0.24, 0.72), (0, 0, 0.36), s)
    add_box((0.2, 0.2, 0.8), (-0.28, 0, 0.98), s, rot=(0, math.radians(-34), 0))
    add_box((0.2, 0.2, 0.8), (0.28, 0, 0.98), s, rot=(0, math.radians(34), 0))
    add_sphere(0.26, (0.54, 0, 1.44), a)


def icon_abz_story_first(s, a):
    """Buchwurm: the worm coming up out of the closed book."""
    add_box((0.4, 1.0, 1.15), (-0.2, 0, 0.575), s)
    add_sphere(0.2, (0.14, -0.16, 1.16), a)
    add_sphere(0.185, (0.46, -0.24, 0.94), a)
    add_sphere(0.16, (0.72, -0.3, 0.66), a)


def icon_abz_story_perfect(s, a):
    """Fehlerlos gelesen: the same book closed and sealed — read clean, start to finish."""
    add_box((1.45, 1.0, 0.34), (0, 0, 0.17), s)
    add_box((1.3, 0.88, 0.12), (0, 0, 0.4), s)
    add_box((0.32, 1.12, 0.62), (0.12, 0, 0.24), a)


def icon_abz_chat_10(s, a):
    """Plaudertasche: a thread of turns, the newest on top and still speaking."""
    add_box((1.2, 0.5, 0.24), (-0.16, 0, 0.12), s)
    add_box((1.05, 0.46, 0.24), (0.14, 0, 0.42), s)
    add_box((0.9, 0.42, 0.24), (-0.1, 0, 0.72), a)
    add_cone(0.12, 0.24, (-0.42, 0, 0.5), a, point_down=True)


def icon_abz_grammar_solid(s, a):
    """Grammatik-Guru: the column — structure that carries load, with the accent capital on top."""
    add_cylinder(0.52, 0.16, (0, 0, 0.08), s)
    add_cylinder(0.3, 1.16, (0, 0, 0.74), s)
    add_box((0.88, 0.88, 0.26), (0, 0, 1.45), a)


def icon_abz_pyramid_base(s, a):
    """Fundament gelegt: the pyramid's bottom course, the only one in accent — the rest is still
    to come. Symmetric on purpose, so it can't be read as `vertiefungA2`'s offset steps."""
    add_box((1.7, 1.0, 0.3), (0, 0, 0.15), a)
    add_box((1.2, 0.8, 0.3), (0, 0, 0.45), s)
    add_box((0.7, 0.6, 0.3), (0, 0, 0.75), s)


ICONS = {
    "fundament": icon_fundament,
    "wortschatzA1": icon_wortschatz,
    "geschichtenA1": icon_geschichten,
    "grammatikKern": icon_grammatik,
    "vertiefungA2": icon_vertiefung,
    "spitze": icon_spitze,
    "wo-du-stehst": icon_wo_du_stehst,
    "bauplan": icon_bauplan,
    "weiterbauen": icon_weiterbauen,
    "grundstein": icon_grundstein,
    "gemeistert": icon_gemeistert,
    "zurueckgeholt": icon_zurueckgeholt,
    "sitzt-noch": icon_sitzt_noch,
    "flamme": icon_flamme,
    "rang": icon_rang,
    "schicht-fertig": icon_schicht_fertig,
    "zurueck-im-training": icon_zurueck_im_training,
    "wegweiser": icon_wegweiser,
    "abzeichen-first-steps": icon_abz_first_steps,
    "abzeichen-streak-7": icon_abz_streak_7,
    "abzeichen-streak-30": icon_abz_streak_30,
    "abzeichen-streak-100": icon_abz_streak_100,
    "abzeichen-words-100": icon_abz_words_100,
    "abzeichen-words-500": icon_abz_words_500,
    "abzeichen-words-1000": icon_abz_words_1000,
    "abzeichen-reviews-500": icon_abz_reviews_500,
    "abzeichen-perfect-match": icon_abz_perfect_match,
    "abzeichen-perfect-article": icon_abz_perfect_article,
    "abzeichen-perfect-case": icon_abz_perfect_case,
    "abzeichen-story-first": icon_abz_story_first,
    "abzeichen-story-perfect": icon_abz_story_perfect,
    "abzeichen-chat-10": icon_abz_chat_10,
    "abzeichen-grammar-solid": icon_abz_grammar_solid,
    "abzeichen-pyramid-base": icon_abz_pyramid_base,
}


# MARK: - Contact sheet
#
# The one review that matters for these is "does it read at row size", and that can't be judged
# from 512px stills. Cells default to 132px — a 44pt row icon at @3x, i.e. the exact pixels the
# device draws — composited on the theme grounds so light and dark are judged where they live.

# The app's own grounds: Grundform screen background, and the dark list ground under it.
GROUNDS = {"light": 0xF3EFE6, "dark": 0x1C1C1E}


def contact_sheet(slugs, mode, out_path, cell=132, cols=6):
    """Composite rendered icons onto the theme ground at ~`cell` px.

    Images are handled as Non-Color so nothing in colour management touches the paste path, and
    the downsample is a plain box average — no filtering that could flatter an icon the device
    would show harshly. The requested cell snaps to the nearest whole divisor of SIZE (132 →
    128), which is close enough to a 44pt row icon at @3x to judge and keeps the average exact.
    """
    import numpy as np

    factor = max(1, round(SIZE / cell))
    cell = SIZE // factor
    ground = GROUNDS[mode]
    rows = math.ceil(len(slugs) / cols)
    canvas = np.zeros((rows * cell, cols * cell, 4), dtype=np.float32)
    canvas[:, :, 0] = ((ground >> 16) & 0xFF) / 255
    canvas[:, :, 1] = ((ground >> 8) & 0xFF) / 255
    canvas[:, :, 2] = (ground & 0xFF) / 255
    canvas[:, :, 3] = 1.0

    for i, slug in enumerate(slugs):
        path = os.path.join(OUT_DIR, f"pyramid-icon-{slug}-{mode}.png")
        if not os.path.exists(path):
            continue
        img = bpy.data.images.load(path)
        img.colorspace_settings.name = "Non-Color"
        img.alpha_mode = "STRAIGHT"
        width, height = img.size
        buf = np.array(img.pixels[:], dtype=np.float32).reshape(height, width, 4)
        bpy.data.images.remove(img)

        # Box-average down to the cell size.
        if factor > 1:
            keep = cell * factor
            buf = buf[:keep, :keep].reshape(cell, factor, cell, factor, 4).mean(axis=(1, 3))

        row, col = divmod(i, cols)
        # Blender image buffers are bottom-up, so row 0 of the grid is the top band.
        y0 = (rows - 1 - row) * cell
        x0 = col * cell
        alpha = buf[:, :, 3:4]
        target = canvas[y0:y0 + cell, x0:x0 + cell, 0:3]
        canvas[y0:y0 + cell, x0:x0 + cell, 0:3] = buf[:, :, 0:3] * alpha + target * (1 - alpha)

    out = bpy.data.images.new("contact", width=cols * cell, height=rows * cell, alpha=True)
    out.colorspace_settings.name = "Non-Color"
    out.pixels = canvas.ravel()
    out.filepath_raw = os.path.abspath(out_path)
    out.file_format = "PNG"
    out.save()
    print(f"CONTACT {out_path} {cols * cell}x{rows * cell} ({len(slugs)} cells @ {cell}px)")


# MARK: - Render loop

def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def parse_args():
    """Blender passes the script's own arguments after a bare `--`."""
    import argparse
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="", help="comma-separated slugs (default: all)")
    parser.add_argument("--contact", action="store_true",
                        help="also write a review sheet per mode")
    parser.add_argument("--cell", type=int, default=132,
                        help="contact cell size in px (132 = a 44pt row icon at @3x)")
    parser.add_argument("--skip-render", action="store_true",
                        help="contact sheet only, from the PNGs already on disk")
    return parser.parse_args(argv)


def main():
    args = parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)

    slugs = [s.strip() for s in args.only.split(",") if s.strip()] or list(ICONS)
    unknown = [s for s in slugs if s not in ICONS]
    if unknown:
        raise SystemExit(f"unknown slug(s): {', '.join(unknown)}")

    if not args.skip_render:
        for slug in slugs:
            for mode in MODES:
                clear_scene()
                structure = make_material("structure", STRUCTURE[mode])
                accent = make_material("accent", ACCENTS[slug][mode])
                ICONS[slug](structure, accent)
                setup_camera()
                setup_lights(mode)
                setup_render()
                out = os.path.join(OUT_DIR, f"pyramid-icon-{slug}-{mode}.png")
                render_to(out)
                print(f"rendered {out}")

    if args.contact:
        for mode in MODES:
            contact_sheet(slugs, mode, os.path.join(OUT_DIR, f"contact-{mode}.png"),
                          cell=args.cell)


if __name__ == "__main__":
    main()
