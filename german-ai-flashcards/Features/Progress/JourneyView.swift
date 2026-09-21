//
//  JourneyView.swift
//  german-ai-flashcards
//
//  „Dein Weg" — where you started, what you've conquered, how far you've come. A month-grouped
//  timeline assembled by `JourneyService` from records the app already keeps, topped by a
//  then-vs-now header and (when one is due) the „Weißt du es noch?" probe: one question about a
//  long-mastered slip, answered right = a "still solid" milestone, answered wrong = the item goes
//  back to the coach through the existing `noteSlips` rail.
//
//  Everything here is earned-only: placement rows read as blueprint events, never progress.
//

import SwiftUI
import SwiftData
import RealityKit

struct JourneyView: View {
    var modelManager: MLXModelManager

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query private var studyDays: [StudyDay]
    @Query(sort: \ArchivedMemoryItem.archivedAt, order: .reverse) private var archived: [ArchivedMemoryItem]
    @Query private var storyAttempts: [StoryQuizAttempt]
    @Query private var conversations: [ChatConversation]
    @Query private var cards: [SavedCard]

    /// The journey file lives outside SwiftData, so SwiftUI can't observe it; probe writes bump
    /// this to re-read.
    @State private var journeyRevision = 0

    // „Weißt du es noch?" — picked once per visit so the question can't re-roll mid-answer.
    @State private var probeItemID: UUID?
    @State private var probeSlip: LexicalSlip?
    @State private var probeChoices: [String] = []
    @State private var probeMonths = 1
    @State private var probeOutcome: Bool?

    private var document: JourneyDocument {
        _ = journeyRevision
        return ProgressSnapshotStore.document()
    }

    private var attempts: [PlacementAttempt] { PlacementAttemptStore.attempts() }

    private var events: [JourneyEvent] {
        JourneyService.events(
            studyDays: studyDays,
            attempts: attempts,
            archived: archived,
            badges: AchievementService.states(),
            storyAttempts: storyAttempts,
            conversations: conversations,
            recorded: document.milestones
        )
    }

