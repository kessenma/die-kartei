//
//  SchreibenDebug.swift
//  german-ai-flashcards
//
//  Launch arguments for the Schreiben room. DEBUG only.
//
//  `-schreiben.debugSeed 1` makes a journal entry and an essay with text already in them, so the
//  rows, the editor and later the check and the hand-off can be seen without typing.
//  `-schreiben.debugOpen hub|timeline|entry|essay` opens a screen the simulator can't tap its way
//  to (the room sits under a wide Home tile).
//

#if DEBUG
import Foundation
import SwiftData
import SwiftUI
#if canImport(PencilKit)
import PencilKit
#endif

enum SchreibenDebugOpen: String, Identifiable, CaseIterable {
    case hub, timeline
    /// The newest seeded journal entry, in the editor.
    case entry
    /// The newest seeded essay, in the editor.
    case essay
    /// The essay prompt picker.
    case prompts
    /// The share-with-the-coach sheet over the seeded journal entry.
    case share
    /// The check sheet over the seeded essay (pair with `-schreiben.debugCanned 1`).
    case check

    var id: String { rawValue }

    init?(argument: String) {
        self.init(rawValue: argument.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

@MainActor
enum SchreibenDebugSeeder {
    static let journalTitle = "[debug] Montag nach dem Kurs"
    static let essayTitle = "[debug] Mein Wochenende"

    /// One Tagebuch entry (German and English mixed, the way a learner vents) and one Aufsatz
    /// with a prompt. Idempotent by title. Refuses while sync runs.
    static func seed(in context: ModelContext) -> String {
        if SyncManager.shared.isRunning { return SyncManager.seedRefusal }
        var made: [String] = []
        if find(title: journalTitle, in: context) == nil {
            let entry = JournalEntry(kind: .tagebuch, level: .a2)
            entry.title = journalTitle
            entry.text = """
            Heute war der Kurs schwer. Wir haben den Dativ geübt und ich habe wieder "mit der Freund" gesagt.
            I keep mixing up dem and den, especially after mit and bei. The teacher was patient though.
            Nach dem Kurs bin ich mit meine Freundin ins Café gegangen. Wir haben über das Wochenende gesprochen.
            Ich glaube, ich muss die Artikel einfach auswendig lernen.
            """
            context.insert(entry)
            #if canImport(PencilKit)
            // Four "lines" of scrawl on the rules, so the Pencil page, the preview and the
            // handwriting reader have something to show (the reading will be nonsense).
            let drawing = PKDrawing(strokes: (0..<4).map { row -> PKStroke in
                let baseline = 28.0 * Double(3 + row * 2)
                let points = stride(from: 0.0, through: 420.0, by: 5.0).map { x in
                    PKStrokePoint(location: CGPoint(x: 60 + x, y: baseline - 6 - 7 * sin(x / 9) - (x.truncatingRemainder(dividingBy: 60) < 6 ? 8 : 0)),
                                  timeOffset: x / 600, size: CGSize(width: 2.6, height: 2.6),
                                  opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
            })
            JournalEntryStore.saveInk(drawing.dataRepresentation(), for: entry, in: context)
            #endif
            made.append("journal")
        }
        if find(title: essayTitle, in: context) == nil {
            let entry = JournalEntry(kind: .aufsatz, level: .a2)
            entry.title = essayTitle
            entry.promptID = "debug-wochenende"
            entry.promptDE = "Was hast du am Wochenende gemacht? Schreib über zwei Dinge."
            entry.promptEN = "What did you do at the weekend? Write about two things."
            entry.promptSourceRaw = JournalPromptSource.bank.rawValue
            entry.promptFocusRaw = GrammarFocus.perfekt.rawValue
            entry.targetMin = 60
            entry.targetMax = 110
            entry.text = """
            Am Samstag bin ich früh aufgestanden. Ich habe mit meinem Bruder Fußball gespielt. Das Wetter war schön, aber kalt.
            Am Sonntag habe ich für die Prüfung gelernt. Ich habe viele Vokabeln geschrieben und ein Buch gelesen.
            Am Abend habe ich mit meine Eltern telefoniert. Sie wohnen in Hamburg. Ich habe sie lange nicht gesehen.
            """
            context.insert(entry)
            made.append("essay")
        }
        try? context.save()
        return made.isEmpty ? "already seeded" : "seeded " + made.joined(separator: " + ")
    }

    static func find(title: String, in context: ModelContext) -> JournalEntry? {
        var d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.title == title })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
}

/// The screen a `-schreiben.debugOpen` value names.
struct SchreibenDebugScreen: View {
    let open: SchreibenDebugOpen
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch open {
        case .hub:
            SchreibenHubView(modelManager: modelManager, mlxService: mlxService)
        case .timeline:
            JournalTimelineView(modelManager: modelManager, mlxService: mlxService)
        case .entry:
            seeded(SchreibenDebugSeeder.journalTitle) { entry in
                JournalEntryView(entry: entry, modelManager: modelManager, mlxService: mlxService)
            }
        case .essay:
            seeded(SchreibenDebugSeeder.essayTitle) { entry in
                JournalEntryView(entry: entry, modelManager: modelManager, mlxService: mlxService)
            }
        case .prompts:
            JournalPromptPickerView(modelManager: modelManager, mlxService: mlxService) { _ in }
        case .share:
            seeded(SchreibenDebugSeeder.journalTitle) { entry in
                JournalCoachShareSheet(entry: entry, modelManager: modelManager, mlxService: mlxService)
            }
        case .check:
            seeded(SchreibenDebugSeeder.essayTitle) { entry in
                JournalCheckView(entry: entry, modelManager: modelManager, mlxService: mlxService)
            }
        }
    }

    @ViewBuilder
    private func seeded<Content: View>(_ title: String, @ViewBuilder content: (JournalEntry) -> Content) -> some View {
        if let entry = SchreibenDebugSeeder.find(title: title, in: modelContext) {
            content(entry)
        } else {
            ContentUnavailableView("No entry", systemImage: "square.and.pencil",
                                   description: Text("Run with -schreiben.debugSeed 1"))
        }
    }
}
#endif
