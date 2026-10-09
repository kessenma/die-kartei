//
//  GermanWritingTests.swift
//  german-ai-flashcardsTests
//
//  The German writing helpers' shared core (Services/GermanWriter.swift): the reply cleanup, the
//  prompts' form-of-address rules, the German check that keeps a refusal out of someone's email,
//  the whitespace a Mac Services replacement keeps, the truncation estimate and the error mapping.
//  The model itself isn't called here; scripts/mac_service_probe.swift drives it end to end.
//

import Foundation
import FoundationModels
import Testing
@testable import Die_Kartei

@Suite struct GermanWritingTests {

    @Test func cleanStripsWrappingButKeepsInnerQuotes() {
        #expect(GermanWriting.clean("  „Hallo Anna“ \n") == "Hallo Anna")
        #expect(GermanWriting.clean("\"Danke!\"") == "Danke!")
        #expect(GermanWriting.clean("```\nGuten Morgen\n```") == "Guten Morgen")
        // A quotation inside the text survives.
        #expect(GermanWriting.clean("Er sagte „ja“ und ging.") == "Er sagte „ja“ und ging.")
    }

    @Test func correctWithoutAnAddressKeepsTheWritersOwn() {
        let keep = GermanWriting.instructions(for: .correct, address: nil)
        #expect(keep.contains(GermanWriting.keepAddress))
        #expect(!keep.contains("with Sie and Ihr"))
        #expect(!keep.contains("with du and dein"))

        let du = GermanWriting.instructions(for: .correct, address: .du)
        #expect(du.contains("with du and dein"))
        #expect(!du.contains(GermanWriting.keepAddress))
    }

    @Test func translateDefaultsToSie() {
        #expect(GermanWriting.instructions(for: .translate, address: nil).contains("with Sie and Ihr"))
        #expect(GermanWriting.instructions(for: .translate, address: .du).contains("with du and dein"))
    }

    @Test func germanCheckCatchesARefusal() {
        #expect(GermanWriting.isGerman("Sehr geehrte Frau Weber, vielen Dank für Ihre schnelle Antwort."))
        #expect(GermanWriting.isGerman("Hallo Max, kommst du am Samstag zur Party?"))
        #expect(!GermanWriting.isGerman("I'm sorry, but I can't help with rewriting this text."))
        // Too short to judge: passes rather than blocking a one-word fix.
        #expect(GermanWriting.isGerman("Danke!"))
    }

    @Test func replacementKeepsTheSelectionsOuterWhitespace() {
        #expect(GermanWriting.replacement(for: "\n  Thanks.\n\n", with: "Danke.") == "\n  Danke.\n\n")
        #expect(GermanWriting.replacement(for: "Thanks.", with: "Danke.") == "Danke.")
        #expect(GermanWriting.replacement(for: "   ", with: "Danke.") == "   ")
    }

    @Test func truncationFlagsAtTheCap() {
        let cap = GermanWriting.maximumResponseTokens
        #expect(GermanWriting.isTruncated(outputTokens: cap, raw: ""))
        #expect(GermanWriting.isTruncated(outputTokens: cap - 2, raw: ""))
        #expect(!GermanWriting.isTruncated(outputTokens: cap - 3, raw: ""))
        // No count: three characters a token, erring toward flagging.
        #expect(GermanWriting.isTruncated(outputTokens: nil, raw: String(repeating: "a", count: cap * 3)))
        #expect(!GermanWriting.isTruncated(outputTokens: nil, raw: "Kurz."))
    }

    @Test func limitsFitTheContextWindow() {
        #expect(GermanWriting.inPlaceLimit < GermanWriting.panelLimit)
        // ~3 characters a token at worst, plus instructions and the reply cap, inside 4,096.
        #expect(GermanWriting.panelLimit / 3 + 300 + GermanWriting.maximumResponseTokens < 4_096)
    }

    @Test func errorsMapToLearnerFacingFailures() {
        #expect(GermanWriting.failure(for: CancellationError()) == .cancelled)
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        #expect(GermanWriting.failure(for: LanguageModelSession.GenerationError.exceededContextWindowSize(context)) == .tooLong(limit: nil))
        #expect(GermanWriting.failure(for: LanguageModelSession.GenerationError.guardrailViolation(context)) == .declined)
        #expect(GermanWriting.failure(for: LanguageModelSession.GenerationError.rateLimited(context)) == .rateLimited)
        #expect(GermanWriting.failure(for: LanguageModelSession.GenerationError.concurrentRequests(context)) == .busy)
        #expect(GermanWriting.failure(for: LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(context)) == .unsupportedLanguage)
    }

    @Test func failureMessagesNameTheLimit() {
        #expect(GermanWriting.Failure.tooLong(limit: 1_500).message.contains("1,500")
                || GermanWriting.Failure.tooLong(limit: 1_500).message.contains("1.500"))
        #expect(!GermanWriting.Failure.empty.message.isEmpty)
    }
}
