//
//  KasusStoryCheck.swift
//  german-ai-flashcards
//
//  Turns one raw tutor output into a Kasus story and decides whether it may be played (Phase 3).
//  Pure: no model, no store, so tests and the Lab run it on canned text.
//
//    parse     TITEL:/GESCHICHTE: prose through `StoryStudyService.parseStory`, never JSON (the
//              JSON sanitizer turns „…“ into ASCII quotes and breaks the prose). A contract B
//              „FÄLLE:“ block is split off first. One paragraph per non-empty line.
//    locate    a planned phrase becomes a target only where it stands verbatim and its verb (or
//              the preposition in it) is in the same sentence, and a verb-frame phrase only where
//              no preposition stands right in front („kauft Futter für den Hund“ is für's, not
//              kauft's). Otherwise it's reported as trigger missing, altered or missing, and its
//              words go to the harvest like any other.
//    harvest   every other article + noun phrase (`KasusHarvest`): proven ones become `inferred`
//              targets, wrong ones targets that make the validator reject, the rest stay plain.
//    gate      `KasusValidator` under the generated policy: any morph.*, trigger.prepositionCase,
//              trigger.wechselVerb, sentence.* or story.* error (too few gradable targets of the
//              unit's case, under half the level's length) rejects the whole story.
//
//  Contract B's labels are scored against the harvest: a label on a phrase whose case the form
//  proves is right or wrong; any other label is unverifiable.
//

import Foundation

// MARK: - Placements

/// What became of one planned phrase. Stable raw values: the Lab exports them.
nonisolated struct KasusPhrasePlacement: Codable, Hashable {
    nonisolated enum Status: String, Codable, CaseIterable, Hashable {
        /// Verbatim, with its verb in the same sentence: a target with the planned reason.
        case placed
        /// Verbatim, but no form of its verb in the sentence. Harvested like any other phrase.
        case triggerMissing
        /// Not verbatim, but its noun is in the text with other words („einen Hund“ for „den Hund“).
        case altered
        /// Its noun isn't in the text.
        case missing
        /// Verbatim with its verb, but an identical untargeted phrase earlier would shadow it.
        case shadowed
    }

    let phraseID: Int
    let expression: String
    let status: Status
    /// Placed: the verb form (or preposition) found. Altered: the words around the noun.
    let found: String?

    /// The expression stands in the text exactly as planned.
    var isVerbatim: Bool { status == .placed || status == .triggerMissing || status == .shadowed }
}

// MARK: - The result

/// One raw output, checked.
struct KasusCheckResult {
    let plan: KasusStoryPlan
    let raw: String
    let title: String?
    /// Nil when nothing usable came back (no paragraphs).
    let story: KasusStory?
    let report: KasusReport?
    /// One per planned phrase, in plan order. Empty for contract B.
    let placements: [KasusPhrasePlacement]
    /// Every article + noun phrase the plan didn't place, in reading order.
    let harvest: [KasusHarvestedPhrase]
    /// Contract B only.
    let labels: KasusLabelScore?

    /// The story may be played: it parsed, and the validator's generated policy lets it through.
    var passes: Bool { story != nil && report?.passes == true }

    /// The errors that reject the story, one code each, most frequent first.
    var rejectingCodes: [KasusIssueCode] {
        guard let report else { return [] }
        let codes = report.errors.map(\.code).filter { KasusValidator.Policy.rejectsGeneratedStory($0) }
        let counts = codes.reduce(into: [KasusIssueCode: Int]()) { $0[$1, default: 0] += 1 }
        return counts.keys.sorted { counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : $0.rawValue < $1.rawValue }
    }

    var gradableByCase: [GrammarCase: Int] { report?.gradableByCase ?? [:] }

    func placements(_ status: KasusPhrasePlacement.Status) -> Int {
        placements.filter { $0.status == status }.count
    }

