//
//  JournalHandwritingSheet.swift
//  german-ai-flashcards
//
//  "Lies ich das richtig?": the page's handwriting read into lines, each beside its crop, unsure
//  ones first, to fix or accept before the text goes into the entry and on to the tutor. Follows
//  the worksheet check's confirm list: nothing is taken until every unsure line has been looked
//  at, and the reading is never typed onto the page (the ink is already there).
//

import SwiftData
import SwiftUI

struct JournalHandwritingSheet: View {
    @Bindable var entry: JournalEntry
    /// Called with the confirmed text in the entry and whether the learner asked to check it.
    var onConfirmed: (_ check: Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("schreiben.inkLanguageCorrection") private var languageCorrection = false

    @State private var lines: [JournalInkLine] = []
    @State private var reading = false
    @State private var readOnce = false
    @State private var edits: [Int: String] = [:]
    @State private var acknowledged: Set<Int> = []
    @State private var pendingReplace: Bool?   // the check flag, while asking what to do with typed text

    private var unsureLeft: Int { lines.filter { !$0.isSure && !acknowledged.contains($0.id) }.count }
    private var transcript: String { JournalInkReader.transcript(from: lines, edits: edits) }
    private var typedText: String { entry.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if reading {
                        HStack { Text("Reading your handwriting…"); Spacer(); ProgressView() }
                    } else if lines.isEmpty, readOnce {
                        Text("No handwriting found on the page.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(lines.sorted { ($0.isSure ? 1 : 0, $0.id) < ($1.isSure ? 1 : 0, $1.id) }) { line in
                            row(line)
                        }
                    }
                } header: {
                    Text("Lies ich das richtig? · Confirm what you wrote").themedSectionHeader()
                } footer: {
                    Text("Read on this device, line by line. A line marked ? needs a look: fix it, pick another reading, or tap Looks right. \(languageCorrection ? "Dictionary smoothing is on." : "Read as written, without dictionary smoothing.")")
                        .font(.caption2)
                }
                .themedListRow()

                if !lines.isEmpty {
                    Section {
                        Button {
                            confirm(check: false)
                        } label: {
                            Label(confirmTitle, systemImage: "text.badge.checkmark")
                        }
                        .disabled(unsureLeft > 0 || reading)
                        Button {
                            confirm(check: true)
                        } label: {
                            Label("Übernehmen und prüfen · Take the text and check it", systemImage: "checkmark.seal")
                        }
                        .disabled(unsureLeft > 0 || reading)
                    } footer: {
                        Text(transcript)
                            .font(.caption)
                            .lineLimit(6)
                    }
                    .themedListRow()
                }

                Section {
                    Toggle("Lesehilfe · Dictionary smoothing", isOn: $languageCorrection)
                    Button {
                        Task { await read() }
                    } label: {
                        Label("Noch einmal lesen · Read again", systemImage: "arrow.clockwise")
                    }
                    .disabled(reading)
                } footer: {
                    Text("Smoothing lets Vision nudge a word toward the dictionary. It reads a hard hand better and hides a misspelling; try it when lines keep coming out wrong.")
                        .font(.caption2)
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle("Handschrift · Handwriting")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("You typed text in this entry too.", isPresented: Binding(
                get: { pendingReplace != nil }, set: { if !$0 { pendingReplace = nil } }
            ), titleVisibility: .visible) {
                Button("Replace it with the handwriting") { take(replace: true) }
                Button("Add the handwriting below it") { take(replace: false) }
                Button("Cancel", role: .cancel) { pendingReplace = nil }
            }
            .task { if !readOnce { await read() } }
        }
    }

    private var confirmTitle: String {
        if unsureLeft > 0 {
            return unsureLeft == 1 ? "Look at the unsure line first" : "Look at the \(unsureLeft) unsure lines first"
        }
        return "Text übernehmen · Take the text"
    }

    // MARK: - Rows

    private func row(_ line: JournalInkLine) -> some View {
        let needsLook = !line.isSure && !acknowledged.contains(line.id)
        return VStack(alignment: .leading, spacing: 6) {
            if let image = line.image {
                Image(decorative: image, scale: JournalInkReader.scale)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 60, alignment: .leading)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            HStack(spacing: 10) {
                TextField("What you wrote", text: Binding(
                    get: { edits[line.id] ?? line.text },
                    set: { edits[line.id] = $0; acknowledged.insert(line.id) }
                ), axis: .vertical)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .fontWeight(.semibold)
                if needsLook {
                    Button("Looks right") { acknowledged.insert(line.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                } else if !line.isSure {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Looked at")
                }
            }
            if line.candidates.count > 1 {
                HStack(spacing: 6) {
                    ForEach(line.candidates, id: \.self) { candidate in
                        Button(candidate) {
                            edits[line.id] = candidate
                            acknowledged.insert(line.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
            if needsLook {
                Label("Unsure reading", systemImage: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .background(needsLook ? Color.orange.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Reading and taking

    private func read() async {
        reading = true
        defer { reading = false; readOnce = true }
        edits = [:]
        acknowledged = []
        #if canImport(PencilKit) && canImport(Vision)
        guard let ink = JournalInkStore.read(entry.id) else { lines = []; return }
        let width = JournalInkStore.pageWidth
        let height = CGFloat(max(entry.inkHeight, JournalInkStore.initialHeight))
        let correction = languageCorrection
        lines = await Task.detached(priority: .userInitiated) {
            JournalInkReader.read(ink: ink, pageWidth: width, pageHeight: height, languageCorrection: correction)
        }.value
        #else
        lines = []
        #endif
    }

    private func confirm(check: Bool) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if !typedText.isEmpty, typedText != text {
            pendingReplace = check
            return
        }
        write(text, check: check)
    }

    private func take(replace: Bool) {
        guard let check = pendingReplace else { return }
        pendingReplace = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        write(replace ? text : typedText + "\n\n" + text, check: check)
    }

    private func write(_ text: String, check: Bool) {
        entry.text = text
        entry.transcriptConfirmedAt = .now
        entry.touch()
        try? modelContext.save()
        onConfirmed(check)
        dismiss()
    }
}
