//
//  FigurSceneView.swift
//  german-ai-flashcards
//
//  The Bauhaus figure on a RealityKit canvas: two cylinder legs, a cube torso, two cone arms,
//  a sphere head. Authored in `tools/blender/figur.py`; regenerate with `figur_all.sh`.
//
//  The choreography is *baked into the asset*, not driven from here. That is the whole reason
//  this view is short: the app's other motion path writes positions every frame and can only
//  translate, and an assembly worth watching needs the arms to rotate down onto the shoulders.
//  Blender bakes translation and rotation per part, RealityKit finds it as an entity animation,
//  and playing it is one call.
//
//  Played once, never `.repeat()` — an assembly that loops forever reads as a glitch rather
//  than as a thing being built. The clip's last sample holds, so the figure simply stays
//  assembled afterwards.
//

import RealityKit
import SwiftUI

enum FigurScene {
    /// The resting figure: six named parts, no clip.
    static let ruhe = "figur"
    /// The self-assembly clip — legs, torso, arms, head over 2.5s, then held.
    static let aufbau = "figur-aufbau"

    /// Charcoal on a light ground, the Grundform ink on a dark one. The asset ships charcoal
    /// (`#33383D`, the same neutral every prop wears), which all but vanishes against the dark
    /// theme ground — so the canvas re-tints rather than shipping a second asset.
    static let defaultTint = Color(light: 0x33383D, dark: 0xECE7DA)

    /// The flat stand-in for the whole canvas on a device running lightweight graphics: the same
    /// figure, same pose, same house angle, rendered in Blender rather than on the phone.
    ///
    /// Two bitmaps rather than one re-tinted one, because a tint would flatten the shading that
    /// makes the primitives read as solid. The asset catalog picks by appearance, matching the
    /// two inks in `defaultTint`. Regenerate with `figur.py --view dim --ortho 3.1 --size 768
    /// --color <hex>`.
    static let still = "figur-still"
}

struct FigurSceneView: View {
    var asset: String = FigurScene.aufbau
    var tint: Color = FigurScene.defaultTint
    /// Replays the clip from its first frame without changing view identity — the same trick
    /// `PrepositionSceneView` uses, and for the same reason: `.id()` would tear down and rebuild
    /// the RealityKit surface.
    var restartToken: Int = 0
    /// How far back the camera sits on the house angle. Larger frames the figure smaller; the
    /// default fits a 1.8-unit figure into roughly two thirds of the frame height.
    var distance: Float = 5.2
    /// Held before the first beat, for a host that is itself still animating into place. A sheet
    /// slides for about a third of a second, and an assembly that starts underneath that slide
    /// spends its opening beat — both legs — behind a moving pane. Zero anywhere the canvas is
    /// already on screen when it loads.
    var settleDelay: Duration = .zero
    /// Ignores lightweight graphics and always builds the RealityKit canvas. For the gallery only:
    /// a surface whose job is judging the live figure is worse than useless showing a flat stand-in
    /// with a camera slider that moves nothing. Product screens leave this alone.
    var forcesLiveScene: Bool = false

    /// Waist height on a 1.8-unit figure whose feet stand at y = 0.
    private static let target = SIMD3<Float>(0, 0.9, 0)

    @State private var root = Entity()
    @State private var camera = PerspectiveCamera()
    @State private var loaded: Entity?
    /// True from the moment a clip starts until shortly after it ends. Drives the timeline below,
    /// and *only* while there is motion — an idle canvas must not hold a display link open.
    @State private var isAnimating = false
    @State private var stopper: Task<Void, Never>?

    /// The clip runs on RealityKit's clock, but a frame only reaches the screen when SwiftUI
    /// re-evaluates this view. Without the timeline the canvas renders once, stays blank through
    /// the whole 2.5s assembly (every part starts off-camera), and then repaints on some unrelated
    /// invalidation — showing a figure that "blinks in" fully built. Measured, not guessed: the
    /// part transforms provably animate while six consecutive screenshots stay empty.
    ///
    /// `PrepositionSceneView` reaches for the same `TimelineView` and pairs it with an `update:`
    /// closure; both halves are load-bearing, since `update:` is what a beat actually runs.
    var body: some View {
        if isLightweight {
            // No RealityKit at all on this path — not a paused scene, not a hidden one. The whole
            // point is that the render context is never built.
            still
        } else {
            live
        }
    }

    /// Resolved once per appearance rather than read inline, so the two branches can never
    /// disagree within a single layout pass.
    private var isLightweight: Bool { !forcesLiveScene && LightweightGraphics.isActive }

    private var still: some View {
        Image(FigurScene.still)
            .resizable()
            .scaledToFit()
    }

