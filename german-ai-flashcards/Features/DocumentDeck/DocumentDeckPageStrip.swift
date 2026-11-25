//
//  DocumentDeckPageStrip.swift
//  german-ai-flashcards
//
//  The deck builder's page picker. With a real PDF in hand every page is a small picture of itself,
//  so the Wortliste among 37 slides can be spotted rather than guessed at; without one (a handout
//  or a paper already in the app, a pasted list, a page fetched from a link, a photo) it falls back
//  to the plain numbered pills.
//
//  The strip shows the pages the parser *read*, not every page of the file. Every other part of the
//  picker — the typed range, All/None, which rows are in the deck — is defined over those, and a
//  page with no text has no rows to contribute, so offering it would be offering nothing. Where the
//  two counts differ the footer says so.
//

import SwiftUI

struct DocumentDeckPageStrip: View {
    let pages: [VocabListParser.Page]
    let selectedPages: Set<Int>
    /// Nil when the draft carries no PDF: then this is the old pill strip.
    let thumbnails: PDFPageThumbnails?
    let accent: Color
    var onToggle: (Int) -> Void
    var onEnlarge: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if let thumbnails {
                // Lazy, because a module of 37 pages should render the three on screen and no more.
                LazyHStack(spacing: 8) {
                    ForEach(pages) { page in
                        PageThumbCard(
                            page: page,
                            isOn: selectedPages.contains(page.number),
                            thumbnails: thumbnails,
                            accent: accent,
                            onToggle: { onToggle(page.number) },
                            onEnlarge: { onEnlarge(page.number) }
                        )
                    }
                }
                .padding(.vertical, 2)
            } else {
                HStack(spacing: 6) {
                    ForEach(pages) { page in
                        FilterPill(
                            label: "\(page.number) · \(page.rows.count)",
                            tint: accent,
                            isOn: selectedPages.contains(page.number),
                            showsClearGlyph: false
                        ) {
                            withAnimation(.snappy(duration: 0.2)) { onToggle(page.number) }
                        }
                        .opacity(page.rows.isEmpty ? 0.45 : 1)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// One page: its picture, its number, how many pairs it gave, and whether it is in. A fixed frame
/// rather than an intrinsic one, so the `LazyHStack` above knows what it is laying out.
private struct PageThumbCard: View {
    let page: VocabListParser.Page
    let isOn: Bool
    let thumbnails: PDFPageThumbnails
    let accent: Color
    var onToggle: () -> Void
    var onEnlarge: () -> Void

    @Environment(\.appTheme) private var appTheme

    private static let cardWidth: CGFloat = 76
    private static let cardHeight: CGFloat = 104

    var body: some View {
        VStack(spacing: 4) {
            Button(action: { withAnimation(.snappy(duration: 0.2)) { onToggle() } }) {
                picture
            }
            .buttonStyle(.plain)
            Text(page.rows.isEmpty ? "keine Paare" : "\(page.rows.count) Paare")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.cardWidth)
        .task(id: page.number) {
            await thumbnails.request(page: page.number, width: Self.cardWidth)
        }
    }

    private var picture: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.10))
            if let image = thumbnails.thumbnail(page: page.number) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView().controlSize(.small)
                    .frame(width: Self.cardWidth, height: Self.cardHeight)
            }
            Text("\(page.number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(4)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if isOn {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.white, accent)
                    .padding(4)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onEnlarge) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(3)
            .accessibilityLabel("See page \(page.number) full size")
        }
        .overlay {
            RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous)
                .strokeBorder(isOn ? accent : Color.secondary.opacity(0.25), lineWidth: isOn ? 2 : 1)
        }
        .accessibilityLabel(isOn ? "Page \(page.number), in the deck" : "Page \(page.number), not in the deck")
    }
}

/// One page, big, with the decision to make while looking at it.
///
/// An in-app page rather than Quick Look, which cannot be opened at page 23 and would mean writing
/// the draft's bytes to a file before the learner has committed to anything. Quick Look stays the
/// right tool where it already is: `DeckSourceDocumentRow`, the whole document, once a deck exists.
struct DocumentPagePreviewSheet: View {
    let pages: [VocabListParser.Page]
    let thumbnails: PDFPageThumbnails
    let accent: Color
    @Binding var selectedPages: Set<Int>
    let startAt: Int

    @Environment(\.dismiss) private var dismiss
    @State private var current = 0
    @State private var image: UIImage?

    private var page: VocabListParser.Page? {
        pages.indices.contains(current) ? pages[current] : nil
    }
    private var isOn: Bool { page.map { selectedPages.contains($0.number) } ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width < -30 { step(1) }
                        if value.translation.width > 30 { step(-1) }
                    }
                )

                HStack {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(current == 0)
                    Spacer()
                    if let page {
                        Button {
                            if selectedPages.contains(page.number) {
                                selectedPages.remove(page.number)
                            } else {
                                selectedPages.insert(page.number)
                            }
                        } label: {
                            Text(isOn ? "Drop this page" : "Use this page")
                                .frame(minWidth: 140)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isOn ? Color.secondary : accent)
                    }
                    Spacer()
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(current >= pages.count - 1)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle(page.map { "Seite \($0.number)" } ?? "Seite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            current = pages.firstIndex { $0.number == startAt } ?? 0
            await loadCurrent()
        }
        // The big bitmap goes when the sheet does; the strip's small ones are a separate cache.
        .onDisappear { image = nil }
    }

    private func step(_ delta: Int) {
        let next = current + delta
        guard pages.indices.contains(next) else { return }
        current = next
        image = nil
        Task { await loadCurrent() }
    }

    private func loadCurrent() async {
        guard let page else { return }
        let wanted = page.number
        let rendered = await thumbnails.fullPage(wanted)
        guard self.page?.number == wanted else { return }
        image = rendered
    }
}
