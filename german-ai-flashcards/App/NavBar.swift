//
//  NavBar.swift
//  german-ai-flashcards
//

import SwiftUI

enum MenuTab: String {
    case home, cards, library, conversation, settings
}

// MARK: - Badge shapes

private struct PieProgress: Shape {
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

private struct DownloadBadge: View {
    let progress: Double?

    var body: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.35))
            if let p = progress {
                PieProgress(progress: max(p, 0.06))
                    .fill(Color.accentColor)
                    .animation(.easeInOut, value: p)
            } else {
                Circle().fill(Color.accentColor)
            }
        }
        .frame(width: 13, height: 13)
        .shadow(radius: 1)
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
    var onReselect: ((MenuTab) -> Void)? = nil

    var body: some View {
        HStack {
            navButton(tab: .home, icon: "sparkles.rectangle.stack", selectedIcon: "sparkles.rectangle.stack.fill", label: "Create") {
                if isGenerating {
                    GeneratingBadge()
                }
            }

            navButton(tab: .cards, icon: "rectangle.stack", selectedIcon: "rectangle.stack.fill", label: "Cards")

            navButton(tab: .library, icon: "brain.head.profile", selectedIcon: "brain.head.profile.fill", label: "Library")

            navButton(tab: .conversation, icon: "bubble.left.and.bubble.right", selectedIcon: "bubble.left.and.bubble.right.fill", label: "Talk")

            navButton(tab: .settings, icon: "gearshape.2", selectedIcon: "gearshape.2.fill", label: "Settings") {
                if isDownloading {
                    DownloadBadge(progress: downloadProgress)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 10)
        .padding(.bottom, 16)
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
                        .fill(.tint.opacity(0.12))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
