"""The story cast (PROPS_PLAN.md): text → concept image → shape-only mesh, raw GLB out.

SDXL-Turbo draws the concept (1 step, seeded); Hunyuan3D-2's shape pipeline lifts it to a
mesh. No texture stage and no on-pod decimation — the app tints geometry flat at runtime,
and Blender decimates during conversion (convert_prop.py), so raw shape is the entire
deliverable here.

Risky props (furniture/architecture, per the house lesson) render two seeds so the judge
step can pick; organisms and simple objects get one.
"""

import os

import torch
from diffusers import AutoPipelineForText2Image
from hy3dgen.rembg import BackgroundRemover
from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline

STYLE = ("smooth solid matte gray material, no texture, plain white background, "
         "soft studio lighting, 3d render")

# name → (prompt, seeds). Two seeds = pilot flagged the category as retry-prone.
PROPS = {
    "katze": (f"a simple minimalist toy figurine of a sitting cat with an upright tail, {STYLE}", [7]),
    "vogel": (f"a simple minimalist toy figurine of a small round bird with folded wings, {STYLE}", [7]),
    "knochen": (f"a simple cartoon dog bone, {STYLE}", [7]),
    "napf": (f"a simple empty dog food bowl, {STYLE}", [7]),
    "kissen": (f"a simple soft square pillow, {STYLE}", [7]),
    "sofa": (f"a simple minimalist two-seat sofa, blocky, {STYLE}", [7, 21]),
    "huette": (f"a minimal doghouse with a pitched roof and an arched door opening, {STYLE}", [7, 21]),
    "baum": (f"a simple toy tree, round foliage ball on a short trunk, {STYLE}", [7, 21]),
}

t2i = AutoPipelineForText2Image.from_pretrained(
    "stabilityai/sdxl-turbo", torch_dtype=torch.float16, variant="fp16"
).to("cuda")
shape = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained("tencent/Hunyuan3D-2")
rembg = BackgroundRemover()

for name, (prompt, seeds) in PROPS.items():
    for seed in seeds:
        tag = name if len(seeds) == 1 else f"{name}-s{seed}"
        raw = f"/workspace/out/{tag}-raw.glb"
        if os.path.exists(raw):
            print(f"=== {tag}: exists, skipping", flush=True)
            continue
        print(f"=== {tag}", flush=True)
        image = t2i(
            prompt=prompt, num_inference_steps=1, guidance_scale=0.0,
            generator=torch.Generator("cuda").manual_seed(seed),
        ).images[0]
        image.save(f"/workspace/out/{tag}-concept.png")
        image = rembg(image)
        mesh = shape(image=image)[0]
        mesh.export(raw)
        print(f"{tag}: exported", flush=True)

print("GEN_DONE", flush=True)
