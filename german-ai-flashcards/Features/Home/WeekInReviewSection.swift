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
//  A from–until picker can swap the rolling week for any window; the comparison then becomes the
//  equally long window before it, and the header, footer, headline, and "of N" all follow, so the
//  section never describes a range it isn't showing.
//

import SwiftUI
import SwiftData

struct WeekInReviewSection: View {
    @Bindable var coordinator: GenerationCoordinator

    @Environment(\.modelContext) private var modelContext

    @Query private var studyDays: [StudyDay]
    @Query(sort: \ChatConversation.createdAt, order: .reverse) private var conversations: [ChatConversation]
    @Query private var profiles: [LearnerProfile]

    @Environment(\.appTheme) private var theme

    /// Set to launch the recap chat once its config + conversation are built.
    @State private var recapChat: ActiveChat?

    // MARK: Range
    //
    // Default is the rolling last-7-days window the section was built around. Picking either date
    // flips `usesCustomRange`, and the section then reports on that window against the equally long
    // one before it. Deliberately *not* persisted: a custom range is a "let me look at something"
    // action, and the honest default to come back to is always this week.

    @State private var rangeStart = Self.defaultStart
    @State private var rangeEnd = Self.defaultEnd
    @State private var usesCustomRange = false
    @State private var isRangeExpanded = false

    private static var defaultEnd: Date { Calendar.current.startOfDay(for: Date()) }
    private static var defaultStart: Date {
        Calendar.current.date(byAdding: .day, value: -6, to: defaultEnd) ?? defaultEnd
    }

    private var review: WeekInReview {
        guard usesCustomRange else {
            return WeekInReviewService.summary(days: studyDays, conversations: conversations)
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: rangeStart)
        // The picker names an inclusive last day; the service window is half-open.
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: rangeEnd)) ?? start
        return WeekInReviewService.summary(
            days: studyDays, conversations: conversations,
            from: start, to: max(end, start), periodLabel: "in this range"
        )
    }

    private var profile: LearnerProfile? { profiles.first }

    var body: some View {
        // Only worth showing once there's a week (or a prior week) to reflect on. A custom range the
        // learner picked themselves always shows, even if it turns out to be empty — otherwise the
        // section would vanish the moment they looked at a quiet stretch, which reads as a bug.
        if usesCustomRange || review.hasActivity || review.hadPriorActivity {
            Section {
                if let headline = review.headline {
                    Label(headline, systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.vertical, 2)
                }

                growthGrid
                    .padding(.vertical, 4)

                rangePicker

                recapButton
            } header: {
                Text(rangeTitle)
                    .themedSectionHeader()
                    .textCase(nil)
            } footer: {
                Text("\(rangeFooterLead) The weekly recap recycles your shakiest grammar and recent words into one chat — spaced practice in a single sitting.")
                    .font(.caption2)
            }
            .themedListRow()
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

    // MARK: - Range title, footer, and picker

    /// "This Week" by default; the actual dates once the learner picks a range, so the header can
    /// never claim "week" about a window that isn't one.
    private var rangeTitle: String {
        guard usesCustomRange else { return "This Week" }
        return "\(Self.rangeFormatter.string(from: rangeStart)) – \(Self.rangeFormatter.string(from: rangeEnd))"
    }

    private var rangeFooterLead: String {
        let n = review.dayCount
        return usesCustomRange
            ? "These \(n) day\(n == 1 ? "" : "s") versus the \(n) before them."
            : "Your last 7 days versus the 7 before."
    }

    /// Collapsed to a one-line summary until tapped — the section's job is the growth story, and a
    /// pair of date pickers permanently open would outweigh it.
    private var rangePicker: some View {
        DisclosureGroup(isExpanded: $isRangeExpanded) {
            DatePicker(
                "From",
                selection: Binding(get: { rangeStart }, set: { setStart($0) }),
                in: ...rangeEnd,
                displayedComponents: .date
            )
            DatePicker(
                "Until",
                selection: Binding(get: { rangeEnd }, set: { setEnd($0) }),
                in: rangeStart...Date(),
                displayedComponents: .date
            )
            if usesCustomRange {
                Button("Back to this week", systemImage: "arrow.uturn.backward") {
                    withAnimation { resetRange() }
                }
                .font(.subheadline)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(.teal)
                    .frame(width: 38, height: 38)
                    .background(Color.teal.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: theme.innerRadius(9), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Date range")
                        .themedLabel(.subheadline, size: 15)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(usesCustomRange ? rangeTitle : "Last 7 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Moving either end keeps the window valid and switches the section onto it.
    private func setStart(_ date: Date) {
        rangeStart = date
        if rangeEnd < date { rangeEnd = date }
        usesCustomRange = true
    }

    private func setEnd(_ date: Date) {
        rangeEnd = date
        if rangeStart > date { rangeStart = date }
        usesCustomRange = true
    }

    private func resetRange() {
        rangeStart = Self.defaultStart
        rangeEnd = Self.defaultEnd
        usesCustomRange = false
        isRangeExpanded = false
    }

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMd"); return f
    }()

    // MARK: - Growth grid

    private var growthGrid: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                StatTile(title: "Active days", value: "\(review.activeDays)",
                         detail: "of \(review.dayCount)",
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
                    .background(Color.indigo.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: theme.innerRadius(9), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly recap")
                        .themedLabel(.subheadline, size: 15)
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
        config.learnerName = ConversationConfig.learnerName(from: manager.learnerName)
        config.mode = .freestyle
        config.focusAreas = weakFocuses
        config.level = manager.germanLevel
        config.formality = Formality(rawValue: manager.chatFormalityRaw) ?? .du
        config.correctionsEnabled = manager.chatCorrectionsEnabled
        config.correctionTranslationEnabled = manager.chatShowCorrectionTranslation
        config.strictness = CorrectionStrictness(rawValue: manager.chatStrictnessRaw) ?? .balanced
        config.autoPlay = manager.autoPlayReplies
        config.inputMode = manager.chatInputMode
        config.eagerAssist = manager.chatEagerAssist
        config.autoShowTranslation = manager.chatAutoShowTranslation
        config.hintCount = manager.chatHintCount
        config.autoHints = manager.chatAutoHints
        config.genderColors = manager.chatGenderColors
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

    @Environment(\.appTheme) private var theme

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
                    .themedLabel(.title2.weight(.bold), size: 22)
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
        // The tint wash stays (it's what tells the four figures apart); the theme supplies the
        // geometry and, on Kritzel/Grundform, the rule around it.
        .background(accent.opacity(0.10), in: tileShape)
        .overlay(tileShape.strokeBorder(theme.cardBorderColor, lineWidth: theme.cardBorderWidth))
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.innerRadius(12), style: .continuous)
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
