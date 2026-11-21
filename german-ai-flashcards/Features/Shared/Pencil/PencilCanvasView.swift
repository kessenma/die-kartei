//
//  PencilCanvasView.swift
//  german-ai-flashcards
//
//  The `PKCanvasView` both writing surfaces use (the Schreibblatt sheet and the Übungen slide), in
//  place of the system tool picker. The picker floats in its own window over the bottom of the app;
//  this keeps what the sheets used from it, with Procreate's gestures on top:
//   • the tools: a pen (PencilKit's own inks, in black, blue or red, three thicknesses), and the
//     bitmap eraser that rubs out only what it passes over;
//   • circle to erase: an eraser loop around a word clears the whole word (`PencilEraseLoop`);
//   • a squeeze (Apple Pencil Pro) switches pen and eraser, or what the gear sets; the Pencil's
//     double-tap is left alone;
//   • a two-finger tap undoes, a three-finger tap redoes;
//   • the wrist guard: only the Pencil writes, one finger does nothing (scrolling and zooming take
//     two, as in Procreate; a two-finger tap still undoes, because a tap is two fingers that do
//     not move), and while the Pencil is writing, or whenever a touch is the size of a resting
//     hand, finger touches neither scroll, zoom nor tap.
//
//  Its own undo stack: `undoManager` is overridden, so each sheet or page undoes only itself, with
//  no first responder and without touching the window's text-field undo. PencilKit registers its
//  strokes and erasures there; a loop's erase registers a snapshot of the drawing next to them.
//
//  The rail beside it is SwiftUI (`PencilRail`); `PencilBoard` is what the two share.
//  See docs/SCHREIBBLATT.md ▸ Pencil controls.
//

#if canImport(UIKit)
import PencilKit
import UIKit
import UIKit.UIGestureRecognizerSubclass

final class PencilCanvasView: PKCanvasView, UIPencilInteractionDelegate {

    var pencilTool: PencilTool = .pen {
        didSet { if pencilTool != oldValue { applyTool() } }
    }

    var pen = PencilPen() {
        didSet { if pen != oldValue { applyTool() } }
    }

    var highlighter = PencilHighlighter() {
        didSet { if highlighter != oldValue { applyTool() } }
    }

    /// The Atelier's brush: when set, the pen draws with it instead of `pen`.
    var studioBrush: PencilStudioBrush? {
        didSet { if studioBrush != oldValue { applyTool() } }
    }

    /// The bitmap eraser's width, in points of the page.
    var eraserWidth: Double = PencilEraserSize.medium.width {
        didSet { if eraserWidth != oldValue { applyTool() } }
    }

    /// Dark paper: the pen's colour is chosen as it looks there (`PencilPen.Shade`).
    var darkPaper = false {
        didSet { if darkPaper != oldValue { applyTool() } }
    }

    /// On: the Pencil only, with the hand ignored (`PalmGuard`) and scrolling on two fingers.
    /// Off: a finger writes too, and PencilKit scrolls with two anyway.
    var wristGuard = false {
        didSet {
            drawingPolicy = wristGuard ? .pencilOnly : .anyInput
            holdScrollingToTwoFingers()
        }
    }

    /// A finished page: it still scrolls and zooms (with one finger, since nothing can be written),
    /// but nothing writes, erases, undoes or clears.
    var isLocked = false {
        didSet {
            drawingGestureRecognizer.isEnabled = !isLocked
            eraserPath.removeAll()
            holdScrollingToTwoFingers()
        }
    }

    /// The gear's settings: the wrist guard's pause and scrolling, the squeeze, the finger taps.
    var prefs = PencilPrefs() {
        didSet {
            guard prefs != oldValue else { return }
            undoTap.isEnabled = prefs.fingerTaps
            redoTap.isEnabled = prefs.fingerTaps
            holdScrollingToTwoFingers()
        }
    }

    /// A Pencil squeeze, as the gear set it: the board performs it.
    var onPencilAction: ((PencilPrefs.Action) -> Void)?
    /// The first Pencil touch, for the board to turn the wrist guard on by itself.
    var onPencilSeen: (() -> Void)?
    var onUndoStateChange: ((_ canUndo: Bool, _ canRedo: Bool) -> Void)?

    private let ownUndo = UndoManager()
    /// The eraser's path in drawing space, while it is down.
    private var eraserPath: [CGPoint] = []

    /// The Pencil is on the glass.
    private(set) var pencilDown = false
    /// When it last left the glass.
    private(set) var pencilLifted = Date.distantPast
    private var pencilEverSeen = false
    private let palmGuard = PalmGuardRecognizer()
    private var guardsPinch = false
    private let undoTap = UITapGestureRecognizer()
    private let redoTap = UITapGestureRecognizer()

    override var undoManager: UndoManager? { ownUndo }

