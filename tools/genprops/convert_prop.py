"""Convert a generated GLB prop into the preposition-scene language.

Blender headless:
    Blender --background --python convert_prop.py -- --glb dog-raw.glb --name dog \
        --height 1.4 --out-dir /path/out

Steps: import, join, decimate to app weight, strip materials to the rig's flat charcoal,
recenter + sit on the ground plane + scale to scene units, render a still with the SAME
dim camera/light rig as prep_render.py (so the prop can be judged against the house style),
and export USDZ (Y-up) for the live scenes.
"""

import argparse
import math
import sys

import bpy
from mathutils import Vector

# prep_render.py's palette + srgb conversion, duplicated knowingly — this is a scratch
# pipeline; if props graduate into the rig, this merges into it.
REFERENCE = 0x33383D


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(hex_value, alpha=1.0):
    r = ((hex_value >> 16) & 0xFF) / 255
    g = ((hex_value >> 8) & 0xFF) / 255
    b = (hex_value & 0xFF) / 255
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), alpha)


def flat_material():
    mat = bpy.data.materials.new("reference")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = rgba(REFERENCE)
    shader.inputs["Roughness"].default_value = 0.62
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.25
    links.new(shader.outputs[0], out.inputs["Surface"])
    return mat


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--height", type=float, default=1.4, help="target height in scene units")
    ap.add_argument("--faces", type=int, default=18000)
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.glb)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("no meshes in GLB")
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Decimate to app weight (the raw meshes are ~300k faces).
    face_count = len(obj.data.polygons)
    if face_count > args.faces:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = args.faces / face_count
        bpy.ops.object.modifier_apply(modifier="dec")

    # Ground + center + scale: min-z on the floor, centered in x/y, height normalized.
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    zmin = min(v.z for v in bb)
    height = max(v.z for v in bb) - zmin
    scale = args.height / height if height > 0 else 1.0
    obj.scale = (scale,) * 3
    bpy.ops.object.transform_apply(scale=True)
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    center = sum(bb, Vector()) / 8
    obj.location.x -= center.x
    obj.location.y -= center.y
    obj.location.z -= min(v.z for v in bb)
    bpy.ops.object.transform_apply(location=True)

    obj.name = "reference.prop"
    obj.data.materials.clear()
    obj.data.materials.append(flat_material())
    bpy.ops.object.shade_smooth()

    # The rig's dim look: perspective raked camera + key/rim/fill, film transparent.
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.data.angle = math.radians(30)
    cam.location = (4.0, -10.6, 4.3)
    direction = Vector((0, 0, 0.5)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    for name, kind, energy, loc in (
        ("key", "SUN", 3.2, (-4.6, -4.2, 6.4)),
        ("rim", "SUN", 1.8, (4.8, 4.4, 2.6)),
        ("fill", "SUN", 0.6, (4.2, -6.4, 0.6)),
    ):
        light = bpy.data.objects.new(name, bpy.data.lights.new(name, kind))
        light.data.energy = energy
        scene.collection.objects.link(light)
        d = Vector((0, 0, 0)) - Vector(loc)
        light.location = loc
        light.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()

    scene.render.filepath = f"{args.out_dir}/{args.name}-judge.png"
    bpy.ops.render.render(write_still=True)

    # No stowaway cameras or lights in shipped assets: the app builds its own rig, and
    # extra cameras from the USDZ can hijack or crash the device renderer (found 2026-07-30:
    # three cameras + nine lights inside prep3d-story-fuer trapped RealityKit on iPhone).
    for _o in [o for o in bpy.data.objects if o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(_o, do_unlink=True)
    bpy.ops.wm.usd_export(
        filepath=f"{args.out_dir}/{args.name}.usdz",
        export_materials=True,
        export_animation=False,
        convert_orientation=True,
    )
    print(f"CONVERTED {args.name}: {len(obj.data.polygons)} faces")


main()
