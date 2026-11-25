//
//  SchreibenTests.swift
//  german-ai-flashcardsTests
//
//  The Schreiben room's pure parts: the entry codec (round trip, the high-water marks, the check
//  group), the file root, the study-day counters, the sentence splitter, the language guess and
//  the score. See docs/SCHREIBEN.md.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

// MARK: - Sync

@MainActor
@Suite struct JournalSyncTests {
    private func container() -> ModelContainer {
        ModelContainer.inMemory([JournalEntry.self])
    }

    private func sample() -> JournalEntry {
        let e = JournalEntry(kind: .aufsatz, day: Date(timeIntervalSince1970: 1_700_000_000), level: .b1)
        e.title = "Mein Wochenende"
        e.text = "Am Samstag bin ich früh aufgestanden. Ich habe mit meine Eltern telefoniert."
        e.promptID = "p1"
        e.promptDE = "Was hast du am Wochenende gemacht?"
        e.promptEN = "What did you do at the weekend?"
        e.promptSourceRaw = JournalPromptSource.bank.rawValue
        e.promptFocusRaw = GrammarFocus.perfekt.rawValue
        e.targetMin = 60
        e.targetMax = 110
        e.inkHeight = 1536
        e.inkStrokeCount = 42
        e.inkPaperRaw = "sepia"
        e.transcriptConfirmedAt = Date(timeIntervalSince1970: 1_700_000_100)
        e.check = WritingCheck(
            sentences: [
                WritingSentenceCheck(index: 0, original: "Am Samstag bin ich früh aufgestanden.", outcome: .ok),
                WritingSentenceCheck(index: 1, original: "Ich habe mit meine Eltern telefoniert.", outcome: .fix,
                                     corrected: "Ich habe mit meinen Eltern telefoniert.", reason: "Dativ plural after mit",
                                     categoryRaw: "dativ"),
            ],
            comment: "Clear and well ordered; watch the Dativ after mit.",
            score: WritingScore(ok: 1, fix: 1, unsure: 0, skipped: 0, words: 12, targetMin: 60, targetMax: 110),
            modelID: "test/model",
            checkedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        e.checkedAt = Date(timeIntervalSince1970: 1_700_000_200)
        e.checkedModelID = "test/model"
        e.checkedTextHash = WritingCheck.hash(of: e.text)
        e.sharedWithCoachAt = Date(timeIntervalSince1970: 1_700_000_300)
        e.lookups = [JournalLookup(german: "telefonieren", english: "to phone", at: Date(timeIntervalSince1970: 1_700_000_050))]
        e.creditedWords = 12
        return e
    }

    @Test func anEntryRoundTrips() throws {
        let e = sample()
        let payload = JournalEntryCodec.known(e)
        let context = ModelContext(container())
        let copy = try #require(JournalEntryCodec.insert(payload, name: JournalEntryCodec.recordName(for: e), in: context))
        #expect(JournalEntryCodec.known(copy) == payload)
        #expect(copy.id == e.id)
        #expect(copy.kind == .aufsatz)
        #expect(copy.level == .b1)
        #expect(copy.day == e.day)
        #expect(copy.check?.sentences.count == 2)
        #expect(copy.check?.score?.checked == 2)
        #expect(copy.check?.score?.points == nil)   // two judged sentences are too few to score
        #expect(copy.lookups.first?.german == "telefonieren")
        #expect(!copy.checkIsStale)
    }

    @Test func twoEntriesAreTwoRecords() {
        #expect(JournalEntryCodec.recordName(for: JournalEntry()) != JournalEntryCodec.recordName(for: JournalEntry()))
    }

    @Test func theHighWaterMarksTakeTheLaterValueEitherWay() {
        let spec = JournalEntryCodec.spec
        let a = sample()
        a.sharedWithCoachAt = Date(timeIntervalSince1970: 1_700_001_000)
        a.creditedWords = 40
        let b = sample()
        b.id = a.id
        b.sharedWithCoachAt = Date(timeIntervalSince1970: 1_700_002_000)
        b.creditedWords = 25
        let l = SyncMerge.compose(base: nil, known: JournalEntryCodec.known(a), spec: spec, slot: "ipad", now: 10)
        let r = SyncMerge.compose(base: nil, known: JournalEntryCodec.known(b), spec: spec, slot: "phone", now: 20)
        for merged in [SyncMerge.merge(ancestor: nil, local: l, remote: r, spec: spec),
                       SyncMerge.merge(ancestor: nil, local: r, remote: l, spec: spec)] {
            let flat = SyncMerge.flatten(merged, spec: spec)
            #expect(flat.date("sharedWithCoachAt") == Date(timeIntervalSince1970: 1_700_002_000))
            #expect(flat.int("creditedWords") == 40)
        }
    }

    @Test func theCheckTravelsWithItsTutor() {
        let spec = JournalEntryCodec.spec
        let a = sample()
        a.checkedModelID = "ipad/model"
        let b = sample()
        b.id = a.id
        b.checkedModelID = "phone/model"
        b.checkedAt = Date(timeIntervalSince1970: 1_700_009_000)
        let l = SyncMerge.compose(base: nil, known: JournalEntryCodec.known(a), spec: spec, slot: "ipad", now: 10)
        let r = SyncMerge.compose(base: nil, known: JournalEntryCodec.known(b), spec: spec, slot: "phone", now: 20)
        for merged in [SyncMerge.merge(ancestor: nil, local: l, remote: r, spec: spec),
                       SyncMerge.merge(ancestor: nil, local: r, remote: l, spec: spec)] {
            let flat = SyncMerge.flatten(merged, spec: spec)
            let model = flat.string("checkedModelID")
            let at = flat.date("checkedAt")
            // Whichever side won, the check's fields came from the same side.
            if model == "phone/model" {
                #expect(at == Date(timeIntervalSince1970: 1_700_009_000))
            } else {
                #expect(model == "ipad/model")
                #expect(at == Date(timeIntervalSince1970: 1_700_000_200))
            }
        }
    }

    @Test func theJournalFolderSyncs() {
        #expect(FileSyncDocument.roots.contains(JournalInkStore.rootName))
    }

    @Test func theStudyDayCountsWriting() {
        #expect(StudyDayCodec.counterFields.contains("wordsWritten"))
        #expect(StudyDayCodec.counterFields.contains("writingSeconds"))
        let day = StudyDay(dayStart: Date())
        day.wordsWritten = 30
        #expect(day.hasActivity)
        #expect(ExperienceService.xp(for: day) == 3)
        day.writingSeconds = 120
        #expect(day.totalSeconds == 120)
    }

    @Test func aStaleCheckIsNoticed() {
        let e = sample()
        #expect(!e.checkIsStale)
        e.text += " Noch ein Satz."
        #expect(e.checkIsStale)
    }
}

// MARK: - Sentences

@Suite struct WritingSentencesTests {
    @Test func splitsOnStopsAndNewlines() {
        let text = "Heute war der Kurs schwer. Wir haben den Dativ geübt!\nIch glaube, ich muss mehr lernen? Ja."
        #expect(WritingSentences.split(text) == [
            "Heute war der Kurs schwer.",
            "Wir haben den Dativ geübt!",
            "Ich glaube, ich muss mehr lernen?",
            "Ja.",
        ])
    }

    @Test func keepsAbbreviationsAndOrdinals() {
        let text = "Ich lerne z.B. Vokabeln. Am 3. Mai habe ich Dr. Müller getroffen. Das kostet ca. 3.50 Euro."
        #expect(WritingSentences.split(text) == [
            "Ich lerne z.B. Vokabeln.",
            "Am 3. Mai habe ich Dr. Müller getroffen.",
            "Das kostet ca. 3.50 Euro.",
        ])
    }

    @Test func keepsQuotedSpeechInsideItsSentence() {
        let text = "Sie sagte: „Komm morgen wieder.“ Dann ging sie. Er fragte \"Warum?\" und wartete."
        #expect(WritingSentences.split(text) == [
            "Sie sagte: „Komm morgen wieder.“",
            "Dann ging sie.",
            "Er fragte \"Warum?\" und wartete.",
        ])
    }

    @Test func aMissingFinalStopStillMakesASentence() {
        #expect(WritingSentences.split("Ich bin müde") == ["Ich bin müde"])
        #expect(WritingSentences.split("   \n  ") == [])
    }

    @Test func countsWordsLikeATargetDoes() {
        #expect(WritingSentences.wordCount("Ich habe gibt's E-Mail geschrieben, oder?") == 6)
        #expect(WritingSentences.wordCount("") == 0)
        #expect(WritingSentences.wordCount("„Komm!“ – sagte sie.") == 3)
    }

    @Test func guessesTheLanguage() {
        #expect(WritingSentences.guessLanguage("Heute war der Kurs schwer.") == .german)
        #expect(WritingSentences.guessLanguage("I keep mixing up dem and den.") == .english)
        #expect(WritingSentences.guessLanguage("Müde.") == .german)
        #expect(WritingSentences.guessLanguage("Hamburg") == .mixed)
        #expect(WritingSentences.guessLanguage("The teacher was patient though.") == .english)
    }
}

