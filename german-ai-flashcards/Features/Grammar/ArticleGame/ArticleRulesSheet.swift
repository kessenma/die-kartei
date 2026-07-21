//
//  ArticleRulesSheet.swift
//  german-ai-flashcards
//
//  The der/die/das cheat sheet — every gender pattern from `ArticleRules`, grouped by
//  article with its reliability spelled out. Reachable from the game's info button and
//  the setup screen, so help is one tap away exactly when a word stumps you.
//

import SwiftUI

struct ArticleRulesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Endings and word groups often give a noun's gender away. Tags show how far to trust each pattern — and when no pattern fits, learn the article as part of the word: \"die Gabel\", never just \"Gabel\".")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(GermanArticle.allCases) { article in
                    Section {
                        ForEach(ArticleRules.rules(for: article)) { rule in
                            ruleRow(rule)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(article.color)
                                .frame(width: 10, height: 10)
                            Text("\(article.rawValue) — \(article.genderGerman)")
                        }
                    }
                }

                Section {
                    Label(
                        "Across this app's dictionary: 39% of nouns are der, 34% die, 27% das — when truly guessing, der is the least-bad bet.",
                        systemImage: "die.face.3"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Der, die or das?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func ruleRow(_ rule: ArticleRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(rule.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(rule.reliability.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(reliabilityColor(rule.reliability).opacity(0.15), in: Capsule())
                    .foregroundStyle(reliabilityColor(rule.reliability))
            }
            Text(rule.examples)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let exceptions = rule.exceptions {
                Text("but: \(exceptions)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private func reliabilityColor(_ reliability: ArticleRule.Reliability) -> Color {
        switch reliability {
        case .always:       .green
        case .almostAlways: .teal
        case .usually:      .orange
        }
    }
}

#Preview {
    ArticleRulesSheet()
}
