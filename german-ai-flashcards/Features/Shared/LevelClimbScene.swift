//
//  LevelClimbScene.swift
//  german-ai-flashcards
//
//  „Die Treppe" — die Figur standing on a five-step staircase, one step per CEFR level, and
//  walking up or down when the learner picks a different one. The hero of the hard-select door
//  (`PlacementDeclareStage`), where the question is literally "how far up are you?".
//
//  Borrowed wholesale from `JourneyHeaderScene`: the baked gait (`figur-gehen.usdz`, authored in
//  `figur.py --gehen`), the prep scenes' contract that the clip owns the limbs while *translation*
//  stays a runtime slide, `SceneRig` for the house angle and lights, and Reduce Motion falling back
//  to the static geh pose.
//
//  What is deliberately NOT borrowed is the switchback. The Journey mountain is endless on purpose —
//  no summit, the lifetime learner — and its ramp pooling exists to express exactly that. Here the
//  climb is finite and *addressable*: five steps, five levels, and the whole job of the picture is
//  to say which one you just chose. Zigzagging would hide the mapping the picker depends on, so the
//  steps run straight, left (A1) to right (C1).
//
//  The gait is speed-matched to the slide (`clipSpeed`), the same discipline as the mountain: a
//  fixed clip over a variable distance is what moonwalking is.
//

import SwiftUI
import RealityKit

struct LevelClimbScene: View {
    var selection: CEFRLevel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Where she is standing now, in step indices. Trails `selection` while a walk plays out.
    @State private var fromStep: Int
    @State private var startedAt = Date()
    /// True only while a walk is in flight — an idle canvas must not hold a display link open
    /// (the rule `FigurSceneView` states and `JourneyHeaderScene` follows).
    @State private var isMoving = false
    @State private var stopper: Task<Void, Never>?

    init(selection: CEFRLevel) {
        self.selection = selection
        _fromStep = State(initialValue: Self.step(selection))
    }

    static func step(_ level: CEFRLevel) -> Int {
        CEFRLevel.allCases.firstIndex(of: level) ?? 0
    }

    private var toStep: Int { Self.step(selection) }

    /// Long enough to read as walking, short enough that a picker still feels responsive. Capped
    /// so A1 → C1 doesn't become a four-second cutscene.
    private static let secondsPerStep: Double = 0.75
    private static let maxDuration: Double = 1.8

    private var duration: Double {
        min(Self.maxDuration, Double(abs(toStep - fromStep)) * Self.secondsPerStep)
    }

    var body: some View {
        Group {
            if LightweightGraphics.isActive {
                // No RealityKit at all on this path — not a paused scene, a different picture.
                // The flat stand-in still has to answer the question the canvas answers, so it
                // draws the five steps and marks the chosen one.
                LevelStairsGlyph(selection: selection)
            } else if reduceMotion {
                LevelClimbRealityScene(
                    fromStep: toStep, toStep: toStep, progress: 1,
                    animated: false, playing: false, tint: selection.chipColor
                )
            } else {
                TimelineView(.animation(paused: !isMoving)) { timeline in
                    LevelClimbRealityScene(
                        fromStep: fromStep,
                        toStep: toStep,
                        progress: progress(at: timeline.date),
                        animated: true,
                        playing: isMoving,
                        tint: selection.chipColor
                    )
                }
            }
        }
        .onChange(of: selection) { old, _ in beginWalk(from: Self.step(old)) }
        .onDisappear { stopper?.cancel(); isMoving = false }
        // Decorative: the choice list below carries every bit of meaning this picture has.
        .accessibilityHidden(true)
    }

    private func progress(at date: Date) -> Double {
        guard isMoving, duration > 0 else { return 1 }
        return min(1, date.timeIntervalSince(startedAt) / duration)
    }

    /// Starts the walk and schedules its own end, so the timeline stops as soon as she arrives.
    /// `fromStep` is only rewritten *after* the walk finishes — it is the anchor the slide
    /// interpolates from, and moving it early would teleport her.
    private func beginWalk(from previous: Int) {
        stopper?.cancel()
        guard !reduceMotion, !LightweightGraphics.isActive else {
            fromStep = toStep
            return
        }
        fromStep = previous
        let span = duration
        guard span > 0 else { return }
        startedAt = Date()
        isMoving = true
        let landing = toStep
        stopper = Task { @MainActor in
            try? await Task.sleep(for: .seconds(span))
            guard !Task.isCancelled else { return }
            fromStep = landing
            isMoving = false
        }
    }
}

// MARK: - The canvas

private struct LevelClimbRealityScene: View {
    let fromStep: Int
    let toStep: Int
    /// 0…1 along the walk from `fromStep` to `toStep`.
    let progress: Double
    let animated: Bool
    /// False when standing still — pauses the gait without tearing the scene down.
    let playing: Bool
    /// The chosen level's own colour, painted onto the step she's headed for — the same
    /// `chipColor` its row in the list wears, so the picture and the list agree at a glance.
    let tint: Color