// MARK: - Score

@Suite struct WritingScoreTests {
    @Test func cleanInsideTheTargetIsAHundred() {
        let s = WritingScore(ok: 8, fix: 0, unsure: 1, skipped: 0, words: 80, targetMin: 60, targetMax: 110)
        #expect(s.points == 100)
        #expect(s.cleanRatio == 1)
    }

    @Test func slipsAndLengthBothCost() {
        let s = WritingScore(ok: 6, fix: 2, unsure: 0, skipped: 0, words: 40, targetMin: 60, targetMax: 110)
        // 70 × 0.75 + 30 × (1 − 20/50) = 52.5 + 18 = 70.5 → 71
        #expect(s.points == 71)
        #expect(abs(s.lengthScore - 0.6) < 0.0001)
    }

    @Test func tooFewSentencesHaveNoPoints() {
        let s = WritingScore(ok: 1, fix: 1, unsure: 3, skipped: 0, words: 20, targetMin: 0, targetMax: 0)
        #expect(s.points == nil)
        #expect(s.lengthScore == 1)
    }

    @Test func farOutsideTheTargetBottomsOut() {
        let s = WritingScore(ok: 3, fix: 0, unsure: 0, skipped: 0, words: 400, targetMin: 60, targetMax: 110)
        #expect(s.lengthScore == 0)
        #expect(s.points == 70)
    }
}

