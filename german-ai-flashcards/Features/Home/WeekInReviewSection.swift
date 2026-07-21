//
//  WeekInReviewSection.swift
//  german-ai-flashcards
//
//  The "This Week" growth block that sits right under the streak calendar in the Home hub. It turns
//  the same `StudyDay` log the streak is built on into a short *growth* story — a 2×2 grid of the
//  week's activity, each figure shown against the previous seven days, topped by an upbeat headline
//  ("Cards reviewed up 3× this week" / "12 words retained"). Below it, a one-tap **Weekly recap**
//  starts a conversation pre-seeded with this week's shakiest grammar tags, so the coach recycles
//  weak spots and saved words in one sitting (see docs/FUTURE_FEATURES.md #6 + #7).
//

import SwiftUI
import SwiftData

struct WeekInReviewSection: View {
    @Bindable var coordinator: GenerationCoordinator

    @Environment(\.modelContext) private var modelContext

    @Query private var studyDays: [StudyDay]
    @Query(sort: \ChatConversation.createdAt, order: .reverse) private var conversations: [ChatConversation]
    @Query private var profiles: [LearnerProfile]

    /// Set to launch the recap chat once its config + conversation are built.
    @State private var recapChat: ActiveChat?

    private var review: WeekInReview {
        WeekInReviewService.summary(days: studyDays, conversations: conversations)
    }

    private var profile: LearnerProfile? { profiles.first }

    var body: some View {
        // Only worth showing once there's a week (or a prior week) to reflect on.
        if review.hasActivity || review.hadPriorActivity {
            Section {
                if let headline = review.headline {
                    Label(headline, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.vertical, 2)
                }

                growthGrid
                    .padding(.vertical, 4)

                recapButton
            } header: {
                Text("This Week")
                    .textCase(nil)
            } footer: {
                Text("Your last 7 days versus the 7 before. The weekly recap recycles your shakiest grammar and recent words into one chat — spaced practice in a single sitting.")
                    .font(.caption2)
            }
            .fullScreenCover(item: $recapChat) { chat in
                ConversationView(
                    conversation: chat.conversation,
                    config: chat.config,
                    modelManager: coordinator.modelManager,
                    mlxService: coordinator.mlxService
                )
            }
        }
    }

    // MARK: - Growth grid

    private var growthGrid: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                StatTile(title: "Active days", value: "\(review.activeDays)", detail: "of 7",
                         delta: review.activeDays - review.prevActiveDays,
                         systemImage: "flame.fill", accent: .orange)
                StatTile(title: "Cards reviewed", value: "\(review.cardsReviewed)",
                         delta: review.cardsReviewed - review.prevCardsReviewed,
                         systemImage: "rectangle.stack.fill", accent: .blue)
            }
            GridRow {
                StatTile(title: "Grammar drills", value: "\(review.grammarExercises)",
                         delta: review.grammarExercises - review.prevGrammarExercises,
                         systemImage: "checklist", accent: .purple)
                StatTile(title: "Words retained", value: "\(review.wordsRetained)",
                         delta: review.wordsRetained - review.prevWordsRetained,
                         systemImage: "arrow.2.circlepath", accent: .green)
            }
        }
    }

    // MARK: - Weekly recap

    private var recapButton: some View {
        Button(action: startRecap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.indigo)
                    .frame(width: 38, height: 38)
                    .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly recap")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(recapSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recapSubtitle: String {
        let focuses = weakFocuses
        if focuses.isEmpty {
            return "A guided chat revisiting your recent words"
        }
        let names = focuses.map(\.germanLabel).joined(separator: " · ")
        return "Interleave \(names) + your saved words in one chat"
    }

    /// This week's shakiest grammar structures, worst-first, capped so the recap stays targeted.
    /// Mirrors the Today plan's weakness sort so both agree on what's weak.
    private var weakFocuses: [GrammarFocus] {
        guard let profile else { return [] }
        return profile.grammar
            .compactMap { key, skill -> (GrammarFocus, Double)? in
                guard skill.struggle >= GrammarSkill.shakyThreshold,
                      let focus = GrammarFocus(rawValue: key) else { return nil }
                return (focus, skill.struggle)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0)
    }

    private func startRecap() {
        let config = recapConfig()
        let convo = ChatConversation(config: config)
        // Freestyle chats title as "Freies Gespräch"; a recap deserves its own name in the list.
        convo.title = "Wochenrückblick"
        modelContext.insert(convo)
        try? modelContext.save()
        recapChat = ActiveChat(conversation: convo, config: config)
    }

    /// A freestyle chat pre-seeded with the week's weak grammar tags. The coach memory (recent words
    /// + slips) and any SRS-due words are injected automatically by `ConversationEngine` at session
    /// start, so this only needs to steer toward the shaky structures the recap is meant to revisit.
    private func recapConfig() -> ConversationConfig {
        let manager = coordinator.modelManager
        var config = ConversationConfig(model: manager.selectedChatModel)
        config.mode = .freestyle
        config.focusAreas = weakFocuses
        config.level = CEFRLevel(rawValue: manager.chatLevelRaw) ?? .a2
        config.formality = Formality(rawValue: manager.chatFormalityRaw) ?? .du
        config.correctionsEnabled = manager.chatCorrectionsEnabled
        config.correctionTranslationEnabled = manager.chatShowCorrectionTranslation
        config.strictness = CorrectionStrictness(rawValue: manager.chatStrictnessRaw) ?? .balanced
        config.autoPlay = manager.autoPlayReplies
        config.eagerAssist = manager.chatEagerAssist
        config.autoShowTranslation = manager.chatAutoShowTranslation
        config.hintCount = manager.chatHintCount
        return config
    }
}

// MARK: - Stat tile

/// One growth figure: a big value with a delta chip versus last week, over a tinted card. Kept
/// deliberately flat and adaptive so it reads in both light and dark and inside a grouped List.
private struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    let delta: Int
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                deltaChip
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// "▲ +3" when up, "▼ 2" when down, and nothing when flat — deltas only appear when there's a
    /// change worth noticing.
    @ViewBuilder
    private var deltaChip: some View {
        if delta > 0 {
            Label("+\(delta)", systemImage: "arrow.up")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
        } else if delta < 0 {
            Label("\(delta)", systemImage: "arrow.down")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
