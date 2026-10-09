//
//  EndungsWerkstattView.swift
//  german-ai-flashcards
//
//  Endungs-Werkstatt · Ending workshop: one determiner in 3D, and three rows of chips to change
//  it. Pick a stem (der, ein, mein, dieser …), a gender and a case; the old ending flies off and
//  the new one snaps onto the stem in its case color. „Durchblättern“ runs one word down the
//  table, Nom → Akk → Dat → Gen, so the learner watches only the ending move.
//
//  The canvas is pinned above the list rather than living in a row, so scrolling never recycles
//  it: one live scene for the whole screen. Bau das Wort (the drill on these blocks) launches
//  from the bottom section.
//

import SwiftUI

struct EndungsWerkstattView: View {
    @Environment(ActivityRouter.self) private var router
    @Environment(\.appTheme) private var appTheme

    @State private var choice: KasusStemChoice = .definite
    @State private var kasus: GrammarCase = .nominativ
    @State private var genus: Gender = .der
    @State private var flipping: Task<Void, Never>?

    var body: some View {
        List {
            caseSection.themedListRow()
            genderSection.themedListRow()
            stemSection.themedListRow()
            buildSection.themedListRow()
        }
        .themedListScreen()
        .safeAreaInset(edge: .top, spacing: 0) { stage }
        .navigationTitle("Endungs-Werkstatt")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: applyDebugPreset)
        .onDisappear { stopFlipping() }
    }

    private var parts: KasusFormParts? { choice.parts(kasus, genus) }

    // MARK: Stage

    private var stage: some View {
        VStack(spacing: 6) {
            if let parts {
                EndingBlocksScene(state: .built(parts, kasus: kasus, genus: genus), framing: choice.allParts)
                    .frame(height: 170)
                Text(kasusRich: caption(parts))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                if let twins = sameForm(parts) {
                    Text(twins)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// „{dat:Dativ} · masculine → d**em**“, the ending in its case color.
    private func caption(_ parts: KasusFormParts) -> String {
        let tag = kasus.markupTag
        let word = parts.hasEnding ? "\(parts.stem){\(tag):\(parts.ending)}" : "\(parts.stem) (no ending)"
        return "{\(tag):\(kasus.name)} · \(genus.genderName) → \(word)"
    }

    /// The other cells with the same word: „die“ is also the feminine Akkusativ. The form alone
    /// doesn't tell you the case; that is what the Kasus-Check is for.
    private func sameForm(_ parts: KasusFormParts) -> String? {
        var twins: [String] = []
        for other in GrammarCase.allCases {
            for gender in Gender.allCases where !(other == kasus && gender == genus) {
                if choice.parts(other, gender)?.word == parts.word {
                    twins.append("\(other.short) \(gender.columnLabel)")
                }
            }
        }
        return twins.isEmpty ? nil : "Same word: \(twins.joined(separator: " · "))"
    }

    // MARK: Pickers

    private var caseSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(GrammarCase.allCases) { option in
                    chip(selected: option == kasus, color: option.color) {
                        stopFlipping()
                        kasus = option
                    } label: {
                        Label(option.short, systemImage: option.symbol)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            Button {
                flipping == nil ? startFlipping() : stopFlipping()
            } label: {
                Label(flipping == nil ? "Durchblättern · Flip through the cases" : "Anhalten · Stop",
                      systemImage: flipping == nil ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.medium))
            }
        } header: {
            Text("Fall · Case").themedSectionHeader()
        } footer: {
            Text("The ending takes the case's color. The stem never changes.")
        }
    }

    private var genderSection: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(Gender.allCases) { option in
                    let allowed = option != .plural || choice.hasPlural
                    chip(selected: option == genus, color: option.color) {
                        genus = option
                    } label: {
                        Label(option.columnLabel, systemImage: option.symbol)
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(!allowed)
                    .opacity(allowed ? 1 : 0.35)
                }
            }
        } header: {
            Text("Genus · Gender").themedSectionHeader()
        } footer: {
            if !choice.hasPlural {
                Text("„\(choice.label)“ has no plural. Use keine or meine instead.")
            } else {
                Text("The plate under the word wears the gender's color.")
            }
        }
    }

    private var stemSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(KasusStemChoice.all) { option in
                        chip(selected: option == choice, color: .accentColor) {
                            choice = option
                            if !option.hasPlural && genus == .plural { genus = .der }
                        } label: {
                            Text(option.label)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Wort · Word").themedSectionHeader()
        } footer: {
            Text("ein, kein and the possessives share one set of endings. dieser, jeder and welcher take der's.")
        }
    }

    private var buildSection: some View {
        Section {
            ForEach(KasusUnit.allCases) { unit in
                Button {
                    stopFlipping()
                    router.launch(.caseEndings(CaseEndingsSession(unit: unit, style: .bauDasWort)))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: unit.symbol)
                            .foregroundStyle(unit.color)
                            .frame(width: 28)
                        Text("\(unit.germanTitle) · \(unit.casesInPlay.map(\.short).joined(separator: " + "))")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    .font(.subheadline)
                }
            }
        } header: {
            Text("Bau das Wort · Build the word").themedSectionHeader()
        } footer: {
            Text("Ten sentences, each with a gap. Tap the ending that fits and watch it snap onto the stem.")
        }
    }

    private func chip<Content: View>(selected: Bool, color: Color, action: @escaping () -> Void,
                                     @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            label()
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minWidth: 44)
                .foregroundStyle(selected ? .white : color)
                .background(selected ? color : color.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Flip through

    private func startFlipping() {
        flipping = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                let all = GrammarCase.allCases
                kasus = all[((all.firstIndex(of: kasus) ?? 0) + 1) % all.count]
            }
        }
    }

    private func stopFlipping() {
        flipping?.cancel()
        flipping = nil
    }

    /// `-kasus.debugWerkstatt dieser:dat:m` opens on that word (stem label : case short : column);
    /// a fourth field `flip` starts Durchblättern.
    private func applyDebugPreset() {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "kasus.debugWerkstatt") else { return }
        let fields = raw.lowercased().split(separator: ":").map(String.init)
        if let label = fields.first, let picked = KasusStemChoice.named(label) { choice = picked }
        if fields.count > 1, let picked = GrammarCase.allCases.first(where: { $0.short.lowercased() == fields[1] }) {
            kasus = picked
        }
        if fields.count > 2, let picked = Gender(columnLabel: fields[2]) { genus = picked }
        if fields.count > 3, fields[3] == "flip" { startFlipping() }
        #endif
    }
}

private extension GrammarCase {
    /// The KasusRich tag for this case: nom, akk, dat, gen.
    var markupTag: String { short.lowercased() }
}
