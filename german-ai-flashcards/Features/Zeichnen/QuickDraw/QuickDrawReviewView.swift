//
//  QuickDrawReviewView.swift
//  german-ai-flashcards
//
//  The end of a Quick Draw run: every sketch with its word, tap to keep or let go, then Fertig.
//
//  Fertig records the run, whatever is kept: every word drawn counts in `WordDrawingStat` and in
//  today's study log, and recall misses go to the coach as words met. Only the ticked sketches are
//  written to the Bildermappe (and so to iCloud).
//

import SwiftData
import SwiftUI

struct QuickDrawReviewView: View {
    @Bindable var session: QuickDrawSession
    var onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var thumbnails: [UUID: CGImage] = [:]
    @State private var recorded = false
    @State private var savingSet = false
    @State private var setName = ""
    @State private var savedSetName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary
                if session.drawnTurns.isEmpty {
                    ContentUnavailableView("Nothing drawn", systemImage: "scribble",
                                           description: Text("The pages were left blank this time."))
                } else {
                    keepControls
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(session.turns) { turn in
                            cell(turn)
                        }
                    }
                }
                if let savedSetName {
                    Label("Saved as „\(savedSetName)“", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(20)
        }
        .themedScreen()
        .navigationTitle("Geschafft")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { finish() }
                    .fontWeight(.semibold)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    setName = defaultSetName
                    savingSet = true
                } label: {
                    Label("Save words as a set", systemImage: "square.stack.3d.up")
                }
            }
        }
        .alert("Save as a Quick Draw set", isPresented: $savingSet) {
            TextField("Name", text: $setName)
            Button("Save") { saveSet() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(session.missed.isEmpty ? "All \(session.turns.count) words." : "Only the \(session.missed.count) you missed, to draw again.")
        }
        .task { await renderThumbnails() }
    }

    // MARK: - Parts

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(session.drawnTurns.count) of \(session.words.count) words drawn")
                .font(.title2.weight(.bold))
            if session.mode == .recall, !session.turns.isEmpty {
                Text("You knew \(session.recalledCount) of \(session.turns.count).")
                    .foregroundStyle(.secondary)
            }
            if session.totalSeconds > 0 {
                Text(StudyTimeFormat.long(session.totalSeconds))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var keepControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keep \(session.turnsToKeep.count) of \(session.drawnTurns.count)")
                    .font(.headline)
                Spacer()
                Button("All") { session.keepAll() }
                Button("None") { session.keepNone() }
            }
            .buttonStyle(.bordered)
            Text("Kept sketches go to each word's Bildermappe and sync through iCloud (about \(WordArtStore.sizePhrase(WordArtStore.typicalSketchBytes)) each).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func cell(_ turn: QuickDrawSession.Turn) -> some View {
        let kept = session.keep.contains(turn.id)
        return Button {
            session.toggleKeep(turn.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color.white
                    if let image = thumbnails[turn.id] {
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                    } else if !turn.drewSomething {
                        Text("blank").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(kept ? ZeichnenTile.tint : Color.secondary.opacity(0.25), lineWidth: kept ? 3 : 1))
                .overlay(alignment: .topTrailing) {
                    if turn.drewSomething {
                        Image(systemName: kept ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(kept ? ZeichnenTile.tint : .secondary)
                            .background(Circle().fill(.white))
                            .padding(6)
                    }
                }
                HStack(spacing: 4) {
                    if let recalled = turn.recalled {
                        Image(systemName: recalled ? "checkmark" : "xmark")
                            .foregroundStyle(recalled ? .green : .orange)
                    }
                    Text.gendered(turn.word.word.german, article: turn.word.word.article)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                Text(turn.word.english).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!turn.drewSomething)
        .accessibilityLabel("\(turn.word.display), \(kept ? "kept" : "not kept")")
    }

    // MARK: - Actions

    private var defaultSetName: String {
        let date = Date().formatted(date: .abbreviated, time: .omitted)
        return session.missed.isEmpty ? "Skizzen \(date)" : "Nochmal \(date)"
    }

    private func renderThumbnails() async {
        for turn in session.turns {
            guard let ink = turn.ink, thumbnails[turn.id] == nil else { continue }
            thumbnails[turn.id] = ZeichnenRender.image(ink: ink, dark: false, pixels: 360)
            await Task.yield()
        }
    }

    private func saveSet() {
        let words = session.missed.isEmpty ? session.turns.map(\.word) : session.missed.map(\.word)
        let name = setName.trimmingCharacters(in: .whitespaces)
        let set = QuickDrawSet(name: name.isEmpty ? defaultSetName : name, cardIDs: words.map(\.id))
        modelContext.insert(set)
        try? modelContext.save()
        savedSetName = set.name
    }

    private func finish() {
        record()
        onDone()
    }

    /// Once per run, whatever the learner keeps.
    private func record() {
        guard !recorded else { return }
        recorded = true

        for turn in session.turnsToKeep {
            guard let ink = turn.ink else { continue }
            let mode = session.mode
            ZeichnenSaving.save(ink: ink, word: turn.word.word, kind: .quick, configure: {
                $0.modeRaw = mode.rawValue
                $0.recalled = turn.recalled
            }, in: modelContext)
        }

        let attempted = session.turns.filter { $0.drewSomething || $0.recalled != nil }
        WordDrawingLog.recordQuick(attempted.map {
            WordDrawingLog.QuickEntry(germanWord: $0.word.display, english: $0.word.english, recalled: $0.recalled)
        }, in: modelContext)

        if !attempted.isEmpty || session.totalSeconds > 0 {
            StudyLogService.record(.drawing(attempted.count), seconds: session.totalSeconds, in: modelContext)
        }

        if !session.missed.isEmpty {
            LearnerMemoryService.noteVocabEncounters(
                session.missed.map { (german: $0.word.display, english: $0.word.english) },
                source: "zeichnen.quick",
                in: modelContext
            )
        }
    }
}
