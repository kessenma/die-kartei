"""Rig the cat's upturned tail and bake a flick loop into the USDZ.

Same recipe as rig_dog.py, different anatomy: this tail rises *vertically* from the rump
(probe: base ≈ (0.34, 0.35, -0.75), tip ≈ (0.45, 0.45, -0.20) in raw mesh coords), so the
flick is a horizontal sway — rotation about the bones' local X — rather than the dog's
ground-plane sweep. Two bones, tip lagging the base, 2s loop.
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
    ap.add_argument("--height", type=float, default=1.2)
    ap.add_argument("--faces", type=int, default=18000)
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

    # Tail anchors in RAW mesh coords, captured before any scaling so the probe numbers
    # transfer directly; everything below works in raw coords and scales at the end.
    base = Vector((0.34, 0.35, -0.75))
    tip = Vector((0.45, 0.45, -0.20))

    if len(obj.data.polygons) > args.faces:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = args.faces / len(obj.data.polygons)
        bpy.ops.object.modifier_apply(modifier="dec")

    axis = tip - base
    length = axis.length
    direction = axis.normalized()

    mesh = obj.data
    g_root = obj.vertex_groups.new(name="root")
    g_t1 = obj.vertex_groups.new(name="tail1")
    g_t2 = obj.vertex_groups.new(name="tail2")
    for v in mesh.vertices:
        rel = v.co - base
        t = rel.dot(direction) / length
        radial = (rel - rel.dot(direction) * direction).length
        if t > -0.05 and radial < 0.26:
            tt = max(0.0, min(1.0, t))
            fade = min(1.0, (tt + 0.05) / 0.25)
            w2 = max(0.0, min(1.0, (tt - 0.35) / 0.4))
            w1 = fade * (1 - w2)
            w2 *= fade
            if w1 > 0:
                g_t1.add([v.index], w1, "REPLACE")
            if w2 > 0:
                g_t2.add([v.index], w2, "REPLACE")
            if fade < 1:
                g_root.add([v.index], 1 - fade, "REPLACE")
        else:
            g_root.add([v.index], 1.0, "REPLACE")

    arm = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    b_root = arm.edit_bones.new("root")
    b_root.head, b_root.tail = Vector((0, 0, -0.9)), Vector((0, 0, -0.5))
    mid = base + axis * 0.5
    b1 = arm.edit_bones.new("tail1")
    b1.head, b1.tail = base, mid
    b1.parent = b_root
    b2 = arm.edit_bones.new("tail2")
    b2.head, b2.tail = mid, tip
    b2.parent = b1
    b2.use_connect = True
    bpy.ops.object.mode_set(mode="OBJECT")

    mod = obj.modifiers.new("arm", "ARMATURE")
    mod.object = rig
    obj.parent = rig

    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, 48
    scene.render.fps = 24
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    p1, p2 = rig.pose.bones["tail1"], rig.pose.bones["tail2"]
    p1.rotation_mode = p2.rotation_mode = "XYZ"
    for frame in range(1, 49):
        phase = 2 * math.pi * 2 * (frame - 1) / 48
        # Local X on a near-vertical bone = horizontal sway; verified by the phase renders.
        p1.rotation_euler = (math.radians(16) * math.sin(phase), 0, 0)
        p2.rotation_euler = (math.radians(26) * math.sin(phase - 0.9), 0, 0)
        p1.keyframe_insert("rotation_euler", frame=frame)
        p2.keyframe_insert("rotation_euler", frame=frame)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Normalize to app scale AFTER rigging (armature parents along), then flatten material.
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    height = max(v.z for v in bb) - min(v.z for v in bb)
    s = args.height / height
    rig.scale = (s,) * 3

    obj.data.materials.clear()
    obj.data.materials.append(flat_material())
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    obj.name = "reference.katze"

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
    cam.location = (2.2, -5.2, 2.2)
    d = Vector((0, 0, 0.5)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    for frame in (1, 7, 13, 19):
        scene.frame_set(frame)
        scene.render.filepath = f"{args.out_dir}/katze-flick-f{frame:02d}.png"
        bpy.ops.render.render(write_still=True)

    # No stowaway cameras or lights in shipped assets: the app builds its own rig, and
    # extra cameras from the USDZ can hijack or crash the device renderer (found 2026-07-30:
    # three cameras + nine lights inside prep3d-story-fuer trapped RealityKit on iPhone).
    for _o in [o for o in bpy.data.objects if o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(_o, do_unlink=True)
    bpy.ops.object.select_all(action="SELECT")
    try:
        bpy.ops.wm.usd_export(
            filepath=f"{args.out_dir}/katze-flick.usdz", export_materials=True,
            export_animation=True, export_armatures=True, convert_orientation=True)
    except TypeError:
        bpy.ops.wm.usd_export(
            filepath=f"{args.out_dir}/katze-flick.usdz", export_materials=True,
            export_animation=True, convert_orientation=True)
    print("KATZE_DONE")


main()
