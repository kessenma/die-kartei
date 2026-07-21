import SwiftUI

/// The per-phase hero animations for `GeneratingStoryView`.
///
/// Each generation phase gets its own motif so the wait reads as progress rather than one
/// looping spinner: the tutor warming up, the page being written, questions popping in, the
/// glossary pairing words, and the illustrator resolving a picture out of noise.

// MARK: - Shared chrome

/// Paper/ink colors shared by every phase animation so they feel like one set.
struct StoryAnimationPalette {
    var colorScheme: ColorScheme
    var accent: Color

    var card: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.20)
            : Color(red: 0.99, green: 0.98, blue: 0.96)
    }
    var line: Color {
        colorScheme == .dark
            ? Color(red: 0.42, green: 0.46, blue: 0.55).opacity(0.55)
            : Color(red: 0.66, green: 0.72, blue: 0.82).opacity(0.7)
    }
    var border: Color {
        accent.opacity(colorScheme == .dark ? 0.5 : 0.35)
    }

    var page: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(card)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }
}

extension View {
    /// Steps a looping animation from `.task`, so the loop dies with the view when the phase
    /// changes — unlike a repeating `Timer`, which would outlive it.
    @MainActor
    func run(every seconds: Double, _ step: @MainActor () -> Void) async {
        step()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            step()
        }
    }
}

/// Two tilted pages behind the active one, giving every phase the same sense of depth.
private struct PageBacking: View {
    var palette: StoryAnimationPalette
    var size: CGSize

    var body: some View {
        ZStack {
            palette.page
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(0.06), radius: 5, y: 3)
                .offset(x: 8, y: 7)
                .rotationEffect(.degrees(3))

            palette.page
                .frame(width: size.width, height: size.height)
                .shadow(color: .black.opacity(0.06), radius: 5, y: 3)
                .offset(x: -5, y: 4)
                .rotationEffect(.degrees(-2))
        }
    }
}

/// Picks the animation for the current phase and cross-fades when the phase changes.
struct StoryPhaseAnimation: View {
    var phase: StoryStudyService.Phase
    var accent: Color
    var imageSlot: Int
    var imageTotal: Int
    var imageStep: Double
    var imageStage: StoryStudyService.ImageStage

    @Environment(\.colorScheme) private var colorScheme

    private var palette: StoryAnimationPalette {
        StoryAnimationPalette(colorScheme: colorScheme, accent: accent)
    }

    var body: some View {
        ZStack {
            // Soft brand glow tying the overlay to the generating model.
            Ellipse()
                .fill(accent)
                .frame(width: 250, height: 180)
                .opacity(0.18)
                .blur(radius: 45)

            content
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                    removal: .scale(scale: 1.05).combined(with: .opacity)
                ))
        }
        .animation(.easeInOut(duration: 0.4), value: phaseKey)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loadingModel:
            WarmingTutorAnimation(palette: palette)
        case .questions:
            QuestionsAnimation(palette: palette)
        case .glossary:
            GlossaryAnimation(palette: palette)
        case .illustrating:
            IllustratingAnimation(
                palette: palette,
                slot: imageSlot,
                total: imageTotal,
                step: imageStep,
                stage: imageStage
            )
        default:
            WritingAnimation(palette: palette)
        }
    }

    /// Transitions key off the phase group, not the associated value, so a failure message
    /// change can't restart the animation.
    private var phaseKey: Int {
        switch phase {
        case .loadingModel:  0
        case .questions:     2
        case .glossary:      3
        case .illustrating:  4
        default:             1
        }
    }
}

// MARK: - 1. Loading the model

/// A closed book with a light sweeping across the cover and rings rippling outward: the tutor
/// waking up before it writes anything.
private struct WarmingTutorAnimation: View {
    var palette: StoryAnimationPalette

