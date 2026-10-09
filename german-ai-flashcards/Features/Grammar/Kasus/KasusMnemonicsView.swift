//
//  KasusMnemonicsView.swift
//  german-ai-flashcards
//
//  Merkhilfen · Memory aids: every `KasusMnemonic`, one line each with why it works, never a
//  chart. The ones for every case first, then by case along the path. A pushed screen under the
//  hub's Werkzeuge, and a sheet (`KasusMnemonicsSheet`) for the debug launch argument.
//

import SwiftUI

struct KasusMnemonicsView: View {
    @Environment(\.appTheme) private var appTheme

    /// The aids grouped: for every case, then per case in path order. An aid for two cases
    /// sits under the first of them.
    private var groups: [(title: String, aids: [KasusMnemonic])] {
        var out: [(String, [KasusMnemonic])] = []
        let general = KasusMnemonics.all.filter(\.cases.isEmpty)
        if !general.isEmpty { out.append(("Für alle Fälle · For every case", general)) }
        for kasus in GrammarCase.allCases {
            let aids = KasusMnemonics.all.filter { $0.cases.first == kasus }
            if !aids.isEmpty { out.append(("\(kasus.name) · \(kasus.role)", aids)) }
        }
        return out
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        ForEach(GrammarCase.allCases) { kasus in
                            CaseLabel(kasus: kasus, style: .short)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    Text("Hooks to hang the cases on. Say the ones that stick; leave the rest.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .themedListRow()

            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.aids) { aid in
                        row(aid)
                    }
                } header: {
                    Text(group.title)
                        .themedSectionHeader()
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Merkhilfen · Memory aids")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ aid: KasusMnemonic) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: aid.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(aid.title)
                    .font(.subheadline.weight(.semibold))
                if let scene = aid.scene, let image = PrepositionScene.image(for: scene.asset, state: "dat") {
                    // A still only: the list may hold several, and the lesson plays it.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(1.5)
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .accessibilityHidden(true)
                }
                Text(kasusRich: aid.line)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(kasusRich: aid.why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The same screen as a sheet.
struct KasusMnemonicsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            KasusMnemonicsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

#Preview("Merkhilfen · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack { KasusMnemonicsView() }
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
}
