//
//  GrammarDayStrip.swift
//  german-ai-flashcards
//
//  The grammar heat grid on Grammatik ▸ Fortschritt: one cell per day, darker for longer.
//
//  It is `StreakGrid` — Home's own contribution grid — handed a grammar-only `DayMetrics`, so the
//  two grids share one shade ramp (`StreakShade`) and can never drift apart. Three deliberate
//  differences from Home's calendar:
//
//    · **Untappable.** `StreakGrid`'s tap opens `DayDetailSheet`, which lists every kind of
//      activity for that day. On a grammar-only screen that would be a lie, so the cells don't
//      invite a tap; the rounds themselves live one row down in Verlauf.
//    · **No range picker.** Home's lives on `StreakCalendarSection` behind the unnamespaced
//      `streak.calendarRange` / `streak.shadeByTime` defaults. Having none here means this strip
//      can't move Home's choice, rather than having to migrate those keys.
//    · **Always shaded by time**, since the question this screen answers is how long.
//
//  `WeekStrip` and `MonthGrid` stay private to Home: both need that section's pager binding.
//

import SwiftUI

struct GrammarDayStrip: View {
    let weeks: Int
    let metrics: DayMetrics

    var body: some View {
        StreakGrid(weeks: weeks, cell: 17, tappable: false, metrics: metrics, onSelect: { _ in })
    }
}

// MARK: - Preview

#Preview("Grammar day strip · 4 themes") {
    /// A plausible quarter: most weekdays touched, a gap, a heavy stretch.
    let metrics: DayMetrics = {
        var seconds: [Date: Int] = [:]
        var items: [Date: Int] = [:]
        let calendar = Calendar.current
        for back in 0..<91 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard weekday != 1, back % 7 != 3, !(20...27).contains(back) else { continue }
            let key = calendar.startOfDay(for: day)
            seconds[key] = [90, 240, 420, 900, 1_500][back % 5]
            items[key] = [4, 10, 18, 26, 31][back % 5]
        }
        return DayMetrics(items: items, seconds: seconds, byTime: true)
    }()

    return TabView {
        ForEach(AppTheme.allCases) { theme in
            List {
                Section {
                    GrammarDayStrip(weeks: 13, metrics: metrics)
                        .padding(.vertical, 6)
                } header: {
                    Text("Grammatik-Tage · Grammar days").themedSectionHeader()
                }
                .themedListRow()
            }
            .themedListScreen()
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}
