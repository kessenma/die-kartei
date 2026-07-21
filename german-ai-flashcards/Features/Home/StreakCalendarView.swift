//
//  StreakCalendarView.swift
//  german-ai-flashcards
//
//  A study-streak calendar for the top of the Home hub, with a range toggle: a finger-friendly
//  Week strip and Month grid (big, tappable day cells), plus the GitHub-style contribution heatmap
//  as a side-scrolling 3-Month and (overview-only) Year view. Every view shades a day from empty
//  (a plain "you didn't study" day) up to deep blue by how much was done, reading the same
//  `StudyDay` log the flame streak is built on — so a colored cell and a streak day are always the
//  same thing. Tapping a day opens a breakdown of what was actually practiced that date.
//

import SwiftUI
import SwiftData

// MARK: - Range

/// The four zoom levels the streak calendar offers, chosen by the segmented control.
enum StreakRange: String, CaseIterable, Identifiable {
    case week, month, threeMonths, year
    var id: String { rawValue }

    var label: String {
        switch self {
        case .week:        return "Week"
        case .month:       return "Month"
        case .threeMonths: return "3 Mo"
        case .year:        return "Year"
        }
    }

    /// The dense heatmap views use tiny cells; only the two calendar views (and 3-Month) are big
    /// enough to tap comfortably, so Year stays an overview.
    var isTappable: Bool { self != .year }
}

// MARK: - Section (drop-in for the Home hub's List)

/// The streak calendar packaged as a self-contained `List` section: it owns its own `StudyDay`
/// query, the range toggle, and the day-detail sheet, so a caller only drops in `StreakCalendarSection()`.
struct StreakCalendarSection: View {
    @Query(sort: \StudyDay.dayStart) private var studyDays: [StudyDay]
    @State private var selectedDay: CalendarDay?
    @AppStorage("streak.calendarRange") private var range: StreakRange = .month

    var body: some View {
        Section {
            Picker("Range", selection: $range) {
                ForEach(StreakRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                calendar
                StreakLegend()
            }
            .padding(.vertical, 4)
            .sheet(item: $selectedDay) { day in
                DayDetailSheet(dayStart: day.date)
            }
        } header: {
            header
        } footer: {
            Text(range.isTappable
                 ? "Darker means a bigger study day. Tap any day to see what you practiced."
                 : "Darker means a bigger study day. A year at a glance.")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private var calendar: some View {
        switch range {
        case .week:
            WeekStrip(intensity: intensityByDay, onSelect: select)
        case .month:
            MonthGrid(intensity: intensityByDay, onSelect: select)
        case .threeMonths:
            StreakGrid(weeks: 13, cell: 17, tappable: true, intensity: intensityByDay, onSelect: select)
        case .year:
            StreakGrid(weeks: 53, cell: 10, tappable: false, intensity: intensityByDay, onSelect: select)
        }
    }

    private func select(_ date: Date) { selectedDay = CalendarDay(date: date) }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your Streak")
            Spacer()
            if streak > 0 {
                Label("\(streak) day\(streak == 1 ? "" : "s")", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
        .textCase(nil)
    }

    private var streak: Int { StudyLogService.currentStreak(studyDays) }

    /// `startOfDay → total activities logged that day`. Every signal the streak counts, summed
    /// into one "how much" number that drives the cell's shade. Story reading joins as one unit
    /// per minute, which puts a ten-minute read in the same band as ten cards.
    private var intensityByDay: [Date: Int] {
        let cal = Calendar.current
        var map: [Date: Int] = [:]
        for day in studyDays where day.hasActivity {
            let key = cal.startOfDay(for: day.dayStart)
            map[key, default: 0] += day.cardsReviewed + day.grammarExercises + day.conversations
                + day.storyQuestions + day.storyMinutes
        }
        return map
    }
}

// MARK: - Shade scale

/// The empty → deep-blue ramp, shared by every view and the legend so they never drift.
enum StreakShade {
    /// 0 = nothing, 4 = a heavy day. Buckets are by total items studied.
    static func level(for count: Int) -> Int {
        switch count {
        case 0:        return 0
        case 1...4:    return 1
        case 5...14:   return 2
        case 15...29:  return 3
        default:       return 4
        }
    }

    static func color(_ level: Int) -> Color {
        switch level {
        case 0:  return Color(.tertiarySystemFill) // "you didn't study" — a faint, adaptive blank
        case 1:  return Color.blue.opacity(0.28)
        case 2:  return Color.blue.opacity(0.48)
        case 3:  return Color.blue.opacity(0.70)
        default: return Color.blue.opacity(0.95)
        }
    }

    /// Legible day-number color for a labeled cell: white once the blue is dark, faded for a
    /// future day, primary otherwise.
    static func textColor(level: Int, isFuture: Bool) -> Color {
        if isFuture { return Color.secondary.opacity(0.6) }
        return level >= 3 ? .white : .primary
    }
}

// MARK: - Calendar math helpers

private let studyCalendar = Calendar.current

/// Monday (locale-independent) of the week containing `date`, so rows/strips are always Mon…Sun.
private func mondayOfWeek(containing date: Date) -> Date {
    let day = studyCalendar.startOfDay(for: date)
    let weekday = studyCalendar.component(.weekday, from: day) // 1 = Sun … 7 = Sat
    let daysSinceMonday = (weekday + 5) % 7
    return studyCalendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
}

// MARK: - Legend

private struct StreakLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("Less")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(StreakShade.color(level))
                    .frame(width: 11, height: 11)
            }
            Text("More")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pager header (Week / Month)

/// The `‹ title ›` strip above the paged calendar views. Chevrons are given a wide tap target and
/// the "next" one is disabled at the present so you can't page into the future.
private struct CalendarPager: View {
    let title: String
    let canGoNext: Bool
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            chevron("chevron.left", enabled: true, action: onPrev)
            Spacer()
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            chevron("chevron.right", enabled: canGoNext, action: onNext)
        }
    }

    private func chevron(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
    }
}

// MARK: - Week strip (big, tappable)

private struct WeekStrip: View {
    let intensity: [Date: Int]
    let onSelect: (Date) -> Void

