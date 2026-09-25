//
//  KasusGenerationFixtures.swift
//  german-ai-flashcards
//
//  Canned tutor output for the Phase 3 pipeline, since MLX doesn't run in the simulator: one fixed
//  plan per unit and what a tutor might write for it, in four flavors.
//
//    good          every planned phrase verbatim with its verb; unplanned phrases, some provable
//                  („einen Kuchen“ → an inferred target), some not („die Zeitung“ → not counted)
//    altered       one planned phrase written another correct way („ihrem Opa“ for „dem Opa“): it
//                  is harvested instead, and the story still passes
//    wrongArticle  one wrong article („mit den Hund“, „auf der Sofa“, „des Regen“): the whole story
//                  is rejected, the retry gets the same text, and the bundled story takes over
//    tooFew        a story with hardly any article phrases: too few gradable targets of the unit's
//                  case, rejected the same way
//
//  `-kasus.debugGenerate <unit>` runs the generator on these (`KasusGenerateDebug`), with
//  `-kasus.debugGenerateFixture good|altered|wrongArticle|tooFew` (default good). The Swift tests
//  use the same texts.
//

#if DEBUG
import Foundation

nonisolated enum KasusCannedOutput: String, CaseIterable, Hashable {
    case good, altered, wrongArticle, tooFew

    /// For a launch argument, ignoring case.
    static func parse(_ raw: String) -> KasusCannedOutput? {
        allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }
    }
}

// MARK: - The canned writer

/// Hands back fixed texts, one per write (the last one repeats, so a retry of a bad fixture fails
/// again). With a delay it counts tokens up in steps, so the sheet's phases can be seen and
/// screenshotted. Observable, like the MLX service, so the sheet's token count moves.
@Observable
@MainActor
final class KasusCannedWriter: KasusStoryWriter {
    let texts: [String]
    let modelID: String
    var memorySaverActive: Bool
    let delay: Duration
    /// Set to fail `prepare()` with this message, like a loadModel refusal.
    var prepareFailure: String?
    private(set) var liveTokenCount = 0
    private(set) var writes = 0
    private var stopRequested = false

    init(texts: [String], modelID: String = "canned", memorySaverActive: Bool = false, delay: Duration = .zero) {
        self.texts = texts
        self.modelID = modelID
        self.memorySaverActive = memorySaverActive
        self.delay = delay
    }

    func prepare() async -> String? {
        if delay > .zero { try? await Task.sleep(for: delay) }
        return prepareFailure
    }

    func write(system: String, user: String, maxTokens: Int, temperature: Float) async throws -> KasusWriterOutput {
        stopRequested = false
        liveTokenCount = 0
        let text = texts.isEmpty ? "" : texts[min(writes, texts.count - 1)]
        writes += 1
        let tokens = min(maxTokens, StoryStudyService.wordCount(of: text) * 4 / 3)
        if delay > .zero {
            let steps = 8
            for step in 1...steps {
                try await Task.sleep(for: delay / steps)
                if stopRequested {
                    return KasusWriterOutput(text: String(text.prefix(text.count * step / steps)),
                                             tokenCount: liveTokenCount, endedEarly: true)
                }
                liveTokenCount = tokens * step / steps
            }
        }
        liveTokenCount = tokens
        return KasusWriterOutput(text: text, tokenCount: tokens, endedEarly: false)
    }

    func stop() {
        stopRequested = true
    }
}

// MARK: - Plans and outputs

@MainActor
enum KasusGenerationFixtures {

    /// The unit's fixed plan (seed 0; the level the texts are written at).
    static func plan(for unit: KasusUnit) -> KasusStoryPlan {
        let (level, topic, phrases) = spec(for: unit)
        return KasusStoryPlan(unitRaw: unit.rawValue, level: level.rawValue, seed: 0, governed: false,
                              contract: .planned, topic: topic, genreRaw: StoryGenre.alltag.rawValue,
                              phrases: phrases.enumerated().map { index, entry in
                                  phrase(index, entry.frame, entry.expression, entry.kasus, entry.genus, entry.lemma, entry.verb)
                              })
    }

    /// What the canned tutor writes for `unit`.
    static func output(for unit: KasusUnit, _ kind: KasusCannedOutput) -> String {
        switch kind {
        case .good:
            return good(for: unit)
        case .tooFew:
            return unit == .nominativ || unit == .akkusativ ? tooFewA1 : tooFewA2
        case .altered, .wrongArticle:
            return edit(good(for: unit), edits(for: unit, kind))
        }
    }

