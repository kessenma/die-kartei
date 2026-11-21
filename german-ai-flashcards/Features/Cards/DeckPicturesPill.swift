//
//  DeckPicturesPill.swift
//  german-ai-flashcards
//
//  Bilder · Pictures: while a deck is being illustrated, a small pill floats above the tab bar on
//  every tab (on the Mac, at the bottom of the window), so it is plain that the pictures keep
//  coming after the deck's start screen is closed. Deck name, picture n of N, a progress ring and
//  Stop. When the run ends it turns into a short note: how many were drawn, or why it stopped.
//
//  It reads `DeckIllustrationService.shared`, the run's single source of truth, and shows only for
//  a saved deck's run (`isDeckRun`). The create flow's draft run has its own overlay on Home.
//  Inside the deck player, a cover, the shell and so the pill are underneath; the deck's start
//  screen shows the same run with its own progress row.
//

import SwiftUI

struct DeckPicturesPill: View {
    @State private var service = DeckIllustrationService.shared
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme
    @State private var confirmingStop = false

    /// How long the "done" note stays when nothing went wrong.
    private static let noteSeconds: Double = 6

    var body: some View {
        Group {
            if service.isRunning, service.isDeckRun {
                running
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let finished = service.lastFinished {
                note(finished)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: finished.id) {
                        // A problem stays until it is read and closed.
                        guard finished.problem == nil else { return }
                        try? await Task.sleep(for: .seconds(Self.noteSeconds))
                        guard service.lastFinished?.id == finished.id else { return }
                        withAnimation(.easeIn(duration: 0.25)) { service.dismissFinished() }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: service.isRunning)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: service.lastFinished)
    }

    private var accent: Color { appTheme.accent(model: modelTheme) }

    // MARK: Running

    private var running: some View {
        HStack(spacing: 12) {
            ring
            VStack(alignment: .leading, spacing: 1) {
                Text("Bilder · Drawing pictures")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(runDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            Button {
                confirmingStop = true
            } label: {
                Text("Stop")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .confirmationDialog("Stop drawing pictures?", isPresented: $confirmingStop, titleVisibility: .visible) {
                Button("Stop", role: .destructive) { service.stop() }
            } message: {
                Text("The pictures drawn so far stay. Illustrate this deck, on its start screen, draws the rest later.")
            }
        }
        .pillFrame()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drawing pictures for \(service.runTitle ?? "a deck"), \(runDetail)")
    }

    private var runDetail: String {
        let title = service.runTitle.map { $0.isEmpty ? "Deck" : $0 } ?? "Deck"
        guard service.totalCount > 0 else { return "\(title) · starting…" }
        let current = min(service.completedCount + 1, service.totalCount)
        return "\(title) · \(current) of \(service.totalCount) · keeps going in the background"
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.03, service.progress))
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: service.progress)
            Image(systemName: "photo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .symbolEffect(.pulse)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    // MARK: Done

    private func note(_ finished: DeckIllustrationService.FinishedRun) -> some View {
        let trouble = finished.problem != nil
        let title = finished.title.isEmpty ? "Deck" : finished.title
        return HStack(spacing: 12) {
            Image(systemName: trouble ? "exclamationmark.triangle.fill"
                  : (finished.stopped ? "stop.circle.fill" : "checkmark.circle.fill"))
                .font(.title3)
                .foregroundStyle(trouble ? .orange : (finished.stopped ? .secondary : Color.green))
            VStack(alignment: .leading, spacing: 1) {
                Text(noteTitle(finished))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(finished.problem.map { "\(title) · \($0)" } ?? "\(title) · \(noteDetail(finished))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeIn(duration: 0.2)) { service.dismissFinished() }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .pillFrame()
        .accessibilityElement(children: .combine)
    }

    private func noteTitle(_ finished: DeckIllustrationService.FinishedRun) -> String {
        if finished.problem != nil { return "Bilder gestoppt · Pictures stopped" }
        if finished.stopped { return "Bilder gestoppt · Pictures stopped" }
        return "Bilder fertig · Pictures ready"
    }

    private func noteDetail(_ finished: DeckIllustrationService.FinishedRun) -> String {
        if finished.stopped {
            return "\(finished.drawn) of \(finished.total) drawn. The rest can be drawn from the deck's start screen."
        }
        if finished.drawn < finished.total {
            return "\(finished.drawn) of \(finished.total) drawn; the deck's start screen can try the rest."
        }
        return finished.drawn == 1 ? "1 picture is on its card." : "\(finished.drawn) pictures are on their cards."
    }
}

private extension View {
    /// The pill's capsule: material, a hairline, a soft shadow, never wider than a phone.
    func pillFrame() -> some View {
        self
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 460)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
            .padding(.horizontal, 16)
    }
}