// MARK: - The tutor's lines

@Suite struct WritingTutorCheckTests {
    let sentences = [
        "Ich habe gestern mit meine Freundin gesprochen.",
        "Das Wetter war schön.",
        "Wir sind ins Kino gegangen.",
    ]

    @Test func aGoodReplyIsReadLineByLine() {
        let reply = """
        1: falsch ; Ich habe gestern mit meiner Freundin gesprochen. ; Dativ after mit ; dativ
        2: richtig ; - ; - ; -
        3. richtig
        """
        let out = WritingTutorCheck.parse(reply, sentences: sentences)
        #expect(out.count == 3)
        #expect(out[0].outcome == .fix)
        #expect(out[0].corrected == "Ich habe gestern mit meiner Freundin gesprochen.")
        #expect(out[0].categoryRaw == "dativ")
        #expect(out[0].focus == .dativ)
        #expect(out[1].outcome == .ok)
        #expect(out[2].outcome == .ok)
    }

    @Test func aMissingLineIsUnsure() {
        let out = WritingTutorCheck.parse("1: richtig", sentences: sentences)
        #expect(out[1].outcome == .unsure)
        #expect(out[2].outcome == .unsure)
    }

    @Test func anEchoIsRight() {
        let reply = "1: falsch ; Ich habe gestern mit meine Freundin gesprochen ; punctuation ; -"
        #expect(WritingTutorCheck.parse(reply, sentences: sentences)[0].outcome == .ok)
    }

