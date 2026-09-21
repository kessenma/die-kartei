"""Convert a Gemma 4 E-series HF checkpoint to MLX 4-bit when mlx_lm refuses it.

mlx_lm 0.31.3 rejects the k_proj/v_proj/k_norm tensors of Gemma 4 E-series KV-shared layers
(54 tensors, layers 24-41 on E4B) that the HF checkpoint carries but the MLX model does not define.
Drop them in sanitize() and convert as usual. Same result the Aug-17 conversion produced.

Usage (from training/):
  .venv/bin/python scripts/convert_gemma4_patched.py models/<name>-merged models/<name>-4bit

Measured 2026-09-06: the v4 merge that converted fine on 2026-08-17 fails identically with today's
mlx_lm, so this is the tool, not the checkpoint (REINFORCEMENT_LEARNING.md Part B)."""
import json, re, sys
import mlx_lm.models.gemma4 as g
from mlx_lm import convert

src, dst = sys.argv[1], sys.argv[2]
cfg = json.load(open(f"{src}/config.json"))
tc = cfg.get("text_config", cfg)
n_layers = tc.get("num_hidden_layers"); n_shared = tc.get("num_kv_shared_layers")
first_shared = (n_layers - n_shared) if (n_layers and n_shared) else 24
print(f"layers {n_layers}, kv-shared {n_shared} -> dropping k/v/k_norm for layers >= {first_shared}")

_orig = g.Model.sanitize
def sanitize(self, weights):
    w = _orig(self, weights)
    pat = re.compile(r"language_model\.model\.layers\.(\d+)\.self_attn\.(k_proj|v_proj|k_norm)\.weight$")
    drop = [k for k in w if (m := pat.match(k)) and int(m.group(1)) >= first_shared]
    for k in drop: w.pop(k)
    print(f"sanitize: dropped {len(drop)} unused kv-shared-layer tensors")
    return w
g.Model.sanitize = sanitize

convert(src, mlx_path=dst, quantize=True, q_bits=4, q_group_size=64)
print("CONVERT_DONE")
