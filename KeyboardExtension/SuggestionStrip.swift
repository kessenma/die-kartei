import SwiftUI

/// The row between the transform buttons and the keys: spelling suggestions, and the switch for
/// which language they're checked against.
///
/// It also earns its place as a buffer. The transform buttons used to sit directly above the top
/// key row, so reaching for `q` or `p` caught "Auf Deutsch" and rewrote a half-finished sentence.
/// A mis-reach now lands on a suggestion, which is harmless and occasionally what you wanted.
struct SuggestionStrip: View {

    @ObservedObject var coach: SpellingCoach
    let onPick: (SpellingCoach.Suggestion) -> Void

    var body: some View {
        HStack(spacing: 0) {
            languageButton

            Divider().frame(height: 22)

            if coach.suggestions.isEmpty {
                Text(coach.isEnabled ? "" : "Corrections off")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(coach.suggestions) { suggestion in
                    Button { onPick(suggestion) } label: {
                        Text(suggestion.text)
                            .font(.system(size: 15, weight: suggestion.isCorrection ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 4)
    }

    /// Tap to switch which dictionary is in use; the label doubles as the indicator, so there is
    /// never a question of which language is being corrected against.
    private var languageButton: some View {
        Button {
            coach.language = coach.language.other
        } label: {
            Text(coach.language.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(coach.isEnabled ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(coach.isEnabled ? 0.12 : 0))
                )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            // Long press turns correction off entirely, for when you're typing something the
            // dictionary will only fight you about.
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                coach.isEnabled.toggle()
                if !coach.isEnabled { coach.clear() }
            }
        )
        .padding(.trailing, 6)
    }
}
