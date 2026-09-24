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
/// query, the range toggle, the Items/Time shading switch, and the day-detail sheet, so a caller
/// only drops in `StreakCalendarSection()`.
///
/// The week/month page offsets live here rather than inside the child views, because the time
/// summary underneath has to describe the range you're actually looking at.
struct StreakCalendarSection: View {
    @Query(sort: \StudyDay.dayStart) private var studyDays: [StudyDay]
    @State private var selectedDay: CalendarDay?
    @State private var weekOffset = 0
    @State private var monthOffset = 0
    @AppStorage("streak.calendarRange") private var range: StreakRange = .month
    @AppStorage("streak.shadeByTime") private var shadeByTime = false
    @Environment(\.appTheme) private var theme

    var body: some View {
        Section {
            Picker("Range", selection: $range) {
                ForEach(StreakRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                calendar
                StreakLegend(shadeByTime: $shadeByTime)
            }
            .padding(.vertical, 4)
            .sheet(item: $selectedDay) { day in
                DayDetailSheet(dayStart: day.date)
            }

            StreakTimeSummary(summary: timeSummary, caption: rangeCaption)
        } header: {
            header
        } footer: {
            Text(range.isTappable
                 ? "Darker means a bigger study day. Tap any day to see what you practiced."
                 : "Darker means a bigger study day. A year at a glance.")
                .font(.caption2)
        }
        .themedListRow()
    }

    @ViewBuilder
    private var calendar: some View {
        switch range {
        case .week:
            WeekStrip(metrics: metrics, offset: $weekOffset, onSelect: select)
        case .month:
            MonthGrid(metrics: metrics, offset: $monthOffset, onSelect: select)
        case .threeMonths:
            StreakGrid(weeks: 13, cell: 17, tappable: true, metrics: metrics, onSelect: select)
        case .year:
            StreakGrid(weeks: 53, cell: 10, tappable: false, metrics: metrics, onSelect: select)
        }
    }

    private func select(_ date: Date) { selectedDay = CalendarDay(date: date) }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your Streak")
                .themedSectionHeader()
            Spacer()
            if streak > 0 {
                Label("\(streak) day\(streak == 1 ? "" : "s")", systemImage: "flame.fill")
                    .themedLabel(.caption.weight(.bold), size: 13)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
        .textCase(nil)
    }

    private var streak: Int { StudyLogService.currentStreak(studyDays) }

    // MARK: Metrics

    private var metrics: DayMetrics {
        var items: [Date: Int] = [:]
        var seconds: [Date: Int] = [:]
        for day in studyDays where day.hasActivity {
            let key = studyCalendar.startOfDay(for: day.dayStart)
            // Every signal the streak counts, summed into one "how much" number. Story reading
            // joins as one unit per minute, which puts a ten-minute read in the same band as ten
            // cards.
            items[key, default: 0] += day.cardsReviewed + day.grammarExercises + day.conversations
                + day.storyQuestions + day.storyMinutes
            seconds[key, default: 0] += day.totalSeconds
        }
        return DayMetrics(items: items, seconds: seconds, byTime: shadeByTime)
    }

    // MARK: Range summary

    /// The half-open span the summary describes — the page you're on for Week/Month, and the
    /// trailing window the heatmap draws for 3-Month/Year.
    private var summaryRange: (start: Date, end: Date) {
        let cal = studyCalendar
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        switch range {
        case .week:
            let monday = cal.date(byAdding: .day, value: 7 * weekOffset,
                                  to: mondayOfWeek(containing: today)) ?? today
            return (monday, cal.date(byAdding: .day, value: 7, to: monday) ?? monday)
        case .month:
            let firstOfThis = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
            let start = cal.date(byAdding: .month, value: monthOffset, to: firstOfThis) ?? firstOfThis
            return (start, cal.date(byAdding: .month, value: 1, to: start) ?? start)
        case .threeMonths:
            let start = cal.date(byAdding: .day, value: -7 * 12,
                                 to: mondayOfWeek(containing: today)) ?? today
            return (start, tomorrow)
        case .year:
            let start = cal.date(byAdding: .day, value: -7 * 52,
                                 to: mondayOfWeek(containing: today)) ?? today
            return (start, tomorrow)
        }
    }

    private var timeSummary: StudyLogService.TimeSummary {
        let span = summaryRange
        return StudyLogService.timeSummary(studyDays, from: span.start, to: span.end)
    }

    /// "this week" / "in October" / "in the last 3 months" — what the total is a total *of*.
    private var rangeCaption: String {
        let cal = studyCalendar
        let today = cal.startOfDay(for: Date())
        switch range {
        case .week:
            if weekOffset == 0 { return "this week" }
            return weekOffset == -1 ? "last week" : "that week"
        case .month:
            if monthOffset == 0 { return "this month" }
            let month = summaryRange.start
            let sameYear = cal.component(.year, from: month) == cal.component(.year, from: today)
            return "in \(Self.captionMonthFormatter.string(from: month))"
                + (sameYear ? "" : " \(cal.component(.year, from: month))")
        case .threeMonths:
            return "in the last 3 months"
        case .year:
            return "in the last year"
        }
    }

    private static let captionMonthFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("LLLL"); return f
    }()
}

