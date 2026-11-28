//
//  DeckTransfer.swift
//  german-ai-flashcards
//
//  The `.kartei` deck file: how a deck leaves one device and arrives on another (AirDrop,
//  Messages, Files — all the same thing once the type is registered in Info.plist).
//
//  Four decisions worth knowing before editing this file:
//
//  1. **Progress travels, sessions don't.** Each card carries its SRS state, because the case this
//     exists for is one learner with an iPad and a phone, and a deck that arrives with every word
//     reset to "new" is worse than useless — it would overwrite months of scheduling. What does not
//     travel is `pausedProgressData`: a half-finished session stores *card indices* into one
//     particular shuffle, so resuming it against a re-inserted deck would land on the wrong words.
//  2. **Pictures don't travel, and the file says so.** Card images are PNGs on disk under
//     `CardImageStore`, not blobs in the store. Base64-ing a 20-card illustrated deck makes a 27 MB
//     "text file" and a miserable AirDrop. `includesImages` is in the envelope and always false in
//     schema 1, so a future package format can set it true without a second version check.
//  3. **`quizResults` are left behind on purpose.** They are session history, and they feed the
//     streak/StudyDay statistics; importing them would credit the receiving device with practice
//     that already counted once on the sending one. Card scheduling is the progress that matters.
//  4. **Dates are second-granular, and that is the trade.** The encoder is `.iso8601`, so every
//     timestamp loses its fractional part — measured at up to 0.85 s earlier on a re-import, which
//     is the truncation's hard bound of one second. A readable `"2026-09-22T15:02:53Z"` is worth
//     more here than microsecond fidelity on a schedule whose unit is the day. Do not "fix" this by
//     encoding raw `timeIntervalSinceReferenceDate` doubles; that trades the file's readability for
//     precision nothing in the app consumes.
//  5. **The deck's own UUID is in the file.** That is what lets the importer recognise a deck you
//     already have and offer to replace it, instead of quietly giving you a second copy every time
//     you re-send an updated deck from the other device.
//
//  `Transferable` rather than a temp file, same as `PlacementExport`: the system materializes the
//  attachment itself, so there is no file lifetime racing the share sheet's dismissal.
//

import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Type

extension UTType {
    /// Declared in Info.plist as an exported type conforming to `public.json`. Keep the identifier
    /// and the extension in step with `UTExportedTypeDeclarations` there or AirDrop hands the file
    /// to no one.
    static var karteiDeck: UTType {
        UTType(exportedAs: "kyle-essenmacher.german-ai-flashcards.deck")
    }
}

// MARK: - Envelope

// `DeckTransferEnvelope` and the encode/decode rules live in DeckTransferFormat.swift (shared with Android).

// MARK: - Document

struct DeckTransferDocument: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .karteiDeck) { $0.data }
            // Without this, Files and Mail name the attachment "Data".
            .suggestedFileName { $0.fileName }
    }
}

// MARK: - Export

/// Main-actor isolated because every read here walks SwiftData models. The document it returns
/// is a plain `Data` value, so the share sheet's own export work stays off this actor.
@MainActor
enum DeckTransfer {
    static let schema = DeckTransferFormat.schema
    static let schemaVersion = DeckTransferFormat.schemaVersion

    /// The shareable file for one deck, or nil if the deck cannot travel.
    ///
    /// The Wortschatz deck is refused: it is a merged singleton keyed to the bundled Goethe index
    /// (`WortschatzHubView` queries for exactly one `goethe-srs` deck), so a second one arriving
    /// from another device would break the hub rather than add anything. The Library list already
    /// hides it — this is the belt to that suspenders.
    static func document(for deck: SavedDeck) -> DeckTransferDocument? {
        guard let envelope = envelope(for: deck),
              let data = try? DeckTransferFormat.encode(envelope) else { return nil }
        return DeckTransferDocument(data: data, fileName: DeckTransferFormat.fileName(topic: deck.topic))
    }

    /// The file's contents for one deck, or nil if the deck cannot travel.
    static func envelope(for deck: SavedDeck, exportedAt: Date = Date()) -> DeckTransferEnvelope? {
        guard DeckTransferFormat.canExport(generatorRaw: deck.generatorRaw) else { return nil }
        let info = Bundle.main.infoDictionary
        return DeckTransferEnvelope(
            exportedAt: exportedAt,
            app: .init(
                name: "Die Kartei",
                version: info?["CFBundleShortVersionString"] as? String,
                build: info?["CFBundleVersion"] as? String
            ),
            deck: .init(
                id: deck.id.uuidString,
                topic: deck.topic,
                wordCount: deck.wordCount,
                includeExamples: deck.includeExamples,
                includeGender: deck.includeGender,
                wordTypeFilter: deck.wordTypeFilterRaw,
                includeConjugations: deck.includeConjugations,
                selectedTenses: deck.selectedTenses,
                createdAt: deck.createdAt,
                generationTimeSeconds: deck.generationTimeSeconds,
                generator: deck.generatorRaw,
                cards: deck.cards
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map(card)
            )
        )
    }

    private static func card(_ card: SavedCard) -> DeckTransferEnvelope.Card {
        let stored: [StoredConjugation]? = card.conjugationsData.flatMap {
            try? JSONDecoder().decode([StoredConjugation].self, from: $0)
        }
        return DeckTransferEnvelope.Card(
            id: card.id.uuidString,
            germanWord: card.germanWord,
            englishTranslation: card.englishTranslation,
            wordType: card.wordType,
            article: card.article,
            exampleSentence: card.exampleSentence,
            conjugations: stored,
            sortOrder: card.sortOrder,
            progress: progress(card)
        )
    }

    /// A never-studied card carries no progress block (`Progress.ifStudied`, shared).
    private static func progress(_ card: SavedCard) -> DeckTransferEnvelope.Progress? {
        DeckTransferEnvelope.Progress(
            easeFactor: card.easeFactor,
            interval: card.interval,
            repetitions: card.repetitions,
            nextReviewDate: card.nextReviewDate,
            totalReviews: card.totalReviews,
            lapses: card.lapses,
            leitnerBox: card.leitnerBox,
            lastReviewedAt: card.lastReviewedAt,
            lastReviewWasCorrect: card.lastReviewWasCorrect,
            firstReviewedAt: card.firstReviewedAt
        ).ifStudied
    }

    /// A file name that survives a topic with slashes, colons or emoji in it.
    ///
    /// `nonisolated` and shared rather than private: `SchreibblattPDF` names its exports the same
    /// way and has no reason to own a second copy of this. Pure string work, so it needs no actor.
    nonisolated static func fileStem(_ topic: String, fallback: String = "deck") -> String {
        DeckTransferFormat.fileStem(topic, fallback: fallback)
    }
}
