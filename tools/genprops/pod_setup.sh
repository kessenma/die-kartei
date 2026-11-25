#!/usr/bin/env bash
# One-time setup on a fresh runpod/pytorch pod for shape-only 3D generation.
# SDXL-Turbo makes the concept image; Hunyuan3D-2 (shape pipeline only, no texture
# rasterizer to compile) turns it into a mesh. Geometry is all we want — the app
# retints everything flat at runtime.
#
# Learnings baked in from the first session (2026-07-30):
#   - The image's python is PEP 668 "externally managed" AND the non-interactive PATH
#     resolves the wrong interpreter — use /usr/local/bin/python explicitly, with
#     --break-system-packages (the pod is disposable).
#   - No pymeshlab: its filter names drift between versions; decimation happens on the
#     Mac in Blender (convert_prop.py) anyway.
set -euo pipefail

export HF_HOME=/workspace/hf
mkdir -p /workspace/out

PY=/usr/local/bin/python
$PY -m pip install --quiet --break-system-packages --upgrade pip
$PY -m pip install --quiet --break-system-packages \
    hy3dgen diffusers transformers accelerate safetensors trimesh rembg onnxruntime

$PY - <<'PY'
import torch
print("torch", torch.__version__, "cuda", torch.cuda.is_available(),
      torch.cuda.get_device_name(0) if torch.cuda.is_available() else "-")
import hy3dgen
print("hy3dgen ok")
PY
echo SETUP_DONE
