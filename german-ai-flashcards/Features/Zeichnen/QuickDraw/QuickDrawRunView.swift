//
//  QuickDrawRunView.swift
//  german-ai-flashcards
//
//  A Quick Draw run, full screen: the word and the clock on top, the page below. In copy runs the
//  reference sits beside the page (above it on a phone). In recall runs, Next turns the card over:
//  the meaning and the picture beside what was drawn, then "Wusste ich / Nicht".
//
//  One canvas per word (`.id(turnID)`), so every word starts on a clean page with its own undo.
//  The ink is read from the canvas handle when the turn ends, not from the debounced save.
//

import SwiftData
import SwiftUI

struct QuickDrawRunView: View {
    @Bindable var session: QuickDrawSession
    let references: [UUID: ZeichnenReference]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var board = PencilBoard()
    @State private var handle = ZeichnenCanvasHandle()
    @State private var referenceImage: UIImage?
    @State private var confirmingQuit = false

    var body: some View {
        Group {
            if session.phase == .finished {
                NavigationStack {
                    QuickDrawReviewView(session: session) { dismiss() }
                }
            } else {
                run
            }
        }
        .task(id: session.current?.id) { await loadReference() }
    }

    // MARK: - The run

    private var run: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if session.phase == .reveal {
                reveal
            } else {
                drawing
            }
        }
        .background(Color(white: 0.96).ignoresSafeArea())
        .task(id: session.turnID) { await runClock() }
        .confirmationDialog("End this round?", isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button("Review what I drew") { session.finishEarly() }
            Button("Leave without saving", role: .destructive) { dismiss() }
            Button("Keep drawing", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            Button {
                confirmingQuit = true
            } label: {
                Image(systemName: "xmark").font(.title3.weight(.semibold))
            }
            .accessibilityLabel("End round")

            VStack(alignment: .leading, spacing: 2) {
                if let word = session.current {
                    Text.gendered(word.word.german, article: word.word.article)
                        .font(.largeTitle.weight(.bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if session.mode == .copy || session.phase == .reveal {
                        Text(word.english).font(.title3).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(session.progressLabel)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
            if session.phase == .drawing {
                QuickDrawClock(deadline: session.deadline, total: session.secondsPerWord)
                Button {
                    session.endDrawing(ink: handle.inkData)
                } label: {
                    Label(session.mode == .recall ? "Aufdecken" : "Weiter", systemImage: "arrow.right.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(ZeichnenTile.tint)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var drawing: some View {
        let canvas = ZeichnenCanvas(board: board, handle: handle)
            .id(session.turnID)
            .pencilRail(board, accent: ZeichnenTile.tint)
        if session.mode == .copy {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    referencePanel.frame(maxWidth: 340)
                    Divider()
                    canvas
                }
            } else {
                VStack(spacing: 0) {
                    referencePanel.frame(height: 180)
                    Divider()
                    canvas
                }
            }
        } else {
            canvas
        }
    }

    private var referencePanel: some View {
        ZStack {
            Color.white
            if let referenceImage {
                Image(uiImage: referenceImage).resizable().scaledToFit().padding(12)
            } else if let word = session.current {
                VStack(spacing: 8) {
                    Image(systemName: "scribble").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(word.english).font(.title2).foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }

    // MARK: - Reveal (recall runs)

    private var reveal: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                revealTile(title: "Deine Skizze · Yours") {
                    if let ink = session.revealInk, let cg = ZeichnenRender.image(ink: ink, dark: false, pixels: 600) {
                        Image(decorative: cg, scale: 1).resizable().scaledToFit()
                    } else {
                        Text("Blank page").foregroundStyle(.secondary)
                    }
                }
                revealTile(title: "Das Bild · The picture") {
                    if let referenceImage {
                        Image(uiImage: referenceImage).resizable().scaledToFit()
                    } else {
                        Image(systemName: "photo").font(.largeTitle).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxHeight: 420)

            Text("Did you know it?").font(.headline)
            HStack(spacing: 16) {
                Button {
                    session.mark(knewIt: false)
                } label: {
                    Label("Nicht gewusst", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                Button {
                    session.mark(knewIt: true)
                } label: {
                    Label("Wusste ich", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .controlSize(.large)
            .frame(maxWidth: 520)
            Spacer()
        }
        .padding(24)
    }

    private func revealTile<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ZStack { Color.white; content().padding(8) }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Clock and pictures

    /// Ends the drawing when the word's time is up. Restarts with every turn.
    private func runClock() async {
        guard session.phase == .drawing else { return }
        let wait = session.remaining(at: Date())
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled, session.phase == .drawing else { return }
        session.endDrawing(ink: handle.inkData)
    }

    private func loadReference() async {
        referenceImage = nil
        guard let word = session.current, let reference = references[word.id] else { return }
        referenceImage = await Task.detached(priority: .userInitiated) {
            reference.load(maxPixel: 900)
        }.value
    }
}

/// The time left on a word: a ring that empties, red in the last five seconds.
struct QuickDrawClock: View {
    let deadline: Date
    let total: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = max(0, deadline.timeIntervalSince(context.date))
            let fraction = total > 0 ? left / Double(total) : 0
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(left <= 5 ? Color.red : ZeichnenTile.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(left.rounded(.up)))")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(left <= 5 ? .red : .primary)
            }
            .frame(width: 48, height: 48)
            .accessibilityLabel("\(Int(left.rounded(.up))) seconds left")
        }
    }
}
