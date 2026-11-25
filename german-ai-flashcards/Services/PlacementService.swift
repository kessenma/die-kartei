//
//  PlacementService.swift
//  german-ai-flashcards
//
//  The placement probe: storage, item generation, and the scoring math. No UI, no SwiftData.
//
//  Everything it asks is drawn from bundled JSON, so the probe works on first launch before any
//  MLX model has been downloaded — which is the whole point, since it runs during onboarding.
//
//  One rule governs item selection and is worth stating loudly: **items come from the same lists
//  the pyramid scores against** (`GoetheVocabService`, `prepositions.json`). The pyramid credits
//  A1 vocabulary as a fraction of the 585-word Goethe A1 list, so sampling questions from any
//  other word list — however well tagged — would make `vocabKnown × goal` an estimate of the
//  wrong population. Grammar is the one exception: its items come from the authored placement
//  bank (`placement_grammar.json`), because grammar feeds the *level estimate*, not a list-sized
//  pyramid credit.
//

import Foundation

enum PlacementService {

    // MARK: - Tuning
    //
    // Every number the probe's judgment depends on lives here, in one block, on purpose. These
    // were chosen by simulating learners of known ability through this exact pair of staircases
    // and scorer (`tools/placement_calibration.py`), not picked by feel — with 4 000 runs per
    // profile the settings below classify a true beginner correctly 100 % of the time, an A1
    // 84 %, an A2 76 %, a B1 74 % and a B2 77 %, with every error landing one level away.

    /// Answers per block: 2 + 8 + 5 + 3 + 8 + 3 = 29, which lands around three minutes.
    static let anchorItems = 2
    static let vocabItems = 8
    static let genderItems = 5
    static let prepositionItems = 3
    static let grammarItems = 8
    static let clozeGaps = 3

    static let choiceCount = 4
    /// der/die/das — three buttons, so a guess lands one time in three.
    static let genderChoiceCount = 3
    /// Grammar and cloze gaps offer three options, like the telc-style tests they're modelled on.
    static let grammarChoiceCount = 3

    /// The vocabulary staircase starts here and walks toward the truth.
    static let startLevel: GoetheLevel = .a2
    /// Consecutive right answers that promote the probe a level, and wrong ones that demote it.
    static let stepUpStreak = 2
    static let stepDownStreak = 2

    /// The grammar staircase's range. Vocabulary stops at B1 with the bundled lists; grammar is
    /// the only block with the reach to tell a B1 from a B2.
    static let grammarLadder: [CEFRLevel] = [.a1, .a2, .b1, .b2]
    /// Cloze gaps that must be right for the finale to confirm the estimate; fewer demotes a level.
    static let clozePassCount = 2
    /// A vocabulary list whose raw rate lands in [rescueFloor, passRate) was *narrowly* missed;
    /// if the grammar staircase held that level anyway, the level counts — pooled evidence, the
    /// way the telc exams count Sprachbausteine toward the written total.
    static let vocabRescueFloor = 0.50

    /// Hit rate at or above which a level counts as "held". Applied to the RAW rate, see `estimate`.
    static let levelPassRate = 0.65
    /// A level needs at least this many items before it can be cleared, so one lucky answer at the
    /// top of the staircase can't promote someone a level.
    static let minItemsPerLevel = 2
    /// If gender/preposition/grammar accuracy falls below this, the vocabulary reading is treated
    /// as recognition without structure and the estimate drops one level.
    static let supportFloor = 0.50
    /// Shrinkage prior: with a 10-item block this caps credit near 77 %, so no one can place their
    /// way to a finished layer — the last quarter has to be earned. That ceiling is the point.
    static let priorItems = 3.0
    /// Corrected knowledge below this reads as luck and credits nothing.
    static let knowledgeDeadband = 0.20

    // MARK: - Storage

    private static let resultKey = "placement.result"
    /// Set once the learner has been offered the probe, whether they took it, skipped it, or
    /// dismissed it — so onboarding never asks twice.
    static let seenKey = "placement.seen"

