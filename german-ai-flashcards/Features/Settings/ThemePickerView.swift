import SwiftUI

/// App ▸ Appearance. Four tappable tiles — one per `AppTheme` — that switch the whole app's look.
/// Each tile previews its theme on its own ground: the sample word in that theme's title face, its
/// swatch strip, and a selection ring in its accent. Bound straight to `@AppStorage`, so the choice
/// persists and every screen reading `\.appTheme` restyles at once. Mirrors `CardStyleCard`.
struct ThemePickerView: View {
    @AppStorage(AppTheme.defaultsKey) private var appTheme: AppTheme = .klar
    @State private var graphicsMode: LightweightGraphics.Mode = LightweightGraphics.mode

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsHeader(icon: "paintpalette", title: "Appearance")

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeCard(theme: theme, isSelected: appTheme == theme) {
                            withAnimation(.snappy) { appTheme = theme }
                        }
                    }
                }

                Text("Sets the whole app's look — backgrounds, cards, and type. Switch anytime; nothing else changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                graphicsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Lives on Appearance rather than beside Memory Saver: this is a look-of-the-app choice made
    /// for its own sake, and only incidentally a memory one.
    private var graphicsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Spelled out as an HStack rather than leaning on the Picker's own label: this screen
            // is a plain VStack, not a Form, and a menu Picker there draws only its value.
            HStack {
                Label("3D scenes", systemImage: "cube")
                    .font(.subheadline)
                Spacer(minLength: 12)
                Picker("3D scenes", selection: $graphicsMode) {
                    ForEach(LightweightGraphics.Mode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .onChange(of: graphicsMode) { _, newValue in
                    LightweightGraphics.mode = newValue
                }
            }
            .padding(.horizontal, 4)

            Text("Die Figur is drawn live in 3D and assembles herself from her own parts. Stills Only swaps that for a flat picture, which costs less memory on smaller phones. \(LightweightGraphics.automaticExplanation)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(.top, 4)
    }
}

/// One theme tile: the sample word in the theme's title face over the theme's ground, a swatch
/// strip, label + subtitle, and a selection ring in the theme's accent.
private struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Hallo")
                        .font(theme.titleFont(24))
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.accent(model: nil))
                    }
                }

                HStack(spacing: 6) {
                    ForEach(Array(theme.previewColors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color)
                            .frame(width: 24, height: 10)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.label)
                        .font(.headline)
                        .lineLimit(1)
                    Text(theme.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .foregroundStyle(.primary)   // grounds are light in light mode / dark in dark, so primary reads on all four
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(theme.screenBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? theme.accent(model: nil) : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 3 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { ThemePickerView() }
}
