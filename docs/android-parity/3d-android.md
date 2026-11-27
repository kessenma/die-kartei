# Die Kartei on Android: 3D rendering options, GLB asset proof, SceneView spike

Date: 2026-11-27. Worked in a scratch copy of the repo (called `3d-work/` below; the GLB export change is in `tools/glb/glb-export.patch`, screenshots in `shots/3d-android-*.png`).
Nothing in `die-kartei` or `die-kartei-android` was edited or built (I only read files there). The spike is a separate app,
`com.kessenma.kartei3dspike`, installed on emulator-5554. `com.kessenma.diekartei` was not touched.

**Summary**
- **Recommendation: SceneView `io.github.sceneview:sceneview:4.76.0`** (Apache-2.0, Compose-native Filament), wrapped
  in a small transpiled Skip Lite module `Kartei3D`. Plain Filament/gltfio is the fallback if SceneView's size or
  toolchain floor becomes a problem.
- **Asset pipeline proven.** Copies of the Blender scripts, with one added `export_glb()` call, export **all 82
  shipped scenes** to GLB headless in **35 s**: figur-aufbau, 37 prep3d, 39 verb3d, 5 kasus3d. Node names such as
  `subject`, `figur_*` and `*_bewegt` survive. Every GLB has 0 cameras and 0 lights. Baked TRS clips come out as one
  glTF animation per scene. Materials are glTF PBR. Total size is **13.6 MB raw / 7.7 MB gzipped, against 26.2 MB
  of shipped USDZ**.
- **Rendering proven** on emulator-5554. The figure assembles itself over a transparent background with Compose
  behind it. A two-figure verb clip and a kasus clip play. A prep3d `subject` is found by name, tinted, and moved
  every frame from code.
- **APK cost measured:** +10.9 MB for an arm64-only release APK with native libraries stored uncompressed. I estimate
  about +6.6 MB with the real app's `useLegacyPackaging=true`. A universal APK with 4 ABIs is +32.7 MB.
- **Two gotchas found** (details in §3.4):
  1. SceneView's non-looping playback snaps back to t=0 when the clip ends, so the runtime must drive the `Animator`
     itself and clamp to the last frame.
  2. SceneView 4.76 pulls Compose BOM 2026.09.00, newer than Skip's 2026.05.01.

---

## 1. Options

Capabilities the app needs:
- (a) play baked glTF clips;
- (b) set node transforms per frame from code (prep3d choreography);
- (c) tint materials at runtime;
- (d) transparent background over Compose;
- APK cost, minSdk, and how it embeds in Skip.