    /// The stored result, or nil if the probe was never completed.
    static var current: PlacementResult? {
        guard let data = UserDefaults.standard.data(forKey: resultKey) else { return nil }
        return try? JSONDecoder().decode(PlacementResult.self, from: data)
    }

    static func save(_ result: PlacementResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        UserDefaults.standard.set(data, forKey: resultKey)
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// Clears the estimate. The pyramid's provisional channel empties; nothing earned is touched.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: resultKey)
    }

    static var hasBeenOffered: Bool {
        UserDefaults.standard.bool(forKey: seenKey)
    }

    static func markOffered() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

#if DEBUG
    /// Seeds a synthetic estimate from a launch argument, so the ghost rendering can actually be
    /// checked on a simulator — which runs the app fine but can't tap through twenty-three
    /// questions. The values mirror what the calibration simulation produces for each profile, so
    /// what you see on screen is what a real learner at that level would get.
    ///
    ///     xcrun simctl launch <udid> <bundle-id> -placement.debugLevel B1
    ///
    /// Accepts `A1` / `A2` / `B1` / `B2` / `beginner`. DEBUG builds only — never ships. Note that
    /// seeding writes only the stored result: `germanLevel` is set by the quiz UI on a real run, so
    /// a seeded `B2` shows on the pyramid but does not move the content level. Its counterpart is
    /// `-level.debugDeclare` (in `ContentView`), which does exactly the opposite — moves the level
    /// and writes no result. Between them they prove the two channels are independent.
    static func applyDebugLaunchArgumentIfNeeded() {
        guard let raw = UserDefaults.standard.string(forKey: "placement.debugLevel") else { return }
        markOffered()

        if raw.lowercased() == "beginner" {
            save(.beginner())
            return
        }
        guard let level = CEFRLevel(rawValue: raw.uppercased()), grammarLadder.contains(level) else { return }

        // Straight from the simulation's mean output per profile (see the calibration harness).
        let vocab: [String: Double]
        let support: Double
        let grammarConstructs: [String: Double]
        switch level {
        case .a1:
            vocab = ["A1": 0.58, "A2": 0.21, "B1": 0.06]; support = 0.60
            grammarConstructs = ["artikel-definit": 0.6, "praesens-konjugation": 0.6]
        case .a2:
            vocab = ["A1": 0.64, "A2": 0.61, "B1": 0.19]; support = 0.72
            grammarConstructs = ["perfekt-aux": 0.7, "weil-order": 0.7]
        case .b1:
            vocab = ["A1": 0.71, "A2": 0.70, "B1": 0.52]; support = 0.85
            grammarConstructs = ["konjunktiv2": 0.8, "passiv-werden": 0.8]
        case .b2:
            vocab = ["A1": 0.72, "A2": 0.72, "B1": 0.67]; support = 0.90
            grammarConstructs = ["konjunktiv2-vergangenheit": 1.0, "passiversatz": 1.0]
        default:
            return   // the ladder guard above keeps C1 out; this is unreachable
        }

        save(PlacementResult(
            takenAt: Date(),
            estimatedLevelRaw: level.rawValue,
            vocabKnown: vocab,
            articleAccuracy: support,
            prepositionAccuracy: support,
            grammarAccuracy: grammarConstructs,
            itemsAnswered: anchorItems + vocabItems + genderItems + prepositionItems + grammarItems + clozeGaps,
            declaredBeginner: false,
            grammarLevelRaw: level.rawValue,
            clozeLevelRaw: level.rawValue,
            clozeCorrect: clozeGaps
        ))
    }

