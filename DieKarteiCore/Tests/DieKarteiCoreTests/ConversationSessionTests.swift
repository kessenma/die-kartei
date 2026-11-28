import Foundation
import Testing
@testable import DieKarteiCore

/// The conversation flow, on a scripted model: what the session asks the tutor, in what order,
/// and what it does with the answers. No model, no device; the same session runs on iOS
/// (SwiftData host) and Android (in-memory host).
@MainActor
struct ConversationSessionTests {

    /// A tutor that answers from a script and records every call.
    final class ScriptedTutor: TutorGenerating {
        var readyModel: MLXModel?
        var loadFailure: String?
        var loads: [MLXModel] = []
        var completions: [(system: String, user: String, maxTokens: Int)] = []
        var replies: [(history: [(role: ChatRole, content: String)], system: String)] = []
        /// Answers `complete` by the kind of prompt it was sent.
        var answer: (_ system: String, _ user: String) -> String = { _, _ in "OK" }
        var replyScript = ["Guten Tag! Wie geht es dir?", "Schön. Und was machst du heute?", "Toll!"]

        init(loaded: MLXModel? = .gemma4_E2B_german) { readyModel = loaded }

        func wasEvicted(_ model: MLXModel) -> Bool { false }
        func loadTutor(_ model: MLXModel) async { loads.append(model); readyModel = model }
        func complete(system: String, user: String, model: MLXModel, maxTokens: Int) async throws -> String {
            completions.append((system, user, maxTokens))
            return answer(system, user)
        }
        func streamReply(history: [(role: ChatRole, content: String)], system: String, model: MLXModel,
                         maxTokens: Int, temperature: Float, onPartial: @escaping (String) -> Void) async throws -> String {
            replies.append((history, system))
            let text = replyScript.isEmpty ? "…" : replyScript.removeFirst()
            onPartial(text)
            return text
        }
    }

    let config: ConversationConfig = {
        var c = ConversationConfig(model: .gemma4_E2B_german)
        c.inputMode = .type
        return c
    }()

    func makeSession(_ tutor: ScriptedTutor, config: ConversationConfig? = nil,
                     host: MemoryConversationHost? = nil) -> ConversationSession<MemoryConversationHost> {
        ConversationSession(host: host ?? MemoryConversationHost(), config: config ?? self.config, tutor: tutor,
                            speechInput: NoSpeechInput(reason: "test"), speechOutput: SilentSpeechOutput())
    }

