//
//  PrepositionSceneView.swift
//  german-ai-flashcards
//
//  The one place the preposition 3D scene is set up, posed, tinted and animated. The drill, the
//  cards and the fill-in-the-blank feedback all render *this*, so the camera angle, the light
//  rig and the motion vocabulary can't drift apart across three screens.
//
//  Assets come from `tools/blender/prep_render.py`: one USDZ per relation shipping the resting
//  (Dativ) pose, plus `prep3d-manifest.json` carrying the offset to the Akkusativ pose and, for
//  fixed-case relations, an authored `motion` spec (durch passes through, um orbits, für tosses
//  the ball from giver to receiver). One asset covers everything because the app poses and tints
//  it at runtime — which is the whole reason this ships geometry instead of pre-rendered frames.
//
//  What the scene may show depends on where it is:
//    - `.neutral`   the relation, subject in grey. Safe on a question side: it teaches the
//                   meaning without leaking the case, which is carried by the *color* and the
//                   two-state contrast, not by the geometry.
//    - `.resolved`  the answer. Assembles, settles, takes its case color, then idles.
//

import SwiftUI
import RealityKit

// MARK: - Asset lookup

/// Naming and availability for the rendered preposition scenes.
enum PrepositionScene {
    /// A fixed-case relation's choreography, authored in the rig (`prep_render.py` `motion`
    /// keys) and published through the manifest with its vectors already remapped to Y-up.
    /// All vectors are deltas from the subject's resting position.
    struct MotionSpec: Decodable {
        let kind: String
        let from: [Float]?
        let to: [Float]?
        let center: [Float]?
        let back: [Float]?
        let delta: [Float]?
        /// The reference's shove in a `cause` scene — wegen's block striking the ball.
        let push: [Float]?
        let arc: Float?
        /// Travel seconds for the shuttle leg; nil takes the default. seit's slow crawl is
        /// authored here, not hardcoded.
        let dur: Float?
        /// Substring naming which reference pieces move (`swap`); nil means all of them.
        let movers: String?
    }

    struct Pose: Decodable {
        let asset: String
        let akkOffset: [Float]
        let motion: MotionSpec?

        /// Where the subject sits in the Akkusativ (moving) pose, relative to its resting pose.
        var offset: SIMD3<Float> {
            akkOffset.count == 3 ? SIMD3(akkOffset[0], akkOffset[1], akkOffset[2]) : .zero
        }

        /// Whether the live scene has anything to show that the still doesn't.
        ///
        /// Two-way relations move between their poses (`akkOffset`), and fixed-case ones now
        /// carry authored choreography (`motion`) — durch passes through, um orbits, aus pops
        /// out of the box. A relation with neither would render as a ball parked next to a
        /// prop, which the arrow-bearing still says better, so it falls back.
        var animates: Bool { offset != .zero || motion != nil }
    }

    private struct Manifest: Decodable {
        let relations: [String: Pose]
    }

    private static let manifest: Manifest = {
        guard let url = Bundle.main.url(forResource: "prep3d-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return Manifest(relations: [:]) }
        return decoded
    }()

    static func pose(for word: String) -> Pose? { manifest.relations[word] }

    /// Whether this preposition has a scene at all — callers fall back to text rather than
    /// to a placeholder for the words that don't.
    static func exists(for word: String) -> Bool { manifest.relations[word] != nil }

    /// A still, for small sizes and as the fallback when RealityKit can't load the scene.
    static func image(for word: String, state: String, look: String = "dim") -> UIImage? {
        guard let asset = pose(for: word)?.asset else { return nil }
        return UIImage(named: "\(asset)-\(state)-\(look)")
    }
}

// MARK: - The view

struct PrepositionSceneView: View {
    enum Mode: Equatable {
        /// Relation shown, case withheld. The question side.
        case neutral
        /// The answer: settles into the given case and idles there.
        case resolved(PrepositionCase)
    }

    let word: String
    var mode: Mode = .neutral
    /// Two-way prepositions loop between the moving and resting poses; fixed-case ones settle
    /// once and stay put, since they have no contrast to show.
    var loops: Bool = false
    /// Bump to restart the choreography from its assemble beat. This — not `.id()` — is how a
    /// host replays or swaps scenes: changing identity tears down the RealityKit surface and
    /// builds a new render context, and a pager that does that per page leaks contexts until
    /// rendering stalls. One live view, re-posed, is the contract.
    var restartToken: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var appTheme