    override init(frame: CGRect) {
        super.init(frame: frame)
        install()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        install()
    }

    private func install() {
        applyTool()

        let pencil = UIPencilInteraction(delegate: self)
        addInteraction(pencil)

        undoTap.addTarget(self, action: #selector(fingerUndo))
        undoTap.numberOfTouchesRequired = 2
        redoTap.addTarget(self, action: #selector(fingerRedo))
        redoTap.numberOfTouchesRequired = 3
        for tap in [undoTap, redoTap] {
            tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            addGestureRecognizer(tap)
        }
        undoTap.require(toFail: redoTap)

        drawingGestureRecognizer.addTarget(self, action: #selector(trackEraser(_:)))

        // The wrist guard: finger gestures wait for the guard to let a touch through.
        let watcher = PencilWatcher()
        watcher.canvas = self
        addGestureRecognizer(watcher)
        palmGuard.canvas = self
        addGestureRecognizer(palmGuard)
        for recognizer in [panGestureRecognizer, undoTap, redoTap] {
            recognizer.require(toFail: palmGuard)
        }

        for name: Notification.Name in [.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange,
                                        .NSUndoManagerDidRedoChange, .NSUndoManagerCheckpoint] {
            NotificationCenter.default.addObserver(self, selector: #selector(undoStackChanged),
                                                   name: name, object: ownUndo)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A scroll view has no pinch recognizer until zooming is allowed, which the screen sets
        // after this view is made.
        if !guardsPinch, let pinch = pinchGestureRecognizer {
            pinch.require(toFail: palmGuard)
            guardsPinch = true
        }
        // Re-asserted here as well: PencilKit configures its own pan when its policy changes.
        holdScrollingToTwoFingers()
    }

    /// Two fingers to scroll while the page can be written on, so a hand resting on the glass can
    /// never move it; one on a locked page, or with the wrist guard on when the learner chose one
    /// (a finger that writes cannot also scroll, so with the guard off it is always two).
    private func holdScrollingToTwoFingers() {
        let fingers = isLocked || (wristGuard && !prefs.twoFingerScroll) ? 1 : 2
        if panGestureRecognizer.minimumNumberOfTouches != fingers {
            panGestureRecognizer.minimumNumberOfTouches = fingers
        }
    }

    private func applyTool() {
        switch pencilTool {
        case .pen: tool = studioBrush?.tool(darkPaper: darkPaper) ?? Self.inkingTool(for: pen, darkPaper: darkPaper)
        case .highlighter: tool = Self.markerTool(for: highlighter, darkPaper: darkPaper)
        case .eraser:
            // Still a bitmap eraser (it rubs out only what it passes over), in the kind that takes a size.
            let range = PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange
            tool = PKEraserTool(.fixedWidthBitmap, width: min(max(eraserWidth, range.lowerBound), range.upperBound))
        }
    }

    /// PencilKit stores a stroke's colour in the light appearance and shows it lighter in the dark
    /// one. So on dark paper the colour as seen there is converted back to what to store, and the
    /// sheet still prints as dark ink on white.
    static func inkingTool(for pen: PencilPen, darkPaper: Bool = false) -> PKInkingTool {
        let type: PKInkingTool.InkType = switch pen.ink {
        case .pen: .pen
        case .fountainPen: .fountainPen
        case .pencil: .pencil
        case .fineliner: .monoline
        }
        let rgb = pen.shade.rgb(onDark: darkPaper)
        let seen = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        let color = darkPaper ? PKInkingTool.convertColor(seen, from: .dark, to: .light) : seen
        let range = type.validWidthRange
        let width = min(max(type.defaultWidth * pen.weight.factor, range.lowerBound), range.upperBound)
        return PKInkingTool(type, color: color, width: width)
    }

    /// PencilKit's marker, wider than a pen and see-through. Stored, like the pen, as its
    /// light-appearance colour.
    static func markerTool(for marker: PencilHighlighter, darkPaper: Bool = false) -> PKInkingTool {
        let type = PKInkingTool.InkType.marker
        let rgb = marker.shade.rgb
        let seen = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        let color = darkPaper ? PKInkingTool.convertColor(seen, from: .dark, to: .light) : seen
        let range = type.validWidthRange
        let width = min(max(type.defaultWidth * 1.5 * marker.weight.factor, range.lowerBound), range.upperBound)
        return PKInkingTool(type, color: color, width: width)
    }

    // MARK: The wrist guard

    /// The Pencil touched down or lifted (`PencilWatcher`).
    fileprivate func pencil(isDown: Bool) {
        pencilDown = isDown
        if !isDown { pencilLifted = Date() }
        if isDown, !pencilEverSeen {
            pencilEverSeen = true
            onPencilSeen?()
        }
    }

    /// Whether a finger touch should be kept from scrolling, zooming and tapping.
    fileprivate func guards(_ touch: UITouch) -> Bool {
        PalmGuard.blocks(guarding: wristGuard, pencilDown: pencilDown,
                         sincePencil: Date().timeIntervalSince(pencilLifted), radius: touch.majorRadius,
                         pause: prefs.guardPause)
    }

    // MARK: Undo

    func undo() {
        guard !isLocked, ownUndo.canUndo else { return }
        ownUndo.undo()
    }

    func redo() {
        guard !isLocked, ownUndo.canRedo else { return }
        ownUndo.redo()
    }

    func refreshUndoState() {
        onUndoStateChange?(ownUndo.canUndo, ownUndo.canRedo)
    }

    @objc private func undoStackChanged() { refreshUndoState() }
    @objc private func fingerUndo() { undo() }
    @objc private func fingerRedo() { redo() }

    /// Wipe the page, undoably.
    func clear() {
        guard !isLocked, !drawing.strokes.isEmpty else { return }
        replaceDrawing(PKDrawing())
    }

    /// Swap the whole drawing as one undoable step. Assigning `drawing` calls the delegate's
    /// `canvasViewDrawingDidChange`, so the screen's debounced save picks it up as it would a stroke.
    func replaceDrawing(_ next: PKDrawing) {
        let previous = drawing
        ownUndo.registerUndo(withTarget: self) { canvas in canvas.replaceDrawing(previous) }
        ownUndo.setActionName("Erase")
        drawing = next
    }

    // MARK: The Pencil

    func pencilInteraction(_ interaction: UIPencilInteraction,
                           didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        // The eraser by default; the gear can change it. Off in Settings still means off.
        guard squeeze.phase == .ended, UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
        onPencilAction?(prefs.squeeze)
    }

    // MARK: Circle to erase

    /// Rides along on PencilKit's own drawing recognizer, so it sees exactly the input the
    /// eraser does. `location(in:)` is in the zoomed content; the drawing is not.
    @objc private func trackEraser(_ recognizer: UIGestureRecognizer) {
        guard pencilTool == .eraser else {
            eraserPath.removeAll()
            return
        }
        let location = recognizer.location(in: self)
        let point = CGPoint(x: location.x / zoomScale, y: location.y / zoomScale)
        switch recognizer.state {
        case .began:
            eraserPath = [point]
        case .changed:
            eraserPath.append(point)
        case .ended:
            eraserPath.append(point)
            let path = eraserPath
            eraserPath.removeAll()
            // PencilKit commits its own erase on the same lift; clear the loop's insides after it.
            DispatchQueue.main.async { [weak self] in self?.eraseInside(path) }
        default:
            eraserPath.removeAll()
        }
    }

    private func eraseInside(_ path: [CGPoint]) {
        guard PencilEraseLoop.isLoop(path) else { return }
        let hit = PencilEraseLoop.enclosedStrokes(in: drawing, loop: path)
        guard !hit.isEmpty else { return }
        var next = drawing
        next.strokes = drawing.strokes.enumerated().filter { !hit.contains($0.offset) }.map(\.element)
        replaceDrawing(next)
    }
}
// MARK: - The wrist guard


/// Never recognizes; tells the canvas when the Pencil is on the glass.
private final class PencilWatcher: UIGestureRecognizer {
    weak var canvas: PencilCanvasView?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    convenience init() { self.init(target: nil, action: nil) }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        canvas?.pencil(isDown: true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        canvas?.pencil(isDown: false)
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        canvas?.pencil(isDown: false)
        state = .failed
    }
}

/// Swallows a finger touch the wrist guard catches, so the scroll view's pan and pinch and the
/// undo taps (which all wait for this to fail) never see it. A touch it lets through fails it at
/// once, after a short look: a resting hand often lands small and spreads.
private final class PalmGuardRecognizer: UIGestureRecognizer {
    weak var canvas: PencilCanvasView?
    private var decision: DispatchWorkItem?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    convenience init() { self.init(target: nil, action: nil) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let canvas, canvas.wristGuard else {
            state = .failed
            return
        }
        if state == .began || state == .changed { return }
        if touches.contains(where: canvas.guards) {
            state = .began
            return
        }
        decision?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.decide(touches) }
        decision = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func decide(_ touches: Set<UITouch>) {
        guard state == .possible, let canvas else { return }
        state = touches.contains(where: canvas.guards) ? .began : .failed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(.ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(.cancelled)
    }

    private func finish(_ end: UIGestureRecognizer.State) {
        decision?.cancel()
        switch state {
        case .began, .changed: state = end
        case .possible: state = .failed
        default: break
        }
    }

    override func reset() {
        super.reset()
        decision?.cancel()
        decision = nil
    }
}
#endif
