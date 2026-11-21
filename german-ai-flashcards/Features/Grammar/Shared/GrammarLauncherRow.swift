//
//  GrammarLauncherRow.swift
//  german-ai-flashcards
//
//  The two rows every Grammatik launcher is built from, after five screens hand-rolled the same
//  `HStack` five ways — and drifted: `PrepositionHubView.sourceRow` filled its chip from
//  `Color.accentColor` while tinting the glyph `.tint`, so its chip ignored Sanft, Kritzel and
//  Grundform. `flame` existed in two copies and the level label in two.
//
//    GrammarTaskRow   something to DO: a task drawing (`GrammarTaskArt`) or an SF chip, a ✓ when
//                     it's finishable, and a play glyph / book glyph / nothing at the end
//    GrammarShelfRow  somewhere to GO: an SF chip — or any view, since Präpositionen's row wears a
//                     3D still — the flame, the level label, and a free trailing slot for the
//                     progress dots or a score
//
//  The split is the hierarchy, and it is the one rule to keep when adding a row: **art marks a task
//  you can play, a tinted chip marks a place you can enter or read.** A room, a case, a rule sheet
//  and the endings table keep their chips; an exercise and a Lektion get a drawing.
//
//  Both are labels, not buttons: the caller keeps its own `Button` or `NavigationLink`, so tap
//  behaviour and navigation semantics stay where they were.
//
//  The tail glyph stays `.tint` even on a case-coloured row — that is how these rows already read,
//  and it keeps „this starts something“ one colour across the whole feature.
//

import SwiftUI

// MARK: - The chip

/// A tinted 34pt chip: the leading icon every non-task grammar row has worn since the theme pass.
/// `tint` nil follows the screen's `.tint`, so the theme accent reaches both the glyph and the
/// ground (the bug the hand-rolled copies had).
struct GrammarRowChip: View {
    let symbol: String
    var tint: Color? = nil
    var size: CGFloat = 34

    @Environment(\.appTheme) private var appTheme

    private var style: AnyShapeStyle { tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint) }
    private var ground: AnyShapeStyle {
        tint.map { AnyShapeStyle($0.opacity(0.12)) } ?? AnyShapeStyle(.tint.opacity(0.12))
    }

    var body: some View {
        Image(systemName: symbol)
            .font(size >= 40 ? .title2 : .title3)
            .foregroundStyle(style)
            .frame(width: size, height: size)
            .background(ground, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(size >= 40 ? 10 : 8),
                                                     style: .continuous))
    }
}

/// The coach's "needs work" mark, the same flame Today and the Pyramid use.
struct GrammarRowFlame: View {
    var body: some View {
        Image(systemName: "flame.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel("Needs work")
    }
}

/// „A1–B1“: a span or a level, as a row's trailing note. A label, never a gate.
struct GrammarRowLevel: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Level \(label)")
    }
}

// MARK: - A task

/// A row for something the learner can play or read through: the drawing says what the task is
/// before the tap, the ✓ says whether it's been done.
struct GrammarTaskRow: View {
    /// A task drawing, or a chip for a row that starts something with no drawing of its own (the
    /// galleries and the tuning surfaces).
    enum Icon: Hashable {
        case art(GrammarTaskArt)
        case symbol(String)
    }

    /// How the row ends. `.play` starts a round, `.read` opens a lesson or a sheet, `.none` lets
    /// the list draw its own chevron — the rule `KasusUnitView`'s header already states.
    enum Tail: Hashable { case play, read, none }

    let icon: Icon
    let title: String
    let subtitle: String
    /// Nil where the row isn't finishable, so no ✓ is drawn (a preposition drill you can replay
    /// forever); true/false draws the circle inline with the caption, as Verstehen does.
    var done: Bool? = nil
    var tail: Tail = .play
    /// The row's colour: a unit's case colour, a topic's, a preposition group's. Nil follows `.tint`.
    var tint: Color? = nil
    /// Used by the rooms' Lektion rows, which are a shelf position *and* a task.
    var shaky = false
    var level: String? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The drawing grows with the text, and is dropped entirely at an accessibility size — the rule
    /// the endings table already follows: a row label drops its icon, then shrinks.
    @ScaledMetric(relativeTo: .subheadline) private var artSize: CGFloat = 52

