import QuickLook
import SwiftUI

/// The document a deck was made from, on the deck's own screen. A document deck already keeps its
/// original beside its text (`SavedDeck.sourceFile`, written by `DocumentDeckService.save`) so the
/// sheet can join a course as a handout later; until now nothing let the learner simply look at it
/// again, which is what you want halfway through a session when a card reads oddly.
///
/// Quick Look rather than a `PDFView`: it is the one opener in the app that already works on both
/// platforms, and it shows a photo-sourced deck's `.jpg` without a second code path.
struct DeckSourceDocumentRow: View {
    let deck: SavedDeck

    @Environment(\.appTheme) private var appTheme
    @State private var previewURL: URL?

    private var kind: ClassMaterial.SourceKind { .forFile(deck.sourceFile) }

    var body: some View {
        if let url = deck.sourceFileURL {
            VStack(spacing: 8) {
                Button {
                    previewURL = url
                } label: {
                    Label("Open the original", systemImage: kind == .photo ? "photo" : "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                ShareLink(item: url) {
                    Label("Share the \(kind == .photo ? "photo" : "PDF")", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .quickLookPreview($previewURL)
        }
    }
}
