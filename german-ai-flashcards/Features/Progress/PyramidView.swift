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
    /// The slab the learner tapped in the canvas; drives the scene's focus and the chip overlay.
    @State private var focusedLayer: PyramidLayerID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                PyramidSceneView(layers: layers, focused: $focusedLayer)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .overlay(alignment: .bottom) {
                        if let focusedLayer, let state = layers.first(where: { $0.id == focusedLayer }) {
                            focusChip(state)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(reduceMotion ? nil : .spring(duration: 0.35), value: focusedLayer)

                // One number, and it only ever means proven. The blueprint (placement credit)
                // deliberately has no percentage here — two percentages of the same pyramid read
                // as a contradiction. It appears as a sentence, and its numbers live in the
                // Einstufung section below, where they're explained.
                VStack(alignment: .leading, spacing: 4) {
                    let earned = PyramidService.overallEarnedFill(layers)
                    let total = PyramidService.overallFill(layers)
                    HStack {
                        Label("\(percent(earned)) gebaut · built", systemImage: "pyramid.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(completionCaption)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if total > earned + 0.005 {
                        Text("Dein Check hat den Bauplan gezeichnet · your check drew the blueprint — build it solid.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } header: {
                Text("Deine Pyramide · Your Pyramid").themedSectionHeader()
            } footer: {
                Text("Each layer is built from real skill — prepositions, matured words, understood stories, real conversations. Tap a layer to keep building it.")
                    .font(.caption2)
            }
            .themedListRow()

            PyramidCoachSection(
                modelManager: coordinator.modelManager,
                mlxService: coordinator.mlxService,
                placement: placement
            )

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

    /// The way in and out of the blueprint. Lives on this screen because this is where a check
    /// visibly does something: the dashed blueprint fill above is the only thing it produces —
    /// and this section is where its numbers live, so the header can stay one honest percentage.
    private var placementSection: some View {
        Section {
            Button { showPlacement = true } label: {
                HStack(spacing: 12) {
                    BauhausIcon(assetName: "pyramid-icon-bauplan",
                                fallbackSystemImage: "person.crop.circle.badge.questionmark",
                                size: 48)
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

            // The history screen owns everything else — taking another check, switching which one
            // applies, reviewing answers, and the (now non-destructive) "stop applying". This
            // section used to end in a destructive "Remove the estimate", which framed the estimate
            // as a single slot you had to clear before you could move on; every check is kept now,
            // so the honest framing is a list you add to.
            if !PlacementAttemptStore.isEmpty {
                NavigationLink {
                    PlacementReviewView(modelManager: coordinator.modelManager)
                } label: {
                    Label(reviewLabel, systemImage: "list.bullet.rectangle")
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Einstufung · Placement").themedSectionHeader()
        } footer: {
            Text("The check draws a blueprint — the dashed outline above — and a blueprint is never counted as built; only studying makes it solid. Every check you take is kept, so you can compare them, switch which blueprint is applied, or put the blueprint away entirely without losing a single brick.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var reviewLabel: String {
        let count = PlacementAttemptStore.attempts().count
        return count > 1 ? "See what you missed · \(count) checks" : "See what you missed"
    }

    private var placementTitle: String {
        guard let placement = PlacementService.current else { return "Already know some German?" }
        if placement.declaredBeginner { return "Starting from zero" }
        return "Placed at \(placement.estimatedLevel.rawValue)"
    }

    private var placementSubtitle: String {
        guard let placement = PlacementService.current else {
            return "Take a three-minute check to draft a blueprint of what you already know."
        }
        if placement.declaredBeginner {
            return "No blueprint — you're building from scratch. Take the check any time."
        }
        let when = placement.takenAt.formatted(date: .abbreviated, time: .omitted)
        // This is where the blueprint's number lives — beside its explanation, not in the header.
        let current = layers
        let blueprint = PyramidService.overallFill(current) - PyramidService.overallEarnedFill(current)
        guard blueprint > 0.005 else {
            return "Checked \(when) — the blueprint is fully built over. Retake it to re-measure."
        }
        return "Checked \(when) · the blueprint covers about \(percent(blueprint)) of the pyramid. Retake any time — it redraws."
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }

    /// A friendly sense of where the build stands — German flavor, English gloss.
    private var completionCaption: String {
        let done = layers.filter(\.isComplete).count
        if done == layers.count { return "Vollendet! · Complete — stark!" }
        if done > 0 { return "\(done) of \(layers.count) layers complete" }
        return "Der Grundstein ist gelegt · The foundation stone is laid"
    }

    // MARK: - Focus chip

    /// The floating card the canvas shows for a tapped slab: what the layer is, where it stands,
    /// and a way in — the scene answering questions in place without stealing the list's job.
    private func focusChip(_ layer: PyramidLayerState) -> some View {
        HStack(spacing: 10) {
            BauhausIcon(assetName: "pyramid-icon-\(layer.id.rawValue)",
                        fallbackSystemImage: layer.id.systemImage,
                        fallbackTint: .white,
                        fallbackBackground: layer.id.tint,
                        size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.id.germanTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(layer.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            NavigationLink { destination(for: layer.id) } label: {
                Text("Öffnen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(layer.id.tint, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(layer.id.germanTitle)")
            Button { focusedLayer = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: theme.innerRadius(12), style: .continuous))
    }

    /// Fires the layer-complete celebration for any layer that finished since the last visit.
    private func celebrateCompletedLayers() {
        let manager = coordinator.modelManager
        for layer in layers where layer.isComplete {
            CelebrationCenter.shared.presentLayerComplete(layer.id, manager: manager)
        }
    }

    // MARK: - Layer rows

    /// The lowest unfinished layer — the same rule the 3D scene's breathing slab follows, so the
    /// list and the canvas always point at the same "build here next".
    private var activeLayerID: PyramidLayerID? {
        layers.first(where: { !$0.isComplete })?.id
    }

    @ViewBuilder
    private func layerRow(_ layer: PyramidLayerState) -> some View {
        let isActive = layer.id == activeLayerID
        NavigationLink { destination(for: layer.id) } label: {
            HStack(spacing: 12) {
                // The rendered icon stands bare; only the SF fallback keeps a chip, where the
                // active row flips it to solid tint. (An active row with an asset is still
                // unmistakable: the weiterbauen tag and the tinted suggestion line carry it.)
                BauhausIcon(assetName: "pyramid-icon-\(layer.id.rawValue)",
                            fallbackSystemImage: layer.id.systemImage,
                            fallbackTint: isActive ? .white : layer.id.tint,
                            fallbackBackground: isActive ? layer.id.tint : layer.id.tint.opacity(0.14),
                            size: 52)
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
                        if isActive {
                            Text("Hier weiterbauen")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(layer.id.tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(layer.id.tint.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(layer.id.englishSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(layer.detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if let tricky = trickyCount(for: layer.id), tricky > 0 {
                        Label("\(tricky) tricky right now", systemImage: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if layer.id == .grammatikKern {
                        CoreStructureDots(grammar: profiles.first?.grammar ?? [:])
                    }
                    LayerFillBar(earned: layer.earnedFill, blueprint: layer.provisionalFill, tint: layer.id.tint)
                    if isActive {
                        Label(suggestion(for: layer.id), systemImage: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundStyle(layer.id.tint)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel(accessibilityLabel(for: layer))
    }

    /// Tricky-item counts where a layer has a live "keeps being missed" list. Word tricky lists
    /// aren't level-tagged, so they surface on the vocabulary home layer (A1) only — showing the
    /// same number on A2 too would double-report it.
    private func trickyCount(for id: PyramidLayerID) -> Int? {
        switch id {
        case .fundament:
            return prepositionStats.filter(\.isTricky).count
        case .wortschatzA1:
            return articleStats.filter(\.isTricky).count + matchingStats.filter(\.isTricky).count
        default:
            return nil
        }
    }

    /// The one concrete next thing for the active layer — the reason to tap, ahead of the row's
    /// existing destination. Concrete where the data is cheap, honest-generic where it isn't.
    private func suggestion(for id: PyramidLayerID) -> String {
        switch id {
        case .fundament:
            let tricky = prepositionStats.filter(\.isTricky).count
            return tricky > 0 ? "Next: drill the cases — \(tricky) tricky" : "Next: a Kasus round"
        case .wortschatzA1:
            let now = Date()
            let due = cards.filter { ($0.nextReviewDate ?? .distantFuture) <= now }.count
            return due > 0 ? "Next: review \(due) due cards" : "Next: learn new A1 words"
        case .geschichtenA1:
            return "Next: read one more A1 story"
        case .grammatikKern:
            let grammar = profiles.first?.grammar ?? [:]
            let weakest = PyramidService.coreGrammar
                .compactMap { focus in grammar[focus.rawValue].map { (focus, $0.struggle) } }
                .filter { $0.1 >= GrammarSkill.shakyThreshold }
                .max { $0.1 < $1.1 }
            if let weakest { return "Next: drill \(weakest.0.germanLabel)" }
            return "Next: drill Akkusativ & Dativ"
        case .vertiefungA2:
            return "Next: A2 words · A2 stories"
        case .spitze:
            return "Next: hold a conversation"
        }
    }

    private func accessibilityLabel(for layer: PyramidLayerState) -> String {
        let earned = "\(Int((layer.earnedFill * 100).rounded())) percent built"
        guard layer.hasEstimate else { return "\(layer.id.germanTitle), \(earned)" }
        return "\(layer.id.germanTitle), \(earned), \(Int((layer.provisionalFill * 100).rounded())) percent on the blueprint"
    }

    /// Each layer routes to its own activity — the same destinations the Activity hub uses.
    @ViewBuilder
    private func destination(for id: PyramidLayerID) -> some View {
        switch id {
        case .fundament:
            PrepositionHubView(modelManager: coordinator.modelManager)
        case .wortschatzA1:
            WortschatzHubView(coordinator: coordinator, initialLevels: [.a1])
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
            WortschatzHubView(coordinator: coordinator, initialLevels: [.a2])
        case .spitze:
            ConversationListView(modelManager: coordinator.modelManager, mlxService: coordinator.mlxService)
        }
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

// MARK: - Bauhaus icon (Blender still, SF Symbol fallback)

/// A rendered Bauhaus icon when its asset has landed in the catalog, the SF Symbol otherwise —
/// the Blender pipeline (`tools/blender/pyramid_icons.py`) can trail the code without ever
/// leaving a hole in the UI. Assets carry their own Any/Dark appearance variants, separately lit.
///
/// The render shows **bare and generous** — the stills carry their own depth and ground shadow,
/// so a tinted chip behind them just muddies the alpha edge. Only the flat SF fallback keeps the
/// chip treatment; without it a bare glyph would leave the row looking unfinished.
struct BauhausIcon: View {
    let assetName: String
    let fallbackSystemImage: String
    var fallbackTint: Color = .secondary
    var fallbackBackground: Color = Color(.tertiarySystemFill)
    var size: CGFloat = 48

    @Environment(\.appTheme) private var theme

    var body: some View {
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSystemImage)
                .font(.title3)
                .foregroundStyle(fallbackTint)
                .frame(width: size * 0.8, height: size * 0.8)
                .background(fallbackBackground,
                            in: RoundedRectangle(cornerRadius: theme.innerRadius(9), style: .continuous))
        }
    }
}

// MARK: - Two-channel fill bar

/// The list's rendering of the solid-vs-blueprint distinction: earned fill draws solid in the
/// layer's tint; blueprint fill continues past it as a faint, dash-edged segment. The single
/// solid `ProgressView` this replaces drew the *total* fill, which quietly contradicted the
/// glyph and the 3D scene — the one place the two channels looked like one.
private struct LayerFillBar: View {
    let earned: Double
    let blueprint: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let credited = min(1, earned + blueprint)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                // The blueprint spans the full credited width; the solid segment covers its
                // proven left edge, so what stays visible is exactly the unproven remainder.
                if blueprint > 0.0001 {
                    Capsule()
                        .fill(tint.opacity(0.16))
                        .overlay(
                            Capsule().strokeBorder(
                                tint.opacity(0.5),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
                            )
                        )
                        .frame(width: max(6, width * credited))
                }
                if earned > 0.0001 {
                    Capsule().fill(tint).frame(width: max(4, width * min(1, earned)))
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
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
/// unfinished one) breathes gently so the eye lands on where to build next. Tapping a slab
/// focuses it: the turntable pauses, the camera eases in, the rest of the stack dims, and the
/// parent overlays a chip naming the layer.
struct PyramidSceneView: View {
    let layers: [PyramidLayerState]
    @Binding var focused: PyramidLayerID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = true
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if reduceMotion {
                // No timeline: the scene re-renders only on state changes, so focus snaps.
                PyramidRealityScene(layers: layers, clock: 0, reduceMotion: true, focused: $focused)
            } else {
                TimelineView(.animation(paused: !isVisible)) { timeline in
                    let t = Float(timeline.date.timeIntervalSince(startedAt))
                    PyramidRealityScene(layers: layers, clock: t, reduceMotion: false, focused: $focused)
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        // Scrolled offscreen counts as gone: the timeline clock drives everything here
        // (turntable, breathing, camera easing), so freezing it stops the per-frame work.
        .onScrollVisibilityChange(threshold: 0.05) { isVisible = $0 }
    }
}

/// The RealityKit half. Geometry is built once; the `update` pass re-tints, re-ghosts and
/// re-poses per frame, so a layer that completes mid-visit visibly settles into place.
///
/// Focus is pure bookkeeping over the free-running clock: on every toggle the current turntable
/// angle and camera pose are recorded as the new "from", so the freeze, the resume and the dolly
/// are all continuous — no @State is ever mutated inside the update pass.
private struct PyramidRealityScene: View {
    let layers: [PyramidLayerState]
    /// Free-running clock (seconds since the canvas appeared); 0 under Reduce Motion.
    let clock: Float
    let reduceMotion: Bool
    @Binding var focused: PyramidLayerID?

    @State private var root = Entity()
    @State private var slabs: [(id: PyramidLayerID, entity: ModelEntity)] = []
    @State private var cap: ModelEntity?
    @State private var camera = PerspectiveCamera()

    // Focus-transition bookkeeping, recorded in the tap handler (never in `update`).
    @State private var baseAngle: Float = 0.6
    @State private var baseClock: Float = 0
    @State private var camFromPosition: SIMD3<Float> = Self.homePosition
    @State private var camFromLook: SIMD3<Float> = Self.homeLook
    /// Clock at the last focus toggle; negative means "settled, no transition running".
    @State private var transitionStart: Float = -1

    private static let homePosition: SIMD3<Float> = [3.4, 2.9, 9.2]
    private static let homeLook: SIMD3<Float> = [0, 0.1, 0]
    private static let turntableSpeed: Float = 0.45
    private static let transitionSeconds: Float = 0.55

    // The stack's proportions — shared by geometry and the focus camera.
    private static let slabHeight: Float = 0.30
    private static let slabGap: Float = 0.05
    private static var stackHeight: Float {
        let count = Float(PyramidLayerID.allCases.count)
        return count * slabHeight + (count - 1) * slabGap
    }

    /// The lowest unfinished layer — where the build continues.
    private var activeLayer: PyramidLayerID? {
        layers.first(where: { !$0.isComplete })?.id
    }

    private var allComplete: Bool { layers.allSatisfy(\.isComplete) }

    var body: some View {
        RealityView { content in
            // The same raked three-quarter framing and key/rim/fill rig as the preposition
            // scenes, so the pyramid reads as the same world, not a new one.
            camera.camera.fieldOfViewInDegrees = 30
            camera.position = Self.homePosition
            camera.look(at: Self.homeLook, from: camera.position, relativeTo: nil)
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
            root.transform.rotation = simd_quatf(angle: currentAngle(at: clock), axis: [0, 1, 0])

            let position = interpolatedCameraPosition(at: clock)
            camera.look(at: interpolatedCameraLook(at: clock), from: position, relativeTo: nil)

            for slab in slabs {
                let state = layers.first { $0.id == slab.id }
                let total = state?.fill ?? 0
                let earned = state?.earnedFill ?? 0
                let ghosted = total <= 0

                // Two dimensions, two channels: how *solid* a slab stands comes from everything
                // credited, while how much *color* it carries comes only from what's been proven.
                // An estimated layer is therefore visibly there but drained of its tint — present,
                // not earned — which is the whole distinction the pyramid is trying to draw.
                var opacity: Float = ghosted ? 0.13 : (earned >= 1 ? 1 : Float(0.28 + 0.5 * total))
                if let focused {
                    // Focus never hides information — it re-weights it. The chosen slab is lifted
                    // to readable no matter how ghostly, everything else steps back.
                    opacity = slab.id == focused ? max(opacity, 0.55) : opacity * 0.35
                }
                slab.entity.components.set(OpacityComponent(opacity: opacity))

                let earnedShare = total > 0 ? earned / total : 0
                let color = ghosted
                    ? Color(white: 0.42)
                    : slab.id.tint.mix(with: Color(white: 0.45), by: 1 - earnedShare)
                tint(slab.entity, color)

                // The active layer breathes (unless a focus holds the stage); the focused slab
                // stands slightly proud, everything else stands still.
                let scale: Float
                if slab.id == focused {
                    scale = 1.035
                } else if slab.id == activeLayer && !allComplete && focused == nil {
                    scale = 1 + 0.025 * (0.5 + 0.5 * sin(clock * 2.2))
                } else {
                    scale = 1
                }
                slab.entity.scale = SIMD3(repeating: scale)
            }
            cap?.isEnabled = allComplete
            if let cap { tint(cap, Color(white: 0.22)) }
        }
        .gesture(
            SpatialTapGesture().targetedToAnyEntity().onEnded { value in
                guard let tapped = slabID(for: value.entity) else { return }
                // Record the continuity state *before* toggling, so angle and camera pick up
                // exactly where this frame leaves them.
                baseAngle = currentAngle(at: clock)
                baseClock = clock
                camFromPosition = interpolatedCameraPosition(at: clock)
                camFromLook = interpolatedCameraLook(at: clock)
                transitionStart = reduceMotion ? -1 : clock
                focused = (focused == tapped) ? nil : tapped
            }
        )
        .task { buildStack() }
    }

    // MARK: Focus math

    private func slabID(for entity: Entity) -> PyramidLayerID? {
        var current: Entity? = entity
        while let cursor = current {
            if let match = slabs.first(where: { $0.entity == cursor }) { return match.id }
            current = cursor.parent
        }
        return nil
    }

    /// Turntable angle: frozen while focused, resuming seamlessly from the frozen angle after.
    private func currentAngle(at t: Float) -> Float {
        focused != nil ? baseAngle : baseAngle + (t - baseClock) * Self.turntableSpeed
    }

    /// 0…1 smoothstep progress of the camera transition; snapped under Reduce Motion.
    private func transitionProgress(at t: Float) -> Float {
        guard !reduceMotion, transitionStart >= 0 else { return 1 }
        let linear = min(1, max(0, (t - transitionStart) / Self.transitionSeconds))
        return linear * linear * (3 - 2 * linear)
    }

    private func slabCenterY(_ id: PyramidLayerID) -> Float {
        -Self.stackHeight / 2 + Self.slabHeight / 2
            + Float(id.indexFromBottom) * (Self.slabHeight + Self.slabGap)
    }

    private func targetCameraPosition() -> SIMD3<Float> {
        guard let focused else { return Self.homePosition }
        // Dolly in and settle level with the slab; higher (narrower) slabs get a touch closer.
        let y = slabCenterY(focused)
        let closeness = 1 - 0.06 * Float(focused.indexFromBottom)
        return [2.4 * closeness, y + 1.0, 6.2 * closeness]
    }

    private func targetCameraLook() -> SIMD3<Float> {
        guard let focused else { return Self.homeLook }
        return [0, slabCenterY(focused), 0]
    }

    private func interpolatedCameraPosition(at t: Float) -> SIMD3<Float> {
        simd_mix(camFromPosition, targetCameraPosition(), SIMD3(repeating: transitionProgress(at: t)))
    }

    private func interpolatedCameraLook(at t: Float) -> SIMD3<Float> {
        simd_mix(camFromLook, targetCameraLook(), SIMD3(repeating: transitionProgress(at: t)))
    }

    // MARK: Geometry

    /// Builds the six slabs once, bottom layer first. When the Blender renders land they replace
    /// this geometry under the same canvas — the camera, lights and update pass stay.
    private func buildStack() {
        root.children.removeAll()
        slabs = []

        let ordered = PyramidLayerID.allCases   // fundament … spitze, bottom → top
        let slabHeight = Self.slabHeight
        let gap = Self.slabGap
        let total = Self.stackHeight

        for (index, layer) in ordered.enumerated() {
            let width: Float = 2.5 - Float(index) * 0.36
            let slab = ModelEntity(
                mesh: .generateBox(size: [width, slabHeight, width]),
                materials: [pyramidMaterial(Color(white: 0.42))]
            )
            let y = -total / 2 + slabHeight / 2 + Float(index) * (slabHeight + gap)
            slab.position = [0, y, 0]
            // Tappable: focus is how the canvas answers "what is this layer?" in place.
            slab.components.set(CollisionComponent(shapes: [.generateBox(size: [width, slabHeight, width])]))
            slab.components.set(InputTargetComponent())
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
