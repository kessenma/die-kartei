//
//  PencilRail.swift
//  german-ai-flashcards
//
//  The slim dock beside a Pencil canvas, in place of the system tool picker: pen, highlighter,
//  eraser, undo, redo, the wrist guard, settings and the tips. Tapping the pen or the highlighter
//  while it is in hand opens its picker (ink, colour, thickness); the gear opens the settings that
//  would clutter the dock (the wrist guard's scrolling and pause, the squeeze, the finger taps, the
//  dock's edge, and the screen's own canvas settings, such as a Schreibblatt's paper).
//
//  It sits in its own strip on one edge of the canvas (the page fits beside it, never under it),
//  upright on the left or right, lying flat along the top or bottom. Dragged by its handle it
//  follows the finger anywhere, turns to match the edge it is nearest, and settles on that edge
//  where it was let go. The edge and the place along it are kept.
//
//  Every label in German keeps its English beside or under it: the learner is learning German.
//
//  `.pencilRail(board, accent:) { canvas settings }` on the canvas. Nothing on the Mac, which has
//  no canvas to write on.
//

import SwiftUI

extension View {
    func pencilRail(_ board: PencilBoard, accent: Color) -> some View {
        pencilRail(board, accent: accent, canvasSettings: { EmptyView() }, tips: { EmptyView() })
    }

    /// `canvasSettings` joins the gear's panel under "Blatt": controls for this screen's canvas.
    func pencilRail<Canvas: View>(_ board: PencilBoard, accent: Color,
                                  @ViewBuilder canvasSettings: () -> Canvas) -> some View {
        pencilRail(board, accent: accent, canvasSettings: canvasSettings, tips: { EmptyView() })
    }

    /// `tips` joins the "?" sheet: rows (`PencilTipRow`) about this screen's own paper and settings.
    ///
    /// A page with the dock is a drawing page, so it also takes the tab bar away while it is up
    /// (`hidesNavBar()`): nothing under the page can be tapped by a hand resting on the glass.
    func pencilRail<Canvas: View, Tips: View>(_ board: PencilBoard, accent: Color,
                                              @ViewBuilder canvasSettings: () -> Canvas,
                                              @ViewBuilder tips: () -> Tips) -> some View {
        let railed = modifier(PencilRailModifier(board: board, accent: accent,
                                                 canvasSettings: canvasSettings(), tips: tips()))
        #if os(iOS)
        return railed.hidesNavBar()
        #else
        // The Mac's pages are placeholders with nothing to draw on; its tab bar stays.
        return railed
        #endif
    }
}

/// The edge the dock sits on. The raw values carry on the old left/right setting.
private enum PencilRailEdge: String, CaseIterable, Identifiable {
    case leading, trailing, top, bottom

    var id: String { rawValue }

    var axis: Axis {
        switch self {
        case .leading, .trailing: .vertical
        case .top, .bottom: .horizontal
        }
    }

    var edges: Edge.Set {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }

    var title: String {
        switch self {
        case .leading: "Links"
        case .trailing: "Rechts"
        case .top: "Oben"
        case .bottom: "Unten"
        }
    }
}

/// The space the dock is placed and dragged in: the canvas and its strip.
private let pencilRailSpace = "pencilRailArea"

private struct PencilRailModifier<Canvas: View, Tips: View>: ViewModifier {
    let board: PencilBoard
    let accent: Color
    let canvasSettings: Canvas
    let tips: Tips

    @AppStorage("pencil.railSide") private var edge: PencilRailEdge = .leading
    /// Where along its edge the dock's middle sits, 0 to 1.
    @AppStorage("pencil.railPosition") private var along = 0.5
    @State private var area: CGSize = .zero
    @State private var railSize: CGSize = .zero
    /// While the handle is dragged: where the dock's middle is, following the finger.
    @State private var dragCenter: CGPoint?
    @State private var dragStart: CGPoint = .zero
    @State private var showTips = false
    @State private var shownNotice: PencilBoard.Notice?

    /// The dock's own strip, so the page fits next to it rather than under it.
    private static var gutter: CGFloat { 70 }

