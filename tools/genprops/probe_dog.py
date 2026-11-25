"""Probe: find the dog's tail region. Colors vertices inside a candidate box red and renders
top + side views so the box can be tuned by eye before committing to a rig."""

import argparse
import math
import sys

import bpy
from mathutils import Vector


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--out-dir", required=True)
    # Candidate tail box in normalized coords (0..1 over the bounding box, x/y/z min/max).
    ap.add_argument("--box", nargs=6, type=float, required=True)
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

    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    size = hi - lo
    x0, x1, y0, y1, z0, z1 = args.box
    bmin = lo + Vector((x0 * size.x, y0 * size.y, z0 * size.z))
    bmax = lo + Vector((x1 * size.x, y1 * size.y, z1 * size.z))
    print("bbox lo", tuple(round(v, 3) for v in lo), "hi", tuple(round(v, 3) for v in hi))

    # Vertex-color the candidate region red, everything else gray.
    mesh = obj.data
    layer = mesh.color_attributes.new("probe", "BYTE_COLOR", "POINT")
    inside = 0
    for i, v in enumerate(mesh.vertices):
        hit = all(bmin[k] <= v.co[k] <= bmax[k] for k in range(3))
        layer.data[i].color = (1, 0.1, 0.1, 1) if hit else (0.62, 0.62, 0.65, 1)
        inside += hit
    print(f"vertices in box: {inside} / {len(mesh.vertices)}")

    mat = bpy.data.materials.new("probe")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "probe"
    links.new(attr.outputs["Color"], em.inputs["Color"])
    links.new(em.outputs[0], out.inputs["Surface"])
    mesh.materials.clear()
    mesh.materials.append(mat)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.view_settings.view_transform = "Standard"

    center = (lo + hi) / 2
    span = max(size.x, size.y, size.z)
    for name, offset, up in (
        ("top", Vector((0, 0, span * 2.2)), "Y"),
        ("side", Vector((0, -span * 2.2, 0)), "Z"),
        ("back", Vector((-span * 2.2, 0, 0)), "Z"),
    ):
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = span * 1.25
        scene.collection.objects.link(cam)
        cam.location = center + offset
        d = center - cam.location
        cam.rotation_euler = d.to_track_quat("-Z", up).to_euler()
        scene.camera = cam
        scene.render.filepath = f"{args.out_dir}/probe-{name}.png"
        bpy.ops.render.render(write_still=True)
    print("PROBE_DONE")


main()
