import SwiftUI

// MARK: - Environment keys

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .klar
}

private struct ModelThemeKey: EnvironmentKey {
    static let defaultValue: ModelTheme? = nil
}

extension EnvironmentValues {
    /// The active app-wide theme. Injected once at the app root; read by every `.themed*` modifier.
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }

    /// The loaded model's brand theme, if any. Lets `.themedScreen()` resolve the tint for themes
    /// that defer their accent to the model (`klar`). Defaults to `nil` (no model / no override),
    /// which keeps Klar's tint at the system accent until the shell wires this in (Phase 2).
    var modelTheme: ModelTheme? {
        get { self[ModelThemeKey.self] }
        set { self[ModelThemeKey.self] = newValue }
    }
}

// MARK: - Themed background

/// Paints the active theme's ground: a flat fill for most themes, plus Kritzel's ruled-paper lines.
/// Used behind `.themedScreen()`; also usable standalone where a raw themed surface is wanted.
struct ThemedBackground: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            Rectangle().fill(theme.screenBackground)
            if theme == .kritzel {
                RuledPaperOverlay()
            }
        }
    }
}

/// Faint blue rules with a red margin — the notebook motif. Purely decorative, never interactive.
///
/// The rules are phased to the **screen**, not to this view's own frame, so the app shell's ground
/// and a screen's own ground land their lines on top of each other instead of doubling into a
/// darker, denser ruling wherever the two overlap.
private struct RuledPaperOverlay: View {
    private let spacing: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let originY = geo.frame(in: .global).minY
            Canvas { context, size in
                let ruleColor = Color(hex: 0x9CC0E6).opacity(0.35)
                // Where the screen-anchored ruling crosses this view's top edge.
                var y = spacing - originY.truncatingRemainder(dividingBy: spacing)
                if y >= spacing { y -= spacing }
                while y < size.height {
                    if y > 0 {
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(ruleColor), lineWidth: 0.75)
                    }
                    y += spacing
                }
                var margin = Path()
                margin.move(to: CGPoint(x: 44, y: 0))
                margin.addLine(to: CGPoint(x: 44, y: size.height))
                context.stroke(margin, with: .color(Color(hex: 0xE7A6A0).opacity(0.5)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Screen

private struct ThemedScreen: ViewModifier {
    @Environment(\.appTheme) private var theme
    @Environment(\.modelTheme) private var model

    func body(content: Content) -> some View {
        content
            .background(ThemedBackground().ignoresSafeArea())
            .fontDesign(theme.bodyDesign)     // nil is a no-op; only Sanft rounds its body
            .tint(theme.accent(model: model))
    }
}

// MARK: - Card

private struct ThemedCard: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        let shadow = theme.cardShadow
        return content
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .strokeBorder(theme.cardBorderColor, lineWidth: theme.cardBorderWidth)
            )
            .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
            .rotationEffect(theme.cardRotation)
    }
}

// MARK: - List row

/// The `List`/`Form` counterpart to `.themedCard()`. A grouped row already has a system-drawn
/// background, so a card *inside* it would double-draw; this replaces that background instead.
///
/// Each row becomes its **own** card rather than one slab per section: inset a hair vertically, and
/// with the system separator hidden — a hairline drawn across the gap between two rounded surfaces
/// (or on top of Kritzel's ink line) reads as a mistake. On Klar it does nothing at all, so grouped
/// screens keep the exact system chrome — separators, insets, selection highlights — they have today.
private struct ThemedListRow: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        if theme == .klar {
            content
        } else {
            content
                .listRowSeparator(.hidden)
                .listRowBackground(
                    // `groupedRowRadius` (≥ the section clip), not `cornerRadius`: a grouped section
                    // is clipped to a rounded rect we don't control (~21pt on iOS 27), so a squarer
                    // border gets its outer corners cut into an unstroked "ear" on the section's
                    // first and last rows. Matching the clip makes the border follow the rounded
                    // corner cleanly. Free-standing `.themedCard()` stays square.
                    RoundedRectangle(cornerRadius: theme.groupedRowRadius, style: .continuous)
                        .fill(theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.groupedRowRadius, style: .continuous)
                                .strokeBorder(theme.cardBorderColor, lineWidth: theme.cardBorderWidth)
                        )
                        .padding(.vertical, 2)
                )
        }
    }
}

/// A `List` that lets the themed ground behind it show through. Klar keeps the system grouped
/// background, since its ground *is* that background and hiding it would lose the inset chrome.
private struct ThemedListBackground: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(theme == .klar ? .visible : .hidden)
            .themedScreen()
    }
}

// MARK: - Section header

