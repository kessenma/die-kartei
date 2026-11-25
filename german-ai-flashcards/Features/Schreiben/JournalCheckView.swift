//
//  JournalCheckView.swift
//  german-ai-flashcards
//
//  Prüfen: pick the tutor, run the check, read the result. An essay gets its score card; a
//  Tagebuch entry gets counts. Every sentence shows its verdict (✓ right, ✗ with the fix shown
//  as a word diff, ? "prüfen" for anything the tutor was unsure of, – left alone because it was
//  not German), its reason and its category, which opens the 30-second lesson.
//

import SwiftData
import SwiftUI

struct JournalCheckView: View {
    @Bindable var entry: JournalEntry
    @Bindable var modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var runner = WritingCheckRunner()
    @State private var lesson: GrammarFocus?

    private var tutorAvailable: Bool { WritingTutorPick.isAvailable(modelManager) }

    private var canRun: Bool {
        tutorAvailable && !runner.phase.isRunning && !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                controls
                if let check = entry.check {
                    if entry.kind == .aufsatz { scoreSection(check) }
                    else { countsSection(check) }
                    if let comment = check.comment { commentSection(comment, fallback: check.commentIsFallback) }
                    sentencesSection(check)
                }
            }
            .themedListScreen()
            .navigationTitle("Prüfen · Check")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { runner.cancel(); dismiss() }
                }
            }
            .sheet(item: $lesson) { focus in
                GrammarLessonSheet(focus: focus)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        Section {
            let options = WritingTutorPick.options
            if !options.isEmpty {
                Picker("Tutor", selection: Binding(
                    get: { WritingTutorPick.current(modelManager) ?? options[0] },
                    set: { modelManager.selectedPaperModel = $0 }
                )) {
                    ForEach(options) { model in Text(model.rawValue).tag(model) }
                }
            }
            Button {
                Task { await run() }
            } label: {
                HStack {
                    Label(entry.hasCheck ? "Noch einmal prüfen · Check again" : "Prüfen · Check my writing",
                          systemImage: "checkmark.seal")
                    if runner.phase.isRunning { Spacer(); ProgressView() }
                }
            }
            .disabled(!canRun)
            if let status = runner.statusText {
                Text(status).font(.caption).foregroundStyle(.secondary)
            } else if entry.checkIsStale {
                Label("Edited since the last check.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let at = entry.checkedAt, let model = entry.checkedModelID {
                Text("Checked \(at.formatted(.relative(presentation: .named))) by \(model).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } footer: {
            if !tutorAvailable {
                Text("No tutor is downloaded. Download one under Settings ▸ Model & Downloads; Apple Intelligence is not used here, because it corrects German it shouldn't.")
                    .font(.caption2)
            } else {
                Text("Sentence by sentence. When the tutor isn't sure it says \"prüfen\" rather than calling something wrong. \(entry.kind == .tagebuch ? "English sentences are left alone." : "")")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private func run() async {
        guard let tutor = WritingTutorPick.tutor(modelManager, service: mlxService) else { return }
        await runner.run(entry: entry, tutor: tutor, in: modelContext)
    }

    // MARK: - Score and counts

    private func scoreSection(_ check: WritingCheck) -> some View {
        Section {
            if let score = check.score {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    if let points = score.points {
                        Text("\(points)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(SchreibenTile.tint)
                        Text("/ 100").font(.title3).foregroundStyle(.secondary)
                    } else {
                        Text("Zu kurz · Too short to score")
                            .font(.headline)
                        Text("At least \(WritingScore.minimumChecked) judged sentences are needed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                scoreRow("Sauber · Clean sentences", "\(score.ok) of \(score.checked)")
                if score.targetMax > 0 {
                    scoreRow("Länge · Length", "\(score.words) words · Ziel \(score.targetMin)–\(score.targetMax)")
                } else {
                    scoreRow("Länge · Length", "\(score.words) words")
                }
                if score.unsure > 0 {
                    scoreRow("Prüfen · Ask your teacher", "\(score.unsure)")
                }
            }
            categoryChips(check)
        } header: {
            Text("Bewertung · Score").themedSectionHeader()
        } footer: {
            Text("The score is the app's arithmetic: seven tenths how many judged sentences were clean, three tenths how close the length came to the target. The tutor judges sentences; it never grades.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private func countsSection(_ check: WritingCheck) -> some View {
        Section {
            scoreRow("Sauber · Clean sentences", "\(check.okCount) of \(check.okCount + check.fixCount)")
            if check.skippedCount > 0 { scoreRow("Left alone · not German", "\(check.skippedCount)") }
            if check.unsureCount > 0 { scoreRow("Prüfen · Ask your teacher", "\(check.unsureCount)") }
            categoryChips(check)
        } header: {
            Text("Ergebnis · Result").themedSectionHeader()
        }
        .themedListRow()
    }

    private func scoreRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    @ViewBuilder
    private func categoryChips(_ check: WritingCheck) -> some View {
        let counts = check.categoryCounts.filter { $0.category != "-" }
        if !counts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(counts, id: \.category) { item in
                        categoryChip(item.category, count: item.count)
                    }
                }
            }
        }
    }

    private func categoryChip(_ raw: String, count: Int? = nil) -> some View {
        let focus = GrammarFocus(rawValue: raw)
        return Button {
            if let focus { lesson = focus }
        } label: {
            HStack(spacing: 4) {
                Text(WritingTutorCheck.categoryLabel(raw))
                if let count { Text("×\(count)").monospacedDigit() }
                if focus != nil { Image(systemName: "book").font(.caption2) }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(SchreibenTile.tint.opacity(0.12), in: Capsule())
            .foregroundStyle(focus != nil ? SchreibenTile.tint : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(focus == nil)
    }

    // MARK: - Comment

    private func commentSection(_ comment: String, fallback: Bool) -> some View {
        Section {
            Text(comment)
                .font(.body.italic())
        } header: {
            Text("Kommentar · Comment").themedSectionHeader()
        } footer: {
            Text(fallback ? "The tutor's comment broke the rules (a grade or a number), so this one is the app's." : "The tutor's words.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Sentences

    private func sentencesSection(_ check: WritingCheck) -> some View {
        Section {
            ForEach(check.sentences) { sentence in
                sentenceRow(sentence)
            }
        } header: {
            Text("Sätze · Sentences").themedSectionHeader()
        } footer: {
            if let limit = check.checkedSentenceLimit {
                Text("The first \(limit) German sentences were checked. Check again for the rest once these are fixed.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private func sentenceRow(_ sentence: WritingSentenceCheck) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: sentence.outcome))
                .foregroundStyle(tint(for: sentence.outcome))
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if sentence.outcome == .fix, let corrected = sentence.corrected {
                    DiffText(original: sentence.original, corrected: corrected)
                } else {
                    Text(sentence.original)
                        .foregroundStyle(sentence.outcome == .skipped ? .secondary : .primary)
                }
                if sentence.outcome == .unsure, let corrected = sentence.corrected {
                    Text("Tutor: \(corrected)").font(.caption).foregroundStyle(.secondary)
                }
                if let reason = sentence.reason, !reason.isEmpty {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let category = sentence.categoryRaw, category != "-", sentence.outcome != .ok {
                        categoryChip(category)
                    }
                    if sentence.outcome == .fix {
                        if sentence.applied {
                            Label("Übernommen", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                        } else if !entry.checkIsStale {
                            Button("Übernehmen · Apply fix") {
                                WritingCheckRunner.apply(sentence, to: entry, in: modelContext)
                            }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func icon(for outcome: WritingSentenceCheck.Outcome) -> String {
        switch outcome {
        case .ok: "checkmark.circle.fill"
        case .fix: "xmark.circle.fill"
        case .unsure: "questionmark.circle"
        case .skipped: "minus.circle"
        }
    }

    private func tint(for outcome: WritingSentenceCheck.Outcome) -> Color {
        switch outcome {
        case .ok: .green
        case .fix: .red
        case .unsure: .orange
        case .skipped: .secondary
        }
    }
}

// MARK: - Diff text

/// The learner's sentence with the tutor's fix in it: removed words struck through, new words
/// underlined in the room's colour.
struct DiffText: View {
    let original: String
    let corrected: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        for (i, token) in WritingDiff.diff(original, corrected).enumerated() {
            var piece = AttributedString(token.text)
            switch token.kind {
            case .same:
                break
            case .removed:
                piece.strikethroughStyle = .single
                piece.foregroundColor = .secondary
            case .inserted:
                piece.underlineStyle = .single
                piece.foregroundColor = SchreibenTile.tint
                piece.font = .body.weight(.semibold)
            }
            if i > 0 { out.append(AttributedString(" ")) }
            out.append(piece)
        }
        return out
    }
}
