//
//  KasusConfusionCard.swift
//  german-ai-flashcards
//
//  The Verwechslungs-Paar card: the two forms mixed up most, how often, and the two-button drill
//  on exactly those forms. On the Grammatik hub under Weiter, and in Coach's Notes above the
//  grammar rows. The analysis is `KasusConfusion`'s; the card only shows it.
//

import SwiftUI

struct KasusConfusionCard: View {
    let pair: KasusConfusionPair
    let session: GrammarDrillSession
    let onPractise: () -> Void

    @Environment(\.appTheme) private var appTheme

    /// The cases the drill spans, for the subtitle.
    private var cases: String {
        if case .endings(let config) = session.variant {
            return config.cases.map(\.short).joined(separator: " + ")
        }
        return session.topic.casesInPlay.map(\.short).joined(separator: " + ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(pair.label)
                        .font(.title3.weight(.semibold))
                    Text("You pick one where the other belongs: \(pair.count) times so far, more than any other pair.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: onPractise) {
                HStack {
                    Text("Üben: \(pair.a) vs \(pair.b) · \(session.kind.meta.roundSize) Sätze")
                    Spacer()
                    Text(cases)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "play.circle.fill")
                }
                .font(.subheadline.weight(.medium))
                .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .accessibilityLabel("Practise \(pair.a) versus \(pair.b), \(session.kind.meta.roundSize) sentences")
        }
        .padding(.vertical, 6)
    }
}

#Preview("Verwechslungs-Paar") {
    List {
        if let session = KasusConfusion.drill(for: KasusConfusionPair(a: "dem", b: "den", count: 9)) {
            Section {
                KasusConfusionCard(pair: KasusConfusionPair(a: "dem", b: "den", count: 9), session: session) {}
            } header: {
                Text("Dein Verwechslungs-Paar · Your mix-up")
            }
        }
    }
}
