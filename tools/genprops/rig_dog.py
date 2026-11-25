"""Rig the generated dog with a two-bone tail and bake a wag loop into the USDZ.

The tail is selected by *geometry*, not by hand: vertices are weighted by how far they sit
along the tail axis (base → tip), gated by distance to that axis so the haunch at the same
depth stays still. Root bone holds everything else rigid. The wag is a two-bone sine with a
phase lag — base leads, tip follows — baked at 24fps over a clean 2s loop.

Verification renders (top view, four phases) come out beside the USDZ; judge those before
trusting the export.
"""

import argparse
import math
import sys

import bpy
from mathutils import Vector

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
    links.new(shader.outputs[0], out.inputs["Surface"])
    return mat


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--height", type=float, default=1.4)
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

    # Decimate, ground, center, scale — same treatment as convert_prop.py.
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

    obj.name = "reference.dog"
    obj.data.materials.clear()
    obj.data.materials.append(flat_material())
    bpy.ops.object.shade_smooth()

    # Tail axis, in the probe's normalized frame scaled to the new size: base just off the
    # rump, tip at the far end of the sweep. (Probe: tip lower-left in top view.)
    s = args.height / 2.0  # rough scale reference; positions below are in scene units
    base = Vector((-0.22, 0.02, 0.10)) * (args.height / 1.4)
    tip = Vector((-0.62, -0.42, 0.05)) * (args.height / 1.4)
    axis = (tip - base)
    length = axis.length
    direction = axis.normalized()

    # Weights: t = progress along the axis; gate by distance to the axis line.
    mesh = obj.data
    g_root = obj.vertex_groups.new(name="root")
    g_t1 = obj.vertex_groups.new(name="tail1")
    g_t2 = obj.vertex_groups.new(name="tail2")
    for v in mesh.vertices:
        rel = v.co - base
        t = rel.dot(direction) / length
        radial = (rel - rel.dot(direction) * direction).length
        # Inside the tail tube: past the base, near the axis, near the ground.
        if t > -0.05 and radial < 0.30 * (args.height / 1.4) and v.co.z < 0.35:
            tt = max(0.0, min(1.0, t))
            fade = min(1.0, (tt + 0.05) / 0.25)          # blend in at the base
            w2 = max(0.0, min(1.0, (tt - 0.35) / 0.4))   # tip bone takes over past mid
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

    # Armature: root (static) + two tail bones down the axis.
    arm = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    b_root = arm.edit_bones.new("root")
    b_root.head, b_root.tail = Vector((0, 0, 0)), Vector((0, 0, 0.3))
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

    # The wag: horizontal sweep = rotation about the world-Z through each bone head. A bone's
    # local +Y runs head→tail, so world-Z maps to the bone's local Z projected — keyframe on
    # rotation_euler Z after setting XYZ mode, verified by the phase renders below.
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = 1, 48
    scene.render.fps = 24
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    p1, p2 = rig.pose.bones["tail1"], rig.pose.bones["tail2"]
    p1.rotation_mode = p2.rotation_mode = "XYZ"
    for frame in range(1, 49):
        phase = 2 * math.pi * 2 * (frame - 1) / 48   # two full wags per loop
        p1.rotation_euler = (0, 0, math.radians(22) * math.sin(phase))
        p2.rotation_euler = (0, 0, math.radians(30) * math.sin(phase - 0.9))
        p1.keyframe_insert("rotation_euler", frame=frame)
        p2.keyframe_insert("rotation_euler", frame=frame)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Verification: top-view renders at four wag phases.
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.view_settings.view_transform = "Standard"
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.4
    scene.collection.objects.link(cam)
    cam.location = Vector((0, 0, 4.0))
    cam.rotation_euler = (0, 0, 0)
    scene.camera = cam
    for frame in (1, 7, 13, 19):
        scene.frame_set(frame)
        scene.render.filepath = f"{args.out_dir}/wag-f{frame:02d}.png"
        bpy.ops.render.render(write_still=True)

    # No stowaway cameras or lights in shipped assets: the app builds its own rig, and
    # extra cameras from the USDZ can hijack or crash the device renderer (found 2026-07-30:
    # three cameras + nine lights inside prep3d-story-fuer trapped RealityKit on iPhone).
    for _o in [o for o in bpy.data.objects if o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(_o, do_unlink=True)
    bpy.ops.object.select_all(action="SELECT")
    try:
        bpy.ops.wm.usd_export(
            filepath=f"{args.out_dir}/dog-wag.usdz",
            export_materials=True,
            export_animation=True,
            export_armatures=True,
            convert_orientation=True,
        )
    except TypeError:
        # Older exporter without the armature switch — animation export implies it.
        bpy.ops.wm.usd_export(
            filepath=f"{args.out_dir}/dog-wag.usdz",
            export_materials=True,
            export_animation=True,
            convert_orientation=True,
        )
    print("RIG_DONE")


main()
