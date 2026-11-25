"""Cut the gift's lid free and bake an open-close loop into the USDZ.

No skeleton — the lid is rigid, so it's the app's own idiom at authoring time: a separate
named part rotating about a hinge. Duplicate-and-bisect makes both halves watertight (each
copy keeps a filled cap at the cut), the lid's origin moves to the back top edge, and the
rotation is keyframed: closed → open → hold → closed.
"""

import argparse
import math
import sys

import bpy
from mathutils import Vector

REFERENCE = 0x33383D


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def flat_material():
    hex_value = REFERENCE
    r = ((hex_value >> 16) & 0xFF) / 255
    g = ((hex_value >> 8) & 0xFF) / 255
    b = (hex_value & 0xFF) / 255
    mat = bpy.data.materials.new("reference")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = (
        srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)
    shader.inputs["Roughness"].default_value = 0.62
    links.new(shader.outputs[0], out.inputs["Surface"])
    return mat


def bisect(obj, z, keep):
    """Cut obj at height z, keeping 'above' or 'below', with a filled cap at the cut."""
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.bisect(
        plane_co=(0, 0, z), plane_no=(0, 0, 1), use_fill=True,
        clear_inner=(keep == "above"), clear_outer=(keep == "below"),
    )
    bpy.ops.object.mode_set(mode="OBJECT")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--height", type=float, default=1.2)
    ap.add_argument("--faces", type=int, default=18000)
    ap.add_argument("--cut", type=float, default=0.58, help="lid line, fraction of height")
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.glb)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if len(obj.data.polygons) > args.faces:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = args.faces / len(obj.data.polygons)
        bpy.ops.object.modifier_apply(modifier="dec")

    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    zmin = min(v.z for v in bb)
    height = max(v.z for v in bb) - zmin
    scale = args.height / height
    obj.scale = (scale,) * 3
    bpy.ops.object.transform_apply(scale=True)
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    center = sum(bb, Vector()) / 8
    obj.location -= Vector((center.x, center.y, min(v.z for v in bb)))
    bpy.ops.object.transform_apply(location=True)

    mat = flat_material()
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()

    # Two watertight halves from two copies.
    cut_z = args.height * args.cut
    bpy.ops.object.duplicate()
    lid = bpy.context.view_layer.objects.active
    bisect(obj, cut_z, keep="below")
    bisect(lid, cut_z, keep="above")
    obj.name = "reference.box"
    lid.name = "reference.lid"

    # Hinge at the back top edge of the base (+y side): origin there, then rotate about X.
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    ymax = max(v.y for v in bb)
    bpy.context.scene.cursor.location = (0, ymax, cut_z)
    bpy.ops.object.select_all(action="DESELECT")
    lid.select_set(True)
    bpy.context.view_layer.objects.active = lid
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, 72
    scene.render.fps = 24
    lid.rotation_mode = "XYZ"
    # closed → open (0.9s) → hold open (1.1s) → close (0.9s) → brief closed hold.
    for frame, angle in ((1, 0), (22, -78), (48, -78), (68, 0), (72, 0)):
        lid.rotation_euler = (math.radians(angle), 0, 0)
        lid.keyframe_insert("rotation_euler", frame=frame)

    # Verification renders at closed / mid / open.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.view_settings.view_transform = "Standard"
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(-35), math.radians(20), 0)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    cam.data.angle = math.radians(30)
    cam.location = (2.6, -6.4, 2.8)
    d = Vector((0, 0, 0.55)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    for frame in (1, 12, 34):
        scene.frame_set(frame)
        scene.render.filepath = f"{args.out_dir}/gift-f{frame:02d}.png"
        bpy.ops.render.render(write_still=True)

    # No stowaway cameras or lights in shipped assets: the app builds its own rig, and
    # extra cameras from the USDZ can hijack or crash the device renderer (found 2026-07-30:
    # three cameras + nine lights inside prep3d-story-fuer trapped RealityKit on iPhone).
    for _o in [o for o in bpy.data.objects if o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(_o, do_unlink=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.wm.usd_export(
        filepath=f"{args.out_dir}/gift-open.usdz",
        export_materials=True,
        export_animation=True,
        convert_orientation=True,
    )
    print("GIFT_DONE")


main()
