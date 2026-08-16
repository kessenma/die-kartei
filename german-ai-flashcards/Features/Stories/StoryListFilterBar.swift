import SwiftUI

// MARK: - Filter state

/// The story list's browse filters. Every field nil/false means "show everything", so a fresh
/// `StoryListFilter()` is the whole library — the list the screen showed before filters existed.
struct StoryListFilter: Equatable {
    /// Whether the story's quiz has been finished. `StudyStory.bestScore` is written the first time
    /// a quiz is scored, so its presence *is* the completion record.
    enum QuizState: String, CaseIterable, Identifiable {
        case open, done

        var id: String { rawValue }

        var label: String {
            switch self {
            case .open: "Quiz open"
            case .done: "Quiz done"
            }
        }

        var systemImage: String {
            switch self {
            case .open: "circle.dotted"
            case .done: "checkmark.seal.fill"
            }
        }
    }

    var quiz: QuizState?
    var level: CEFRLevel?
    var genre: StoryGenre?
    var picturesOnly = false

    var isActive: Bool { quiz != nil || level != nil || genre != nil || picturesOnly }

    func matches(_ story: StudyStory) -> Bool {
        if let quiz {
            let completed = story.bestScore != nil
            switch quiz {
            case .open: if completed { return false }
            case .done: if !completed { return false }
            }
        }
        if let level, story.level != level { return false }
        if let genre, story.genre != genre { return false }
        if picturesOnly, story.coverImage == nil { return false }
        return true
    }
}

// MARK: - Filter bar

/// The pill strip above the story list: quiz state, pictures, and level on one line, the story
/// styles on the next — the styles wearing the same icon-on-gradient art as the setup screen's
/// style gallery.
///
/// Only the levels and styles the library actually holds get a pill, so no pill can lead to an
/// empty list. A selected pill carries an ✕ and clears itself on the next tap.
struct StoryFilterBar: View {
    @Binding var filter: StoryListFilter
    /// Levels present in the library, in CEFR order.
    let levels: [CEFRLevel]
    /// Styles present in the library, in `StoryGenre.allCases` order.
    let genres: [StoryGenre]
    /// Whether any story has a picture at all — no pictures, no Pictures pill.
    let hasPictures: Bool

    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelTheme) private var modelTheme

    private var accent: Color { appTheme.accent(model: modelTheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            strip {
                ForEach(StoryListFilter.QuizState.allCases) { state in
                    FilterPill(
                        label: state.label,
                        systemImage: state.systemImage,
                        tint: accent,
                        isOn: filter.quiz == state
                    ) {
                        set { $0.quiz = $0.quiz == state ? nil : state }
                    }
                }

                if hasPictures {
                    groupDivider
                    FilterPill(
                        label: "Pictures",
                        systemImage: "photo",
                        tint: accent,
                        isOn: filter.picturesOnly
                    ) {
                        set { $0.picturesOnly.toggle() }
                    }
                }

                if levels.count > 1 {
                    groupDivider
                    ForEach(levels) { level in
                        FilterPill(
                            label: level.rawValue,
                            tint: level.chipColor,
                            isOn: filter.level == level
                        ) {
                            set { $0.level = $0.level == level ? nil : level }
                        }
                    }
                }
            }

            if genres.count > 1 {
                strip {
                    ForEach(genres) { genre in
                        StyleFilterPill(
                            genre: genre,
                            isOn: filter.genre == genre,
                            isDimmed: filter.genre != nil && filter.genre != genre
                        ) {
                            set { $0.genre = $0.genre == genre ? nil : genre }
                        }
                    }
                }
            }
        }
    }

    /// One horizontally scrolling line of pills, inset to sit under the section header's text.
    private func strip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 16)
            // The selected style pill's ring is drawn on the pill's edge; without a hair of room
            // the strip clips it.
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 2)
    }

    /// Every pill mutates through here so the list rows animate in and out with the pill's own
    /// selected state.
    private func set(_ change: (inout StoryListFilter) -> Void) {
        var updated = filter
        change(&updated)
        withAnimation(.snappy(duration: 0.25)) { filter = updated }
    }
}

// MARK: - Pills

/// One filter pill: tinted when off, filled when on, with an ✕ that reads as "tap to clear".
private struct FilterPill: View {
    let label: String
    var systemImage: String?
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(label)
                if isOn {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? .white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? tint : tint.opacity(0.12), in: appTheme.pillShape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A style pill in the style's own gradient, so the filter row reads as the same family of art as
/// the style gallery. Once a style is picked the others sit back rather than disappear.
private struct StyleFilterPill: View {
    let genre: StoryGenre
    let isOn: Bool
    let isDimmed: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: genre.systemImage)
                    .symbolRenderingMode(.hierarchical)
                Text(genre.label)
                if isOn {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(genre.styleGradient, in: appTheme.pillShape)
            .overlay {
                appTheme.pillShape
                    .stroke(Color.primary.opacity(isOn ? 0.9 : 0), lineWidth: 2)
            }
            .opacity(isDimmed ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(genre.label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Preview

#Preview("Story filters · 4 themes") {
    @Previewable @State var filter = StoryListFilter()

    return ScrollView {
        VStack(spacing: 24) {
            ForEach(AppTheme.allCases) { theme in
                StoryFilterBar(
                    filter: $filter,
                    levels: [.a1, .a2, .b1],
                    genres: [.alltag, .krimi, .maerchen, .scifi],
                    hasPictures: true
                )
                .environment(\.appTheme, theme)
                .padding(.vertical, 8)
                .background(theme.screenBackground)
            }
        }
    }
}