    @State private var weekOffset = 0
    private let cal = studyCalendar

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEE"); return f
    }()
    private static let dayNumFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d"); return f
    }()
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMd"); return f
    }()

    var body: some View {
        VStack(spacing: 10) {
            CalendarPager(title: title, canGoNext: weekOffset < 0,
                          onPrev: { weekOffset -= 1 }, onNext: { weekOffset += 1 })
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { date in
                    cell(date)
                }
            }
        }
    }

    private var monday: Date {
        cal.date(byAdding: .day, value: 7 * weekOffset, to: mondayOfWeek(containing: Date())) ?? Date()
    }

    private var days: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    private var title: String {
        let end = days.last ?? monday
        return "\(Self.monthDayFormatter.string(from: monday)) – \(Self.monthDayFormatter.string(from: end))"
    }

    private func cell(_ date: Date) -> some View {
        let today = cal.startOfDay(for: Date())
        let isFuture = date > today
        let level = StreakShade.level(for: intensity[cal.startOfDay(for: date)] ?? 0)
        return VStack(spacing: 5) {
            Text(Self.weekdayFormatter.string(from: date))
                .font(.caption2)
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isFuture ? Color(.tertiarySystemFill).opacity(0.4) : StreakShade.color(level))
                .frame(height: 50)
                .overlay(
                    Text(Self.dayNumFormatter.string(from: date))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(StreakShade.textColor(level: level, isFuture: isFuture))
                )
                .overlay(todayRing(date, cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if !isFuture { onSelect(date) } }
    }
}

// MARK: - Month grid (big, tappable)

private struct MonthGrid: View {
    let intensity: [Date: Int]
    let onSelect: (Date) -> Void

    @State private var monthOffset = 0
    private let cal = studyCalendar
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdayHeaders = ["M", "T", "W", "T", "F", "S", "S"]