    /// Seeds N synthetic *attempts* — the review screen's only route onto a simulator, which runs
    /// the probe fine but can't be tapped through twenty-nine questions, let alone four times over
    /// to make a repeat offender appear.
    ///
    ///     xcrun simctl launch <udid> <bundle-id> -placement.debugAttempts 4 -placement.debugAccuracy 0.6
    ///
    /// Drives a **real** `PlacementSession`, so the questions, the staircases and the explanations
    /// are the real ones rather than a fixture that could drift from them.
    ///
    /// The seed governs the simulated *answers* only — which items get asked still comes from the
    /// session's own unseeded sampling, so two runs at the same accuracy produce similar but not
    /// identical histories. That's deliberate (a fixed item list would stop exercising the
    /// staircases), but it does mean counts wobble between runs.
    ///
    /// Repeat offenders are guaranteed regardless: the two anchors open every run, and the bank
    /// holds 10–12 items per level against 8 grammar questions, so grammar ids recur heavily across
    /// a few attempts. Vocabulary repeats stay rare — that block samples 585/1209/2358-word lists —
    /// and that asymmetry is real rather than a flaw in the seeder.
    static func seedDebugAttempts(count: Int, accuracy: Double) {
        var rng = SeededGenerator(seed: 42)
        let skipRate = 0.05

        for offset in 0..<count {
            let session = PlacementSession()
            while let item = session.current {
                let roll = Double.random(in: 0..<1, using: &rng)
                if roll < skipRate {
                    session.answer(nil)
                } else if roll < skipRate + accuracy {
                    session.answer(item.correctIndex)
                } else {
                    let wrong = (0..<item.choices.count).filter { $0 != item.correctIndex }
                    session.answer(wrong.randomElement(using: &rng))
                }
            }
            if let cloze = session.currentCloze {
                session.answerCloze(cloze.gaps.map { gap in
                    Double.random(in: 0..<1, using: &rng) < accuracy
                        ? gap.correctIndex
                        : (0..<gap.choices.count).filter { $0 != gap.correctIndex }.randomElement(using: &rng)
                })
            }
            // Backdated a week apart so the attempt list, the date pills and the calendar-style
            // ordering all have something real to sort.
            let takenAt = Date().addingTimeInterval(-Double(offset) * 7 * 24 * 3600)
            PlacementAttemptStore.record(
                result: session.result(at: takenAt),
                answers: session.answers,
                cloze: session.finishedCloze
            )
        }
    }

    static func applyDebugAttemptsLaunchArgumentIfNeeded() {
        let count = UserDefaults.standard.integer(forKey: "placement.debugAttempts")
        guard count > 0 else { return }
        let accuracy = UserDefaults.standard.object(forKey: "placement.debugAccuracy") as? Double ?? 0.6
        PlacementAttemptStore.deleteAll()
        PlacementCoachExport.resetHighWaterMark()
        seedDebugAttempts(count: min(count, attemptCapForDebug), accuracy: accuracy)

        // Adopt the newest seeded run, so the sim matches how a real device behaves: the live
        // estimate is always *some check's* result. Without this the stored estimate comes from
        // `-placement.debugLevel`'s synthetic blob, which equals no attempt, and the review screen
        // correctly shows nothing as "Now in use" — accurate, but it makes the badge untestable.
        if let newest = PlacementAttemptStore.attempts().first {
            save(newest.result)
        }
    }

    private static var attemptCapForDebug: Int { PlacementAttemptStore.cap }
#endif

    // MARK: - Item generation

    /// A word's meaning, four ways. Distractors come from the *same* level list, so a wrong answer
    /// is wrong on meaning rather than giving the level away by being obviously harder.
    static func vocabItem(level: GoetheLevel, used: Set<String>) -> PlacementItem? {
        let pool = GoetheVocabService.entries(for: level).filter { entry in
            guard let translation = entry.translation, !translation.isEmpty else { return false }
            return !used.contains(entry.word.lowercased())
        }
        guard let answer = pool.randomElement(), let correct = answer.translation.map(conciseGloss)
        else { return nil }

        var choices: Set<String> = [correct]
        var attempts = 0
        while choices.count < choiceCount, attempts < 200 {
            attempts += 1
            if let candidate = pool.randomElement()?.translation, !candidate.isEmpty {
                choices.insert(conciseGloss(candidate))
            }
        }
        guard choices.count == choiceCount else { return nil }

        let ordered = choices.shuffled()
        guard let index = ordered.firstIndex(of: correct) else { return nil }
        return PlacementItem(
            kind: .vocab(level),
            prompt: answer.word,
            subtitle: nil,
            choices: ordered,
            correctIndex: index
        )
    }

