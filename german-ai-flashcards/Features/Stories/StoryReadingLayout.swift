import SwiftUI

/// How the story reader arranges the text and its generated pictures. The learner's pick is kept
/// across stories — it's a reading preference, not a property of one story.
enum StoryReadingLayout: String, CaseIterable, Identifiable {
    /// Cropped banners between the paragraphs. Least scrolling, but a square picture loses its top
    /// and bottom.
    case kompakt
    /// Every picture whole, full width, at its own proportions. The default: nothing is cut off.
    case ganz
    /// Every picture whole but half-width, sitting in the corner of its paragraph with the text
    /// flowing around it.
    case umfluss

    var id: String { rawValue }

    /// German identity word, as the app labels its modes.
    var label: String {
        switch self {
        case .kompakt: "Kompakt"
        case .ganz:    "Ganz"
        case .umfluss: "Umfluss"
        }
    }

    var detail: String {
        switch self {
        case .kompakt: "Short banners — less scrolling, pictures cropped"
        case .ganz:    "Whole pictures, full width"
        case .umfluss: "Text flows around the pictures"
        }
    }

    var symbol: String {
        switch self {
        case .kompakt: "rectangle.compress.vertical"
        case .ganz:    "rectangle.expand.vertical"
        case .umfluss: "square.righthalf.filled"
        }
    }

    /// The fit the inline pictures use. `.umfluss` places its own pictures inside the text, so it
    /// never reaches here.
    func inlineFit(compactHeight: CGFloat) -> StoryImageFit {
        self == .kompakt ? .banner(height: compactHeight) : .full
    }
}

// MARK: - Picture cache

/// Keeps the decoded pictures of one story around, so the „Umfluss" layout can hand real `UIImage`s
/// to the text view (which needs their proportions before it can lay out around them). The stacked
/// layouts don't need this — `StoryIllustrationView` loads its own file.
@MainActor
@Observable
final class StoryImageCache {
    private(set) var images: [String: UIImage] = [:]
    /// Bumped by every `purge()`. A decode that started before a purge compares this after it
    /// finishes and drops its result, so a purge can never be undone by work already in flight.
    @ObservationIgnored private var generation = 0
    /// The decode in progress, so a second `load` while one is running waits for it instead of
    /// starting another full-set decode on top.
    @ObservationIgnored private var inFlight: Task<[String: UIImage], Never>?
    /// Written once in `init` and read once in the (nonisolated) `deinit`, so it needs to be
    /// reachable from both.
    @ObservationIgnored nonisolated(unsafe) private var warningObserver: NSObjectProtocol?

    /// Long edge to decode to. „Umfluss" draws a picture at under half the reading width, so
    /// decoding the full 512 px would be paying for pixels nobody sees. (The store never upscales
    /// past the file, so this is a cap, not a target.)
    private static let maxPixelSize = 700

    /// Registry key in the memory breakdown; one entry stands for whichever reader is open.
    private static let contributorKey = "storyPictures"

    init() {
        // These are among the first megabytes worth giving back: the pictures reload off disk in a
        // moment, and on a device with a model resident the reserve for everything-but-the-model is
        // only `MemoryBudget.reserveMB`.
        warningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.purge() }
        }
        MemoryDiagnostics.register(Self.contributorKey, name: "Story pictures") { [weak self] in
            self?.decodedBytes ?? 0
        }
    }

    deinit {
        if let warningObserver { NotificationCenter.default.removeObserver(warningObserver) }
        Task { @MainActor in MemoryDiagnostics.unregister(StoryImageCache.contributorKey) }
    }

    func image(_ record: StoryImageRecord) -> UIImage? { images[record.fileName] }

    /// What the decoded bitmaps cost, for the memory breakdown.
    var decodedBytes: Int {
        images.values.reduce(0) { total, image in
            guard let cg = image.cgImage else { return total }
            return total + cg.bytesPerRow * cg.height
        }
    }

    /// Read any not-yet-loaded files off the main thread. Safe to call on every appearance, and
    /// safe to be cancelled: a cancelled call discards what it decoded rather than filing it.
    func load(_ records: [StoryImageRecord], storyID: UUID) async {
        // A decode already running covers these files. Wait it out first, so two never run at once
        // and so the check below sees what it filed.
        if let inFlight {
            _ = await inFlight.value
        }
        // Derived from `images` itself rather than a separate "claimed" set. A claim has to be
        // released on every early return, and the release loses a race against the next caller:
        // a claim made by a call that then went away left the files looking loaded to everyone
        // else, so nobody decoded them and the layout stayed blank until a purge reset it.
        let missing = records.map(\.fileName).filter { images[$0] == nil }
        guard !missing.isEmpty else { return }
        let size = Self.maxPixelSize
        let startedIn = generation
        let task = Task.detached(priority: .userInitiated) {
            missing.reduce(into: [String: UIImage]()) { result, name in
                result[name] = StoryImageStore.loadImage(fileName: name, storyID: storyID,
                                                         maxPixelSize: size)
            }
        }
        inFlight = task
        let decoded = await task.value
        if inFlight == task { inFlight = nil }
        // Deliberately *not* checking `Task.isCancelled`. The caller is a `.task(id:)` that is
        // cancelled by any change to its id — including ones that stay in Umfluss — and the
        // pictures are already decoded by this point, so dropping them on the caller's
        // cancellation just throws away finished work nobody will ask for again.
        //
        // `generation` is the check that matters: leaving Umfluss and closing the screen both go
        // through `purge`, which bumps it, so a set nobody is looking at still gets dropped.
        guard startedIn == generation else { return }
        for (name, image) in decoded { images[name] = image }
    }

    /// Drop every decoded picture. Called when the reader leaves „Umfluss", when the screen goes
    /// away, and on a system memory warning — holding a second full set of bitmaps behind a layout
    /// the learner has switched away from is exactly the kind of quiet cost that gets an app killed.
    func purge() {
        generation += 1
        guard !images.isEmpty else { return }
        images.removeAll()
    }
}

// MARK: - Picker

/// The layout menu the story reader puts in its toolbar. Only shown for illustrated stories —
/// without pictures there is nothing to arrange.
struct StoryLayoutMenu: View {
    @Binding var layout: StoryReadingLayout

    var body: some View {
        Menu {
            Picker("Bilder", selection: $layout) {
                ForEach(StoryReadingLayout.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
            Section {
                Text(layout.detail)
            }
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
        }
        .accessibilityLabel("Picture layout")
    }
}
