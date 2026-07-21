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

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.12))
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(accent.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: maxHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("Story illustration")
        .task(id: record.fileName) {
            image = StoryImageStore.loadImage(fileName: record.fileName, storyID: storyID)
        }
    }
}