| Option | Version / licence / maintenance | (a) baked clips | (b) per-frame nodes | (c) tint | (d) transparent | APK cost (arm64) | minSdk | Skip embedding | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| **SceneView** (`io.github.sceneview:sceneview`) | **4.76.0**, released 2026-11-26; Apache-2.0; ~1.4k★, 187 releases, very active. Uses Filament 1.77.3. Its SwiftUI/Flutter/RN ports reached end of life at 4.68 (Android only now) | ✅ `ModelNode(animationName=…)`, `playAnimation(name|index)`, or `node.animator.applyAnimation(i,t)` **(verified)** | ✅ `node.model.getFirstEntityByName("subject")` plus `engine.transformManager`, or `ModelNode.nodes` **(verified)** | ✅ `MaterialInstance.setParameter("baseColorFactor", SRGB, …)` **(verified)** | ✅ `surfaceType = TextureSurface, isOpaque = false` **(verified)** | **+10.9 MB stored**: 7.45 MB `.so` + 2.2 MB SceneView assets + 1.2 MB dex. About +6.6 MB with compressed `.so` | 24 | Skip Lite module + `ComposeView`/`ContentComposer` | **Pick** |
| **Filament directly** (`com.google.android.filament:filament-android` + `gltfio-android`) | **1.81.0** (2026-11-17); Apache-2.0; Google, 20.8k★ | ✅ `Animator.applyAnimation` | ✅ `TransformManager` | ✅ same API | ✅ `UiHelper.isOpaque=false` + TextureView | ~6 MB `.so` stored (filament + gltfio; no filament-utils unless KTX IBL is needed); no SceneView assets or dex | 19+ | `AndroidView(SurfaceView/TextureView)` in a `ContentComposer` | Fallback. Means writing ~400–600 lines of Kotlin for the render loop, camera, lights, IBL and lifecycle |
| react-native-filament (Margelo) | 1.11.0; MIT; last push 2026-05-27 | ✅ | ✅ | ✅ | ✅ | n/a | n/a | Not usable (needs RN/JSI) | **Evidence only.** React Native's production 3D answer is also "wrap Filament natively and drive it declaratively", the same shape as SceneView + Skip |
| WebView + three.js / `<model-viewer>` | three 0.187.0 (MIT); model-viewer 4.4.0 (Apache-2.0) | ✅ (three `AnimationMixer`; model-viewer `animation-name`) | three: ✅ `getObjectByName`, but every frame crosses JS. model-viewer: ❌ no node-transform API | ✅ | ✅ transparent WebView + `alpha:true` | ~0.7 MB JS, plus WebView process RAM and 0.3–0.8 s cold start | 21 | `AndroidView(WebView)` | No. This is the RN `expo-gl` + react-three-fiber route, which pmndrs themselves flag for "SIGNIFICANT performance issues". It also adds a JS bridge to every reveal and a second rendering engine to test |
| Godot 4 as an Android library | MIT; official "Godot Android library" | ✅ | ✅ (GDScript) | ✅ | possible | tens of MB (not measured) | 24 | Own `GodotFragment`, not a Compose node | Overkill |
| Unity as a Library | proprietary licence | ✅ | ✅ | ✅ | awkward | 20–40 MB+ | 23+ | Own Activity, one instance per process | Overkill, licence cost |
| Rajawali | last push 2023-04 | partial glTF | ✅ | ✅ | ✅ | small | 21 | AndroidView | Unmaintained. No |
| Jetpack XR SceneCore | 1.0.0 stable, 1.1.0-alpha02; Apache-2.0 | ✅ (`GltfModelEntity`) | ✅ | ✅ | n/a | n/a | 34 | n/a | **Android XR headsets and glasses only.** There is no phone renderer. No |

Versions come from Maven Central and Google Maven `maven-metadata.xml`, npm `latest` and the GitHub API, checked
today. SceneView floors from its quickstart are compileSdk 37, AGP ≥ 9.4, Kotlin ≥ 2.3 and JVM target 21. **In
practice the spike built with Skip's toolchain (AGP 9.2.0, Kotlin 2.3.0, JVM 17, compileSdk 37, minSdk 28)** with no
errors or warnings (§3). It doesn't call kotlin-math's inline operators, which is where the JVM-21 floor would bite.

## 2. Part 2: GLB export from the real Blender pipeline

### 2.1 What I changed (copies only)

- I copied `tools/blender`, `tools/genprops` and `german-ai-flashcards/Resources` into `3d-work/repo/`, keeping the
  repo layout so `HERE/../../…` paths resolve.
- `repo/tools/blender/figur.py` and `prep_render.py` each got one line, `export_glb(path, animated)`, after
  `bpy.ops.wm.usd_export` inside `export_usdz`, plus this helper:
  ```python
  bpy.ops.export_scene.gltf(filepath=<usd path>.glb, export_format="GLB", export_yup=True, export_apply=True,
      export_cameras=False, export_lights=False, export_extras=True, export_animations=animated,
      export_animation_mode="SCENE", export_anim_scene_split_object=False,   # ONE clip per scene, named "Scene"
      export_force_sampling=True, export_optimize_animation_size=True)
  ```
  `GLB_MODE=ACTIONS` switches to the exporter default, which writes one animation per action (see 2.3).
- `verben.py` and `kasus_szenen.py` are unchanged. They call `pr.export_usdz` and so get the GLB for free, as the
  earlier audit predicted.
