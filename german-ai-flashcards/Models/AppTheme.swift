import SwiftUI
import UIKit

// MARK: - AppTheme

/// The app's own visual identity, chosen by the learner in Settings and applied app-wide.
///
/// Sits **beside** `ModelTheme`, never replacing it: `AppTheme` owns the chrome (backgrounds, cards,
/// type, corners, motifs); `ModelTheme` stays the per-model accent. A theme decides via
/// `usesModelAccent` whether to defer its accent to the loaded model or override it with its own.
///
/// Four themes ship together and the picker switches freely — no direction is a one-way door.
/// **`klar` is the untouched baseline:** it returns system-equivalent tokens so every `.themed*`
/// modifier is a no-op on it, which is what lets screens migrate to the modifiers incrementally
/// without regressing the current look.
///
/// Persisted as a raw `String` under `defaultsKey` via `@AppStorage`, mirroring how `CardImageStyle`
/// stores its choice. Injected into the environment at the app root (`\.appTheme`); screens read it
/// through the `.themed*` modifiers in `ThemeEnvironment`.
nonisolated enum AppTheme: String, CaseIterable, Identifiable {
    case klar        // "System"   — the current look, baseline
    case sanft       // "Soft"     — warm & cozy, SF Rounded
    case kritzel     // "Notebook" — hand-drawn, ruled paper
    case grundform   // "Bauhaus"  — geometric, primary-colored

    var id: String { rawValue }

    static let defaultsKey = "app.theme"

    // MARK: Identity copy

    /// Picker label — English, since the German key names carry the identity internally.
    var label: String {
        switch self {
        case .klar:      "System"
        case .sanft:     "Soft"
        case .kritzel:   "Notebook"
        case .grundform: "Bauhaus"
        }
    }

    /// One-liner shown under the label on the picker tile.
    var subtitle: String {
        switch self {
        case .klar:      "The clean iOS look"
        case .sanft:     "Warm and cozy"
        case .kritzel:   "Hand-drawn on ruled paper"
        case .grundform: "Geometric, primary colors"
        }
    }

    // MARK: Surfaces

    /// The screen's ground fill. For Kritzel this is just the flat paper base — the ruled lines are
    /// drawn on top by `ThemedBackground`.
    var screenBackground: AnyShapeStyle {
        switch self {
        case .klar:      AnyShapeStyle(Color(.systemGroupedBackground))
        case .sanft:     AnyShapeStyle(Color(light: 0xF1E9DC, dark: 0x26221D))
        case .kritzel:   AnyShapeStyle(Color(light: 0xFBF9F0, dark: 0x201E18))
        case .grundform: AnyShapeStyle(Color(light: 0xF3EFE6, dark: 0x17150F))
        }
    }

    /// Fill for cards and rows sitting on the ground.
    var surface: Color {
        switch self {
        case .klar:      Color(.secondarySystemGroupedBackground)
        case .sanft:     Color(light: 0xFBF6EE, dark: 0x332E27)
        case .kritzel:   Color(light: 0xFEFCF6, dark: 0x2B2921)
        case .grundform: Color(light: 0xFBF8F1, dark: 0x221F18)
        }
    }

    var cardBorderColor: Color {
        switch self {
        case .klar:      .clear
        case .sanft:     .clear                                  // soft shadow instead of a border
        case .kritzel:   Color(light: 0x3A362C, dark: 0xC9C3B2)  // ink line
        case .grundform: Color(light: 0x141414, dark: 0xECE7DA)  // black rule
        }
    }

    var cardBorderWidth: CGFloat {
        switch self {
        case .klar:      0
        case .sanft:     0
        case .kritzel:   1.5
        case .grundform: 2
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .klar:      10
        case .sanft:     20
        case .kritzel:   6    // 4–8 irregular; the motif pass can jitter this per card
        case .grundform: 0    // sharp, geometric
        }
    }

    /// The radius SwiftUI clips a grouped `List`/`Form` **section** to. Applied above us, to the
    /// section's background *and* its content, with no public knob to change it.
    ///
    /// Measured on-device rather than guessed (iPhone 17 Pro, iOS 27): on a first row, the left
    /// border is clipped away entirely for the first ~14pt and doesn't reach the row's true edge
    /// until ~32pt below the section top — a `.continuous` corner of ~21pt. The old value here was
    /// `10`, from an earlier iOS whose sections were far squarer; that undershoot is exactly what
    /// cut the borders. Rounded up a little: overshooting is free (the card's corner simply sits
    /// inside the clip, over hidden section background), while undershooting cuts the border again.
    private static let systemSectionClipRadius: CGFloat = 22

    /// Corner radius for a themed **grouped-`List`/`Form` row** card only — clamped up to the
    /// section clip above, so the border traces that rounded corner cleanly instead of being sliced
    /// into an unstroked "ear" on a section's first and last rows.
    ///
    /// Free-standing shapes (`.themedCard()`, `innerRadius`, tiles, chips, the six-tile hub) are
    /// **not** clipped, so they keep the theme's true corner — Grundform stays genuinely square
    /// everywhere except inside a grouped list, where square corners are not purchasable: clearing
    /// the clip with a square card costs ~27pt of row width or ~16pt of row height, per row.
    var groupedRowRadius: CGFloat { max(cornerRadius, Self.systemSectionClipRadius) }

    var cardShadow: (color: Color, radius: CGFloat, y: CGFloat) {
        switch self {
        case .klar:      (.clear, 0, 0)
        case .sanft:     (Color.black.opacity(0.10), 12, 6)   // the cozy lift
        case .kritzel:   (Color.black.opacity(0.06), 3, 2)    // a faint sketch drop
        case .grundform: (.clear, 0, 0)                       // flat by design
        }
    }

    /// Kritzel tilts its cards a hair; everything else stays square. A per-card alternating tilt is
    /// left to the Phase 11 motif pass — this is the single-value default.
    var cardRotation: Angle {
        switch self {
        case .kritzel: .degrees(-1)
        default:       .zero
        }
    }

    /// Corner radius for a *small inner shape* — an icon chip, a stat tile, the tab bar and its
    /// selection pill — whose radius in the current design is `base`.
    ///
    /// `cornerRadius` is the **card** token; reusing it on small shapes would swallow them (Sanft's
    /// 20pt on a 34pt chip is a circle). This scales the shape's own radius by the theme's geometry
    /// instead: Klar returns `base` untouched (so every adopting screen stays pixel-identical on the
    /// baseline theme), Sanft softens, Kritzel tightens, Grundform squares off.
    func innerRadius(_ base: CGFloat) -> CGFloat {
        switch self {
        case .klar:      base
        case .sanft:     base * 1.2
        case .kritzel:   max(base * 0.5, 4)
        case .grundform: 0
        }
    }

    // MARK: Type

    /// Display face for titles. Kritzel and Grundform take a custom face; Klar and Sanft stay on SF
    /// (Sanft rounded). Body text stays SF everywhere (see `bodyDesign`) so long German passages
    /// remain legible — only titles, numbers, and headers take the custom face.
    func titleFont(_ size: CGFloat) -> Font {
        switch self {
        case .klar:
            .system(size: size, weight: .bold)
        case .sanft:
            .system(size: size, weight: .bold, design: .rounded)
        case .kritzel:
            Self.firstAvailable(
                ["Noteworthy-Bold", "BradleyHandITCTT-Bold", "MarkerFelt-Wide"],
                size: size, fallbackWeight: .bold
            )
        case .grundform:
            Self.firstAvailable(
                ["Futura-CondensedExtraBold", "Futura-Bold", "Futura-Medium"],
                size: size, fallbackWeight: .heavy
            )
        }
    }

    /// Face for big numerals (streak counts, scores). Same faces as `titleFont`, heavier on the SF
    /// themes so numbers read as a focal point.
    func numberFont(_ size: CGFloat) -> Font {
        switch self {
        case .klar:
            .system(size: size, weight: .heavy)
        case .sanft:
            .system(size: size, weight: .heavy, design: .rounded)
        case .kritzel:
            Self.firstAvailable(
                ["Noteworthy-Bold", "BradleyHandITCTT-Bold", "MarkerFelt-Wide"],
                size: size, fallbackWeight: .bold
            )
        case .grundform:
            Self.firstAvailable(
                ["Futura-CondensedExtraBold", "Futura-Bold"],
                size: size, fallbackWeight: .heavy
            )
        }
    }

    /// Design applied to body text screen-wide via `.themedScreen()`. Only Sanft rounds its body;
    /// `nil` on the rest is a no-op, keeping Kritzel/Grundform body copy in plain SF.
    var bodyDesign: Font.Design? {
        switch self {
        case .sanft: .rounded
        default:     nil
        }
    }

    /// Grundform sets section headers in UPPERCASE with tracking; the rest leave them as-is.
    var uppercaseSectionHeaders: Bool {
        self == .grundform
    }

    /// Whether this theme has a display face of its **own**. Klar is SF by definition, and Sanft
    /// gets its character from `.fontDesign(.rounded)` applied screen-wide rather than from a
    /// separate face — so for both, swapping an existing label's font would be a regression, not a
    /// theme. `.themedLabel(_:size:)` uses this to leave those two labels exactly as they are.
    var hasDisplayFace: Bool {
        self == .kritzel || self == .grundform
    }

    // MARK: Shapes

    /// A capsule — except on Grundform, which has no round corners anywhere, so its pills are
    /// rectangles. For `.background(_:in:)` and `.clipShape(_:)` on chips and CTA buttons.
    var pillShape: AnyShape {
        self == .grundform ? AnyShape(Rectangle()) : AnyShape(Capsule())
    }

    // MARK: Accent

    /// Whether this theme lets the loaded model's brand color drive the tint. Klar does (matching
    /// today); the identity-forward themes override with a color of their own.
    var usesModelAccent: Bool {
        self == .klar
    }

    /// The tint for controls and links. Klar defers to the loaded model (or the system accent when
    /// no model is loaded); the other themes assert their own accent. Grundform's is the der-blue
    /// Bauhaus primary, so its accent and its gender coding are the same color.
    func accent(model: ModelTheme?) -> Color {
        switch self {
        case .klar:      model?.accent ?? .accentColor
        case .sanft:     Color(light: 0xC97C5D, dark: 0xD79170)   // terracotta
        case .kritzel:   Color(light: 0x2E5FA3, dark: 0x7FA6E0)   // ballpoint blue
        case .grundform: GenderPalette.color(.der)                // Bauhaus blue == der
        }
    }

    // MARK: Picker

    /// The swatch strip shown on this theme's picker tile.
    var previewColors: [Color] {
        switch self {
        case .klar:
            [Color(.systemGray4), Color(.systemGray2), .accentColor]
        case .sanft:
            [Color(hex: 0xF1E9DC), Color(hex: 0xC97C5D), Color(hex: 0x6E5A48)]
        case .kritzel:
            [Color(hex: 0xFBF9F0), Color(hex: 0x3A362C), Color(hex: 0x2E5FA3)]
        case .grundform:
            // The Bauhaus primaries, which are also der/die/plural.
            [GenderPalette.color(.der), GenderPalette.color(.die), Color(hex: 0xF2B705)]
        }
    }

    // MARK: Font resolution

    /// First PostScript name in `names` actually installed, as a `Font` at `size`; otherwise a
    /// system fallback. Guards with `UIFont(name:size:)` so we never emit the console warning
    /// `Font.custom` logs for a missing face, and so a renamed/absent face degrades gracefully
    /// instead of silently rendering SF with no signal.
    private static func firstAvailable(
        _ names: [String],
        size: CGFloat,
        fallbackWeight: Font.Weight
    ) -> Font {
        for name in names where UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: fallbackWeight)
    }
}

// MARK: - Color light/dark helper

extension Color {
    /// A color that resolves to `light` in light mode and `dark` in dark mode, each a 24-bit RGB
    /// hex literal. Lets each theme define its own dark tokens instead of naively inverting.
    /// `nonisolated` so the `nonisolated` theme/gender enums can build their tokens off the main actor.
    nonisolated init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hexValue: dark)
                : UIColor(hexValue: light)
        })
    }
}

private extension UIColor {
    nonisolated convenience init(hexValue: UInt) {
        self.init(
            red: CGFloat((hexValue >> 16) & 0xFF) / 255,
            green: CGFloat((hexValue >> 8) & 0xFF) / 255,
            blue: CGFloat(hexValue & 0xFF) / 255,
            alpha: 1
        )
    }
}
