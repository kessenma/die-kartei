//
//  PlacementExport.swift
//  german-ai-flashcards
//
//  The placement review's JSON export — the app's first way of getting anything out of it.
//
//  Three decisions worth knowing before editing this file:
//
//  1. **Choices export as strings, never indices.** Indices are the scorer's language and are
//     meaningless outside the app, because the options are reshuffled on every run. Storage keeps
//     indices (compact, and what `isCorrect` compares); export resolves them. That asymmetry is the
//     whole reason `PlacementRecord` and this envelope are different shapes.
//  2. **`english` / `why` are resolved from the bank at export time** even though they're not stored.
//     Denormalizing is right in a snapshot meant for a human and wrong in storage, where a frozen
//     copy would stay wrong forever. Keys are omitted entirely when a lookup misses.
//  3. **The active filter travels in the file.** Export covers exactly what's on screen — a Share
//     button that quietly wrote forty checks while showing six rows would be a trust bug — so the
//     file has to say what it was filtered to, or the recipient is misled instead.
//
//  Nothing device-identifying goes in. `Transferable` rather than a temp file: the system
//  materializes the attachment itself, so there's no file lifetime to race against the share
//  sheet's dismissal, and share targets that render a `URL` item as a *link* get an attachment.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - Document

struct PlacementExportDocument: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            // Without this, Files and Mail name the attachment "Data".
            .suggestedFileName { $0.fileName }
    }
}

// MARK: - Envelope

private struct PlacementExportEnvelope: Encodable {
    struct App: Encodable {
        var name: String
        var version: String?
        var build: String?
    }

    struct FilterDescription: Encodable {
        var outcome: String?
        var block: String?
        var level: String?
        var attempt: String?
        var missedAtLeast: Int?
    }

    struct Scope: Encodable {
        var attempts: Int
        var questions: Int
        var filter: FilterDescription
    }

    struct Question: Encodable {
        var block: String
        var level: String?
        var construct: String?
        var sourceID: String?
        var isAnchor: Bool
        var prompt: String
        var context: String?
        var subtitle: String?
        var choices: [String]
        var correct: String
        var chosen: String?
        var outcome: String
        var english: String?
        var why: String?
    }

    struct Attempt: Encodable {
        var id: String
        var takenAt: Date
        var bankVersion: Int
        var appVersion: String?
        var result: PlacementResult
        var questions: [Question]
    }

    var schema = "die-kartei.placement-export"
    var schemaVersion = 1
    var exportedAt: Date
    var app: App
    var bankVersion: Int
    var scope: Scope
    /// The live estimate, so the file stands on its own even when the filter excluded everything.
    var current: PlacementResult?
    var attempts: [Attempt]
}

// MARK: - Builder

@MainActor
enum PlacementExport {

    /// The export for the review screen: the attempts on screen, carrying only the questions the
    /// active filter left visible.
    static func document(
        attempts: [PlacementAttempt],
        visible: [PlacementReviewItem],
        filter: PlacementReviewFilter
    ) -> PlacementExportDocument? {
        let visibleByAttempt = Dictionary(grouping: visible, by: \.attemptID)

        // An attempt survives if the filter left it any questions — or if it never had any, which
        // is the beginner declaration and still belongs in the timeline.
        let included = attempts.filter { attempt in
            if let rows = visibleByAttempt[attempt.id] { return !rows.isEmpty }
            return attempt.records.isEmpty && filter.attemptID == nil
        }

        let encoded = included.map { attempt -> PlacementExportEnvelope.Attempt in
            let records = visibleByAttempt[attempt.id]?
                .sorted { $0.index < $1.index }
                .map(\.record) ?? []
            return attemptEnvelope(attempt, records: records)
        }

        return build(
            attempts: encoded,
            questionCount: visible.count,
            filter: describe(filter, attempts: attempts),
            fileName: "placement-results-\(fileStamp(Date())).json"
        )
    }

    /// The export for one check's detail screen: that check, whole.
    static func document(attempt: PlacementAttempt) -> PlacementExportDocument? {
        build(
            attempts: [attemptEnvelope(attempt, records: attempt.records)],
            questionCount: attempt.records.count,
            filter: PlacementExportEnvelope.FilterDescription(),
            fileName: "placement-check-\(fileStamp(attempt.takenAt)).json"
        )
    }

    // MARK: - Pieces

    private static func build(
        attempts: [PlacementExportEnvelope.Attempt],
        questionCount: Int,
        filter: PlacementExportEnvelope.FilterDescription,
        fileName: String
    ) -> PlacementExportDocument? {
        let info = Bundle.main.infoDictionary
        let envelope = PlacementExportEnvelope(
            exportedAt: Date(),
            app: .init(
                name: "Die Kartei",
                version: info?["CFBundleShortVersionString"] as? String,
                build: info?["CFBundleVersion"] as? String
            ),
            bankVersion: PlacementGrammarBank.version,
            scope: .init(attempts: attempts.count, questions: questionCount, filter: filter),
            current: PlacementService.current,
            attempts: attempts
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // This file exists to be read by a person (or pasted into a tutor's inbox), so the ~9 %
        // pretty-printing costs is worth it.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        guard let data = try? encoder.encode(envelope) else { return nil }
        return PlacementExportDocument(data: data, fileName: fileName)
    }

    private static func attemptEnvelope(
        _ attempt: PlacementAttempt,
        records: [PlacementRecord]
    ) -> PlacementExportEnvelope.Attempt {
        PlacementExportEnvelope.Attempt(
            id: attempt.id.uuidString,
            takenAt: attempt.takenAt,
            bankVersion: attempt.bankVersion,
            appVersion: attempt.appVersion,
            result: attempt.result,
            questions: records.map(question)
        )
    }

    private static func question(_ record: PlacementRecord) -> PlacementExportEnvelope.Question {
        let explanation = explanation(for: record)
        return PlacementExportEnvelope.Question(
            block: record.block.rawValue,
            level: record.levelRaw,
            construct: record.construct,
            sourceID: record.sourceID,
            isAnchor: record.isAnchor,
            prompt: record.prompt,
            context: record.context,
            subtitle: record.subtitle,
            choices: record.choices,
            correct: record.correctChoice,
            chosen: record.chosenChoice,
            outcome: record.wasSkipped ? "skipped" : (record.isCorrect ? "right" : "wrong"),
            english: explanation.english,
            why: explanation.why
        )
    }

    private static func explanation(for record: PlacementRecord) -> (english: String?, why: String?) {
        guard let sourceID = record.sourceID else { return (nil, nil) }
        switch record.block {
        case .grammar:
            let item = PlacementGrammarBank.item(id: sourceID)
            return (item?.english, item?.why)
        case .cloze:
            guard let gap = record.gap else { return (nil, nil) }
            return (nil, PlacementGrammarBank.clozeGap(paragraphID: sourceID, gap: gap)?.why)
        default:
            return (nil, nil)
        }
    }

    private static func describe(
        _ filter: PlacementReviewFilter,
        attempts: [PlacementAttempt]
    ) -> PlacementExportEnvelope.FilterDescription {
        PlacementExportEnvelope.FilterDescription(
            outcome: filter.outcome?.rawValue,
            block: filter.block?.rawValue,
            level: filter.levelRaw,
            attempt: filter.attemptID.flatMap { id in
                attempts.first { $0.id == id }?.takenAt.formatted(.iso8601)
            },
            missedAtLeast: filter.repeatMisses
        )
    }

    private static func fileStamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
}