    @Test func aRewriteIsUnsure() {
        let reply = "2: falsch ; Gestern war es draußen den ganzen Tag lang wirklich wunderschön. ; style ; wortwahl"
        let out = WritingTutorCheck.parse(reply, sentences: sentences)
        #expect(out[1].outcome == .unsure)
        #expect(out[1].corrected != nil)
    }

    @Test func aStrayNounIsUnsure() {
        let reply = "3: falsch ; Wir sind ins Theater gegangen. ; wrong place ; wortwahl"
        #expect(WritingTutorCheck.parse(reply, sentences: sentences)[2].outcome == .unsure)
    }

    @Test func aWrongWithNoCorrectionIsUnsure() {
        let reply = "2: falsch ; - ; something is off ; -"
        #expect(WritingTutorCheck.parse(reply, sentences: sentences)[1].outcome == .unsure)
    }

    @Test func englishOutcomeWordsAndBulletsAreRead() {
        let reply = "- 1) wrong | Ich habe gestern mit meiner Freundin gesprochen. | case | Dative\n* 2) correct\n3: ok"
        let out = WritingTutorCheck.parse(reply, sentences: sentences)
        #expect(out[0].outcome == .fix)
        #expect(out[0].categoryRaw == "dativ")
        #expect(out[1].outcome == .ok)
        #expect(out[2].outcome == .ok)
    }

    @Test func categoriesNormalise() {
        #expect(WritingTutorCheck.normalizeCategory("Präpositionen") == "praepositionen")
        #expect(WritingTutorCheck.normalizeCategory("word order") == "wortstellung")
        #expect(WritingTutorCheck.normalizeCategory("Konjunktiv II") == "konjunktiv2")
        #expect(WritingTutorCheck.normalizeCategory("spelling") == "rechtschreibung")
        #expect(WritingTutorCheck.normalizeCategory("-") == nil)
        #expect(WritingTutorCheck.normalizeCategory("banana") == nil)
    }

    @Test func theCommentGateRefusesGrades() {
        #expect(WritingTutorCheck.parseComment("Clear and well ordered; watch the Dativ after mit.") != nil)
        #expect(WritingTutorCheck.parseComment("Good work, 7/10 sentences were right.") == nil)
        #expect(WritingTutorCheck.parseComment("Grade: B. Nice.") == nil)
        #expect(WritingTutorCheck.parseComment("Ok.") == nil)
    }

    @Test func strugglesAreReadNotInferred() {
        let entry = "Heute war der Kurs schwer. I keep mixing up dem and den after mit."
        let reply = """
        STRUGGLE: mixing up dem and den after mit ; dativ
        STRUGGLE: mixing up dem and den after mit ; -
        STRUGGLE: remembering noun genders ; Artikel
        STRUGGLE: I keep mixing up dem and den after mit. ; dativ
        """
        let out = WritingTutorCheck.parseStruggles(reply, entryText: entry)
        #expect(out.count == 2)
        #expect(out[0].text == "mixing up dem and den after mit")
        #expect(out[0].focus == .dativ)
        #expect(out[1].focus == .artikel)
        #expect(WritingTutorCheck.parseStruggles("NONE", entryText: entry).isEmpty)
    }
}

// MARK: - The prompt bank

@Suite struct WritingPromptBankTests {
    @Test func theShippedBankPassesItsGate() {
        #expect(WritingPromptBank.validate(WritingPromptBank.all).isEmpty)
        #expect(WritingPromptBank.all.count == WritingPromptFixtures.total)
    }

    @Test func theGoldenCountsHold() {
        for (key, expected) in WritingPromptFixtures.golden {
            let parts = key.split(separator: "/")
            let n = WritingPromptBank.all.filter { $0.level == parts[0] && $0.kind == parts[1] }.count
            #expect(n == expected, "\(key)")
        }
    }