    /// „PASS · 6/6 placed · 4 inferred · gradable Nom 3 · Akk 2 · Dat 7“ or
    /// „FAIL story.unitCaseCount, trigger.prepositionCase · 5/6 placed …“.
    var summaryLine: String {
        var parts: [String] = []
        if story == nil {
            parts.append("FAIL empty")
        } else {
            parts.append(passes ? "PASS" : "FAIL " + rejectingCodes.map(\.rawValue).joined(separator: ", "))
        }
        if !placements.isEmpty { parts.append("\(placements(.placed))/\(placements.count) placed") }
        let inferred = report?.located.filter { $0.spec.reason == .inferred && $0.gradable }.count ?? 0
        parts.append("\(inferred) inferred")
        parts.append("\(harvest.filter { $0.unverifiable != nil }.count) ungraded")
        let gradable = GrammarCase.allCases.compactMap { kasus in gradableByCase[kasus].map { "\(kasus.short) \($0)" } }
        parts.append("gradable " + (gradable.isEmpty ? "none" : gradable.joined(separator: " · ")))
        if let report { parts.append("\(report.wordCount) words") }
        if let labels { parts.append(labels.summaryLine) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The check

@MainActor
enum KasusStoryCheck {

    /// Checks one raw output against its plan. `storyID` names the story if it passes.
    static func run(raw: String, plan: KasusStoryPlan, storyID: String? = nil,
                    lexicon: (any KasusLexicon)? = nil,
                    learnerNouns: [String] = []) -> KasusCheckResult {
        let lexicon = lexicon ?? AppKasusLexicon()
        let text = KasusStoryText.parse(raw)
        let nouns = KasusNounIndex(extra: plan.phrases.map(\.lemma) + learnerNouns, lexicon: lexicon)
        guard !text.paragraphs.isEmpty else {
            let placements = plan.phrases.map {
                KasusPhrasePlacement(phraseID: $0.id, expression: $0.expression, status: .missing, found: nil)
            }
            return KasusCheckResult(plan: plan, raw: raw, title: text.title, story: nil, report: nil,
                                    placements: placements, harvest: [], labels: nil)
        }
        let scanned = text.paragraphs.map(KasusScannedParagraph.init)

        // 1. The planned phrases.
        var (placements, hits) = locate(plan: plan, in: scanned, lexicon: lexicon)

        // 2. Everything else.
        var excluding: [Int: [NSRange]] = [:]
        for hit in hits { excluding[hit.paragraphIndex, default: []].append(hit.range) }
        var harvest = KasusHarvest.harvest(paragraphs: text.paragraphs, excluding: excluding,
                                           nouns: nouns, lexicon: lexicon)

        // 3. Targets in reading order, keeping only those the validator's forward walk lands on.
        enum Source { case planned(Int), harvested(Int) }
        struct Entry { let paragraph: Int; let range: NSRange; let spec: KasusTargetSpec; let source: Source }
        var entries: [Entry] = hits.enumerated().map { index, hit in
            Entry(paragraph: hit.paragraphIndex, range: hit.range, spec: hit.spec, source: .planned(index))
        }
        for (index, phrase) in harvest.enumerated() {
            guard let spec = phrase.spec else { continue }
            entries.append(Entry(paragraph: phrase.paragraphIndex, range: phrase.range, spec: spec, source: .harvested(index)))
        }
        entries.sort { ($0.paragraph, $0.range.location) < ($1.paragraph, $1.range.location) }
        /// The entries the validator's forward walk lands on; the others are marked shadowed.
        func landing(_ entries: [Entry]) -> [Entry] {
            var kept: [Entry] = []
            var cursor = (paragraph: 0, index: text.paragraphs[0].startIndex)
            for entry in entries {
                if let landed = walk(entry.spec.phrase, in: text.paragraphs, from: cursor),
                   landed.paragraph == entry.paragraph, NSRange(landed.range, in: text.paragraphs[landed.paragraph]) == entry.range {
                    kept.append(entry)
                    cursor = (landed.paragraph, landed.range.upperBound)
                    continue
                }
                switch entry.source {
                case .planned(let index):
                    let hit = hits[index]
                    if let at = placements.firstIndex(where: { $0.phraseID == hit.phrase.id }) {
                        placements[at] = KasusPhrasePlacement(phraseID: hit.phrase.id, expression: hit.phrase.expression,
                                                              status: .shadowed, found: placements[at].found)
                    }
                case .harvested(let index):
                    harvest[index].verdict = .unverifiable(.shadowed)
                }
            }
            return kept
        }

        // 4. The story, validated. A wrong phrase the validator doesn't reject for is dropped:
        //    it must never end up graded under a label the form guessed. Dropping one moves the
        //    forward walk, so the landing check runs again, until nothing more is dropped (the
        //    list only shrinks, so it ends).
        let title = text.title?.isEmpty == false ? text.title! : plan.topic
        let id = storyID ?? KasusStoryPlan.newStoryID(unitRaw: plan.unitRaw, level: plan.level)
        var targets = landing(entries)
        var story = makeStory(id: id, plan: plan, title: title, paragraphs: text.paragraphs, targets: targets.map(\.spec))
        var report = KasusValidator.validate(story, source: .generated, lexicon: lexicon)
        while true {
            let unconfirmed = targets.indices.filter { i in
                guard case .harvested(let h) = targets[i].source, harvest[h].isWrong else { return false }
                return !report.targets[i].issues.contains {
                    $0.severity == .error && KasusValidator.Policy.rejectsGeneratedStory($0.code)
                }
            }
            guard !unconfirmed.isEmpty else { break }
            for i in unconfirmed {
                if case .harvested(let h) = targets[i].source { harvest[h].verdict = .unverifiable(.unconfirmed) }
            }
            let drop = Set(unconfirmed)
            targets = landing(targets.indices.filter { !drop.contains($0) }.map { targets[$0] })
            story = makeStory(id: id, plan: plan, title: title, paragraphs: text.paragraphs, targets: targets.map(\.spec))
            report = KasusValidator.validate(story, source: .generated, lexicon: lexicon)
        }

        let labels = plan.contract == .selfLabelled
            ? KasusSelfLabels.score(KasusSelfLabels.parse(text.labelBlock ?? ""), harvest: harvest) : nil
        return KasusCheckResult(plan: plan, raw: raw, title: title, story: story, report: report,
                                placements: placements, harvest: harvest, labels: labels)
    }

    static func makeStory(id: String, plan: KasusStoryPlan, title: String, paragraphs: [String],
                          targets: [KasusTargetSpec]) -> KasusStory {
        KasusStory(
            id: id,
            unitRaw: plan.unitRaw,
            level: plan.level,
            source: .generated,
            reviewed: .init(by: "", date: ""),
            title: title,
            titleEnglish: "",
            question: .init(de: "", en: "", options: [], answer: 0),
            paragraphs: paragraphs.map { .init(de: $0, en: "") },
            targets: targets,
            notTargets: []
        )
    }

    /// Where the validator's locate would land for `phrase`: the first match at or after `start`,
    /// moving on through later paragraphs (`KasusScanner.find`, the validator's own search).
    private static func walk(_ phrase: String, in texts: [String],
                             from start: (paragraph: Int, index: String.Index)) -> (paragraph: Int, range: Range<String.Index>)? {
        for p in start.paragraph..<texts.count {
            let from = p == start.paragraph ? start.index : texts[p].startIndex
            if let range = KasusScanner.find(phrase, in: texts[p], from: from) { return (p, range) }
        }
        return nil
    }

    // MARK: Locating the plan

    /// A planned phrase found verbatim with its trigger.
    struct PlannedHit {
        let phrase: KasusPlannedPhrase
        let paragraphIndex: Int
        /// UTF-16 range of the target (determiner + noun, without the preposition).
        let range: NSRange
        let spec: KasusTargetSpec
    }

    /// Each planned phrase: its first verbatim occurrence whose sentence has the verb (or whose
    /// expression carries the preposition), not overlapping another phrase's. A verb-frame phrase
    /// with a preposition right in front doesn't count there: the preposition decides its case.
    static func locate(plan: KasusStoryPlan, in paragraphs: [KasusScannedParagraph], lexicon: any KasusLexicon)
    -> (placements: [KasusPhrasePlacement], hits: [PlannedHit]) {
        var placements: [KasusPhrasePlacement] = []
        var hits: [PlannedHit] = []
        for phrase in plan.phrases {
            var verbatim = false
            var placed: PlannedHit?
            search: for (p, paragraph) in paragraphs.enumerated() {
                let text = paragraph.text
                for occurrence in KasusScanner.occurrences(of: phrase.expression, in: text) {
                    verbatim = true
                    let inside = paragraph.tokens.filter { occurrence.contains($0.range.lowerBound) }
                    let targetStart = phrase.preposition != nil && inside.count > 2 ? inside[1].range.lowerBound : occurrence.lowerBound
                    let range = NSRange(targetStart..<occurrence.upperBound, in: text)
                    if hits.contains(where: { $0.paragraphIndex == p && NSIntersectionRange($0.range, range).length > 0 }) { continue }
                    if phrase.preposition == nil, prepositionBefore(occurrence, in: paragraph, lexicon: lexicon) { continue }
                    guard let trigger = trigger(for: phrase, at: occurrence, in: paragraph) else { continue }
                    let spec = KasusTargetSpec(phrase: String(text[targetStart..<occurrence.upperBound]),
                                               kasus: phrase.kasus, genus: phrase.genus, lemma: phrase.lemma,
                                               reason: phrase.reason, trigger: trigger)
                    placed = PlannedHit(phrase: phrase, paragraphIndex: p, range: range, spec: spec)
                    break search
                }
            }
            if let placed {
                hits.append(placed)
                placements.append(.init(phraseID: phrase.id, expression: phrase.expression, status: .placed,
                                        found: placed.spec.trigger))
            } else if verbatim {
                placements.append(.init(phraseID: phrase.id, expression: phrase.expression, status: .triggerMissing, found: nil))
            } else if let found = aroundNoun(phrase, in: paragraphs) {
                placements.append(.init(phraseID: phrase.id, expression: phrase.expression, status: .altered, found: found))
            } else {
                placements.append(.init(phraseID: phrase.id, expression: phrase.expression, status: .missing, found: nil))
            }
        }
        return (placements, hits)
    }

    /// The target's trigger if the phrase counts here: the preposition of a preposition frame, or
    /// the preposition of a two-way frame whose sentence has a verb of the right kind, or the verb
    /// form as written. Nil when the sentence has no form of the verb.
    private static func trigger(for phrase: KasusPlannedPhrase, at occurrence: Range<String.Index>,
                                in paragraph: KasusScannedParagraph) -> String? {
        guard phrase.frame.needsVerb else { return phrase.preposition }
        let sentence = paragraph.sentence(containing: occurrence.lowerBound)
        let words = paragraph.tokens.filter { sentence.contains($0.range.lowerBound) && !occurrence.contains($0.range.lowerBound) }
        let lowered = Set(words.map { $0.text.lowercased() })
        for form in phrase.verbForms {
            let parts = form.split(separator: " ").map(String.init)
            guard let head = parts.first, parts.allSatisfy(lowered.contains) else { continue }
            if phrase.frame == .wechselWo || phrase.frame == .wechselWohin { return phrase.preposition }
            if parts.count > 1 { return form }
            return words.first { $0.text.lowercased() == head }?.text ?? head
        }
        return nil
    }

    /// A preposition (or a word that is one elsewhere: um, bis, ohne …) stands right in front.
    private static func prepositionBefore(_ occurrence: Range<String.Index>, in paragraph: KasusScannedParagraph,
                                          lexicon: any KasusLexicon) -> Bool {
        let tokens = paragraph.tokens
        guard let first = tokens.firstIndex(where: { $0.range.lowerBound == occurrence.lowerBound }), first > 0,
              paragraph.isWhitespaceGap(tokens[first - 1], tokens[first]) else { return false }
        let before = tokens[first - 1].text.lowercased()
        return lexicon.prepositionCases(before) != nil || KasusForms.softPrepositions.contains(before) || before == "entlang"
    }

    /// For an altered phrase: the planned noun (or its lemma) in the text with the word before it,
    /// „einen Hund“. Nil when the noun isn't there.
    private static func aroundNoun(_ phrase: KasusPlannedPhrase, in paragraphs: [KasusScannedParagraph]) -> String? {
        for paragraph in paragraphs {
            for (i, token) in paragraph.tokens.enumerated() where token.text == phrase.noun || token.text == phrase.lemma {
                guard i > 0, paragraph.isWhitespaceGap(paragraph.tokens[i - 1], token) else { return token.text }
                return "\(paragraph.tokens[i - 1].text) \(token.text)"
            }
        }
        return nil
    }
}

// MARK: - Parsing the output

@MainActor
enum KasusStoryText {

    struct Parsed {
        let title: String?
        let paragraphs: [String]
        /// Contract B: everything after the „FÄLLE:“ line.
        let labelBlock: String?
    }

    /// The label block's heading, however the model spells it.
    static func isLabelHeading(_ line: String) -> Bool {
        let upper = line.trimmingCharacters(in: .whitespaces).uppercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "*#_ "))
        return ["FÄLLE", "FAELLE", "FALLE"].contains { upper == $0 || upper.hasPrefix($0 + ":") }
    }

    static func parse(_ raw: String) -> Parsed {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var storyLines: [String] = []
        var labelLines: [String]?
        var listLines = 0
        for rawLine in normalized.components(separatedBy: "\n") {
            if labelLines == nil, listMarker(in: rawLine.trimmingCharacters(in: .whitespaces)) != nil { listLines += 1 }
            let line = clean(rawLine)
            if labelLines != nil {
                labelLines?.append(line)
            } else if isLabelHeading(line) {
                let rest = line.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                labelLines = rest.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [rest]
            } else {
                storyLines.append(line)
            }
        }
        let parsed = StoryStudyService.parseStory(storyLines.joined(separator: "\n"))
        var paragraphs = parsed.text.components(separatedBy: "\n")
            .map(clean)
            .filter { !$0.isEmpty && !isMetaLine($0) && !isMarkerLine($0) }
        // A story written as a numbered list, one sentence per line, reads as paragraphs of four.
        if listLines >= 3 {
            paragraphs = stride(from: 0, to: paragraphs.count, by: 4).map {
                paragraphs[$0..<min($0 + 4, paragraphs.count)].joined(separator: " ")
            }
        }
        return Parsed(title: parsed.title.map(clean), paragraphs: paragraphs,
                      labelBlock: labelLines?.joined(separator: "\n"))
    }

    /// Markdown the model sometimes adds (bold phrases, headings) comes off, so a phrase reads as
    /// the words it is: „mit **dem Hund**“ would hide the preposition from the validator. So does
    /// a list marker („1. “, „2) “, „- “, „• “): the numbers would count as words and show next to
    /// Markieren's own sentence numbers.
    static func clean(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if let marker = listMarker(in: text) { text.removeSubrange(marker) }
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "*", with: "")
        text = text.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("#") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return text
    }

