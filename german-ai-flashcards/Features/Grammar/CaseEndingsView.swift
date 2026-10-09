//
//  CaseEndingsView.swift
//  german-ai-flashcards
//
//  Kasus · the case-endings table (Nom/Akk/Dat/Gen × m/f/n/pl) and the classroom code that goes
//  with it: the last letters of the definite articles spell rese / nese / mrmn / srsr, and
//  ein-words take the same letters. Ending letters wear their gender color, row labels wear
//  their case color and symbol (both from GrammarPalette). The Schnellrunde is generated from
//  the same `GrammarCase` table (Models/EndingsQuestion.swift), so the two can never disagree;
//  it plays on the drill shell (Features/Grammar/Drill, `Activity.grammarDrill`). This screen is
//  the reference only.
//

import SwiftUI
import SwiftData

/// A word with its ending in the gender color and bold, e.g. de**r**, mein**em**.
private func ending(_ stem: String, _ ending: String, _ gender: Gender) -> AttributedString {
    var tail = AttributedString(ending)
    tail.foregroundColor = gender.color
    tail.inlinePresentationIntent = .stronglyEmphasized
    return AttributedString(stem) + tail
}

private func plain(_ s: String) -> AttributedString { AttributedString(s) }

/// The code word with each letter in its column's gender color.
func codeText(_ kasus: GrammarCase) -> Text {
    var out = AttributedString()
    for (letter, gender) in zip(kasus.code, Gender.allCases) {
        var run = AttributedString(String(letter))
        run.foregroundColor = gender.color
        out += run
    }
    return Text(out)
}

// MARK: - Case label

/// A case's symbol and name in its color: the chip every case lesson uses.
struct CaseLabel: View {
    let kasus: GrammarCase
    var style: Style = .short

    enum Style { case short, name }

    var body: some View {
        Label(style == .short ? kasus.short : kasus.name, systemImage: kasus.symbol)
            .foregroundStyle(kasus.color)
    }
}

// MARK: - Gender tag

/// A noun's gender as a teacher's table writes it (m, f, n, pl) on its gender color. Stands in
/// for the article wherever „der Hund“ would give the answer away.
struct GenderTag: View {
    let gender: Gender

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: gender.symbol)
                .font(.caption2)
            Text(gender.columnLabel)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(gender.color, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gender.genderName)
    }
}

// MARK: - The table

