"""[3d-android spike] Headless driver: build scenes with the (copied) pipeline functions and export
USDZ + GLB (export_glb is called inside the patched export_usdz). Skips the judge/storyboard renders.

  Blender --background --python glb_driver.py -- OUT_DIR figur-aufbau verb:helfen kasus:geben
"""
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
argv = sys.argv[sys.argv.index("--") + 1:]
out_dir, jobs = os.path.abspath(argv[0]), argv[1:]
os.makedirs(out_dir, exist_ok=True)

import figur  # noqa: E402

for job in jobs:
    if job == "figur-aufbau":
        # The export half of figur.scene_aufbau (same calls, minus the storyboard render).
        figur._LOD = "low"
        figur.clear_scene()
        figur.setup_render(256)
        objects, p = figur.build_figure("standard", 1.8)
        figur.keyframe_aufbau(objects, p)
        out = os.path.join(out_dir, "figur-aufbau.usdz")
        twin = os.path.join(out_dir, "figur-aufbau.usda")
        bpy.ops.wm.usd_export(filepath=twin, export_materials=True, export_animation=True,
                              convert_orientation=True)
        figur.export_usdz(out, animated=True)
        figur.verify_animation(twin)
    elif job.startswith("verb:"):
        import verben
        ok = verben.export([job[5:]], out_dir=out_dir)
        print("VERB", job, ok)
    elif job.startswith("kasus:"):
        import kasus_szenen
        ok = kasus_szenen.export([job[6:]], out_dir)
        print("KASUS", job, ok)
    else:
        raise SystemExit(f"unknown job {job}")