    @State private var root = Entity()
    @State private var figure: Entity?
    @State private var walkController: AnimationPlaybackController?
    @State private var camera = PerspectiveCamera()
    /// Kept so the active step can be repainted without rebuilding the scene.
    @State private var slabs: [ModelEntity] = []

    // Proportions, in the same spirit as the mountain: the figure ships 1.8 units tall and is
    // scaled to half, so a 0.5 rise leaves clear air above her head on the step above.
    private static let figureScale: Float = 0.5
    // Tightened from 0.78/0.50: on the house angle a wider flight runs off both sides of a 190pt
    // canvas, and the bottom step was being clipped — all five have to be visible or the picture
    // stops being a five-level ladder.
    private static let stepRun: Float = 0.66
    private static let stepRise: Float = 0.46
    private static let stepCount = 5
    /// The mountain's honest gait speed at this scale — one 1 s stride pair covers ~0.8 units ×
    /// `figureScale`. Any other speed is fine as long as the clip is scaled to match it.
    private static let honestWalkSpeed: Float = 0.4

    /// Centres the run on x so the camera never has to pan.
    private static func xFor(_ step: Int) -> Float {
        (Float(step) - Float(stepCount - 1) / 2) * stepRun
    }
    private static func yFor(_ step: Int) -> Float { Float(step) * stepRise }

    var body: some View {
        RealityView { content in
            camera.camera.fieldOfViewInDegrees = 30
            SceneRig.aim(camera, at: Self.frameTarget, distance: Self.frameDistance)
            content.add(camera)
            for light in SceneRig.lights() { content.add(light) }
            content.add(root)
        } update: { _ in
            // Stateless on purpose — nothing here mutates view state, so it's safe in the update
            // pass (the tap-handler rule the pyramid canvas learned the hard way).
            place()
            syncWalkClip()
        }
        .task { await buildScene() }
        // Repainting belongs on the change, not in `update:` — that pass runs every frame of a
        // walk, and rebuilding five materials sixty times a second to set a colour that changed
        // once is pure waste. Same split `FigurSceneView` makes for its tint.
        .onChange(of: toStep) { paintSteps() }
        .onChange(of: tint) { paintSteps() }
    }

    /// The figure at this scale, for framing. The asset ships 1.8 units tall.
    private static var figureHeight: Float { 1.8 * figureScale }

    /// Framing has to hold **every** selection, not just the middle one: the camera never moves,
    /// but she does — from the bottom step to standing a head above the top one. So aim at the
    /// centre of that whole span (ground to top step + her height) rather than at the staircase
    /// alone. Aiming at the steps put her within 0.16 units of the top edge on C1.
    private static var frameTarget: SIMD3<Float> {
        [0, (yFor(stepCount - 1) + figureHeight) / 2, 0]
    }
    /// At 30° the visible half-height here is ~1.66 units against a span of ~1.37 — margin enough
    /// that neither C1's head nor A1's step touches an edge.
    private static let frameDistance: Float = 6.2

    private func buildScene() async {
        root.children.removeAll()
        var built: [ModelEntity] = []

        for step in 0..<Self.stepCount {
            let slab = ModelEntity(
                mesh: .generateBox(size: [Self.stepRun, 0.12, 0.72]),
                materials: [material(Self.restColor)]
            )
            slab.position = [Self.xFor(step), Self.yFor(step) - 0.06, 0]
            root.addChild(slab)
            built.append(slab)
        }
        slabs = built

        let asset = animated ? "figur-gehen" : "figur-geh"
        guard let loaded = try? await Entity(named: asset, in: .main) else { return }
        loaded.removeCamerasAndLights()
        loaded.scale = SIMD3(repeating: Self.figureScale)
        root.addChild(loaded)
        figure = loaded
        if animated, let clip = walkClip(of: loaded) {
            walkController = loaded.playAnimation(clip.repeat(duration: .infinity), transitionDuration: 0)
        }
        place()
        paintSteps()
        syncWalkClip()
    }

    /// The chosen step wears its level's colour; the rest stay the neutral every prop wears.
    /// Painted on `toStep` rather than where she's standing, so the tap answers immediately and
    /// she is visibly walking *toward* the step already marked as chosen.
    private func paintSteps() {
        for (index, slab) in slabs.enumerated() {
            slab.model?.materials = [material(index == toStep ? tint : Self.restColor)]
        }
    }

    /// The same neutral charcoal every prop in the app wears (`FigurScene.defaultTint`'s ground).
    private static let restColor = Color(white: 0.28)