    /// A dictionary gloss condensed to its head translations: parenthetical elaborations dropped,
    /// whitespace healed. "to use, apply, utilize or deploy (to put to use for a purpose)" reads
    /// as a definition; "to use, apply, utilize or deploy" reads as an answer button. Condensing
    /// *before* the choice set dedupes also keeps two options from differing only inside a
    /// parenthetical the learner has to squint at. Falls back to the input when stripping would
    /// leave nothing — some glosses ("indicating (…) motion into something") lean on their parens.
    nonisolated static func conciseGloss(_ translation: String) -> String {
        var out = ""
        var depth = 0
        for ch in translation {
            if ch == "(" { depth += 1; continue }
            if ch == ")" { depth = max(0, depth - 1); continue }
            if depth == 0 { out.append(ch) }
        }
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
        return out.count >= 2 ? out : translation.trimmingCharacters(in: .whitespaces)
    }

    /// der/die/das for a noun. The prompt is the bare noun — showing the article would answer it.
    static func genderItem(level: GoetheLevel, used: Set<String>) -> PlacementItem? {
        let articles = ["der", "die", "das"]
        let pool = GoetheVocabService.entries(for: level).filter { entry in
            guard let article = entry.article?.lowercased(), articles.contains(article) else { return false }
            return !used.contains(entry.word.lowercased())
        }
        guard let answer = pool.randomElement(),
              let article = answer.article?.lowercased(),
              let index = articles.firstIndex(of: article)
        else { return nil }

        return PlacementItem(
            kind: .gender,
            prompt: answer.word,
            subtitle: answer.translation.map(conciseGloss),
            choices: articles,
            correctIndex: index
        )
    }

    /// Which case a preposition governs. All four cases stay on offer, as in the Kasus drill, so a
    /// learner can't narrow the answer by counting buttons.
    static func prepositionItem(used: Set<String>) -> PlacementItem? {
        let pool = PrepositionService.prepositions(includeAdvanced: false).filter {
            !used.contains($0.word.lowercased())
        }
        guard let answer = pool.randomElement() else { return nil }
        let choices = PrepositionCase.allCases.map(\.germanLabel)
        guard let index = choices.firstIndex(of: answer.governs.germanLabel) else { return nil }

        return PlacementItem(
            kind: .preposition,
            prompt: answer.word,
            subtitle: answer.meaningLine,
            choices: choices,
            correctIndex: index
        )
    }

    /// One of the two fixed anchor items, by position. Both probe the A1/A2 boundary (Perfekt
    /// auxiliary, weil word order) and decide where the grammar staircase starts.
    static func anchorItem(index: Int) -> PlacementItem? {
        let anchors = PlacementGrammarBank.anchors()
        guard anchors.indices.contains(index) else { return nil }
        return grammarPlacementItem(from: anchors[index], isAnchor: true)
    }

    /// A staircase item at the given level from the authored bank, avoiding anything already asked
    /// this run. No subtitle: naming the construct would hint at the answer.
    static func grammarItem(level: CEFRLevel, used: Set<String>) -> PlacementItem? {
        guard let bank = PlacementGrammarBank.items(level: level, excluding: used).randomElement()
        else { return nil }
        return grammarPlacementItem(from: bank, isAnchor: false)
    }

