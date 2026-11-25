//
//  StammtischBar.swift
//  german-ai-flashcards
//
//  Above the input in a Stammtisch chat (roadmap item 8): one-tap listener replies (Ach so, Genau,
//  Echt?), and with the reply timer on, a countdown that starts when the tutor stops speaking.
//  When it runs out with no answer started, the tutor moves on (`ConversationEngine.tutorMovesOn`).
//

import SwiftUI

struct StammtischBar: View {
    let engine: ConversationEngine
    let options: StammtischOptions
    /// True while the learner is typing a turn: the clock stops.
    let isTyping: Bool

    @State private var remaining: Int?

    /// Waiting on the learner: the tutor spoke last, nothing runs, nothing is playing.
    private var waitingOnLearner: Bool {
        engine.phase == .idle && !engine.isRecording && engine.speakingMessageID == nil && !isTyping
            && engine.conversation.sortedMessages.last.map { !$0.isUser } == true
    }

    private var clockKey: String {
        "\(engine.conversation.messages.count)-\(waitingOnLearner)"
    }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let remaining {
                        Label("\(remaining)s", systemImage: "timer")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(remaining <= 5 ? .orange : .secondary)
                            .accessibilityLabel("\(remaining) seconds to answer")
                    }
                    ForEach(StammtischTopics.listenerPhrases.prefix(6), id: \.german) { phrase in
                        Button(phrase.german) { _ = engine.submitTyped(phrase.german) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .disabled(!engine.canSubmitTyped)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .task(id: clockKey) {
            remaining = nil
            guard let seconds = options.replySeconds, waitingOnLearner else { return }
            var left = seconds
            while left > 0 {
                remaining = left
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                left -= 1
            }
            remaining = nil
            if waitingOnLearner { engine.tutorMovesOn() }
        }
    }
}
