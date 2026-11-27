//
//  JobVocabDebug.swift
//  german-ai-flashcards
//
//  `-jobPrep.debugOpen hub|count|phrases|posting|collect|save`: the job-ad word count and Collect mode on
//  a simulator that can't tap its way in. Seeds three sample postings (titles start „[debug]“)
//  the first time. `collect` opens the first posting in Collect mode with a few words picked,
//  `save` the save sheet for them. DEBUG only (docs/JOB_PREP.md ▸ Sammeln).
//

#if DEBUG
import SwiftUI
import SwiftData

enum JobVocabDebugOpen: String, Identifiable, CaseIterable {
    case hub, count, phrases, posting, collect, save

    var id: String { rawValue }

    init?(argument: String) {
        self.init(rawValue: argument.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

@MainActor
enum JobVocabDebugSeeder {
    static let prefix = "[debug] "

    /// The sample postings, made once. Returns them, newest first.
    @discardableResult
    static func seed(in context: ModelContext) -> [JobPosting] {
        let all = (try? context.fetch(FetchDescriptor<JobPosting>())) ?? []
        let existing = all.filter { $0.title.hasPrefix(prefix) }
        if !existing.isEmpty || SyncManager.shared.isRunning { return existing }
        let made = samples.enumerated().map { index, sample -> JobPosting in
            let posting = JobPosting(title: prefix + sample.title, text: sample.text, sourceKind: .paste,
                                     createdAt: Date().addingTimeInterval(Double(-index) * 3600))
            posting.company = sample.company
            posting.location = "Berlin"
            context.insert(posting)
            return posting
        }
        try? context.save()
        return made
    }

    static let pickedWords = ["eigenverantwortlich", "Kenntnisse", "abgeschlossenes Studium", "Zuverlässigkeit"]

    private static let samples: [(title: String, company: String, text: String)] = [
        ("iOS-Entwickler:in (m/w/d)", "Beispiel GmbH", """
        Deine Aufgaben
        • Du entwickelst gemeinsam mit dem Team neue Funktionen für unsere App.
        • Du übernimmst eigenverantwortlich kleinere Projekte und arbeitest eng mit dem Design zusammen.
        • Du sorgst für die Qualität des Codes durch Tests und Code-Reviews.

        Dein Profil
        • Ein abgeschlossenes Studium der Informatik oder eine vergleichbare Ausbildung
        • Mehrjährige Berufserfahrung in der Softwareentwicklung mit Swift und SwiftUI
        • Fundierte Kenntnisse in agilen Methoden
        • Sehr gute Deutschkenntnisse in Wort und Schrift
        • Zuverlässigkeit und Teamfähigkeit zeichnen dich aus.

        Wir bieten
        • Flexible Arbeitszeiten und die Möglichkeit zum mobilen Arbeiten
        • Ein unbefristetes Arbeitsverhältnis und 30 Tage Urlaub
        """),
        ("Backend-Entwickler (m/w/d)", "Muster AG", """
        Ihre Aufgaben
        Sie entwickeln und betreuen unsere Plattform für Kunden in ganz Europa. Sie analysieren Anforderungen und setzen sie eigenverantwortlich um.

        Ihr Profil
        Sie haben ein abgeschlossenes Studium der Informatik und erste Berufserfahrung in der Softwareentwicklung. Kenntnisse in Java oder Kotlin sowie in agilen Methoden setzen wir voraus. Sehr gute Deutschkenntnisse in Wort und Schrift sind erforderlich.

        Wir bieten
        Ein unbefristetes Arbeitsverhältnis, flexible Arbeitszeiten und ein motiviertes Team.
        """),
        ("Werkstudent:in IT-Support", "Kleinfirma KG", """
        Was dich erwartet
        Du unterstützt unser Team im IT-Support und hilfst Kolleginnen und Kollegen bei Störungen. Du dokumentierst Lösungen und pflegst unsere Systeme.

        Was du mitbringst
        Du studierst Informatik oder ein vergleichbares Fach. Erste Kenntnisse in Netzwerken sind von Vorteil. Zuverlässigkeit und gute Deutschkenntnisse in Wort und Schrift.

        Was wir bieten
        Flexible Arbeitszeiten, ein nettes Team und die Möglichkeit, nach dem Studium übernommen zu werden.
        """)
    ]
}

/// The screen a `-jobPrep.debugOpen` argument names.
struct JobVocabDebugScreen: View {
    let open: JobVocabDebugOpen
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @State private var postings: [JobPosting] = []

    var body: some View {
        Group {
            if postings.isEmpty {
                ProgressView()
            } else {
                switch open {
                case .hub:
                    JobPrepHubView(modelManager: modelManager, mlxService: mlxService)
                case .count:
                    JobVocabAnalysisView(modelManager: modelManager, mlxService: mlxService,
                                         initialSelection: Set(postings.map(\.id)))
                case .phrases:
                    JobVocabAnalysisView(modelManager: modelManager, mlxService: mlxService,
                                         initialSelection: Set(postings.map(\.id)), initialTab: .phrases)
                case .posting:
                    JobPostingDetailView(posting: postings[0], modelManager: modelManager, mlxService: mlxService)
                case .collect:
                    JobPostingDetailView(posting: postings[0], modelManager: modelManager, mlxService: mlxService,
                                         debugPicks: JobVocabDebugSeeder.pickedWords)
                case .save:
                    JobVocabSaveSheet(
                        picks: JobVocabDebugSeeder.pickedWords.map {
                            JobVocabPick(german: $0, example: JobVocabAnalyzer.sentence(containing: $0, in: postings[0].text))
                        },
                        posting: postings[0],
                        modelManager: modelManager,
                        mlxService: mlxService
                    ) { added, deck, _ in
                        print("[jobPrep] added \(added) to \(deck)")
                    }
                }
            }
        }
        .onAppear {
            if postings.isEmpty {
                postings = JobVocabDebugSeeder.seed(in: modelContext).sorted { $0.createdAt > $1.createdAt }
                print("[jobPrep] open \(open.rawValue) with \(postings.count) postings")
            }
        }
    }
}
#endif