    /// The good text with `edits` applied, each (find, replace) once. Tests build their own
    /// variants this way.
    static func edit(_ text: String, _ edits: [(String, String)]) -> String {
        edits.reduce(text) { text, edit in
            guard let range = text.range(of: edit.0) else {
                assertionFailure("fixture edit „\(edit.0)“ not found")
                return text
            }
            return text.replacingCharacters(in: range, with: edit.1)
        }
    }

    static func writer(for unit: KasusUnit, _ kind: KasusCannedOutput, delay: Duration = .zero) -> KasusCannedWriter {
        KasusCannedWriter(texts: [output(for: unit, kind)], modelID: "canned:\(kind.rawValue)", delay: delay)
    }

    /// A request that plays the fixture's plan on every attempt.
    static func request(for unit: KasusUnit) -> KasusGenerationRequest {
        let plan = plan(for: unit)
        return KasusGenerationRequest(unit: unit, level: plan.cefr ?? .a2, seed: 0, fixedPlan: plan)
    }

    // MARK: The plans

    private typealias Entry = (frame: KasusFrameKind, expression: String, kasus: GrammarCase, genus: Gender,
                               lemma: String, verb: String?)

    private static func spec(for unit: KasusUnit) -> (CEFRLevel, String, [Entry]) {
        switch unit {
        case .nominativ:
            return (.a1, "Ein Sonntag zu Hause", [
                (.subject, "der Hund", .nominativ, .der, "Hund", "schlafen"),
                (.subject, "der Vater", .nominativ, .der, "Vater", "kochen"),
                (.subject, "ein Freund", .nominativ, .der, "Freund", "kommen"),
                (.subject, "der Bruder", .nominativ, .der, "Bruder", "spielen"),
                (.object, "den Kuchen", .akkusativ, .der, "Kuchen", "essen"),
            ])
        case .akkusativ:
            return (.a1, "Ein Ausflug mit Opa", [
                (.subject, "der Opa", .nominativ, .der, "Opa", "warten"),
                (.object, "den Ball", .akkusativ, .der, "Ball", "suchen"),
                (.object, "den Kaffee", .akkusativ, .der, "Kaffee", "trinken"),
                (.preposition, "für die Oma", .akkusativ, .die, "Oma", nil),
                (.preposition, "durch den Park", .akkusativ, .der, "Park", nil),
            ])
        case .dativ:
            return (.a2, "Etwas ist verschwunden", [
                (.subject, "der Vater", .nominativ, .der, "Vater", "kommen"),
                (.object, "den Ball", .akkusativ, .der, "Ball", "suchen"),
                (.dativeVerb, "dem Opa", .dativ, .der, "Opa", "helfen"),
                (.recipient, "dem Kind", .dativ, .das, "Kind", "geben"),
                (.preposition, "mit dem Hund", .dativ, .der, "Hund", nil),
                (.wechselWo, "auf dem Sofa", .dativ, .das, "Sofa", "liegen"),
            ])
        case .genitiv:
            return (.a2, "Ein schwieriger Morgen", [
                (.subject, "der Bus", .nominativ, .der, "Bus", "kommen"),
                (.object, "den Mantel", .akkusativ, .der, "Mantel", "tragen"),
                (.preposition, "mit dem Fahrrad", .dativ, .das, "Fahrrad", nil),
                (.genitivePreposition, "wegen des Regens", .genitiv, .der, "Regen", nil),
                (.genitivePreposition, "wegen eines Unfalls", .genitiv, .der, "Unfall", nil),
                (.genitivePreposition, "trotz der Kälte", .genitiv, .die, "Kälte", nil),
            ])
        case .alleFaelle:
            return (.a2, "Das Familienfest", [
                (.subject, "der Onkel", .nominativ, .der, "Onkel", "kommen"),
                (.subject, "ein Hund", .nominativ, .der, "Hund", "spielen"),
                (.object, "einen Kuchen", .akkusativ, .der, "Kuchen", "kaufen"),
                (.preposition, "für die Tante", .akkusativ, .die, "Tante", nil),
                (.dativeVerb, "dem Mädchen", .dativ, .das, "Mädchen", "gefallen"),
                (.wechselWo, "auf dem Tisch", .dativ, .der, "Tisch", "liegen"),
                (.genitivePreposition, "wegen des Wetters", .genitiv, .das, "Wetter", nil),
                (.genitivePreposition, "trotz des Regens", .genitiv, .der, "Regen", nil),
            ])
        }
    }

