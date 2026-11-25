//
//  PencilBoard.swift
//  german-ai-flashcards
//
//  The state a Pencil surface shares between its canvas and the rail beside it: the tool, the pen
//  (ink, colour, thickness), the wrist guard, and whether there is anything to undo or redo. The
//  screen owns one; the canvas attaches to it in `makeUIView` and detaches when it is torn down.
//
//  The tool always starts on the pen and is never kept, so a sheet is never reopened with the
//  eraser in hand. The pen and the wrist guard are kept, for every Pencil surface at once.
//
//  Compiles on the Mac, where there is no canvas to attach and the rail is never shown.
//  See docs/SCHREIBBLATT.md ▸ Pencil controls.
//

import Observation
import SwiftUI
#if canImport(UIKit)
import PencilKit
import UIKit
#endif

enum PencilTool {
    case pen, highlighter, eraser
}

/// The eraser's size, in points of the page. Kept for every surface. PencilKit's sizeable eraser
/// (`fixedWidthBitmap`) runs from 16.4 to 80.4 points; the plain `bitmap` one ignores a width
/// (its valid range reads 0...0), which is why the sizes once all came out the same.
enum PencilEraserSize: String, CaseIterable, Identifiable {
    case small, medium, large, huge

    var id: String { rawValue }

    var width: Double {
        switch self {
        case .small: 16.4
        case .medium: 26
        case .large: 44
        case .huge: 72
        }
    }

    var title: String {
        switch self {
        case .small: "Klein"
        case .medium: "Mittel"
        case .large: "Groß"
        case .huge: "Riesig"
        }
    }

    var english: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .huge: "Huge"
        }
    }

    static let key = "pencil.eraserSize"

    static var stored: PencilEraserSize {
        UserDefaults.standard.string(forKey: key).flatMap(PencilEraserSize.init(rawValue:)) ?? .medium
    }
}

/// The highlighter: PencilKit's marker, see-through, in its own colours. A tool of its own beside
/// the pen, so switching between writing and marking is one tap and each keeps its colour.
struct PencilHighlighter: Equatable {
    enum Shade: String, CaseIterable, Identifiable {
        case yellow, green, pink, blue

        var id: String { rawValue }

        var title: String {
            switch self {
            case .yellow: "Gelb"
            case .green: "Grün"
            case .pink: "Pink"
            case .blue: "Blau"
            }
        }

        var english: String {
            switch self {
            case .yellow: "Yellow"
            case .green: "Green"
            case .pink: "Pink"
            case .blue: "Blue"
            }
        }

        /// sRGB as it looks on the paper. Already light, so the same on light and dark paper.
        var rgb: (red: Double, green: Double, blue: Double) {
            switch self {
            case .yellow: (1.00, 0.86, 0.10)
            case .green: (0.45, 0.86, 0.35)
            case .pink: (1.00, 0.45, 0.72)
            case .blue: (0.40, 0.72, 1.00)
            }
        }

        var color: Color { Color(red: rgb.red, green: rgb.green, blue: rgb.blue) }
    }

    var shade: Shade = .yellow
    var weight: PencilPen.Weight = .medium

    private static let shadeKey = "pencil.highlighter.shade"
    private static let weightKey = "pencil.highlighter.weight"

    static var stored: PencilHighlighter {
        let defaults = UserDefaults.standard
        return PencilHighlighter(
            shade: defaults.string(forKey: shadeKey).flatMap(Shade.init(rawValue:)) ?? .yellow,
            weight: defaults.string(forKey: weightKey).flatMap(PencilPen.Weight.init(rawValue:)) ?? .medium
        )
    }

    func store() {
        UserDefaults.standard.set(shade.rawValue, forKey: Self.shadeKey)
        UserDefaults.standard.set(weight.rawValue, forKey: Self.weightKey)
    }
}