    /// Restarted whenever the mode changes, so the assemble beat plays on reveal rather than
    /// mid-way through whatever the idle loop happened to be doing.
    @State private var startedAt = Date()
    @State private var isVisible = true

    var body: some View {
        Group {
            if let pose = PrepositionScene.pose(for: word), pose.animates {
                if reduceMotion {
                    // Motion is the whole point of this view, so with it switched off we show
                    // the resolved still rather than a frozen 3D scene doing nothing.
                    stillFallback
                } else {
                    TimelineView(.animation(paused: !isVisible)) { timeline in
                        let t = Float(timeline.date.timeIntervalSince(startedAt))
                        PrepositionRealityScene(
                            asset: pose.asset,
                            subjectOffset: subjectOffset(pose, at: t),
                            moverOffset: moverOffset(pose, at: t),
                            moverFilter: pose.motion?.movers,
                            tint: tint(at: t),
                            assembly: assembly(at: t)
                        )
                    }
                }
            } else {
                stillFallback
            }
        }
        .onChange(of: mode) { startedAt = Date() }
        // A word swap re-uses this same view (and its RealityKit surface) for a new relation —
        // the clock restarts so the new scene opens on its assemble beat, not mid-loop.
        .onChange(of: word) { startedAt = Date() }
        .onChange(of: restartToken) { startedAt = Date() }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    @ViewBuilder
    private var stillFallback: some View {
        let state = switch mode {
        case .neutral: "neutral"
        case .resolved: "dat"
        }
        if let image = PrepositionScene.image(for: word, state: state) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Color.clear
        }
    }

    // MARK: - The four beats

    private var isResolved: Bool { if case .resolved = mode { return true }; return false }

    /// 0 → 1 as the reference pieces fly in from off-scene. Only on reveal: the question side is
    /// already assembled, so there's nothing to announce.
    private func assembly(at t: Float) -> Float {
        guard isResolved else { return 1 }
        return smoothstep(t / 0.45)
    }

    /// The loop's shape: travel, dwell, travel back, dwell. Flat at both ends *and* periodic,
    /// which is what closes the cycle without a snap-back frame.
    private static let cycle: Float = 3.4
    private static let segments: (travelOut: Float, restLow: Float, travelBack: Float) =
        (0.34, 0.62, 0.94)

    /// Where the subject is: 1 = the Akkusativ (moving) pose, 0 = at rest.
    private func travel(at t: Float) -> Float {
        switch mode {
        case .neutral:
            return 0
        case .resolved:
            guard loops else { return smoothstep(1 - (t - 0.35) / 0.5) }
            let s = Self.segments
            let u = t.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
            switch u {
            case ..<s.travelOut:  return 1 - smoothstep(u / s.travelOut)
            case ..<s.restLow:    return 0
            case ..<s.travelBack: return smoothstep((u - s.restLow) / (s.travelBack - s.restLow))
            default:              return 1
            }
        }
    }

    // MARK: - Fixed-case choreography
    //
    // Two-way relations animate by traveling between their two authored poses. Fixed-case ones
    // have one pose, so their life comes from an authored `MotionSpec` instead: each kind is a
    // small pose function of time, and each states its preposition and nothing else. Motion only
    // plays on the *resolved* side — on a question, a learner could read movement as "Akkusativ"
    // and be misled precisely by the words this exists for (aus moves, and takes the Dativ).
    //
    // Everything loops (Kyle's call — a settled scene reads as broken), but the settled tableau
    // owns most of each cycle, so the resting state still dominates what you remember.

    /// When choreography starts: after the assemble beat has landed and the color is arriving.
    private static let motionLeadIn: Float = 0.55

    /// The shared loop shape: travel out (dur), hold the settled tableau, travel back, brief
    /// home dwell. 0 = at `from`, 1 = settled.
    private func loopLeg(_ tm: Float, dur: Float, settle: Float = 2.3, home: Float = 0.8) -> Float {
        let cycle = 2 * dur + settle + home
        let u = tm.truncatingRemainder(dividingBy: cycle)
        switch u {
        case ..<dur:                return smoothstep(u / dur)
        case ..<(dur + settle):     return 1
        case ..<(2 * dur + settle): return 1 - smoothstep((u - dur - settle) / dur)
        default:                    return 0
        }
    }

