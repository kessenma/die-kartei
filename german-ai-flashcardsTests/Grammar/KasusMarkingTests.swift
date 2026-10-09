//
//  KasusMarkingTests.swift
//  german-ai-flashcardsTests
//
//  Markieren and the numbered sentences: every story cut into sentences numbered straight across
//  paragraphs, every word classified (a word of its target's case, never counted and why, or
//  plain), the cases each unit asks, the class sheet's score, both feedback modes, the notes a
//  tap shows, and the result `recordRound` stores.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Kasus Markieren")
struct KasusMarkingTests {
    let story: KasusStory
    let playable: KasusPlayableStory

    init() throws {
        story = try #require(KasusTestData.story(KasusTestData.schluesselID))
        playable = KasusService.prepare(story, lexicon: KasusTestData.lexicon)
    }

    private func prepared(_ id: String) throws -> KasusPlayableStory {
        KasusService.prepare(try #require(KasusTestData.story(id)), lexicon: KasusTestData.lexicon)
    }

    /// The first word with this text (and, when given, in this sentence).
    private func word(_ text: String, in numbered: KasusNumberedStory, sentence: Int? = nil) throws -> KasusWord {
        try #require(numbered.words.first { $0.text == text && (sentence == nil || $0.sentenceNumber == sentence) },
                     "no word „\(text)“")
    }

    // MARK: Sentences

