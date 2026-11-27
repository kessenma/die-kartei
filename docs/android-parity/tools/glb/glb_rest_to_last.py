"""Rewrite each animated node's rest TRS in a GLB to the LAST keyframe of its animation channel.

Why: Blender's glTF exporter writes node TRS from the scene start, so a one-shot clip (figur-aufbau)
rests *scattered*, and SceneView/gltfio show the rest pose once a non-looping clip ends.
usage: python3 glb_rest_to_last.py in.glb [out.glb]   (in place if out omitted)"""
import json
import struct
import sys

sys.path.insert(0, __import__("os").path.dirname(__file__))
from inspect_glb import accessor_values, load  # noqa: E402


def main(src, dst):
    g, b = load(src)
    changed = 0
    for anim in g.get("animations", []):
        for ch in anim["channels"]:
            path = ch["target"]["path"]
            if path not in ("translation", "rotation", "scale"):
                continue
            last = accessor_values(g, b, anim["samplers"][ch["sampler"]]["output"])[-1]
            g["nodes"][ch["target"]["node"]][path] = [float(x) for x in last]
            changed += 1
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    bn = b + b"\0" * (-len(b) % 4)
    total = 12 + 8 + len(js) + (8 + len(bn) if bn else 0)
    with open(dst, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        if bn:
            f.write(struct.pack("<I4s", len(bn), b"BIN\x00") + bn)
    print(f"{dst}: {changed} channel rest values set to last key")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
