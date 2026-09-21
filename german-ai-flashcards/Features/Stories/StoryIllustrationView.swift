import SwiftUI

/// How much of a generated picture is shown.
enum StoryImageFit: Equatable {
    /// A banner of a fixed height, filled and cropped. Compact, but a square picture loses its top
    /// and bottom — the look the reader's „Kompakt" layout and the story list rows want.
    case banner(height: CGFloat)
    /// The whole picture: full row width, height from the image's own proportions, nothing cut off.
    case full
}

/// One generated story picture, with a theme-tinted placeholder while loading or if the file went
/// missing (e.g. the app was killed between file write and record save — the story still renders
/// fine).
struct StoryIllustrationView: View {
    let record: StoryImageRecord
    let storyID: UUID
    let accent: Color
    var fit: StoryImageFit = .banner(height: 200)

    /// Banner convenience, so the fixed-height call sites read as they always did.
    init(record: StoryImageRecord, storyID: UUID, accent: Color, maxHeight: CGFloat) {
        self.init(record: record, storyID: storyID, accent: accent, fit: .banner(height: maxHeight))
    }

    init(record: StoryImageRecord, storyID: UUID, accent: Color, fit: StoryImageFit = .banner(height: 200)) {
        self.record = record
        self.storyID = storyID
        self.accent = accent
        self.fit = fit
    }

    @State private var image: UIImage?
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous))
            // A banner's `scaledToFill` renders a square picture far taller than its frame, and
            // `clipShape` hides that overflow without shrinking the hit region — so the invisible
            // band would land on top of the paragraph above (drawn earlier, so it loses the hit
            // test) and swallow the double-tap-to-translate and drag-to-select gestures there. The
            // picture isn't interactive, so keep it out of hit testing entirely.
            .allowsHitTesting(false)
            .accessibilityLabel("Story illustration")
            // Keyed on the decode size too: the reader's header picture keeps its identity across
            // a layout switch but changes fit, and a 200 pt banner decode stretched to full width
            // is visibly soft.
            .task(id: "\(record.fileName)|\(decodePixelSize)") {
                let pixels = decodePixelSize
                let decoded = await Task.detached(priority: .userInitiated) {
                    StoryImageStore.loadImage(fileName: record.fileName, storyID: storyID,
                                              maxPixelSize: pixels)
                }.value
                // A detached decode outlives a cancelled task; don't file a bitmap for a view
                // that has already moved on (every picture is rebuilt on a layout switch).
                guard !Task.isCancelled else { return }
                image = decoded
            }
            .onDisappear {
                // A story list or a long story can hold a lot of these at once, and a decoded
                // 512×512 costs 1 MB each. Off screen, give it back.
                image = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        switch fit {
        case .banner(let height):
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .frame(height: height)
        case .full:
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                // Reserve a square, the shape the generator produces, so the text below doesn't
                // jump once the file is read.
                placeholder
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }

    /// Long edge to decode to. A banner is cropped from a square, so it needs its *height* at
    /// screen scale, not its width; a full-width picture is capped at a sensible reading width.
    /// The store clamps to the file's own size (512 px), so this only ever shrinks.
    private var decodePixelSize: Int {
        let scale = max(UITraitCollection.current.displayScale, 1)
        switch fit {
        case .banner(let height): return Int((height * scale).rounded())
        case .full:               return Int((820 * scale).rounded())
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: appTheme.innerRadius(12), style: .continuous)
                .fill(accent.opacity(0.12))
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(accent.opacity(0.5))
        }
    }
}
