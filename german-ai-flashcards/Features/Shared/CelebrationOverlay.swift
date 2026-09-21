//
//  CelebrationOverlay.swift
//  german-ai-flashcards
//
//  The confetti moment. `CelebrationOverlayHost` sits in `ContentView`'s overlay above every
//  tab, reads `CelebrationCenter.shared.current`, and shows the celebration: a dimmed scrim, a
//  Bauhaus-flavored confetti rain (squares, circles, triangles — the preposition scenes' shape
//  vocabulary), and a card with the German headline. Auto-dismisses; tap anywhere dismisses.
//  Reduce Motion keeps the card and skips the rain.
//

import StoreKit
import SwiftUI

/// Drop-in overlay: shows whatever the center is holding, if anything. One instance at the app
/// root covers every tab.
///
/// Also the app's one call site for the App Store rating prompt. `ReviewPromptService` decides
/// *whether* to ask (a dismissed 7-day streak, at most once a version); this decides *when* —
/// after the confetti has cleared, so the system sheet never lands on top of a celebration.
struct CelebrationOverlayHost: View {
    @State private var center = CelebrationCenter.shared
    @State private var reviewPrompt = ReviewPromptService.shared
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        ZStack {
            if let celebration = center.current {
                CelebrationOverlay(celebration: celebration) { center.dismiss() }
                    .transition(.opacity)
            }
        }
        // With no celebration the ZStack is empty, but it still spans the overlay — keep it out of
        // the way of the tab underneath.
        .allowsHitTesting(center.current != nil)
        .onChange(of: reviewPrompt.pending) { _, pending in
            guard pending else { return }
            Task {
                // Long enough for the overlay's fade to finish; short enough to still read as part
                // of the same moment.
                try? await Task.sleep(for: .seconds(0.6))
                reviewPrompt.consume()
                requestReview()
            }
        }
    }
}

struct CelebrationOverlay: View {
    let celebration: Celebration
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            if !reduceMotion {
                ConfettiRain(accent: celebration.accent)
                    .ignoresSafeArea()
            }

            card
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .task {
            try? await Task.sleep(for: .seconds(3.2))
            onDismiss()
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            Image(systemName: celebration.systemImage)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(celebration.accent, in: Circle())
                .shadow(color: celebration.accent.opacity(0.4), radius: 12, y: 4)

            Text(celebration.title)
                .themedLabel(.title2.weight(.bold), size: 24)
                .multilineTextAlignment(.center)

            Text(celebration.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: 320)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius + 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius + 6, style: .continuous)
                .strokeBorder(theme.cardBorderColor, lineWidth: theme.cardBorderWidth)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Confetti

/// Falling Bauhaus confetti: squares, circles and triangles in the celebration accent plus the
/// app's orange/teal/charcoal, one Canvas pass driven by a TimelineView. Purely decorative.
private struct ConfettiRain: View {
    let accent: Color

    private struct Piece {
        var x: Double          // 0…1 across the screen
        var delay: Double      // seconds before it enters
        var fall: Double       // seconds for the full drop
        var size: CGFloat
        var color: Color
        var shape: Int         // 0 square · 1 circle · 2 triangle
        var spin: Double
        var drift: Double
    }

    @State private var pieces: [Piece] = []
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(startedAt)
                for piece in pieces {
                    let local = t - piece.delay
                    guard local > 0 else { continue }
                    let p = local / piece.fall
                    guard p < 1 else { continue }
                    let x = (piece.x + sin(local * 2.1) * 0.03 + piece.drift * p) * size.width
                    let y = -20 + p * (size.height + 40)
                    let fade = p > 0.85 ? max(0, (1 - p) / 0.15) : 1

                    var ctx = context
                    ctx.opacity = fade
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(piece.spin * local))

                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 2, width: piece.size, height: piece.size)
                    switch piece.shape {
                    case 1:
                        ctx.fill(Circle().path(in: rect), with: .color(piece.color))
                    case 2:
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: -piece.size / 2))
                        path.addLine(to: CGPoint(x: piece.size / 2, y: piece.size / 2))
                        path.addLine(to: CGPoint(x: -piece.size / 2, y: piece.size / 2))
                        path.closeSubpath()
                        ctx.fill(path, with: .color(piece.color))
                    default:
                        ctx.fill(Rectangle().path(in: rect), with: .color(piece.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startedAt = Date()
            pieces = (0..<72).map { i in
                Piece(
                    x: Double.random(in: 0...1),
                    delay: Double.random(in: 0...0.7),
                    fall: Double.random(in: 1.8...3.0),
                    size: CGFloat.random(in: 6...12),
                    color: palette[i % palette.count],
                    shape: i % 3,
                    spin: Double.random(in: 2...5) * (i.isMultiple(of: 2) ? 1 : -1),
                    drift: Double.random(in: -0.06...0.06)
                )
            }
        }
    }

    /// The celebration accent woven through the app's own orange/teal/charcoal — the same three
    /// notes the preposition scenes play.
    private var palette: [Color] {
        [accent, .orange, .teal, Color(light: 0x3A362C, dark: 0xC9C3B2), accent.opacity(0.7)]
    }
}

#Preview("Level up") {
    CelebrationOverlay(celebration: .levelUp(level: 7, rank: .entdecker)) {}
}

#Preview("Streak") {
    CelebrationOverlay(celebration: .streak(days: 30)) {}
        .preferredColorScheme(.dark)
}