    private static let dayNumFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d"); return f
    }()
    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("LLLL yyyy"); return f
    }()

    var body: some View {
        VStack(spacing: 10) {
            CalendarPager(title: Self.monthTitleFormatter.string(from: firstOfMonth),
                          canGoNext: monthOffset < 0,
                          onPrev: { monthOffset -= 1 }, onNext: { monthOffset += 1 })
            HStack(spacing: 6) {
                ForEach(weekdayHeaders.indices, id: \.self) { i in
                    Text(weekdayHeaders[i])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells.indices, id: \.self) { i in
                    if let date = cells[i] {
                        cell(date)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
    }

    /// Midnight on the 1st of the currently-shown month.
    private var firstOfMonth: Date {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: cal.startOfDay(for: Date()))) ?? Date()
        return cal.date(byAdding: .month, value: monthOffset, to: start) ?? start
    }

    /// Leading `nil` pads (for the weekdays before the 1st) then one entry per day of the month.
    private var cells: [Date?] {
        let weekday = cal.component(.weekday, from: firstOfMonth)
        let leading = (weekday + 5) % 7
        let dayCount = cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        var result: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<dayCount {
            result.append(cal.date(byAdding: .day, value: d, to: firstOfMonth))
        }
        return result
    }

    private func cell(_ date: Date) -> some View {
        let today = cal.startOfDay(for: Date())
        let isFuture = date > today
        let level = StreakShade.level(for: intensity[cal.startOfDay(for: date)] ?? 0)
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isFuture ? Color(.tertiarySystemFill).opacity(0.4) : StreakShade.color(level))
            .frame(height: 42)
            .overlay(
                Text(Self.dayNumFormatter.string(from: date))
                    .font(.subheadline)
                    .foregroundStyle(StreakShade.textColor(level: level, isFuture: isFuture))
            )
            .overlay(todayRing(date, cornerRadius: 9))
            .contentShape(Rectangle())
            .onTapGesture { if !isFuture { onSelect(date) } }
    }
}

// MARK: - Heatmap grid (3-Month / Year)

/// Identifies a tapped cell for the day-detail sheet.
private struct CalendarDay: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

/// The GitHub-style contribution grid: columns are weeks (oldest left), rows are Mon…Sun. Cell
/// size, week span, and tappability are all set by the caller so it can serve both the medium
/// 3-Month view and the tiny Year overview.
private struct StreakGrid: View {
    let weeks: Int
    var cell: CGFloat = 14
    var tappable: Bool = true
    let intensity: [Date: Int]
    let onSelect: (Date) -> Void

    private let spacing: CGFloat = 3
    private let labelWidth: CGFloat = 26
    private let cal = studyCalendar

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM"); return f
    }()

    var body: some View {
        // The weekday key stays pinned outside the scroll so it's always visible, even after the
        // grid auto-scrolls to today.
        HStack(alignment: .top, spacing: spacing) {
            weekdayColumn
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(columns) { col in
                            column(col).id(col.index)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .onAppear {
                    guard let last = columns.last?.index else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(last, anchor: .trailing)
                    }
                }
            }
        }
    }

    // MARK: Columns

    private struct WeekColumn: Identifiable {
        var id: Int { index }
        let index: Int
        /// 7 entries, Mon…Sun. `nil` = a future day (drawn blank to keep the grid rectangular).
        let days: [Date?]
        /// Set on the first column of each month, for the labels along the top.
        let monthLabel: String?
    }

    private var today: Date { cal.startOfDay(for: Date()) }

    private var columns: [WeekColumn] {
        let thisMonday = mondayOfWeek(containing: today)
        let firstMonday = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: thisMonday) ?? thisMonday
        var result: [WeekColumn] = []
        var lastMonth = -1
        for w in 0..<weeks {
            guard let weekStart = cal.date(byAdding: .day, value: 7 * w, to: firstMonday) else { continue }
            var days: [Date?] = []
            for d in 0..<7 {
                let date = cal.date(byAdding: .day, value: d, to: weekStart) ?? weekStart
                days.append(date <= today ? date : nil)
            }
            let month = cal.component(.month, from: weekStart)
            let label = month == lastMonth ? nil : Self.monthFormatter.string(from: weekStart)
            lastMonth = month
            result.append(WeekColumn(index: w, days: days, monthLabel: label))
        }
        return result
    }

    private func column(_ col: WeekColumn) -> some View {
        VStack(spacing: spacing) {
            Text(col.monthLabel ?? "")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false) // let the label overflow its slot
                .frame(width: cell, height: 11, alignment: .leading)
            ForEach(0..<7, id: \.self) { row in
                cellView(col.days[row])
            }
        }
    }

    /// The fixed weekday key on the left (Mon / Wed / Fri, like GitHub).
    private var weekdayColumn: some View {
        VStack(spacing: spacing) {
            Color.clear.frame(width: labelWidth, height: 11) // aligns with the month-label row
            ForEach(0..<7, id: \.self) { row in
                Text(["Mon", "", "Wed", "", "Fri", "", ""][row])
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, height: cell, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ date: Date?) -> some View {
        if let date {
            let count = intensity[cal.startOfDay(for: date)] ?? 0
            let square = RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(StreakShade.color(StreakShade.level(for: count)))
                .frame(width: cell, height: cell)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(
                            cal.isDateInToday(date) ? Color.accentColor : Color.primary.opacity(0.06),
                            lineWidth: cal.isDateInToday(date) ? 1.5 : 0.5
                        )
                )
                .accessibilityLabel(Text(date.formatted(date: .abbreviated, time: .omitted)))
                .accessibilityValue(Text(count == 0 ? "No study" : "\(count) items studied"))

            if tappable {
                square
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(date) }
            } else {
                square
            }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }
}