/// What the pen writes with. PencilKit's own inks only: it has no way to load a brush of ours, so
/// there is nothing to download and nothing to license.
struct PencilPen: Equatable {
    enum Ink: String, CaseIterable, Identifiable {
        case pen, fountainPen, pencil, fineliner

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pen: "Kugelschreiber"
            case .fountainPen: "Füller"
            case .pencil: "Bleistift"
            case .fineliner: "Fineliner"
            }
        }

        var english: String {
            switch self {
            case .pen: "Ballpoint"
            case .fountainPen: "Fountain pen"
            case .pencil: "Pencil"
            case .fineliner: "Fineliner"
            }
        }

        var systemImage: String {
            switch self {
            case .pen: "pencil.tip"
            case .fountainPen: "signature"
            case .pencil: "pencil"
            case .fineliner: "pencil.line"
            }
        }
    }

    /// A colour as it is chosen. On dark paper the canvas draws in the dark appearance, where
    /// PencilKit shows every ink lighter: the black pen writes white there, and yellow, which would
    /// vanish on white paper, is offered. Strokes keep their light-appearance colour, so a sheet
    /// written on dark paper still prints as dark ink on white.
    enum Shade: String, CaseIterable, Identifiable {
        case black, blue, red, yellow

        var id: String { rawValue }

        /// The colours offered on this paper.
        static func offered(onDark: Bool) -> [Shade] {
            onDark ? [.black, .yellow, .blue, .red] : [.black, .blue, .red]
        }

        func title(onDark: Bool) -> String {
            switch self {
            case .black: onDark ? "Weiß" : "Schwarz"
            case .blue: "Blau"
            case .red: "Rot"
            case .yellow: "Gelb"
            }
        }

        func english(onDark: Bool) -> String {
            switch self {
            case .black: onDark ? "White" : "Black"
            case .blue: "Blue"
            case .red: "Red"
            case .yellow: "Yellow"
            }
        }

        /// sRGB, as it looks on the paper: light paper (what the ink is stored as) or dark.
        func rgb(onDark: Bool) -> (red: Double, green: Double, blue: Double) {
            switch (self, onDark) {
            case (.black, false): (0.08, 0.08, 0.10)
            case (.black, true): (0.95, 0.95, 0.95)
            case (.blue, false): (0.05, 0.27, 0.78)
            case (.blue, true): (0.45, 0.66, 1.00)
            case (.red, false): (0.80, 0.10, 0.12)
            case (.red, true): (1.00, 0.45, 0.45)
            case (.yellow, false): (0.78, 0.58, 0.00)
            case (.yellow, true): (1.00, 0.85, 0.20)
            }
        }

        func color(onDark: Bool) -> Color {
            let rgb = rgb(onDark: onDark)
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
    }

    enum Weight: String, CaseIterable, Identifiable {
        case fine, medium, bold

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fine: "Fein"
            case .medium: "Mittel"
            case .bold: "Dick"
            }
        }

        var english: String {
            switch self {
            case .fine: "Fine"
            case .medium: "Medium"
            case .bold: "Thick"
            }
        }

        /// Times the ink's own default width.
        var factor: Double {
            switch self {
            case .fine: 0.6
            case .medium: 1
            case .bold: 1.7
            }
        }
    }

    var ink: Ink = .pen
    var shade: Shade = .black
    var weight: Weight = .medium

    static let inkKey = "pencil.ink"
    static let shadeKey = "pencil.shade"
    static let weightKey = "pencil.weight"

    static var stored: PencilPen {
        let defaults = UserDefaults.standard
        return PencilPen(
            ink: defaults.string(forKey: inkKey).flatMap(Ink.init(rawValue:)) ?? .pen,
            shade: defaults.string(forKey: shadeKey).flatMap(Shade.init(rawValue:)) ?? .black,
            weight: defaults.string(forKey: weightKey).flatMap(Weight.init(rawValue:)) ?? .medium
        )
    }

    func store() {
        let defaults = UserDefaults.standard
        defaults.set(ink.rawValue, forKey: Self.inkKey)
        defaults.set(shade.rawValue, forKey: Self.shadeKey)
        defaults.set(weight.rawValue, forKey: Self.weightKey)
    }
}

