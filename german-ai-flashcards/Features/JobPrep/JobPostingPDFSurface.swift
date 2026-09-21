//
//  JobPostingPDFSurface.swift
//  german-ai-flashcards
//
//  The saved copy of the page as a reading surface: the ad as it looked, offline, with a double
//  tap on a word going to the same inspector the text surface uses and the same markings drawn
//  over the words as in-memory highlight annotations (never written back to the file).
//
//  Known limits of a WebKit-rendered snapshot: it's one tall page whose text layer includes the
//  site's navigation and cookie text, and a word hyphenated across a line end comes back as its
//  first half. The text surface is the exact one; this is the faithful-looking one.
//

import PDFKit
import SwiftUI

#if canImport(UIKit)

struct JobPostingPDFSurface: View {
    let url: URL
    let decorations: JobReadingDecorations
    let callbacks: JobReadingCallbacks
    let accent: Color

    /// The current page selection, for the strip below — the fallback for the edit-menu items.
    @State private var selection = ""

    var body: some View {
        VStack(spacing: 0) {
            PDFSurfaceRepresentable(
                url: url,
                decorations: decorations,
                callbacks: callbacks,
                accent: UIColor(accent),
                onSelectionChange: { selection = $0 }
            )
            if !selection.isEmpty {
                selectionStrip
            }
        }
    }

