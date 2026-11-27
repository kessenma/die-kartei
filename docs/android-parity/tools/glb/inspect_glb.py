"""Inspect GLB files: parse the JSON chunk + read animation input accessors from the BIN chunk.
usage: python3 inspect_glb.py out/*.glb [--json report.json]"""
import json
import os
import struct
import sys

COMP = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2, path
    off, gltf, binc = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<I4s", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == b"JSON":
            gltf = json.loads(chunk)
        elif ctype == b"BIN\x00":
            binc = chunk
        off += 8 + clen
    return gltf, binc


def accessor_values(g, b, i):
    a = g["accessors"][i]
    bv = g["bufferViews"][a["bufferView"]]
    fmt, size = COMP[a["componentType"]]
    n = NCOMP[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", size * n)
    return [struct.unpack_from("<" + fmt * n, b, start + k * stride) for k in range(a["count"])]


def report(path):
    g, b = load(path)
    nodes = g.get("nodes", [])
    names = [n.get("name") for n in nodes]
    tris = 0
    for m in g.get("meshes", []):
        for p in m["primitives"]:
            if "indices" in p:
                tris += g["accessors"][p["indices"]]["count"] // 3
    anims = []
    for a in g.get("animations", []):
        times = set()
        paths, targets = {}, set()
        for ch in a["channels"]:
            s = a["samplers"][ch["sampler"]]
            times.update(v[0] for v in accessor_values(g, b, s["input"]))
            t = ch["target"]
            paths[t["path"]] = paths.get(t["path"], 0) + 1
            targets.add(names[t["node"]] if "node" in t else "?")
        anims.append({"name": a.get("name"), "channels": len(a["channels"]), "paths": paths,
                      "nodes": sorted(targets), "start": round(min(times), 3) if times else None,
                      "end": round(max(times), 3) if times else None,
                      "keys": len(times),
                      "interp": sorted({s.get("interpolation", "LINEAR") for s in a["samplers"]})})
    mats = []
    for m in g.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        mats.append({"name": m.get("name"), "base": [round(x, 3) for x in pbr.get("baseColorFactor", [1, 1, 1, 1])],
                     "metal": pbr.get("metallicFactor", 1), "rough": pbr.get("roughnessFactor", 1),
                     "emissive": m.get("emissiveFactor"), "ext": sorted(m.get("extensions", {})),
                     "alpha": m.get("alphaMode", "OPAQUE"), "tex": "baseColorTexture" in pbr})
    return {"file": os.path.basename(path), "bytes": os.path.getsize(path),
            "extensionsUsed": g.get("extensionsUsed", []), "nodes": len(nodes), "node_names": names,
            "meshes": len(g.get("meshes", [])), "triangles": tris,
            "cameras": len(g.get("cameras", [])),
            "lights": len(g.get("extensions", {}).get("KHR_lights_punctual", {}).get("lights", [])),
            "images": len(g.get("images", [])), "materials": mats, "animations": anims,
            "has_subject": any(n and "subject" in n.lower() for n in names)}


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    reps = [report(p) for p in args if p.endswith(".glb")]
    for r in reps:
        print(f"== {r['file']}  {r['bytes']/1024:.1f} KiB  nodes={r['nodes']} meshes={r['meshes']} "
              f"tris={r['triangles']} cams={r['cameras']} lights={r['lights']} images={r['images']} "
              f"subject={r['has_subject']} ext={r['extensionsUsed']}")
        print("   names:", ", ".join(str(n) for n in r["node_names"][:40]) + (" …" if r["nodes"] > 40 else ""))
        for a in r["animations"]:
            print(f"   anim '{a['name']}': {a['channels']} ch {a['paths']} t={a['start']}..{a['end']}s "
                  f"keys={a['keys']} interp={a['interp']} nodes={a['nodes'][:12]}{' …' if len(a['nodes']) > 12 else ''}")
        for m in r["materials"]:
            print(f"   mat {m['name']}: base={m['base']} metal={m['metal']} rough={m['rough']} "
                  f"emis={m['emissive']} ext={m['ext']} alpha={m['alpha']} tex={m['tex']}")
    if out:
        json.dump(reps, open(out, "w"), indent=1)
