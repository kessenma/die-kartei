//
//  EndingBlocksScene.swift
//  german-ai-flashcards
//
//  A determiner as 3D blocks: the stem in ink, the ending in its case color, a thin plate in the
//  noun's gender color. Swap the case and the old ending flies off while the new one drops onto
//  the stem. The Endungs-Werkstatt, the endings table, the Schnellrunde and Bau das Wort all show
//  words through this one view.
//
//  The letters are extruded at runtime (`MeshResource(extruding:)`), not shipped as assets, so
//  any stem works and the app grows by nothing. Like every 3D canvas here:
//    - one camera, built once and re-aimed, never rebuilt (`.id()` would drop the render context);
//    - motion is written per frame from `EndingBlocksPose`, under a `TimelineView` that runs only
//      while something moves, so an idle canvas holds no display link;
//    - Stills Only (`LightweightGraphics`) and Reduce Motion get `EndingBlocksFlat`, which builds
//      no RealityKit at all;
//    - at most one of these is live on a screen (docs/PREPOSITION_3D.md).
//

import RealityKit
import SwiftUI

struct EndingBlocksScene: View {
    let state: EndingBlocksState
    /// Every form the canvas should have room for, so the camera holds still while the learner
    /// flips through a stem's cases. Empty frames the word on show.
    var framing: [KasusFormParts] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if LightweightGraphics.isActive || reduceMotion {
                EndingBlocksFlat(state: state)
            } else {
                EndingBlocksCanvas(state: state, framing: framing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
    }
}

// MARK: - Colors

enum EndingBlocksInk {
    /// die Figur's ink: charcoal on a light ground, Grundform cream on a dark one.
    static let stem = FigurScene.defaultTint
    /// An open slot, a wrong pick, and every ending before it lands.
    static let neutral = Color(light: 0xB9BEC6, dark: 0x6E747D)

    static func ending(_ kasus: GrammarCase?) -> Color {
        kasus.map(CasePalette.color) ?? neutral
    }
}

// MARK: - Canvas

private struct EndingBlocksCanvas: View {
    let state: EndingBlocksState
    let framing: [KasusFormParts]

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme

    @State private var camera = PerspectiveCamera()
    @State private var root = Entity()
    /// Stem, ending and plate: everything that rises together.
    @State private var word = Entity()
    @State private var stem = EndingBlock()
    @State private var ending = EndingBlock()
    @State private var plate = ModelEntity()
    @State private var outgoing = EndingBlock()
    @State private var rejected = EndingBlock()
    @State private var meshes = EndingBlocksMeshes()