    private static func grammarPlacementItem(from bank: PlacementGrammarItem, isAnchor: Bool) -> PlacementItem? {
        guard let level = bank.cefr else { return nil }
        let choices = bank.options.shuffled()
        guard let index = choices.firstIndex(of: bank.correct) else { return nil }
        return PlacementItem(
            kind: .grammar(level: level, construct: bank.construct, isAnchor: isAnchor),
            prompt: bank.sentence,
            subtitle: nil,
            choices: choices,
            correctIndex: index,
            sourceID: bank.id
        )
    }

    /// The finale paragraph for a level, split around its `{i}` markers with each gap's options
    /// shuffled exactly once — what's shown is what gets scored.
    static func clozePrompt(level: CEFRLevel) -> PlacementClozePrompt? {
        guard let paragraph = PlacementGrammarBank.clozeParagraph(level: level),
              let cefr = paragraph.cefr else { return nil }

        var segments: [String] = []
        var gaps: [PlacementClozePrompt.Gap] = []
        var rest = paragraph.text
        for (index, gap) in paragraph.gaps.enumerated() {
            guard let range = rest.range(of: "{\(index)}") else { return nil }
            segments.append(String(rest[..<range.lowerBound]))
            rest = String(rest[range.upperBound...])
            let choices = gap.options.shuffled()
            guard let correctIndex = choices.firstIndex(of: gap.correct) else { return nil }
            gaps.append(.init(construct: gap.construct, choices: choices, correctIndex: correctIndex))
        }
        segments.append(rest)

        return PlacementClozePrompt(
            id: paragraph.id,
            level: cefr,
            title: paragraph.title,
            segments: segments,
            gaps: gaps
        )
    }

    // MARK: - Scoring

    /// Turns a finished set of answers into an estimate.
    static func score(_ answers: [PlacementAnswer], at date: Date = Date()) -> PlacementResult {
        let vocab = vocabKnownByLevel(answers)
        let article = accuracy(answers) { if case .gender = $0 { return true } else { return false } } ?? 0
        let preposition = accuracy(answers) { if case .preposition = $0 { return true } else { return false } } ?? 0

        // Per-construct rates over the single-gap grammar items (anchors included, cloze excluded).
        var grammar: [String: Double] = [:]
        let constructs = Set(answers.compactMap { answer -> String? in
            guard case .grammar(_, let construct, _) = answer.item.kind else { return nil }
            return construct
        })
        for construct in constructs {
            let rate = accuracy(answers) { kind in
                if case .grammar(_, let c, _) = kind { return c == construct } else { return false }
            }
            if let rate { grammar[construct] = rate }
        }

        let gCounts = grammarCounts(answers)
        let grammarOverall = accuracy(answers) { if case .grammar = $0 { return true } else { return false } }

        var clozeLevel: CEFRLevel?
        var clozeCorrect: Int?
        let clozeAnswers = answers.filter { if case .cloze = $0.item.kind { return true } else { return false } }
        if let first = clozeAnswers.first, case .cloze(let level, _, _) = first.item.kind {
            clozeLevel = level
            clozeCorrect = clozeAnswers.filter(\.isCorrect).count
        }

        let level = estimate(
            vocabCounts: vocabCounts(answers),
            grammarCounts: gCounts,
            article: article,
            preposition: preposition,
            grammarOverall: grammarOverall,
            clozeLevel: clozeLevel,
            clozeCorrect: clozeCorrect
        )

        return PlacementResult(
            takenAt: date,
            estimatedLevelRaw: level.rawValue,
            vocabKnown: vocab,
            articleAccuracy: article,
            prepositionAccuracy: preposition,
            grammarAccuracy: grammar,
            itemsAnswered: answers.filter { !$0.wasSkipped }.count,
            declaredBeginner: false,
            grammarLevelRaw: grammarPeak(gCounts)?.rawValue,
            clozeLevelRaw: clozeLevel?.rawValue,
            clozeCorrect: clozeCorrect
        )
    }

    /// Right answers and questions asked, per level.
    struct LevelCount { var correct = 0; var asked = 0 }

