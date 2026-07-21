import SwiftUI

/// A short, self-playing tutorial shown from the info button on screens with interactive German
/// text (conversation, story reading). It teaches the two gestures with looping animations:
///  • **Double-tap a word** → translate it (and save it to the flashcard library).
///  • **Select a phrase** → "Save phrase" → the phrase library.
/// Honors Reduce Motion by showing each demo's end state statically instead of looping.
struct GestureHelpSheet: View {
    /// Context line above the demos, e.g. "Two quick gestures help you learn while you chat."
    let intro: String
    var accent: Color = .accentColor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(intro)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    GestureDemoCard(
                        icon: "hand.tap.fill",
                        title: "Double-tap a word to translate it",
                        caption: "Double-tap any German word to see its meaning — then save it to your flashcard library.",
                        accent: accent
                    ) {
                        DoubleTapDemo(accent: accent, reduceMotion: reduceMotion)
                    }

                    GestureDemoCard(
                        icon: "character.cursor.ibeam",
                        title: "Select a phrase to save it",
                        caption: "Press and drag to select a phrase, then choose “Save phrase” to add it to your phrase library.",
                        accent: accent
                    ) {
                        SelectPhraseDemo(accent: accent, reduceMotion: reduceMotion)
                    }

                    Label(
                        "Saved words become flashcards you can study at the end of the session.",
                        systemImage: "rectangle.stack.badge.plus"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .padding()
            }
            .navigationTitle("Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDetents([.large])
        }
    }
}

// MARK: - Card chrome

private struct GestureDemoCard<Content: View>: View {
    let icon: String
    let title: String
    let caption: String
    let accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)

            content
                .frame(maxWidth: .infinity)
                .padding(.top, 42)   // headroom for the floating bubble / pill
                .padding(.bottom, 8)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Demo A: double-tap to translate

private struct DoubleTapDemo: View {
    let accent: Color
    let reduceMotion: Bool

    private let words = ["Einen", "Kaffee", "bitte."]
    private let targetIndex = 1

    @State private var showRipple = false
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                wordView(word, isTarget: i == targetIndex)
            }
        }
        .font(.title3.weight(.medium))
        .task {
            if reduceMotion {
                revealed = true
            } else {
                await loop()
            }
        }
    }

    @ViewBuilder
    private func wordView(_ word: String, isTarget: Bool) -> some View {
        Text(word)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(accent.opacity(isTarget && revealed ? 0.18 : 0))
            )
            .overlay {
                if isTarget && showRipple { TapRipple() }
            }
            .overlay(alignment: .top) {
                if isTarget && revealed {
                    TranslationBubble(german: "Kaffee", english: "coffee", accent: accent)
                        .fixedSize()
                        .offset(y: -36)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
            }
    }

    private func loop() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.3)) { revealed = false }
            try? await Task.sleep(for: .seconds(0.7))
            showRipple = true                              // double-tap pulses
            try? await Task.sleep(for: .seconds(1.0))
            showRipple = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { revealed = true }
            try? await Task.sleep(for: .seconds(2.0))
        }
    }
}

// MARK: - Demo B: select a phrase to save it

private struct SelectPhraseDemo: View {
    let accent: Color
    let reduceMotion: Bool

    private let words = ["Sonst", "noch", "etwas?"]

    @State private var selectedCount = 0
    @State private var showPill = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                Text(word)
                    .padding(.horizontal, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(accent.opacity(i < selectedCount ? 0.30 : 0))
                    )
            }
        }
        .font(.title3.weight(.medium))
        .overlay(alignment: .top) {
            if showPill {
                SavePhrasePill(accent: accent)
                    .offset(y: -36)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
        }
        .task {
            if reduceMotion {
                selectedCount = words.count
                showPill = true
            } else {
                await loop()
            }
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.3)) { selectedCount = 0; showPill = false }
            try? await Task.sleep(for: .seconds(0.7))
            for n in 1...words.count {                      // selection sweeps across the phrase
                withAnimation(.easeInOut(duration: 0.18)) { selectedCount = n }
                try? await Task.sleep(for: .seconds(0.22))
            }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showPill = true }
            try? await Task.sleep(for: .seconds(2.0))
        }
    }
}

// MARK: - Floating bits

/// A pulsing ring that reads as a finger tapping the word beneath it.
private struct TapRipple: View {
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(Color.primary.opacity(0.55), lineWidth: 2)
            .background(Circle().fill(Color.primary.opacity(0.12)))
            .frame(width: 26, height: 26)
            .scaleEffect(animate ? 1.5 : 0.7)
            .opacity(animate ? 0 : 0.9)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

private struct TranslationBubble: View {
    let german: String
    let english: String
    let accent: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(german).fontWeight(.semibold)
            Image(systemName: "arrow.right").font(.caption2)
            Text(english).foregroundStyle(.secondary)
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

private struct SavePhrasePill: View {
    let accent: Color

    var body: some View {
        Label("Save phrase", systemImage: "ear.badge.waveform")
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
