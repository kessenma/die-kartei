//
//  KasusStoryPrompt.swift
//  german-ai-flashcards
//
//  The pure half of a tutor-written Kasus story: the prompt, the request, an attempt and its
//  result, and the trim of a cut-off write. Nothing here touches MLX, so `training/kasus_cli`
//  compiles it with the planner and the check, and training data is written to the exact prompt
//  the app sends.
//

import Foundation

// MARK: - The prompt

@MainActor
enum KasusStoryPrompt {

    static let temperature: Float = 0.75
    static let phraseInstruction = "Verwende JEDEN dieser Ausdrücke genau einmal und GENAU so geschrieben:"

    /// The story prompt the Stories feature uses (level constraints, TITEL:/GESCHICHTE:), plus the
    /// planned phrases (contract A) or the „FÄLLE:“ block (contract B). The phrases are listed
    /// without quotes so the model doesn't quote them in the story.
    static func build(_ plan: KasusStoryPlan) -> (system: String, user: String) {
        let level = plan.cefr ?? .a2
        let base = StoryStudyService.storyPrompt(topic: plan.topic, level: level, genre: plan.genre)
        switch plan.contract {
        case .planned:
            let list = plan.phrases.map { "- \($0.expression)\($0.promptHint)" }.joined(separator: "\n")
            let user = base.user + """


            \(phraseInstruction)
            \(list)
            Schreibe jeden Ausdruck zusammen mit seinem Verb in denselben Satz. Ändere keinen Artikel und keine Endung.
            Schreibe genau diesen Artikel (der, den, dem, ein, einen …), nicht mein, dein, sein oder ihr. Am Satzanfang darfst du ihn großschreiben.
            """
            return (base.system, user)
        case .selfLabelled:
            let focus = plan.unit.flatMap(\.focusCase).map { "Verwende viele Nomen mit Artikel im \($0.name)." }
                ?? "Verwende Nomen mit Artikel in allen vier Fällen."
            let system = base.system + """

            \(KasusSelfLabels.heading)
            <jede Nominalgruppe mit Artikel aus der Geschichte, eine pro Zeile: Ausdruck | Fall>
            """
            let user = base.user + """

            \(focus)
            Schreibe nach der Geschichte die Zeile „\(KasusSelfLabels.heading)“. Darunter steht JEDE Nominalgruppe aus der Geschichte, die mit einem Artikel beginnt (der, die, das, ein, eine, mein, kein …), genau wie im Text, eine pro Zeile, mit ihrem Fall: Nom, Akk, Dat oder Gen. Zum Beispiel:
            den Ball | Akk
            dem Kind | Dat
            Schreibe den Artikel so, wie er im Text steht, nicht die Grundform: Steht im Text „Ich sehe den Schrank“, schreibe „den Schrank | Akk“ (nicht „der Schrank“).
            """
            return (system, user)
        }
    }

    /// The level's story budget; contract B gets room for its label block on top.
    static func maxTokens(for plan: KasusStoryPlan) -> Int {
        (plan.cefr ?? .a2).storyMaxTokens + (plan.contract == .selfLabelled ? 250 : 0)
    }
}

// MARK: - Request and result

struct KasusGenerationRequest {
    var unit: KasusUnit
    var level: CEFRLevel
    var contract: KasusContract = .planned
    /// The first attempt's seed; the retry's follows from it (`KasusStoryPlan.retrySeed`).
    var seed: UInt64 = KasusStoryPlan.randomSeed()
    /// The learner's own nouns, offered to the planner as things.
    var learnerNouns: [String] = []
    /// Tests and `-kasus.debugGenerate`: every attempt uses this plan instead of planning.
    var fixedPlan: KasusStoryPlan? = nil
    /// The bundled story to fall back on; nil picks the unit's first.
    var fallbackStoryID: String? = nil
    /// Attempts after the first. The product retries once.
    var retries: Int = 1
}

/// One write and its check.
struct KasusGenerationAttempt {
    /// 1 for the first try, 2 for the retry.
    let number: Int
    let plan: KasusStoryPlan
    let system: String
    let user: String
    let raw: String
    let seconds: Double
    let tokenCount: Int
    let endedEarly: Bool
    /// Nil when the write threw.
    let check: KasusCheckResult?
    let error: String?

    var passes: Bool { check?.passes == true }
}

struct KasusGenerationResult {
    enum Outcome: String {
        /// A story passed the check: play it, and save it (`KasusStoryStore.save`).
        case generated
        /// Every attempt failed: play the bundled story with the note.
        case fallback
        /// The model couldn't be used at all (not a tutor, a loadModel refusal). `story` still
        /// holds the bundled fallback, for the sheet to offer.
        case failed
        case cancelled
    }

    let outcome: Outcome
    /// The generated story, or the bundled fallback.
    let story: KasusStory?
    /// The fallback note, or why nothing could be written.
    let note: String?
    let attempts: [KasusGenerationAttempt]
    let modelID: String
    let governed: Bool
    let request: KasusGenerationRequest

    /// The attempt whose story is being played.
    var passing: KasusGenerationAttempt? { attempts.first(where: \.passes) }
    var passedFirstTry: Bool { attempts.first?.passes == true }
    var passedAfterRetry: Bool { passing != nil }
    var totalSeconds: Double { attempts.reduce(0) { $0 + $1.seconds } }
}

// MARK: - A cut-off write

extension KasusStoryGenerator {

    /// A write cut off mid-sentence (stopped early, or not ending on . ! ? …) up to its last full
    /// sentence, so a saved story never ends halfway through one. Unchanged when it ends
    /// cleanly, or when no sentence ends anywhere (the check will say so).
    static func completeSentences(_ text: String, endedEarly: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let closers: Set<Character> = ["“", "”", "\"", "'", "»", ")"]
        let enders: Set<Character> = [".", "!", "?", "…"]
        var end = trimmed.endIndex
        while end > trimmed.startIndex, closers.contains(trimmed[trimmed.index(before: end)]) {
            end = trimmed.index(before: end)
        }
        let endsCleanly = end > trimmed.startIndex && enders.contains(trimmed[trimmed.index(before: end)])
        guard endedEarly || !endsCleanly else { return trimmed }
        guard let last = trimmed.lastIndex(where: { enders.contains($0) }) else { return trimmed }
        var cut = trimmed.index(after: last)
        while cut < trimmed.endIndex, closers.contains(trimmed[cut]) { cut = trimmed.index(after: cut) }
        // A write that ended early on a clean full stop is already whole.
        if endsCleanly, cut >= end { return trimmed }
        return String(trimmed[..<cut])
    }
}
