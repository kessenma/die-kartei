import SwiftUI

/// Full-screen overlay while an interview chat gets its recruiter on the line: the tutor loads
/// into memory, then writes its opening. Same treatment as the story and flashcard overlays
/// (near-opaque themed ground, brand glow, phase rail), with a "call connecting" motif that
/// takes its icon from the interview format.
struct RecruiterWarmupView: View {
    var config: ConversationConfig
    /// True while the model loads; false while the recruiter writes the opening line.
    var isLoadingModel: Bool
    var loadProgress: Double?
    var loadInfo: String?
    var onCancel: (() -> Void)?

    @Environment(\.appTheme) private var appTheme

    private var accent: Color { config.model.theme.accent }

    var body: some View {
        ZStack {
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
                RecruiterCallAnimation(
                    format: config.interviewFormat,
                    accent: accent,
                    typing: !isLoadingModel
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

                detailChips

                StoryPhaseRail(
                    steps: [.init(icon: "arrow.down.circle"), .init(icon: "text.bubble")],
                    currentIndex: isLoadingModel ? 0 : 1,
                    activeFill: activeFill,
                    accent: accent
                )

                if isLoadingModel, let onCancel {
                    Button(role: .destructive, action: onCancel) {
                        Label("Cancel", systemImage: "stop.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
            .padding(28)
        }
    }

    // MARK: Copy

    private var title: String {
        if isLoadingModel {
            switch config.interviewFormat {
            case .phone:    return "Dialing the recruiter…"
            case .video:    return "Joining the video call…"
            case .inPerson: return "Walking into the interview…"
            case nil:       return "Getting the recruiter on the line…"
            }
        }
        switch config.interviewRound {
        case .technical: return "The team lead is opening the round…"
        case .final:     return "The hiring manager is opening the round…"
        default:         return "The recruiter is opening the conversation…"
        }
    }

    private var subtitle: String {
        if isLoadingModel {
            return loadInfo ?? "Loading \(config.model.rawValue) into memory"
        }
        if let company = config.jobCompany?.trimmingCharacters(in: .whitespacesAndNewlines), !company.isEmpty {
            return "Reading the posting from \(company)"
        }
        return "Reading the posting"
    }

    /// Round, format, and title as small labelled chips, so the wait says what is being set up.
    private var detailChips: some View {
        HStack(spacing: 8) {
            if let round = config.interviewRound {
                chip(round.label, systemImage: round.systemImage)
            }
            if let format = config.interviewFormat {
                chip(format.label, systemImage: format.systemImage)
            }
        }
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accent.opacity(0.12), in: appTheme.pillShape)
    }

    private var activeFill: Double? {
        guard isLoadingModel, let loadProgress, loadProgress > 0 else { return nil }
        return min(max(loadProgress, 0), 1)
    }
}

// MARK: - Animation

/// The format's icon in a badge, with rings spreading outward like a ringing call, and a
/// typing indicator beneath once the model is in memory and composing. Driven by a timeline
/// rather than timers, so it pauses cleanly under Reduce Motion.
private struct RecruiterCallAnimation: View {
    let format: InterviewFormat?
    let accent: Color
    let typing: Bool

    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var badgeFill: Color {
        appTheme == .klar ? Color(.secondarySystemBackground) : appTheme.surface
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                // Soft brand glow, as behind the card stack and the story scenes.
                Ellipse()
                    .fill(accent)
                    .frame(width: 240, height: 150)
                    .opacity(0.18)
                    .blur(radius: 45)

                ForEach(0..<3, id: \.self) { ring in
                    let progress = reduceMotion
                        ? (Double(ring) + 0.5) / 3
                        : (t / 2.6 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(accent.opacity((1 - progress) * 0.55), lineWidth: 1.5)
                        .frame(width: 96 + 150 * progress, height: 96 + 150 * progress)
                }

                Circle()
                    .fill(badgeFill)
                    .frame(width: 96, height: 96)
                    .overlay(Circle().strokeBorder(accent.opacity(0.45), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)

                Image(systemName: format?.systemImage ?? "briefcase.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(accent)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && !typing)

                if typing {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { dot in
                            Circle()
                                .fill(accent)
                                .frame(width: 8, height: 8)
                                .opacity(reduceMotion ? 0.7 : 0.3 + 0.7 * abs(sin((t * 1.6 + Double(dot) * 0.33) * .pi)))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(badgeFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 1))
                    .offset(y: 78)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: typing)
        }
    }
}

#Preview("Loading · phone") {
    var config = ConversationConfig(model: .hero)
    config.mode = .interview
    config.jobCompany = "Digital Workforce Group"
    config.interviewRound = .technical
    config.interviewFormat = .phone
    return RecruiterWarmupView(config: config, isLoadingModel: true, loadProgress: 0.4, loadInfo: "Loading weights…", onCancel: {})
}

#Preview("Opening · video") {
    var config = ConversationConfig(model: .hero)
    config.mode = .interview
    config.jobCompany = "Digital Workforce Group"
    config.interviewRound = .screening
    config.interviewFormat = .video
    return RecruiterWarmupView(config: config, isLoadingModel: false, loadProgress: nil, loadInfo: nil, onCancel: nil)
}