// MARK: - Per-day metrics

/// Both "how much" measures for every logged day, plus which one the calendar is currently shaded
/// by. Passed down whole so a cell can shade by one and still describe the other out loud.
struct DayMetrics {
    let items: [Date: Int]
    let seconds: [Date: Int]
    /// Set by the Items/Time switch under the calendar.
    let byTime: Bool

    func itemCount(on date: Date) -> Int { items[studyCalendar.startOfDay(for: date)] ?? 0 }
    func secondsSpent(on date: Date) -> Int { seconds[studyCalendar.startOfDay(for: date)] ?? 0 }

    /// 0…4 shade band for a day, by whichever measure is selected.
    func level(on date: Date) -> Int {
        byTime ? StreakShade.level(forSeconds: secondsSpent(on: date))
               : StreakShade.level(for: itemCount(on: date))
    }

    /// What VoiceOver reads for a cell — always both measures, whichever is being shaded.
    func spokenValue(on date: Date) -> String {
        let count = itemCount(on: date)
        let secs = secondsSpent(on: date)
        guard count > 0 || secs > 0 else { return "No study" }
        var parts: [String] = []
        if count > 0 { parts.append("\(count) items studied") }
        if secs > 0 { parts.append(StudyTimeFormat.long(secs)) }
        return parts.joined(separator: ", ")
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

    /// The same ramp measured in time instead of items: a five-minute sitting is a light day, half
    /// an hour or more is a heavy one. Anything under a minute reads as a light day rather than a
    /// blank one, so a quick drill still shows up.
    static func level(forSeconds seconds: Int) -> Int {
        switch seconds / 60 {
        case ..<0:     return 0
        case 0:        return seconds > 0 ? 1 : 0
        case 1...5:    return 1
        case 6...15:   return 2
        case 16...29:  return 3
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

/// The shade ramp, plus the switch that decides what the ramp measures: how many things you did,
/// or how long you spent.
private struct StreakLegend: View {
    @Binding var shadeByTime: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Text("Less")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: theme.innerRadius(2), style: .continuous)
                    .fill(StreakShade.color(level))
                    .frame(width: 11, height: 11)
            }
            Text("More")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Picker("Shade by", selection: $shadeByTime) {
                Text("Items").tag(false)
                Text("Time").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 116)
        }
    }
}

// MARK: - Range time summary

/// The "how long have I actually spent" line under the calendar: the total for the range on
/// screen, with the two numbers that keep it honest — how many days were active, and the average
/// across those days.
private struct StreakTimeSummary: View {
    let summary: StudyLogService.TimeSummary
    /// "this week" / "in October" — what the total covers.
    let caption: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.subheadline)
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.hasTime ? StudyTimeFormat.long(summary.totalSeconds) : "No time logged")
                    .themedLabel(.headline, size: 17)
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if summary.activeDays > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(summary.activeDays) active day\(summary.activeDays == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if summary.hasTime {
                        Text("avg \(StudyTimeFormat.long(summary.averageSeconds))/day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
    let metrics: DayMetrics
    /// Owned by the section so the time summary can describe the week you paged to.
    @Binding var offset: Int
    let onSelect: (Date) -> Void

    @Environment(\.appTheme) private var theme

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
            CalendarPager(title: title, canGoNext: offset < 0,
                          onPrev: { offset -= 1 }, onNext: { offset += 1 })
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { date in
                    cell(date)
                }
            }
        }
    }

    private var monday: Date {
        cal.date(byAdding: .day, value: 7 * offset, to: mondayOfWeek(containing: Date())) ?? Date()
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
        let level = metrics.level(on: date)
        let seconds = metrics.secondsSpent(on: date)
        let radius = theme.innerRadius(10)   // Grundform squares the day cells off
        return VStack(spacing: 5) {
            Text(Self.weekdayFormatter.string(from: date))
                .font(.caption2)
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(isFuture ? Color(.tertiarySystemFill).opacity(0.4) : StreakShade.color(level))
                .frame(height: 50)
                .overlay(
                    // The week view has room to say how long as well as which day.
                    VStack(spacing: 1) {
                        Text(Self.dayNumFormatter.string(from: date))
                            .font(.callout.weight(.semibold))
                        if seconds > 0 && !isFuture {
                            Text(StudyTimeFormat.short(seconds))
                                .font(.system(size: 9, weight: .medium))
                                .opacity(0.85)
                        }
                    }
                    .foregroundStyle(StreakShade.textColor(level: level, isFuture: isFuture))
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 2)
                )
                .overlay(todayRing(date, cornerRadius: radius))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date.formatted(date: .abbreviated, time: .omitted)))
        .accessibilityValue(Text(isFuture ? "Upcoming" : metrics.spokenValue(on: date)))
        .onTapGesture { if !isFuture { onSelect(date) } }
    }
}