    @Test func theGateCatchesBadPrompts() {
        let bad = WritingPrompt(id: "x", de: "beschreibe etwas", en: "", level: "A1", kind: "aufsatz", topics: [],
                                focus: "genitiv", targetWords: .init(min: 90, max: 61), scaffold: ["", "a", "b", "c", "d"])
        let codes = Set(WritingPromptBank.validate([bad]).map { $0.split(separator: " ").last.map(String.init) ?? "" })
        #expect(codes.contains("no-final-punctuation"))
        #expect(codes.contains("empty-en"))
        #expect(codes.contains("no-topics"))
        #expect(codes.contains("focus-above-level"))
        #expect(codes.contains("target-order"))
        #expect(codes.contains("target-outside-level"))
        #expect(codes.contains("too-much-scaffold"))
        #expect(codes.contains("empty-scaffold"))
    }

    @Test func aCoachPickPractisesTheShakyStructure() {
        let pick = WritingPromptBank.coachPick(level: .a2, kind: .aufsatz, shaky: [.dativ])
        #expect(pick?.focus == "dativ")
        #expect(WritingPromptBank.coachPick(level: .a1, kind: .aufsatz, shaky: [.genitiv]) == nil)
        #expect(WritingPromptBank.daily(level: .c1, kind: .tagebuch, dayIndex: 3)?.level == "B2")
    }

    @Test func theTutorPromptGate() {
        for (text, ok) in WritingPromptFixtures.gateCases {
            #expect((WritingPromptGate.accept(text) != nil) == ok, "\(text)")
        }
        #expect(WritingPromptGate.accept("Prompt: „Beschreibe deinen Lieblingsort.“") == "Beschreibe deinen Lieblingsort.")
    }
}

// MARK: - Self-report notes

@MainActor
@Suite struct SelfReportTests {
    private func container() -> ModelContainer {
        ModelContainer.inMemory([LearnerProfile.self, ArchivedMemoryItem.self])
    }

    @Test func notesMergeByTheirWordsAndCap() {
        let context = ModelContext(container())
        LearnerMemoryService.noteSelfReports([
            SelfReportNote(text: "Mixing up dem and den after mit", focus: "dativ", notedAt: .now),
        ], in: context)
        LearnerMemoryService.noteSelfReports([
            SelfReportNote(text: "mixing up dem and den after mit!", focus: nil, notedAt: .now),
        ], in: context)
        var p = LearnerMemoryService.profile(in: context)
        #expect(p.selfReports.count == 1)
        #expect(p.selfReports[0].timesNoted == 2)
        #expect(p.selfReports[0].focus == "dativ")
        #expect(p.sessionCount == 0)
        #expect(p.grammar.isEmpty)

        // Distinct words, not digits: the id keeps letters only, so "note 1" and "note 2" would merge.
        let words = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu"]
        for word in words.prefix(LearnerProfile.selfReportCap + 2) {
            LearnerMemoryService.noteSelfReports([SelfReportNote(text: "forgetting \(word) endings", notedAt: .now)], in: context)
        }
        p = LearnerMemoryService.profile(in: context)
        #expect(p.selfReports.count == LearnerProfile.selfReportCap)
        let archived = (try? context.fetch(FetchDescriptor<ArchivedMemoryItem>())) ?? []
        #expect(archived.contains { $0.kind == .selfReport })
    }

    @Test func theBriefingCarriesTheirWordsBeforeAnySession() {
        let context = ModelContext(container())
        #expect(LearnerMemoryService.briefing(in: context).isEmpty)
        LearnerMemoryService.noteSelfReports([SelfReportNote(text: "the Dativ after mit", focus: "dativ", notedAt: .now)], in: context)
        let briefing = LearnerMemoryService.briefing(in: context)
        #expect(briefing.contains("They say they find hard"))
        #expect(briefing.contains("the Dativ after mit"))
        #expect(briefing.contains("first conversation"))
    }