    private var selectionStrip: some View {
        HStack(spacing: 10) {
            Text(selection)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button {
                callbacks.onTranslateSelection(selection)
            } label: {
                Label("Translate", systemImage: "character.book.closed")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.small)
            Button {
                callbacks.onSavePhrase(selection)
            } label: {
                Label("Save phrase", systemImage: "plus.bubble")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Representable

private struct PDFSurfaceRepresentable: UIViewRepresentable {
    let url: URL
    let decorations: JobReadingDecorations
    let callbacks: JobReadingCallbacks
    let accent: UIColor
    let onSelectionChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> JobReadingPDFView {
        let view = JobReadingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(url: url)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)
        view.wordTap = doubleTap

        context.coordinator.pdfView = view
        context.coordinator.selectionObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewSelectionChanged, object: view, queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated { coordinator?.selectionChanged() }
        }
        sync(view, context: context)
        view.applyDecorations(decorations, accent: accent)
        return view
    }

    func updateUIView(_ view: JobReadingPDFView, context: Context) {
        sync(view, context: context)
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            view.appliedDecorations = nil
        }
        if view.appliedDecorations != decorations {
            view.applyDecorations(decorations, accent: accent)
        }
    }

    private func sync(_ view: JobReadingPDFView, context: Context) {
        context.coordinator.onTapWord = callbacks.onTapWord
        context.coordinator.onSelectionChange = onSelectionChange
        view.onTranslate = callbacks.onTranslateSelection
        view.onSavePhrase = callbacks.onSavePhrase
    }

    static func dismantleUIView(_ view: JobReadingPDFView, coordinator: Coordinator) {
        if let observer = coordinator.selectionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var pdfView: JobReadingPDFView?
        var onTapWord: ((String) -> Void)?
        var onSelectionChange: ((String) -> Void)?
        var selectionObserver: NSObjectProtocol?

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let pdfView, let word = pdfView.word(at: recognizer.location(in: pdfView)) else { return }
            pdfView.clearSelection()
            onTapWord?(word)
        }

        func selectionChanged() {
            let text = pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            onSelectionChange?(text)
        }

        /// Only claim the double tap when it lands on a word; taps on whitespace fall through to
        /// PDFKit's own zoom.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pdfView else { return false }
            return pdfView.word(at: gestureRecognizer.location(in: pdfView)) != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - PDF view

/// `PDFView` plus the reader's edit-menu items, word lookup at a point, decoration annotations,
/// and the deferral of PDFKit's own double-tap zoom to the word tap.
final class JobReadingPDFView: PDFView {
    var onTranslate: ((String) -> Void)?
    var onSavePhrase: ((String) -> Void)?
    /// The reader's double tap; PDFKit's zoom recognizers are told to wait for it to fail.
    weak var wordTap: UITapGestureRecognizer?
    var appliedDecorations: JobReadingDecorations?

    private var annotations: [(PDFPage, PDFAnnotation)] = []
    private var deferredZoomRecognizers = Set<ObjectIdentifier>()

    override func layoutSubviews() {
        super.layoutSubviews()
        deferBuiltInDoubleTap()
    }

    // MARK: Words

    /// The word under `point` (in this view's coordinates), or nil off the text.
    func word(at point: CGPoint) -> String? {
        guard let page = page(for: point, nearest: false) else { return nil }
        let pagePoint = convert(point, to: page)
        guard let selection = page.selectionForWord(at: pagePoint) else { return nil }
        let word = SingleWordTranslator.cleanWord(selection.string ?? "")
        return word.isEmpty ? nil : word
    }

    // MARK: Edit menu

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context,
              let text = currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        let translate = UIAction(title: "Translate", image: UIImage(systemName: "character.book.closed")) { [weak self] _ in
            self?.onTranslate?(text)
            self?.clearSelection()
        }
        let save = UIAction(title: "Save phrase", image: UIImage(systemName: "plus.bubble")) { [weak self] _ in
            self?.onSavePhrase?(text)
            self?.clearSelection()
        }
        builder.insertChild(UIMenu(options: .displayInline, children: [translate, save]), atStartOfMenu: .root)
    }

    // MARK: Decorations

    /// Replace the highlight annotations: an accent wash on every saved word, a red one on every
    /// looked-up word. In memory only; the file on disk is never touched.
    func applyDecorations(_ decorations: JobReadingDecorations, accent: UIColor) {
        for (page, annotation) in annotations {
            page.removeAnnotation(annotation)
        }
        annotations = []
        appliedDecorations = decorations
        guard let document else { return }
        let saved = accent.withAlphaComponent(0.28)
        let looked = UIColor.systemRed.withAlphaComponent(0.22)
        // A word in both sets is saved; the wash says so and the red would only muddy it.
        for word in decorations.lookedUpWords.subtracting(decorations.savedWords) {
            highlight(word, in: document, color: looked)
        }
        for word in decorations.savedWords {
            highlight(word, in: document, color: saved)
        }
    }

    private func highlight(_ word: String, in document: PDFDocument, color: UIColor) {
        guard word.count >= 2 else { return }
        for selection in document.findString(word, withOptions: [.caseInsensitive]) {
            guard let page = selection.pages.first else { continue }
            // `findString` matches substrings ("Arbeit" inside "Mitarbeiter"); keep whole words.
            let bounds = selection.bounds(for: page)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let whole = SingleWordTranslator.cleanWord(page.selectionForWord(at: center)?.string ?? "")
            guard whole.lowercased() == word.lowercased() else { continue }
            for line in selection.selectionsByLine() {
                guard let linePage = line.pages.first else { continue }
                let annotation = PDFAnnotation(bounds: line.bounds(for: linePage), forType: .highlight, withProperties: nil)
                annotation.color = color
                linePage.addAnnotation(annotation)
                annotations.append((linePage, annotation))
            }
        }
    }

    // MARK: Zoom deferral

    /// PDFKit's double-tap-to-zoom lives on recognizers inside its private view tree. Each one is
    /// asked to wait for the word tap to fail, so a double tap on a word looks the word up and a
    /// double tap on the margin still zooms. Idempotent, and harmless when nothing is found: both
    /// then fire, which is the pre-existing behavior.
    private func deferBuiltInDoubleTap() {
        guard let wordTap else { return }
        var stack: [UIView] = subviews
        while let view = stack.popLast() {
            for recognizer in view.gestureRecognizers ?? [] {
                guard let tap = recognizer as? UITapGestureRecognizer, tap !== wordTap,
                      tap.numberOfTapsRequired == 2 else { continue }
                let id = ObjectIdentifier(tap)
                guard !deferredZoomRecognizers.contains(id) else { continue }
                tap.require(toFail: wordTap)
                deferredZoomRecognizers.insert(id)
            }
            stack.append(contentsOf: view.subviews)
        }
    }
}

#endif
