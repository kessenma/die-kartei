import SwiftUI

/// The morphing large-title header from the old segmented Settings screen, extracted so every
/// settings screen — the grouped root and each pushed section — wears the same look, now driven by
/// navigation instead of segments. The symbol swaps in with `.symbolEffect(.replace)` when the
/// screen appears, so it still animates the way Kyle likes.
///
/// Carries `listRow*` modifiers so it can sit as the first row of a `Form`/`List` (its intended
/// home) *and* atop a plain `ScrollView` (e.g. `ThemePickerView`), where those modifiers are no-ops.
struct SettingsHeader: View {
    let icon: String
    let title: String

    /// Flips `true` on appear so the symbol morphs from a neutral placeholder into `icon`.
    @State private var shown = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: shown ? icon : "circle.dotted")
                .foregroundStyle(.tint)
                // Fixed slot (both axes) anchored toward the text so the icon morphs in place:
                // width keeps the title from shifting, height keeps the row a constant size.
                .frame(width: 44, height: 44, alignment: .trailing)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
        }
        .font(.largeTitle.weight(.bold))
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
        .listRowBackground(Color.clear)
        .onAppear { withAnimation(.snappy(duration: 0.3)) { shown = true } }
    }
}
