import DieKarteiCore
import SwiftUI

struct ModelCrossCheckView: View {
    let germanWord: String
    let englishWord: String
    let wordType: String?
    let dictionarySuggestion: String?

    @Environment(MLXGenerationService.self) private var service

    @State private var selectedModels: Set<MLXModel> = []
    @State private var results: [MLXModel: CrossCheckResult] = [:]
    @State private var isChecking = false
    @State private var checkingModel: MLXModel? = nil

    private var installedModels: [MLXModel] {
        MLXModel.allCases.filter { $0.isDownloaded }
    }

    var body: some View {
        Form {
            modelPickerSection
            if !results.isEmpty { resultsSection }
        }
        .navigationTitle("Cross-check Article")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Model picker

    @ViewBuilder
    private var modelPickerSection: some View {
        Section {
            if installedModels.isEmpty {
                Label("No models downloaded yet. Download a model from Settings to enable cross-checking.", systemImage: "arrow.down.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(installedModels) { model in
                    modelRow(model)
                }
            }
        } header: {
            Text("Select models to query")
        } footer: {
            Text("Each model will be loaded into memory in turn — this may take a moment per model.")
        }

        if !selectedModels.isEmpty {
            Section {
                Button {
                    Task { await runChecks() }
                } label: {
                    if isChecking {
                        HStack {
                            ProgressView()
                            if let m = checkingModel {
                                Text("Asking \(m.displayName)…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Ask \(selectedModels.count) model\(selectedModels.count == 1 ? "" : "s")", systemImage: "sparkles")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isChecking)
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: MLXModel) -> some View {
        HStack {
            Image(systemName: selectedModels.contains(model) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selectedModels.contains(model) ? .blue : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.subheadline)
                if let r = results[model] {
                    resultLabel(r)
                }
            }

            Spacer()

            if checkingModel == model {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedModels.contains(model) {
                selectedModels.remove(model)
            } else {
                selectedModels.insert(model)
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Model")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text("Answer")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text("vs. Dictionary")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                Divider()
                ForEach(installedModels.filter { results[$0] != nil }) { model in
                    let result = results[model]!
                    GridRow {
                        Text(model.displayName)
                            .font(.caption)
                        articleDisplay(result.article)
                        matchIcon(result: result)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Results for \u{201C}\(germanWord)\u{201D}")
        }
    }

    @ViewBuilder
    private func articleDisplay(_ article: String?) -> some View {
        if let article {
            let badge = genderInfo(for: article)
            HStack(spacing: 4) {
                Image(systemName: badge.symbol)
                    .foregroundStyle(badge.color)
                Text(article)
                    .fontWeight(.medium)
                    .foregroundStyle(badge.color)
            }
            .font(.caption)
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func matchIcon(result: CrossCheckResult) -> some View {
        switch result.match {
        case .agrees:
            Label("Agrees", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .disagrees:
            Label("Disagrees", systemImage: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .noSuggestion:
            Label("No dict. data", systemImage: "minus.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .unclear:
            Label("Unclear", systemImage: "questionmark.circle")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func resultLabel(_ result: CrossCheckResult) -> some View {
        if let article = result.article {
            let badge = genderInfo(for: article)
            HStack(spacing: 3) {
                Image(systemName: badge.symbol)
                    .font(.caption2)
                    .foregroundStyle(badge.color)
                Text(article)
                    .font(.caption2)
                    .foregroundStyle(badge.color)
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - Logic

    private func runChecks() async {
        isChecking = true
        let modelsToCheck = installedModels.filter { selectedModels.contains($0) }

        for model in modelsToCheck {
            checkingModel = model
            do {
                await service.loadModel(model)
                let raw = try await service.generateText(
                    system: "You are a German grammar expert. Reply with exactly one word — the correct German article for the noun given. Only answer with: der, die, or das.",
                    user: "What is the correct German article for the noun \"\(germanWord)\" (\(englishWord))?",
                    model: model,
                    maxTokens: 8
                )
                let article = extractArticle(from: raw)
                let match = compareArticle(article, to: dictionarySuggestion)
                results[model] = CrossCheckResult(article: article, match: match)
            } catch {
                results[model] = CrossCheckResult(article: nil, match: .unclear)
            }
        }

        checkingModel = nil
        isChecking = false
    }

    private func extractArticle(from raw: String) -> String? {
        let lower = raw.lowercased()
        for article in ["der", "die", "das"] {
            if lower.contains(article) { return article }
        }
        return nil
    }

    private func compareArticle(_ article: String?, to suggestion: String?) -> CrossCheckResult.Match {
        guard let suggestion else { return .noSuggestion }
        guard let article else { return .unclear }
        return article.lowercased() == suggestion.lowercased() ? .agrees : .disagrees
    }

    private func genderInfo(for article: String) -> (symbol: String, color: Color) {
        switch article.lowercased() {
        case "der": return ("figure.stand", .blue)
        case "die": return ("figure.stand.dress", Color(.systemPink))
        case "das": return ("figure.stand.dress.line.vertical.figure", .purple)
        default: return ("questionmark", .secondary)
        }
    }
}

struct CrossCheckResult {
    var article: String?
    var match: Match

    enum Match {
        case agrees, disagrees, noSuggestion, unclear
    }
}
