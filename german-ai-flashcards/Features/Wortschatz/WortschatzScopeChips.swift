//
//  WortschatzScopeChips.swift
//  german-ai-flashcards
//
//  The two pill strips that set what the box studies: levels on one line, word classes on the
//  next. Multi-select, and the last pill in each strip can't be turned off — an empty scope would
//  study nothing. Progress outside the scope is kept, not lost.
//

import SwiftUI

struct WortschatzScopeChips: View {
    @Binding var scope: WortschatzScope

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            strip {
                ForEach(GoetheLevel.allCases) { level in
                    FilterPill(
                        label: level.rawValue,
                        tint: .blue,
                        isOn: scope.levels.contains(level),
                        showsClearGlyph: false
                    ) {
                        set { $0.toggle(level) }
                    }
                }
            }
            strip {
                ForEach(GoetheWordType.allCases) { type in
                    FilterPill(
                        label: type.label,
                        tint: .purple,
                        isOn: scope.wordTypes.contains(type),
                        showsClearGlyph: false
                    ) {
                        set { $0.toggle(type) }
                    }
                }
            }
        }
    }

    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func set(_ change: (inout WortschatzScope) -> Void) {
        var updated = scope
        change(&updated)
        withAnimation(.snappy(duration: 0.25)) { scope = updated }
    }
}

/// Single-select level chips for the browse list: All, or one level.
struct WortschatzLevelChips: View {
    @Binding var level: GoetheLevel?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterPill(label: "All", tint: .blue, isOn: level == nil, showsClearGlyph: false) {
                    withAnimation(.snappy(duration: 0.25)) { level = nil }
                }
                ForEach(GoetheLevel.allCases) { candidate in
                    FilterPill(label: candidate.rawValue, tint: .blue, isOn: level == candidate) {
                        withAnimation(.snappy(duration: 0.25)) {
                            level = level == candidate ? nil : candidate
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

#Preview("Scope chips · 4 themes") {
    @Previewable @State var scope = WortschatzScope.all
    @Previewable @State var level: GoetheLevel? = nil

    return ScrollView {
        VStack(spacing: 24) {
            ForEach(AppTheme.allCases) { theme in
                VStack(alignment: .leading, spacing: 12) {
                    WortschatzScopeChips(scope: $scope)
                    WortschatzLevelChips(level: $level)
                }
                .padding()
                .environment(\.appTheme, theme)
                .background(theme.screenBackground)
            }
        }
    }
}