    /// A planned phrase with the forms the planner would give it.
    private static func phrase(_ id: Int, _ frame: KasusFrameKind, _ expression: String, _ kasus: GrammarCase,
                               _ genus: Gender, _ lemma: String, _ verb: String?) -> KasusPlannedPhrase {
        let words = expression.split(separator: " ").map(String.init)
        let hasPreposition = [.preposition, .genitivePreposition, .wechselWo, .wechselWohin].contains(frame)
        let bank = KasusTriggerBank.bundled
        let subjectVerb = bank.subjectVerbs.first { $0.lemma == verb }
        let forms: [String] = switch frame {
        case .dativeVerb:
            KasusForms.dativeVerbs[verb ?? ""] ?? []
        case .wechselWo:
            KasusForms.wechselVerbForms.filter { $0.value.kind == .position }.map(\.key).sorted()
        case .wechselWohin:
            KasusForms.wechselVerbForms.filter { $0.value.kind == .placement }.map(\.key).sorted()
        case .subject:
            subjectVerb.map(KasusStoryPlanner.subjectForms) ?? []
        case .object, .recipient:
            (bank.objectVerbs + bank.recipientVerbs).first { $0.lemma == verb }?.forms ?? []
        case .preposition, .genitivePreposition:
            []
        }
        return KasusPlannedPhrase(id: id, frame: frame, expression: expression,
                                  phrase: hasPreposition ? words.dropFirst().joined(separator: " ") : expression,
                                  caseRaw: kasus.rawValue, genusRaw: genus.columnLabel, lemma: lemma,
                                  preposition: hasPreposition ? words.first : nil, verb: verb, verbForms: forms,
                                  verbShown: frame == .subject ? subjectVerb?.forms?.first : nil)
    }

    // MARK: The texts

    private static func good(for unit: KasusUnit) -> String {
        switch unit {
        case .nominativ: nominativGood
        case .akkusativ: akkusativGood
        case .dativ: dativGood
        case .genitiv: genitivGood
        case .alleFaelle: alleGood
        }
    }

    private static func edits(for unit: KasusUnit, _ kind: KasusCannedOutput) -> [(String, String)] {
        switch (unit, kind) {
        case (.nominativ, .altered):     [("Der Bruder spielt", "Mein Bruder spielt")]
        case (.nominativ, _):            [("auf dem Sofa", "auf der Sofa")]
        case (.akkusativ, .altered):     [("Opa trinkt den Kaffee", "Opa trinkt seinen Kaffee")]
        case (.akkusativ, _):            [("spielt mit dem Ball", "spielt mit den Ball")]
        case (.dativ, .altered):         [("Mia hilft dem Opa", "Mia hilft ihrem Opa")]
        case (.dativ, _):                [("mit dem Hund im Park", "mit den Hund im Park")]
        case (.genitiv, .altered):       [("Er trägt den Mantel", "Er trägt einen Mantel")]
        case (.genitiv, _):              [("Wegen des Regens", "Wegen des Regen")]
        case (.alleFaelle, .altered):    [("einen Kuchen beim", "den Kuchen beim")]
        case (.alleFaelle, _):           [("mit der Kamera", "mit die Kamera")]
        }
    }

    static let nominativGood = """
    TITEL: Sonntag bei Familie Klein
    GESCHICHTE:
    Es ist Sonntag. Familie Klein ist zu Hause. Der Hund schläft auf dem Sofa. Die Sonne scheint. Der Vater kocht heute in der Küche. Er macht Nudeln mit Tomaten. Die Mutter liest ein Buch.

    Um zwölf klingelt es. Ein Freund kommt zu Besuch. Er heißt Paul. Paul bringt einen Kuchen mit. Der Bruder spielt mit Paul im Garten. Dann essen alle zusammen. Das Essen ist sehr gut.

    Am Nachmittag essen alle den Kuchen. Der Kuchen ist lecker. Der Hund wacht auf. Er will auch Kuchen. Aber der Kuchen ist schon weg. Der Hund ist traurig. Der Vater lacht.
    """

