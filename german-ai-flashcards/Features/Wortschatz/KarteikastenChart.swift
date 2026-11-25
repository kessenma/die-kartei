//
//  KarteikastenChart.swift
//  german-ai-flashcards
//
//  Der Karteikasten: seven compartments, one bar each, so the learner can see their words move
//  from new to known. Hand-drawn, like every chart in the app.
//

import SwiftUI

struct KarteikastenChart: View {
    let buckets: [WortschatzService.Bucket]

    @Environment(\.appTheme) private var theme

    private var maxCount: Int { max(1, buckets.map(\.count).max() ?? 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(buckets) { bucket in
                VStack(spacing: 4) {
                    Text("\(bucket.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(bucket.count == 0 ? .tertiary : .secondary)
                    RoundedRectangle(cornerRadius: theme.innerRadius(4), style: .continuous)
                        .fill(bucket.color.opacity(bucket.id == 0 ? 0.45 : 0.9))
                        .frame(height: barHeight(bucket.count))
                    Text(bucket.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 132, alignment: .bottom)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Der Karteikasten")
        .accessibilityValue(buckets.map { "\($0.label): \($0.count)" }.joined(separator: ", "))
    }

    private func barHeight(_ count: Int) -> CGFloat {
        guard count > 0 else { return 6 }
        return max(8, CGFloat(count) / CGFloat(maxCount) * 84)
    }
}

#Preview("Karteikasten · 4 themes") {
    let sample = [
        (0, "Neu", 1900), (1, "1 T.", 40), (2, "3 T.", 62), (3, "7 T.", 88),
        (4, "14 T.", 51), (5, "20 T.", 30), (6, "Bekannt", 210),
    ].map { WortschatzService.Bucket(id: $0.0, label: $0.1, count: $0.2, color: WortschatzService.bucketColor($0.0)) }

    return ScrollView {
        VStack(spacing: 24) {
            ForEach(AppTheme.allCases) { theme in
                KarteikastenChart(buckets: sample)
                    .padding()
                    .environment(\.appTheme, theme)
                    .background(theme.screenBackground)
            }
        }
    }
}