// MARK: - Today ring (shared by the labeled views)

/// An accent-colored border shown only when `date` is today, sized to overlay a labeled day cell.
private func todayRing(_ date: Date, cornerRadius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
            studyCalendar.isDateInToday(date) ? Color.accentColor : Color.clear,
            lineWidth: 2
        )
}

// MARK: - Day detail

/// One thing the learner did on the tapped day, ready to render as a row.
private struct DayExercise: Identifiable {
    let id = UUID()
    let time: Date
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
}

/// The "what did I do that day" sheet. Fetches the timestamped records that fall on `dayStart`
/// once, maps them to a unified timeline, and lists them. Falls back to the `StudyDay` totals
/// for the one case that leaves no per-record trail (cross-deck "Daily Review", which has no
/// deck to hang a `QuizResult` on).
struct DayDetailSheet: View {
    let dayStart: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var exercises: [DayExercise] = []
    @State private var loaded = false

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE MMMd")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    ContentUnavailableView(
                        "No study logged",
                        systemImage: "moon.zzz",
                        description: Text("You didn't record any learning on this day.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(exercises) { ex in
                                row(ex)
                            }
                        } header: {
                            Text("\(exercises.count) \(exercises.count == 1 ? "activity" : "activities")")
                        }
                    }
                }
            }
            .navigationTitle(Self.titleFormatter.string(from: dayStart))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            exercises = Self.load(dayStart: dayStart, context: context)
        }
    }

    private func row(_ ex: DayExercise) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ex.icon)
                .font(.title3)
                .foregroundStyle(ex.tint)
                .frame(width: 36, height: 36)
                .background(ex.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(ex.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Self.timeFormatter.string(from: ex.time))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Fetch

    private static func load(dayStart: Date, context: ModelContext) -> [DayExercise] {
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        var out: [DayExercise] = []

        // Flashcard reviews and grammar drills both persist as QuizResult (grammar ones hang off a
        // deck tagged `generatorRaw == "grammar"`).
        let quizzes = (try? context.fetch(FetchDescriptor<QuizResult>(
            predicate: #Predicate<QuizResult> { $0.date >= dayStart && $0.date < end }
        ))) ?? []
        for q in quizzes {
            let isGrammar = q.deck?.generatorRaw == "grammar"
            let name = q.deck?.topic ?? q.subDeckLabel ?? (isGrammar ? "Grammar drill" : "Flashcards")
            var parts = ["\(q.totalCards) \(isGrammar ? "questions" : "cards")", "\(q.scorePercentage)%"]
            if q.durationSeconds > 0 { parts.append(q.formattedDuration) }
            out.append(DayExercise(
                time: q.date,
                icon: isGrammar ? "checklist" : "rectangle.on.rectangle.angled",
                tint: isGrammar ? .purple : .blue,
                title: isGrammar ? "Grammar · \(name)" : name,
                subtitle: parts.joined(separator: " · ")
            ))
        }

        // Conversations.
        let chats = (try? context.fetch(FetchDescriptor<ChatConversation>(
            predicate: #Predicate<ChatConversation> { $0.createdAt >= dayStart && $0.createdAt < end }
        ))) ?? []
        for c in chats {
            out.append(DayExercise(
                time: c.createdAt,
                icon: "bubble.left.and.bubble.right.fill",
                tint: .green,
                title: c.title.isEmpty ? "Conversation" : c.title,
                subtitle: "Conversation practice"
            ))
        }

        // Matching rounds.
        let rounds = (try? context.fetch(FetchDescriptor<MatchingRound>(
            predicate: #Predicate<MatchingRound> { $0.date >= dayStart && $0.date < end }
        ))) ?? []
        for r in rounds {
            var parts = ["\(r.pairCount) pairs", "\(r.firstTryCount)/\(r.pairCount) first try"]
            if r.durationSeconds > 0 { parts.append("\(r.durationSeconds)s") }
            out.append(DayExercise(
                time: r.date,
                icon: "square.grid.2x2.fill",
                tint: .orange,
                title: r.topic.isEmpty ? "Card matching" : "Matching · \(r.topic)",
                subtitle: parts.joined(separator: " · ")
            ))
        }

        // Der/die/das article rounds.
        let articleRounds = (try? context.fetch(FetchDescriptor<ArticleRound>(
            predicate: #Predicate<ArticleRound> { $0.date >= dayStart && $0.date < end }
        ))) ?? []
        for r in articleRounds {
            var parts = ["\(r.questionCount) nouns", "\(r.firstTryCount)/\(r.questionCount) first try"]
            if r.durationSeconds > 0 { parts.append("\(r.durationSeconds)s") }
            out.append(DayExercise(
                time: r.date,
                icon: "textformat.abc",
                tint: .indigo,
                title: r.topic.isEmpty ? "Der · Die · Das" : "Der · Die · Das · \(r.topic)",
                subtitle: parts.joined(separator: " · ")
            ))
        }

        // Story reading / listening stretches.
        let reading = (try? context.fetch(FetchDescriptor<StoryReadingSession>(
            predicate: #Predicate<StoryReadingSession> { $0.date >= dayStart && $0.date < end }
        ))) ?? []
        for r in reading {
            var parts = [r.formattedDuration]
            if r.lookups > 0 { parts.append("\(r.lookups) looked up") }
            if r.wordsSaved > 0 { parts.append("\(r.wordsSaved) saved") }
            out.append(DayExercise(
                time: r.date,
                icon: r.wasListening ? "ear" : "book.pages",
                tint: .pink,
                title: r.wasListening ? "Hören · \(r.storyTitle)" : r.storyTitle,
                subtitle: parts.joined(separator: " · ")
            ))
        }

        // Story comprehension quizzes.
        let storyQuizzes = (try? context.fetch(FetchDescriptor<StoryQuizAttempt>(
            predicate: #Predicate<StoryQuizAttempt> { $0.date >= dayStart && $0.date < end }
        ))) ?? []
        for q in storyQuizzes {
            var parts = ["\(q.questionCount) questions", "\(q.scorePercentage)%"]
            if q.durationSeconds > 0 { parts.append(StoryProgressService.formatShort(q.durationSeconds)) }
            out.append(DayExercise(
                time: q.date,
                icon: "checklist",
                tint: .pink,
                title: "Fragen · \(q.storyTitle)",
                subtitle: parts.joined(separator: " · ")
            ))
        }

        // Papers and photo scans.
        let papers = (try? context.fetch(FetchDescriptor<StudyPaper>(
            predicate: #Predicate<StudyPaper> { $0.createdAt >= dayStart && $0.createdAt < end }
        ))) ?? []
        for p in papers {
            out.append(DayExercise(
                time: p.createdAt,
                icon: "doc.text.magnifyingglass",
                tint: .teal,
                title: p.title.isEmpty ? "Study material" : p.title,
                subtitle: "Reading / scan"
            ))
        }

        // Fallback: a day the streak counted but that left no per-record trail (a cross-deck
        // Daily Review). Reconstruct rows from the day's totals so the sheet is never emptier
        // than the calendar shade implies.
        if out.isEmpty {
            let day = (try? context.fetch(FetchDescriptor<StudyDay>(
                predicate: #Predicate<StudyDay> { $0.dayStart == dayStart }
            )))?.first
            if let day, day.hasActivity {
                if day.cardsReviewed > 0 {
                    out.append(DayExercise(
                        time: day.lastActivityAt, icon: "rectangle.on.rectangle.angled", tint: .blue,
                        title: "Flashcard review", subtitle: "\(day.cardsReviewed) cards reviewed"
                    ))
                }
                if day.grammarExercises > 0 {
                    out.append(DayExercise(
                        time: day.lastActivityAt, icon: "checklist", tint: .purple,
                        title: "Grammar practice", subtitle: "\(day.grammarExercises) exercises"
                    ))
                }
                if day.conversations > 0 {
                    out.append(DayExercise(
                        time: day.lastActivityAt, icon: "bubble.left.and.bubble.right.fill", tint: .green,
                        title: "Conversation practice", subtitle: "\(day.conversations) finished"
                    ))
                }
                if day.storySeconds > 0 {
                    out.append(DayExercise(
                        time: day.lastActivityAt, icon: "book.pages", tint: .pink,
                        title: "Story reading",
                        subtitle: StoryProgressService.formatShort(day.storySeconds)
                    ))
                }
            }
        }

        return out.sorted { $0.time < $1.time }
    }
}
