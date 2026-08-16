import SwiftUI

/// One generated story picture: aspect-fill in a rounded rect, with a theme-tinted placeholder
/// while loading or if the file went missing (e.g. the app was killed between file write and
/// record save — the story still renders fine).
struct StoryIllustrationView: View {
    let record: StoryImageRecord
    let storyID: UUID
    let accent: Color
    var maxHeight: CGFloat = 200

    @State private var image: UIImage?
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous)
                    .fill(accent.opacity(0.12))
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(accent.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxHeight)
        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous))
        // `scaledToFill` renders a square picture far taller than this frame, and `clipShape` hides
        // that overflow without shrinking the hit region — so the invisible band would land on top
        // of the paragraph above (drawn earlier, so it loses the hit test) and swallow the
        // double-tap-to-translate and drag-to-select gestures there. The picture isn't interactive,
        // so keep it out of hit testing entirely.
        .allowsHitTesting(false)
        .accessibilityLabel("Story illustration")
        .task(id: record.fileName) {
            image = StoryImageStore.loadImage(fileName: record.fileName, storyID: storyID)
        }
    }
}