    /// „1. “, „12) “, „- “, „• “ at the start of a trimmed line. Markdown bold („**Titel**“) is not
    /// a bullet.
    static func listMarker(in line: String) -> Range<String.Index>? {
        if let numbered = line.range(of: #"^\d{1,2}[.)]\s+"#, options: .regularExpression) { return numbered }
        return line.range(of: #"^[-•–]\s+"#, options: .regularExpression)
    }

    /// A stray „TITEL:“ or „GESCHICHTE:“ that ended up in the body.
    private static func isMarkerLine(_ line: String) -> Bool {
        let upper = line.uppercased()
        return upper.hasPrefix("TITEL:") || upper == "GESCHICHTE:" || upper == "GESCHICHTE"
    }

    /// „(95 Wörter)“, „Wörter: 95“: a count the model adds after the story.
    private static func isMetaLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return (lower.contains("wörter") || lower.contains("words")) && lower.count < 24
            && lower.contains(where: \.isNumber)
    }
}

// MARK: - Contract B: the tutor's own labels

/// One line of a „FÄLLE:“ block.
nonisolated struct KasusCaseLabel: Codable, Hashable {
    let phrase: String
    /// A `GrammarCase` raw value; nil when the line's case couldn't be read.
    let caseRaw: String?
    let line: String

    var kasus: GrammarCase? { caseRaw.flatMap(GrammarCase.init(rawValue:)) }
}

/// Contract B's score: the tutor's labels against the cases the form proves.
nonisolated struct KasusLabelScore: Codable, Hashable {
    /// Lines with a phrase and a readable case.
    var labels = 0
    /// Lines whose case couldn't be read.
    var unparseable = 0
    /// Labelled phrases that aren't in the story.
    var notInStory = 0
    /// Labels matched only by their noun: the tutor wrote the phrase in another form than the
    /// text has, usually the dictionary form („der Schrank“ for „den Schrank“). Scored like any
    /// other match, and counted here too.
    var byNoun = 0
    /// Labels on phrases whose case the form proves.
    var correct = 0
    var wrong = 0
    /// Labels on phrases the app can't prove either way.
    var unverifiable = 0
    /// Proven phrases in the story the tutor didn't label.
    var unlabelledProven = 0
    /// „den Ball: Dat, form says Akk“, for the Lab's detail.
    var mismatches: [String] = []

    /// Right share of the labels that could be checked. Nil when none could.
    var accuracy: Double? { correct + wrong == 0 ? nil : Double(correct) / Double(correct + wrong) }
    /// Share of the labels found in the story that the app can't check.
    var unverifiableShare: Double? {
        let matched = correct + wrong + unverifiable
        return matched == 0 ? nil : Double(unverifiable) / Double(matched)
    }

    var summaryLine: String {
        let accuracy = accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        let share = unverifiableShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        return "labels \(correct)/\(correct + wrong) right (\(accuracy)) · \(share) unverifiable · \(byNoun) by noun · \(notInStory) not in story"
    }
}

@MainActor
enum KasusSelfLabels {