// MARK: - Month grid (big, tappable)

private struct MonthGrid: View {
    let metrics: DayMetrics
    /// Owned by the section so the time summary can describe the month you paged to.
    @Binding var offset: Int
    let onSelect: (Date) -> Void

    @Environment(\.appTheme) private var theme

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
                          canGoNext: offset < 0,
                          onPrev: { offset -= 1 }, onNext: { offset += 1 })
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
        return cal.date(byAdding: .month, value: offset, to: start) ?? start
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
        let level = metrics.level(on: date)
        let radius = theme.innerRadius(9)   // Grundform squares the day cells off
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(isFuture ? Color(.tertiarySystemFill).opacity(0.4) : StreakShade.color(level))
            .frame(height: 42)
            .overlay(
                Text(Self.dayNumFormatter.string(from: date))
                    .themedLabel(.subheadline, size: 15)
                    .foregroundStyle(StreakShade.textColor(level: level, isFuture: isFuture))
            )
            .overlay(todayRing(date, cornerRadius: radius))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(date.formatted(date: .abbreviated, time: .omitted)))
            .accessibilityValue(Text(isFuture ? "Upcoming" : metrics.spokenValue(on: date)))
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
    let metrics: DayMetrics
    let onSelect: (Date) -> Void

    @Environment(\.appTheme) private var theme

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
            let radius = theme.innerRadius(3)
            let square = RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(StreakShade.color(metrics.level(on: date)))
                .frame(width: cell, height: cell)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            cal.isDateInToday(date)
                                ? AnyShapeStyle(.tint)
                                : AnyShapeStyle(Color.primary.opacity(0.06)),
                            lineWidth: cal.isDateInToday(date) ? 1.5 : 0.5
                        )
                )
                .accessibilityLabel(Text(date.formatted(date: .abbreviated, time: .omitted)))
                .accessibilityValue(Text(metrics.spokenValue(on: date)))

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