    @Test("Sentences are numbered straight across paragraphs, and their words rebuild them", arguments: BundledStories.ids)
    func numbering(_ id: String) throws {
        let playable = try prepared(id)
        let numbered = playable.numbered
        #expect(!numbered.sentences.isEmpty)
        var nextID = 0
        for (i, sentence) in numbered.sentences.enumerated() {
            #expect(sentence.number == i + 1)
            let paragraph = playable.story.paragraphs[sentence.paragraphIndex].de as NSString
            #expect(paragraph.substring(with: sentence.range) == sentence.text, "#\(sentence.number) range")
            #expect(sentence.text == sentence.text.trimmingCharacters(in: .whitespacesAndNewlines))
            let rebuilt = sentence.words.map(\.display).joined(separator: " ")
            let squeezed = sentence.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(rebuilt == squeezed, "#\(sentence.number)")
            for word in sentence.words {
                #expect(word.id == nextID, "word ids run on across the story")
                nextID += 1
                #expect(word.sentenceNumber == sentence.number && word.paragraphIndex == sentence.paragraphIndex)
                #expect((sentence.text as NSString).substring(with: word.range) == word.text)
                #expect(paragraph.substring(with: word.paragraphRange) == word.text)
                #expect(!word.text.isEmpty && word.text.allSatisfy { $0.isLetter || $0.isNumber || "-'’".contains($0) },
                        "punctuation is never a word of its own: „\(word.text)“")
                #expect(numbered.word(word.id) == word)
            }
        }
        #expect(numbered.words.count == nextID)
        // The paragraphs stay whole for Lesen: every sentence belongs to one, in order.
        #expect(numbered.sentences.map(\.paragraphIndex) == numbered.sentences.map(\.paragraphIndex).sorted())
        #expect(Set(numbered.sentences.map(\.paragraphIndex)) == Set(playable.story.paragraphs.indices))
    }

    @Test("„Der verlorene Schlüssel“ as numbered sentences, punctuation riding along")
    func schluesselSentences() throws {
        let numbered = playable.numbered
        #expect(numbered.sentences.count == 19)
        #expect(numbered.sentence(1)?.text == "Es ist Montag, und Jonas hat um acht Uhr einen Termin.")
        #expect(numbered.sentence(6)?.text == "Jonas fragt seine Mutter: „Hast du meinen Schlüssel gesehen?“")
        #expect(numbered.sentence(8)?.paragraphIndex == 1, "sentence 8 opens the second paragraph")
        #expect(numbered.sentence(20) == nil)
        let mutter = try word("Mutter", in: numbered, sentence: 6)
        #expect(mutter.trailing == ":" && mutter.leading.isEmpty)
        let hast = try word("Hast", in: numbered)
        #expect(hast.leading == "„" && hast.display == "„Hast")
        #expect(try word("gesehen", in: numbered).trailing == "?“")
        #expect(try word("Montag", in: numbered).trailing == ",")
        #expect(numbered.sentenceNumber(ofTarget: 0) == 1, "„einen Termin“")
        #expect(!numbered.countsPronouns)
    }

    // MARK: Roles

    @Test("Every word of every gradable target counts for its case; contractions never do", arguments: BundledStories.ids)
    func targetWords(_ id: String) throws {
        let playable = try prepared(id)
        let numbered = playable.numbered
        for target in playable.targets {
            let label = "#\(target.index + 1) \(target.surface)"
            let words = numbered.words(ofTarget: target.index)
            #expect(words.map(\.text) == target.surface.split(separator: " ").map(String.init), "\(label)")
            for (i, word) in words.enumerated() {
                switch target.kind {
                case .contraction:
                    #expect(word.role == .ungraded(.contraction, target: target.index), "\(label): \(word.text)")
                case .pronoun:
                    #expect(word.role == .target(index: target.index, kasus: target.kasus, part: .pronoun), "\(label)")
                case .article:
                    let part: KasusWordPart = i == 0 ? .determiner : i == words.count - 1 ? .noun : .adjective
                    #expect(word.role == .target(index: target.index, kasus: target.kasus, part: part), "\(label): \(word.text)")
                }
            }
        }
        // Nothing else counts for a case: the words to find are exactly the targets' words.
        for kasus in GrammarCase.allCases {
            let expected = playable.targets.filter { $0.gradable && $0.kind != .contraction && $0.kasus == kasus }
                .reduce(0) { $0 + $1.surface.split(separator: " ").count }
            #expect(numbered.caseWords(kasus).count == expected, "\(kasus.name)")
        }
        // A capitalised plain word only opens a sentence, a quote or what follows a colon.
        let words = numbered.words
        for (i, word) in words.enumerated() where word.role == .plain && word.text.first?.isUppercase == true {
            let opensSentence = i == 0 || words[i - 1].sentenceNumber != word.sentenceNumber
            let opensQuote = word.leading.contains("„") || (i > 0 && words[i - 1].trailing.hasSuffix(":"))
            #expect(opensSentence || opensQuote, "„\(word.text)“ in sentence \(word.sentenceNumber) is capitalised mid-sentence")
        }
    }

    @Test("Words that never count, and why")
    func ungradedWords() throws {
        let umzug = try prepared("ks-dat-a2-umzug").numbered
        #expect(try word("Zum", in: umzug).role == .ungraded(.contraction, target: nil), "the idiom „Zum Glück“")
        #expect(try word("Glück", in: umzug).role == .ungraded(.contraction, target: nil))
        #expect(try word("Wohnzimmer", in: umzug).role.ungradedReason == .contraction, "„im Wohnzimmer“, a contraction target")
        #expect(try word("zwanzig", in: umzug).role == .ungraded(.noArticle, target: nil), "„zwanzig Kisten“")
        #expect(try word("Kisten", in: umzug, sentence: 6).role == .ungraded(.noArticle, target: nil))
        #expect(try word("Max", in: umzug, sentence: 3).role == .ungraded(.sentenceStart, target: nil))
        #expect(try word("Max", in: umzug, sentence: 17).role == .ungraded(.noArticle, target: nil))
        #expect(try word("sie", in: umzug).role == .ungraded(.pronoun, target: nil))
        #expect(try word("Kannst", in: umzug).role == .plain, "a verb opening a quote")
        #expect(try word("Um", in: umzug).role == .plain, "a preposition opening a sentence")
        #expect(umzug.countsPronouns)

        let gespraech = try prepared("ks-alle-b1-gespraech").numbered
        #expect(try word("Kein", in: gespraech).role == .ungraded(.idiom, target: nil))
        #expect(try word("Problem", in: gespraech).role == .ungraded(.idiom, target: nil))
        #expect(try word("paar", in: gespraech).role == .ungraded(.unchecked, target: nil), "„ein paar Entwürfe“ is no target")
        #expect(try word("Entwürfe", in: gespraech).role == .ungraded(.unchecked, target: nil))
        #expect(try word("Das", in: gespraech).role == .ungraded(.standalone, target: nil), "„Das ist ihre Chance!“")
        #expect(try word("Sie", in: gespraech, sentence: 15).role == .ungraded(.pronoun, target: nil), "formal Sie")
        #expect(try word("viele", in: gespraech).role == .ungraded(.noArticle, target: nil))
        #expect(try word("Herr", in: gespraech).role == .ungraded(.sentenceStart, target: nil))
        #expect(try word("Weber", in: gespraech).role == .ungraded(.noArticle, target: nil))

        let schluessel = playable.numbered
        #expect(try word("liegt", in: schluessel).role == .plain)
        #expect(try word("mit", in: schluessel).role == .plain)
        #expect(try word("Dort", in: schluessel).role == .plain, "an adverb opening a sentence")
        #expect(try word("Hast", in: schluessel).role == .plain)
        #expect(try word("Jonas", in: schluessel, sentence: 14).role == .ungraded(.noArticle, target: nil))

        let picknick = try prepared("ks-akk-a1-picknick").numbered
        let dich = try word("dich", in: picknick)
        #expect(dich.role.kasus == .akkusativ && dich.role.part == .pronoun)

        #expect(try word("Am", in: gespraech, sentence: 25).role == .ungraded(.superlative, target: nil), "„Am liebsten“")
        #expect(try word("liebsten", in: gespraech).role == .ungraded(.superlative, target: nil))
        #expect(try word("Am", in: gespraech, sentence: 19).role.ungradedReason == .contraction, "„Am Anfang“")
        let grossmutter = try prepared("ks-gen-b1-grossmutter").numbered
        #expect(try word("sechs", in: grossmutter, sentence: 7).role == .ungraded(.noArticle, target: nil),
                "„um sechs“: numbers never decline, so marking one is never wrong")
    }

    /// A story written for this test, so the patterns AI stories will bring have a check before
    /// any bundled story has them.
    private func synthetic(_ paragraph: String) throws -> KasusNumberedStory {
        let json = """
        {"id": "test-synthetic", "unit": "dativ", "level": "A2", "source": "authored",
         "reviewed": {"by": "", "date": ""}, "title": "Test", "titleEnglish": "Test",
         "question": {"de": "?", "en": "?", "options": ["a", "b"], "answer": 0},
         "paragraphs": [{"de": "\(paragraph)", "en": ""}],
         "targets": [], "notTargets": []}
        """
        let story = try JSONDecoder().decode(KasusStory.self, from: Data(json.utf8))
        return KasusNumberedStory.build(story: story, targets: [], lexicon: KasusTestData.lexicon)
    }

    @Test("An adjective before a noun with no article is never judged; a verb in front of one still is")
    func adjectiveBeforeBareNoun() throws {
        let numbered = try synthetic(
            "Wir fahren nächsten Montag mit großer Freude zu Paul. Bei gutem Wetter trinken wir Tee. "
            + "Wir trinken Kaffee. Er kauft frische Brötchen. Dort spielen Kinder. Ich esse am liebsten Kuchen. "
            + "Am nächsten Morgen regnet es. Er kommt um acht.")
        func role(_ text: String, _ sentence: Int) throws -> KasusTokenRole {
            try word(text, in: numbered, sentence: sentence).role
        }
        let bare = KasusTokenRole.ungraded(.noArticle, target: nil)
        #expect(try role("nächsten", 1) == bare, "a time word")
        #expect(try role("großer", 1) == bare, "-er shows the Dativ")
        #expect(try role("gutem", 2) == bare, "-em shows the Dativ")
        #expect(try role("frische", 4) == bare, "after a verb in -t, -e is an adjective")
        #expect(try role("fahren", 1) == .plain, "a verb after its subject")
        #expect(try role("trinken", 3) == .plain, "„Wir trinken Kaffee“: the verb stays wrong to mark")
        #expect(try role("spielen", 5) == .plain, "„Dort spielen Kinder“: a verb after a fronted adverb")
        #expect(try role("am", 6) == .ungraded(.superlative, target: nil), "„am liebsten Kuchen“")
        #expect(try role("liebsten", 6) == .ungraded(.superlative, target: nil))
        #expect(try role("Am", 7) == .ungraded(.contraction, target: nil), "„Am nächsten Morgen“ is an + dem")
        #expect(try role("nächsten", 7) == .ungraded(.contraction, target: nil))
        #expect(try role("acht", 8) == bare, "a number alone")
    }

    @Test("Each unit asks its own case first, then the earlier ones")
    func markCases() throws {
        #expect(KasusUnit.nominativ.markCases == [.nominativ])
        #expect(KasusUnit.akkusativ.markCases == [.akkusativ, .nominativ])
        #expect(KasusUnit.dativ.markCases == [.dativ, .akkusativ, .nominativ])
        #expect(KasusUnit.genitiv.markCases == [.genitiv, .dativ, .akkusativ, .nominativ])
        #expect(KasusUnit.alleFaelle.markCases == GrammarCase.allCases)
        #expect(KasusService.markCases(in: playable, unit: .dativ) == [.dativ, .akkusativ, .nominativ])
        #expect(KasusService.markCases(in: try prepared("ks-nom-a1-foto"), unit: .nominativ) == [.nominativ])
        #expect(KasusService.markCases(in: try prepared("ks-akk-a1-picknick"), unit: .akkusativ) == [.akkusativ, .nominativ])
        #expect(KasusService.markCases(in: try prepared("ks-gen-b1-grossmutter"), unit: .genitiv)
                == [.genitiv, .dativ, .akkusativ, .nominativ])
        #expect(KasusService.markCases(in: try prepared("ks-alle-b1-gespraech"), unit: .alleFaelle) == GrammarCase.allCases)
        // A case with no words in the story is skipped.
        #expect(KasusService.markCases(in: playable, unit: .genitiv) == [.dativ, .akkusativ, .nominativ])
    }

    // MARK: Score

    @Test("The class sheet's score: right minus wrong, never below zero, out of the words to find")
    func score() {
        let sheet = KasusMarkScore(caseWords: 10, right: 8, wrong: 2)
        #expect(sheet.points == 6 && sheet.missed == 2 && abs(sheet.fraction - 0.6) < 0.0001)
        #expect(sheet.scoreLabel == "6 / 10")
        #expect(sheet.countsLabel == "8 richtig · 2 falsch · 2 übersehen")
        let reckless = KasusMarkScore(caseWords: 10, right: 3, wrong: 7)
        #expect(reckless.points == 0 && reckless.fraction == 0 && reckless.scoreLabel == "0 / 10")
        #expect(KasusMarkScore(caseWords: 0, right: 0, wrong: 0).fraction == 0)
    }

    @Test("Am Ende: marks toggle, Prüfen judges every word, Lösung zeigen shows the missed, Noch mal clears")
    func amEndeRound() throws {
        let numbered = playable.numbered
        var round = KasusService.markRound(.dativ, in: playable, mode: .amEnde)
        let dative = numbered.caseWords(.dativ)
        let akk = numbered.caseWords(.akkusativ)
        let jonas = try word("Jonas", in: numbered, sentence: 14)      // ungraded
        let liegt = try word("liegt", in: numbered)                     // plain
        #expect(dative.count == 18 && round.caseWordIDs == Set(dative.map(\.id)))

        for word in dative.dropLast(2) { #expect(round.tap(word.id) == nil, "nothing is judged before Prüfen") }
        round.tap(akk[0].id)
        round.tap(liegt.id)
        round.tap(jonas.id)
        round.tap(akk[1].id)
        round.tap(akk[1].id)                                            // toggled off again
        #expect(round.verdict(for: dative[0].id) == nil && round.verdict(for: liegt.id) == nil)

        round.check()
        #expect(round.isChecked && round.attempt == 1)
        #expect(round.score == KasusMarkScore(caseWords: 18, right: 16, wrong: 2))
        #expect(round.verdict(for: dative[0].id) == .right)
        #expect(round.verdict(for: dative[17].id) == .missed)
        #expect(round.verdict(for: akk[0].id) == .wrong)
        #expect(round.verdict(for: liegt.id) == .wrong)
        #expect(round.verdict(for: jonas.id) == .notCounted(.noArticle))
        #expect(round.verdict(for: akk[1].id) == nil)
        #expect(round.tap(dative[17].id) == nil && round.score.right == 16, "marks are frozen after Prüfen")

        round.showAnswers()
        #expect(round.answersShown && round.verdict(for: dative[17].id) == .shown)

        let id = round.id
        round.reset()
        #expect(round.id == id && round.attempt == 2 && round.marked.isEmpty && !round.isChecked && !round.answersShown)

        var everything = KasusService.markRound(.dativ, in: playable, mode: .amEnde)
        for word in numbered.words { everything.tap(word.id) }
        everything.check()
        #expect(everything.score.points == 0 && everything.score.right == 18, "marking every word scores nothing")
    }

    @Test("Sofort: each tap is judged and locked; Fertig shows what was missed")
    func sofortRound() throws {
        let numbered = playable.numbered
        var round = KasusService.markRound(.dativ, in: playable, mode: .sofort)
        let dative = numbered.caseWords(.dativ)
        let akk = numbered.caseWords(.akkusativ)[0]
        let er = try word("Er", in: numbered)
        #expect(round.tap(dative[0].id) == .right)
        #expect(round.tap(akk.id) == .wrong)
        #expect(round.tap(akk.id) == nil && round.marked.contains(akk.id), "a Sofort mark can't be taken back")
        #expect(round.tap(er.id) == .notCounted(.pronoun))
        #expect(!round.marked.contains(er.id), "an uncounted word isn't marked")
        #expect(round.verdict(for: dative[0].id) == .right && round.verdict(for: dative[1].id) == nil)
        round.check()
        #expect(round.verdict(for: dative[1].id) == .missed)
        #expect(round.score == KasusMarkScore(caseWords: 18, right: 1, wrong: 1))
        #expect(round.tap(dative[1].id) == nil)
    }

    // MARK: Notes and instruction

    @Test("A tap's note is clean markup and says something true", arguments: BundledStories.ids)
    func notes(_ id: String) throws {
        let playable = try prepared(id)
        let round = KasusService.markRound(.dativ, in: playable, mode: .amEnde)
        for word in playable.numbered.words {
            let note = try #require(KasusService.markNote(for: word.id, in: round, playable: playable))
            #expect(!note.isEmpty, "„\(word.text)“")
            #expect(RichMarkup.problems(note).isEmpty, "„\(word.text)“: \(RichMarkup.problems(note)) in \(note)")
            #expect(!note.contains("—"))
        }
    }

    @Test("Pinned notes")
    func pinnedNotes() throws {
        let umzug = try prepared("ks-dat-a2-umzug")
        let round = KasusService.markRound(.dativ, in: umzug, mode: .amEnde)
        func note(_ text: String, sentence: Int? = nil, in playable: KasusPlayableStory, round: KasusMarkRound) throws -> String {
            let word = try word(text, in: playable.numbered, sentence: sentence)
            return try #require(KasusService.markNote(for: word.id, in: round, playable: playable))
        }
        #expect(try note("zum", in: umzug, round: round) == "*zum* = *zu* + {m:dem}: contractions aren't counted here.")
        #expect(try note("Nachbarn", sentence: 14, in: umzug, round: round)
                == "Part of „zum Nachbarn“ (*zum* = *zu* + {m:dem}): contractions aren't counted here.")
        #expect(try note("Zum", in: umzug, round: round) == "*zum* = *zu* + **dem**: contractions aren't counted here.")
        #expect(try note("Lisa", sentence: 1, in: umzug, round: round)
                == "No article in front: names and phrases without one aren't counted in this exercise.")
        #expect(try note("sie", in: umzug, round: round)
                == "Only *mich, mir, dich, dir, ihn* and *ihm* are counted in this exercise.")
        // Never "the case doesn't show": a name's -s is a Genitiv, and a number just never declines.
        #expect(try note("Lisas", in: umzug, round: round)
                == "*Lisas* = Lisa's: a name with *-s* is in the {gen:Genitiv}, but names aren't counted here.")
        #expect(try note("zwanzig", in: umzug, round: round) == "Numbers don't change with the case: not counted here.")
        let gespraech = try prepared("ks-alle-b1-gespraech")
        let gespraechRound = KasusService.markRound(.genitiv, in: gespraech, mode: .amEnde)
        #expect(try note("Saras", in: gespraech, round: gespraechRound)
                == "*Saras* = Sara's: a name with *-s* is in the {gen:Genitiv}, but names aren't counted here.")
        #expect(try note("Am", sentence: 25, in: gespraech, round: gespraechRound)
                == "*am* + *-sten* is the superlative, a fixed form: not counted here.")
        #expect(try note("Am", sentence: 19, in: gespraech, round: gespraechRound)
                == "*am* = *an* + {m:dem}: contractions aren't counted here.", "„Am Anfang“ really is an + dem")
        #expect(try note("Nächsten", in: gespraech, round: gespraechRound) == "No article in front: not counted in this exercise.")

        let schluessel = KasusService.markRound(.dativ, in: playable, mode: .amEnde)
        #expect(try note("Tisch", in: playable, round: schluessel).hasPrefix("„den Tisch“ is {akk:Akkusativ} here, not {dat:Dativ}. "))
        #expect(try note("mit", in: playable, round: schluessel)
                == "*mit* decides the case of „dem Schlüssel“ ({dat:Dativ}), but it isn't part of it. Only the article, any adjective and the noun are marked.")
        #expect(try note("Er", in: playable, round: schluessel) == "Pronouns aren't counted in this story.")
        let boden = try note("Boden", in: playable, round: schluessel)
        #expect(boden == KasusExplanation.explanation(for: try #require(playable.targets.first { $0.noun == "Boden" }), in: story))
    }

    @Test("The instruction names the case, and the pronouns when the story marks them")
    func instruction() {
        let plain = KasusMarking.instruction(for: .dativ, countsPronouns: false)
        #expect(plain.german == "„Markiere alle Wörter im {dat:Dativ}.“")
        #expect(plain.english == "Tap every word in the {dat:Dativ}: the article, any adjective and the noun.")
        #expect(KasusMarking.instruction(for: .akkusativ, countsPronouns: true).english
                == "Tap every word in the {akk:Akkusativ}: the article, any adjective and the noun (also *mich*, *dich* and *ihn*).")
        #expect(KasusMarking.instruction(for: .genitiv, countsPronouns: true).english.hasSuffix("the noun."))
        #expect(KasusMarking.instruction(for: .nominativ, countsPronouns: true).english
                == "Tap every word in the {nom:Nominativ}: the article, any adjective and the noun. Pronouns like *er* and *sie* aren't counted.")
        for kasus in GrammarCase.allCases {
            let (german, english) = KasusMarking.instruction(for: kasus, countsPronouns: true)
            #expect(RichMarkup.problems(german).isEmpty && RichMarkup.problems(english).isEmpty)
        }
    }

    // MARK: Result

    @Test("Markieren's result counts words and keeps one history row per phrase")
    func result() throws {
        var round = KasusService.markRound(.dativ, in: playable, mode: .amEnde)
        for id in KasusService.debugMarks(for: round, answers: .mixed) { round.tap(id) }
        round.check()
        let score = round.score
        #expect(score.wrong > 0 && score.missed > 0, "the mixed prefill misses and marks wrongly")
        let result = KasusService.markResult(round, storyID: story.id, unit: .dativ, in: playable, durationSeconds: 90)
        #expect(result.step == .find && result.markCase == .dativ && result.feedbackMode == .amEnde)
        #expect(result.markScore == score && result.id == round.id && !result.revealedAnswers)
        #expect(result.askedCount == 18 && result.firstTryCount == score.right && result.wrongCount == score.wrong)
        #expect(result.answeredCount == 18)
        #expect(KasusService.skillMoves(for: result).isEmpty, "recognition never moves the coach")

        let records = result.items.compactMap(\.record)
        #expect(records.count == result.items.count)
        let dative = records.filter { $0.kasus == .dativ && $0.outcome != .wrongMark }
        #expect(dative.count == 9, "one row per Dativ phrase")
        #expect(dative.filter { $0.outcome == .right }.count == 7 && dative.filter { $0.outcome == .missed }.count == 2)
        for record in records {
            let start = try #require(record.phraseStart)
            #expect((record.sentence as NSString).substring(with: NSRange(location: start, length: (record.phrase as NSString).length))
                    == record.phrase, "„\(record.phrase)“")
            #expect(RichMarkup.problems(record.explanation).isEmpty, "„\(record.phrase)“")
            #expect(record.wordCount != nil && record.markedWords != nil)
        }
        let wrongMarks = records.filter { $0.outcome == .wrongMark }
        let otherCases = records.filter { $0.outcome == .wrongPick }
        #expect(wrongMarks.count + otherCases.reduce(0) { $0 + ($1.markedWords ?? 0) } == score.wrong)
        for record in wrongMarks {
            #expect(record.formGenus == nil && record.genus == nil && record.pickedCase == .dativ)
        }
        for record in otherCases { #expect(record.pickedCase == .dativ && record.kasus != .dativ) }

        // Lösung zeigen before the result was built flags the missed phrases.
        round.showAnswers()
        let shown = KasusService.markResult(round, storyID: story.id, unit: .dativ, in: playable, durationSeconds: 90)
        #expect(shown.revealedAnswers)
        let missed = shown.items.compactMap(\.record).filter { $0.outcome == .missed }
        #expect(!missed.isEmpty && missed.allSatisfy { $0.wasRevealed })
    }

    // MARK: Feedback mode

    @Test("Each exercise keeps its own feedback mode, with its own default")
    func feedbackModes() {
        #expect(KasusFeedbackMode.markStorageKey != KasusFeedbackMode.endingsStorageKey)
        #expect(KasusFeedbackMode.storageKey(for: .find) == KasusFeedbackMode.markStorageKey)
        #expect(KasusFeedbackMode.storageKey(for: .fill) == KasusFeedbackMode.endingsStorageKey)
        #expect(KasusFeedbackMode.defaultMode(for: .find) == .amEnde)
        #expect(KasusFeedbackMode.defaultMode(for: .fill) == .sofort)
        #expect(KasusFeedbackMode.resolve(stored: "", default: .amEnde) == .amEnde)
        #expect(KasusFeedbackMode.resolve(stored: "sofort", default: .amEnde) == .sofort)
        #expect(KasusFeedbackMode.parse("amende") == .amEnde && KasusFeedbackMode.parse("Sofort") == .sofort)
        #expect(KasusFeedbackMode.parse("später") == nil)
        let defaults = UserDefaults(suiteName: "kasus.feedback.test")!
        defaults.removePersistentDomain(forName: "kasus.feedback.test")
        #expect(KasusFeedbackMode.current(for: .find, defaults: defaults) == .amEnde)
        #expect(KasusFeedbackMode.current(for: .fill, defaults: defaults) == .sofort)
        defaults.set("sofort", forKey: KasusFeedbackMode.markStorageKey)
        #expect(KasusFeedbackMode.current(for: .find, defaults: defaults) == .sofort)
        #expect(KasusFeedbackMode.current(for: .fill, defaults: defaults) == .sofort, "the other exercise is untouched")
        defaults.removePersistentDomain(forName: "kasus.feedback.test")
    }
}