    /// A shuttle's position at path parameter `s` (0 = from, 1 = settled at to/rest).
    ///
    /// With an arc, the horizontal leg waits out the first stretch while the lift builds — so a
    /// path that must clear something (aus over the box wall, trotz over its wall) is already
    /// high when it starts crossing. The same curve runs backwards on the return leg, so it is
    /// clip-safe in both directions.
    private func shuttlePoint(_ m: PrepositionScene.MotionSpec, s: Float) -> SIMD3<Float> {
        let from = vec(m.from), to = vec(m.to)
        guard let arc = m.arc else { return mix(from, to, t: s) }
        var pos = mix(from, to, t: smoothstep((s - 0.22) / 0.78))
        pos.y += arc * 4 * s * (1 - s)
        return pos
    }

    /// The subject's displacement from rest at time `t`.
    private func subjectOffset(_ pose: PrepositionScene.Pose, at t: Float) -> SIMD3<Float> {
        // Two-way: the travel loop between the two authored poses, exactly as before.
        guard let m = pose.motion else { return pose.offset * travel(at: t) }
        guard isResolved else { return .zero }
        let tm = max(0, t - Self.motionLeadIn)

        switch m.kind {
        case "shuttle", "swap":
            // Out of the box / over to the receiver / plucked from the cluster — then, after a
            // long settled dwell, gently back to do it again.
            return shuttlePoint(m, s: loopLeg(tm, dur: m.dur ?? 1.1))

        case "cause":
            // The push arrives first (movers below), and the ball rolls off because of it.
            let u = tm.truncatingRemainder(dividingBy: 4.8)
            let depart = vec(m.delta)
            switch u {
            case ..<0.45: return .zero
            case ..<1.5:  return depart * smoothstep((u - 0.45) / 1.05)
            case ..<3.4:  return depart
            default:      return depart * (1 - smoothstep((u - 3.4) / 1.0))
            }

        case "through":
            // Lead out of the opening, then ping-pong: a pass in either direction is still
            // "durch", which is what makes this one honest to loop.
            let exit = -vec(m.from)
            let lead: Float = 0.7, pass: Float = 1.2, dwell: Float = 0.8
            if tm < lead { return mix(.zero, exit, t: smoothstep(tm / lead)) }
            let u = (tm - lead).truncatingRemainder(dividingBy: 2 * (pass + dwell))
            switch u {
            case ..<dwell:                  return exit
            case ..<(dwell + pass):         return mix(exit, -exit, t: smoothstep((u - dwell) / pass))
            case ..<(2 * dwell + pass):     return -exit
            default:                        return mix(-exit, exit, t: smoothstep((u - 2 * dwell - pass) / pass))
            }

        case "orbit":
            // Constant circling in the ground plane, eased in from rest. Never settles —
            // neither does "um".
            let c = vec(m.center)
            let radius = (c.x * c.x + c.z * c.z).squareRoot()
            guard radius > 0 else { return .zero }
            let theta0 = atan2(-c.z, -c.x)
            let theta = theta0 + (2 * .pi / 4.6) * tm * smoothstep(tm / 0.9)
            return SIMD3(c.x + radius * cos(theta), c.y, c.z + radius * sin(theta))

        case "bounce":
            // Wind back, strike (the rest pose IS the wall contact), small rebound, resettle.
            let back = vec(m.back)
            let u = tm.truncatingRemainder(dividingBy: 2.6)
            switch u {
            case ..<0.9:
                return back * smoothstep(u / 0.9)
            case ..<1.25:
                let p = (u - 0.9) / 0.35
                return back * (1 - p * p)                    // ease-in: gathers speed into the wall
            case ..<1.55:
                let p = (u - 1.25) / 0.3
                return back * 0.3 * (1 - (1 - p) * (1 - p))  // ease-out: the rebound dies quickly
            case ..<2.1:
                return back * 0.3 * (1 - smoothstep((u - 1.55) / 0.55))
            default:
                return .zero
            }

        case "carry":
            // A stroll out and back, with a little hop while under way — pure translation
            // reads as sliding statues, and the bob is what makes it a walk.
            let (f, moving) = stroll(tm)
            var pos = vec(m.delta) * f
            pos.y += 0.07 * abs(sin(tm * 7)) * moving
            return pos

        case "idle":
            // A slow visible float for the relations whose meaning is simply being somewhere
            // (bei, gegenüber, the formal locatives). Cosine-shaped so it starts at rest and
            // never dips below it — the ball is sitting on something.
            return SIMD3(0, 0.14 * (0.5 - 0.5 * cos(tm * 1.2)), 0)

        default:  // "abandon" moves only the figure; unknown kinds hold still rather than guess.
            return .zero
        }
    }