    static func vocabCounts(_ answers: [PlacementAnswer]) -> [GoetheLevel: LevelCount] {
        var counts: [GoetheLevel: LevelCount] = [:]
        for answer in answers {
            guard case .vocab(let level) = answer.item.kind else { continue }
            var count = counts[level] ?? LevelCount()
            count.asked += 1
            if answer.isCorrect { count.correct += 1 }
            counts[level] = count
        }
        return counts
    }

    /// Grammar answers per staircase level — anchors count (they're real A2 evidence), the cloze
    /// doesn't (it gates the estimate separately).
    static func grammarCounts(_ answers: [PlacementAnswer]) -> [CEFRLevel: LevelCount] {
        var counts: [CEFRLevel: LevelCount] = [:]
        for answer in answers {
            guard case .grammar(let level, _, _) = answer.item.kind else { continue }
            var count = counts[level] ?? LevelCount()
            count.asked += 1
            if answer.isCorrect { count.correct += 1 }
            counts[level] = count
        }
        return counts
    }

    /// The highest staircase level held to the same standard the vocab reading uses: at least
    /// `minItemsPerLevel` asked and the raw rate at or above `levelPassRate`. Nil when no level
    /// clears it.
    static func grammarPeak(_ counts: [CEFRLevel: LevelCount]) -> CEFRLevel? {
        var peak: CEFRLevel?
        for level in grammarLadder {
            guard let count = counts[level], count.asked >= minItemsPerLevel else { continue }
            if Double(count.correct) / Double(count.asked) >= levelPassRate { peak = level }
        }
        return peak
    }

    /// The estimate as it stands before the finale — what the session uses to pick the cloze
    /// paragraph's level, so the finale tests exactly the level the scorer would otherwise report.
    static func preClozeEstimate(_ answers: [PlacementAnswer]) -> CEFRLevel {
        let article = accuracy(answers) { if case .gender = $0 { return true } else { return false } } ?? 0
        let preposition = accuracy(answers) { if case .preposition = $0 { return true } else { return false } } ?? 0
        let grammarOverall = accuracy(answers) { if case .grammar = $0 { return true } else { return false } }
        return estimate(
            vocabCounts: vocabCounts(answers),
            grammarCounts: grammarCounts(answers),
            article: article,
            preposition: preposition,
            grammarOverall: grammarOverall,
            clozeLevel: nil,
            clozeCorrect: nil
        )
    }

    /// An observed hit rate turned into the fraction of a list the learner actually knows.
    ///
    /// Two corrections, both deliberately conservative. Over-crediting fills the pyramid with words
    /// the learner can't produce — the exact failure this feature exists to prevent — while
    /// under-crediting only means they earn it for real slightly sooner.
    ///
    ///   1. **Correction for guessing.** A k-choice question floors the hit rate at 1/k, so someone
    ///      who knows nothing still scores 25 %. Strip that floor out before believing anything.
    ///   2. **Shrinkage on the size of the whole block, not this level's slice.** The staircase
    ///      spends its questions where the learner is marginal, so a strong learner sees few A1
    ///      items *because* they climbed past A1. Shrinking per level would punish exactly the
    ///      learner this feature is for.
    static func knowledge(correct: Int, asked: Int, choices: Int, blockSize: Int) -> Double {
        guard asked > 0, choices > 1 else { return 0 }
        let raw = Double(correct) / Double(asked)
        let chance = 1.0 / Double(choices)
        let corrected = max(0, (raw - chance) / (1 - chance))
        guard corrected >= knowledgeDeadband else { return 0 }
        let n = Double(max(blockSize, asked))
        return corrected * (n / (n + priorItems))
    }

