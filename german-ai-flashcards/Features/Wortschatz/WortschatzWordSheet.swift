//
//  WortschatzWordSheet.swift
//  german-ai-flashcards
//
//  One Goethe word's history: the word itself with its forms, where it stands in the box, and what
//  the der/die/das and matching games have seen of it.
//

import SwiftUI
import SwiftData

struct WortschatzWordSheet: View {
    let word: GoetheWord
    let card: SavedCard?
    let articleStat: ArticleWordStat?
    let matchingStat: MatchingPairStat?
    let style: FlashcardStyle
    let leitnerSession: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            List {
                wordSection
                boxSection
                if articleStat != nil || matchingStat != nil {
                    gamesSection
                }
            }
            .themedListScreen()
            .navigationTitle("Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - The word

    private var wordSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text.gendered(word.word, article: word.article)
                        .font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        SpeechService.shared.speak(word.word.withArticle(word.article))
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hear the word")
                }
                if let forms = word.formsLine {
                    Text(forms)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let translation = word.translation {
                    Text(translation)
                        .font(.body)
                }
                if let example = word.example, !example.isEmpty {
                    Text(example)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(word.orderedLevels) { level in
                        Text(level.rawValue)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12), in: theme.pillShape)
                            .foregroundStyle(.blue)
                    }
                    if let type = word.rawWordType {
                        Text(type)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 4)
        }
        .themedListRow()
    }

    // MARK: - In the box

    private var boxSection: some View {
        Section {
            if let card {
                let badge = WortschatzService.badgeText(card, style: style, leitnerSession: leitnerSession)
                let color = WortschatzService.badgeColor(card, style: style, leitnerSession: leitnerSession)
                LabeledContent("Status") {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.14), in: theme.pillShape)
                }
                if !WortschatzService.isNew(card) {
                    if let next = card.nextReviewDate {
                        LabeledContent("Next review", value: next.formatted(date: .abbreviated, time: .omitted))
                    }
                    LabeledContent("Spacing", value: card.interval == 1 ? "1 day" : "\(card.interval) days")
                    LabeledContent("Correct in a row", value: "\(card.repetitions)")
                    LabeledContent("Reviews", value: "\(card.totalReviews)")
                    LabeledContent("Lapses", value: "\(card.lapses)")
                    if card.leitnerBox > 0 {
                        LabeledContent("Leitner", value: LeitnerService.boxLabel(card.leitnerBox))
                    }
                } else {
                    Text("Not studied yet. It joins a session as a new word once the levels it belongs to are in scope.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Not studied yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Im Karteikasten · In the box").themedSectionHeader()
        } footer: {
            Text("A word counts as known after three weeks of spacing or three correct reviews in a row, the same rule the Lernpyramide uses.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Games

    private var gamesSection: some View {
        Section {
            if let stat = articleStat {
                statRow(
                    title: "Der · Die · Das",
                    detail: "\(stat.timesSeen) rounds · \(stat.timesMissed) missed"
                        + (stat.topWrongPick.map { " · you reach for \($0.rawValue)" } ?? ""),
                    tricky: stat.isTricky,
                    systemImage: "textformat.abc"
                )
            }
            if let stat = matchingStat {
                statRow(
                    title: "Card Matching",
                    detail: "\(stat.timesSeen) rounds · \(stat.timesMissed) missed"
                        + (stat.topConfusion.map { " · confused with “\($0)”" } ?? ""),
                    tricky: stat.isTricky,
                    systemImage: "square.grid.2x2"
                )
            }
        } header: {
            Text("Spiele · Games").themedSectionHeader()
        }
        .themedListRow()
    }

    private func statRow(title: String, detail: String, tricky: Bool, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tricky ? .red : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.medium))
                    if tricky {
                        Text("tricky")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12), in: theme.pillShape)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