    /// The reference pieces' displacement — the half of the story the subject can't tell.
    /// mit is only "with" if the figure strolls too; ohne is only "without" because the figure
    /// walks off while the ball stays; statt's block slides out as the ball takes its place.
    private func moverOffset(_ pose: PrepositionScene.Pose, at t: Float) -> SIMD3<Float> {
        guard let m = pose.motion, isResolved else { return .zero }
        let tm = max(0, t - Self.motionLeadIn)
        switch m.kind {
        case "carry":
            let (f, moving) = stroll(tm)
            var pos = vec(m.delta) * f
            pos.y += 0.07 * abs(sin(tm * 7 + 0.9)) * moving   // off-beat: two walkers, not one
            return pos
        case "abandon":
            // Walks off, stays gone for the long dwell, wanders back for the next cycle.
            return vec(m.delta) * loopLeg(tm, dur: 1.3, settle: 2.6, home: 0.9)
        case "swap":
            // The block leaves in step with the ball's arrival, and returns as it leaves.
            return vec(m.delta) * loopLeg(tm, dur: m.dur ?? 1.1)
        case "cause":
            // The shove: accelerates in, holds against the ball, resets with it.
            let u = tm.truncatingRemainder(dividingBy: 4.8)
            let push = vec(m.push)
            switch u {
            case ..<0.15: return .zero
            case ..<0.5:  let p = (u - 0.15) / 0.35; return push * (p * p)
            case ..<3.4:  return push
            default:      return push * (1 - smoothstep((u - 3.4) / 1.0))
            }
        default:
            return .zero
        }
    }

    /// Out, dwell, back, dwell — the carry stroll, plus a "moving" envelope for the walk bob.
    private func stroll(_ tm: Float) -> (f: Float, moving: Float) {
        let u = tm.truncatingRemainder(dividingBy: 4.4)
        func envelope(_ a: Float, _ b: Float) -> Float {
            min(smoothstep((u - a) / 0.15), smoothstep((b - u) / 0.15))
        }
        switch u {
        case ..<1.0:  return (smoothstep(u / 1.0), envelope(0, 1.0))
        case ..<1.9:  return (1, 0)
        case ..<2.9:  return (1 - smoothstep((u - 1.9) / 1.0), envelope(1.9, 2.9))
        default:      return (0, 0)
        }
    }