/// The wrist guard's rule (`PalmGuardRecognizer` applies it), kept apart so the tests can hold it.
enum PalmGuard {
    /// After the Pencil lifts, the hand is still coming off the glass for about this long: the
    /// default for the gear's slider. Short, because with two-finger scrolling a lone hand cannot
    /// scroll anyway: this catches a hand and a stray finger together, and should not hold up a
    /// deliberate scroll after a word. One-finger scrolling may want it longer.
    static let afterPencil: TimeInterval = 0.25
    /// What iPads report for a fingertip pressed flat runs to about 42 points (it comes in steps of
    /// about 10.4); a palm or the side of a hand is well past 50. At 30, two fingers scrolling were
    /// taken for a hand and the page would not move.
    static let handRadius: CGFloat = 50

    static func blocks(guarding: Bool, pencilDown: Bool, sincePencil: TimeInterval, radius: CGFloat,
                       pause: TimeInterval = afterPencil) -> Bool {
        guard guarding else { return false }
        return pencilDown || sincePencil < pause || radius > handRadius
    }
}

/// The settings behind the gear on the rail: how the wrist guard behaves, what a squeeze of the
/// Pencil does, and the finger taps. Kept for every Pencil surface at once.
///
/// There is no double-tap setting: the double-tap was dropped after testing on a device, and the
/// canvas leaves it alone.
struct PencilPrefs: Equatable {
    /// What a squeeze does (`PencilBoard.perform`).
    enum Action: String, CaseIterable, Identifiable {
        case undo, redo, eraser, nextColour, nextWidth, penPicker, off

        var id: String { rawValue }

        var title: String {
            switch self {
            case .undo: "Rückgängig"
            case .redo: "Wiederholen"
            case .eraser: "Radierer an/aus"
            case .nextColour: "Farbe wechseln"
            case .nextWidth: "Stärke wechseln"
            case .penPicker: "Stiftauswahl"
            case .off: "Aus"
            }
        }

        var english: String {
            switch self {
            case .undo: "Undo"
            case .redo: "Redo"
            case .eraser: "Eraser on/off"
            case .nextColour: "Next colour"
            case .nextWidth: "Next thickness"
            case .penPicker: "Pen picker"
            case .off: "Off"
            }
        }
    }

    /// How long after the Pencil lifts a finger touch is still taken for the hand coming off.
    var guardPause: Double = PalmGuard.afterPencil
    /// With the wrist guard on: scrolling takes two fingers (a resting hand can never move the
    /// page) or one (quicker, and the guard still ignores a hand-sized touch).
    var twoFingerScroll = true
    /// Apple Pencil Pro.
    var squeeze: Action = .eraser
    /// Two fingers tap to undo, three to redo.
    var fingerTaps = true

    static let guardPauseRange: ClosedRange<Double> = 0...1

    private static let pauseKey = "pencil.guardPause"
    private static let twoFingerKey = "pencil.twoFingerScroll"
    private static let squeezeKey = "pencil.squeeze"
    private static let fingerTapsKey = "pencil.fingerTaps"

    static var stored: PencilPrefs {
        let defaults = UserDefaults.standard
        var prefs = PencilPrefs()
        if let pause = defaults.object(forKey: pauseKey) as? Double {
            prefs.guardPause = min(max(pause, guardPauseRange.lowerBound), guardPauseRange.upperBound)
        }
        if let two = defaults.object(forKey: twoFingerKey) as? Bool { prefs.twoFingerScroll = two }
        if let squeeze = defaults.string(forKey: squeezeKey).flatMap(Action.init(rawValue:)) { prefs.squeeze = squeeze }
        if let taps = defaults.object(forKey: fingerTapsKey) as? Bool { prefs.fingerTaps = taps }
        return prefs
    }

    func store() {
        let defaults = UserDefaults.standard
        defaults.set(guardPause, forKey: Self.pauseKey)
        defaults.set(twoFingerScroll, forKey: Self.twoFingerKey)
        defaults.set(squeeze.rawValue, forKey: Self.squeezeKey)
        defaults.set(fingerTaps, forKey: Self.fingerTapsKey)
    }
}

