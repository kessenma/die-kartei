@testable import DieKarteiCore
import SwiftUI

/// The article table: every cell comes from the shared `GrammarCase.article(_:)`, the same
/// function the iOS Kasus lessons use.
struct FaelleView: View {
    @Environment(\.colorScheme) var scheme

    var body: some View {
        List {
            Section("Bestimmter Artikel") {
                headerRow
                ForEach(GrammarCase.allCases) { kasus in
                    HStack {
                        Text(kasus.short)
                            .fontWeight(.semibold)
                            .foregroundStyle(AndroidPalette.kasus(kasus, dark: scheme == .dark))
                            .frame(width: 48, alignment: .leading)
                        ForEach(Gender.allCases) { gender in
                            Text(kasus.article(gender))
                                .foregroundStyle(AndroidPalette.gender(gender, dark: scheme == .dark))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            Section("Wozu?") {
                // Compose keys must be unique across the whole list, and the table above already
                // uses the cases themselves.
                ForEach(GrammarCase.allCases.map { ($0, "wozu-\($0.rawValue)") }, id: \.1) { kasus, _ in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(kasus.name) · \(kasus.role)")
                            .foregroundStyle(AndroidPalette.kasus(kasus, dark: scheme == .dark))
                        Text(kasus.question)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Die vier Fälle")
    }

    private var headerRow: some View {
        HStack {
            Text("")
                .frame(width: 48)
            ForEach(Gender.allCases) { gender in
                Text(gender.columnLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
