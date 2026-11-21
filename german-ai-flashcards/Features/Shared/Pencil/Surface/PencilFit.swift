//
//  PencilFit.swift
//  german-ai-flashcards
//
//  How a Pencil surface fits the screen when it opens, turns or changes size. Shared by every
//  drawing screen; the Schreibblatt's name for it stays as an alias.
//

import SwiftUI

enum PencilFit: String, CaseIterable, Identifiable {
    /// The paper fills the width (`PencilPaper.fitWidth`): the biggest room to write in,
    /// scrolling down through the rest.
    case width
    /// A whole page at once (`PencilPaper.pageSize`), centred.
    case page

    var id: String { rawValue }

    var title: String {
        switch self {
        case .width: "Seitenbreite"
        case .page: "Ganze Seite"
        }
    }

    var systemImage: String {
        switch self {
        case .width: "arrow.left.and.right"
        case .page: "rectangle.portrait.arrowtriangle.2.inward"
        }
    }
}

typealias SchreibblattFit = PencilFit