@MainActor
@Observable
final class PencilBoard {
    static let wristGuardKey = "pencil.wristGuard"
    /// Before the wrist guard there was a finger-drawing switch, its opposite.
    static let legacyFingerDrawsKey = "pencil.fingerDraws"

    var tool: PencilTool = .pen {
        didSet {
            if tool != .eraser { lastInk = tool }
            push()
        }
    }

    /// The pen or the highlighter, whichever was in hand before the eraser: where a squeeze set to
    /// the eraser goes back to.
    private(set) var lastInk: PencilTool = .pen

    var eraserSize: PencilEraserSize {
        didSet {
            UserDefaults.standard.set(eraserSize.rawValue, forKey: PencilEraserSize.key)
            // Choosing a size means erasing with it.
            if tool != .eraser { tool = .eraser }
            push()
        }
    }

    var highlighter: PencilHighlighter {
        didSet {
            highlighter.store()
            // Choosing a colour means marking with it.
            if tool != .highlighter { tool = .highlighter }
            push()
        }
    }

    var pen: PencilPen {
        didSet {
            pen.store()
            // Choosing a pen means writing with it.
            if tool != .pen { tool = .pen }
            push()
        }
    }

    /// The Atelier's brush (`PencilStudioBrush`): set by that screen only, never stored here, so
    /// the Schreibblatt and worksheets keep their plain pens. While set, the pen draws with it.
    var studioBrush: PencilStudioBrush? {
        didSet {
            if studioBrush != nil, tool != .pen { tool = .pen }
            push()
        }
    }

    /// The gear's settings.
    var prefs: PencilPrefs {
        didSet {
            prefs.store()
            push()
        }
    }

    /// On: only the Pencil writes, and a hand resting on the glass neither writes, scrolls nor
    /// taps. Off: a finger writes too, and scrolling takes two.
    var wristGuard: Bool {
        didSet {
            UserDefaults.standard.set(wristGuard, forKey: Self.wristGuardKey)
            push()
            guard wristGuard != oldValue else { return }
            announce(wristGuard
                     ? "Wrist guard on: only the Pencil writes. Scroll with "
                        + (prefs.twoFingerScroll ? "two fingers." : "one finger.")
                     : "Wrist guard off: a finger writes too.",
                     symbol: wristGuard ? "hand.raised.fill" : "hand.draw")
        }
    }

    /// A word beside the rail for a moment: what a squeeze just switched to, or the wrist guard.
    struct Notice: Equatable {
        let id = UUID()
        let text: String
        let symbol: String
    }

    private(set) var notice: Notice?
    /// Bumped to open the pen picker on the rail (a squeeze set to it).
    private(set) var penPickerRequest = 0

    func announce(_ text: String, symbol: String) {
        notice = Notice(text: text, symbol: symbol)
    }

    /// What a squeeze was set to do. Nothing on a finished page.
    func perform(_ action: PencilPrefs.Action) {
        guard !isLocked else { return }
        switch action {
        case .undo:
            undo()
        case .redo:
            redo()
        case .eraser:
            toggleEraser()
            switch tool {
            case .eraser: announce("Radierer · Eraser", symbol: "eraser")
            case .highlighter: announce("Textmarker · Highlighter", symbol: "highlighter")
            case .pen: announce("\(pen.ink.title) · \(pen.ink.english)", symbol: pen.ink.systemImage)
            }
        case .nextColour:
            // The colour of whatever is in hand: the highlighter's own, or the pen's.
            if tool == .highlighter {
                let shades = PencilHighlighter.Shade.allCases
                let next = shades[((shades.firstIndex(of: highlighter.shade) ?? -1) + 1) % shades.count]
                highlighter.shade = next
                announce("\(next.title) · \(next.english)", symbol: "highlighter")
            } else {
                let shades = PencilPen.Shade.offered(onDark: darkPaper)
                let next = shades[((shades.firstIndex(of: pen.shade) ?? -1) + 1) % shades.count]
                pen.shade = next
                announce("\(next.title(onDark: darkPaper)) · \(next.english(onDark: darkPaper))",
                         symbol: "paintpalette.fill")
            }
        case .nextWidth:
            let weights = PencilPen.Weight.allCases
            if tool == .highlighter {
                let next = weights[((weights.firstIndex(of: highlighter.weight) ?? -1) + 1) % weights.count]
                highlighter.weight = next
                announce("\(next.title) · \(next.english)", symbol: "lineweight")
            } else {
                let next = weights[((weights.firstIndex(of: pen.weight) ?? -1) + 1) % weights.count]
                pen.weight = next
                announce("\(next.title) · \(next.english)", symbol: "lineweight")
            }
        case .penPicker:
            if tool != .pen { tool = .pen }
            penPickerRequest += 1
        case .off:
            break
        }
    }

