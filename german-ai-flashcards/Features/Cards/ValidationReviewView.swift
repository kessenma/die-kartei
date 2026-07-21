import SwiftUI

/// Shared der/die/das presentation, so the picker, the badges and the cross-check results
/// all read the same way.
enum ArticleStyle {
    static func symbol(for article: String) -> String {
        switch article.lowercased() {
        case "der": return "figure.stand"
        case "die": return "figure.stand.dress"
        case "das": return "figure.stand.dress.line.vertical.figure"
        default: return "questionmark"
        }
    }

    static func color(for article: String) -> Color {
        switch article.lowercased() {
        case "der": return .blue
        case "die": return Color(.systemPink)
        case "das": return .purple
        default: return .secondary
        }
    }

    static let all = ["der", "die", "das"]
}

/// One screen for everything the validator did and everything it couldn't settle.
///
/// Replaces the old row → sheet → picker → apply → back drill-down: every word is visible
/// at once and every article is one tap, because the article picker lives in the row itself.
struct ValidationReviewView: View {
    @Binding var cards: [VocabCard]
    @Binding var validationResults: [ValidationResult]
    var onApplyCorrection: (Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(MLXGenerationService.self) private var service

    @State private var crossCheck = ArticleCrossCheck()

    /// Words the app couldn't settle on its own.
    private var attentionIndices: [Int] {
        validationResults.indices.filter { validationResults[$0].status.needsAttention }
    }

    /// Corrections still standing, in card order. Read from `validationResults` rather than the
    /// `corrections` snapshot so a row leaves the list the moment the user overrides it.
    private var correctedIndices: [Int] {
        validationResults.indices.filter { validationResults[$0].status.wasAutoCorrected }
    }

    var body: some View {
        NavigationStack {
            Group {
                if attentionIndices.isEmpty && correctedIndices.isEmpty {
                    cleanState
                } else {
                    List {
                        if !attentionIndices.isEmpty { attentionSection }
                        if !correctedIndices.isEmpty { correctionsSection }
                    }
                }
            }
            .navigationTitle("Dictionary Check")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Needs your input

    @ViewBuilder
    private var attentionSection: some View {
        Section {
            ForEach(attentionIndices, id: \.self) { index in
                reviewRow(index: index, suggestion: nil)
            }
        } header: {
            Text("Needs your input")
        } footer: {
            Text("These aren't in the dictionary and no rule could settle them, usually proper nouns, slang, or very new words. Set an article, or leave them as the model wrote them.")
        }

        if crossCheck.isSupported(service: service) {
            Section {
                crossCheckButton
                if let error = crossCheck.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Asks the loaded model about all \(attentionIndices.count) word\(attentionIndices.count == 1 ? "" : "s") in a single prompt. Its answer appears on each row as a suggestion. Nothing is applied for you.")
            }
        }
    }

    @ViewBuilder
    private var crossCheckButton: some View {
        Button {
            let words = attentionIndices.map {
                (german: cards[$0].germanWord, english: cards[$0].englishTranslation)
            }
            Task { await crossCheck.run(words: words, service: service) }
        } label: {
            if crossCheck.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Asking \(crossCheck.modelName(service: service))\u{2026}")
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(
                    crossCheck.answers.isEmpty
                        ? "Ask \(crossCheck.modelName(service: service))"
                        : "Ask again",
                    systemImage: "sparkles"
                )
            }
        }
        .disabled(crossCheck.isRunning)
    }

    // MARK: - Corrected automatically

    @ViewBuilder
    private var correctionsSection: some View {
        Section {
            ForEach(correctedIndices, id: \.self) { index in
                reviewRow(index: index, suggestion: nil)
            }
        } header: {
            Text("Corrected for you")
        } footer: {
            Text("The model's article disagreed with the dictionary, so it was fixed before you saw the cards. Tap a different article to override.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func reviewRow(index: Int, suggestion: String?) -> some View {
        let card = cards[index]
        let status = validationResults[index].status
        let isNoun = card.wordType?.lowercased() == "noun" || card.wordType == nil
        let modelAnswer = crossCheck.answers[card.germanWord.lowercased()]

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.germanWord)
                    .font(.headline)
                Spacer()
                Text(card.englishTranslation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let detail = rowDetail(for: status) {
                Label(detail.text, systemImage: detail.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isNoun {
                articlePicker(selected: card.article?.lowercased()) { article in
                    apply(article, at: index)
                }
            }

            if let modelAnswer {
                modelSuggestionRow(
                    answer: modelAnswer,
                    matchesCurrent: modelAnswer == card.article?.lowercased(),
                    onUse: { apply(modelAnswer, at: index) }
                )
            }
        }
        .padding(.vertical, 6)
    }

    private func rowDetail(for status: ValidationStatus) -> (icon: String, text: String)? {
        switch status {
        case .autoCorrected(let from, let to, let source):
            if let from {
                return (source.systemImage, "\(from) \u{2192} \(to) \u{00B7} \(source.explanation)")
            }
            return (source.systemImage, "Set to \(to) \u{00B7} \(source.explanation)")
        case .genderMismatch(let expected):
            return ("book.closed", "Dictionary records \(expected)")
        case .notFound:
            return ("questionmark.circle", "Not in the dictionary")
        default:
            return nil
        }
    }

    @ViewBuilder
    private func articlePicker(selected: String?, onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(ArticleStyle.all, id: \.self) { article in
                let isSelected = selected == article
                let color = ArticleStyle.color(for: article)
                Button {
                    onSelect(article)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: ArticleStyle.symbol(for: article))
                            .font(.caption)
                        Text(article)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                    }
                    .foregroundStyle(isSelected ? color : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        isSelected ? color.opacity(0.12) : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? color : .clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(duration: 0.2), value: selected)
    }

    @ViewBuilder
    private func modelSuggestionRow(answer: String, matchesCurrent: Bool, onUse: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Model says")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(answer)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(ArticleStyle.color(for: answer))

            Spacer()

            if matchesCurrent {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Button("Use", action: onUse)
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - Actions

    private func apply(_ article: String, at index: Int) {
        guard cards.indices.contains(index), validationResults.indices.contains(index) else { return }
        cards[index].article = article
        validationResults[index].status = .verified
        onApplyCorrection(index, article)
    }

    @ViewBuilder
    private var cleanState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Nothing to review")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Every word checked out against the dictionary.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
