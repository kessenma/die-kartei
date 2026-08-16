import SwiftUI

/// Full-screen overlay shown while the hero model writes a story. Mirrors the flashcard
/// generation overlay (`GeneratingFlashcardsView`) — same brand glow and card treatment — but with
/// a per-phase animation (see `GeneratingStoryAnimations`), a phase rail, and phase-aware English
/// copy instead of raw German status text.
struct GeneratingStoryView: View {
    var phase: StoryStudyService.Phase
    var progress: Double
    var tokenCount: Int
    var accent: Color
    var imageTarget: Int = 0
    var imageSlot: Int = 0
    var imageStep: Double = 0
    var imageStage: StoryStudyService.ImageStage = .planning
    /// The picture as it's being drawn, on devices that can decode it (see ``ImageGenPreview``).
    /// Nil everywhere else, which is what falls back to the drawn animation.
    var imagePreview: CGImage?
    var imagePreviewID: Int = 0
    var imageThumbs: [CGImage?] = []
    var onStop: (() -> Void)?

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        ZStack {
            // Klar keeps the plain dimmed system backdrop; identity themes paint their ground so the
            // overlay belongs to the same world as the story behind it.
            Group {
                if appTheme == .klar {
                    Color(.systemBackground)
                } else {
                    ThemedBackground()
                }
            }
            .opacity(0.95)
            .ignoresSafeArea()

            VStack(spacing: 22) {
                StoryPhaseAnimation(
                    phase: phase,
                    accent: accent,
                    imageSlot: imageSlot,
                    imageTotal: imageTarget,
                    imageStep: imageStep,
                    imageStage: imageStage,
                    imagePreview: imagePreview,
                    imagePreviewID: imagePreviewID,
                    imageThumbs: imageThumbs
                )
                .frame(height: 210)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .contentTransition(.opacity)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .contentTransition(.opacity)
                }
                .animation(.easeInOut(duration: 0.25), value: subtitle)

                StoryPhaseRail(
                    steps: steps,
                    currentIndex: currentIndex,
                    activeFill: activeFill,
                    accent: accent
                )

                if let onStop, showsStop {
                    Button(role: .destructive, action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
            .padding(28)
        }
    }

    // MARK: - Copy

    private var title: String {
        switch phase {
        case .loadingModel: "Warming up the tutor…"
        case .writing:      "Writing your story…"
        case .questions:    "Creating questions…"
        case .glossary:     "Building the glossary…"
        case .illustrating: "Drawing the pictures…"
        case .done:         "Fertig!"
        case .idle:         ""
        case .failed:       "Something went wrong"
        }
    }

    private var subtitle: String {
        switch phase {
        case .loadingModel:
            "Loading the German model into memory"
        case .writing:
            tokenCount > 0 ? "\(tokenCount) tokens written" : "Getting the first sentence down"
        case .questions:
            "Turning the story into comprehension practice"
        case .glossary:
            "Collecting the words worth knowing"
        case .illustrating:
            illustrationSubtitle
        case .done:
            "Your story is ready"
        case .failed(let message):
            message
        case .idle:
            ""
        }
    }

    private var illustrationSubtitle: String {
        switch imageStage {
        case .planning:
            return "Sketching out the scenes"
        case .loadingPipeline:
            return "Waking up the illustrator"
        case .rendering:
            let percent = Int((min(max(imageStep, 0), 1) * 100).rounded())
            guard imageTarget > 1 else { return "Painting the picture · \(percent)%" }
            return "Picture \(min(imageSlot + 1, imageTarget)) of \(imageTarget) · \(percent)%"
        }
    }

    private var showsStop: Bool {
        switch phase {
        case .loadingModel, .writing, .questions, .glossary, .illustrating: true
        default: false
        }
    }

    // MARK: - Phase rail

    private var steps: [StoryPhaseRail.Step] {
        var steps: [StoryPhaseRail.Step] = [
            .init(icon: "wand.and.stars"),
            .init(icon: "text.alignleft"),
            .init(icon: "questionmark.circle"),
            .init(icon: "character.book.closed"),
        ]
        if imageTarget > 0 { steps.append(.init(icon: "photo")) }
        return steps
    }

    private var currentIndex: Int {
        switch phase {
        case .idle, .loadingModel: 0
        case .writing:             1
        case .questions:           2
        case .glossary:            3
        case .illustrating:        4
        case .done:                steps.count
        case .failed:              -1
        }
    }

    /// Fill of the segment currently running, or `nil` when the step has no measurable
    /// progress — the rail shimmers instead of faking a number.
    private var activeFill: Double? {
        switch phase {
        case .writing:
            // The service only reports progress at step boundaries, so tokens carry the middle.
            guard tokenCount > 0 else { return nil }
            return min(Double(tokenCount) / 700, 0.95)
        case .questions:
            return clamped((progress - 0.55) / 0.30)
        case .illustrating:
            guard imageStage == .rendering, imageTarget > 0 else { return nil }
            return clamped((Double(imageSlot) + min(max(imageStep, 0), 1)) / Double(imageTarget))
        default:
            return nil
        }
    }

    private func clamped(_ value: Double) -> Double { min(max(value, 0), 1) }
}

// MARK: - Phase rail

/// One segment per generation step: filled behind, shimmering or partly filled at the current
/// step, dim ahead. Replaces the single progress bar, which said nothing about what was running.
struct StoryPhaseRail: View {
    struct Step: Identifiable {
        let icon: String
        var id: String { icon }
    }

    var steps: [Step]
    var currentIndex: Int
    var activeFill: Double?
    var accent: Color

    @State private var shimmer = false

    private let segmentWidth: CGFloat = 44
    private let trackHeight: CGFloat = 5

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                VStack(spacing: 7) {
                    Image(systemName: step.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint(for: index))
                        .symbolEffect(.pulse, isActive: index == currentIndex)

                    segment(at: index)
                }
                .frame(width: segmentWidth)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentIndex)
        .onAppear { shimmer = true }
    }

    private func segment(at index: Int) -> some View {
        Capsule()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: segmentWidth, height: trackHeight)
            .overlay(alignment: .leading) {
                if index < currentIndex {
                    Capsule()
                        .fill(accent)
                        .frame(width: segmentWidth, height: trackHeight)
                } else if index == currentIndex {
                    if let fill = activeFill {
                        Capsule()
                            .fill(accent)
                            .frame(width: max(segmentWidth * fill, trackHeight), height: trackHeight)
                            .animation(.easeOut(duration: 0.4), value: fill)
                    } else {
                        // No measurable progress: a highlight travels the segment instead.
                        Capsule()
                            .fill(accent.opacity(0.9))
                            .frame(width: 16, height: trackHeight)
                            .offset(x: shimmer ? segmentWidth - 16 : 0)
                            .animation(
                                .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                value: shimmer
                            )
                    }
                }
            }
            .clipShape(Capsule())
    }

    private func tint(for index: Int) -> Color {
        if index < currentIndex { return accent }
        if index == currentIndex { return accent }
        return .secondary.opacity(0.35)
    }
}
