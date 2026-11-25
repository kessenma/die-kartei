//
//  AtelierView.swift
//  german-ai-flashcards
//
//  Atelier · Studio: one word, drawn slowly from a reference picture. The reference can sit under
//  the ink as a tracing layer (its opacity live) or be hidden; the brush bar has PencilKit's inks
//  including watercolour and crayon, any colour, opacity and width. Saving renders the piece (with
//  an optional halftone finish) to the word's Bildermappe and keeps the ink, so it can be reopened.
//
//  Leaving with unsaved strokes saves them too: an hour's drawing must not vanish on a Back tap.
//

import SwiftData
import SwiftUI

struct AtelierView: View {
    let word: GameWord
    /// The picture to draw from.
    var reference: WordArtwork?
    /// A studio piece being reopened.
    var existing: WordArtwork? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var board = PencilBoard()
    @State private var handle = ZeichnenCanvasHandle()
    @State private var brush = PencilStudioBrush()
    @State private var dark = false
    @State private var showReference = true
    @State private var referenceOpacity = 0.35
    @State private var referenceImage: UIImage?
    @State private var startInk: Data?
    @State private var inkLoaded = false
    @State private var finish: ZeichnenHalftone = .none
    @State private var savedID: UUID?
    @State private var draft = AtelierDraft()
    @State private var showingSave = false
    @State private var savedMessage: String?
    @State private var pickingReference = false
    @State private var chosenReference: WordArtwork?

    private var activeReference: WordArtwork? { chosenReference ?? reference }