    private var tailSymbol: String? {
        switch tail {
        case .play: "play.circle.fill"
        case .read: "book.pages"
        case .none: nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                switch icon {
                case .art(let art):
                    GrammarTaskArtView(art: art, tint: tint, size: min(artSize, 72))
                case .symbol(let symbol):
                    GrammarRowChip(symbol: symbol, tint: tint)
                        .frame(width: 44, height: 44)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    if let done {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    }
                    Text(subtitle)
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if shaky { GrammarRowFlame() }
            if let level { GrammarRowLevel(label: level) }
            if let tailSymbol {
                Image(systemName: tailSymbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(done.map { "\(title). \($0 ? "Done" : "Not yet")" } ?? title)
    }
}

// MARK: - A place

/// A row for somewhere to go: a room, a case, a topic, a table, the history. The leading slot is 44
/// wide so a bare 3D still and a symbol chip line their titles up.
struct GrammarShelfRow<Icon: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    var shaky: Bool
    var level: String?
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, shaky: Bool = false, level: String? = nil,
         @ViewBuilder icon: @escaping () -> Icon,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.shaky = shaky
        self.level = level
        self.icon = icon
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            icon()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing()
            if shaky { GrammarRowFlame() }
            if let level { GrammarRowLevel(label: level) }
        }
        // The hub padded 2 and the room 4; one value for both.
        .padding(.vertical, 3)
    }
}

extension GrammarShelfRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, shaky: Bool = false, level: String? = nil,
         @ViewBuilder icon: @escaping () -> Icon) {
        self.init(title: title, subtitle: subtitle, shaky: shaky, level: level,
                  icon: icon, trailing: { EmptyView() })
    }
}

// MARK: - Previews

#Preview("Launcher rows · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                List {
                    Section {
                        GrammarTaskRow(icon: .art(.ideaCard), title: "Lektion · The idea",
                                       subtitle: "What this case is · about 2 min",
                                       done: true, tail: .read, tint: CasePalette.color(.dativ))
                        GrammarTaskRow(icon: .art(.wordGap), title: "Schnellrunde · Quick round",
                                       subtitle: "10 Sätze · Nom + Dat",
                                       done: false, tail: .play, tint: CasePalette.color(.dativ))
                        GrammarTaskRow(icon: .art(.beatTheClock), title: "Blitzrunde · Speed round",
                                       subtitle: "60 seconds, as many as you can · best 14",
                                       tail: .play)
                        GrammarTaskRow(icon: .art(.matchPairs), title: "Paare finden · Match",
                                       subtitle: "Verb and preposition, side by side", tail: .none)
                        GrammarTaskRow(icon: .symbol("cube.fill"), title: "Verb-Szenen · Scenes",
                                       subtitle: "No drawing of its own yet", tail: .play)
                        GrammarTaskRow(icon: .art(.ideaCard), title: "Perfekt · Lektion",
                                       subtitle: "The spoken past", tail: .read,
                                       shaky: true, level: "A2")
                    } header: {
                        Text("Üben · Practice").themedSectionHeader()
                    }
                    Section {
                        GrammarShelfRow(title: "③ Dativ · The receiver",
                                        subtitle: "dem · der · dem · den",
                                        shaky: true, level: "A2") {
                            GrammarRowChip(symbol: "gift.fill", tint: CasePalette.color(.dativ))
                        } trailing: {
                            HStack(spacing: 3) {
                                ForEach(0..<4, id: \.self) { i in
                                    Circle()
                                        .strokeBorder(CasePalette.color(.dativ), lineWidth: 1.2)
                                        .background(Circle().fill(i < 2 ? CasePalette.color(.dativ) : .clear))
                                        .frame(width: 7, height: 7)
                                }
                            }
                        }
                        GrammarShelfRow(title: "Die Endungstabelle · The endings table",
                                        subtitle: "Formen · Sinn · Takt, every cell in 3D") {
                            GrammarRowChip(symbol: "tablecells")
                        }
                    } header: {
                        Text("Nachschlagen · Look it up").themedSectionHeader()
                    }
                }
                .themedListScreen()
                .navigationTitle("Launcher rows")
                .navigationBarTitleDisplayMode(.inline)
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
}

/// The drawing drops out and the text stays: the ✓ and the tail glyph are what an accessibility
/// reader relies on, so neither moves.
#Preview("Launcher rows · accessibility size") {
    NavigationStack {
        List {
            GrammarTaskRow(icon: .art(.wordGap), title: "Schnellrunde · Quick round",
                           subtitle: "10 Sätze · Nom + Dat", done: false, tail: .play,
                           tint: CasePalette.color(.dativ))
            GrammarTaskRow(icon: .art(.ideaCard), title: "Lektion · The idea",
                           subtitle: "What this case is · about 2 min", done: true, tail: .read,
                           tint: CasePalette.color(.dativ))
            GrammarShelfRow(title: "③ Dativ · The receiver", subtitle: "dem · der · dem · den",
                            shaky: true, level: "A2") {
                GrammarRowChip(symbol: "gift.fill", tint: CasePalette.color(.dativ))
            }
        }
        .themedListScreen()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
