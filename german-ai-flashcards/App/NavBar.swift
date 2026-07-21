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
                // Determinate download — pie fill that tracks progress.
                PieProgress(progress: max(p, 0.06))
                    .fill(Color.accentColor)
                    .animation(.easeInOut, value: p)
            } else {
                // Indeterminate (connecting / loading into memory) — a spinning arc.
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
        .tint(modelTheme?.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 10)
        .padding(.bottom, 16)
        .animation(.easeInOut(duration: 0.3), value: modelTheme?.accent)
    }

    /// Fill for the selected tab's highlight pill: the model's brand gradient when a model is loaded,
    /// otherwise the standard faint tint wash.
    private var selectedTabFill: AnyShapeStyle {
        if let modelTheme {
            AnyShapeStyle(modelTheme.linear.opacity(0.18))
        } else {
            AnyShapeStyle(.tint.opacity(0.12))
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
                Text(label)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selectedTabFill)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
