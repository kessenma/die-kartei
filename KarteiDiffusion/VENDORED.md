# Vendored from turbo-mlx

The picture engine in `Sources/KarteiDiffusion` is a trimmed copy of turbo-mlx's native engine.

- **Upstream:** https://github.com/rinste/turbo-mlx, `Engine/Sources/TurboEngineCore`
- **Commit:** `24359c28aed6d4656bc7f8f37461d8f2f37336dc` (2026-10-02)
- **License:** MIT, copyright 2026 Stefano Rinaldo. See `LICENSE`. The notice also has to appear in
  the app's acknowledgements.

## Why vendored, not a package dependency

turbo-mlx's package asks for mlx-swift ≥ 0.32.2. The app's tutors come from mlx-swift-lm 3.31.x,
which pins mlx-swift `upToNextMinor(0.31.4)`, and bumping that pair risks the Gemma-4 tutors. This
copy builds against mlx-swift 0.31.x, so the app links one MLX.

The engine's own use of MLX compiled unchanged on 0.31.6 (`quantizeSingle(…mode:)`, `Memory.*`).
mlx-swift 0.32's changes are Device/Stream semantics and logging, and 0.32.2 crashes at launch on
OS versions before 26.4.

## What's kept

Only the two families Die Kartei draws with: Z-Image Turbo and FLUX.2 klein 4B. Upstream paths are
kept as they are, so a refresh is a copy.

| Here | Upstream |
|---|---|
| `Checkpoint.swift`, `ImageOutput.swift`, `Provenance.swift` | same names |
| `Families/Family.swift` | same, **loader trimmed** (see below) |
| `Families/Klein/*` | `Families/Klein/*` |
| `Families/ZImage/*` | `Families/ZImage/*` |
| `Families/Shared/*` | `Families/Shared/*` (all ten files) |
| `Tokenizer/*` | `Tokenizer/*` |

Left out: `Engine.swift` and `Protocol.swift` (the JSON-over-stdio engine), the `turbo-engine`
executable, video output, and the LTX, Ming, Qwen-Image, SenseNova and SeedVR2 families with
SeedVR2's resource file.

## Local changes

Each change is listed here so a refresh can re-apply it.

1. **`Families/Family.swift`:** `FamilyLoader` is replaced. Upstream switches over nine families
   from a JSON `ModelSpec`. Here, `FamilyLoader.load(_ family: Family, modelPath:loadTokenizer:)`
   takes `.zImageTurbo` or `.flux2Klein4B`.
2. **`Support.swift`** (new) holds the two symbols the kept files use from left-out files:
   - `Emitter` (upstream `Protocol.swift`): `log(_:)` goes to `os.Logger` instead of stdout.
   - `roundHalfEven` (upstream `LTXMedia.swift`): copied as is.
3. **Releasing the prompt reader**, in `ZImagePipeline.swift`, `KleinPipeline.swift` and
   `Family.swift`:
   - `textEncoder` becomes an optional `var`.
   - A new `releasesPromptReader` (on the `FamilyModel` protocol too) makes `promptsEncoded()` drop
     it.
   - `encodePrompt` reads it back from the checkpoint when it's gone (`residentTextEncoder()`).
   - Upstream keeps the 2–4 GB Qwen3 encoder resident. Releasing it is what lets a 16 GB Mac draw
     Z-Image at 1024 px (5.6 GB peak) and klein at 768 px.
   - Separate from `lowRam`, which still only tiles Z-Image's decoder.

The app shows the MIT notice in Settings ▸ Sources (Mac only).

## Checked against mflux

`kartei-diffusion-probe` renders the bake-off prompts. `Tools/parity.py` (also in the gitignored
`training/imagegen/bakeoff/`)
compares them with mflux 0.20 on the same prompts, seed and size.

- **Z-Image Turbo 4-bit, 1024²:** PSNR 53.6 / 38.9 / 29.8 dB on c1 / a1 / s1. The 29.8 dB image is
  the same picture by eye; only the small dove's spots differ.
- **FLUX.2 klein 4B 4-bit** (`mflux-community/flux2-klein-4b-mflux-q4`), 1024²: PSNR 35.0 /
  29.8 dB on c1 / s1.
- **Speed and peak on an M1 Max.** "Released" is the prompt reader released after encoding (local
  change 3) with Z-Image's decoder tiled:

  | | 512² | 768² | 1024² |
  |---|---|---|---|
  | Z-Image, released | 33 s, 5.6 GB | 64 s, 5.6 GB | 122 s, 5.6 GB |
  | Z-Image, resident | 31–34 s, 7.6 GB | 65 s, 7.6 GB | 124–139 s, 12.1 GB (untiled) |
  | klein, released | 13 s, 4.7 GB | 24 s, 7.1 GB | 44 s, 11.0 GB |
  | klein, resident | 13 s, 6.3 GB | 24 s, 8.8 GB | 45 s, 12.7 GB |
  | mflux (reference) | Z-Image 38 s, klein 12 s | Z-Image 71 s, klein 22 s | Z-Image 144 s, klein 38 s |

## Refreshing from upstream

1. Copy the kept files from the new upstream commit over these.
2. Re-apply the local changes above.
3. Build `kartei-diffusion-probe` and re-run the parity check.
4. Update the commit hash here.
