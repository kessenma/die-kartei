//
//  SchreibblattCelebration.swift
//  german-ai-flashcards
//
//  The finish: a whole set written (or a sheet on its own) and, usually, its last round of
//  flashcards done. Die Figur cheers beside a gold trophy, Bauhaus confetti falls once, and one
//  writing number shows (`SchreibblattStats`, a different one each time; tap for another).
//  "Fertig" leaves the whole flow, back to where the writing started (`schreibblattLeave`), not
//  to the setup screen it was made from.
//
//  The scene is the shipped „sich freuen über" verb scene (`verb3d-freuen_ueber.usdz`, authored in
//  tools/blender/verben.py with figur.py's `jubel` clip): the figure, the trophy as its subject,
//  and the slab it stands on. Here the trophy is tinted gold and the clip plays three times, then
//  holds its first pose, arms up. Lightweight graphics and Reduce Motion get the scene's still.
//

import RealityKit
import SwiftUI

/// What the finish screen shows.
struct SchreibblattFinish: Identifiable {
    let id = UUID()
    /// "Alle Teile geschafft" or "Blatt geschafft".
    let title: String
    /// "52 Wörter · 6 Teile · each 5×".
    let subtitle: String
    let stats: SchreibblattStats
}

struct SchreibblattCelebration: View {
    let finish: SchreibblattFinish
    /// Fertig: leave the flow. The cover is already on its way down.
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replay = 0
    @State private var cheered = false

    var body: some View {
        ZStack {
            ThemedBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    SchreibblattJubelScene(restartToken: replay)
                        .frame(height: 300)
                        .frame(maxWidth: 520)
                        .contentShape(Rectangle())
                        .onTapGesture { replay += 1 }
                        .accessibilityLabel("Die Figur cheers beside a gold trophy")

                    VStack(spacing: 6) {
                        Text(finish.title)
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(finish.subtitle)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    SchreibblattStatCard(stats: finish.stats, large: true)
                        .frame(maxWidth: 420)

                    Button {
                        dismiss()
                        onDone()
                    } label: {
                        Text("Fertig")
                            .font(.headline)
                            .frame(maxWidth: 280)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SchreibblattTile.tint)
                    .controlSize(.large)
                    .padding(.top, 8)
                    .accessibilityHint("Back to your sheets")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }

            if !reduceMotion {
                BauhausConfetti(restartToken: replay)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.success, trigger: cheered)
        .onAppear { cheered = true }
    }
}

// MARK: - The scene

/// Die Figur cheering beside the trophy: the „sich freuen über" scene, trophy in gold.
struct SchreibblattJubelScene: View {
    static let asset = "verb3d-freuen_ueber"
    static let gold = Color(light: 0xD9A21B, dark: 0xF0C24B)
    /// Three cheers, then the clip holds its first pose (arms up).
    static let cheers = 3

    /// Bump to cheer again without rebuilding the RealityKit surface (see `FigurSceneView`).
    var restartToken: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var root = Entity()
    @State private var camera = PerspectiveCamera()
    @State private var loaded: Entity?
    @State private var isAnimating = false
    @State private var stopper: Task<Void, Never>?

    var body: some View {
        if LightweightGraphics.isActive || reduceMotion {
            still
        } else {
            TimelineView(.animation(paused: !isAnimating)) { context in
                canvas(beat: context.date)
            }
            .task { await load() }
            .onChange(of: restartToken) { cheer() }
            .onDisappear { stopper?.cancel(); isAnimating = false }
        }
    }

    /// The scene's own still, on a light disc so the charcoal figure reads on a dark ground too.
    private var still: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.96))
                .frame(width: 260, height: 260)
            if let image = UIImage(named: "\(Self.asset)-neutral-dim") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
            }
        }
    }

    private func canvas(beat: Date) -> some View {
        RealityView { content in
            camera.camera.fieldOfViewInDegrees = 30
            content.add(camera)
            for light in SceneRig.lights() { content.add(light) }
            content.add(root)
        } update: { _ in
            // Reading the beat makes each tick a change, so the frame is presented (FigurSceneView).
            _ = beat
        }
    }

    private func load() async {
        guard loaded == nil,
              let scene = try? await Entity(named: Self.asset, in: .main) else { return }
        scene.removeCamerasAndLights()
        scene.tintEveryModel(FigurScene.defaultTint)
        Self.subject(in: scene)?.tintEveryModel(Self.gold)
        // Framed on the bind pose: the figure and the trophy, centred, the jump's headroom kept.
        let bounds = scene.visualBounds(relativeTo: nil)
        let target = bounds.center + SIMD3<Float>(0, 0.08, 0)
        SceneRig.aim(camera, at: target, distance: 5.4)
        loaded = scene
        root.addChild(scene)
        cheer()
    }

    /// The trophy: the scene's `subject` prim (the name the verb rig gives the tinted object).
    private static func subject(in scene: Entity) -> Entity? {
        var queue = Array(scene.children)
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next.name.lowercased().contains("subject") { return next }
            queue.append(contentsOf: next.children)
        }
        return nil
    }

    private func cheer() {
        guard let scene = loaded else { return }
        let clips = scene.availableAnimations
        guard let clip = clips.first(where: { $0.name == "global scene animation" })
                ?? clips.max(by: { $0.definition.duration < $1.definition.duration })
        else { return }
        scene.stopAllAnimations(recursive: true)
        scene.playAnimation(clip.repeat(count: Self.cheers))
        stopper?.cancel()
        isAnimating = true
        let length = clip.definition.duration * Double(Self.cheers)
        stopper = Task { @MainActor in
            try? await Task.sleep(for: .seconds(length + 0.4))
            guard !Task.isCancelled else { return }
            isAnimating = false
        }
    }
}

