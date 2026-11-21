//
//  HoerenScoringService.swift
//  german-ai-flashcards
//
//  Saves a finished Hören round, credits the day (`StudyDay.hoerenItems`, XP through
//  `ExperienceService`), and hands Diktat misses to the coach memory.
//
//  What reaches the profile is deliberately small. A dictation miss is listening evidence, and an
//  unstressed -en or -em is close to inaudible in a synthetic voice, so nothing here moves
//  `profile.grammar` (`applyDrillResult` would turn an estimate into earned pyramid fill). Ending
//  misses go in as tagged slips (`MemorySource.diktat`, at most two a round, so the 20-slip LRU
//  keeps the learner's own conversation slips) and headword misses as vocabulary touches.
//

import Foundation
import SwiftData

@MainActor
enum HoerenScoringService {

    static let maxSlipsPerRound = 2
    static let maxVocabPerRound = 3

    /// Inserts the round and credits the day. Items count right or wrong.
    static func save(_ round: HoerenRound, in context: ModelContext) {
        context.insert(round)
        StudyLogService.record(.hoeren(max(1, round.askedCount)), seconds: round.durationSeconds, in: context)
        if round.kind == .diktat { noteDiktat(round.items, in: context) }
        try? context.save()
    }

    /// Ending misses as cloze-ready slips, tagged with their grammar point; missed headwords as
    /// vocabulary the coach can work in.
    static func noteDiktat(_ items: [HoerenItem], in context: ModelContext) {
        var slips: [LexicalSlip] = []
        var vocab: [(german: String, english: String)] = []
        for item in items {
            guard let result = item.diktat else { continue }
            let referenceTokens = result.tokens.filter { $0.reference != nil }
            for (index, token) in referenceTokens.enumerated() where token.cls == .ending {
                guard slips.count < maxSlipsPerRound, let focus = token.focus,
                      let right = token.reference, let wrong = token.typed else { continue }
                slips.append(LexicalSlip(
                    wrong: wrong, right: right,
                    note: "Diktat · Endung (\(focus.germanLabel))",
                    lastSeen: .now, timesSeen: 1,
                    sentence: item.expected, blankIndex: index,
                    source: MemorySource.diktat
                ))
            }
            if vocab.count < maxVocabPerRound, let head = item.headword,
               let missed = headwordMissed(head, in: result) {
                vocab.append((german: missed, english: item.headwordEnglish ?? ""))
            }
        }
        if !slips.isEmpty { LearnerMemoryService.noteSlips(slips, in: context) }
        if !vocab.isEmpty { LearnerMemoryService.noteVocabEncounters(vocab, source: MemorySource.diktat, in: context) }
    }

    /// The headword ("der Bahnhof", "abfahren"), when the sentence's matching word was missed.
    private static func headwordMissed(_ headword: String, in result: DiktatResult) -> String? {
        let bare = headword.split(separator: " ").last.map(String.init) ?? headword
        let stem = DiktatScorer.foldKey(bare).prefix(max(3, bare.count - 2))
        let hit = result.tokens.contains { token in
            guard let ref = token.reference, !token.cls.countsRight, token.cls != .extra else { return false }
            return DiktatScorer.foldKey(ref).hasPrefix(stem)
        }
        return hit ? headword : nil
    }
}

/// Numbers for the stats screen, computed from the stored rounds.
@MainActor
struct HoerenStats {
    struct KindLine: Identifiable {
        let kind: HoerenNumberKind
        let asked: Int
        let right: Int
        let firstPass: Int
        var id: String { kind.rawValue }
    }

    struct ConfusionPair: Identifiable, Hashable {
        let expected: String
        let typed: String
        let confusion: HoerenConfusion
        let count: Int
        var id: String { expected + "→" + typed }
    }

    var kinds: [KindLine] = []
    var bareRight = 0, bareAsked = 0
    var carrierRight = 0, carrierAsked = 0
    var confusions: [HoerenConfusion: Int] = [:]
    var pairs: [ConfusionPair] = []
    var diktatWords = 0, diktatRight = 0
    var diktatMisses: [DiktatClass: Int] = [:]
    var endingByFocus: [GrammarFocus: Int] = [:]
    var gistRounds = 0
    var predictionsMade = 0, predictionsHit = 0
    /// Per level: numbers right / asked, and Diktat words right / words (the listening profile).
    var numbersByLevel: [String: (right: Int, asked: Int)] = [:]
    var wordsByLevel: [String: (right: Int, total: Int)] = [:]
    /// Hör-Checks, newest first: the day and each part's share right.
    var checks: [(date: Date, numbers: Double?, words: Double?)] = []

