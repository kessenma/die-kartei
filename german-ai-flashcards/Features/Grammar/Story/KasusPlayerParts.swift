//
//  KasusPlayerParts.swift
//  german-ai-flashcards
//
//  The pieces the story player's steps share, so Lesen, Markieren, Endungen and Ergebnis look
//  like one screen:
//
//    KasusStepClock     time on one step, paused while the learner is on another
//    KasusTray          the bottom tray: chips, buttons and explanations live here, never in the text
//    KasusFooterLabel   a secondary action's label when it moves into the pinned footer
//    KasusNoteLine      a small ⓘ line in the tray
//    KasusStoryHeader   the story's title, its English, level and unit
//    KasusOptionsMenu   the pill that holds the help level and the feedback mode, remembered per
//                       exercise
//

import SwiftUI

// MARK: - Clock

/// Time spent on one step, paused while the learner is on another, so Markieren and Endungen
/// never bank each other's minutes when the step bar hops between them.
struct KasusStepClock {
    private var banked: TimeInterval = 0
    private var runningSince: Date?

    /// From zero, running.
    mutating func restart() {
        banked = 0
        runningSince = Date()
    }

    mutating func resume() {
        if runningSince == nil { runningSince = Date() }
    }

    mutating func pause() {
        guard let runningSince else { return }
        banked += Date().timeIntervalSince(runningSince)
        self.runningSince = nil
    }

    var seconds: Int {
        max(0, Int(banked + (runningSince.map { Date().timeIntervalSince($0) } ?? 0)))
    }
}

// MARK: - Tray

/// The bottom tray: where case labels, chips, options and explanations live, so the story text
/// above never has to make room for them. Past `maxHeight` (the largest text sizes on a small
/// phone) the content scrolls instead of covering the story; the `footer`, the step's main
/// button, always stays in view under it.
struct KasusTray<Content: View, Footer: View>: View {
    var spacing: CGFloat = 10
    var maxHeight: CGFloat = .infinity
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if maxHeight.isFinite {
                KasusCappedScroll(maxHeight: maxHeight, spacing: spacing) {
                    content()
                }
            } else {
                content()
            }
            footer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if appTheme == .klar {
                Rectangle().fill(.bar).ignoresSafeArea()
            } else {
                appTheme.surface.ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) { Divider() }
    }
}

extension KasusTray where Footer == EmptyView {
    init(spacing: CGFloat = 10, maxHeight: CGFloat = .infinity, @ViewBuilder content: @escaping () -> Content) {
        self.init(spacing: spacing, maxHeight: maxHeight, content: content, footer: { EmptyView() })
    }
}

/// A secondary action's label for the tray's pinned footer, used at the accessibility sizes
/// (Lösung zeigen, Noch mal, Alle Fälle): the German with its icon where it fits, the icon alone
/// where it doesn't. There a long explanation above can scroll, but never these out of sight.
struct KasusFooterLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .fixedSize()
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A small ⓘ line in the tray, in the `KasusRich` markup.
struct KasusNoteLine: View {
    let text: String

    var body: some View {
        Label {
            Text(kasusRich: text)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Header

/// „Der verlorene Schlüssel“, then "The lost key · A2 · Dativ".
struct KasusStoryHeader: View {
    let story: KasusStory
    let unit: KasusUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(story.title)
                .font(.title2.weight(.bold))
            // A tutor-written story says so, and has no English title yet.
            Text([story.source == .generated ? "KI-Geschichte" : nil,
                  story.titleEnglish.isEmpty ? nil : story.titleEnglish,
                  story.level, unit.germanTitle].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An exercise's instruction: the German line (the class sheet's) over the English one, both in
/// the `KasusRich` markup.
struct KasusInstruction: View {
    let german: String
    let english: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kasusRich: german)
                .font(.headline)
            Text(kasusRich: english)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Options

/// The exercise's settings in one small pill: the help level (Endungen only) and the feedback
/// mode, each remembered by the caller. A setting that can't change mid-round is shown but
/// disabled, with a line saying why.
struct KasusOptionsMenu: View {
    /// The levels to offer; empty hides the help section (Markieren).
    var hintLevels: [KasusHintLevel] = []
    var hint: KasusHintLevel? = nil
    var hintLocked = false
    let mode: KasusFeedbackMode
    var modeLocked = false
    var onHint: (KasusHintLevel) -> Void = { _ in }
    let onMode: (KasusFeedbackMode) -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Menu {
            if !hintLevels.isEmpty {
                Picker(selection: Binding(get: { hint ?? hintLevels[0] }, set: onHint)) {
                    ForEach(hintLevels) { level in
                        Text("\(level.germanLabel) · \(level.englishLabel)").tag(level)
                    }
                } label: {
                    Text("Hilfe · Help")
                }
                .pickerStyle(.inline)
                .disabled(hintLocked)
            }
            Picker(selection: Binding(get: { mode }, set: onMode)) {
                ForEach(KasusFeedbackMode.allCases) { option in
                    Text("\(option.germanLabel) · \(option.englishLabel)").tag(option)
                }
            } label: {
                Text("Rückmeldung · Feedback")
            }
            .pickerStyle(.inline)
            .disabled(modeLocked)
            if hintLocked || modeLocked {
                Text("Finish or restart this round to change the rest.")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                Text(summary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.tint.opacity(0.12), in: appTheme.pillShape)
            .contentShape(appTheme.pillShape)
        }
        .accessibilityLabel("Options")
        .accessibilityValue(summary)
    }

    /// „Viel Hilfe · Sofort“, or just „Am Ende“.
    private var summary: String {
        [hint?.germanLabel, mode.germanLabel].compactMap { $0 }.joined(separator: " · ")
    }
}
