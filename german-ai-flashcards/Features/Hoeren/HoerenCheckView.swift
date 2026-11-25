//
//  HoerenCheckView.swift
//  german-ai-flashcards
//
//  Hör-Check (roadmap item 11): a short, fixed listening check Today offers every four weeks, so
//  the Hören stats can show how the ear moves over time. Eight numbers in sentences and three
//  dictated sentences at the learner's level, single pass. Its rounds are ordinary Hören rounds
//  tagged "check:" in `sourceRaw`; nothing here writes the learner's level or the pyramid.
//
//  The roadmap names DLI's Online Diagnostic Assessment as the model. Its site could not be reached
//  (2026-11-20), so this cites nothing from it and claims no level: the stats show the numbers.
//

import SwiftData
import SwiftUI

enum HoerenCheck {
    static let tag = "check"
    static let intervalDays = 28

    /// The newest check round's date, if any.
    @MainActor
    static func lastCheck(in context: ModelContext) -> Date? {
        let prefix = tag + ":"
        var d = FetchDescriptor<HoerenRound>(predicate: #Predicate { $0.sourceRaw.starts(with: prefix) },
                                             sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first?.date
    }

    /// Due for someone who uses Hören: never checked, or four weeks since the last check.
    @MainActor
    static func isDue(in context: ModelContext, now: Date = .now) -> Bool {
        let anyRound = ((try? context.fetchCount(FetchDescriptor<HoerenRound>())) ?? 0) > 0
        guard anyRound else { return false }
        guard let last = lastCheck(in: context) else { return true }
        return now.timeIntervalSince(last) >= Double(intervalDays) * 86_400
    }

    static func level(_ declared: CEFRLevel) -> CEFRLevel {
        declared.hoerenRank > 2 ? .b1 : declared
    }
}

struct HoerenCheckView: View {
    let modelManager: MLXModelManager

    @State private var zahlen: ZahlenConfig?
    @State private var diktat: DiktatConfig?

    private var level: CEFRLevel { HoerenCheck.level(modelManager.germanLevel) }

    var body: some View {
        List {
            Section {
                Text("Two short parts at \(level.rawValue), each heard once. The results go into Hören ▸ Statistik next to your earlier checks, so you can see your ear change.")
                    .font(.callout)
            }
            .themedListRow()
            Section {
                Button {
                    var rng = SystemRandomNumberGenerator()
                    let kinds = HoerenNumberKind.kinds(for: level)
                    zahlen = ZahlenConfig(level: level, kinds: kinds, mode: .carrier, playback: .singlePass,
                                          items: HoerenNumberGenerator.round(kinds: kinds, level: level, mode: .carrier, count: 8, rng: &rng),
                                          tag: HoerenCheck.tag)
                } label: {
                    Label("1 · Zahlen: eight numbers in sentences", systemImage: "number.circle")
                }
                Button {
                    var rng = SystemRandomNumberGenerator()
                    let sources: Set<DiktatSourceKind> = [.vocab, .perfekt, .kasus]
                    diktat = DiktatConfig(level: level, playback: .singlePass,
                                          sentences: DiktatSentenceBank.round(level: level, sources: sources, count: 3, rng: &rng),
                                          sourceRaw: HoerenCheck.tag + ":" + sources.map(\.rawValue).sorted().joined(separator: ","))
                } label: {
                    Label("2 · Diktat: three sentences", systemImage: "text.cursor")
                }
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Hör-Check")
        .fullScreenCover(item: $zahlen) { config in
            NavigationStack { ZahlenDiktatView(config: config) }
        }
        .fullScreenCover(item: $diktat) { config in
            NavigationStack { DiktatView(config: config) }
        }
    }
}
