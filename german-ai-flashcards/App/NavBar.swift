//
//  NavBar.swift
//  german-ai-flashcards
//

import SwiftUI

enum MenuTab: String {
    case home, library, settings
}

// MARK: - Badge shapes

struct PieProgress: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * progress),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// The circular download/loading badge used on the Settings nav item and, mirrored, on the
/// Settings → Model segment. A determinate pie while downloading, a spinning arc while
/// indeterminate (connecting / loading into memory).
struct DownloadBadge: View {
    let progress: Double?
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.35))
            if let p = progress {
                // Determinate download — pie fill that tracks progress. Drawn in the ambient tint
                // (rather than a hard-coded accent) so it picks up the app theme and the loaded
                // model's color wherever the badge is shown.
                PieProgress(progress: max(p, 0.06))
                    .fill(.tint)
                    .animation(.easeInOut, value: p)
            } else {
                // Indeterminate (connecting / loading into memory) — a spinning arc.
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .padding(1.5)
                    .rotationEffect(.degrees(spin ? 360 : 0))
            }
        }
        .frame(width: 13, height: 13)
        .shadow(radius: 1)
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

private struct GeneratingBadge: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 9, height: 9)
            .scaleEffect(pulsing ? 1.3 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .shadow(radius: 1)
    }
}

// MARK: - NavBar

struct NavBar: View {
    @Binding var selectedTab: MenuTab
    var isGenerating: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double? = nil
    /// Brand theme of the model loaded in memory, or `nil` when none is ready. Tints the selected
    /// tab (icon, label, and the highlight pill) with the model's colors so the bar reflects which
    /// model is active. Falls back to the app accent when nil.
    var modelTheme: ModelTheme? = nil
    var onReselect: ((MenuTab) -> Void)? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack {
            navButton(tab: .home, icon: "house", selectedIcon: "house.fill", label: "Home") {
                // Generation can be kicked off from Home, so keep the generating pulse here. The
                // download badge lives only on Settings (where the model status screen is), so users
                // learn to look there for load progress.
                if isGenerating {
                    GeneratingBadge()
                }
            }

            navButton(tab: .library, icon: "brain.head.profile", selectedIcon: "brain.head.profile.fill", label: "Library")

            navButton(tab: .settings, icon: "gearshape.2", selectedIcon: "gearshape.2.fill", label: "Settings") {
                if isDownloading {
                    DownloadBadge(progress: downloadProgress)
                }
            }
        }
        .tint(theme.accent(model: modelTheme))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        // Docked against the very bottom of the display (ContentView lets the bar's column run
        // through the bottom safe area), so this padding — not the home-indicator inset — is what
        // sets how high the tabs sit. Enough to clear the indicator, no more.
        .padding(.bottom, 20)
        .background(barBackground)
        .animation(.easeInOut(duration: 0.3), value: modelTheme?.accent)
    }

    // MARK: - Theming
    //
    // The bar is a slab docked to the bottom edge, not a grouped card, so it sizes its own geometry
    // through `innerRadius(20)` rather than the card `cornerRadius`. Klar returns every value the
    // bar already used, which is what keeps the baseline theme untouched.

    /// How far the background runs past the bottom safe area. Enough to carry the shape's bottom
    /// edge — and its border — off-screen, so the bar reads as rising from the screen edge rather
    /// than as a slab with a hairline drawn along the bottom of the display.
    private static let bottomBleed: CGFloat = 8

    /// Only the top corners are rounded: the bar meets the bottom of the screen, so there is no
    /// bottom edge left to round.
    private var barShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: theme.innerRadius(20),
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: theme.innerRadius(20),
            style: .continuous
        )
    }

    /// Klar keeps the frosted material it has today; the identity themes take their own opaque
    /// surface (plus Kritzel's ink line and Grundform's black rule) so the bar reads as part of
    /// the theme instead of a system component floating above it.
    ///
    /// The whole background — fill, border, and shadow — bleeds down through the home-indicator
    /// strip, which is what closes the gap content used to scroll into underneath the bar. The
    /// shadow has to be drawn here rather than on the composed bar: applied outside, its silhouette
    /// would be the button row alone and it would cast a line across the middle of the bar.
    private var barBackground: some View {
        Group {
            if theme == .klar {
                barShape.fill(.ultraThinMaterial)
            } else {
                barShape
                    .fill(theme.surface)
                    .overlay(barShape.strokeBorder(theme.cardBorderColor, lineWidth: theme.cardBorderWidth))
            }
        }
        .shadow(color: barShadow.color, radius: barShadow.radius, y: barShadow.y)
        .padding(.bottom, -Self.bottomBleed)
        .ignoresSafeArea(edges: .bottom)
    }

    /// Klar's tuple is SwiftUI's own `.shadow(radius: 10)` default, spelled out so the bar renders
    /// identically while the other themes drop in their card shadow (Grundform: none, by design).
    private var barShadow: (color: Color, radius: CGFloat, y: CGFloat) {
        theme == .klar ? (Color(.sRGBLinear, white: 0, opacity: 0.33), 10, 0) : theme.cardShadow
    }

    /// Fill for the selected tab's highlight pill: the model's brand gradient when a model is loaded
    /// *and* the theme defers to it, otherwise a faint wash of the theme's own tint.
    private var selectedTabFill: AnyShapeStyle {
        if theme.usesModelAccent, let modelTheme {
            AnyShapeStyle(modelTheme.linear.opacity(0.18))
        } else {
            AnyShapeStyle(.tint.opacity(theme == .grundform ? 0.20 : 0.12))
        }
    }

    @ViewBuilder
    private func navButton<Badge: View>(
        tab: MenuTab,
        icon: String,
        selectedIcon: String,
        label: String,
        @ViewBuilder badge: () -> Badge = { EmptyView() }
    ) -> some View {
        let isSelected = selectedTab == tab

        Button(action: {
            if selectedTab == tab {
                onReselect?(tab)
            } else {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .overlay(alignment: .topTrailing) {
                        badge()
                            .offset(x: 6, y: -6)
                    }
                // Grundform sets its labels in condensed Futura caps, the way it sets section
                // headers; the other themes leave the caption as it is.
                Text(label)
                    .font(theme == .grundform ? theme.titleFont(11) : .caption)
                    .textCase(theme.uppercaseSectionHeaders ? .uppercase : nil)
                    .tracking(theme.uppercaseSectionHeaders ? 0.8 : 0)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: theme.innerRadius(12), style: .continuous)
                        .fill(selectedTabFill)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Preview

/// The bar on all four themes, each over its own ground, with the download badge showing.
#Preview("NavBar · four themes") {
    // Spaced by the background's bleed so the stacked bars don't draw over each other; in the app
    // that bleed runs off the bottom of the screen.
    VStack(spacing: 8) {
        ForEach(AppTheme.allCases) { theme in
            NavBar(
                selectedTab: .constant(.home),
                isGenerating: true,
                isDownloading: true,
                downloadProgress: 0.45
            )
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .background(ThemedBackground())
            .environment(\.appTheme, theme)
        }
    }
}