    /// The line the prompt asks for after the story.
    static let heading = "FÄLLE:"

    /// „den Ball | Akk“, and the ways a model bends it: a bullet or number in front, „:“ or „–“
    /// instead of „|“, the case spelled out.
    static func parse(_ block: String) -> [KasusCaseLabel] {
        block.components(separatedBy: "\n").compactMap { rawLine -> KasusCaseLabel? in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            while let first = line.first, "-•*·".contains(first) { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if let match = line.range(of: #"^\d+[.)]\s*"#, options: .regularExpression) { line.removeSubrange(match) }
            let separators = ["|", " – ", " — ", " - ", "→", "=", ":"]
            guard let separator = separators.first(where: line.contains),
                  let at = line.range(of: separator, options: .backwards) else {
                return KasusCaseLabel(phrase: line, caseRaw: nil, line: rawLine)
            }
            let phrase = line[..<at.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " „“\"'»«"))
            let caseText = line[at.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !phrase.isEmpty else { return nil }
            return KasusCaseLabel(phrase: phrase, caseRaw: caseName(caseText)?.rawValue, line: rawLine)
        }
    }

    /// „Akk“, „Akkusativ“, „accusative“, „A“ → .akkusativ.
    static func caseName(_ text: String) -> GrammarCase? {
        let word = text.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
        guard !word.isEmpty else { return nil }
        if word.hasPrefix("nom") || word == "n" { return .nominativ }
        if word.hasPrefix("akk") || word.hasPrefix("acc") || word == "a" { return .akkusativ }
        if word.hasPrefix("dat") || word == "d" { return .dativ }
        if word.hasPrefix("gen") || word == "g" { return .genitiv }
        return nil
    }

    /// Each label matched to a harvested phrase in reading order (a phrase once), exactly or with a
    /// preposition in front of it („mit dem Hund“ for „dem Hund“); failing that, by its noun
    /// („der Schrank“ for „den Schrank“, counted in `byNoun`).
    static func score(_ labels: [KasusCaseLabel], harvest: [KasusHarvestedPhrase]) -> KasusLabelScore {
        var score = KasusLabelScore()
        var used = Set<Int>()
        func normalized(_ text: String) -> String {
            text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        for label in labels {
            guard let kasus = label.kasus else { score.unparseable += 1; continue }
            score.labels += 1
            let wanted = normalized(label.phrase)
            var match = harvest.indices.first { i in
                guard !used.contains(i) else { return false }
                let surface = normalized(harvest[i].surface)
                return wanted == surface || wanted.hasSuffix(" " + surface)
            }
            if match == nil, let noun = wanted.split(separator: " ").last.map(String.init), wanted.contains(" ") {
                match = harvest.indices.first { i in
                    guard !used.contains(i) else { return false }
                    let phrase = harvest[i]
                    return phrase.noun.lowercased() == noun || phrase.lemma?.lowercased() == noun
                }
                if match != nil { score.byNoun += 1 }
            }
            guard let match else { score.notInStory += 1; continue }
            used.insert(match)
            let phrase = harvest[match]
            if phrase.isProven, let proven = phrase.kasus {
                if proven == kasus {
                    score.correct += 1
                } else {
                    score.wrong += 1
                    score.mismatches.append("\(phrase.surface): \(kasus.short), form says \(proven.short)")
                }
            } else {
                score.unverifiable += 1
            }
        }
        score.unlabelledProven = harvest.indices.filter { !used.contains($0) && harvest[$0].isProven }.count
        return score
    }
}