/// A tinted border shown only when `date` is today, sized to overlay a labeled day cell. Drawn in
/// the ambient `.tint` so it tracks the active theme's accent rather than the fixed app accent.
private func todayRing(_ date: Date, cornerRadius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(
            studyCalendar.isDateInToday(date) ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
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

/// One activity family's share of a day's time, for the sheet's breakdown.
private struct TimeSlice: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let tint: Color
    let seconds: Int
}

/// The "what did I do that day" sheet. Fetches the timestamped records that fall on `dayStart`
/// once, maps them to a unified timeline, and lists them under that day's time on task. Falls back
/// to the `StudyDay` totals for the one case that leaves no per-record trail (cross-deck "Daily
/// Review", which has no deck to hang a `QuizResult` on).
struct DayDetailSheet: View {
    let dayStart: Date

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var exercises: [DayExercise] = []
    @State private var totalSeconds = 0
    @State private var slices: [TimeSlice] = []
    @State private var loaded = false

    @Environment(\.appTheme) private var theme

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
                if exercises.isEmpty && totalSeconds == 0 {
                    ContentUnavailableView(
                        "No study logged",
                        systemImage: "moon.zzz",
                        description: Text("You didn't record any learning on this day.")
                    )
                } else {
                    List {
                        if totalSeconds > 0 {
                            Section {
                                timeHeader
                                ForEach(slices) { slice in
                                    sliceRow(slice)
                                }
                            } header: {
                                Text("Time on task").themedSectionHeader()
                            }
                            .themedListRow()
                        }
                        if !exercises.isEmpty {
                            Section {
                                ForEach(exercises) { ex in
                                    row(ex)
                                }
                            } header: {
                                Text("\(exercises.count) \(exercises.count == 1 ? "activity" : "activities")")
                                    .themedSectionHeader()
                            }
                            .themedListRow()
                        }
                    }
                    .themedListScreen()
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
            let time = Self.loadTime(dayStart: dayStart, context: context)
            totalSeconds = time.total
            slices = time.slices
        }
    }

    /// The day's headline number, with the share bar underneath it.
    private var timeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(StudyTimeFormat.long(totalSeconds))
                    .themedLabel(.title2.weight(.semibold), size: 22)
                Text("studied")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // A single stacked bar: each activity's share of the day, in its own color.
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(slices) { slice in
                        Capsule()
                            .fill(slice.tint)
                            .frame(width: max(3, geo.size.width * shareOf(slice)))
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func shareOf(_ slice: TimeSlice) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(slice.seconds) / Double(totalSeconds)
    }

    private func sliceRow(_ slice: TimeSlice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: slice.icon)
                .font(.footnote)
                .foregroundStyle(slice.tint)
                .frame(width: 22)
            Text(slice.label)
                .font(.subheadline)
            Spacer(minLength: 8)
            Text(StudyTimeFormat.long(slice.seconds))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func row(_ ex: DayExercise) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ex.icon)
                .font(.title3)
                .foregroundStyle(ex.tint)
                .frame(width: 36, height: 36)
                .background(ex.tint.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: theme.innerRadius(9), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.title)
                    .themedLabel(.subheadline, size: 15)
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

    /// The day's time on task, split by activity family. Read straight off the `StudyDay` row —
    /// the same numbers the calendar shades and the range summary totals, so the sheet can never
    /// disagree with the grid above it.
    private static func loadTime(dayStart: Date, context: ModelContext) -> (total: Int, slices: [TimeSlice]) {
        let day = (try? context.fetch(FetchDescriptor<StudyDay>(
            predicate: #Predicate<StudyDay> { $0.dayStart == dayStart }
        )))?.first
        guard let day, day.totalSeconds > 0 else { return (0, []) }

        let candidates: [TimeSlice] = [
            TimeSlice(label: "Cards", icon: "rectangle.on.rectangle.angled", tint: .blue,
                      seconds: day.cardSeconds),
            TimeSlice(label: "Grammar", icon: "checklist", tint: .purple,
                      seconds: day.grammarSeconds),
            TimeSlice(label: "Conversation", icon: "bubble.left.and.bubble.right.fill", tint: .green,
                      seconds: day.conversationSeconds),
            TimeSlice(label: "Stories", icon: "book.pages", tint: .pink,
                      seconds: day.storySeconds),
            TimeSlice(label: "Story questions", icon: "text.badge.checkmark", tint: .orange,
                      seconds: day.storyQuizSeconds),
        ]
        return (day.totalSeconds, candidates.filter { $0.seconds > 0 }.sorted { $0.seconds > $1.seconds })
    }

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

        // Preposition Kasus rounds.
        let prepositionRounds = (try? context.fetch(FetchDescriptor<PrepositionRound>(
            predicate: #Predicate<PrepositionRound> { $0.date >= dayStart && $0.date < end }
        ))) ?? []
        for r in prepositionRounds {
            var parts = ["\(r.questionCount) prepositions", "\(r.firstTryCount)/\(r.questionCount) first try"]
            if r.durationSeconds > 0 { parts.append("\(r.durationSeconds)s") }
            out.append(DayExercise(
                time: r.date,
                icon: "arrow.triangle.branch",
                tint: .purple,
                title: r.topic.isEmpty ? "Präpositionen" : "Präpositionen · \(r.topic)",
                subtitle: parts.joined(separator: " · ")
            ))
        }

        // Kasus path: a story's Finden or Einsetzen, or a unit's Schnellrunde. The title is looked
        // up from the story id, so a renamed story still reads right on old days.
        let kasusRounds = (try? context.fetch(FetchDescriptor<KasusRound>(
            predicate: #Predicate<KasusRound> { $0.date >= dayStart && $0.date < end }
        ))) ?? []
        for r in kasusRounds {
            let step = r.step ?? .fill
            let noun = switch step {
            case .find:  "phrases"
            case .fill:  "articles"
            case .quick: "sentences"
            }
            var parts = ["\(r.askedCount) \(noun)", "\(r.firstTryCount)/\(r.askedCount) first try"]
            if let hint = r.hintLevel { parts.append(hint.germanLabel) }
            if r.durationSeconds > 0 { parts.append("\(r.durationSeconds)s") }
            // "Kasus · Der verlorene Schlüssel · Einsetzen", "Kasus · Schnellrunde · Dativ".
            let title = step == .quick
                ? ["Kasus", step.germanLabel, r.unit?.germanTitle]
                : ["Kasus", KasusStoryBank.bundled.story(id: r.storyID)?.title, step.germanLabel]
            out.append(DayExercise(
                time: r.date,
                icon: r.unit?.symbol ?? "checklist",
                tint: r.unit?.color ?? .purple,
                title: title.compactMap { $0 }.joined(separator: " · "),
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