    func body(content: Content) -> some View {
        #if os(iOS)
        // The same modifiers whether locked or not, so the canvas underneath keeps its identity
        // (a rebuilt canvas would re-read stale ink); a locked page just gets its strip back.
        content
            .padding(edge.edges, board.isLocked ? 0 : Self.gutter)
            // The strip matches what shows around the sheet: grey, or near black around dark paper.
            .background(board.darkPaper ? Color(white: 0.05) : Color(.secondarySystemBackground))
            .overlay(alignment: .topLeading) {
                if !board.isLocked { placedRail }
            }
            .overlay(alignment: .top) {
                notice.padding(.top, 12)
            }
            .coordinateSpace(name: pencilRailSpace)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { area = $0 }
            .onChange(of: board.notice) { _, notice in
                withAnimation(.easeOut(duration: 0.2)) { shownNotice = notice }
            }
            .task(id: shownNotice) {
                guard shownNotice != nil else { return }
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeIn(duration: 0.3)) { shownNotice = nil }
            }
            .sheet(isPresented: $showTips) {
                PencilHelpSheet(accent: accent) { tips }
            }
        #else
        content
        #endif
    }

    // MARK: Placing the dock

    /// Floated over the area at its place, never laid out by it (a positioned child would make the
    /// container claim all the space).
    private var placedRail: some View {
        let center = dragCenter ?? dockedCenter
        let axis = dragCenter.map { nearestEdge(to: $0).axis } ?? edge.axis
        return PencilRail(board: board, accent: accent, axis: axis,
                          settings: PencilSettingsPanel(board: board, edge: $edge, accent: accent,
                                                        canvas: canvasSettings),
                          showTips: { showTips = true },
                          onDrag: drag, onDragEnd: drop)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { railSize = $0 }
            .offset(x: center.x - railSize.width / 2, y: center.y - railSize.height / 2)
    }

    /// The dock's middle on its edge, kept clear of the corners.
    private var dockedCenter: CGPoint {
        let half = (edge.axis == .vertical ? railSize.height : railSize.width) / 2 + 8
        let inset = Self.gutter / 2
        switch edge {
        case .leading:
            return CGPoint(x: inset, y: clamp(along * area.height, half, area.height - half))
        case .trailing:
            return CGPoint(x: area.width - inset, y: clamp(along * area.height, half, area.height - half))
        case .top:
            return CGPoint(x: clamp(along * area.width, half, area.width - half), y: inset)
        case .bottom:
            return CGPoint(x: clamp(along * area.width, half, area.width - half), y: area.height - inset)
        }
    }

    private func drag(_ value: DragGesture.Value) {
        if dragCenter == nil { dragStart = dockedCenter }
        dragCenter = CGPoint(x: dragStart.x + value.translation.width, y: dragStart.y + value.translation.height)
    }

    private func drop(_ value: DragGesture.Value) {
        let point = CGPoint(x: dragStart.x + value.translation.width, y: dragStart.y + value.translation.height)
        let landed = nearestEdge(to: point)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            edge = landed
            along = landed.axis == .vertical
                ? Double(min(max(point.y / max(area.height, 1), 0), 1))
                : Double(min(max(point.x / max(area.width, 1), 0), 1))
            dragCenter = nil
        }
    }

    /// The closest edge; the top or bottom only if the dock fits along it lying flat.
    private func nearestEdge(to point: CGPoint) -> PencilRailEdge {
        let long = max(railSize.width, railSize.height)
        let fitsFlat = area.width >= long + 32
        let distances: [(PencilRailEdge, CGFloat)] = [
            (.leading, point.x), (.trailing, area.width - point.x),
            (.top, fitsFlat ? point.y : .infinity), (.bottom, fitsFlat ? area.height - point.y : .infinity),
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .leading
    }

    private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        low > high ? (low + high) / 2 : min(max(value, low), high)
    }

    // MARK: The notice

    @ViewBuilder
    private var notice: some View {
        if let shownNotice {
            Label(shownNotice.text, systemImage: shownNotice.symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - The dock

struct PencilRail<Settings: View>: View {
    @Bindable var board: PencilBoard
    let accent: Color
    let axis: Axis
    let settings: Settings
    let showTips: () -> Void
    let onDrag: (DragGesture.Value) -> Void
    let onDragEnd: (DragGesture.Value) -> Void

    @State private var choosingPen = false
    @State private var choosingHighlighter = false
    @State private var choosingEraser = false
    @State private var showingSettings = false

    private var upright: Bool { axis == .vertical }

    var body: some View {
        let stack = upright ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        stack {
            handle

            penButton
            highlighterButton
            eraserButton
            separator

            Button(action: board.undo) { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(RailButtonStyle(accent: accent))
                .disabled(!board.canUndo)
                .accessibilityLabel("Undo")
            Button(action: board.redo) { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(RailButtonStyle(accent: accent))
                .disabled(!board.canRedo)
                .accessibilityLabel("Redo")
            separator

            Button {
                board.wristGuard.toggle()
            } label: {
                Image(systemName: board.wristGuard ? "hand.raised.fill" : "hand.draw")
            }
            .buttonStyle(RailButtonStyle(accent: accent, isOn: board.wristGuard))
            .accessibilityLabel("Wrist guard")
            .accessibilityValue(board.wristGuard ? "On, only the Pencil writes" : "Off, a finger writes too")
            separator

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(RailButtonStyle(accent: accent))
            .accessibilityLabel("Pencil settings")
            .popover(isPresented: $showingSettings) {
                settings
                    .presentationCompactAdaptation(.popover)
            }
            Button(action: showTips) { Image(systemName: "questionmark.circle") }
                .buttonStyle(RailButtonStyle(accent: accent))
                .accessibilityLabel("Pencil tips")
        }
        .font(.system(size: 18, weight: .medium))
        .padding(upright ? .horizontal : .vertical, 5)
        .padding(upright ? .bottom : .trailing, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    /// The grip at the dock's start: drag it to move the dock. Only the grip drags, so the buttons
    /// and the gear's slider are never fighting a drag.
    private var handle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.55))
            .frame(width: upright ? 22 : 4, height: upright ? 4 : 22)
            .frame(width: upright ? 44 : 24, height: upright ? 24 : 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(pencilRailSpace))
                    .onChanged(onDrag)
                    .onEnded(onDragEnd)
            )
            .accessibilityLabel("Move the dock")
            .accessibilityHint("Drag to any edge of the page")
    }

    /// The pen in hand shows its ink and colour. Tapped while in hand, it opens the pen picker.
    private var penButton: some View {
        Button {
            if board.tool == .pen { choosingPen = true } else { board.tool = .pen }
        } label: {
            Image(systemName: board.pen.ink.systemImage)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(board.pen.shade.color(onDark: board.darkPaper))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                        .frame(width: 9, height: 9)
                        .offset(x: 6, y: 5)
                }
        }
        .buttonStyle(RailButtonStyle(accent: accent, isSelected: board.tool == .pen))
        .accessibilityLabel("Pen, \(board.pen.ink.english), \(board.pen.shade.english(onDark: board.darkPaper))")
        .accessibilityHint(board.tool == .pen ? "Opens the pen picker" : "")
        .accessibilityAddTraits(board.tool == .pen ? .isSelected : [])
        .onChange(of: board.penPickerRequest) {
            choosingPen = true
        }
        .popover(isPresented: $choosingPen) {
            PencilPenPicker(pen: $board.pen, darkPaper: board.darkPaper, accent: accent)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// The highlighter in hand shows its colour. Tapped while in hand, it opens its picker.
    private var highlighterButton: some View {
        Button {
            if board.tool == .highlighter { choosingHighlighter = true } else { board.tool = .highlighter }
        } label: {
            Image(systemName: "highlighter")
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(board.highlighter.shade.color)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                        .frame(width: 9, height: 9)
                        .offset(x: 6, y: 5)
                }
        }
        .buttonStyle(RailButtonStyle(accent: accent, isSelected: board.tool == .highlighter))
        .accessibilityLabel("Highlighter, \(board.highlighter.shade.english)")
        .accessibilityHint(board.tool == .highlighter ? "Opens the highlighter's colours" : "")
        .accessibilityAddTraits(board.tool == .highlighter ? .isSelected : [])
        .popover(isPresented: $choosingHighlighter) {
            PencilHighlighterPicker(highlighter: $board.highlighter, accent: accent)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// The eraser. Tapped while in hand, it opens its sizes.
    private var eraserButton: some View {
        Button {
            if board.tool == .eraser { choosingEraser = true } else { board.tool = .eraser }
        } label: {
            Image(systemName: "eraser")
        }
        .buttonStyle(RailButtonStyle(accent: accent, isSelected: board.tool == .eraser))
        .accessibilityLabel("Eraser, \(board.eraserSize.english)")
        .accessibilityHint(board.tool == .eraser ? "Opens the eraser's sizes" : "")
        .accessibilityAddTraits(board.tool == .eraser ? .isSelected : [])
        .popover(isPresented: $choosingEraser) {
            PencilEraserPicker(size: $board.eraserSize, accent: accent)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: upright ? 24 : 1, height: upright ? 1 : 24)
            .padding(upright ? .vertical : .horizontal, 3)
    }
}

// MARK: - The gear's panel

/// The settings that would clutter the dock. German headings keep their English beside them.
private struct PencilSettingsPanel<Canvas: View>: View {
    @Bindable var board: PencilBoard
    @Binding var edge: PencilRailEdge
    let accent: Color
    let canvas: Canvas

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                group("Handballen-Schutz · Wrist guard") {
                    Toggle(isOn: $board.wristGuard) {
                        PencilSettingsLabel("An · On", caption: "Only the Pencil writes; your hand on the glass is ignored.")
                    }
                    PencilSettingsRow("Scrollen · Scrolling",
                                      caption: board.wristGuard
                                        ? (board.prefs.twoFingerScroll
                                           ? "Two fingers: a hand resting on the glass can never move the page."
                                           : "One finger: quicker, and a hand-sized touch is still ignored.")
                                        : "With the guard off one finger writes, so scrolling takes two fingers.") {
                        Picker("Scrolling", selection: $board.prefs.twoFingerScroll) {
                            Text("Ein Finger").tag(false)
                            Text("Zwei Finger").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(!board.wristGuard)
                    }
                    PencilSettingsRow("Pause nach dem Stift · Pause after the Pencil: \(pause)",
                                      caption: "How long after the Pencil lifts a finger touch is still taken for your hand.") {
                        Slider(value: $board.prefs.guardPause, in: PencilPrefs.guardPauseRange, step: 0.05) {
                            Text("Pause after the Pencil")
                        } minimumValueLabel: {
                            Text("0").font(.caption2)
                        } maximumValueLabel: {
                            Text("1 s").font(.caption2)
                        }
                        .disabled(!board.wristGuard)
                    }
                }

                group("Stift · Pencil") {
                    PencilSettingsRow("Drücken · Squeeze", caption: "What squeezing Apple Pencil Pro does.") {
                        Picker("Squeeze", selection: $board.prefs.squeeze) {
                            ForEach(PencilPrefs.Action.allCases) { Text("\($0.title) · \($0.english)").tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    Toggle(isOn: $board.prefs.fingerTaps) {
                        PencilSettingsLabel("Fingertippen · Finger taps", caption: "Two fingers undo, three redo.")
                    }
                }

                group("Leiste · Dock") {
                    PencilSettingsRow("Rand · Edge", caption: "Left, right, top or bottom. Or drag the dock by its handle.") {
                        Picker("Edge", selection: $edge) {
                            ForEach(PencilRailEdge.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                if Canvas.self != EmptyView.self {
                    group("Blatt · Sheet") { canvas }
                }
            }
            .padding(16)
        }
        .frame(width: 360)
        .frame(minHeight: 300, idealHeight: Canvas.self == EmptyView.self ? 520 : 720, maxHeight: 760)
        .tint(accent)
    }

    private var pause: String {
        board.prefs.guardPause.formatted(.number.precision(.fractionLength(2))) + " s"
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// A row in the gear's panel: a title (German · English) over its control, an English line under.
struct PencilSettingsRow<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder let content: Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            content
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A toggle's label in the gear's panel: the title and an English line under it.
struct PencilSettingsLabel: View {
    let title: String
    let caption: String

    init(_ title: String, caption: String) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(caption).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The pickers

/// The eraser's sizes, each drawn at its width.
private struct PencilEraserPicker: View {
    @Binding var size: PencilEraserSize
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Radierer · Eraser").font(.headline)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(PencilEraserSize.allCases) { option in
                    Button {
                        size = option
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
                                .frame(width: option.width, height: option.width)
                                .frame(width: 56, height: 56)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(size == option ? accent.opacity(0.15) : Color.clear))
                            BilingualCaption(option.title, option.english)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.english)
                    .accessibilityAddTraits(size == option ? .isSelected : [])
                }
            }
            Text("Circling a word with the eraser still clears the whole word, whatever its size.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Colour and thickness, from the highlighter on the dock.
private struct PencilHighlighterPicker: View {
    @Binding var highlighter: PencilHighlighter
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Textmarker · Highlighter").font(.headline)
            HStack(spacing: 10) {
                ForEach(PencilHighlighter.Shade.allCases) { shade in
                    Button {
                        highlighter.shade = shade
                    } label: {
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(shade.color.opacity(0.75))
                                .frame(width: 34, height: 18)
                                .padding(6)
                                .overlay(Capsule().strokeBorder(highlighter.shade == shade ? accent : .clear, lineWidth: 2.5))
                            BilingualCaption(shade.title, shade.english)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shade.english)
                    .accessibilityAddTraits(highlighter.shade == shade ? .isSelected : [])
                }
            }
            HStack(spacing: 10) {
                ForEach(PencilPen.Weight.allCases) { weight in
                    Button {
                        highlighter.weight = weight
                    } label: {
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(highlighter.shade.color.opacity(0.75))
                                .frame(width: 30, height: 4 + 7 * weight.factor)
                                .frame(width: 44, height: 34)
                                .background(Circle().fill(highlighter.weight == weight ? accent.opacity(0.15) : .clear))
                            BilingualCaption(weight.title, weight.english)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weight.english)
                    .accessibilityAddTraits(highlighter.weight == weight ? .isSelected : [])
                }
            }
        }
        .padding(16)
    }
}

/// Ink, colour and thickness, from the pen on the dock.
private struct PencilPenPicker: View {
    @Binding var pen: PencilPen
    let darkPaper: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stift · Pen").font(.headline)

            HStack(spacing: 8) {
                ForEach(PencilPen.Ink.allCases) { ink in
                    Button {
                        pen.ink = ink
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: ink.systemImage).font(.title3)
                            BilingualCaption(ink.title, ink.english)
                        }
                        .frame(minWidth: 72, minHeight: 60)
                        .foregroundStyle(pen.ink == ink ? accent : Color.primary)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(pen.ink == ink ? accent.opacity(0.15) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ink.english)
                    .accessibilityAddTraits(pen.ink == ink ? .isSelected : [])
                }
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(PencilPen.Shade.offered(onDark: darkPaper)) { shade in
                    Button {
                        pen.shade = shade
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(shade.color(onDark: darkPaper))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                                .frame(width: 30, height: 30)
                                .padding(4)
                                .overlay(Circle().strokeBorder(pen.shade == shade ? accent : .clear, lineWidth: 2.5))
                            BilingualCaption(shade.title(onDark: darkPaper), shade.english(onDark: darkPaper))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shade.english(onDark: darkPaper))
                    .accessibilityAddTraits(pen.shade == shade ? .isSelected : [])
                }
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(PencilPen.Weight.allCases) { weight in
                    Button {
                        pen.weight = weight
                    } label: {
                        VStack(spacing: 4) {
                            Capsule()
                                .fill(pen.shade.color(onDark: darkPaper))
                                .frame(width: 26, height: 2 + 3 * weight.factor)
                                .frame(width: 44, height: 34)
                                .background(Circle().fill(pen.weight == weight ? accent.opacity(0.15) : .clear))
                            BilingualCaption(weight.title, weight.english)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weight.english)
                    .accessibilityAddTraits(pen.weight == weight ? .isSelected : [])
                }
            }
        }
        .padding(16)
    }
}

/// A German word with its English under it, small.
private struct BilingualCaption: View {
    let german: String
    let english: String

    init(_ german: String, _ english: String) {
        self.german = german
        self.english = english
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(german).font(.caption2)
            if english != german {
                Text(english).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A round 44-pt target: filled in the accent when it is the tool in hand, tinted when a toggle is on.
private struct RailButtonStyle: ButtonStyle {
    let accent: Color
    var isSelected = false
    var isOn = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .foregroundStyle(isSelected ? Color(.systemBackground) : isOn ? accent : Color.primary)
            .background {
                Circle().fill(isSelected ? accent : isOn ? accent.opacity(0.18) : .clear)
            }
            .contentShape(Circle())
            .opacity(!isEnabled ? 0.3 : configuration.isPressed ? 0.6 : 1)
    }
}