    static let akkusativGood = """
    TITEL: Ein Ausflug mit Opa
    GESCHICHTE:
    Heute ist Samstag. Lena und Tim besuchen Opa. Der Opa wartet schon an der Tür. Er hat einen Plan: Alle gehen in den Park. Tim sucht den Ball. Er findet ihn unter dem Bett. Lena packt einen Apfel und Brot ein.

    Dann laufen sie durch den Park. Die Sonne scheint. Opa kauft einen Kaffee. Lena und Tim trinken Saft. Tim spielt mit dem Ball. Lena pflückt Blumen für die Oma.

    Am Abend gehen alle nach Hause. Oma freut sich über die Blumen. Opa trinkt den Kaffee. Er ist schon kalt. Aber alle lachen. Es war ein schöner Tag.
    """

    static let dativGood = """
    TITEL: Wo ist der Ball?
    GESCHICHTE:
    Am Samstag ist Mia bei ihrem Opa. Sie ist sechs Jahre alt. Im Garten spielt sie jeden Tag. Heute ist etwas weg: Mia sucht den Ball. Sie sucht im Garten und in der Küche. Aber sie findet ihn nicht.

    Der Opa sitzt im Wohnzimmer und liest die Zeitung. Er ist schon alt und hat Probleme mit dem Rücken. Mia hilft dem Opa gern. Sie bringt ihm einen Tee und macht das Fenster auf.

    Dann kommt der Vater nach Hause. Er ist mit dem Hund im Park gewesen. Der Hund heißt Bello und ist sehr müde. Er springt sofort auf das Sofa.

    Plötzlich lacht Mia. Der Ball liegt auf dem Sofa, direkt neben Bello! Der Vater nimmt den Ball und gibt dem Kind das Spielzeug zurück. Mia ist glücklich. Am Abend spielen alle zusammen im Garten.
    """

    static let genitivGood = """
    TITEL: Ein nasser Montag
    GESCHICHTE:
    Am Montag regnet es schon am Morgen. Jonas muss zur Arbeit. Wegen des Regens nimmt er heute nicht das Fahrrad. Er trägt den Mantel und geht zur Haltestelle.

    Dort wartet er lange. Der Bus kommt nicht. Jonas ist nervös, denn er hat heute um neun einen Termin. Eine Frau erklärt ihm: „Wegen eines Unfalls gibt es einen Stau in der Stadt.“ Jonas ruft seinen Chef an. Der Chef ist nett und sagt: „Kein Problem.“

    Nach einer Stunde kommt der Bus endlich. Jonas kommt zu spät ins Büro. Trotz der Kälte ist die Kollegin schon da. Sie bringt ihm einen heißen Kaffee.

    Am Abend scheint die Sonne. Jonas fährt mit dem Fahrrad nach Hause. Er denkt an den Morgen und lacht. Der Tag war lang, aber am Ende war alles gut.
    """

    static let alleGood = """
    TITEL: Ein Fest im Wohnzimmer
    GESCHICHTE:
    Heute hat Anna Geburtstag. Sie wird zehn Jahre alt. Leider ist das Wetter schlecht. Wegen des Wetters feiert die Familie nicht im Garten, sondern im Wohnzimmer.

    Am Nachmittag kommt der Onkel. Er bringt ein großes Paket mit. Die Mutter kauft noch schnell einen Kuchen beim Bäcker. Das Geschenk liegt auf dem Tisch. Anna öffnet es sofort. Es ist eine Kamera!

    Die Kamera gefällt dem Mädchen sehr. Sie macht gleich ein Foto mit dem Onkel. Dann macht sie Fotos für die Tante. Die Tante wohnt in Hamburg und kann nicht kommen.

    Später spielt ein Hund vor dem Haus. Er gehört dem Nachbarn. Trotz des Regens geht Anna mit der Kamera hinaus. Sie fotografiert den Hund. Am Abend zeigt sie der Familie alle Bilder. Alle lachen über den nassen Hund.
    """

