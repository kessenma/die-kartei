import SwiftUI

/// Reusable picker controls for study mode, which side to show first,
/// which side to display example sentences on, and auto-advance behaviour.
struct FlashcardPreviewOptionsView: View {
    @Binding var flashcardStyle: FlashcardStyle
    @Binding var showGermanFirst: Bool
    @Binding var showExamplesOnGermanSide: Bool
    @Binding var autoAdvance: Bool
    var showHints: Binding<Bool>? = nil
    var hasExamples: Bool
    var validationIssues: [ValidationResult] = []
    var cards: [VocabCard] = []
    var onFixIssues: (() -> Void)? = nil

    @State private var showingWordList = false

    private var correctableCount: Int {
        validationIssues.filter { $0.status.isCorrectable }.count
    }

    private var genderIssueCount: Int {
        validationIssues.filter {
            if case .genderMismatch = $0.status { return true }
            return false
        }.count
    }

    private var notFoundCount: Int {
        validationIssues.filter { $0.status == .notFound }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Study mode")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Study mode", selection: $flashcardStyle) {
                ForEach(FlashcardStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Text(flashcardStyle.description)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }

        if !cards.isEmpty {
            Button {
                showingWordList = true
            } label: {
                Label("See all \(cards.count) words", systemImage: "list.bullet")
                    .font(.subheadline)
            }
            .sheet(isPresented: $showingWordList) {
                WordListSheet(cards: cards)
            }
        }

        VStack(spacing: 12) {
            Text("Which side do you want to see first?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Front side", selection: $showGermanFirst) {
                Text("German").tag(true)
                Text("English").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
        }

        if hasExamples {
            VStack(spacing: 12) {
                Text("Show examples on which side?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Examples side", selection: $showExamplesOnGermanSide) {
                    Text("German side").tag(true)
                    Text("English side").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
        }

        VStack(spacing: 8) {
            Toggle("Auto-advance after rating", isOn: $autoAdvance)
                .frame(maxWidth: 280)
            Text("Skip the Next button — moves to the next card as soon as you choose a rating.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }

        if let showHints {
            VStack(spacing: 8) {
                Toggle("Show sentence hints", isOn: showHints)
                    .frame(maxWidth: 280)
                Text("Highlights the verb and noun; shows the noun's gender below the blank.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }

        if correctableCount > 0, let onFixIssues {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Validation Issues")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(issueDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)

                Button(action: onFixIssues) {
                    Label("Fix Issues", systemImage: "pencil.circle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
    }

    private var issueDescription: String {
        var parts: [String] = []
        if genderIssueCount > 0 {
            parts.append("\(genderIssueCount) gender issue\(genderIssueCount == 1 ? "" : "s")")
        }
        if notFoundCount > 0 {
            parts.append("\(notFoundCount) not in dictionary")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Word list sheet

struct WordListSheet: View {
    var cards: [VocabCard]
    @Environment(\.dismiss) private var dismiss
    @State private var showGerman = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)
                            .monospacedDigit()

                        Text(card.englishTranslation)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if showGerman {
                            Text(card.germanWord)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: showGerman)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Word List (\(cards.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(showGerman ? "Hide German" : "Reveal German") {
                        withAnimation { showGerman.toggle() }
                    }
                }
            }
        }
    }
}
