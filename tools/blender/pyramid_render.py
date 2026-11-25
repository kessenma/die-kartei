#!/usr/bin/env python3
"""
pyramid_render.py — Blender rig for the Lernpyramide assets (SPEC / SCAFFOLD).

STATUS: spec only — the app ships a procedural stack today (`PyramidSceneView` builds the six
slabs + capstone ball in code). This rig replaces those placeholders with rendered geometry when
authored. Until then nothing here is invoked; `render_all.sh` does not call it yet.

What ships when built (mirrors the preposition pipeline, `prep_render.py`):

  Assets      Resources/pyramid-layer-<n>-<state>-dim.png   stills (n = 1…6 bottom→top,
                                                            state = ghost | building | solid)
              Resources/pyramid.usdz                        one scene, slabs named "layer1"…
                                                            "layer6" plus "capstone" (the ball),
                                                            so the app can ghost/tint per layer
                                                            at runtime (same trick as the prep
                                                            scenes' "subject" convention)

  Geometry    Six stacked slabs, Bauhaus vocabulary: flat charcoal slabs, width shrinking
              2.5 → 0.7 in 0.36 steps, height 0.30, gap 0.05 (matches the procedural fallback,
              so swapping render for code changes nothing about the framing). Capstone: the
              preposition scenes' sphere (r 0.17) on the peak. All from `add_box` / `add_sphere`
              in the existing rig — no sculpted meshes.

  Materials   `make_material(...)` charcoal family for structure; each layer carries its accent
              only in the `solid` state (Fundament orange → … → Spitze green — see
              `PyramidLayerID.tint`). `ghost` = neutral grey, no accent; `building` = accent at
              reduced saturation. USDZ ships the *solid* state only — ghosting is a runtime
              opacity, exactly like the prep scenes' runtime tint.

  Camera      `setup_camera("dim")` unchanged: raked three-quarter framing. The app's canvas
              builds its own camera/lights anyway (USDZ is geometry-only by contract —
              `stripCamerasAndLights` strips anything that sneaks in).

  States      ghost    — empty lot (outline feel, stills only)
              building — accent arriving
              solid    — finished layer

TODO when authoring:
  [ ] build(layer) using RELATIONS-style table: width/height/gap + accent per layer
  [ ] render_loop for the 18 stills (6 layers × 3 states, dim look only)
  [ ] export_usdz with per-slab naming for runtime ghost/tint
  [ ] wire into render_all.sh; drop Resources PNGs; verify app size delta
  [ ] then delete the procedural `buildStack()` fallback in PyramidView.swift
"""

# Intentionally no executable code yet — see the spec above.
