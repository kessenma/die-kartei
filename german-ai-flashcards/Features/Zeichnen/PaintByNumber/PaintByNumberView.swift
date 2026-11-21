//
//  PaintByNumberView.swift
//  german-ai-flashcards
//
//  Painting a numbered picture. Pick a colour in the key ("3 · dunkelrot"), tap its regions.
//  A wrong region shakes gently and nothing else happens: no timer, no score. Pinch to zoom,
//  drag to move; numbers on tiny regions show once zoomed in. "Zeig mir" washes the regions still
//  waiting for the chosen colour.
//
//  Progress is kept on the way out and every few fills, with a preview, so a picture can be picked
//  up days later on any device. Finishing fades the outlines and files the painting in the
//  word's Bildermappe.
//
//  Tap mode works with a finger, the Pencil or a Mac pointer. Painting inside the lines with the
//  Pencil (brush mode) is the next step (docs/ZEICHNEN.md).
//

import SwiftData
import SwiftUI

struct PaintByNumberView: View {
    let artwork: WordArtwork
    let word: GameWord

    @Environment(\.modelContext) private var modelContext
    @State private var template: PaintByNumberTemplate?
    @State private var map: [UInt16] = []
    @State private var progress = PaintByNumberProgress()
    @State private var fillImage: CGImage?
    @State private var outlineImage: CGImage?
    @State private var selected = 0
    @State private var hinting = false
    @State private var zoom: CGFloat = 1
    @State private var zoomAtStart: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panAtStart: CGSize = .zero
    @State private var shake = 0
    @State private var fillsSinceSave = 0
    @State private var finished = false
    @State private var startedAt = Date()
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            if let template {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height) - 24
                    picture(template, side: side)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(magnify.simultaneously(with: drag))
                }
                Divider()
                if finished {
                    finishedBar
                } else {
                    key(template)
                }
            } else if loadFailed {
                ContentUnavailableView("Couldn't open this picture", systemImage: "exclamationmark.triangle",
                                       description: Text("Its file may still be on its way from your other device."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(white: 0.95))
        .navigationTitle(word.display)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.spring) { zoom = 1; pan = .zero }
                } label: {
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .accessibilityLabel("Fit the picture")
            }
        }
        .task { await load() }
        .onDisappear { persist(withPreview: true) }
    }

    // MARK: - The picture

    private func picture(_ template: PaintByNumberTemplate, side: CGFloat) -> some View {
        let scale = side / CGFloat(template.side)
        return ZStack {
            Color.white
            if let fillImage {
                Image(decorative: fillImage, scale: 1)
                    .resizable()
                    .interpolation(.none)
            }
            if let outlineImage {
                Image(decorative: outlineImage, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .opacity(finished ? 0 : 1)
            }
            if !finished {
                Canvas { context, _ in
                    for (facet, label) in template.labels.enumerated() where !progress.filled.contains(facet) {
                        // Numbers that would be tinier than 6 points on screen wait for a zoom.
                        let size = min(label.room * 1.3, 16) * scale
                        guard size * zoom >= 6 else { continue }
                        let number = template.palette[template.facetSwatch[facet]].number
                        let isSelected = template.facetSwatch[facet] == selected
                        context.draw(
                            Text("\(number)")
                                .font(.system(size: size, weight: isSelected ? .bold : .regular, design: .rounded))
                                .foregroundStyle(isSelected ? Color.black : Color.gray),
                            at: CGPoint(x: label.x * scale, y: label.y * scale)
                        )
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        .gesture(SpatialTapGesture().onEnded { value in
            tap(at: value.location, scale: scale, template: template)
        })
        .modifier(PaintShakeEffect(shakes: CGFloat(shake)))
        .scaleEffect(zoom)
        .offset(pan)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = min(max(zoomAtStart * value.magnification, 1), 8) }
            .onEnded { _ in zoomAtStart = zoom }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard zoom > 1 else { return }
                pan = CGSize(width: panAtStart.width + value.translation.width,
                             height: panAtStart.height + value.translation.height)
            }
            .onEnded { _ in panAtStart = pan }
    }

    // MARK: - The key

    private func key(_ template: PaintByNumberTemplate) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(template.palette.enumerated()), id: \.offset) { index, swatch in
                        swatchButton(index: index, swatch: swatch, template: template)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            HStack {
                let swatch = template.palette[min(selected, template.palette.count - 1)]
                Text("\(swatch.number) · \(swatch.name)")
                    .font(.title3.weight(.semibold))
                Spacer()
                Toggle(isOn: $hinting) {
                    Label("Zeig mir", systemImage: "eye")
                }
                .toggleStyle(.button)
                .onChange(of: hinting) { redraw() }
                Text("\(progress.filled.count) / \(template.facetCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    private func swatchButton(index: Int, swatch: PaintByNumberTemplate.Swatch, template: PaintByNumberTemplate) -> some View {
        let facets = template.facetSwatch.indices.filter { template.facetSwatch[$0] == index }
        let done = facets.filter { progress.filled.contains($0) }.count
        let complete = done == facets.count
        return Button {
            selected = index
            redraw()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: swatch.red, green: swatch.green, blue: swatch.blue))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(.black.opacity(0.15)))
                Circle()
                    .trim(from: 0, to: facets.isEmpty ? 1 : CGFloat(done) / CGFloat(facets.count))
                    .stroke(ZeichnenTile.tint, lineWidth: 3)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 52, height: 52)
                if complete {
                    Image(systemName: "checkmark").font(.headline.weight(.bold))
                        .foregroundStyle(contrast(swatch))
                } else {
                    Text("\(swatch.number)").font(.headline.weight(.bold)).foregroundStyle(contrast(swatch))
                }
            }
            .padding(2)
            .background(Circle().fill(selected == index ? Color.primary.opacity(0.12) : .clear).frame(width: 60, height: 60))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(swatch.number), \(swatch.name)\(complete ? ", fertig" : "")")
        .contextMenu {
            Button { SpeechService.shared.speak(swatch.name) } label: { Label("Anhören", systemImage: "speaker.wave.2") }
        }
    }

    private func contrast(_ swatch: PaintByNumberTemplate.Swatch) -> Color {
        let lab = ColorLab.lab(red: swatch.red, green: swatch.green, blue: swatch.blue)
        return lab.l > 60 ? .black : .white
    }

    private var finishedBar: some View {
        VStack(spacing: 6) {
            Text.gendered(word.german, article: word.article)
                .font(.title.weight(.bold))
            Text(word.english).foregroundStyle(.secondary)
            Label("In der Bildermappe", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.bar)
    }

    // MARK: - Actions

    private func load() async {
        guard template == nil else { return }
        guard let loaded = PaintByNumberLibrary.template(for: artwork) else { loadFailed = true; return }
        let decoded = await Task.detached(priority: .userInitiated) { () -> ([UInt16], CGImage?) in
            let map = loaded.facetMap()
            return (map, PaintByNumberRenderer.outlines(loaded, map: map))
        }.value
        map = decoded.0
        outlineImage = decoded.1
        progress = PaintByNumberLibrary.progress(for: artwork)
        template = loaded
        finished = !artwork.inProgress
        selected = firstUnfinishedColor(loaded) ?? 0
        startedAt = Date()
        redraw()
    }

    private func tap(at location: CGPoint, scale: CGFloat, template: PaintByNumberTemplate) {
        guard !finished, !map.isEmpty else { return }
        let x = Int(location.x / scale), y = Int(location.y / scale)
        guard x >= 0, y >= 0, x < template.side, y < template.side else { return }
        let facet = Int(map[y * template.side + x])
        guard !progress.filled.contains(facet) else { return }
        guard template.facetSwatch[facet] == selected else {
            withAnimation(.default) { shake += 1 }
            return
        }
        progress.filled.insert(facet)
        progress.updatedAt = Date()
        fillsSinceSave += 1
        redraw()
        if progress.filled.count == template.facetCount {
            complete()
        } else {
            if facetsLeft(for: selected, in: template) == 0, let next = firstUnfinishedColor(template) {
                selected = next
                redraw()
            }
            if fillsSinceSave >= 10 { persist(withPreview: true) }
        }
    }

    private func facetsLeft(for color: Int, in template: PaintByNumberTemplate) -> Int {
        template.facetSwatch.indices.filter { template.facetSwatch[$0] == color && !progress.filled.contains($0) }.count
    }

    private func firstUnfinishedColor(_ template: PaintByNumberTemplate) -> Int? {
        template.palette.indices.first { facetsLeft(for: $0, in: template) > 0 }
    }

    private func redraw() {
        guard let template else { return }
        let hint: Set<Int> = hinting
            ? Set(template.facetSwatch.indices.filter { template.facetSwatch[$0] == selected && !progress.filled.contains($0) })
            : []
        fillImage = PaintByNumberRenderer.fill(template, map: map, filled: progress.filled, hint: hint)
    }

    private func persist(withPreview: Bool) {
        guard template != nil, artwork.inProgress || fillsSinceSave > 0 else { return }
        fillsSinceSave = 0
        PaintByNumberLibrary.save(progress, preview: withPreview ? previewImage() : nil, for: artwork, in: modelContext)
    }

    private func previewImage() -> CGImage? {
        guard let template else { return nil }
        return PaintByNumberRenderer.fill(template, map: map, filled: progress.filled)
    }

    private func complete() {
        withAnimation(.easeInOut(duration: 1.2)) { finished = true }
        artwork.inProgress = false
        persist(withPreview: true)
        WordDrawingLog.recordPainted(germanWord: word.display, english: word.english, in: modelContext)
        let seconds = Int(Date().timeIntervalSince(startedAt))
        StudyLogService.record(.drawing(1), seconds: seconds, in: modelContext)
    }
}

/// A short side-to-side wobble: the gentle "not this colour".
private struct PaintShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(shakes * .pi * 4), y: 0))
    }
}