    private var live: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            canvas(beat: context.date)
        }
        .task(id: asset) { await load() }
        .onChange(of: restartToken) { replay() }
        .onChange(of: tint) { loaded?.tintEveryModel(tint) }
        // Re-aim the camera we already have rather than rebuilding the view. Framing is a
        // tuning knob, and `.id(distance)` would drop the render context on every drag.
        .onChange(of: distance) { SceneRig.aim(camera, at: Self.target, distance: distance) }
        .onDisappear { stopper?.cancel(); isAnimating = false }
    }

    private func canvas(beat: Date) -> some View {
        RealityView { content in
            camera.camera.fieldOfViewInDegrees = 30
            SceneRig.aim(camera, at: Self.target, distance: distance)
            content.add(camera)
            for light in SceneRig.lights() { content.add(light) }
            // Content arrives via `load`, not here: this closure runs once, so loading in it
            // would mean a change of `asset` never reaches the scene.
            content.add(root)
        } update: { _ in
            // Nothing to write — RealityKit is already posing the parts. Reading the beat is the
            // point: it makes each timeline tick a genuine change, so the frame gets presented.
            _ = beat
        }
    }

    /// Runs the timeline for a clip's length plus a short tail, so the last beat — the head
    /// settling — is presented before the display link is released.
    private func animate(for duration: TimeInterval) {
        stopper?.cancel()
        isAnimating = true
        stopper = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration + 0.4))
            guard !Task.isCancelled else { return }
            isAnimating = false
        }
    }

    private func load() async {
        loaded = nil
        root.children.removeAll()

        guard let scene = try? await Entity(named: asset, in: .main) else { return }
        // Geometry only, whatever the asset claims.
        scene.removeCamerasAndLights()
        scene.tintEveryModel(tint)
        loaded = scene

        let clip = assemblyClip(of: scene)
        if clip != nil, settleDelay > .zero {
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
        }

        // Attached at the moment it starts moving, never before. A loaded-but-unplayed stage
        // evaluates to its bind pose — the *finished* figure — so attaching earlier would flash
        // the punchline and then yank it apart. Frame one has every part off-camera, so attaching
        // here leaves the canvas honestly empty until the legs enter.
        root.addChild(scene)
        if let clip {
            scene.playAnimation(clip)
            animate(for: clip.definition.duration)
        }
    }

    private func play(_ scene: Entity) {
        guard let clip = assemblyClip(of: scene) else { return }
        scene.playAnimation(clip)
        animate(for: clip.definition.duration)
    }

    /// The one clip to play, out of the many that describe the same motion.
    ///
    /// This is the whole trick, and it is worth stating plainly because the obvious code is
    /// wrong. A Blender-authored USD arrives with its motion exposed many ways: a hierarchy-wide
    /// clip on the loaded root, a clip on each of the six parts covering that part's own beat,
    /// and every one of those aliased under two or three names — 21 entries for this asset. They
    /// all write the same transforms, so any two playing at once means the last to start wins.
    ///
    /// Looping over `availableAnimations` therefore does the opposite of what it reads like: the
    /// last clip to start is the root's *empty* `default subtree animation`, which pins the figure
    /// at its bind pose. The symptom is a figure that appears abruptly, fully built, having moved
    /// not at all — which is precisely what this view did until the clips were enumerated.
    ///
    /// Matched by name, not by duration: that do-nothing sibling reports an identical duration,
    /// so length cannot separate them. The longest-clip fallback keeps a future exporter that
    /// omits the name animating rather than silently freezing.
    private func assemblyClip(of scene: Entity) -> AnimationResource? {
        let clips = scene.availableAnimations
        return clips.first { $0.name == "global scene animation" }
            ?? clips.max { $0.definition.duration < $1.definition.duration }
    }

    private func replay() {
        guard let scene = loaded else { return }
        scene.stopAllAnimations(recursive: true)
        play(scene)
    }
}

// MARK: - Gallery (tuning surface)

/// Where the figure gets judged on a real device, reached from the bottom of the preposition
/// hub — the same place the scene gallery lives, for the same reason.
///
/// The distance slider is here because framing is the one thing a Blender render cannot settle:
/// the judge renders are orthographic, the canvas is perspective, and how much of the frame a
/// 1.8-unit figure should fill is a matter of taste on a real screen.
struct FigurGalleryView: View {
    @State private var showsRestPose = false
    @State private var replay = 0
    @State private var distance: Float = 5.2

    var body: some View {
        VStack(spacing: 16) {
            Picker("Asset", selection: $showsRestPose) {
                Text("Aufbau").tag(false)
                Text("Ruhe").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: showsRestPose) { replay += 1 }

            FigurSceneView(
                asset: showsRestPose ? FigurScene.ruhe : FigurScene.aufbau,
                restartToken: replay,
                distance: distance,
                forcesLiveScene: true
            )
            .frame(height: 340)

            VStack(spacing: 4) {
                Slider(value: $distance, in: 3.0...9.0)
                Text("Kameraabstand \(distance, specifier: "%.1f")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .background { ThemedBackground().ignoresSafeArea() }
        .navigationTitle("Figur")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { replay += 1 } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Replay assembly")
            }
        }
    }
}

// MARK: - Previews
//
// The simulator here can't be driven by hand, so a preview is the visual check (see the testing
// note in docs/theme-upgrade.md).

#Preview("Aufbau") {
    struct Harness: View {
        @State private var replay = 0
        var body: some View {
            VStack(spacing: 12) {
                FigurSceneView(restartToken: replay)
                    .frame(height: 320)
                Button("Replay") { replay += 1 }
                    .buttonStyle(.bordered)
            }
            .padding()
            .background { ThemedBackground().ignoresSafeArea() }
        }
    }
    return Harness()
}

#Preview("Rest pose, four themes") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(AppTheme.allCases) { theme in
                ZStack {
                    ThemedBackground()
                    FigurSceneView(asset: FigurScene.ruhe)
                        .frame(height: 240)
                }
                .environment(\.appTheme, theme)
                .frame(height: 240)
            }
        }
    }
}
