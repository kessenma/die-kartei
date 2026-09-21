import SwiftUI
#if canImport(UIKit)
import UIKit

/// One picture the text flows around, magazine style: it sits in the corner of a paragraph and the
/// lines close around it. Used by the story reader's „Umfluss" layout.
struct WrappedImageSpec: Identifiable {
    enum Side { case leading, trailing }

    var id: String
    var image: UIImage
    var side: Side
    /// Share of the paragraph's width the picture takes. Under about a third the leftover column is
    /// too narrow for German compounds to break cleanly; over about a half there's no column left.
    var widthFraction: CGFloat = 0.46
    var cornerRadius: CGFloat = 12

    /// Cheap equality: the image is compared by identity (they come from a cache, so the same file
    /// is the same object) rather than by `UIImage`'s pixel-wise `isEqual`.
    static func sameLayout(_ lhs: [WrappedImageSpec], _ rhs: [WrappedImageSpec]) -> Bool {
            guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            $0.id == $1.id && $0.side == $1.side
                && $0.widthFraction == $1.widthFraction && $0.cornerRadius == $1.cornerRadius
                && $0.image === $1.image
        }
    }
}

/// A non-scrolling `UITextView` that can cut pictures out of its own text container, so the text
/// wraps around them instead of being interrupted by them.
///
/// The pictures are plain subviews positioned to match `NSTextContainer.exclusionPaths`, which is
/// the only mechanism that makes text flow *around* something — an `NSTextAttachment` would sit in
/// the line like a very large character and push everything below it.
final class WrappingTextView: UITextView {
    /// Built on an explicit TextKit 1 stack, because exclusion paths are TextKit 1's own feature
    /// and it lays them out predictably.
    ///
    /// **Not** `UITextView(usingTextLayoutManager:)`. That convenience initializer does not run a
    /// subclass's designated initializer, so every Swift stored property below is left
    /// uninitialized — and the first read of `wrappedImages` then faults on garbage
    /// (`EXC_BAD_ACCESS` inside `_ArrayBuffer.count`). `init(frame:textContainer:)` is the
    /// designated initializer, and a container behind an `NSLayoutManager` is TextKit 1.
    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("WrappingTextView is created in code, never from a nib")
    }

    /// Pictures to flow the text around, in reading order. Empty (the default) leaves the view
    /// behaving exactly like a plain `UITextView`.
    var wrappedImages: [WrappedImageSpec] = [] {
        didSet {
            guard !WrappedImageSpec.sameLayout(oldValue, wrappedImages) else { return }
            // Only flag the work. Adding and removing subviews from a property setter can land in
            // the middle of a UIKit layout traversal — and `addSubview` can drive layout straight
            // back into this view, which re-enters the setter while the subview array is being
            // rebuilt. The rebuild happens in `layoutSubviews`, where mutating subviews is safe.
            needsImageViewRebuild = true
            laidOutWidth = -1
            setNeedsLayout()
        }
    }

    private var needsImageViewRebuild = false

    /// Breathing room between a picture and the lines that run past and below it.
    private let gutter: CGFloat = 12

    private var imageViews: [UIImageView] = []
    /// The cut-outs currently installed on the text container, and the width they were computed for.
    ///
    /// Writing `exclusionPaths` invalidates layout, and UIKit invalidates the intrinsic content size
    /// with it — which makes SwiftUI measure again. So the write has to happen only when the result
    /// actually differs, or measuring and laying out re-trigger each other without end.
    private var appliedCuts: [CGRect] = []
    private var laidOutWidth: CGFloat = -1
    /// Set while `applyExclusions` is writing, so a layout pass it provokes can't write again.
    private var isApplyingExclusions = false

    /// True once this view has anything to do. While false — which is every use of
    /// `SelectableGermanText` outside the story reader's „Umfluss" layout — the overrides below are
    /// pure pass-throughs and the view behaves exactly like a plain `UITextView`.
    private var wrapsText: Bool { !wrappedImages.isEmpty || !appliedCuts.isEmpty || needsImageViewRebuild }

    private func rebuildImageViewsIfNeeded() {
        guard needsImageViewRebuild else { return }
        needsImageViewRebuild = false
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = wrappedImages.map { spec in
            let view = UIImageView(image: spec.image)
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.layer.cornerRadius = spec.cornerRadius
            view.layer.cornerCurve = .continuous
            // The picture is decoration: it must not eat the double-tap-to-translate or the
            // drag-to-select gestures of the text it's sitting inside.
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = true
            view.accessibilityLabel = "Story illustration"
            addSubview(view)
            return view
        }
        laidOutWidth = -1
    }

    /// Where each picture goes at a given text width, and the rectangle to cut out of the text for
    /// it. Pictures stack downward: a second one in the same paragraph starts below the first, so
    /// two cut-outs never overlap and the text always keeps a readable column.
    ///
    /// The width is rounded first: measuring and laying out can hand over widths a hair apart, and
    /// two placements that differ by a fraction of a point would look like a real change.
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
            // Widen the cut-out toward the text column and below, so lines keep the gutter.
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

    private func applyExclusions(forWidth rawWidth: CGFloat) {
        let width = rawWidth.rounded()
        guard wrapsText, width > 0, !isApplyingExclusions else { return }
        guard width != laidOutWidth else { return }
        laidOutWidth = width
        let cuts = placements(forWidth: width).map(\.cut)
        guard cuts != appliedCuts else { return }
        appliedCuts = cuts
        isApplyingExclusions = true
        textContainer.exclusionPaths = cuts.map { UIBezierPath(rect: $0) }
        isApplyingExclusions = false
    }

    /// A detached twin used only for measuring. Measuring must not touch the live view's text
    /// container: writing `exclusionPaths` invalidates layout and the intrinsic content size, so a
    /// measure that wrote would ask SwiftUI to measure again, forever. Only `layoutSubviews` writes.
    private lazy var sizer: UITextView = {
        let tv = UITextView(usingTextLayoutManager: false)
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        return tv
    }()

    /// A paragraph shorter than its picture still has to be tall enough to show it.
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard wrapsText else { return super.sizeThatFits(size) }
        let cut = placements(forWidth: size.width)
        sizer.attributedText = attributedText
        sizer.textContainerInset = textContainerInset
        sizer.textContainer.lineFragmentPadding = textContainer.lineFragmentPadding
        sizer.textContainer.exclusionPaths = cut.map { UIBezierPath(rect: $0.cut) }
        var fit = sizer.sizeThatFits(size)
        if let bottom = cut.last?.image.maxY {
            fit.height = max(fit.height, bottom)
        }
        return fit
    }

    override func layoutSubviews() {
        rebuildImageViewsIfNeeded()
        guard wrapsText else {
            super.layoutSubviews()
            return
        }
        applyExclusions(forWidth: bounds.width)
        super.layoutSubviews()
        for (view, placement) in zip(imageViews, placements(forWidth: bounds.width)) {
            view.frame = placement.image
        }
    }
}

// MARK: - Plain wrapped text

/// Read-only text with pictures the lines flow around. The German story text uses
/// `SelectableGermanText` (same wrapping, plus the word gestures); this is for the English
/// translation, where the gestures deliberately don't apply.
struct WrappedText: UIViewRepresentable {
    let text: String
    var textStyle: UIFont.TextStyle = .body
    var wrappedImages: [WrappedImageSpec] = []

    func makeUIView(context: Context) -> WrappingTextView {
        let tv = WrappingTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.setContentHuggingPriority(.required, for: .vertical)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: WrappingTextView, context: Context) {
        let base = UIFont.preferredFont(forTextStyle: textStyle)
        tv.attributedText = NSAttributedString(string: text, attributes: [
            .font: base,
            .foregroundColor: UIColor.label
        ])
        tv.wrappedImages = wrappedImages
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: WrappingTextView, context: Context) -> CGSize? {
        let proposed = proposal.width ?? 320
        let maxWidth = (proposed.isFinite && proposed > 0) ? proposed : 320
        let fit = tv.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: maxWidth, height: ceil(fit.height))
    }
}
#endif
