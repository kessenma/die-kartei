import SwiftUI

struct CorrectionSheetView: View {
    let germanWord: String
    let englishWord: String
    let validationResult: ValidationResult
    let wordType: String?
    var onApply: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedArticle: String = "der"
    @State private var didCopy = false

    private let articles = ["der", "die", "das"]

    private func genderInfo(for article: String) -> (symbol: String, color: Color) {
        switch article.lowercased() {
        case "der": return ("figure.stand", .blue)
        case "die": return ("figure.stand.dress", Color(.systemPink))
        case "das": return ("figure.stand.dress.line.vertical.figure", .purple)
        default: return ("questionmark", .secondary)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                wordInfoSection

                switch validationResult.status {
                case .genderMismatch(let expected):
                    genderMismatchContent(suggested: expected)
                case .notFound:
                    notFoundContent
                default:
                    EmptyView()
                }
            }
            .navigationTitle("Correct \u{201C}\(germanWord)\u{201D}")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if case .genderMismatch(let expected) = validationResult.status {
                selectedArticle = expected
            }
        }
    }

    // MARK: - Word info + copy

    @ViewBuilder
    private var wordInfoSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(germanWord)
                        .font(.headline)
                    Text(englishWord)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copyToClipboard()
                } label: {
                    Label(didCopy ? "Copied!" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(didCopy ? .green : .blue)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .animation(.spring(duration: 0.3), value: didCopy)
            }
        } footer: {
            Text("Copy to check in Google Translate or another tool.")
        }
    }

    private func copyToClipboard() {
        let text = "\(germanWord) — \(englishWord)"
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }

    // MARK: - Article picker (shared)

    @ViewBuilder
    private func articlePicker() -> some View {
        HStack(spacing: 10) {
            ForEach(articles, id: \.self) { article in
                let info = genderInfo(for: article)
                let isSelected = selectedArticle == article
                Button {
                    selectedArticle = article
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: info.symbol)
                            .font(.title2)
                            .foregroundStyle(isSelected ? info.color : .secondary)
                        Text(article)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .bold : .regular)
                            .foregroundStyle(isSelected ? info.color : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        isSelected ? info.color.opacity(0.12) : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? info.color : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .animation(.spring(duration: 0.2), value: selectedArticle)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }

    // MARK: - Gender mismatch

    @ViewBuilder
    private func genderMismatchContent(suggested: String) -> some View {
        Section {
            HStack {
                Text("Dictionary suggests")
                    .foregroundStyle(.secondary)
                Spacer()
                let info = genderInfo(for: suggested)
                HStack(spacing: 4) {
                    Image(systemName: info.symbol)
                        .foregroundStyle(info.color)
                    Text(suggested)
                        .foregroundStyle(info.color)
                        .fontWeight(.semibold)
                }
            }

            Button {
                selectedArticle = suggested
            } label: {
                Label("Use dictionary suggestion (\(suggested))", systemImage: "book.closed")
            }
        } header: {
            Text("Gender Mismatch")
        } footer: {
            Text("The Wiktionary dictionary data shows a different gender for this noun.")
        }

        Section {
            articlePicker()
        } header: {
            Text("Choose correct article")
        }

        crossCheckSection(dictionarySuggestion: suggested)

        Section {
            Button {
                onApply(selectedArticle)
                dismiss()
            } label: {
                Label("Apply correction", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
        }
    }

    // MARK: - Not found

    @ViewBuilder
    private var notFoundContent: some View {
        Section {
            Text("This word wasn't found in the bundled Wiktionary data. It may be a proper noun, technical term, or regional word.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Not in Dictionary")
        }

        let isNoun = wordType?.lowercased() == "noun" || wordType == nil
        if isNoun {
            Section {
                articlePicker()
            } header: {
                Text("Set article manually")
            }
        }

        crossCheckSection(dictionarySuggestion: nil)

        Section {
            Button {
                onApply(isNoun ? selectedArticle : nil)
                dismiss()
            } label: {
                Label("Mark as correct", systemImage: "checkmark.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)

            Button {
                onApply(nil)
                dismiss()
            } label: {
                Label("Dismiss warning", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .tint(.secondary)
        }
    }

    // MARK: - Cross-check section

    @ViewBuilder
    private func crossCheckSection(dictionarySuggestion: String?) -> some View {
        let installed = MLXModel.allCases.filter { $0.isDownloaded }
        if !installed.isEmpty {
            Section {
                NavigationLink {
                    ModelCrossCheckView(
                        germanWord: germanWord,
                        englishWord: englishWord,
                        wordType: wordType,
                        dictionarySuggestion: dictionarySuggestion
                    )
                } label: {
                    Label("Ask local AI models", systemImage: "brain")
                }
            } header: {
                Text("Cross-check")
            } footer: {
                Text("Query your downloaded models to see what each one thinks the correct article is.")
            }
        }
    }
}