- `repo/tools/blender/glb_driver.py` is a new headless driver. It calls the pipeline's own `figur.keyframe_aufbau`,
  `verben.export([...])` and `kasus_szenen.export([...])` and skips the judge/storyboard renders. Kasus has no
  export-only CLI; its `--ship` also renders stills.
- `3d-work/inspect_glb.py` is a stdlib validator. It parses the JSON chunk and reads the animation input accessors
  from BIN. pygltflib wasn't needed.

### 2.2 Commands (exact)

```sh
cd 3d-work; B=/Applications/Blender.app/Contents/MacOS/Blender; R=repo/tools/blender     # Blender 5.3.0, glTF io 5.3.43
$B --background --python $R/glb_driver.py -- out figur-aufbau verb:helfen kasus:geben    # 1.3 s for aufbau
$B --background --python $R/prep_render.py -- --prep auf --state neutral --look dim --usdz --out out/prep3d-auf.usdz
#   (same for über, mit; the stock CLI, GLB lands next to the USDZ)
GLB_MODE=ACTIONS $B --background --python $R/glb_driver.py -- out/actions figur-aufbau verb:helfen kasus:geben
# full set (all 39 verbs + 5 kasus + aufbau in one session, then 37 prep runs): 35 s total → out/all/ (82 GLB)
python3 inspect_glb.py out/*.glb out/actions/*.glb --json glb-report.json
python3 inspect_glb.py out/all/*.glb --json out/all-report.json
```

### 2.3 Results