    @State private var ripple = false
    @State private var sweep = false
    @State private var dotPhase = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.accent.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 150, height: 182)
                    .scaleEffect(ripple ? 1.35 : 0.94)
                    .opacity(ripple ? 0 : 0.55)
                    .animation(
                        .easeOut(duration: 2.4)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.8),
                        value: ripple
                    )
            }

            cover
                .frame(width: 142, height: 176)
                .shadow(color: .black.opacity(0.12), radius: 7, y: 4)
        }
        .onAppear {
            ripple = true
            sweep = true
            dotPhase = true
        }
    }

    private var cover: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.card)

            // Spine
            Rectangle()
                .fill(palette.accent.opacity(0.85))
                .frame(width: 11)

            VStack(alignment: .leading, spacing: 9) {
                Capsule()
                    .fill(palette.accent.opacity(0.75))
                    .frame(width: 68, height: 9)
                Capsule()
                    .fill(palette.line)
                    .frame(width: 46, height: 6)

                Spacer()

                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 7, height: 7)
                            .opacity(dotPhase ? 1 : 0.25)
                            .scaleEffect(dotPhase ? 1 : 0.7)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(i) * 0.18),
                                value: dotPhase
                            )
                    }
                }
            }
            .padding(.leading, 26)
            .padding([.trailing, .vertical], 18)
        }
        .overlay {
            // Light sweeping across the cover while the weights load.
            LinearGradient(
                colors: [.clear, palette.accent.opacity(0.45), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 60)
            .rotationEffect(.degrees(22))
            .offset(x: sweep ? 130 : -130)
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false), value: sweep)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

// MARK: - 2. Writing the story

/// A page that writes its ruled lines in behind a blinking caret, then turns to a fresh page.
private struct WritingAnimation: View {
    var palette: StoryAnimationPalette

    @State private var pageIndex = 0
    @State private var writeAmount: CGFloat = 0
    @State private var caretOn = true

    /// Width fractions of each ruled "text" line: an uneven ragged-right paragraph shape.
    private let lineWidths: [CGFloat] = [0.92, 0.74, 0.86, 0.62, 0.8, 0.5]
    private let lineBase: CGFloat = 122

    var body: some View {
        ZStack {
            PageBacking(palette: palette, size: CGSize(width: 168, height: 196))

            writingPage
                .frame(width: 168, height: 196)
                .shadow(color: .black.opacity(0.12), radius: 7, y: 4)
                .id(pageIndex)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .scale(scale: 1.06).combined(with: .opacity)
                ))
        }
        // A `.task` loop rather than a repeating Timer: it cancels with the view when the phase
        // moves on, instead of firing for the rest of the session.
        .task {
            animateWriting()
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) { caretOn = false }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.7))
                guard !Task.isCancelled else { break }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    pageIndex += 1
                }
                writeAmount = 0
                animateWriting()
            }
        }
    }

    private var writingPage: some View {
        palette.page.overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                // Title bar in the brand accent.
                Capsule()
                    .fill(palette.accent.opacity(0.85))
                    .frame(width: 74, height: 9)
                    .scaleEffect(x: max(0.15, writeAmount), anchor: .leading)
                    .padding(.bottom, 4)

                ForEach(lineWidths.indices, id: \.self) { i in
                    line(at: i)
                }
            }
            .padding(20)
        }
    }

    private func line(at index: Int) -> some View {
        let width = lineWidths[index] * lineBase
        let filled = lineProgress(for: index)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(palette.line)
                .frame(width: width, height: 5)
                .scaleEffect(x: filled, anchor: .leading)
                .opacity(filled > 0.02 ? 1 : 0)

            // Caret rides the line that is currently being written.
            if filled > 0.02, filled < 0.99 {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 2.5, height: 13)
                    .offset(x: width * filled)
                    .opacity(caretOn ? 1 : 0.2)
            }
        }
        .frame(height: 5)
    }

    /// Lines fill in sequence as `writeAmount` grows 0→1, so text appears to be written top-down.
    private func lineProgress(for index: Int) -> CGFloat {
        let count = CGFloat(lineWidths.count)
        let start = CGFloat(index) / count
        let filled = (writeAmount - start) * count
        return min(max(filled, 0), 1)
    }

    private func animateWriting() {
        withAnimation(.easeOut(duration: 2.1)) {
            writeAmount = 1
        }
    }
}

// MARK: - 3. Writing the questions

