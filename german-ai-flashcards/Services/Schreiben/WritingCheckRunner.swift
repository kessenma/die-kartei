//
//  WritingCheckRunner.swift
//  german-ai-flashcards
//
//  Runs one check of one entry: prepares the tutor (the Kasus writer's refuse-then-load), splits
//  the text, skips sentences that are not German in a Tagebuch entry, asks in batches of six,
//  reads the replies through the gates, asks for the one-line comment, scores an essay, and
//  writes the result onto the entry.
//
//  Memory: one heavy resident, so nothing here loads anything but the tutor; batches are small
//  and `maxTokens` is capped per call; and every call runs under a timeout, because
//  `generateText` has no stall watchdog of its own and a stalled run would pin
//  `activeGenerations` and block eviction.
//
//  `WritingTutor` is the seam the simulator uses: `WritingCannedTutor` answers from fixtures so
//  the whole flow (status, results, apply, hand-off) can be driven where MLX cannot run.
//

import Foundation
import SwiftData

// MARK: - The tutor seam

@MainActor
protocol WritingTutor: AnyObject {
    var modelID: String { get }
    /// Nil when ready; else why not, in the learner's words.
    func prepare() async -> String?
    func reply(system: String, user: String, maxTokens: Int) async throws -> String
}

struct WritingTutorTimeout: Error {}

/// Which downloaded tutor the Schreiben room asks: the learner's document tutor when it is a
/// German tutor on this device, else the best German tutor on it. Never Apple Intelligence, which
/// corrects German it shouldn't (docs/WORKSHEETS.md), so it is not even offered.
@MainActor
enum WritingTutorPick {
    static var options: [MLXModel] { DocumentTutorChoice.downloaded.filter { $0 != .appleIntelligence } }

    static func current(_ modelManager: MLXModelManager) -> MLXModel? {
        let picked = DocumentTutorChoice.current(modelManager)
        if picked != .appleIntelligence, options.contains(picked) { return picked }
        return options.first
    }

    /// The tutor to run with: the canned one in DEBUG when asked for, else the MLX pick, else nil.
    static func tutor(_ modelManager: MLXModelManager, service: MLXGenerationService) -> WritingTutor? {
        #if DEBUG
        if WritingCannedTutor.isRequested { return WritingCannedTutor() }
        #endif
        return current(modelManager).map { WritingMLXTutor(service: service, model: $0) }
    }

    static func isAvailable(_ modelManager: MLXModelManager) -> Bool {
        #if DEBUG
        if WritingCannedTutor.isRequested { return true }
        #endif
        return current(modelManager) != nil
    }
}

@MainActor
final class WritingMLXTutor: WritingTutor {
    let service: MLXGenerationService
    let model: MLXModel
    /// Seconds one tutor call may take before it is cancelled.
    var timeout: Double = 90

    init(service: MLXGenerationService, model: MLXModel) {
        self.service = service
        self.model = model
    }

    var modelID: String { model.rawValue }

    func prepare() async -> String? {
        if model == .appleIntelligence {
            return "Apple Intelligence doesn't check German reliably. Pick a downloaded tutor."
        }
        if BatchQueueService.shared.isRunning {
            return "The queue is using the tutor right now. Try again once it finishes."
        }
        if service.isGenerating { return "The tutor is still answering. Try again in a moment." }
        if service.isModelLoaded && service.currentModel == model { return nil }
        await service.loadModel(model)
        if service.isModelLoaded && service.currentModel == model { return nil }
        return service.loadError ?? "Couldn't load \(model.rawValue)."
    }

    func reply(system: String, user: String, maxTokens: Int) async throws -> String {
        let service = service, model = model
        let work = Task { @MainActor in
            try await service.generateText(system: system, user: user, model: model, maxTokens: maxTokens)
        }
        let seconds = timeout
        let watchdog = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work.cancel()
        }
        defer { watchdog.cancel() }
        do {
            let text = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            return ConversationPrompts.stripThinkBlocks(text)
        } catch is CancellationError where watchdog.isCancelled == false {
            throw WritingTutorTimeout()
        }
    }
}

#if DEBUG
/// Fixture answers for the simulator. Marks every third German sentence as a one-word fix
/// (the first word's last letter swapped), the sixth as unsure, the rest right.
@MainActor
final class WritingCannedTutor: WritingTutor {
    var modelID: String { "debug/canned" }
    static let launchKey = "schreiben.debugCanned"
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: launchKey) }

    func prepare() async -> String? { nil }

    func reply(system: String, user: String, maxTokens: Int) async throws -> String {
        try? await Task.sleep(for: .milliseconds(300))
        if system.hasPrefix(WritingTutorCheck.commentSystem.prefix(30)) {
            return "Clear and well ordered; keep an eye on the Dativ after mit and bei."
        }
        if user.contains("STRUGGLE:") {
            return "STRUGGLE: mixing up dem and den after mit ; dativ\nSTRUGGLE: remembering noun genders ; artikel"
        }
        var out: [String] = []
        for line in user.components(separatedBy: .newlines) {
            guard let dot = line.firstIndex(of: "."), let n = Int(line[line.startIndex..<dot]) else { continue }
            let sentence = line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
            switch n % 3 {
            case 0:
                out.append("\(n): unsicher ; - ; not sure about this one ; -")
            case 2:
                var words = sentence.split(separator: " ").map(String.init)
                if words.count >= 3, words[2].count > 2 {
                    words[2] = String(words[2].dropLast()) + (words[2].hasSuffix("e") ? "en" : "e")
                }
                out.append("\(n): falsch ; \(words.joined(separator: " ")) ; ending after the preposition ; dativ")
            default:
                out.append("\(n): richtig ; - ; - ; -")
            }
        }
        return out.joined(separator: "\n")
    }
}
#endif

