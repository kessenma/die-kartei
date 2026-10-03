#if os(macOS)
import AppKit
import SwiftUI

/// The macOS text view behind `SelectableGermanText` and `WrappedText`: a non-editable,
/// selectable `NSTextView` that sizes to its text, can flow the text around pictures (the story
/// reader's „Umfluss" layout), and reports clicks on words.
///
/// It mirrors the iOS `WrappingTextView`: the pictures are subviews positioned to match
/// `NSTextContainer.exclusionPaths`, and measuring happens on a detached layout stack so it never
/// writes to the live container (which would invalidate layout and make SwiftUI measure again).
final class WrappingTextView: NSTextView {
    /// Clicks needed to inspect a word: 2 by default, so a single click and a drag stay free for
    /// selecting a phrase.
    var clicksToInspect = 2
    /// A click (of `clicksToInspect`) on the character at this UTF-16 offset.
    var onInspect: ((Int) -> Void)?
    /// A single click that didn't turn into a double-click or a selection.
    var onSingleClick: (() -> Void)?
    /// Items put at the top of the right-click menu for the selected range.
    var selectionMenuItems: ((NSRange) -> [NSMenuItem])?

    /// Pictures to flow the text around, in reading order. Empty leaves a plain text view.
    var wrappedImages: [WrappedImageSpec] = [] {
        didSet {
            guard !WrappedImageSpec.sameLayout(oldValue, wrappedImages) else { return }
            rebuildImageViews()
        }
    }

    /// Breathing room between a picture and the lines that run past and below it.
    private let gutter: CGFloat = 12
    private var imageViews: [NSView] = []
    private var appliedCuts: [CGRect] = []
    private var pendingSingleClick: DispatchWorkItem?

    /// An explicit TextKit 1 stack, as on iOS: exclusion paths are TextKit 1's own feature.
    convenience init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        isEditable = false
        isSelectable = true
        isRichText = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WrappingTextView is created in code, never from a nib")
    }

    /// Replace the text without scrolling or keeping a selection into text that changed.
    func setStyledText(_ text: NSAttributedString) {
        guard let storage = textStorage, !storage.isEqual(to: text) else { return }
        storage.setAttributedString(text)
    }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == clicksToInspect, clicksToInspect > 1 {
            pendingSingleClick?.cancel()
            // Not passed to super: a double-click would otherwise select the word under the
            // inspector the click is about to open.
            setSelectedRange(NSRange(location: selectedRange().location, length: 0))
            onInspect?(characterIndexForInsertion(at: point))
            return
        }
        // NSTextView tracks the drag itself and returns once the button is up.
        super.mouseDown(with: event)
        guard event.clickCount == 1, selectedRange().length == 0 else { return }
        if clicksToInspect == 1 {
            onInspect?(characterIndexForInsertion(at: point))
        } else if let onSingleClick {
            let work = DispatchWorkItem { onSingleClick() }
            pendingSingleClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let range = selectedRange()
        guard range.length > 0, let items = selectionMenuItems?(range), !items.isEmpty else { return menu }
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        menu.insertItem(.separator(), at: items.count)
        return menu
    }

    // MARK: Pictures

    private func rebuildImageViews() {
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = wrappedImages.map { spec in
            let view = PictureView()
            view.wantsLayer = true
            view.layer?.contents = spec.image
            view.layer?.contentsGravity = .resizeAspectFill
            view.layer?.cornerRadius = spec.cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
            view.setAccessibilityLabel("Story illustration")
            addSubview(view)
            return view
        }
        appliedCuts = []
        needsLayout = true
    }

    /// Where each picture goes at a given width, and the rectangle cut out of the text for it.
    /// The same placement as the iOS view: pictures stack downward and never overlap.
    private func placements(forWidth rawWidth: CGFloat) -> [(image: CGRect, cut: CGRect)] {
        let width = rawWidth.rounded()
        guard width > 0 else { return [] }
        var top: CGFloat = 0
        return wrappedImages.map { spec in
            let imageWidth = (width * spec.widthFraction).rounded()
            let ratio = spec.image.size.height / max(spec.image.size.width, 1)
            let imageHeight = (imageWidth * ratio).rounded()
            let x = spec.side == .leading ? 0 : width - imageWidth
            let frame = CGRect(x: x, y: top, width: imageWidth, height: imageHeight)
            let cut = CGRect(
                x: spec.side == .leading ? frame.minX : frame.minX - gutter,
                y: frame.minY,
                width: frame.width + gutter,
                height: frame.height + gutter
            )
            top = frame.maxY + gutter
            return (frame, cut)
        }
    }

    override func layout() {
        super.layout()
        let placed = placements(forWidth: bounds.width)
        let cuts = placed.map(\.cut)
        if cuts != appliedCuts {
            appliedCuts = cuts
            textContainer?.exclusionPaths = cuts.map { NSBezierPath(rect: $0) }
        }
        for (view, placement) in zip(imageViews, placed) {
            view.frame = placement.image
        }
    }

    // MARK: Measuring

    /// The size the text needs at `width`, measured on a detached stack. A paragraph shorter than
    /// its picture is still tall enough to show it.
    func fittingSize(forWidth width: CGFloat) -> CGSize {
        let placed = placements(forWidth: width)
        let storage = NSTextStorage(attributedString: attributedString())
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.exclusionPaths = placed.map { NSBezierPath(rect: $0.cut) }
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        var used = layoutManager.usedRect(for: container).size
        if let bottom = placed.last?.image.maxY { used.height = max(used.height, bottom) }
        return used
    }
}

/// A picture inside the text: decoration only, so clicks go to the text underneath.
private final class PictureView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbol: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("created in code") }

    @objc private func run() { handler() }
}

// MARK: - Plain wrapped text

/// Read-only text with pictures the lines flow around: the story reader's English translation.
struct WrappedText: NSViewRepresentable {
    let text: String
    var textStyle: NSFont.TextStyle = .body
    var wrappedImages: [WrappedImageSpec] = []

    func makeNSView(context: Context) -> WrappingTextView { WrappingTextView() }

    func updateNSView(_ tv: WrappingTextView, context: Context) {
        let size = NSFont.preferredFont(forTextStyle: textStyle).pointSize * context.environment.macReadingScale
        tv.setStyledText(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.labelColor
        ]))
        tv.wrappedImages = wrappedImages
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: WrappingTextView, context: Context) -> CGSize? {
        let proposed = proposal.width ?? 320
        let maxWidth = (proposed.isFinite && proposed > 0) ? proposed : 320
        return CGSize(width: maxWidth, height: ceil(tv.fittingSize(forWidth: maxWidth).height))
    }
}
#endif