// MARK: - Confetti

/// Circles, squares, triangles and half-discs in the Bauhaus primaries, falling once and gone.
/// Each piece is a small view animated from above the top edge to below the bottom one by Core
/// Animation, so nothing ticks on the main thread and the end state is empty.
struct BauhausConfetti: View {
    var restartToken: Int = 0

    private struct Piece: Identifiable {
        let id: Int
        var x: CGFloat          // 0…1 across
        var drift: CGFloat      // sideways travel over the fall, points
        var delay: Double       // seconds before it starts falling
        var fall: Double        // seconds from top to bottom
        var turns: Double       // turns over the fall
        var size: CGFloat
        var shape: Int          // 0 circle, 1 square, 2 triangle, 3 half-disc
        var color: Color
    }

    private static let colors: [Color] = [
        Color(red: 0.86, green: 0.20, blue: 0.16),   // red
        Color(red: 0.96, green: 0.76, blue: 0.13),   // yellow
        Color(red: 0.11, green: 0.33, blue: 0.64),   // blue
        Color(white: 0.16),                          // black
    ]

    @State private var pieces: [Piece] = []
    @State private var fallen = false
    /// New ids on every start, so a replay builds fresh pieces at the top instead of animating the
    /// old ones back up.
    @State private var generation = 0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                ForEach(pieces) { piece in
                    BauhausShape(kind: piece.shape)
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size)
                        .rotationEffect(.degrees(fallen ? piece.turns * 360 : 0))
                        .position(x: piece.x * size.width + (fallen ? piece.drift : 0),
                                  y: fallen ? size.height + piece.size * 2 : -piece.size * 2)
                        .animation(.linear(duration: piece.fall).delay(piece.delay), value: fallen)
                }
            }
        }
        .onAppear(perform: start)
        .onChange(of: restartToken) { start() }
    }

    private func start() {
        fallen = false
        generation += 1
        let base = generation * 1000
        pieces = (0..<90).map { index in
            Piece(id: base + index, x: .random(in: 0.02...0.98), drift: .random(in: -60...60),
                  delay: .random(in: 0...1.4), fall: .random(in: 2.6...4.4),
                  turns: .random(in: -2...2), size: .random(in: 8...16),
                  shape: .random(in: 0...3), color: Self.colors.randomElement() ?? .red)
        }
        // A beat later, so the pieces are laid out above the top before they are told to fall.
        DispatchQueue.main.async { fallen = true }
    }
}

/// One piece of the confetti.
private struct BauhausShape: Shape {
    let kind: Int

    func path(in rect: CGRect) -> Path {
        switch kind {
        case 0: return Path(ellipseIn: rect)
        case 1: return Path(rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08))
        case 2:
            var p = Path()
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        default:
            var p = Path()
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                     startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
            return p
        }
    }
}

// MARK: - The writing numbers

/// One writing number at a time: the next in turn each time it appears (kept in
/// `schreibblatt.lastStat`), another on a tap.
struct SchreibblattStatCard: View {
    let stats: SchreibblattStats
    /// The finish screen's size: centred, a bigger number.
    var large = false

    @AppStorage("schreibblatt.lastStat") private var lastStat = ""
    @State private var current: SchreibblattStats.Stat?

    var body: some View {
        ZStack {
            if let current {
                Button(action: advance) {
                    card(current)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(stats.stats.count > 1 ? "Shows another number" : "")
            } else {
                // Something to appear, so the first number is picked (an empty view never does).
                Color.clear.frame(height: 1)
            }
        }
        .onAppear { if current == nil { advance() } }
    }

    private func card(_ stat: SchreibblattStats.Stat) -> some View {
        let layout = large
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return layout {
            Image(systemName: stat.symbol)
                .font(large ? .title2 : .title3)
                .foregroundStyle(SchreibblattTile.tint)
                .frame(width: 44, height: 44)
                .background(SchreibblattTile.tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: large ? .center : .leading, spacing: 2) {
                Text(stat.value)
                    .font(.system(size: large ? 44 : 28, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(stat.title)
                    .font(.subheadline.weight(.semibold))
                Text(stat.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(large ? .center : .leading)
            if !large { Spacer(minLength: 0) }
        }
        .padding(large ? 20 : 14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func advance() {
        guard let next = stats.next(after: current?.id ?? (lastStat.isEmpty ? nil : lastStat)) else { return }
        withAnimation(.snappy(duration: 0.3)) { current = next }
        lastStat = next.id
    }
}