    /// Same clip-selection rule as `FigurSceneView` and the Journey mountain: the root's "global
    /// scene animation" covers every part; the longest clip is the fallback for a future exporter
    /// that names it differently.
    private func walkClip(of scene: Entity) -> AnimationResource? {
        let clips = scene.availableAnimations
        return clips.first { $0.name == "global scene animation" }
            ?? clips.max { $0.definition.duration < $1.definition.duration }
    }

    /// Pause and resume rather than stop and restart — the controller keeps its phase, so a walk
    /// resumed mid-stride doesn't snap back to the first frame.
    private func syncWalkClip() {
        guard let walkController else { return }
        if playing {
            // Scale the gait to the distance actually being covered. A fixed clip over a variable
            // slide is exactly what moonwalking is.
            walkController.speed = Self.clipSpeed(from: fromStep, to: toStep)
            if !walkController.isPlaying { walkController.resume() }
        } else if walkController.isPlaying {
            walkController.pause()
        }
    }

    /// The gait multiplier that keeps footfalls matched to the slide.
    private static func clipSpeed(from: Int, to: Int) -> Float {
        let steps = abs(to - from)
        guard steps > 0 else { return 1 }
        let seconds = Float(min(maxWalkSeconds, Double(steps) * perStepSeconds))
        guard seconds > 0 else { return 1 }
        let speed = (Float(steps) * stepRun) / seconds
        return max(0.5, speed / honestWalkSpeed)
    }
    // Mirrors `LevelClimbScene`; kept here so `clipSpeed` is self-contained and testable by eye.
    private static let perStepSeconds: Double = 0.75
    private static let maxWalkSeconds: Double = 1.8

    /// Translation only — the clip owns the limbs and the bob (the prep scenes' contract).
    private func place() {
        guard let figure else { return }
        let t = Float(max(0, min(1, progress)))
        let x = Self.xFor(fromStep) + (Self.xFor(toStep) - Self.xFor(fromStep)) * t
        figure.position = [x, Self.walkHeight(from: fromStep, to: toStep, t: t, x: x), 0]
        // Face the way she's travelling; standing still, face up the climb.
        let facing: Float = toStep < fromStep ? -1 : 1
        figure.transform.rotation = simd_quatf(angle: facing * .pi / 2, axis: [0, 1, 0])
    }

    /// Height along the walk.
    ///
    /// Lerping y against x — the obvious version — walks her diagonally from one tread's centre to
    /// the next, and that straight line passes clean **through** the corner of the step being
    /// climbed. It looked exactly like what it was: a figure clipping through geometry.
    ///
    /// So the climb is resolved per step, and the rise is timed against the moment she crosses the
    /// edge, which is always the midpoint between two tread centres (`local == 0.5`):
    ///   * **going up**, be at the new height *by* the crossing — you rise as the lead foot lands;
    ///   * **going down**, hold the height *until* you've crossed — you drop off the edge, not before.
    ///
    /// `max` against the tread underfoot is the belt-and-braces guarantee: whatever the easing
    /// does, she is never below the step she is over, so clipping cannot come back.
    private static func walkHeight(from: Int, to: Int, t: Float, x: Float) -> Float {
        let delta = to - from
        guard delta != 0 else { return yFor(from) }
        let span = abs(delta)
        let direction = delta > 0 ? 1 : -1
        let u = t * Float(span)
        let index = min(Int(u), span - 1)
        let local = u - Float(index)
        let lower = from + direction * index
        let upper = lower + direction
        let window: (Float, Float) = direction > 0 ? (0.15, 0.5) : (0.5, 0.85)
        let eased = yFor(lower) + (yFor(upper) - yFor(lower)) * smoothstep(window.0, window.1, local)
        return max(eased, treadHeight(atX: x))
    }

    /// Top of the step whose tread contains `x`, clamped to the flight.
    private static func treadHeight(atX x: Float) -> Float {
        let index = Int((x / stepRun + Float(stepCount - 1) / 2).rounded())
        return yFor(max(0, min(stepCount - 1, index)))
    }

    /// Hermite ease — a linear rise starts and stops with a visible jolt at this scale.
    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private func material(_ color: Color) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(color))
        material.roughness = 0.65
        return material
    }
}

// MARK: - Flat stand-in

/// What a lightweight-graphics device sees instead of the canvas: five rising bars, the chosen one
/// in its level's colour. It answers the same question the scene answers — which of the five you're
/// on — without a render context.
struct LevelStairsGlyph: View {
    var selection: CEFRLevel

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(CEFRLevel.allCases.enumerated()), id: \.element) { index, level in
                let isOn = level == selection
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isOn ? level.chipColor : Color.secondary.opacity(0.22))
                    .frame(width: 26, height: 16 + CGFloat(index) * 16)
                    .overlay(alignment: .top) {
                        if isOn {
                            Circle()
                                .fill(level.chipColor)
                                .frame(width: 9, height: 9)
                                .offset(y: -13)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}