    @Test func notesRoundTripThroughTheProfileCodec() throws {
        let context = ModelContext(container())
        LearnerMemoryService.noteSelfReports([SelfReportNote(text: "remembering genders", focus: "artikel", notedAt: .now)], in: context)
        let p = LearnerMemoryService.profile(in: context)
        let payload = LearnerProfileCodec.known(p)
        let other = ModelContext(container())
        let copy = try #require(LearnerProfileCodec.insert(payload, name: LearnerProfileCodec.singletonName, in: other))
        #expect(copy.selfReports.count == 1)
        #expect(copy.selfReports[0].text == "remembering genders")
        #expect(copy.selfReports[0].id == p.selfReports[0].id)
    }

    @Test func anOlderBuildWithoutTheFieldKeepsTheNotes() {
        let spec = LearnerProfileCodec.spec
        let context = ModelContext(container())
        LearnerMemoryService.noteSelfReports([SelfReportNote(text: "remembering genders", focus: "artikel", notedAt: .now)], in: context)
        let withNotes = LearnerProfileCodec.known(LearnerMemoryService.profile(in: context))
        var without = withNotes
        without["selfReports"] = nil
        let l = SyncMerge.compose(base: nil, known: withNotes, spec: spec, slot: "ipad", now: 10)
        let r = SyncMerge.compose(base: nil, known: without, spec: spec, slot: "oldphone", now: 20)
        for merged in [SyncMerge.merge(ancestor: nil, local: l, remote: r, spec: spec),
                       SyncMerge.merge(ancestor: nil, local: r, remote: l, spec: spec)] {
            let flat = SyncMerge.flatten(merged, spec: spec)
            let notes = flat.jsonData("selfReports").flatMap { try? JSONDecoder().decode([SelfReportNote].self, from: $0) } ?? []
            #expect(notes.count == 1)
        }
    }

    @Test func aPlanOffersOnlyWhatIsNew() {
        let e = JournalEntry(kind: .aufsatz)
        e.text = "Ich habe mit meine Eltern telefoniert. Das war schön."
        e.check = WritingCheck(sentences: [
            WritingSentenceCheck(index: 0, original: "Ich habe mit meine Eltern telefoniert.", outcome: .fix,
                                 corrected: "Ich habe mit meinen Eltern telefoniert.", categoryRaw: "dativ"),
            WritingSentenceCheck(index: 1, original: "Das war schön.", outcome: .ok),
        ], checkedAt: Date(timeIntervalSince1970: 2000))
        e.checkedAt = Date(timeIntervalSince1970: 2000)
        e.lookups = [JournalLookup(german: "telefonieren", english: "to phone", at: Date(timeIntervalSince1970: 1500))]
        var plan = JournalCoachExport.pendingPlan(for: e)
        #expect(plan.slips.count == 1)
        #expect(plan.words.count == 1)
        #expect(plan.buttonTitle == "Send 1 sentence and 1 word to the coach")
        e.sharedWithCoachAt = Date(timeIntervalSince1970: 3000)
        plan = JournalCoachExport.pendingPlan(for: e)
        #expect(plan.isEmpty)
    }
}

// MARK: - Check bookkeeping

@Suite struct WritingCheckTests {
    @Test func theHashNoticesAnEdit() {
        let a = WritingCheck.hash(of: "Ich bin müde.")
        #expect(a == WritingCheck.hash(of: "Ich bin müde."))
        #expect(a != WritingCheck.hash(of: "Ich bin müde!"))
    }

    @Test func categoryCountsAreMostFrequentFirst() {
        let check = WritingCheck(sentences: [
            WritingSentenceCheck(index: 0, original: "a", outcome: .fix, categoryRaw: "dativ"),
            WritingSentenceCheck(index: 1, original: "b", outcome: .fix, categoryRaw: "artikel"),
            WritingSentenceCheck(index: 2, original: "c", outcome: .fix, categoryRaw: "dativ"),
            WritingSentenceCheck(index: 3, original: "d", outcome: .ok, categoryRaw: "dativ"),
            WritingSentenceCheck(index: 4, original: "e", outcome: .unsure),
        ], checkedAt: .now)
        #expect(check.categoryCounts.map(\.category) == ["dativ", "artikel"])
        #expect(check.categoryCounts.first?.count == 2)
        #expect(check.okCount == 1)
        #expect(check.unsureCount == 1)
    }
}
