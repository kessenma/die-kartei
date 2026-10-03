"""PSNR between the Swift engine's pictures and mflux's for the same prompt, seed and size.
usage: parity.py <swift dir> <mflux dir> [ids...]"""
import sys, os, math
import numpy as np
from PIL import Image
a, b = sys.argv[1], sys.argv[2]
ids = sys.argv[3:] or sorted(f[:-4] for f in os.listdir(a) if f.endswith(".png"))
for i in ids:
    x = np.asarray(Image.open(f"{a}/{i}.png").convert("RGB"), dtype=np.float64)
    y = np.asarray(Image.open(f"{b}/{i}.png").convert("RGB"), dtype=np.float64)
    if x.shape != y.shape:
        print(i, "shape", x.shape, y.shape); continue
    mse = ((x - y) ** 2).mean()
    psnr = float("inf") if mse == 0 else 20 * math.log10(255 / math.sqrt(mse))
    print(f"{i}: PSNR {psnr:.1f} dB  (max abs diff {np.abs(x-y).max():.0f})")