/// The endings table on its own, so the reference screen and the quick lesson share one layout.
/// With `highlight`, the other rows fade back so one case stands out.
///
/// `compact` is Endungen's version inside the story player's tray: smaller type, no code word and
/// no noun-ending line, and each form split where Endungen splits it (d·**em**, ein·**em**), so
/// the table reads like the ending buttons under it. `highlightCell` (Lernhilfe) rings one cell,
/// the gap's case row × gender column, and lets the rest step back.
struct CaseEndingsTable: View {
    var cases: [GrammarCase] = GrammarCase.allCases
    var highlight: GrammarCase?
    var highlightCell: KasusTableCell? = nil
    var compact = false
    /// The pinned reference shows whole definite articles, without extra ending rows.
    var articlesOnly = false
    /// The reference table's 3D pick: the ringed cell, nothing dimmed.
    var selectedCell: KasusTableCell? = nil
    /// Set, every full cell is a button (the reference table builds the tapped form in 3D).
    var onSelectCell: ((KasusTableCell) -> Void)? = nil

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: compact ? 4 : 6, verticalSpacing: compact ? 3 : 14) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(Gender.allCases) { gender in
                    HStack(spacing: 3) {
                        Image(systemName: gender.symbol)
                            .font(.caption2)
                        Text(gender.columnLabel)
                            .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: compact ? 20 : 26)
                    .background(gender.color, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous))
                    .opacity(highlightCell == nil || highlightCell?.genus == gender ? 1 : 0.45)
                    .accessibilityLabel(gender.genderName)
                }
            }
            ForEach(cases) { kasus in
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        // Not `CaseLabel`: inside a List a Label takes the row's wide icon slot,
                        // and „Nom“ truncated to „N…“ in this 62-point column. At the largest
                        // text sizes the icon goes first, then the word shrinks, so it never
                        // breaks into one letter per line.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 3) {
                                Image(systemName: kasus.symbol)
                                Text(kasus.short)
                            }
                            Text(kasus.short)
                            Text(kasus.short)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kasus.color)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(kasus.name)
                        if !compact {
                            codeText(kasus)
                                .font(.title3.weight(.heavy))
                        }
                    }
                    .frame(width: compact ? 50 : 62, alignment: .leading)
                    .opacity(highlightCell == nil || highlightCell?.kasus == kasus ? 1 : 0.45)
                    ForEach(Gender.allCases) { gender in
                        if articlesOnly {
                            Text(kasus.article(gender))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(gender.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 3)
                                .accessibilityLabel("\(kasus.name), \(gender.genderName): \(kasus.article(gender))")
                        } else if compact {
                            compactCell(kasus, gender)
                        } else if let onSelectCell {
                            // Borderless: a List row holding many buttons hands each its own tap.
                            Button {
                                onSelectCell(KasusTableCell(kasus: kasus, genus: gender))
                            } label: {
                                selectable(cell(kasus, gender), kasus: kasus, gender: gender)
                            }
                            .buttonStyle(.borderless)
                            .tint(.primary)
                        } else {
                            cell(kasus, gender)
                        }
                    }
                }
                .opacity(highlight == nil || highlight == kasus ? 1 : 0.3)
            }
        }
    }

    private func cell(_ kasus: GrammarCase, _ gender: Gender) -> some View {
        let article = kasus.article(gender)
        let einEnding = kasus.einEnding(gender)
        let nounEnding: String? = switch (kasus, gender) {
        case (.dativ, .plural):                 "+ n"
        case (.genitiv, .der), (.genitiv, .das): "+ s"
        default:                                nil
        }
        return VStack(spacing: 3) {
            Text(ending(String(article.dropLast()), String(article.suffix(1)), gender))
                .font(.subheadline)
            Text(ending(gender == .plural ? "mein" : "(m)ein", einEnding, gender))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let nounEnding {
                Text(nounEnding)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(gender.color)
            }
        }
        .frame(maxWidth: .infinity)
        .minimumScaleFactor(0.8)
        .lineLimit(1)
    }

    /// The tapped cell, ringed and washed in its case color like Endungen's highlighted one.
    private func selectable(_ content: some View, kasus: GrammarCase, gender: Gender) -> some View {
        let isSelected = selectedCell == KasusTableCell(kasus: kasus, genus: gender)
        let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous)
        return content
            .padding(.vertical, 3)
            .background(isSelected ? kasus.color.opacity(0.16) : .clear, in: shape)
            .overlay {
                if isSelected { shape.strokeBorder(kasus.color, lineWidth: 2) }
            }
            .contentShape(shape)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint("Builds this form in 3D")
    }

    /// d·**em** over ein·**em**; the plural, which has no ein, shows (k)ein·**e**. No ending
    /// reads ein**–**, like Endungen's „–“ button. The highlighted cell is ringed and washed in
    /// its case color with its ending bold.
    private func compactCell(_ kasus: GrammarCase, _ gender: Gender) -> some View {
        let article = kasus.article(gender)
        let einEnding = kasus.einEnding(gender)
        let isLit = highlightCell == KasusTableCell(kasus: kasus, genus: gender)
        let dimmed = highlightCell != nil && !isLit
        let shape = RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous)
        return VStack(spacing: 1) {
            Text(ending("d", String(article.dropFirst()), gender))
                .font(.footnote)
            Text(ending(gender == .plural ? "(k)ein" : "ein", einEnding.isEmpty ? "–" : einEnding, gender))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(isLit ? kasus.color.opacity(0.16) : .clear, in: shape)
        .overlay {
            if isLit { shape.strokeBorder(kasus.color, lineWidth: 2) }
        }
        .opacity(dimmed ? 0.4 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }
}

