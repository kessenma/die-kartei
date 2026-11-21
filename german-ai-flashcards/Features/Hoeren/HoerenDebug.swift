//
//  HoerenDebug.swift
//  german-ai-flashcards
//
//  Launch arguments for the Hören room. DEBUG only. See docs/HOEREN.md ▸ Debug.
//
//  `-hoeren.debugSeed 1` writes a Zahlen and a Diktat round (so the hub, the stats and the
//  calendar have something to show) and a story with key points (the simulator can't run a tutor,
//  so Worum geht's? needs one ready-made).
//  `-hoeren.debugOpen hub|zahlen|diktat|gist|stats|speller|story` opens a screen the simulator
//  can't tap its way to (the room sits under a wide Home tile).
//  `-hoeren.debugVerify 1` prints the speller, parser and scorer goldens ("Hören ALL OK").
//

#if DEBUG
import Foundation
import SwiftData
import SwiftUI

enum HoerenDebugOpen: String, Identifiable, CaseIterable {
    case hub, zahlen, diktat, gist, stats
    /// Each number kind as digits and as spelled text, to hear which the voice reads right.
    case speller
    /// The seeded story, opened in Hören mode.
    case story

    var id: String { rawValue }

    init?(argument: String) {
        self.init(rawValue: argument.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

@MainActor
enum HoerenDebugSeeder {
    static let storyTitle = "[debug] Der verpasste Zug"

    static func seed(in context: ModelContext) -> String {
        if SyncManager.shared.isRunning { return SyncManager.seedRefusal }
        var made: [String] = []

        let existing = (try? context.fetchCount(FetchDescriptor<HoerenRound>())) ?? 0
        if existing == 0 {
            var rng = SeededGenerator(seed: 42)
            let numbers = HoerenNumberGenerator.round(kinds: [.small, .price, .timeColloquial], level: .a2,
                                                      mode: .bare, count: 6, rng: &rng)
            let zahlen = HoerenRound(kind: .zahlen, date: Date().addingTimeInterval(-3600))
            zahlen.modeRaw = HoerenNumberMode.bare.rawValue
            zahlen.playbackRaw = HoerenPlayback.singlePass.rawValue
            zahlen.levelRaw = "A2"
            zahlen.sourceRaw = "small,price,timeColloquial"
            var items: [HoerenItem] = []
            for (i, n) in numbers.enumerated() {
                var item = HoerenItem(id: i, expected: n.value.display, spoken: n.spoken)
                item.numberKindRaw = n.kind.rawValue
                item.numberValue = n.value
                // Two wrong, the classic swap and the halb hour.
                if i == 0, case .integer(let v) = n.value, v >= 10 {
                    let swapped = Int(String(String(v).reversed())) ?? v
                    item.typed = String(swapped)
                    item.typedValue = .integer(swapped)
                    item.confusionRaw = HoerenConfusion.classify(typed: .integer(swapped), expected: n.value, kind: n.kind).rawValue
                } else if case .time(let h, let m) = n.value, m == 30 {
                    item.typed = String(format: "%ld:30", (h % 12) + 1)
                    item.confusionRaw = HoerenConfusion.halbHour.rawValue
                } else {
                    item.typed = n.value.display
                    item.correct = true
                    item.replays = i == 3 ? 1 : 0
                }
                items.append(item)
            }
            zahlen.items = items
            zahlen.askedCount = items.count
            zahlen.correctCount = items.filter(\.correct).count
            zahlen.firstPassCount = items.filter(\.firstPass).count
            zahlen.replayCount = 1
            zahlen.durationSeconds = 140
            HoerenScoringService.save(zahlen, in: context)

            let pairs = [("Ich helfe dem Mann.", "ich helfe den mann"),
                         ("Wir fahren morgen mit dem Zug nach Berlin.", "Wir fahren morgen mit den Zug nach Berlin"),
                         ("Das Mädchen kauft einen neuen Rock.", "Das Madchen kauft einen neue Rock")]
            let diktat = HoerenRound(kind: .diktat, date: Date().addingTimeInterval(-1800))
            diktat.playbackRaw = HoerenPlayback.study.rawValue
            diktat.levelRaw = "A2"
            diktat.sourceRaw = "kasus,perfekt,vocab"
            diktat.items = pairs.enumerated().map { i, pair in
                var item = HoerenItem(id: i, expected: pair.0, spoken: pair.0)
                item.typed = pair.1
                let result = DiktatScorer.score(reference: pair.0, typed: pair.1,
                                                focusByWord: ["dem": .dativ, "mann": .dativ, "zug": .dativ])
                item.diktat = result
                item.correct = result.isPerfect
                return item
            }
            diktat.askedCount = pairs.count
            diktat.durationSeconds = 210
            HoerenScoringService.save(diktat, in: context)
            made.append("rounds")
        }

        if story(in: context) == nil {
            let story = StudyStory(topic: "Ein verpasster Zug", level: .a2, genre: .nachrichten)
            story.title = storyTitle
            story.storyText = """
            Am Montagmorgen ist der Regionalzug von Köln nach Bonn zwanzig Minuten zu spät gekommen. \
            Viele Pendler haben ihren Anschluss verpasst. Der Grund war ein Baum auf den Gleisen. \
            Die Feuerwehr hat den Baum schnell entfernt. Ab neun Uhr sind die Züge wieder pünktlich gefahren. \
            Die Bahn entschuldigt sich bei den Fahrgästen und bietet einen Gutschein an.
            """
            story.englishText = "On Monday morning the regional train from Cologne to Bonn came twenty minutes late. Many commuters missed their connection. The reason was a tree on the tracks. The fire brigade removed the tree quickly. From nine o'clock the trains ran on time again. The railway apologises to passengers and offers a voucher."
            story.keyPoints = [
                "A train from Cologne to Bonn was twenty minutes late on Monday morning.",
                "A tree on the tracks caused the delay.",
                "The fire brigade removed it and trains ran on time from nine.",
                "The railway apologised and offers passengers a voucher.",
            ]
            story.generationComplete = true
            context.insert(story)
            try? context.save()
            made.append("story")
        }
        return made.isEmpty ? "already seeded" : "seeded " + made.joined(separator: " + ")
    }

    static func story(in context: ModelContext) -> StudyStory? {
        let title = storyTitle
        var d = FetchDescriptor<StudyStory>(predicate: #Predicate { $0.title == title })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    /// The goldens the unit tests pin, runnable on a device with no test target attached.
    static func runVerification() -> String {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }
        check(GermanNumberSpeller.cardinal(24) == "vierundzwanzig", "24")
        check(GermanNumberSpeller.year(1987) == "neunzehnhundertsiebenundachtzig", "1987")
        check(GermanNumberSpeller.colloquialTime(hour: 2, minute: 30) == "halb drei", "halb drei")
        check(GermanNumberSpeller.price(cents: 350) == "drei Euro fünfzig", "3,50")
        check(HoerenNumberAnswer.parse("14.30 Uhr", kind: .time) == .time(hour: 14, minute: 30), "14.30 Uhr")
        check(HoerenNumberAnswer.parse("030 4567", kind: .phone) == .digits("0304567"), "phone zero")
        let d = DiktatScorer.score(reference: "Ich helfe dem Mann.", typed: "ich helfe den mann", focusByWord: ["dem": .dativ])
        check(d.tokens.map(\.cls) == [.right, .right, .ending, .capital], "diktat classes")
        check(d.tokens[2].focus == .dativ, "diktat tag")
        let counts = [CEFRLevel.a1, .a2, .b1].map { DiktatSentenceBank.pool(for: $0, sources: Set(DiktatSourceKind.allCases)).count }
        let pools = "pools A1 \(counts[0]) · A2 \(counts[1]) · B1 \(counts[2])"
        return failures.isEmpty ? "[hoeren] Hören ALL OK · \(pools)" : "[hoeren] FAILED: \(failures.joined(separator: ", ")) · \(pools)"
    }
}

/// The screen a `-hoeren.debugOpen` value names.
struct HoerenDebugScreen: View {
    let open: HoerenDebugOpen
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch open {
        case .hub: HoerenHubView(modelManager: modelManager, mlxService: mlxService)
        case .zahlen: ZahlenSetupView(modelManager: modelManager)
        case .diktat: DiktatSetupView(modelManager: modelManager)
        case .gist: HoerenStoryPickerView(modelManager: modelManager, mlxService: mlxService)
        case .stats: HoerenStatsView()
        case .speller: HoerenSpellerLab()
        case .story:
            if let story = HoerenDebugSeeder.story(in: modelContext) {
                StoryDetailView(story: story, modelManager: modelManager, mlxService: mlxService, initialMode: .listen)
            } else {
                ContentUnavailableView("No story", systemImage: "book.pages",
                                       description: Text("Run with -hoeren.debugSeed 1"))
            }
        }
    }
}

/// Each number kind read two ways: the digits as written, and the spelled text the app hands the
/// voice. Decides which kinds the voice may be given digits for (see docs/HOEREN.md).
struct HoerenSpellerLab: View {
    @State private var items: [HoerenNumberItem] = []
    @State private var player = HoerenPlayer()

    var body: some View {
        List {
            ForEach(HoerenNumberKind.allCases) { kind in
                Section {
                    ForEach(items.filter { $0.kind == kind }) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.value.display).font(.headline.monospacedDigit())
                            Text(item.spelled).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Digits") { player.play(item.value.display) }
                                Button("Spelled") { player.play(item.spelled) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text(kind.germanLabel)
                }
            }
        }
        .navigationTitle("Speller A/B")
        .onAppear {
            guard items.isEmpty else { return }
            var rng = SeededGenerator(seed: 5)
            items = HoerenNumberKind.allCases.flatMap { kind in
                HoerenNumberGenerator.round(kinds: [kind], level: .b1, mode: .bare, count: 3, rng: &rng)
            }.enumerated().map { i, item in
                var copy = item
                copy.id = i
                return copy
            }
        }
        .onDisappear { player.stop() }
    }
}
#endif