/// Question rows slide onto the page one at a time, each ticking an answer as it lands.
private struct QuestionsAnimation: View {
    var palette: StoryAnimationPalette

    @State private var shown = 0
    private let rowCount = 3

    var body: some View {
        ZStack {
            PageBacking(palette: palette, size: CGSize(width: 168, height: 196))

            palette.page
                .frame(width: 168, height: 196)
                .shadow(color: .black.opacity(0.12), radius: 7, y: 4)
                .overlay {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(0..<rowCount, id: \.self) { i in
                            questionRow(at: i)
                                // Rows not yet "asked" stay as faint placeholders so the page
                                // keeps its composition instead of emptying out each cycle.
                                .opacity(i < shown ? 1 : 0.12)
                                .offset(x: i < shown ? 0 : 22)
                        }
                    }
                    .padding(18)
                }
        }
        .task { await run(every: 0.75) { advance() } }
    }

    private func questionRow(at index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.18))
                Text("?")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.accent)
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 6) {
                Capsule()
                    .fill(palette.line)
                    .frame(width: index == 1 ? 80 : 94, height: 5)

                HStack(spacing: 5) {
                    // The answer key ticking in behind each question.
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(palette.accent)
                        .scaleEffect(index < shown ? 1 : 0.2)
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.6).delay(0.25),
                            value: shown
                        )
                    Capsule()
                        .fill(palette.line.opacity(0.6))
                        .frame(width: index == 2 ? 52 : 64, height: 4)
                }
            }
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            shown = shown >= rowCount ? 0 : shown + 1
        }
    }
}

// MARK: - 4. Building the glossary

/// German and English chips fly in from opposite sides and pair up, row after row.
private struct GlossaryAnimation: View {
    var palette: StoryAnimationPalette

    @State private var shown = 0
    private let rows: [(CGFloat, CGFloat)] = [(46, 38), (34, 50), (52, 32), (40, 44), (36, 46)]

    var body: some View {
        ZStack {
            PageBacking(palette: palette, size: CGSize(width: 168, height: 196))

            palette.page
                .frame(width: 168, height: 196)
                .shadow(color: .black.opacity(0.12), radius: 7, y: 4)
                .overlay {
                    VStack(spacing: 18) {
                        ForEach(rows.indices, id: \.self) { i in
                            pairRow(at: i)
                        }
                    }
                    .padding(.horizontal, 16)
                }
        }
        .task { await run(every: 0.6) { advance() } }
    }

    private func pairRow(at index: Int) -> some View {
        let landed = index < shown
        return HStack(spacing: 7) {
            Capsule()
                .fill(palette.accent.opacity(0.8))
                .frame(width: rows[index].0, height: 7)
                .offset(x: landed ? 0 : -22)

            Image(systemName: "arrow.right")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(palette.line)

            Capsule()
                .fill(palette.line)
                .frame(width: rows[index].1, height: 7)
                .offset(x: landed ? 0 : 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Un-paired rows linger as faint placeholders rather than leaving blank paper.
        .opacity(landed ? 1 : 0.12)
    }

    private func advance() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            shown = shown >= rows.count ? 0 : shown + 1
        }
    }
}

// MARK: - 5. Creating the images

/// A framed canvas where a scene resolves out of noise as the diffusion steps land, plus a
/// filmstrip of the run's picture slots so the wait has a visible end.
private struct IllustratingAnimation: View {
    var palette: StoryAnimationPalette
    var slot: Int
    var total: Int
    var step: Double
    var stage: StoryStudyService.ImageStage

    @State private var noiseFlip = false
    @State private var scan = false

    /// 0 while planning and loading, then the current image's diffusion progress.
    private var reveal: Double {
        stage == .rendering ? min(max(step, 0), 1) : 0
    }
    private var isRendering: Bool { stage == .rendering }