    /// A finished page: the canvas only scrolls and zooms, and the rail steps aside.
    var isLocked = false {
        didSet { push() }
    }

    /// The screen's paper is dark: colours are chosen as they look on it (`PencilPen.Shade`).
    var darkPaper = false {
        didSet { push() }
    }

    private(set) var canUndo = false
    private(set) var canRedo = false
    /// Strokes on the attached canvas right now, ahead of the debounced save; 0 when detached.
    /// What a screen asks before doing something that only makes sense on a blank page.
    private(set) var strokeCount = 0
    /// Where the pen's newest stroke landed, in the canvas's sheet space (the paper's own points,
    /// unzoomed); nil until one does. A screen that knows its paper reads where the learner is
    /// writing from it: the Schreibblatt's crib sheet marks that row. Highlighter strokes and
    /// erasing leave it alone.
    private(set) var lastStroke: CGRect?

    init() {
        pen = PencilPen.stored
        highlighter = PencilHighlighter.stored
        eraserSize = PencilEraserSize.stored
        prefs = PencilPrefs.stored
        wristGuard = Self.storedWristGuard
    }

    /// The learner's choice; else the old finger switch turned around; else the system's "Only Draw
    /// with Apple Pencil", so the simulator and an iPad without a Pencil can still write. The
    /// first Pencil touch turns it on if nobody has chosen (`pencilSeen`).
    private static var storedWristGuard: Bool {
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: wristGuardKey) as? Bool { return stored }
        if let fingerDraws = defaults.object(forKey: legacyFingerDrawsKey) as? Bool { return !fingerDraws }
        #if canImport(UIKit)
        return UIPencilInteraction.prefersPencilOnlyDrawing
        #else
        return false
        #endif
    }

    func toggleEraser() {
        tool = tool == .eraser ? lastInk : .eraser
    }

    /// The canvas's delegate reports every change of the drawing here.
    func inkChanged(strokeCount: Int) {
        if self.strokeCount != strokeCount { self.strokeCount = strokeCount }
    }

    /// A new stroke joined the drawing (the surface reports its bounds in sheet space). Only the
    /// pen's count: a highlighter mark is not writing.
    func strokeLanded(_ bounds: CGRect) {
        guard tool == .pen, !bounds.isNull, !bounds.isEmpty else { return }
        lastStroke = bounds
    }

    /// A Pencil touched the canvas. Whoever writes with one wants their wrist ignored, so the guard
    /// comes on by itself, once, unless it was set by hand.
    func pencilSeen() {
        guard !wristGuard, UserDefaults.standard.object(forKey: Self.wristGuardKey) == nil else { return }
        wristGuard = true
    }

    #if canImport(UIKit)
    @ObservationIgnored private weak var canvas: PencilCanvasView?

    func attach(_ canvas: PencilCanvasView) {
        self.canvas = canvas
        // The other surface (the full-screen slide, say) may have changed them since this board was made.
        if wristGuard != Self.storedWristGuard { wristGuard = Self.storedWristGuard }
        // Reading them back must not change the tool in the learner's hand (a new page's canvas
        // attaches to the same board).
        let inHand = tool
        if pen != PencilPen.stored { pen = PencilPen.stored }
        if highlighter != PencilHighlighter.stored { highlighter = PencilHighlighter.stored }
        if eraserSize != PencilEraserSize.stored { eraserSize = PencilEraserSize.stored }
        if tool != inHand { tool = inHand }
        if prefs != PencilPrefs.stored { prefs = PencilPrefs.stored }
        canvas.onPencilAction = { [weak self] action in self?.perform(action) }
        canvas.onPencilSeen = { [weak self] in self?.pencilSeen() }
        canvas.onUndoStateChange = { [weak self] canUndo, canRedo in
            self?.canUndo = canUndo
            self?.canRedo = canRedo
        }
        push()
        canvas.refreshUndoState()
        strokeCount = canvas.drawing.strokes.count
    }

    /// Only the canvas that is attached: a new page's canvas can be made before the old one goes.
    func detach(_ canvas: PencilCanvasView) {
        guard self.canvas === canvas else { return }
        canvas.onPencilAction = nil
        canvas.onPencilSeen = nil
        canvas.onUndoStateChange = nil
        self.canvas = nil
        canUndo = false
        canRedo = false
        strokeCount = 0
    }

    func undo() { canvas?.undo() }
    func redo() { canvas?.redo() }
    /// Everything off the page, as one step the learner can undo.
    func clear() { canvas?.clear() }

    /// The part of the paper on screen, in sheet space (the paper's own points, unzoomed); nil
    /// with no canvas attached. Read when asked, never observed: scrolling does not redraw a view.
    var visibleSheetRect: CGRect? {
        guard let canvas, canvas.zoomScale > 0, canvas.bounds.width > 0 else { return nil }
        let zoom = canvas.zoomScale
        return CGRect(x: canvas.contentOffset.x / zoom, y: canvas.contentOffset.y / zoom,
                      width: canvas.bounds.width / zoom, height: canvas.bounds.height / zoom)
    }

    /// Scrolls a sheet-space rect into view at the current zoom: its top `padding` below the top
    /// of the screen, and sideways only when it is not already all in view. The zoom is the
    /// learner's and stays. What the Schreibblatt's "Nächste Tabelle" does, so a hand on the glass
    /// with the wrist guard on never has to scroll.
    func reveal(sheetRect rect: CGRect, padding: CGFloat = 20, animated: Bool = true) {
        guard let canvas, canvas.zoomScale > 0, !rect.isNull else { return }
        let zoom = canvas.zoomScale
        let inset = canvas.contentInset
        let size = canvas.bounds.size
        let lowestY = max(-inset.top, canvas.contentSize.height + inset.bottom - size.height)
        let farthestX = max(-inset.left, canvas.contentSize.width + inset.right - size.width)

        var x = canvas.contentOffset.x
        let shownMinX = x / zoom
        let shownMaxX = shownMinX + size.width / zoom
        if rect.minX < shownMinX || rect.maxX > shownMaxX {
            x = (rect.minX - padding) * zoom
        }
        let y = (rect.minY - padding) * zoom
        let target = CGPoint(x: min(max(-inset.left, x), farthestX), y: min(max(-inset.top, y), lowestY))
        canvas.setContentOffset(target, animated: animated)
    }

    private func push() {
        canvas?.darkPaper = darkPaper
        canvas?.prefs = prefs
        canvas?.pen = pen
        canvas?.highlighter = highlighter
        canvas?.studioBrush = studioBrush
        canvas?.eraserWidth = eraserSize.width
        canvas?.pencilTool = tool
        canvas?.wristGuard = wristGuard
        canvas?.isLocked = isLocked
    }
    #else
    func undo() {}
    func redo() {}
    func clear() {}
    var visibleSheetRect: CGRect? { nil }
    func reveal(sheetRect rect: CGRect, padding: CGFloat = 20, animated: Bool = true) {}
    private func push() {}
    #endif
}