    var body: some View {
        List {
            Section {
                JourneyHeaderScene()
                    .frame(height: 195)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            .themedListRow()

            if let probeSlip {
                probeSection(probeSlip)
            }
            headerSection
            comebackSection
            timelineSections
        }
        .navigationTitle("Dein Weg")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .themedListScreen()
        .onAppear { pickProbe() }
    }

    // MARK: - Then vs now

    @ViewBuilder
    private var headerSection: some View {
        let start = startAnchor
        let now = nowAnchor
        Section {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(start.line)
                        .themedLabel(.subheadline, size: 15)
                        .fontWeight(.semibold)
                    Text(start.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.right")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Heute · Now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(now.line)
                        .themedLabel(.subheadline, size: 15)
                        .fontWeight(.semibold)
                    Text(now.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)

            if let trend = trendLine {
                Label(trend, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Damals & heute · Then and Now").themedSectionHeader()
        } footer: {
            Text("Built means proven here — a blueprint from a check never counts. The rest of this screen is every step in between.")
                .font(.caption2)
        }
        .themedListRow()
    }

    /// Where the journey began: the oldest real placement check, or the first study day.
    private var startAnchor: (line: String, detail: String) {
        if let first = attempts.last(where: { !$0.isBeginnerDeclaration }) {
            return ("Eingestuft \(first.result.estimatedLevel.rawValue)",
                    first.takenAt.formatted(date: .abbreviated, time: .omitted))
        }
        if let firstDay = studyDays.filter(\.hasActivity).map(\.dayStart).min() {
            return ("Bei null · from zero", firstDay.formatted(date: .abbreviated, time: .omitted))
        }
        return ("Bei null · from zero", "Your first session starts the clock")
    }

    /// Today's standing, read from the latest snapshot (with a live fallback before one exists).
    private var nowAnchor: (line: String, detail: String) {
        let level = ExperienceService.level(for: studyDays)
        let built: Double
        if let latest = document.snapshots.last {
            built = mean(latest.earnedFill)
        } else {
            built = 0
        }
        return ("Level \(level.level) · \(level.rank.germanName)",
                "\(Int((built * 100).rounded())) % built")
    }

    private var trendLine: String? {
        let snapshots = document.snapshots
        guard let first = snapshots.first, let last = snapshots.last, snapshots.count >= 2 else { return nil }
        let from = Int((mean(first.earnedFill) * 100).rounded())
        let to = Int((mean(last.earnedFill) * 100).rounded())
        guard to > from else { return nil }
        return "\(from) % → \(to) % built since \(Self.monthFormatter.string(from: first.takenAt))"
    }

    private func mean(_ fills: [String: Double]) -> Double {
        guard !fills.isEmpty else { return 0 }
        return fills.values.reduce(0, +) / Double(fills.count)
    }

    // MARK: - Comeback words

    /// Words forgotten at least once and re-proven — detectable live but not datable (cards carry
    /// no history), so they get a summary card here rather than fake timeline dates. The weekly
    /// recorder dates new ones from now on.
    @ViewBuilder
    private var comebackSection: some View {
        let words = comebackWords
        if !words.isEmpty {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    BauhausIcon(assetName: "pyramid-icon-zurueckgeholt",
                                fallbackSystemImage: "arrow.uturn.backward.circle",
                                fallbackTint: .indigo,
                                fallbackBackground: Color.indigo.opacity(0.14),
                                size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zurückgeholt · Comeback words")
                            .themedLabel(.subheadline, size: 15)
                            .fontWeight(.semibold)
                        Text(words.prefix(8).joined(separator: ", ")
                             + (words.count > 8 ? " … \(words.count) in all" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Forgotten once, proven again — the hardest kind of learned.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
            .themedListRow()
        }
    }

    private var comebackWords: [String] {
        var seen = Set<String>()
        return cards
            .filter { $0.lapses > 0 && $0.repetitions >= PyramidService.provenRepetitions }
            .map(\.germanWord)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted()
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineSections: some View {
        let groups = monthGroups
        if groups.isEmpty {
            Section {
                ContentUnavailableView {
                    // The one icon on this screen that isn't a 44pt row mark, so it gets the
                    // signpost at the size an empty state deserves.
                    VStack(spacing: 10) {
                        BauhausIcon(assetName: "pyramid-icon-wegweiser",
                                    fallbackSystemImage: "signpost.right",
                                    fallbackTint: .teal,
                                    fallbackBackground: .clear,
                                    size: 64)
                        Text("Noch keine Meilensteine")
                    }
                } description: {
                    Text("Your first session lays the first stone — everything you conquer lands here.")
                }
            }
            .themedListRow()
        } else {
            ForEach(groups, id: \.id) { group in
                Section {
                    ForEach(group.events) { event in
                        eventRow(event)
                    }
                } header: {
                    Text(group.title).themedSectionHeader()
                }
                .themedListRow()
            }
        }
    }

    private var monthGroups: [(id: Date, title: String, events: [JourneyEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            calendar.date(from: calendar.dateComponents([.year, .month], from: event.date)) ?? event.date
        }
        return grouped.keys.sorted(by: >).map { key in
            (id: key,
             title: Self.monthFormatter.string(from: key),
             events: grouped[key]?.sorted { $0.date > $1.date } ?? [])
        }
    }

    private func eventRow(_ event: JourneyEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            BauhausIcon(assetName: event.assetSlug.map { "pyramid-icon-\($0)" } ?? "",
                        fallbackSystemImage: event.systemImage,
                        fallbackTint: event.tint,
                        fallbackBackground: event.tint.opacity(0.14),
                        size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .themedLabel(.subheadline, size: 15)
                    .fontWeight(.semibold)
                Text(event.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(event.date, format: .dateTime.day().month())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title). \(event.subtitle). \(event.date.formatted(date: .abbreviated, time: .omitted))")
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    // MARK: - „Weißt du es noch?"

    private func probeSection(_ slip: LexicalSlip) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(blankedSentence(slip) ?? "Which form is right?")
                    .themedLabel(.subheadline, size: 16)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)

                if let probeOutcome {
                    Label(
                        probeOutcome
                            ? "Sitzt noch! Still «\(slip.right)», \(probeMonths) month\(probeMonths == 1 ? "" : "s") later."
                            : "It's «\(slip.right)» — back with the coach, it'll come around again.",
                        systemImage: probeOutcome ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(probeOutcome ? .green : .orange)
                } else {
                    HStack(spacing: 10) {
                        ForEach(probeChoices, id: \.self) { choice in
                            Button {
                                answerProbe(choice)
                            } label: {
                                Text(choice)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(.tertiarySystemFill),
                                                in: RoundedRectangle(cornerRadius: theme.innerRadius(10), style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Weißt du es noch? · Still Know It?").themedSectionHeader()
        } footer: {
            Text(probeOutcome == nil
                 ? "You mastered this \(probeMonths) month\(probeMonths == 1 ? "" : "s") ago. One tap — right keeps it retired, wrong sends it back to training."
                 : "Answering counts as study. The next check comes along in a week or so.")
                .font(.caption2)
        }
        .themedListRow()
    }

    /// Eligible = a mastered, unpinned-payload slip at least 30 days retired, at most one probe a
    /// week (throttled on *answer*, so an ignored card just waits).
    private func pickProbe() {
        guard modelManager.gamificationRememberProbeEnabled, probeSlip == nil else { return }
        if let asked = document.probe?.lastAskedAt,
           Date().timeIntervalSince(asked) < 7 * 86_400 { return }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let eligible = archived.filter {
            $0.reason == .mastered && $0.kind == .slip && $0.archivedAt < cutoff && $0.payload != nil
        }
        guard let item = eligible.randomElement(),
              let data = item.payload,
              let slip = try? JSONDecoder().decode(LexicalSlip.self, from: data)
        else { return }
        probeItemID = item.id
        probeSlip = slip
        probeChoices = [slip.wrong, slip.right].shuffled()
        probeMonths = max(1, Calendar.current.dateComponents([.month], from: item.archivedAt, to: Date()).month ?? 1)
    }

    private func answerProbe(_ choice: String) {
        guard let slip = probeSlip, probeOutcome == nil,
              let item = archived.first(where: { $0.id == probeItemID })
        else { return }
        let right = choice == slip.right
        probeOutcome = right

        if right {
            ProgressSnapshotStore.appendMilestone(RecordedMilestone(
                kind: .stillSolid, date: Date(),
                title: "«\(slip.right)» sitzt noch",
                subtitle: "Still solid, \(probeMonths) month\(probeMonths == 1 ? "" : "s") after the coach let it go"
            ))
        } else {
            // The existing pre-built-slip rail: merges back into active memory, LRU-capped, and
            // the coach naturally resumes watching for it. The archive row goes — the item is no
            // longer mastered history, it's live again.
            LearnerMemoryService.noteSlips([slip], in: modelContext)
            modelContext.delete(item)
            ProgressSnapshotStore.appendMilestone(RecordedMilestone(
                kind: .backInTraining, date: Date(),
                title: "«\(slip.wrong) → \(slip.right)» zurück im Training",
                subtitle: "It slipped away again — the coach has it back"
            ))
        }
        ProgressSnapshotStore.markProbeAsked()
        // Retrieval is study: one card's worth keeps the day honest without gaming the streak.
        StudyLogService.record(.cards(1), in: modelContext)
        journeyRevision += 1
    }

    private func blankedSentence(_ slip: LexicalSlip) -> String? {
        guard let sentence = slip.sentence, let index = slip.blankIndex else { return nil }
        var words = sentence.split(separator: " ").map(String.init)
        guard words.indices.contains(index) else { return nil }
        words[index] = "____"
        return words.joined(separator: " ")
    }
}

// MARK: - Journey header canvas

/// „Die Figur unterwegs" — the screen's one live canvas: the figure climbing an *endless*
/// switchback mountainside, the camera riding up with her. There is no summit and no reset —
/// the tier index just grows, and a fixed pool of ramps and bend pads is recycled around her
/// (a switchback treadmill), so the ascent never stops and never visibly loops: the lifetime
/// learner. The gait is a real baked clip (`figur-gehen.usdz`: legs swing about the hip line,
/// arms counter-swing, torso bobs — authored in `figur.py --gehen`, motion verified against
/// its plain-text `.usda` twin), looped with `.repeat`; the *translation* stays a runtime
/// slide, the prep scenes' contract, so one clip works at any walking speed. Reduce Motion
/// swaps in the static geh pose (`figur-geh.usdz`), frozen mid-mountain.
///
/// Scrolled offscreen counts as gone: `onScrollVisibilityChange` freezes the timeline clock
/// (the slide) and pauses the walk clip, which runs on RealityKit's own clock and would
/// otherwise keep burning frames under the scrolled-away list.
struct JourneyHeaderScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = true
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if reduceMotion {
                JourneyRealityScene(clock: 0, animated: false, playing: false)
            } else {
                TimelineView(.animation(paused: !isVisible)) { timeline in
                    JourneyRealityScene(
                        clock: Float(timeline.date.timeIntervalSince(startedAt)),
                        animated: true,
                        playing: isVisible
                    )
                }
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onScrollVisibilityChange(threshold: 0.05) { isVisible = $0 }
        .accessibilityHidden(true)
    }
}

private struct JourneyRealityScene: View {
    let clock: Float
    let animated: Bool
    /// False while scrolled offscreen — pauses the walk clip without tearing the scene down.
    let playing: Bool

    @State private var root = Entity()
    @State private var figure: Entity?
    @State private var walkController: AnimationPlaybackController?
    @State private var camera = PerspectiveCamera()
    // Entity pools, recycled as the climb goes on (see `layoutMountain`).
    @State private var ramps: [ModelEntity] = []
    @State private var pads: [ModelEntity] = []

    // The endless mountain. The figure's tier index simply grows forever; the camera rides her
    // height; and a fixed pool of ramp/pad entities is re-positioned around whatever tier
    // she's on — a switchback treadmill. `poolCount` is even on purpose: a pooled entity always
    // shows tiers of one parity, so its tilt, direction and depth never have to change, only
    // its height. Tiers alternate depth (rather than accumulating it) for the same reason the
    // climb can be endless: the pattern repeats every two tiers.
    //
    // Proportions: the figure ships 1.8 units tall and is scaled to half; the tier rise leaves
    // clear air above her head, so she is never clipped by the ramp overhead — the first
    // on-device screenshot had her spanning three tiers.
    private static let figureScale: Float = 0.5
    private static let tierLength: Float = 3.6
    private static let tierRise: Float = 1.3
    private static let tierSetback: Float = 0.4
    /// Matched to the clip at this scale: one 1 s stride pair covers ~0.8 units × figureScale,
    /// so ~0.4 units/s of slide keeps the gait honest instead of moonwalking.
    private static let walkSpeed: Float = 0.4
    private static let turnSeconds: Float = 0.45
    /// 8 tiers × 1.3 rise covers the camera's ~4.8-unit vertical span with ample margin.
    private static let poolCount = 8

    private static var tierSeconds: Float { tierLength / walkSpeed }
    private static var blockSeconds: Float { tierSeconds + turnSeconds }
    /// The frozen moment Reduce Motion (and the pre-load frame) shows: mid-stride on tier 1.
    private static var staticClock: Float { blockSeconds + tierSeconds * 0.5 }

    /// Direction of travel on a tier: even tiers walk toward +x, odd toward −x.
    private static func direction(_ tier: Int) -> Float { tier.isMultiple(of: 2) ? 1 : -1 }
    /// Depth alternates instead of accumulating, so the pattern (and the climb) can repeat.
    private static func zFor(_ tier: Int) -> Float { tier.isMultiple(of: 2) ? 0 : -tierSetback }
    /// Path height `progress` of the way along a tier — continuous: each tier ends where the
    /// next begins.
    private static func pathY(_ tier: Int, _ progress: Float) -> Float {
        (Float(tier) + progress) * tierRise
    }

    /// Which tier the pooled entity in `slot` currently shows: the unique tier ≡ slot
    /// (mod poolCount) within half a pool of `center`. Parity is preserved because the pool
    /// size is even.
    private static func displayedTier(slot: Int, around center: Int) -> Int {
        let base = center - poolCount / 2
        let offset = ((slot - base) % poolCount + poolCount) % poolCount
        return base + offset
    }

    var body: some View {
        RealityView { content in
            camera.camera.fieldOfViewInDegrees = 30
            SceneRig.aim(camera, at: [0, 1.0, -Self.tierSetback / 2], distance: 9)
            content.add(camera)
            for light in SceneRig.lights() { content.add(light) }
            content.add(root)
        } update: { _ in
            layoutMountain(at: animated ? clock : Self.staticClock)
            syncWalkClip()
        }
        .task { await buildScene() }
    }

    /// Same clip-selection rule as `FigurSceneView`: the root's "global scene animation" is the
    /// one that covers every part; the longest clip is the fallback for a future exporter that
    /// names it differently.
    private func walkClip(of scene: Entity) -> AnimationResource? {
        let clips = scene.availableAnimations
        return clips.first { $0.name == "global scene animation" }
            ?? clips.max { $0.definition.duration < $1.definition.duration }
    }

    private func syncWalkClip() {
        guard let walkController else { return }
        if playing, !walkController.isPlaying {
            walkController.resume()
        } else if !playing, walkController.isPlaying {
            walkController.pause()
        }
    }

    private func buildScene() async {
        root.children.removeAll()
        ramps = []
        pads = []

        let half = Self.tierLength / 2
        let grade = atan2(Self.tierRise, Self.tierLength)

        // The pools. Geometry that depends only on a slot's *parity* — tilt, direction of
        // travel, depth, x — is set once here; `layoutMountain` only ever moves things in y.
        for slot in 0..<Self.poolCount {
            let direction = Self.direction(slot)

            // A switchback ramp. Rotating about +z lifts a box's +x end, so each ramp tilts
            // toward its own bend.
            let ramp = ModelEntity(
                mesh: .generateBox(size: [Self.tierLength + 0.4, 0.12, 0.55]),
                materials: [material(Color(white: 0.28))]
            )
            ramp.position = [0, 0, Self.zFor(slot)]
            ramp.transform.rotation = simd_quatf(angle: grade * direction, axis: [0, 0, 1])
            root.addChild(ramp)
            ramps.append(ramp)

            // The landing pad at this tier's bend, bridging the two depths.
            let pad = ModelEntity(
                mesh: .generateBox(size: [0.7, 0.12, Self.tierSetback + 0.55]),
                materials: [material(Color(white: 0.24))]
            )
            pad.position = [direction * (half + 0.18), 0, -Self.tierSetback / 2]
            root.addChild(pad)
            pads.append(pad)
        }

        // The gait ships in the asset; Reduce Motion gets the static geh pose instead.
        let asset = animated ? "figur-gehen" : "figur-geh"
        guard let loaded = try? await Entity(named: asset, in: .main) else { return }
        loaded.removeCamerasAndLights()
        loaded.scale = SIMD3(repeating: Self.figureScale)
        root.addChild(loaded)
        figure = loaded
        if animated, let clip = walkClip(of: loaded) {
            walkController = loaded.playAnimation(clip.repeat(duration: .infinity), transitionDuration: 0)
        }
        layoutMountain(at: animated ? clock : Self.staticClock)
    }

    /// The endless ascent, laid out for one moment in time. The figure's tier index grows
    /// without bound; the camera rides her height; the pooled tiers wrap around her. Stateless
    /// on purpose — nothing here mutates view state, so it's safe in the update pass.
    /// Translation only: the clip owns the limbs and the bob (the prep scenes' contract).
    private func layoutMountain(at t: Float) {
        let half = Self.tierLength / 2
        let tier = max(0, Int(t / Self.blockSeconds))
        let within = t - Float(tier) * Self.blockSeconds
        let direction = Self.direction(tier)

        var position: SIMD3<Float>
        var yaw: Float
        if within < Self.tierSeconds {
            let progress = within / Self.tierSeconds
            position = [direction * (-half + progress * Self.tierLength),
                        Self.pathY(tier, progress),
                        Self.zFor(tier)]
            yaw = direction * .pi / 2
        } else {
            // The bend: hold the corner, ease across to the next tier's depth, swing to face
            // the new direction — through front, like rounding a real switchback.
            let progress = (within - Self.tierSeconds) / Self.turnSeconds
            position = [direction * half,
                        Self.pathY(tier + 1, 0),
                        Self.zFor(tier) + (Self.zFor(tier + 1) - Self.zFor(tier)) * progress]
            yaw = direction * .pi / 2 * (1 - 2 * progress)
        }

        if let figure {
            figure.position = position
            figure.transform.rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        }

        // The camera climbs with her — same house angle, framing held, mountain streaming past.
        // The target sits above her head, so she rides the lower half of the frame and the
        // switchbacks still to come fill the upper: the climb visibly continues.
        SceneRig.aim(camera, at: [0, position.y + 0.85, -Self.tierSetback / 2], distance: 9)

        // Recycle the pools around the current tier.
        for (slot, ramp) in ramps.enumerated() {
            let shown = Self.displayedTier(slot: slot, around: tier)
            ramp.position.y = Self.pathY(shown, 0.5) - 0.06
        }
        for (slot, pad) in pads.enumerated() {
            let shown = Self.displayedTier(slot: slot, around: tier)
            pad.position.y = Self.pathY(shown, 1) - 0.06
        }
    }

    private func material(_ color: Color) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(color))
        material.roughness = 0.65
        return material
    }
}