/// Klar passes the header straight through — a grouped `List` uppercases its headers by default,
/// and overriding `textCase` here would silently un-uppercase every screen that adopts this. The
/// identity themes take their own face (where they have one) and their own casing.
private struct ThemedSectionHeader: ViewModifier {
    @Environment(\.appTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme == .klar {
            content
        } else {
            content
                .font(theme.hasDisplayFace ? theme.titleFont(13) : nil)
                .textCase(theme.uppercaseSectionHeaders ? .uppercase : nil)
                .tracking(theme.uppercaseSectionHeaders ? 1.5 : 0)
        }
    }
}

// MARK: - Text font helpers

private struct ThemedTitle: ViewModifier {
    @Environment(\.appTheme) private var theme
    let size: CGFloat
    func body(content: Content) -> some View { content.font(theme.titleFont(size)) }
}

private struct ThemedNumber: ViewModifier {
    @Environment(\.appTheme) private var theme
    let size: CGFloat
    func body(content: Content) -> some View { content.font(theme.numberFont(size)) }
}

/// For labels that **already have** a font in the current design — row titles, button captions,
/// stat figures. Only the themes with a display face of their own swap it out; Klar and Sanft keep
/// `base` untouched, which is what lets an existing screen adopt the theme without changing on the
/// baseline. Use `.themedTitle(_:)` instead when the caller wants a display face unconditionally.
private struct ThemedLabel: ViewModifier {
    @Environment(\.appTheme) private var theme
    let base: Font
    let size: CGFloat
    func body(content: Content) -> some View {
        content.font(theme.hasDisplayFace ? theme.titleFont(size) : base)
    }
}

// MARK: - Public API

extension View {
    /// Screen container: paints the themed ground, rounds body text where the theme wants it, and
    /// sets the tint. Replaces ad-hoc `.background(Color(.systemGroupedBackground))`. For a `List`/
    /// `Form`, pair with `.scrollContentBackground(.hidden)` so the themed ground shows through.
    /// A no-op-equivalent on Klar.
    func themedScreen() -> some View { modifier(ThemedScreen()) }

    /// Card/row surface: themed fill, border, corner radius, shadow, and Kritzel tilt. Replaces
    /// bespoke `RoundedRectangle` fills — use it on free-standing cards, not on `List` rows.
    func themedCard() -> some View { modifier(ThemedCard()) }

    /// The `List`-row form of `.themedCard()`: swaps the grouped row's system background for the
    /// theme's surface. A no-op on Klar. Apply to a row, or to a whole `Section` to cover its rows.
    func themedListRow() -> some View { modifier(ThemedListRow()) }

    /// Screen container for a `List`/`Form`: hides the scroll background (except on Klar, where it
    /// *is* the ground) and paints the themed one behind it. Use in place of `.themedScreen()` on
    /// grouped screens.
    func themedListScreen() -> some View { modifier(ThemedListBackground()) }

    /// Section-header type: the theme's title face, uppercased with tracking on Grundform.
    func themedSectionHeader() -> some View { modifier(ThemedSectionHeader()) }

    /// The theme's title face at `size` — for headings and hero words.
    func themedTitle(_ size: CGFloat) -> some View { modifier(ThemedTitle(size: size)) }

    /// The theme's numeral face at `size` — for big streak counts and scores.
    func themedNumber(_ size: CGFloat) -> some View { modifier(ThemedNumber(size: size)) }

    /// Re-fonts an existing label: `base` on Klar and Sanft, the theme's display face at `size` on
    /// Kritzel and Grundform. The migration workhorse — it themes a screen's type without moving
    /// the baseline. Pass the font the label already used as `base`.
    func themedLabel(_ base: Font, size: CGFloat) -> some View {
        modifier(ThemedLabel(base: base, size: size))
    }
}

// MARK: - Foundation proof preview

/// Throwaway proof that `titleFont` renders per theme: SF on System, SF Rounded on Soft,
/// Noteworthy on Notebook, Futura on Bauhaus — and that the ground/card tokens differ. Remove once
/// real screens carry their own four-theme previews.
#Preview("Theme foundation") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(AppTheme.allCases) { theme in
                VStack(alignment: .leading, spacing: 8) {
                    Text(theme.label.uppercased())
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Hallo, Welt")
                        .themedTitle(28)
                    Text("128")
                        .themedNumber(40)
                        .foregroundStyle(theme.accent(model: nil))
                    HStack(spacing: 6) {
                        ForEach(Gender.allCases) { g in
                            Text(g.article)
                                .font(.headline)
                                .foregroundStyle(g.color)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .themedCard()
                .padding()
                .frame(maxWidth: .infinity)
                .background(theme.screenBackground)
                .environment(\.appTheme, theme)
            }
        }
    }
}
