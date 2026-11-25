//
//  HandoutGlossary.swift
//  german-ai-flashcards
//
//  A class handout read with its vocabulary sheet: the deck's cards become the glossary the
//  story reader already knows how to mark up (`StoryGlossaryHighlighter`: the word, its lemma,
//  its inflections), so every occurrence in the text is underlined and a tap answers with the
//  teacher's English and no model. A sheet entry that lists forms ("anzünden/ zündete…an/ hat
//  angezündet") is split into them first, which is what takes the match rate on a real story from
//  two thirds of the entries to nearly all of them.
//

import Foundation

enum HandoutGlossary {
    /// The deck's cards as glossary entries, one per listed form, each carrying the card's English.
    static func entries(from deck: SavedDeck) -> [GlossaryEntry] {
        var out: [GlossaryEntry] = []
        var seen = Set<String>()
        for card in deck.cards.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let german = [card.article, card.germanWord].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            for form in VocabForms.split(german) {
                let key = form.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(GlossaryEntry(german: form, english: card.englishTranslation))
            }
        }
        return out
    }

    /// The markup for a text, and how many of the deck's cards were found in it.
    static func highlight(deck: SavedDeck, in text: String) -> (highlight: GlossaryHighlight, found: Int, total: Int) {
        let highlight = StoryGlossaryHighlighter.highlight(for: entries(from: deck), in: text)
        let hitForms = Set(highlight.words.values.map { $0.german.lowercased() })
            .union(highlight.phrases.map { $0.lowercased() })
        var found = 0
        for card in deck.cards {
            let german = [card.article, card.germanWord].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            if VocabForms.split(german).contains(where: { hitForms.contains($0.lowercased()) }) { found += 1 }
        }
        return (highlight, found, deck.cards.count)
    }
}