    @State private var shown: EndingBlocksState?
    @State private var previousKasus: GrammarCase?
    @State private var transition: EndingBlocksTransition = .hold
    @State private var startedAt = Date.distantPast
    @State private var layout = EndingBlocksLayout()
    @State private var outgoingSeat: SIMD3<Float> = .zero
    @State private var isAnimating = false
    @State private var stopper: Task<Void, Never>?
    @State private var aspect: Float = 2
    @State private var framedKey = ""

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            canvas(beat: context.date)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            guard size.height > 0 else { return }
            aspect = Float(size.width / size.height)
            frame(force: true)
        }
        .task(id: state) { await show(state) }
        .onChange(of: framing) { frame(force: false) }
        .onChange(of: colorScheme) { paint(tint: 1) }
        .onDisappear { stopper?.cancel(); isAnimating = false }
    }

    private func canvas(beat: Date) -> some View {
        RealityView { content in
            camera.camera.fieldOfViewInDegrees = 30
            content.add(camera)
            for light in SceneRig.lights() { content.add(light) }
            word.addChild(plate)
            word.addChild(stem)
            word.addChild(ending)
            root.addChild(word)
            root.addChild(outgoing)
            root.addChild(rejected)
            outgoing.isEnabled = false
            rejected.isEnabled = false
            word.isEnabled = shown != nil
            content.add(root)
        } update: { _ in
            pose(at: Float(beat.timeIntervalSince(startedAt)))
        }
    }

    // MARK: Showing a state

    private func show(_ next: EndingBlocksState) async {
        let previous = shown
        let change = EndingBlocksTransition(from: previous, to: next)
        if change == .hold, previous != nil {
            shown = next
            paint(tint: 1)
            return
        }

        var texts = [next.stem, next.ending]
        if case .swap(let from, _) = change { texts.append(from) }
        if case .bounceThenSnap(let wrong) = change { texts.append(wrong) }
        await meshes.prepare(texts)
        guard !Task.isCancelled else { return }

        previousKasus = previous?.kasus
        outgoingSeat = layout.ending
        shown = next
        transition = change
        layout = meshes.layout(stem: next.stem, ending: next.ending)

        meshes.fill(stem, with: next.stem)
        stem.position = layout.stem
        meshes.fill(ending, with: next.ending)
        plate.model = ModelComponent(mesh: .generateBox(width: layout.width + 0.4, height: 0.09,
                                                        depth: meshes.depth + 0.55, cornerRadius: 0.03),
                                     materials: [])
        plate.position = [0, -0.07, 0]
        word.isEnabled = true

        if case .swap(let from, _) = change {
            meshes.fill(outgoing, with: from)
        }
        if case .bounceThenSnap(let wrong) = change {
            meshes.fill(rejected, with: wrong)
        }

        frame(force: false)
        paint(tint: 0)
        startedAt = .now
        animate(for: change.duration)
    }

    /// Runs the timeline for the transition plus a short tail, so the settled pose is presented
    /// before the display link is released.
    private func animate(for duration: Double) {
        stopper?.cancel()
        isAnimating = true
        stopper = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration + 0.25))
            guard !Task.isCancelled else { return }
            isAnimating = false
        }
    }

    // MARK: Per-frame pose

    private func pose(at t: Float) {
        guard shown != nil else { return }
        let pose = EndingBlocksPose.at(transition, time: t)

        word.position = [0, pose.wordDrop, 0]
        word.scale = SIMD3(repeating: pose.wordScale)

        let squash = pose.stemSquash * 0.09
        stem.scale = [1 + squash * 0.5, 1 - squash, 1 + squash * 0.5]
        ending.position = layout.ending + [0, pose.endingDrop, 0]
        ending.scale = SIMD3(repeating: pose.endingScale)
        paint(tint: pose.endingTint)

        place(outgoing, exit: pose.outgoing, seat: outgoingSeat)
        place(rejected, exit: pose.rejected, seat: layout.ending)
    }

    private func place(_ block: EndingBlock, exit: EndingBlocksPose.Exit?, seat: SIMD3<Float>) {
        guard let exit else { block.isEnabled = false; return }
        block.isEnabled = true
        block.transform = Transform(scale: SIMD3(repeating: exit.scale),
                                    rotation: simd_quatf(angle: exit.roll, axis: [0, 0, 1]),
                                    translation: seat + [exit.dx, exit.dy, 0])
    }

    // MARK: Color

    /// Writes every material for the current state. `tint` runs the landing ending from grey to
    /// its case color (from the old case color, on a recolor).
    private func paint(tint: Float) {
        guard let shown else { return }
        let neutral = EndingBlocksInk.neutral.sceneColor(in: environment)
        let target = EndingBlocksInk.ending(shown.kasus).sceneColor(in: environment)
        let from = transition == .recolor
            ? EndingBlocksInk.ending(previousKasus).sceneColor(in: environment) : neutral
        // An empty slot is a ghost of the block that would be there.
        let slotOpacity: Float = shown.isOpen ? 0.3 : 0.4

        stem.paint(EndingBlocksInk.stem.sceneColor(in: environment))
        ending.paint(Self.mix(from, target, tint), opacity: shown.ending.isEmpty ? slotOpacity : 1)
        plate.model?.materials = [EndingBlock.material(GenderPalette.color(shown.genus).sceneColor(in: environment),
                                                       roughness: 0.7)]
        if case .swap(let from, let wasOpen) = transition {
            let color = wasOpen ? neutral : EndingBlocksInk.ending(previousKasus).sceneColor(in: environment)
            outgoing.paint(color, opacity: from.isEmpty ? slotOpacity : 1)
        }
        if case .bounceThenSnap(let wrong) = transition {
            rejected.paint(neutral, opacity: wrong.isEmpty ? slotOpacity : 1)
        }
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ t: Float) -> UIColor {
        guard t < 1 else { return b }
        guard t > 0 else { return a }
        var (ar, ag, ab, aa): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (br, bg, bb, ba): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let k = CGFloat(t)
        return UIColor(red: ar + (br - ar) * k, green: ag + (bg - ag) * k,
                       blue: ab + (bb - ab) * k, alpha: aa + (ba - aa) * k)
    }

    // MARK: Framing

    /// Re-aims only when what has to fit changed: a new stem, a new framing set, a new size.
    /// Flipping through one stem's cases keeps the camera still.
    private func frame(force: Bool) {
        guard let shown else { return }
        let key = "\(shown.stem)|\(framing.map(\.word).joined(separator: ","))"
        guard force || key != framedKey else { return }
        framedKey = key
        let widest = ([layout.width] + framing.map { meshes.estimatedWidth($0) }).max() ?? 1
        // Taller than a „d“: the house angle looks down, so the plate's far edge and the letters'
        // tops both need room.
        let distance = EndingBlocksFraming.distance(width: widest + 0.4, height: 1.7,
                                                    depth: meshes.depth + 0.55, aspect: aspect)
        SceneRig.aim(camera, at: [0, 0.4, 0], distance: distance)
    }
}

// MARK: - Blocks

/// One block: a holder posed at the block's bottom centre (so squashes and exits pivot there),
/// with the mesh as its child, offset and scaled to sit on that point.
final class EndingBlock: Entity {
    let body = ModelEntity()

    required init() {
        super.init()
        addChild(body)
    }

    func paint(_ color: UIColor, opacity: Float = 1) {
        body.model?.materials = [Self.material(color, opacity: opacity)]
    }