    /// The session's work runs in its own tasks; wait for it to settle.
    func settle(_ session: ConversationSession<MemoryConversationHost>, until done: () -> Bool) async {
        for _ in 0..<500 {
            if done(), session.phase == .idle { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("session never settled (phase \(session.phase))")
    }

    @Test func opensThenCorrectsThenReplies() async {
        let tutor = ScriptedTutor()
        tutor.answer = { system, _ in
            system.contains("FIX:") ? "FIX: Ich warte auf den Bus.\nWHY: 'warten' takes 'auf'." : "OK"
        }
        let session = makeSession(tutor)
        session.onAppear()
        await settle(session) { session.conversation.messages.count == 1 }
        #expect(session.conversation.messages.first?.role == .assistant)
        // The opener went in as one user turn: the opener seed, never shown.
        #expect(tutor.replies.first?.history.count == 1)

        #expect(session.submitTyped("Ich warte für den Bus."))
        await settle(session) { session.conversation.messages.count == 3 }

        let turn = session.conversation.sortedMessages[1]
        #expect(turn.isUser && turn.correctedText == "Ich warte auf den Bus.")
        #expect(turn.correctionNote == "'warten' takes 'auf'.")
        // The correction pass saw the tutor's line it answers, then the reply saw the whole chat.
        let correction = tutor.completions.first { $0.system.contains("FIX:") }
        #expect(correction?.user.contains("Guten Tag!") == true)
        #expect(correction?.maxTokens == TutorBudget.correction)
        let history = tutor.replies.last?.history ?? []
        #expect(history.map(\.role) == [.assistant, .user])
        #expect(history.last?.content == "Ich warte für den Bus.")
    }

    @Test func cleanTurnCountsAsSuccess() async {
        let tutor = ScriptedTutor()
        let session = makeSession(tutor)
        session.onAppear()
        await settle(session) { session.conversation.messages.count == 1 }
        session.submitTyped("Mir geht es gut.")
        await settle(session) { session.conversation.messages.count == 3 }
        #expect(session.conversation.sortedMessages[1].confirmedClean)
        #expect(session.successTurnCount == 1)
    }

    @Test func nudgeHoldsTheReplyUntilTheLearnerRepairs() async {
        let tutor = ScriptedTutor()
        tutor.answer = { system, _ in
            system.contains("FIX:")
                ? "FIX: Ich wohne seit zwei Jahren in Berlin.\nWHY: 'seit' takes dative.\nHINT: Welcher Fall kommt nach 'seit'?"
                : "OK"
        }
        var config = self.config
        config.feedbackStyle = .nudgeMe
        let session = makeSession(tutor, config: config)
        session.onAppear()
        await settle(session) { session.conversation.messages.count == 1 }

        session.submitTyped("Ich wohne seit zwei Jahre in Berlin.")
        await settle(session) { session.repairPrompt != nil }
        #expect(session.conversation.messages.count == 2)     // no reply yet
        #expect(session.repairPrompt?.hint == "Welcher Fall kommt nach 'seit'?")

        session.submitTyped("Ich wohne seit zwei Jahren in Berlin.")
        await settle(session) { session.conversation.messages.count == 3 }
        #expect(session.repairPrompt == nil)
        #expect(session.conversation.sortedMessages[1].selfCorrected)
    }

    @Test func unloadedModelAsksBeforeLoading() async {
        let tutor = ScriptedTutor(loaded: nil)
        let session = makeSession(tutor)
        #expect(!session.submitTyped("Hallo"))
        #expect(session.showModelLoadPrompt)
        #expect(tutor.loads.isEmpty)
        session.confirmModelLoad()
        await settle(session) { tutor.readyModel != nil }
        #expect(tutor.loads == [.gemma4_E2B_german])
    }

    @Test func summaryCountsTheSessionAndRecordsTheStreak() async {
        let tutor = ScriptedTutor()
        tutor.answer = { system, _ in
            if system.contains("STRENGTHS:") {
                return "STRENGTHS:\n- Clear answers\nIMPROVE:\n- Dative after 'seit'\nPATTERN: Verb position is solid."
            }
            return "OK"
        }
        let host = MemoryConversationHost(bestUnaidedStreak: 1)
        var summarized: [String]?
        host.onSummary = { _, _, words in summarized = words }
        let session = makeSession(tutor, host: host)
        session.onAppear()
        await settle(session) { session.conversation.messages.count == 1 }
        session.submitTyped("Mir geht es gut.")
        await settle(session) { session.conversation.messages.count == 3 }
        session.submitTyped("Ich gehe heute ins Kino.")
        await settle(session) { session.conversation.messages.count == 5 }

        let summary = await session.endAndSummarize()
        #expect(summary?.strengths == ["Clear answers"])
        #expect(summary?.improvements == ["Dative after 'seit'"])
        #expect(summary?.turnCount == 2)
        #expect(summary?.bestUnaidedStreak == 2 && summary?.unaidedStreakIsRecord == true)
        #expect(host.bestUnaidedStreak == 2)
        #expect(summarized != nil)
        #expect(session.conversation.summary?.patternNote == "Verb position is solid.")
    }

    @Test func phraseMatchIgnoresCaseAndPunctuation() {
        #expect(PhraseMatch.similarity("Ich heiße Kyle.", "ich heisse kyle") == 1)
        #expect(PhraseMatch.closeEnough(original: "Ich wohne in Berlin seit zwei Jahre.",
                                        corrected: "Ich wohne seit zwei Jahren in Berlin.") == false)
    }
}
