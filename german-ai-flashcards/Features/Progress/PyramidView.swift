//
//  PyramidView.swift
//  german-ai-flashcards
//
//  Die Lernpyramide — the learning path as a building. Six layers stack from the Fundament
//  (prepositions — every sentence stands on its case) to the Spitze (conversation), each filling
//  in from ghost to solid as the underlying mastery accrues (`PyramidService` does the math from
//  live stats; nothing is stored).
//
//  Three renderings of the same stack, one vocabulary:
//  - `PyramidView` — the full screen: one live RealityKit canvas (the app's one-live-scene rule)
//    over a tappable layer list that routes into each layer's activity.
//  - `PyramidGlyph` — a 2D trapezoid stack for rows and teasers (the "stills in lists" rule).
//  - `PyramidSceneView` — the canvas. Procedural slabs for now, in the preposition scenes'
//    Bauhaus vocabulary (charcoal, flat shading, same camera/light rig). When Blender renders
//    land (`tools/blender/pyramid_render.py`, see docs/GAMIFICATION.md), they swap in here —
//    one asset per layer state, same naming discipline as the prep scenes.
//

import SwiftUI
import SwiftData
import RealityKit

// MARK: - Full screen

struct PyramidView: View {
    @Bindable var coordinator: GenerationCoordinator

    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query private var prepositionStats: [PrepositionStat]
    @Query private var cards: [SavedCard]
    @Query private var storyAttempts: [StoryQuizAttempt]
    @Query private var profiles: [LearnerProfile]
    @Query private var studyDays: [StudyDay]
    @Query private var articleStats: [ArticleWordStat]
    @Query private var matchingStats: [MatchingPairStat]

    @Query private var conversations: [ChatConversation]