    /// Names and bare nouns almost throughout: no unit's case reaches three gradable targets.
    static let tooFewA1 = """
    TITEL: Ein ruhiger Samstag
    GESCHICHTE:
    Heute ist Samstag. Lena und Tom sind zu Hause. Lena liest. Tom spielt Gitarre. Um zehn Uhr ruft Oma an. Sie kommt heute zu Besuch. Lena freut sich sehr. Tom räumt schnell auf. Lena kocht Kaffee.

    Um elf klingelt es. Oma ist da! Sie bringt Kekse mit. Alle trinken Kaffee und essen Kekse. Oma erzählt von früher. Lena und Tom hören zu. Später gehen alle spazieren. Es ist warm und sonnig.

    Sie laufen bis zum See. Dort sitzen sie lange. Am Abend fährt Oma nach Hause. Lena und Tom sind müde, aber glücklich.
    """

    static let tooFewA2 = tooFewA1 + """


    Sonntags schlafen Lena und Tom lange. Dann frühstücken sie zusammen. Tom macht Eier und Toast. Lena holt frische Brötchen. Danach lesen beide Zeitung und trinken Tee. Nachmittags besuchen sie Freunde. Sie gehen zusammen spazieren und essen Pizza. Alle haben viel Spaß.
    """
}

// MARK: - Launch arguments

/// `-kasus.debugGenerate <unit>` and `-kasus.debugGenerateFixture good|altered|wrongArticle|tooFew`:
/// the whole pipeline on canned output, so the sheet, the gate, the fallback and a generated story
/// can be screenshotted in the simulator. The screen opens the generation sheet for the unit with
/// `generator(for:)`; `report(_:)` prints what happened.
@MainActor
enum KasusGenerateDebug {
    static let unitKey = "kasus.debugGenerate"
    static let fixtureKey = "kasus.debugGenerateFixture"
    static let logPrefix = "[kasus.debugGenerate]"

    struct Launch: Hashable {
        let unit: KasusUnit
        let fixture: KasusCannedOutput
    }

    /// Nil unless `-kasus.debugGenerate` names a unit (nominativ … alleFaelle, any case; „alle“ too).
    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> Launch? {
        guard let raw = defaults.string(forKey: unitKey)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let unit = KasusUnit.allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame }
            ?? (raw.lowercased().hasPrefix("alle") ? .alleFaelle : nil)
        guard let unit else { return nil }
        let fixture = defaults.string(forKey: fixtureKey).flatMap(KasusCannedOutput.parse) ?? .good
        return Launch(unit: unit, fixture: fixture)
    }

    /// `-kasus.debugGenerateDelay <seconds>`: how long each canned phase takes (default 0.9 s), so
    /// a screenshot can catch the sheet mid-write.
    nonisolated static var launchDelay: Duration {
        let seconds = UserDefaults.standard.double(forKey: "kasus.debugGenerateDelay")
        return seconds > 0 ? .milliseconds(Int(seconds * 1000)) : .milliseconds(900)
    }

    /// A generator on the canned writer (a short delay per phase, so the sheet shows each one) and
    /// the request that plays the unit's fixture plan.
    static func generator(for launch: Launch, delay: Duration = launchDelay)
    -> (generator: KasusStoryGenerator, request: KasusGenerationRequest) {
        let writer = KasusGenerationFixtures.writer(for: launch.unit, launch.fixture, delay: delay)
        return (KasusStoryGenerator(writer: writer), KasusGenerationFixtures.request(for: launch.unit))
    }

    /// Printable lines: the outcome, then one line per attempt and its placements.
    static func report(_ result: KasusGenerationResult) -> [String] {
        var lines = ["\(logPrefix) \(result.request.unit.rawValue) · \(result.modelID) · \(result.outcome.rawValue)"
                     + (result.story.map { " · „\($0.title)“ (\($0.id))" } ?? "")]
        if let note = result.note { lines.append("\(logPrefix)   note: \(note)") }
        for attempt in result.attempts {
            lines.append("\(logPrefix)   #\(attempt.number) \(attempt.check?.summaryLine ?? attempt.error ?? "no output")")
            for placement in attempt.check?.placements ?? [] {
                lines.append("\(logPrefix)     \(placement.status.rawValue) \(placement.expression)"
                             + (placement.found.map { " → \($0)" } ?? ""))
            }
            for line in attempt.check?.report?.issueLines.filter({ $0.hasPrefix("error") }) ?? [] {
                lines.append("\(logPrefix)     \(line)")
            }
        }
        return lines
    }
}
#endif