    var body: some View {
        VStack(spacing: 16) {
            canvas
                .frame(width: 176, height: 132)
                .shadow(color: .black.opacity(0.12), radius: 7, y: 4)

            if total > 0 {
                filmstrip
            }
        }
        .onAppear {
            noiseFlip = true
            scan = true
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.card)

            scene
                .opacity(reveal)
                .blur(radius: 14 * (1 - reveal))
                .saturation(0.25 + 0.75 * reveal)

            noiseField
                .opacity(1 - reveal * 0.95)

            if isRendering {
                scanLine
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .overlay(cornerBrackets)
        .animation(.easeOut(duration: 0.4), value: reveal)
    }

    /// A generic landscape standing in for whatever is being drawn: sky, sun, two hills.
    private var scene: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [palette.accent.opacity(0.55), palette.accent.opacity(0.12)],
                    startPoint: .top, endPoint: .bottom
                )

                Circle()
                    .fill(.white.opacity(0.75))
                    .frame(width: w * 0.16)
                    .offset(x: w * 0.24, y: -h * 0.42)

                Ellipse()
                    .fill(palette.accent.opacity(0.75))
                    .frame(width: w * 1.1, height: h * 0.62)
                    .offset(x: -w * 0.3, y: h * 0.2)

                Ellipse()
                    .fill(palette.accent)
                    .frame(width: w * 0.95, height: h * 0.5)
                    .offset(x: w * 0.28, y: h * 0.16)
            }
        }
    }

    /// Coarse blocks flickering like sampling noise. Seeded, so the pattern is stable across
    /// redraws instead of reshuffling every frame.
    private var noiseField: some View {
        GeometryReader { geo in
            let cols = 8
            let rows = 6
            let cw = geo.size.width / CGFloat(cols)
            let ch = geo.size.height / CGFloat(rows)
            ZStack(alignment: .topLeading) {
                ForEach(0..<(cols * rows), id: \.self) { i in
                    let seed = Self.seed(i)
                    let alt = Self.seed(i + 97)
                    Rectangle()
                        .fill(palette.line.opacity(0.25 + 0.5 * (noiseFlip ? seed : alt)))
                        .frame(width: cw, height: ch)
                        .offset(
                            x: cw * CGFloat(i % cols),
                            y: ch * CGFloat(i / cols)
                        )
                        .animation(
                            .easeInOut(duration: 0.5 + 0.4 * seed).repeatForever(),
                            value: noiseFlip
                        )
                }
            }
        }
        .blur(radius: 2)
    }

    private var scanLine: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, palette.accent.opacity(0.5), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 30)
            .offset(y: scan ? geo.size.height : -30)
            .animation(.linear(duration: 1.6).repeatForever(autoreverses: false), value: scan)
        }
    }

    private var cornerBrackets: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                CornerBracket()
                    .stroke(palette.accent.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(Double(i) * 90))
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: Self.bracketAlignment(i)
                    )
            }
        }
        .padding(7)
    }

    // MARK: Filmstrip

    private var filmstrip: some View {
        HStack(spacing: 9) {
            ForEach(0..<total, id: \.self) { i in
                slotThumb(at: i)
            }
        }
    }

    @ViewBuilder
    private func slotThumb(at index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        if index < slot {
            // Finished picture
            shape
                .fill(palette.accent)
                .frame(width: 30, height: 22)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                )
        } else if index == slot, isRendering {
            // In progress: fills left to right with the diffusion steps
            shape
                .fill(palette.line.opacity(0.25))
                .frame(width: 30, height: 22)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.accent.opacity(0.85))
                        .frame(width: 30 * min(max(step, 0), 1))
                        .animation(.linear(duration: 0.3), value: step)
                }
                .clipShape(shape)
                .overlay(shape.stroke(palette.accent, lineWidth: 1.5))
        } else {
            shape
                .stroke(palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                .frame(width: 30, height: 22)
        }
    }

    // MARK: Helpers

    /// Deterministic 0…1 value per cell — the usual fract(sin) hash, no RNG state to carry.
    private static func seed(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return x - x.rounded(.down)
    }

    private static func bracketAlignment(_ i: Int) -> Alignment {
        switch i {
        case 0: .topLeading
        case 1: .topTrailing
        case 2: .bottomTrailing
        default: .bottomLeading
        }
    }
}

/// An L-shaped viewfinder corner, drawn top-left and rotated into the other three corners.
private struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}