// MARK: - Reference view

struct CaseEndingsView: View {
    @State private var showKasusCheck = false
    /// The cell built in 3D above the table, nil until one is tapped.
    @State private var selectedCell: KasusTableCell?
    @State private var stem: KasusStemChoice = .definite

    /// The stems the 3D panel offers: the table's two rows, plus kein and dieser.
    private static let panelStems = ["der", "ein", "kein", "mein", "dieser"].compactMap(KasusStemChoice.named)

    var body: some View {
        List {
            Section {
                CaseEndingsTable(selectedCell: selectedCell) { cell in
                    withAnimation(.snappy) { selectedCell = cell }
                }
                .padding(.vertical, 6)
            } footer: {
                Text(kasusRich: "The last letter of each article spells the code on the left. The noun itself changes in two places: **+ n** in the {dat:Dativ} plural, **+ s** on masculine and neuter in the {gen:Genitiv}. Tap a cell to build it in 3D.")
            }
            .themedListRow()

            kasusCheckSection
                .themedListRow()
            einWordSection
                .themedListRow()
            pluralSection
                .themedListRow()
            genitivSection
                .themedListRow()
        }
        .themedListScreen()
        .safeAreaInset(edge: .top, spacing: 0) {
            if let selectedCell {
                blocksPanel(selectedCell)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationTitle("Kasus · Case Endings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showKasusCheck) {
            KasusCheckSheet()
        }
        .onAppear(perform: applyDebugCell)
    }

    /// The tapped cell as blocks, pinned above the list so scrolling never recycles the canvas.
    /// ein has no plural, so its plural cell shows kein's.
    private func blocksPanel(_ cell: KasusTableCell) -> some View {
        let choice = cell.genus == .plural && !stem.hasPlural ? KasusStemChoice.named("kein")! : stem
        return VStack(spacing: 6) {
            HStack {
                Text(kasusRich: "{\(cell.kasus.short.lowercased()):\(cell.kasus.name)} · \(cell.genus.genderName)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    withAnimation(.snappy) { selectedCell = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the 3D word")
            }
            if let parts = choice.parts(cell.kasus, cell.genus) {
                EndingBlocksScene(state: .built(parts, kasus: cell.kasus, genus: cell.genus),
                                  framing: choice.allParts)
                    .frame(height: 130)
            }
            Picker("Word", selection: $stem) {
                ForEach(Self.panelStems) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// `-kasus.debugCell dat:m` opens the table with that cell built.
    private func applyDebugCell() {
        #if DEBUG
        guard selectedCell == nil, let raw = UserDefaults.standard.string(forKey: "kasus.debugCell") else { return }
        let fields = raw.lowercased().split(separator: ":").map(String.init)
        guard fields.count == 2,
              let kasus = GrammarCase.allCases.first(where: { $0.short.lowercased() == fields[0] }),
              let genus = Gender(columnLabel: fields[1]) else { return }
        selectedCell = KasusTableCell(kasus: kasus, genus: genus)
        #endif
    }

    /// Which row of the table: the Kasus-Check's six questions in short, then one sentence run
    /// through them. The full card, with examples and traps, is a tap away.
    private var kasusCheckSection: some View {
        Section {
            ForEach(KasusCheckSheet.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(step.id)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .trailing)
                    Text(kasusRich: step.short)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    HStack(spacing: 8) {
                        // Not `CaseLabel`: inside a List a Label takes the row's wide icon slot.
                        ForEach(step.answers, id: \.kasus) { answer in
                            HStack(spacing: 2) {
                                Image(systemName: answer.kasus.symbol)
                                Text(answer.kasus.short)
                            }
                            .foregroundStyle(answer.kasus.color)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(answer.kasus.name)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .fixedSize()
                }
                .padding(.vertical, 1)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(ending("De", "r", .der) + plain(" Mann gibt ") + ending("de", "m", .das)
                     + plain(" Kind ") + ending("ein", "en", .der) + plain(" Ball."))
                    .font(.body)
                HStack(spacing: 14) {
                    caseChip(.nominativ, "der Mann")
                    caseChip(.dativ, "dem Kind")
                    caseChip(.akkusativ, "einen Ball")
                }
                Text(kasusRich: "No preposition, nothing hangs on another noun. *Der Mann* is the **subject** → {nom:Nominativ}. *dem Kind* is the **receiver** → {dat:Dativ}. *einen Ball* is none of these → {akk:Akkusativ}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            Button {
                showKasusCheck = true
            } label: {
                Label("Der Kasus-Check · with examples", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.medium))
            }
        } header: {
            Text("Welcher Fall? · Which case?")
                .themedSectionHeader()
        } footer: {
            Text("Ask in order; the first question that fits decides the case.")
        }
    }

    private func caseChip(_ kasus: GrammarCase, _ phrase: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // Not `CaseLabel`: inside a List a Label takes the row's wide icon slot.
            HStack(spacing: 3) {
                Image(systemName: kasus.symbol)
                Text(kasus.short)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kasus.color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kasus.name)
            Text(phrase)
                .font(.caption)
        }
    }

    private var einWordSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(kasusRich: "*ein, mein, dein, kein* and friends take the **same code letters** as the article: {m:den} → {m:einen}, {m:dem} → {m:einem}, {f:der} → {f:einer}.")
                    .font(.subheadline)
                Text(kasusRich: "Three spots have **no ending** at all: masculine {nom:Nominativ} and neuter {nom:Nominativ} and {akk:Akkusativ}.")
                    .font(.subheadline)
                Text(ending("De", "r", .der) + plain(" Hund → ein Hund   ·   ") + ending("da", "s", .das) + plain(" Kind → ein Kind"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("ein-Wörter · ein-words")
                .themedSectionHeader()
        }
    }

    private var pluralSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(plain("die Kinder → mit ") + ending("de", "n", .plural) + plain(" ") + ending("Kinder", "n", .plural))
                    .font(.subheadline)
                Text(kasusRich: "Plurals that already end in **-n** or **-s** stay as they are: *mit* {pl:den} *Frauen*, *mit* {pl:den} *Autos*.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            HStack(spacing: 6) {
                Image(systemName: GrammarCase.dativ.symbol)
                    .foregroundStyle(GrammarCase.dativ.color)
                Text("Dativ Plural · + n")
                    .themedSectionHeader()
            }
        }
    }

    private var genitivSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(plain("das Auto ") + ending("de", "s", .der) + plain(" ") + ending("Mann", "es", .der)
                     + plain("  ·  die Tasche ") + ending("de", "r", .die) + plain(" Frau"))
                    .font(.subheadline)
                Text(kasusRich: "**Masculine** and **neuter** nouns add **-s** (short words often **-es**). **Feminine** and **plural** nouns don't change. In everyday speech „*von* {m:dem} *Mann*“ often replaces it; writing and exams expect the {gen:Genitiv}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            HStack(spacing: 6) {
                Image(systemName: GrammarCase.genitiv.symbol)
                    .foregroundStyle(GrammarCase.genitiv.color)
                Text("Genitiv · B1")
                    .themedSectionHeader()
            }
        }
    }
}

// MARK: - Drill

// MARK: - Previews

#Preview("Case endings") {
    NavigationStack { CaseEndingsView() }
        .inMemoryModelContainer(for: [LearnerProfile.self, StudyDay.self])
}

#Preview("Case endings · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack { CaseEndingsView() }
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
    .inMemoryModelContainer(for: [LearnerProfile.self, StudyDay.self])
}