    init(rounds: [HoerenRound]) {
        var byKind: [HoerenNumberKind: (asked: Int, right: Int, first: Int)] = [:]
        var pairCounts: [String: (String, String, HoerenConfusion, Int)] = [:]
        var checkDays: [Date: (n: (Int, Int), w: (Int, Int))] = [:]
        for round in rounds {
            let isCheck = round.sourceRaw.hasPrefix(HoerenCheck.tag + ":")
            let day = Calendar.current.startOfDay(for: round.date)
            switch round.kind {
            case .zahlen:
                var line = numbersByLevel[round.levelRaw] ?? (0, 0)
                line.right += round.correctCount
                line.asked += round.askedCount
                numbersByLevel[round.levelRaw] = line
                if isCheck { checkDays[day, default: ((0, 0), (0, 0))].n.0 += round.correctCount; checkDays[day, default: ((0, 0), (0, 0))].n.1 += round.askedCount }
            case .diktat:
                let results = round.items.compactMap(\.diktat)
                let right = results.reduce(0) { $0 + $1.rightCount }, total = results.reduce(0) { $0 + $1.referenceCount }
                var line = wordsByLevel[round.levelRaw] ?? (0, 0)
                line.right += right
                line.total += total
                wordsByLevel[round.levelRaw] = line
                if isCheck { checkDays[day, default: ((0, 0), (0, 0))].w.0 += right; checkDays[day, default: ((0, 0), (0, 0))].w.1 += total }
            default: break
            }
            switch round.kind {
            case .zahlen:
                let carrier = round.modeRaw == HoerenNumberMode.carrier.rawValue
                for item in round.items {
                    guard let kind = item.numberKind else { continue }
                    var line = byKind[kind] ?? (0, 0, 0)
                    line.asked += 1
                    if item.correct { line.right += 1 }
                    if item.firstPass { line.first += 1 }
                    byKind[kind] = line
                    if carrier { carrierAsked += 1; if item.correct { carrierRight += 1 } }
                    else { bareAsked += 1; if item.correct { bareRight += 1 } }
                    if !item.correct, let c = item.confusion {
                        confusions[c, default: 0] += 1
                        if c != .other {
                            let key = item.expected + "→" + item.typed
                            let prev = pairCounts[key]?.3 ?? 0
                            pairCounts[key] = (item.expected, item.typed, c, prev + 1)
                        }
                    }
                }
            case .diktat:
                for result in round.items.compactMap(\.diktat) {
                    diktatWords += result.referenceCount
                    diktatRight += result.rightCount
                    for token in result.tokens where token.reference != nil && token.cls != .right {
                        diktatMisses[token.cls, default: 0] += 1
                        if token.cls == .ending, let f = token.focus { endingByFocus[f, default: 0] += 1 }
                    }
                }
            case .gist:
                gistRounds += 1
                for item in round.items {
                    predictionsMade += item.predictions?.count ?? 0
                    predictionsHit += item.predictionHits?.count ?? 0
                }
            case nil:
                break
            }
        }
        checks = checkDays.sorted { $0.key > $1.key }.map { day, v in
            (date: day,
             numbers: v.n.1 > 0 ? Double(v.n.0) / Double(v.n.1) : nil,
             words: v.w.1 > 0 ? Double(v.w.0) / Double(v.w.1) : nil)
        }
        kinds = HoerenNumberKind.allCases.compactMap { k in
            byKind[k].map { KindLine(kind: k, asked: $0.asked, right: $0.right, firstPass: $0.first) }
        }
        pairs = pairCounts.values
            .map { ConfusionPair(expected: $0.0, typed: $0.1, confusion: $0.2, count: $0.3) }
            .sorted { $0.count > $1.count }
            .prefix(8).map { $0 }
    }

    var isEmpty: Bool { kinds.isEmpty && diktatWords == 0 && gistRounds == 0 }

    /// A count kept in halves (teilweise = ½) as text: 5 → "2½".
    nonisolated static func halfString(_ halves: Int) -> String {
        let whole = halves / 2
        return halves % 2 == 0 ? "\(whole)" : (whole == 0 ? "½" : "\(whole)½")
    }
}