    var body: some View {
        VStack(spacing: 0) {
            brushBar
            Divider()
            if inkLoaded {
                ZeichnenCanvas(ink: startInk, dark: dark,
                               reference: showReference ? referenceImage : nil,
                               referenceOpacity: referenceOpacity,
                               board: board, handle: handle,
                               onSave: { [draft] data in draft.inkChanged(data) })
                    .pencilRail(board, accent: ZeichnenTile.tint, canvasSettings: { canvasSettings })
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(word.display)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSave = true
                } label: {
                    Label("Sichern", systemImage: "square.and.arrow.down")
                }
            }
        }
        .onAppear(perform: loadInk)
        .task(id: activeReference?.id) { await loadReference() }
        .onChange(of: brush, initial: true) { board.studioBrush = brush }
        .onDisappear(perform: saveIfLeftUnsaved)
        .sheet(isPresented: $showingSave) { saveSheet }
        .sheet(isPresented: $pickingReference) { referencePicker }
        .overlay(alignment: .bottom) {
            if let savedMessage {
                Label(savedMessage, systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Brush bar

    private var brushBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                Menu {
                    ForEach(PencilStudioBrush.Ink.allCases) { ink in
                        Button {
                            brush.ink = ink
                            brush.width = ink.startWidth
                        } label: {
                            Label("\(ink.title) · \(ink.english)", systemImage: ink.systemImage)
                        }
                    }
                } label: {
                    Label(brush.ink.title, systemImage: brush.ink.systemImage)
                        .font(.subheadline.weight(.medium))
                }

                HStack(spacing: 6) {
                    ForEach(PencilStudioPalette.swatches) { swatch in
                        Button {
                            brush.red = swatch.red; brush.green = swatch.green; brush.blue = swatch.blue
                        } label: {
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
                                .overlay(Circle().strokeBorder(ZeichnenTile.tint, lineWidth: isCurrent(swatch) ? 3 : 0).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.id)
                    }
                    #if canImport(UIKit)
                    ColorPicker("Farbe", selection: Binding(get: { brush.color }, set: { brush.setColor($0) }),
                                supportsOpacity: false)
                        .labelsHidden()
                    #endif
                }

                sliderBlock(title: "Deckkraft", value: $brush.opacity, range: PencilStudioBrush.opacityRange,
                            label: "\(Int(brush.opacity * 100)) %")
                sliderBlock(title: "Breite", value: $brush.width, range: brush.ink.widthRange,
                            label: "\(Int(brush.width)) pt")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func sliderBlock(title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
        .frame(width: 150)
    }

    private func isCurrent(_ swatch: PencilStudioPalette.Swatch) -> Bool {
        abs(swatch.red - brush.red) < 0.01 && abs(swatch.green - brush.green) < 0.01 && abs(swatch.blue - brush.blue) < 0.01
    }

    // MARK: - Canvas settings (the rail's gear)

    @ViewBuilder
    private var canvasSettings: some View {
        Toggle("Schwarzes Blatt · Black paper", isOn: $dark)
        Toggle("Vorlage zeigen · Show reference", isOn: $showReference)
            .disabled(referenceImage == nil)
        if showReference, referenceImage != nil {
            VStack(alignment: .leading) {
                Text("Vorlage · Reference \(Int(referenceOpacity * 100)) %").font(.caption)
                Slider(value: $referenceOpacity, in: 0.05...1)
            }
        }
        Button("Andere Vorlage · Other reference…") { pickingReference = true }
    }

    // MARK: - Save

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Finish", selection: $finish) {
                        ForEach(ZeichnenHalftone.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Finish").themedSectionHeader()
                } footer: {
                    Text("A halftone finish is applied to the saved picture. Your strokes stay as drawn, so you can reopen the piece and try another.")
                }
            }
            .navigationTitle("Sichern")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showingSave = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        showingSave = false
                        save(announce: true)
                    }
                    .disabled(handle.isBlank && draft.ink == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var referencePicker: some View {
        NavigationStack {
            let options = WordArtLibrary.artworks(forKey: WordArtKey.make(word.german), in: modelContext)
                .filter { !$0.inProgress && $0.id != existing?.id }
            ScrollView {
                if options.isEmpty {
                    ContentUnavailableView("Keine Bilder", systemImage: "photo",
                                           description: Text("Have a picture drawn in the Bildermappe first."))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(options) { artwork in
                        Button {
                            chosenReference = artwork
                            showReference = true
                            pickingReference = false
                        } label: {
                            WordArtThumbnail(fileName: artwork.fileName, key: artwork.wordKey)
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Vorlage")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { pickingReference = false } } }
        }
    }

    // MARK: - Actions

    private func loadInk() {
        guard !inkLoaded else { return }
        if let existing, let inkName = existing.inkFileName {
            startInk = WordArtStore.readData(fileName: inkName, key: existing.wordKey)
            savedID = existing.id
        }
        inkLoaded = true
    }

    private func loadReference() async {
        guard let artwork = activeReference else { referenceImage = nil; return }
        let name = artwork.fileName, key = artwork.wordKey
        referenceImage = await Task.detached(priority: .userInitiated) {
            WordArtStore.loadImage(fileName: name, key: key, maxPixelSize: 1024)
        }.value
    }

    /// The canvas hands over its last ink as it is torn down, which can be after this view's
    /// `onDisappear`: so wait a turn of the run loop, then save from the draft.
    private func saveIfLeftUnsaved() {
        let draft = draft
        DispatchQueue.main.async {
            guard draft.dirty, let ink = draft.ink else { return }
            save(ink: ink, announce: false)
        }
    }

    private func save(announce: Bool) {
        guard let ink = handle.inkData ?? draft.ink else { return }
        save(ink: ink, announce: announce)
    }

    private func save(ink: Data, announce: Bool) {
        guard let base = ZeichnenRender.image(ink: ink, dark: dark, pixels: WordArtStore.artMaxPixel) else { return }
        let picture = finish.apply(to: base)
        let key = WordArtKey.make(word.german)
        let firstSave = savedID == nil

        // A piece saved before (in this visit or reopened) is updated in place: new picture name
        // so views reload, same ink file.
        if let savedID, let artwork = fetch(savedID) {
            let fileName = WordArtStore.newPictureName(for: artwork.id)
            guard (try? WordArtStore.write(picture, fileName: fileName, key: key)) != nil else { return }
            let inkName = artwork.inkFileName ?? WordArtStore.inkName(for: artwork.id)
            try? WordArtStore.writeData(ink, fileName: inkName, key: key)
            let old = artwork.fileName
            artwork.fileName = fileName
            artwork.inkFileName = inkName
            try? modelContext.save()
            if old != fileName { try? FileManager.default.removeItem(at: WordArtStore.url(fileName: old, key: key)) }
        } else {
            let id = UUID()
            let fileName = WordArtStore.newPictureName(for: id)
            let inkName = WordArtStore.inkName(for: id)
            guard (try? WordArtStore.write(picture, fileName: fileName, key: key)) != nil else { return }
            try? WordArtStore.writeData(ink, fileName: inkName, key: key)
            let artwork = WordArtwork(wordKey: key, germanWord: word.display, english: word.english,
                                      kind: .studio, fileName: fileName)
            artwork.id = id
            artwork.inkFileName = inkName
            artwork.sourceArtworkID = activeReference?.id
            modelContext.insert(artwork)
            try? modelContext.save()
            savedID = id
        }
        draft.dirty = false

        if firstSave {
            WordDrawingLog.recordStudio(germanWord: word.display, english: word.english, in: modelContext)
            StudyLogService.record(.drawing(1), in: modelContext)
        }
        if announce {
            withAnimation { savedMessage = "In der Bildermappe gesichert" }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation { savedMessage = nil }
            }
        }
    }

    private func fetch(_ id: UUID) -> WordArtwork? {
        var d = FetchDescriptor<WordArtwork>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? modelContext.fetch(d))?.first
    }
}


/// The Atelier's latest ink, written by the canvas's save callback. A class, so the callback the
/// canvas captured when it was made keeps reaching it after the view has gone.
@Observable
@MainActor
final class AtelierDraft {
    private(set) var ink: Data?
    var dirty = false

    func inkChanged(_ data: Data?) {
        ink = data
        dirty = data != nil
    }
}
