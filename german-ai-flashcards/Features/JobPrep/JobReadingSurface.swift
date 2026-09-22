//
//  JobReadingSurface.swift
//  german-ai-flashcards
//
//  The contract every way of reading a job posting implements. Three surfaces exist so they can be
//  compared on a real device — the extracted text, the saved PDF, and the live page — and the
//  ones that don't earn their keep can be deleted by removing a file and a case here. The detail
//  screen builds one set of callbacks and one set of decorations and hands the same values to
//  whichever surface is showing, so a word tapped on any of them lands in the same inspector,
//  the same lookup list, and the same deck.
//

import Foundation
import SwiftUI

/// What a surface reports back. Words and phrases both go through the inspector; a phrase the
/// learner wants to keep as a phrase (not a card) goes to the phrase library.
struct JobReadingCallbacks {
    var onTapWord: (String) -> Void
    var onTranslateSelection: (String) -> Void
    var onSavePhrase: (String) -> Void
}

/// What a surface marks in the text: words already saved to the posting's deck (an accent wash)
/// and words the learner looked up here (a red dashed underline). Both lowercased.
struct JobReadingDecorations: Equatable {
    var savedWords: Set<String> = []
    var lookedUpWords: Set<String> = []
    /// Words a vocabulary list explains (a dotted underline; a tap answers from the list). The
    /// class handouts use this with the course's vocab deck; postings leave it empty.
    var glossary: GlossaryHighlight = .none
    /// Print the glossary's English inline after each glossed word.
    var inlineGlosses: InlineGlossMode = .off

    static let none = JobReadingDecorations()
}

enum JobReadingSurfaceKind: String, CaseIterable, Identifiable {
    case text = "Text"
    case pdf = "PDF"
    case web = "Seite"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .pdf:  "doc.richtext"
        case .web:  "safari"
        }
    }

    /// One line for the help sheet and the comparison notes.
    var blurb: String {
        switch self {
        case .text: "The posting as plain text. Every gesture and marking works; nothing to load."
        case .pdf:  "The saved copy of the page, as it looked. Works offline; markings are approximate."
        case .web:  "The live page. Needs the network and shares memory with the tutor."
        }
    }
}