// MARK: - The runner

@MainActor
@Observable
final class WritingCheckRunner {

    enum Phase: Equatable {
        case idle
        case preparing
        case checking(done: Int, total: Int)
        case commenting
        case finished
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .preparing, .checking, .commenting: true
            default: false
            }
        }
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    /// Where the status line reads from.
    var statusText: String? {
        switch phase {
        case .idle: nil
        case .preparing: "Loading the tutor…"
        case .checking(let done, let total): "Checking sentences \(min(done + 1, total)) of \(total)…"
        case .commenting: "Asking for a comment…"
        case .finished: nil
        case .failed(let why): why
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase.isRunning { phase = .idle }
    }

    /// Check `entry` with `tutor` and write the result onto it. Returns when done or failed.
    func run(entry: JournalEntry, tutor: WritingTutor, in context: ModelContext) async {
        guard !phase.isRunning else { return }
        let text = entry.text
        let all = WritingSentences.split(text)
        guard !all.isEmpty else {
            phase = .failed("Nothing to check yet.")
            return
        }
        phase = .preparing
        if let why = await tutor.prepare() {
            phase = .failed(why)
            return
        }
        let memoryHint = LearnerMemoryService.correctionHint(in: context)
        let system = WritingTutorCheck.system(level: entry.level, focus: entry.promptFocus, memoryHint: memoryHint)
        let promptContext = [entry.promptDE ?? ""].filter { !$0.isEmpty }

        // Which sentences go to the tutor: in a Tagebuch entry, the German ones.
        var results: [WritingSentenceCheck] = []
        var toCheck: [(index: Int, text: String)] = []
        for (i, sentence) in all.enumerated() {
            if entry.kind == .tagebuch, WritingSentences.guessLanguage(sentence) == .english {
                results.append(WritingSentenceCheck(index: i, original: sentence, outcome: .skipped))
            } else {
                toCheck.append((i, sentence))
            }
        }
        var limit: Int?
        if toCheck.count > WritingTutorCheck.maxSentencesPerRun {
            limit = WritingTutorCheck.maxSentencesPerRun
            toCheck = Array(toCheck.prefix(WritingTutorCheck.maxSentencesPerRun))
        }

        var done = 0
        for batchStart in stride(from: 0, to: toCheck.count, by: WritingTutorCheck.batchSize) {
            if Task.isCancelled { phase = .idle; return }
            let batch = Array(toCheck[batchStart..<min(batchStart + WritingTutorCheck.batchSize, toCheck.count)])
            phase = .checking(done: done, total: toCheck.count)
            let sentences = batch.map(\.text)
            let reply: String
            do {
                reply = try await tutor.reply(system: system, user: WritingTutorCheck.prompt(sentences: sentences),
                                              maxTokens: WritingTutorCheck.maxTokens(sentences: sentences.count))
            } catch is WritingTutorTimeout {
                reply = ""   // every sentence in the batch reads as "the tutor didn't answer"
            } catch is CancellationError {
                phase = .idle
                return
            } catch {
                phase = .failed("The tutor stopped: \(error.localizedDescription)")
                return
            }
            let parsed = WritingTutorCheck.parse(reply, sentences: sentences, startIndex: 0, context: promptContext)
            for (offset, var check) in parsed.enumerated() {
                check.index = batch[offset].index
                results.append(check)
            }
            done += batch.count
        }
        results.sort { $0.index < $1.index }

        // The comment, only when something was judged.
        var comment: String?
        var fallback = false
        if results.contains(where: { $0.outcome == .ok || $0.outcome == .fix }) {
            phase = .commenting
            let reply = try? await tutor.reply(system: WritingTutorCheck.commentSystem,
                                               user: WritingTutorCheck.commentPrompt(text: text, check: results),
                                               maxTokens: WritingTutorCheck.commentMaxTokens)
            comment = reply.flatMap(WritingTutorCheck.parseComment)
            if comment == nil {
                comment = WritingTutorCheck.fallbackComment(results)
                fallback = true
            }
        }

        var score: WritingScore?
        if entry.kind == .aufsatz {
            score = WritingScore(
                ok: results.filter { $0.outcome == .ok }.count,
                fix: results.filter { $0.outcome == .fix }.count,
                unsure: results.filter { $0.outcome == .unsure }.count,
                skipped: results.filter { $0.outcome == .skipped }.count,
                words: WritingSentences.wordCount(text),
                targetMin: entry.targetMin, targetMax: entry.targetMax
            )
        }

        // The entry may have been edited while the tutor worked: the hash records the text that
        // was checked, so the row shows "edited since" rather than claiming the new text passed.
        let now = Date()
        entry.check = WritingCheck(sentences: results, comment: comment, commentIsFallback: fallback,
                                   score: score, modelID: tutor.modelID, checkedAt: now,
                                   checkedSentenceLimit: limit)
        entry.checkedAt = now
        entry.checkedModelID = tutor.modelID
        entry.checkedTextHash = WritingCheck.hash(of: text)
        entry.touch()
        try? context.save()
        phase = .finished
    }

    /// Replace the sentence in the entry's text with its correction and keep the check current.
    static func apply(_ sentence: WritingSentenceCheck, to entry: JournalEntry, in context: ModelContext) {
        guard sentence.outcome == .fix, let corrected = sentence.corrected, var check = entry.check,
              let row = check.sentences.firstIndex(where: { $0.index == sentence.index }),
              let range = entry.text.range(of: sentence.original) else { return }
        entry.text.replaceSubrange(range, with: corrected)
        check.sentences[row].applied = true
        entry.check = check
        entry.checkedTextHash = WritingCheck.hash(of: entry.text)
        entry.touch()
        try? context.save()
    }
}
