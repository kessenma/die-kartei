//
//  WriteItSheet.swift
//  german-ai-flashcards
//
//  Schreib es · Write it: after a missed card, the word to write out by hand with the Apple Pencil,
//  once looking at it and once with it covered. The Schreibblatt's drill in miniature, at the
//  moment the word slipped.
//
//  iPad only, and optional: `CardStudyPrefs.writeAfterMissKey` (on by default) is switched in the
//  deck's start screen, the player's text menu and Settings ▸ Flashcards, and none of the three
//  shows it on an iPhone or a Mac (`CardStudyPrefs.writeAfterMissAvailable`).
//
//  Copying practice, like the Schreibblatt: nothing reads the handwriting, nothing is graded and
//  nothing is kept. The ink goes when the sheet closes. The card's rating is already made when it
//  opens, so closing it never changes the session.
//
//  The page is the shared `PencilPad`: a small sheet of exercise-book paper fitted to the width,
//  so its lines come out about 40 points apart on screen, room for a full-size hand.
//

import SwiftUI

/// The word a missed card asks to be written: the German as the card shows it, article included.
struct WriteItWord: Identifiable, Equatable {
    let id = UUID()
    let german: String
    let english: String
}

extension View {
    /// Presents the write-it sheet while `word` is set.
    func writeItSheet(_ word: Binding<WriteItWord?>, accent: Color) -> some View {
        sheet(item: word) { WriteItSheet(word: $0, accent: accent) }
    }
}

struct WriteItSheet: View {
    let word: WriteItWord
    var accent: Color = .accentColor

    @Environment(\.dismiss) private var dismiss
    /// The Schreibblatt's paper choice, so the page looks like the learner's other writing.
    @AppStorage("schreibblatt.paper") private var paper: SchreibblattPaperStyle = .white
    /// The word hidden, to write it from memory.
    @State private var covered = false

    /// About a third of a page: fitted to the sheet's width it writes large, with eleven lines.
    static let paperSize = CGSize(width: 400, height: 28 * 12)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                PencilPad(ink: nil, size: Self.paperSize, style: paper, lines: true,
                          accent: accent) { _ in }
            }
            .navigationTitle("Schreib es · Write it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(accent)
        // A downward stroke must never close the sheet; Done does.
        .interactiveDismissDisabled()
        .presentationSizing(.page)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(word.german)
                .font(.system(size: 34, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .opacity(covered ? 0 : 1)
                .overlay {
                    if covered {
                        Text("· · ·")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityLabel(covered ? "Covered" : word.german)

            Text(word.english)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 12) {
                Text(covered
                     ? "Now write it from memory, then show it to check."
                     : "Copy it once, then cover it and write it from memory.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { covered.toggle() }
                } label: {
                    Label(covered ? "Zeigen · Show" : "Verdecken · Cover",
                          systemImage: covered ? "eye" : "eye.slash")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
