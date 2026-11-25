//
//  ClozePracticeView.swift
//  german-ai-flashcards
//
//  "Fix your sentences" — a self-graded fill-in-the-blank round over the learner's own corrected
//  sentences (see `ClozeSession` / `LexicalSlip`). Each card shows one of their real sentences with
//  the word they slipped on blanked out; they recall it, reveal, and self-rate. A correct fill
//  retires that slip (self-heal); the round feeds the streak. FUTURE #3.
//
//  Presented immersively via `ActivityRouter` (`.cloze`), exactly like `.matching`. On finish it
//  hands the mastered / missed slip ids up so `ContentView` can fold them back into the profile.
//

import SwiftUI

struct ClozePracticeView: View {
    let session: ClozeSession
    /// Called once when the round ends — (mastered slip ids, missed slip ids, seconds spent).
    var onComplete: (_ mastered: [String], _ missed: [String], _ durationSeconds: Int) -> Void
    var onDismiss: () -> Void

    @State private var index = 0
    @State private var revealed = false
    @State private var masteredIDs: [String] = []
    @State private var missedIDs: [String] = []
    @State private var showSummary = false
    @State private var didReport = false
    /// When the round opened — its time on task, banked into the day log on finish.
    @State private var startedAt = Date()

    private var cards: [ClozeCard] { session.cards }
    private var currentCard: ClozeCard? { cards.indices.contains(index) ? cards[index] : nil }
    private var answeredCount: Int { masteredIDs.count + missedIDs.count }

    var body: some View {
        ZStack {
            ThemedBackground().ignoresSafeArea()

            if cards.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    topBar
                    progressHeader
                    Spacer(minLength: 0)
                    if let card = currentCard { cardBody(card) }
                    Spacer(minLength: 0)
                    controls
                }
            }

            if showSummary {
                summaryOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .tint(.accentColor)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                reportIfNeeded()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            Spacer()
            Text(session.topic)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            // Balances the close button so the title stays centered.
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var progressHeader: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .systemGray5))
                    Capsule()
                        .fill(.tint)
                        .frame(width: geo.size.width * progressFraction)
                }
            }
            .frame(height: 6)

            Text("Sentence \(min(index + 1, cards.count)) of \(cards.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var progressFraction: CGFloat {
        guard !cards.isEmpty else { return 0 }
        return CGFloat(answeredCount) / CGFloat(cards.count)
    }

    // MARK: - Card

    private func cardBody(_ card: ClozeCard) -> some View {
        VStack(spacing: 20) {
            Text("Fill in the blank")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(card.prompt)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            if revealed {
                answerReveal(card)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .themedCard()
        .padding(.horizontal)
    }

    private func answerReveal(_ card: ClozeCard) -> some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 10) {
                Text(card.answer)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.green)
                Button {
                    SpeechService.shared.speak(card.fullSentence)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
            if !card.wrong.isEmpty {
                HStack(spacing: 6) {
                    Text("You wrote")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.wrong)
                        .font(.caption.weight(.medium))
                        .strikethrough()
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        if !revealed {
            Button {
                if let card = currentCard { SpeechService.shared.speak(card.answer) }
                withAnimation(.easeInOut(duration: 0.2)) { revealed = true }
            } label: {
                Text("Reveal answer")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        } else {
            HStack(spacing: 12) {
                Button {
                    rate(mastered: false)
                } label: {
                    Label("Missed it", systemImage: "xmark")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)

                Button {
                    rate(mastered: true)
                } label: {
                    Label("Got it", systemImage: "checkmark")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
            }
            .padding()
        }
    }

    // MARK: - Summary

    private var summaryOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)

                Text("Round complete")
                    .font(.title2.bold())

                Text("You fixed \(masteredIDs.count) of \(cards.count) sentence\(cards.count == 1 ? "" : "s").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(masteredIDs.isEmpty
                     ? "The ones you missed stay in Coach's Notes so you can try them again."
                     : "The ones you fixed retire from Coach's Notes; anything you missed stays for next time.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Button {
                    onDismiss()
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(40)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Nothing to fix yet",
                systemImage: "text.insert",
                description: Text("Have a few conversations — when the coach corrects a word, that sentence becomes a fill-in-the-blank card here.")
            )
            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Logic

    private func rate(mastered: Bool) {
        guard let card = currentCard else { return }
        if mastered { masteredIDs.append(card.slipID) } else { missedIDs.append(card.slipID) }

        if index + 1 < cards.count {
            withAnimation(.easeInOut(duration: 0.15)) {
                index += 1
                revealed = false
            }
        } else {
            reportIfNeeded()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showSummary = true }
        }
    }

    /// Fold results back into the profile exactly once — on finish or on an early close.
    private func reportIfNeeded() {
        guard !didReport, answeredCount > 0 else { return }
        didReport = true
        onComplete(masteredIDs, missedIDs, max(0, Int(Date().timeIntervalSince(startedAt))))
    }
}
