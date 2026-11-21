//
//  SpieleTestWords.swift
//  german-ai-flashcardsTests
//
//  Word fixtures for the Spiele tests. Everything here is a real German word, because the
//  generators are sensitive to which letters actually repeat.
//

import Foundation
@testable import Die_Kartei

enum SpieleTestWords {

    /// One word. Fails loudly rather than silently skipping a case.
    /// A deck id for picture fixtures. Fixed, so a test can assert on it.
    static let deckID = UUID(uuidString: "5EEDDECC-0000-0000-0000-00000000CAFE")!

    static func word(_ german: String, _ english: String = "thing", article: String? = nil,
                     forms: String? = nil, wordType: String? = nil,
                     image: String? = nil, imageDeckID: UUID? = nil) -> GameWord {
        guard let word = GameWord(german: german, english: english, article: article,
                                  forms: forms, wordType: wordType, imageFileName: image,
                                  imageDeckID: imageDeckID ?? (image == nil ? nil : deckID))
        else { preconditionFailure("\(german) is not a usable GameWord") }
        return word
    }

    static func words(_ germans: [String]) -> [GameWord] { germans.map { word($0) } }

    /// Ten A1 nouns that share plenty of letters — the happy case for both grid games.
    static let küche = words(["Teller", "Gabel", "Messer", "Tasse", "Löffel",
                              "Topf", "Pfanne", "Herd", "Salz", "Brot"])

    /// Deliberately letter-poor: these two share nothing, so nothing can interlock.
    static let strangers = words(["Hund", "Katze"])

    /// Carries an umlaut exactly once, which is the camouflage case.
    static let umlaut = words(["Mädchen", "Blume", "Stein", "Wasser", "Brot", "Tisch"])
}