    /// The corrected knowledge implied by a stored block accuracy.
    ///
    /// `PlacementResult` keeps gender/preposition accuracy raw, because the level estimate needs
    /// the raw rate. Pyramid credit needs the corrected figure, and since a rate over a known item
    /// count recovers the counts exactly, it can be derived here rather than stored twice.
    static func knowledge(fromAccuracy accuracy: Double, items: Int, choices: Int) -> Double {
        let correct = Int((accuracy * Double(items)).rounded())
        return knowledge(correct: correct, asked: items, choices: choices, blockSize: items)
    }

    /// Per-level vocabulary knowledge — the figure that becomes provisional pyramid credit.
    static func vocabKnownByLevel(_ answers: [PlacementAnswer]) -> [String: Double] {
        let counts = vocabCounts(answers)
        let blockSize = counts.values.reduce(0) { $0 + $1.asked }
        guard blockSize > 0 else { return [:] }

        var measured: [GoetheLevel: Double] = [:]
        for (level, count) in counts where count.asked > 0 {
            measured[level] = knowledge(
                correct: count.correct,
                asked: count.asked,
                choices: choiceCount,
                blockSize: blockSize
            )
        }

        // Levels the staircase never reached inherit their nearest probed neighbour: a learner who
        // never got asked an A1 word because they were answering B1 ones still knows the A1 list.
        var filled: [GoetheLevel: Double] = [:]
        var carried: Double?
        for level in GoetheLevel.allCases {
            if let value = measured[level] { carried = value }
            if let carried { filled[level] = carried }
        }
        carried = nil
        for level in GoetheLevel.allCases.reversed() {
            if let value = filled[level] { carried = value } else if let carried { filled[level] = carried }
        }

        // Monotonic: never claim more of a harder list than of an easier one.
        var result: [String: Double] = [:]
        var ceiling = 1.0
        for level in GoetheLevel.allCases {
            let value = min(filled[level] ?? 0, ceiling)
            result[level.rawValue] = value
            ceiling = value
        }
        return result
    }

    /// The headline reading. Vocabulary sets the base level; grammar can rescue a narrow vocab
    /// miss and is the only road past B1; support/cloze can only pull the reading down —
    /// recognising words without holding the structures is not that level.
    ///
    /// This reads **raw** hit rates, not the credit figure above, and the difference matters:
    /// shrinkage exists to keep the pyramid honest about how many words to credit, and applying it
    /// here made a strong learner unclassifiable in simulation (a true B1 read as A1 83 % of the
    /// time) because they earn few items per level precisely by climbing. Credit and classification
    /// are different questions and are answered separately.
    ///
    /// Order is deliberate and documented: the support floor demotes before the cloze gate so two
    /// independent pieces of negative evidence can stack, and both floor at A1. A B2 pulled down by
    /// either gate lands on B1 — the safe published level.
    static func estimate(
        vocabCounts counts: [GoetheLevel: LevelCount],
        grammarCounts: [CEFRLevel: LevelCount],
        article: Double,
        preposition: Double,
        grammarOverall: Double?,
        clozeLevel: CEFRLevel?,
        clozeCorrect: Int?
    ) -> CEFRLevel {
        // 1. Vocabulary base — the bundled lists stop at B1, so vocabulary can never claim B2.
        var reached: GoetheLevel = .a1
        var cleared = false
        for level in GoetheLevel.allCases {
            guard let count = counts[level], count.asked >= minItemsPerLevel else { continue }
            if Double(count.correct) / Double(count.asked) >= levelPassRate {
                reached = level
                cleared = true
            }
        }
        var candidate: CEFRLevel = cleared ? reached.cefr : .a1
        let peak = grammarPeak(grammarCounts)

        // 2. Rescue at the margin: the next list was narrowly missed (raw in the rescue band)
        //    while the grammar staircase held that level or better. Vocabulary alone under-read a
        //    true B1 one run in five in simulation; pooling the two signals fixed that without
        //    letting grammar promote on its own.
        if candidate == .a1 || candidate == .a2 {
            let next: GoetheLevel = candidate == .a1 ? .a2 : .b1
            if let count = counts[next], count.asked >= minItemsPerLevel,
               Double(count.correct) / Double(count.asked) >= vocabRescueFloor,
               let peak,
               let peakIndex = grammarLadder.firstIndex(of: peak),
               let nextIndex = grammarLadder.firstIndex(of: next.cefr),
               peakIndex >= nextIndex {
                candidate = next.cefr
            }
        }

        // 3. Held B1 vocabulary plus held B2 grammar is the only road to B2.
        if candidate == .b1, peak == .b2 { candidate = .b2 }

        // 4. Support floor: gender/preposition/grammar under 50 % reads as recognition without
        //    structure, and the estimate drops a level.
        var support = [article, preposition]
        if let grammarOverall { support.append(grammarOverall) }
        let supportScore = support.reduce(0, +) / Double(support.count)
        if supportScore < supportFloor { candidate = demoted(candidate) }

        // 5. Cloze gate: the finale confirms or demotes, never promotes.
        if clozeLevel != nil, let clozeCorrect, clozeCorrect < clozePassCount {
            candidate = demoted(candidate)
        }
        return candidate
    }