    @State private var showPlacement = false
    /// The placement estimate lives in UserDefaults, which SwiftUI can't observe. Bumping this
    /// after a retake or a clear is what re-reads it into the layers above.
    @State private var placementRevision = 0

    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }

    private var layers: [PyramidLayerState] {
        PyramidService.layers(from: PyramidService.snapshot(
            prepositionStats: prepositionStats,
            cards: cards,
            storyAttempts: storyAttempts,
            profile: profiles.first,
            studyDays: studyDays,
            articleStats: articleStats,
            matchingStats: matchingStats,
            placement: placement,
            conversations: conversations
        ))
    }

    /// Re-read whenever `placementRevision` changes — the estimate lives in UserDefaults, which
    /// SwiftUI can't observe on its own.
    private var placement: PlacementResult? {
        _ = placementRevision
        return PlacementService.current
    }

    var body: some View {
        List {
            Section {
                PyramidSceneView(layers: layers)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                HStack {
                    let earned = PyramidService.overallEarnedFill(layers)
                    let total = PyramidService.overallFill(layers)
                    Label("\(percent(earned)) built", systemImage: "pyramid.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if total > earned + 0.005 {
                        Text("· \(percent(total - earned)) estimated")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(completionCaption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("Deine Pyramide · Your Pyramid").themedSectionHeader()
            } footer: {
                Text("Each layer is built from real skill — prepositions, matured words, understood stories, real conversations. Tap a layer to keep building it.")
                    .font(.caption2)
            }
            .themedListRow()

            Section {
                // Top of the pyramid first on screen — the peak is what you're working toward.
                ForEach(layers.reversed()) { layer in
                    layerRow(layer)
                }
            } header: {
                Text("Ebenen · Layers").themedSectionHeader()
            }
            .themedListRow()

            placementSection
        }
        .navigationTitle("Lernpyramide")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .themedListScreen()
        .onAppear { celebrateCompletedLayers() }
        .sheet(isPresented: $showPlacement) {
            PlacementQuizView(modelManager: coordinator.modelManager) { _ in
                placementRevision += 1
            }
        }
    }

    // MARK: - Placement

    /// The way in and out of the placement estimate. Lives on this screen because this is where an
    /// estimate visibly does something: the ghost fill above is the only thing it produces.
    private var placementSection: some View {
        Section {
            Button { showPlacement = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(Color(.tertiarySystemFill),
                                    in: RoundedRectangle(cornerRadius: theme.innerRadius(9), style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(placementTitle)
                            .themedLabel(.subheadline, size: 15)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text(placementSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if PlacementService.current != nil {
                Button("Remove the estimate", role: .destructive) {
                    PlacementService.clear()
                    placementRevision += 1
                }
                .font(.subheadline)
            }
        } header: {
            Text("Einstufung · Placement").themedSectionHeader()
        } footer: {
            Text("An estimate only outlines a layer. Removing it clears the outlines and leaves everything you've actually proven untouched.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var placementTitle: String {
        guard let placement = PlacementService.current else { return "Already know some German?" }
        if placement.declaredBeginner { return "Starting from zero" }
        return "Placed at \(placement.estimatedLevel.rawValue)"
    }

    private var placementSubtitle: String {
        guard let placement = PlacementService.current else {
            return "Take a three-minute check to fill in what you already know."
        }
        let when = placement.takenAt.formatted(date: .abbreviated, time: .omitted)
        return placement.declaredBeginner
            ? "Nothing estimated. Take the check any time."
            : "Checked \(when). Retake it to re-measure."
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }

    /// A friendly sense of where the build stands — German flavor, English gloss.
    private var completionCaption: String {
        let done = layers.filter(\.isComplete).count
        if done == layers.count { return "Vollendet! · Complete — stark!" }
        if done > 0 { return "\(done) of \(layers.count) layers complete" }
        return "Der Grundstein ist gelegt · The foundation stone is laid"
    }

    /// Fires the layer-complete celebration for any layer that finished since the last visit.
    private func celebrateCompletedLayers() {
        let manager = coordinator.modelManager
        for layer in layers where layer.isComplete {
            CelebrationCenter.shared.presentLayerComplete(layer.id, manager: manager)
        }
    }

    // MARK: - Layer rows

    @ViewBuilder
    private func layerRow(_ layer: PyramidLayerState) -> some View {
        NavigationLink { destination(for: layer.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: layer.id.systemImage)
                    .font(.title3)
                    .foregroundStyle(layer.id.tint)
                    .frame(width: 38, height: 38)
                    .background(layer.id.tint.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: theme.innerRadius(9), style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(layer.id.germanTitle)
                            .themedLabel(.subheadline, size: 15)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        if layer.isComplete {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    Text(layer.id.englishSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(layer.detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    ProgressView(value: layer.fill)
                        .tint(layer.id.tint)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel("\(layer.id.germanTitle), \(Int((layer.fill * 100).rounded())) Prozent")
    }

    /// Each layer routes to its own activity — the same destinations the Activity hub uses.
    @ViewBuilder
    private func destination(for id: PyramidLayerID) -> some View {
        switch id {
        case .fundament:
            PrepositionHubView(modelManager: coordinator.modelManager)
        case .wortschatzA1:
            GoetheVocabListView(level: .a1, onStartStudy: launchGoethe, onStartPastTenseStudy: launchPastTense)
        case .geschichtenA1:
            StoryListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
        case .grammatikKern:
            GrammarHubView(
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService,
                onStartFlipCards: launchGrammarFlip,
                onStartMultipleChoice: launchGrammarMC,
                onStartPastTenseStudy: launchPastTense
            )
        case .vertiefungA2:
            GoetheVocabListView(level: .a2, onStartStudy: launchGoethe, onStartPastTenseStudy: launchPastTense)
        case .spitze:
            ConversationListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
        }
    }

    private func launchGoethe(_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ label: String) {
        router.launch(.cardDeck(deckStore.goetheSession(cards: cards, topic: topic, style: style, label: label)))
    }

    private func launchPastTense(_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ label: String) {
        router.launch(.cardDeck(deckStore.pastTenseSession(cards: cards, topic: topic, style: style, label: label)))
    }

    private func launchGrammarFlip(_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ label: String) {
        router.launch(.cardDeck(deckStore.grammarFlipSession(cards: cards, topic: topic, style: style, label: label)))
    }

    private func launchGrammarMC(_ category: GrammarCategory, _ hints: Bool) {
        router.launch(.grammarMultipleChoice(category: category, showHints: hints))
    }
}

// MARK: - 2D glyph (rows, teasers)

/// The pyramid as a flat trapezoid stack — the list-safe rendering, same fill logic as the 3D
/// scene: ghost layers read as empty outline, partial layers carry their tint at low strength,
/// complete layers are solid.
struct PyramidGlyph: View {
    let layers: [PyramidLayerState]

    var body: some View {
        Canvas { context, size in
            let count = layers.count
            guard count > 0 else { return }
            let gap: CGFloat = max(1, size.height * 0.02)
            let layerHeight = (size.height - gap * CGFloat(count - 1)) / CGFloat(count)

            // Draw top → bottom; the top slice is the narrowest.
            for (row, layer) in layers.reversed().enumerated() {
                let k = CGFloat(row)
                let topFraction = 0.14 + 0.72 * (k / CGFloat(count))
                let bottomFraction = 0.14 + 0.72 * ((k + 1) / CGFloat(count))
                let y = k * (layerHeight + gap)

                var path = Path()
                path.move(to: CGPoint(x: size.width * (1 - topFraction) / 2, y: y))
                path.addLine(to: CGPoint(x: size.width * (1 + topFraction) / 2, y: y))
                path.addLine(to: CGPoint(x: size.width * (1 + bottomFraction) / 2, y: y + layerHeight))
                path.addLine(to: CGPoint(x: size.width * (1 - bottomFraction) / 2, y: y + layerHeight))
                path.closeSubpath()

                // Solid = proven. A dashed outline marks a layer standing partly on an estimate,
                // so the glyph carries the same earned/estimated distinction as the full screen.
                let color: Color = layer.earnedFill > 0
                    ? layer.id.tint.opacity(layer.isComplete ? 1 : 0.3 + 0.45 * layer.earnedFill)
                    : Color(.tertiarySystemFill)
                context.fill(path, with: .color(color))

                if layer.hasEstimate {
                    context.stroke(
                        path,
                        with: .color(layer.id.tint.opacity(0.6)),
                        style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2])
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 3D scene

/// One live canvas, procedural slabs, the preposition rig's camera and lights. Render states
/// follow the same ghost → building → solid language as the glyph; the active layer (the lowest
/// unfinished one) breathes gently so the eye lands on where to build next.
struct PyramidSceneView: View {
    let layers: [PyramidLayerState]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = true
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if reduceMotion {
                PyramidRealityScene(layers: layers, angle: 0.6, pulse: 0)
            } else {
                TimelineView(.animation(paused: !isVisible)) { timeline in
                    let t = Float(timeline.date.timeIntervalSince(startedAt))
                    PyramidRealityScene(layers: layers, angle: t * 0.45, pulse: t)
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

/// The RealityKit half. Geometry is built once; the `update` pass re-tints, re-ghosts and
/// re-poses per frame, so a layer that completes mid-visit visibly settles into place.
private struct PyramidRealityScene: View {
    let layers: [PyramidLayerState]
    /// Turntable angle (radians).
    let angle: Float
    /// Free-running clock for the active layer's pulse; 0 freezes it.
    let pulse: Float

    @State private var root = Entity()
    @State private var slabs: [(id: PyramidLayerID, entity: ModelEntity)] = []
    @State private var cap: ModelEntity?

    /// The lowest unfinished layer — where the build continues.
    private var activeLayer: PyramidLayerID? {
        layers.first(where: { !$0.isComplete })?.id
    }

    private var allComplete: Bool { layers.allSatisfy(\.isComplete) }

    var body: some View {
        RealityView { content in
            // The same raked three-quarter framing and key/rim/fill rig as the preposition
            // scenes, so the pyramid reads as the same world, not a new one.
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 30
            camera.position = [3.4, 2.9, 9.2]
            camera.look(at: [0, 0.1, 0], from: camera.position, relativeTo: nil)
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

            // Geometry is added by the task below, not here — the same one-canvas rule as the
            // preposition scenes: `make` runs once, so content arrives from a task and the
            // update pass re-poses it.
            content.add(root)
        } update: { _ in
            root.transform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
            for slab in slabs {
                let state = layers.first { $0.id == slab.id }
                let total = state?.fill ?? 0
                let earned = state?.earnedFill ?? 0
                let ghosted = total <= 0

                // Two dimensions, two channels: how *solid* a slab stands comes from everything
                // credited, while how much *color* it carries comes only from what's been proven.
                // An estimated layer is therefore visibly there but drained of its tint — present,
                // not earned — which is the whole distinction the pyramid is trying to draw.
                let opacity: Float = ghosted ? 0.13 : (earned >= 1 ? 1 : Float(0.28 + 0.5 * total))
                slab.entity.components.set(OpacityComponent(opacity: opacity))

                let earnedShare = total > 0 ? earned / total : 0
                let color = ghosted
                    ? Color(white: 0.42)
                    : slab.id.tint.mix(with: Color(white: 0.45), by: 1 - earnedShare)
                tint(slab.entity, color)

                // The active layer breathes; everything else stands still.
                let breathing = slab.id == activeLayer && !allComplete
                let scale: Float = breathing ? 1 + 0.025 * (0.5 + 0.5 * sin(pulse * 2.2)) : 1
                slab.entity.scale = SIMD3(repeating: scale)
            }
            cap?.isEnabled = allComplete
            if let cap { tint(cap, Color(white: 0.22)) }
        }
        .task { buildStack() }
    }

    /// Builds the six slabs once, bottom layer first. When the Blender renders land they replace
    /// this geometry under the same canvas — the camera, lights and update pass stay.
    private func buildStack() {
        root.children.removeAll()
        slabs = []

        let ordered = PyramidLayerID.allCases   // fundament … spitze, bottom → top
        let count = CGFloat(ordered.count)
        let slabHeight: Float = 0.30
        let gap: Float = 0.05
        let total = Float(count) * slabHeight + Float(count - 1) * gap

        for (index, layer) in ordered.enumerated() {
            let width: Float = 2.5 - Float(index) * 0.36
            let slab = ModelEntity(
                mesh: .generateBox(size: [width, slabHeight, width]),
                materials: [pyramidMaterial(Color(white: 0.42))]
            )
            let y = -total / 2 + slabHeight / 2 + Float(index) * (slabHeight + gap)
            slab.position = [0, y, 0]
            root.addChild(slab)
            slabs.append((layer, slab))
        }

        // The capstone: the preposition scenes' ball, set on the peak once every layer stands.
        let ball = ModelEntity(
            mesh: .generateSphere(radius: 0.17),
            materials: [pyramidMaterial(Color(white: 0.22))]
        )
        ball.position = [0, total / 2 + 0.2, 0]
        ball.isEnabled = false
        root.addChild(ball)
        cap = ball
    }

    private func pyramidMaterial(_ color: Color) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(color))
        material.roughness = 0.65
        return material
    }

    private func tint(_ entity: ModelEntity, _ color: Color) {
        guard var material = entity.model?.materials.first as? PhysicallyBasedMaterial else { return }
        material.baseColor = .init(tint: UIColor(color))
        entity.model?.materials[0] = material
    }
}

// MARK: - Previews

#Preview("Glyph") {
    let layers = PyramidService.layers(from: PyramidSnapshot(
        masteredPrepositions: 20, corePrepositions: 28,
        learnedA1Words: 130, a1WordGoal: 585,
        a1StoriesPassed: 3,
        solidCoreGrammar: 2, coreGrammarCount: 4,
        learnedA2Words: 40, a2WordGoal: 200, a2StoriesPassed: 1,
        conversations: 7, conversationGoal: 20
    ))
    PyramidGlyph(layers: layers)
        .frame(width: 120, height: 100)
        .padding()
}

/// A learner who placed at B1 on day one: vocabulary and grammar credited as estimate (ghost),
/// stories and conversation still untouched — the shape that proves placement can't buy the peak.
#Preview("Glyph · placed, nothing proven") {
    let layers = PyramidService.layers(from: PyramidSnapshot(
        masteredPrepositions: 0, estimatedPrepositions: 24, corePrepositions: 28,
        learnedA1Words: 0, estimatedA1Words: 520, a1WordGoal: 585,
        a1StoriesPassed: 0,
        solidCoreGrammar: 0, estimatedCoreGrammar: 3, coreGrammarCount: 4,
        learnedA2Words: 0, estimatedA2Words: 120, a2WordGoal: 200, a2StoriesPassed: 0,
        conversations: 0, conversationGoal: 20
    ))
    PyramidGlyph(layers: layers)
        .frame(width: 120, height: 100)
        .padding()
}
