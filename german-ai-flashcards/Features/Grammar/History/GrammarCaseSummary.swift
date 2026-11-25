//
//  GrammarCaseSummary.swift
//  german-ai-flashcards
//
//  Rounds · answers · right first try, over one bar per case. Two surfaces show it and they must
//  agree, so there is one definition: Verlauf's „Insgesamt“ strip passes the totals for the rounds
//  currently filtered, the Grammatik hub's Fortschritt pane passes the all-time ones. It only
//  renders — the counting lives in `GrammarProgress` and in Verlauf's own reduce.
//
//  The bars are the case path only: a reflexive pick (sich, uns, euch) can't demonstrate a case,
//  so a caller leaves those rounds out of `perCase` while still counting them in the three
//  numbers above.
//

import SwiftUI

struct GrammarCaseSummary: View {
    let rounds: Int
    let answers: Int
    let firstTry: Int
    let perCase: [GrammarCase: KasusRound.CaseTally]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                stat("\(rounds)", rounds == 1 ? "round" : "rounds")
                stat("\(answers)", "answers")
                stat("\(KasusHistoryFormat.percent(firstTry, of: answers))%", "right first try")
            }
            if !perCase.isEmpty {
                CaseTallyBars(perCase: perCase)
            }
        }
        .padding(.vertical, 6)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .themedLabel(.title2.weight(.bold), size: 24)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Case summary · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            List {
                Section {
                    GrammarCaseSummary(
                        rounds: 14, answers: 126, firstTry: 98,
                        perCase: [
                            .nominativ: .init(asked: 31, firstTry: 29),
                            .akkusativ: .init(asked: 44, firstTry: 32),
                            .dativ: .init(asked: 39, firstTry: 28),
                            .genitiv: .init(asked: 12, firstTry: 9),
                        ]
                    )
                } header: {
                    Text("Insgesamt · All time").themedSectionHeader()
                }
                .themedListRow()
            }
            .themedListScreen()
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}