    private func vec(_ a: [Float]?) -> SIMD3<Float> {
        guard let a, a.count == 3 else { return .zero }
        return SIMD3(a[0], a[1], a[2])
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    /// Whether the subject is *moving* right now — 1 travelling, 0 stopped.
    ///
    /// This, not position, is what drives the case color. Akkusativ is movement and Dativ is
    /// location, so colouring by where the ball *is* (orange at one end, teal at the other, muddy
    /// in between) states the rule wrongly: a ball halfway through a journey is not half-Dativ.
    /// Colouring by whether it is moving says exactly what the grammar says, and it means both
    /// ends of the loop read as Dativ, which is correct — stopped is stopped.
    private func motion(at t: Float) -> Float {
        guard loops, isResolved else { return 0 }
        let s = Self.segments
        let u = t.truncatingRemainder(dividingBy: Self.cycle) / Self.cycle
        // A short crossfade either side of each boundary, so the colour changes with the ball
        // rather than snapping a frame before or after it.
        let fade: Float = 0.05
        func band(_ from: Float, _ to: Float) -> Float {
            min(smoothstep((u - from) / fade), smoothstep((to - u) / fade))
        }
        return max(band(0, s.travelOut), band(s.restLow, s.travelBack))
    }

    /// The subject's color. On reveal it *arrives* — a case color that fades in reads as the
    /// answer, where one that was there all along reads as decoration.
    private func tint(at t: Float) -> Color {
        let neutral = Color(white: 0.74)
        switch mode {
        case .neutral:
            return neutral
        case .resolved(let group):
            let settled = group == .wechsel
                // A two-way preposition has no single color: it is Akkusativ while it moves and
                // Dativ once it stops, so the loop states the rule as it happens.
                ? PrepositionCase.dativ.color.mix(with: PrepositionCase.akkusativ.color,
                                                  by: Double(motion(at: t)))
                : group.color
            return neutral.mix(with: settled, by: Double(smoothstep((t - 0.3) / 0.45)))
        }
    }

    private func smoothstep(_ x: Float) -> Float {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}

// MARK: - RealityKit

/// One persistent canvas that swaps its content, rather than one RealityView per word.
///
/// This matters for more than tidiness: `RealityView`'s `make` closure runs **once**. Loading the
/// USDZ in there means a change of `asset` never reaches the scene — advancing to the next drill
/// question would leave the previous preposition on screen. The load lives in `.task(id: asset)`
/// instead, which re-runs on change and swaps the entity under the same camera and lights, so one
/// RealityKit surface serves a whole round or a whole card deck.
private struct PrepositionRealityScene: View {
    let asset: String
    /// The subject's displacement from its resting pose, already computed per-kind upstream.
    var subjectOffset: SIMD3<Float>
    /// Displacement for the moving reference pieces (mit's companion, ohne's departing figure,
    /// statt's displaced block). Zero for every other relation.
    var moverOffset: SIMD3<Float>
    /// Substring naming which pieces move; nil moves all of them (mit and ohne's figure is the
    /// whole reference). Matched against USD prim names, which mangle dots — hence substrings.
    var moverFilter: String?
    var tint: Color
    var assembly: Float

    @State private var root = Entity()
    /// The entity carrying the authored name — an Xform, whose mesh is a child.
    @State private var subject: Entity?
    /// The mesh under it, which is what actually holds the material.
    @State private var subjectModel: ModelEntity?
    @State private var restPosition: SIMD3<Float> = .zero
    /// Reference pieces with their final position and the off-scene position they fly in from.
    @State private var pieces: [(entity: Entity, home: SIMD3<Float>, away: SIMD3<Float>)] = []

    var body: some View {
        canvas.task(id: asset) { await load(asset) }
    }

    /// Swap in a new relation under the existing camera and lights.
    private func load(_ name: String) async {
        subject = nil
        subjectModel = nil
        pieces = []
        root.children.removeAll()

        guard let scene = try? await Entity(named: name, in: .main) else { return }
        // Geometry only, whatever the asset claims: the canvas builds its own camera and
        // light rig, and a camera smuggled in by an exporter (three of them rode inside an
        // early story USDZ) can hijack or crash the device renderer.
        scene.stripCamerasAndLights()
        root.addChild(scene)

        // Baked clips ride along: a prop authored with its own animation (a wagging tail, an
        // opening lid — see tools/genprops) starts looping on load. Ambient life only — the
        // case-teaching motion stays in the pose functions above, so a clip playing on the
        // question side leaks nothing. Today's primitive scenes carry no clips; this is a no-op
        // until an animated prop ships.
        for animation in scene.availableAnimations {
            scene.playAnimation(animation.repeat())
        }

        // USD wraps each mesh in an Xform that carries the authored name — `def Xform "subject"
        // { def Mesh "Sphere" }` — so the name lives on the parent, not on the ModelEntity.
        // Matching against ModelEntity names alone never hits, and a `?? models.last` fallback
        // then silently recolors and displaces a table leg. Walk every entity, and if the
        // subject genuinely isn't there, do nothing rather than pose the wrong object.
        let named = scene.firstDescendant { $0.name.lowercased().contains("subject") }
        guard let named else { return }

        restPosition = named.position(relativeTo: root)
        subjectModel = named as? ModelEntity ?? named.firstDescendant { $0 is ModelEntity } as? ModelEntity

        // Entry directions are derived, not authored: each piece flies in from the direction it
        // already sits in relative to the scene centre. The `zwischen` bars come in from the
        // sides, a table drops from below — all of it falls out of the geometry, with no
        // per-preposition choreography to keep in sync.
        pieces = scene.children.compactMap { child in
            guard child !== named, !child.isAncestor(of: named) else { return nil }
            let home = child.position(relativeTo: root)
            let outward = home == .zero ? SIMD3<Float>(0, -1, 0) : normalize(home)
            return (child, home, home + outward * 3.2)
        }
        // Assigned last: `update` bails until this is set, so nothing poses a half-built scene.
        subject = named

        // Backstop for the fly-in. Every pose here is written from the timeline clock, so if that
        // clock stalls — the view pauses off-screen and never reappears, an update is dropped —
        // the pieces stay stranded between their entry point and home. That doesn't read as a
        // missing animation, it reads as a broken picture: a floor slab adrift under nothing.
        // A second in, write the assembled pose once from a clock this view doesn't own. A live
        // timeline has already reached the same values by then, so it costs a redundant write.
        // Pieces only: the subject may legitimately be mid-choreography at this point, and a
        // one-off write would snap it home for a frame.
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        for piece in pieces { piece.entity.setPosition(piece.home, relativeTo: root) }
    }

    private var canvas: some View {
        RealityView { content in
            // Same raked three-quarter framing and key/rim/fill rig as the Blender `dim` look,
            // so a live scene and a rendered still are recognisably the same picture.
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 30
            camera.position = [4.0, 3.6, 10.6]
            camera.look(at: [0, 0.4, 0], from: camera.position, relativeTo: nil)
            content.add(camera)

            let key = DirectionalLight()
            key.light.intensity = 5200
            key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 24, depthBias: 1.2)
            key.look(at: .zero, from: [-4.6, 6.4, 4.2], relativeTo: nil)
            content.add(key)

            let rim = DirectionalLight()
            rim.light.intensity = 3000
            rim.look(at: .zero, from: [4.8, 2.6, -4.4], relativeTo: nil)
            content.add(rim)

            let fill = DirectionalLight()
            fill.light.intensity = 900
            fill.look(at: .zero, from: [4.2, 0.6, 6.4], relativeTo: nil)
            content.add(fill)

            // Content is added by `load`, not here — see the type comment.
            content.add(root)
        } update: { _ in
            guard let subject else { return }
            // `setPosition(_:relativeTo:)`, not `.position =`. The positions were *read* in root
            // space, and `.position` writes in **parent** space — and the USD export puts a
            // Z-up→Y-up rotation on the scene root, so the two spaces differ. Writing one into
            // the other double-transforms every piece and scatters the table's legs.
            subject.setPosition(restPosition + subjectOffset, relativeTo: root)
            subjectModel?.tint(tint)
            for piece in pieces {
                var position = mix(piece.away, piece.home, t: assembly)
                if moverOffset != .zero,
                   moverFilter.map({ piece.entity.name.lowercased().contains($0) }) ?? true {
                    position += moverOffset
                }
                piece.entity.setPosition(position, relativeTo: root)
            }
        }
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}

private extension Entity {
    /// Remove every camera and light in this subtree. Shipped scene assets are geometry-only
    /// by contract, but a stale bundle may still carry an exporter's judge rig — and a scene
    /// camera fights the canvas's own, up to crashing the renderer on device.
    func stripCamerasAndLights() {
        var doomed: [Entity] = []
        var queue: [Entity] = [self]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next.components.has(PerspectiveCameraComponent.self)
                || next.components.has(DirectionalLightComponent.self)
                || next.components.has(PointLightComponent.self)
                || next.components.has(SpotLightComponent.self) {
                doomed.append(next)
            } else {
                queue.append(contentsOf: next.children)
            }
        }
        for entity in doomed { entity.removeFromParent() }
    }

    /// Breadth-first search over the whole subtree — *any* entity, not just `ModelEntity`,
    /// because USD hangs the authored name on an Xform wrapping the mesh.
    func firstDescendant(where matches: (Entity) -> Bool) -> Entity? {
        var queue: [Entity] = Array(children)
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if matches(next) { return next }
            queue.append(contentsOf: next.children)
        }
        return nil
    }

    func isAncestor(of entity: Entity) -> Bool {
        var parent = entity.parent
        while let current = parent {
            if current === self { return true }
            parent = current.parent
        }
        return false
    }
}

private extension ModelEntity {
    /// Re-tint the first material. One asset serves every case color and both themes because of
    /// this; pre-rendered frames would need a variant per color.
    func tint(_ color: Color) {
        guard var material = model?.materials.first as? PhysicallyBasedMaterial else { return }
        material.baseColor = .init(tint: UIColor(color))
        model?.materials[0] = material
    }
}

#Preview("Scene states") {
    VStack(spacing: 16) {
        PrepositionSceneView(word: "zwischen", mode: .neutral)
            .frame(height: 180)
        PrepositionSceneView(word: "zwischen", mode: .resolved(.wechsel), loops: true)
            .frame(height: 180)
    }
}