    private static func demoted(_ level: CEFRLevel) -> CEFRLevel {
        guard let index = grammarLadder.firstIndex(of: level), index > 0 else { return level }
        return grammarLadder[index - 1]
    }

    /// Accuracy over the answers whose kind matches, or nil when none were asked — "not asked" and
    /// "got them all wrong" must not collapse into the same 0.
    private static func accuracy(
        _ answers: [PlacementAnswer],
        matching predicate: (PlacementItem.Kind) -> Bool
    ) -> Double? {
        let asked = answers.filter { predicate($0.item.kind) }
        guard !asked.isEmpty else { return nil }
        return Double(asked.filter(\.isCorrect).count) / Double(asked.count)
    }

    // MARK: - Calibration

    /// Raw block scores next to the estimate they produce, for checking the cutoffs above against
    /// real answers instead of trusting them. Printed from the debug row on the pyramid screen.
    static func debugScoreReport(_ answers: [PlacementAnswer]) -> String {
        let result = score(answers)
        var lines = ["PLACEMENT — \(answers.count) items"]
        for level in GoetheLevel.allCases {
            let asked = answers.filter { if case .vocab(let l) = $0.item.kind { return l == level } else { return false } }
            let correct = asked.filter(\.isCorrect).count
            lines.append("  vocab \(level.rawValue): \(correct)/\(asked.count) raw → \(pct(result.vocabKnown(level))) smoothed")
        }
        lines.append("  gender: \(pct(result.articleAccuracy))")
        lines.append("  prepositions: \(pct(result.prepositionAccuracy))")
        let gCounts = grammarCounts(answers)
        for level in grammarLadder {
            guard let count = gCounts[level], count.asked > 0 else { continue }
            lines.append("  grammar \(level.rawValue): \(count.correct)/\(count.asked)")
        }
        for (construct, rate) in result.grammarAccuracy.sorted(by: { $0.key < $1.key }) {
            lines.append("    \(construct): \(pct(rate))")
        }
        if let clozeLevelRaw = result.clozeLevelRaw, let clozeCorrect = result.clozeCorrect {
            lines.append("  cloze \(clozeLevelRaw): \(clozeCorrect)/\(clozeGaps)")
        }
        lines.append("  → estimate \(result.estimatedLevelRaw) (pass \(pct(levelPassRate)), support floor \(pct(supportFloor)))")
        return lines.joined(separator: "\n")
    }

    private static func pct(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

// MARK: - Level bridge

extension GoetheLevel {
    /// The bundled word lists stop at B1. The estimate no longer does — B2 rides on grammar
    /// evidence — but every vocabulary-derived reading still maps one-to-one.
    var cefr: CEFRLevel {
        switch self {
        case .a1: .a1
        case .a2: .a2
        case .b1: .b1
        }
    }
}