    static func material(_ color: UIColor, opacity: Float = 1, roughness: Float = 0.45) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        if opacity < 1 { material.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return material
    }
}

/// Where the blocks' bottom centres sit, the word centred on x = 0 with its baseline on y = 0.
struct EndingBlocksLayout {
    var stem: SIMD3<Float> = .zero
    var ending: SIMD3<Float> = .zero
    var width: Float = 1
}

// MARK: - Meshes

/// Extruded letter meshes, built once per string and kept for the canvas's life. The canvas
/// works in „d“ heights (a „d“ is 1 unit tall), whatever units the text extruder uses.
@MainActor
final class EndingBlocksMeshes {
    private var cache: [String: MeshResource] = [:]
    /// Mesh units per „d“ height, known once „d“ is built.
    private var unit: Float = 0.01
    private var baseline: Float = 0

    /// The space between stem and ending, so they read as two pieces.
    let gap: Float = 0.26
    /// How deep the letters are extruded, in „d“ heights.
    let depth: Float = 0.34
    /// The empty slot: about a lowercase letter.
    let slot = SIMD3<Float>(0.42, 0.56, 0.34)

    private static let pointSize: CGFloat = 100

    func prepare(_ texts: [String]) async {
        if cache["d"] == nil {
            await build("d")
            if let d = cache["d"]?.bounds, d.extents.y > 0 {
                unit = 1 / d.extents.y
                baseline = d.min.y
            }
        }
        for text in Set(texts) where !text.isEmpty && cache[text] == nil {
            await build(text)
        }
    }

    private func build(_ text: String) async {
        var string = AttributedString(text)
        // A little tracking: extruded and seen from the side, Futura's tight letters run together.
        #if canImport(UIKit)
        string.uiKit.font = Self.font
        string.uiKit.kern = Self.pointSize * 0.06
        #else
        string.appKit.font = Self.font
        string.appKit.kern = Self.pointSize * 0.06
        #endif
        var options = MeshResource.ShapeExtrusionOptions()
        options.extrusionMethod = .linear(depth: Float(Self.pointSize) * 0.34)
        options.chamferRadius = Float(Self.pointSize) * 0.025
        options.chamferMode = .both
        guard let mesh = try? await MeshResource(extruding: string, extrusionOptions: options) else { return }
        cache[text] = mesh
    }

    private static var font: UIFont {
        UIFont(name: "Futura-Bold", size: pointSize) ?? .systemFont(ofSize: pointSize, weight: .heavy)
    }

    /// Puts `text` on the block, or the empty slot for „“.
    func fill(_ block: EndingBlock, with text: String) {
        if !text.isEmpty, let mesh = cache[text] {
            let box = mesh.bounds
            block.body.model = ModelComponent(mesh: mesh, materials: [])
            block.body.scale = SIMD3(repeating: unit)
            block.body.position = -SIMD3(box.center.x, baseline, box.center.z) * unit
        } else {
            block.body.model = ModelComponent(
                mesh: .generateBox(width: slot.x, height: slot.y, depth: slot.z, cornerRadius: 0.05),
                materials: [])
            block.body.scale = .one
            block.body.position = [0, slot.y / 2, 0]
        }
    }

    func width(_ text: String) -> Float {
        guard !text.isEmpty else { return slot.x }
        guard let mesh = cache[text] else { return Float(text.count) * 0.62 }
        return mesh.bounds.extents.x * unit
    }

    /// A word's width before all its meshes exist, from the letters already measured.
    func estimatedWidth(_ parts: KasusFormParts) -> Float {
        let measured = cache.keys.filter { !$0.isEmpty }
        let perLetter = measured.isEmpty ? 0.62
            : measured.map { width($0) / Float($0.count) }.reduce(0, +) / Float(measured.count)
        func w(_ s: String) -> Float {
            s.isEmpty ? slot.x : (cache[s] != nil ? width(s) : perLetter * Float(s.count))
        }
        return w(parts.stem) + gap + w(parts.ending)
    }

    /// Stem then ending, a gap apart, the whole word centred on x = 0.
    func layout(stem: String, ending: String) -> EndingBlocksLayout {
        let stemWidth = width(stem)
        let endingWidth = width(ending)
        let total = stemWidth + gap + endingWidth
        let left = -total / 2
        return EndingBlocksLayout(stem: [left + stemWidth / 2, 0, 0],
                                  ending: [left + stemWidth + gap + endingWidth / 2, 0, 0],
                                  width: total)
    }
}

#Preview("Ending blocks") {
    VStack(spacing: 20) {
        EndingBlocksScene(state: .built(KasusFormParts(stem: "d", ending: "em"), kasus: .dativ, genus: .der))
            .frame(height: 160)
        EndingBlocksScene(state: .built(KasusFormParts(stem: "mein", ending: "en"), kasus: .akkusativ, genus: .der))
            .frame(height: 160)
        EndingBlocksScene(state: .built(KasusFormParts(stem: "kein", ending: ""), kasus: .nominativ, genus: .das))
            .frame(height: 160)
    }
    .padding()
}
