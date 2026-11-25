"""Rig the bird's wings and bake a flap loop into the USDZ.

Skeletal, not hinge-cut: the wings blend into a round body, and a rigid cut would open a
seam at the shoulder on every flap. Weights fall off by |x| (probes: wing lobes live past
|x| ≈ 0.45 in raw mesh coords), one bone per wing pointing outward, mirrored rotation.
The über scene flies this bird over the fence; the flap is what says "fliegt".
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
    r = ((REFERENCE >> 16) & 0xFF) / 255
    g = ((REFERENCE >> 8) & 0xFF) / 255
    b = (REFERENCE & 0xFF) / 255
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


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--name", default="vogel")
    ap.add_argument("--height", type=float, default=0.7)
    ap.add_argument("--faces", type=int, default=18000)
    # Generated meshes arrive at arbitrary yaw; wings must lie along ±x for the |x| weight
    # rule, so measure the wing axis in a probe and pass the correction here.
    ap.add_argument("--rotz", type=float, default=0.0, help="degrees, applied before weighting")
    ap.add_argument("--wing-start", type=float, default=0.38)
    ap.add_argument("--wing-full", type=float, default=0.60)
    ap.add_argument("--shoulder", type=float, default=0.40)
    ap.add_argument("--amp", type=float, default=24.0, help="flap amplitude, degrees")
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

    if args.rotz:
        obj.rotation_euler = (0, 0, math.radians(args.rotz))
        bpy.ops.object.transform_apply(rotation=True)

    if len(obj.data.polygons) > args.faces:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = args.faces / len(obj.data.polygons)
        bpy.ops.object.modifier_apply(modifier="dec")

    # Weights by |x|: 0 at the body (|x| < 0.38), 1 at the wing lobes (|x| > 0.60).
    mesh = obj.data
    g_root = obj.vertex_groups.new(name="root")
    g_l = obj.vertex_groups.new(name="wingL")
    g_r = obj.vertex_groups.new(name="wingR")
    for v in mesh.vertices:
        w = max(0.0, min(1.0, (abs(v.co.x) - args.wing_start) / (args.wing_full - args.wing_start)))
        # Smoothstep the falloff so the shoulder blend has no crease.
        w = w * w * (3 - 2 * w)
        if w > 0:
            (g_l if v.co.x < 0 else g_r).add([v.index], w, "REPLACE")
        if w < 1:
            g_root.add([v.index], 1 - w, "REPLACE")

    arm = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    b_root = arm.edit_bones.new("root")
    b_root.head, b_root.tail = Vector((0, 0, -0.9)), Vector((0, 0, -0.5))
    for name, sign in (("wingL", -1), ("wingR", 1)):
        b = arm.edit_bones.new(name)
        b.head = Vector((sign * args.shoulder, -0.15, 0.05))
        b.tail = Vector((sign * 0.95, -0.20, 0.15))
        b.parent = b_root
    bpy.ops.object.mode_set(mode="OBJECT")

    mod = obj.modifiers.new("arm", "ARMATURE")
    mod.object = rig
    obj.parent = rig

    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 36, 36 * 2 - 12  # placeholder, set below
    scene.frame_start, scene.frame_end = 1, 36
    scene.render.fps = 24
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    pl, pr = rig.pose.bones["wingL"], rig.pose.bones["wingR"]
    pl.rotation_mode = pr.rotation_mode = "XYZ"
    for frame in range(1, 37):
        # Three beats per 1.5s loop; wings mirrored about the body plane.
        phase = 2 * math.pi * 3 * (frame - 1) / 36
        angle = math.radians(args.amp) * math.sin(phase)
        pl.rotation_euler = (0, 0, angle)
        pr.rotation_euler = (0, 0, -angle)
        pl.keyframe_insert("rotation_euler", frame=frame)
        pr.keyframe_insert("rotation_euler", frame=frame)
    bpy.ops.object.mode_set(mode="OBJECT")

    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    height = max(v.z for v in bb) - min(v.z for v in bb)
    rig.scale = (args.height / height,) * 3

    obj.data.materials.clear()
    obj.data.materials.append(flat_material())
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    obj.name = "reference.vogel"

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
    cam.location = (1.4, -3.4, 1.5)
    d = Vector((0, 0, 0.3)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    for frame in (1, 4, 7, 10):
        scene.frame_set(frame)
        scene.render.filepath = f"{args.out_dir}/{args.name}-flap-f{frame:02d}.png"
        bpy.ops.render.render(write_still=True)

    # No stowaway cameras or lights in shipped assets: the app builds its own rig, and
    # extra cameras from the USDZ can hijack or crash the device renderer (found 2026-07-30:
    # three cameras + nine lights inside prep3d-story-fuer trapped RealityKit on iPhone).
    for _o in [o for o in bpy.data.objects if o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(_o, do_unlink=True)
    bpy.ops.object.select_all(action="SELECT")
    try:
        bpy.ops.wm.usd_export(
            filepath=f"{args.out_dir}/{args.name}-flap.usdz", export_materials=True,
            export_animation=True, export_armatures=True, convert_orientation=True)
    except TypeError:
        bpy.ops.wm.usd_export(
            filepath=f"{args.out_dir}/{args.name}-flap.usdz", export_materials=True,
            export_animation=True, convert_orientation=True)
    print("VOGEL_DONE")


main()