| Asset | Nodes (names) | Animation | Materials | Shipped USDZ | Re-exported USDZ | **GLB** | GLB gz |
|---|---|---|---|---|---|---|---|
| figur-aufbau | 6: `figur_arm_l/r, figur_head, figur_leg_l/r, figur_torso` | 1 clip `Scene`, 8 ch (6 T, 2 R), 0.042–3.25 s, 78 keys, LINEAR | `figur` PBR, base 0.033/0.04/0.047, rough 0.62, metal 0 | 65,279 | 36,025 | **54,684** | 16,561 |
| prep3d-auf (two-way) | 13: `figur*`, `reference.leg0..3`, `reference.top`, **`subject`** | none (static, code-driven, as on iOS) | `reference`, `subject` | 107,999 | 49,841 | **76,492** | 25,170 |
| prep3d-über | same shape as auf | none | same | 107,992 | 49,908 | 76,484 | 25,146 |
| prep3d-mit (ambient walk) | 10, incl. `subject`; `world` and `_materials` come in from the imported hund sample | `Scene`, 4 R ch on figur legs/arms, 0.92 s loop | same | 899,234 | 869,963 | **372,096** (19.3k tris; prep scenes aren't decimated) | 290,601 |
| verb3d-helfen (**two figures, two clips + subject motion**) | 16: `figur_*`, `freund_*`, `helfen_bewegt`, `subject` | **1 clip `Scene`, 21 ch** (13 T, 8 R) over 13 nodes, 0–2.04 s | `reference`, `ink_kreide`, `subject` | 83,628 | 53,289 | **104,404** | 30,104 |
| kasus3d-geben | 16: `figur_*`, `kind_*`, `geben_bewegt`, `subject` | `Scene`, 4 ch (T, **S** on `geben_bewegt`, R on both heads), 3.04 s | `reference`, `ink_0e8794`, `subject` | 168,545 | 81,424 | **118,432** | 35,122 |
| **All 82** | every file has `subject` (figur-aufbau has none, by design); cams = lights = 0 everywhere | 46 animated (figur 1, kasus 5/5, verb 37/39, prep 3/37); no file has more than 1 clip in SCENE mode | only `KHR_materials_specular`; no textures | **26.2 MB** | – | **13.6 MB** | **7.7 MB** |

What this settles from the earlier audit's open questions:
- **Multi-clip verb scenes are fine.**
  - In the default `ACTIONS` mode, helfen becomes **13 separate animations**, one per object action (`figur_arm_lAction`…). kasus geben becomes 13 too.
  - The runtime would then have to start all of them together, like the iOS `for animation in availableAnimations` loop.
  - `SCENE` mode with `export_anim_scene_split_object=False` gives **exactly one clip per asset** with every channel.
    This is the export setting to use. Android then plays index 0 / `"Scene"`.
- **Names survive.** `subject`, `figur_*`, `*_bewegt` and `*_halter` come through. Unlike USD, glTF **keeps dots**
  (`reference.leg0`), where USD writes `reference_leg0`. Any name matching shared with iOS must normalise `.`→`_`;
  iOS already uses `contains("subject")`.
- **TRS only, no armatures.** Rotation is written as quaternions. Constant channels are optimised away; kasus geben
  keeps only 4 of 26 channels because the hands are held still by design.
- **The timeline starts at 1/24 s.** Blender frame 1 becomes t=0.042. Harmless, but `export_anim_slide_to_zero=True`
  (or authoring from frame 0) would make it start at 0.
- **Materials:** Principled BSDF becomes metallic-roughness PBR plus `KHR_materials_specular`, which Filament
  supports and the spike rendered. The shipped look is `dim` only. The `flat`/Emission look (→
  `KHR_materials_emissive_strength`) isn't shipped and wasn't tested.
- **Size:**
  - Small static or short scenes are 1.4–2× the *re-exported* USDZ raw, and equal once gzipped (an APK deflates
    assets).
  - Heavy meshes are 0.4×, because USDZ stores float data unaligned and uncompressed.
  - The set is half the shipped USDZ size. Do not ship the `.usda` twins.

Pipeline findings that also matter for iOS:
- **Blender 5.3 re-exports USDZ 30–55 % smaller than the shipped files** (e.g. figur-aufbau 65 KB → 36 KB). The
  shipped set was made by an older exporter or other settings. I didn't compare them further and didn't overwrite
  anything.
- **12 of 39 verb scenes fail the existing USD twin check** under Blender 5.3 with the **unmodified** scripts.
  Reproduced with a pristine copy: `verben.py -- --usdz rudel` gives "TimeSamples on non-ambient prim
  'figur_arm_l'…". The failing scenes are rudel, schreiben, sprechen_ueber, erzaehlen, beschweren, bitten,
  sprechen_mit, angeben, handeln, fragen, sehnen and verlangen. GLBs were still written. `verb3d-handeln` and
  `verb3d-verlangen` export **with no animation**; check them before shipping.
- The verb manifest has 39 keys, but only 35 verb USDZ ship. The GLB run produced all 39.

## 3. Part 3: Rendering spike (SceneView on emulator-5554)

### 3.1 Build

`3d-work/spike/` is a standalone Gradle project, package `com.kessenma.kartei3dspike`. It has two flavours: `scene`
(SceneView) and `empty` (same Compose dependencies and GLB assets, no SceneView), so the APK delta is library-only.
The toolchain is pinned to the Skip app's catalog (`skip-unit` skip.yml): AGP 9.2.0, Kotlin compose plugin 2.3.0,
JVM 17, compileSdk 37, minSdk 28.

```sh
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"   # JBR 25; Gradle 9.9.2 (brew)
cd 3d-work/spike && gradle --no-daemon -q :app:assembleSceneDebug :app:assembleSceneRelease :app:assembleEmptyRelease
adb -s emulator-5554 install -r app/build/outputs/apk/scene/debug/app-scene-debug.apk
adb -s emulator-5554 shell am start -S -W -n com.kessenma.kartei3dspike/.MainActivity --es asset figur-aufbau
adb -s emulator-5554 exec-out screencap -p > shots/aufbau-sN.png        # every ~0.3 s, then once after 3 s
adb ... --es asset prep3d-auf --ez choreo true      # subject tint + per-frame offset from code
adb ... --es asset verb3d-helfen --ez loop true     # / kasus3d-geben
```

- Compose BOM 2026.11.01 (Compose 1.13) **fails**: it requires compileSdk 37.1. 2026.09.00 works.
- First successful build of the full workspace: about 2 minutes.

### 3.2 Screenshots (`3d-work/shots/`)

- `aufbau-sequence.png` is a strip of 6 frames:
  - t≈0: splash, then the empty scene while the GLB loads;
  - parts scattered (legs, then the torso falling in);
  - partly assembled (arm flying in);
  - assembled;
  - **assembled and held after 3.25 s** (logcat: `clip held at 3.25s`).
- The individual frames are `aufbau-s0..s5.png` and `aufbau-z-end.png`.
- `scenes-sheet.png` has four panels:
  - `prep-auf-a` / `prep-auf-b`: the ball found by name, **tinted red from code**, and **lifted by the akkOffset
    (0, 1.09, 0) every frame** above the table;
  - `verb-helfen`: two figures lifting the teal box;
  - `kasus-geben`: man, child and the orange ball.
  Compose text and the gradient are visible behind all of them, so transparency works.
- Logcat confirms what loaded:
  - `loaded figur-aufbau animations=1 … anim0=Scene 3.25s`
  - `loaded verb3d-helfen animations=1`
  - `choreo: subject entity=4371`
- Cold start (`am start -W`) was 470–610 ms. `Displayed` came at +612 ms and the model was loaded about 70 ms after
  that.

### 3.3 APK size (release, R8, 4 ABIs because SceneView ships all of them)

| | Size |
|---|---|
| empty flavour (Compose + 4 GLBs) | 1,371,997 B |
| scene flavour, universal | 34,111,692 B (**+32.7 MB**) |
| └ native `.so` per ABI, stored | arm64 7.45 MB (filament-jni 2.96, gltfio-jni 3.09, filament-utils-jni 1.38); armeabi-v7a 5.5; x86 8.0; x86_64 7.9 |
| └ SceneView assets (IBL 2.1 MB + skybox 1.6 MB + 15 `.filamat`) | 8.19 MB raw, **2.17 MB compressed** |
| └ dex | 2.25 MB vs 1.07 MB (**+1.18 MB**) |
| **arm64-only (AAB split / `abiFilters`)** | **≈12.2 MB → +10.9 MB** |
| arm64 with compressed `.so` (the real app sets `useLegacyPackaging = true` for llama.cpp) | `.so` gzip about 3.25 MB, so **≈ +6.6 MB** (estimate) |

Ways to cut it:
- Drop the default skybox, since the canvas is transparent and doesn't need one.
- Ship a small IBL, or none: the app lights with its own rig anyway.
- Possibly drop filament-utils if the IBL isn't KTX.
- Filament directly would save roughly the SceneView dex and assets (~3.3 MB).

### 3.4 Gotchas found in the spike

1. **SceneView's `animationLoop = false` jumps back to the first frame when the clip ends.** For figur-aufbau the end
   screenshot showed the scattered parts again. Rewriting the GLB rest pose (`glb_rest_to_last.py`) didn't help,
   because it evaluates t=0 rather than the rest pose.
   - **Fix (verified):** `autoAnimate = false`. Then in `SceneView(onAnimationFrame = …)` call
     `animator.applyAnimation(0, min(elapsed, duration))` and `updateBoneMatrices()`. Set the callback to `null` once
     the clip is done, which lets the scene park (`FrameRatePolicy.OnDemand`).
   - The Kartei3D module needs this clock anyway, for "frozen on question side, play on reveal" and Reduce Motion
     (apply at t=duration once).
2. **Blender's glTF exporter writes the node rest TRS from frame 1** (aufbau rests scattered). Calling
   `scene.frame_set(frame_end)` before the export did *not* change that. It's harmless when the runtime drives the
   clip; a still or Reduce-Motion pose = `applyAnimation(0, duration)`.
3. **Framing.** Use `autoCenterContent = false` and `autoFitContent = false` with an explicit
   `rememberCameraNode { position; lookAt }` that mirrors iOS (`[4, 3.6, 10.6]` → `[0, 0.4, 0]`). With
   auto-fit/`scaleToUnits`, the scattered rest pose's bounding box gave absurd framing.
   - **Unverified:** an exact FOV match. iOS uses 30° vertical, and SceneView's default lens is wider, so scenes look
     smaller.
   - **Unverified:** a matching light rig. Default SceneView lighting is DPCF shadows, SSAO and bloom. Use
     `RenderQuality.Performance` and the iOS key/rim/fill lights.
4. **Dependency drift.** SceneView 4.76.0's POM pulls `compose-bom 2026.09.00`, `kotlin-stdlib 2.4.21` and
   `filament 1.77.3`. Skip's catalog has Compose BOM **2026.05.01** and Kotlin **2.3.0**, so adding SceneView will
   **upgrade the Skip app's Compose**. That compiled in the spike, but SkipUI on Compose 1.12 isn't verified.
   Fallback: an older SceneView (4.18.0 is the last for AGP 8/compileSdk 36), or Filament directly.

## 4. How it plugs into the Skip app

### 4.1 Module shape

A new Skip Lite module **`Kartei3D`**, a sibling of `GermanVoice` (`mode: 'transpiled'`, `bridging: true`):

```yaml
# Sources/Kartei3D/Skip/skip.yml
skip:
  mode: 'transpiled'
  bridging: true
build:
  contents:
    - block: 'dependencies'
      contents:
        - 'implementation("io.github.sceneview:sceneview:4.76.0")'
```

- **Kotlin side** (in `#if SKIP`): `@Composable fun Kartei3DCanvas(spec: SceneSpec, clock: SceneClock)`. It holds one
  `rememberEngine()` per screen, `rememberModelInstance("models/<asset>.glb")` and an explicit camera.
  `onAnimationFrame` does three things:
  - applies the baked clip (clamped or looped);
  - writes node offsets through `TransformManager` (entities cached by name at load);
  - sets `baseColorFactor` on the tint targets when the tint changes, not every frame.
- **Swift side** (DieKartei, Fuse): `ComposeView { Kartei3DComposer(spec: spec) }` inside `#if os(Android)`, with
  `Kartei3DComposer: ContentComposer` defined in a `#if SKIP` block, as in the skip.dev ComposeView docs.
  - On Android, `SceneCanvas` replaces `RealityView` at the same branch points iOS uses for `LightweightGraphics`.
- **Assets:** GLBs go into Android `assets/models/` (gradle `sourceSets.main.assets`) or the module's Resources.
  `core_sync.py` gets a GLB step.
  - Keep GLBs **out of the iOS bundle**. The exporter writes them to a separate `android-assets/` folder, not to
    `Resources/`.

### 4.2 Swift API sketch (portable spec in DieKarteiCore; renderer per platform)

```swift
public struct SceneSpec: Equatable, Sendable {
    public var asset: String                       // "prep3d-auf", "figur-aufbau", "verb3d-helfen"
    public var clip: Clip = .none                  // .none | .once | .loop  (always the single "Scene" clip)
    public var tint: [String: RGBA] = [:]          // node name → colour, e.g. ["subject": KasusColor.akk]
    public var nodeOffsets: [String: SIMD3<Float>] = [:]   // static pose (neutral/dat/akk)
    public var track: ChoreoTrack? = nil           // per-frame motion, see below
    public var camera: CameraPose = .prepDefault   // eye [4,3.6,10.6] → [0,0.4,0], fov 30
    public var playing: Bool = true                // false = frozen on the question side / Reduce Motion
}
// iOS: RealityKit view reads the same spec. Android:
SceneCanvas(SceneSpec(asset: "prep3d-auf", tint: ["subject": .akk], track: PrepositionChoreography.track(for: rel, case: .akk)))
```

**Per-frame choreography without a per-frame JNI call.** Move the iOS beats (`subjectOffset`, `moverOffset`, `tint`
and `assembly(at:)`, ~200 lines in `PrepositionSceneView`) into Foundation-only `PrepositionChoreography.swift` in
the core. Have it emit a **`ChoreoTrack`**: per node, keyframes `(t, offset, tint?)` plus a loop period, sampled at
30–60 Hz or as easing keys. The Kotlin canvas interpolates the track inside `onAnimationFrame`. The math stays in one
place, and Swift isn't called from Kotlin 60× a second through the bridge. iOS can use the same track or keep its
closure.

## 5. Per-surface rollout (numbers from the earlier audit's A.2)

| Phase | Surfaces | Work | Gate |
|---|---|---|---|
| 0 (now, no 3D) | 1, 3–7, 11 stills; 8 `EndingBlocksFlat` | as in the earlier audit's option 1 (PNG stills) | – |
| 1 | **7 Kasus lesson** (still first, then "Abspielen"), **11 Schreibblatt celebration** | Kartei3D module + `.once` clip + tint. Lowest risk: user-initiated, one scene | APK size OK; SkipUI on Compose 1.12 OK |
| 2 | **6 Verben mit Präpositionen** (cards + review), **1 Onboarding Aufbau** | baked `.once`/`.loop`, frozen on question side | low-end device perf check |
| 3 | **3–5 Präpositionen** (case game, cards, rules sheet `wohinwo`) | `PrepositionChoreography` split + `ChoreoTrack`; assembly fly-in per piece | parity review against iOS videos |
| 4 | 2 Treppe, 10 Journey, 9 Pyramide | need GLBs for procedural geometry (`pyramid_render.py`, steps, ramps) **or** stay 2D | product call |
| never | 8 extruded-letter endings | keep `EndingBlocksFlat` | – |

Keep the house rules: one live `SceneView` per screen, stills in lists, the render loop parked when idle (SceneView
OnDemand does this by itself), and a `LightweightGraphics`-equivalent switch that falls back to stills.

## 6. Risks and what is still unverified

- **Performance on real low-end GPUs.** Not measured. Emulator numbers mean little: ANGLE over Vulkan on an Apple
  M6, 28 % janky frames, p50 23 ms. Spike PSS was 148 MB, native heap 73 MB. Needs a Mali/Adreno budget phone.
- **Integration with Skip** (ContentComposer in a Fuse module calling a Lite module's composable, and bridging
  `SceneSpec`): not built. I followed the skip.dev docs pattern without running it.
- Dark-mode material variants: not tested. The plan is the runtime tint (`baseColorFactor`) from the theme, as on
  iOS. No asset variants are needed.
- iOS look parity: lighting, FOV, shadows and tone mapping not tuned. SceneView defaults differ (Khronos PBR Neutral
  tone mapper, SSAO, bloom).
- Compose upgrade forced by SceneView (§3.4 item 4). An alternative is to pin an older SceneView, or use Filament
  directly.
- Pipeline:
  - add `export_glb` to the real `figur.py`/`prep_render.py`;
  - add a GLB check to `verify()` (exactly 1 `Scene` clip when animated, `subject` present, 0 cams/lights);
  - decide `export_anim_slide_to_zero`;
  - investigate the 12 verb scenes that fail the USD twin check under Blender 5.3 and the 2 animation-less verb
    GLBs.
- prep3d `assembly(at:)` (per-piece fly-in from the scene centre) is not prototyped. It needs per-child entity
  transforms, which are the same API as the `subject` offset, so it's low risk.

## 7. Files

- `3d-work/repo/tools/blender/{figur.py,prep_render.py}`: copies with `export_glb`.
- `3d-work/repo/tools/blender/glb_driver.py`: headless driver.
- `3d-work/pristine/`: an unmodified copy, used for the twin-check repro.
- `3d-work/inspect_glb.py`: validator. `3d-work/glb_rest_to_last.py`: rest-pose rewriter (didn't fix the
  SceneView snap-back; kept for reference).
- `3d-work/out/*.glb`: the 6 sample GLBs. `out/actions/`: ACTIONS-mode variants. `out/all/`: all 82 GLB + USDZ +
  `out/all-report.json`. `glb-report.json`. `logs/`: every Blender and Gradle log.
- `3d-work/spike/`: the Gradle project (MainActivity in `app/src/scene/kotlin/...`). APKs are under
  `app/build/outputs/apk/`.
- `3d-work/shots/`: `aufbau-sequence.png`, `scenes-sheet.png` and the raw frames.
- The spike app `com.kessenma.kartei3dspike` is still installed on emulator-5554. Remove it with
  `adb -s emulator-5554 uninstall com.kessenma.kartei3dspike`.
