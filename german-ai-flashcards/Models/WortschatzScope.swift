//
//  WortschatzScope.swift
//  german-ai-flashcards
//
//  Which levels and word types the Wortschatz box studies, and how a session over them is named.
//  Foundation only and shared with the Android app (DieKarteiCore): both apps label a Wortschatz
//  session's result with it and read the same settings keys.
//

import Foundation

/// Which levels and word classes feed reviews and new words. Progress outside the scope is kept,
/// not lost — a deselected level's cards simply wait until it is switched back on.
struct WortschatzScope: Equatable {
    var levels: Set<GoetheLevel>
    var wordTypes: Set<GoetheWordType>

    static let all = WortschatzScope(levels: Set(GoetheLevel.allCases), wordTypes: Set(GoetheWordType.allCases))

    static let levelsKey = "wortschatz.levels"
    static let wordTypesKey = "wortschatz.wordTypes"

    func contains(_ word: GoetheWord) -> Bool {
        !levels.isDisjoint(with: word.levels) && wordTypes.contains(word.wordType)
    }

    var orderedLevels: [GoetheLevel] { GoetheLevel.allCases.filter { levels.contains($0) } }
    var orderedTypes: [GoetheWordType] { GoetheWordType.allCases.filter { wordTypes.contains($0) } }

    /// The session topic: a single level keeps the per-level label the deck history and the
    /// Goethe badge have always used; a mix gets the merged deck's own name.
    var topic: String {
        orderedLevels.count == 1 ? "\(orderedLevels[0].rawValue) Vocabulary" : SyncSingletonDecks.wortschatzTopic
    }

    /// "A1 · A2 · Nomen, Verben" — the one-line recap the hero and the options row show.
    var summary: String {
        let levelPart = levels.count == GoetheLevel.allCases.count
            ? "A1–B1" : orderedLevels.map(\.rawValue).joined(separator: " · ")
        let typePart = wordTypes.count == GoetheWordType.allCases.count
            ? "all word types" : orderedTypes.map(\.label).joined(separator: ", ")
        return "\(levelPart) · \(typePart)"
    }

    // MARK: Persistence (comma-joined raw values, the `home.selectedTenses` pattern)

    var levelsRaw: String { orderedLevels.map(\.rawValue).joined(separator: ",") }
    var wordTypesRaw: String { orderedTypes.map(\.rawValue).joined(separator: ",") }

    /// Decode the two stored strings; anything empty or unreadable falls back to everything, so a
    /// fresh install and a corrupted key both study the whole box.
    static func decode(levelsRaw: String, wordTypesRaw: String) -> WortschatzScope {
        let levels = Set(levelsRaw.split(separator: ",").compactMap { GoetheLevel(rawValue: String($0)) })
        let types = Set(wordTypesRaw.split(separator: ",").compactMap { GoetheWordType(rawValue: String($0)) })
        return WortschatzScope(
            levels: levels.isEmpty ? all.levels : levels,
            wordTypes: types.isEmpty ? all.wordTypes : types
        )
    }

    static func load(_ defaults: UserDefaults = SharedDefaults.store) -> WortschatzScope {
        decode(levelsRaw: defaults.string(forKey: levelsKey) ?? "",
               wordTypesRaw: defaults.string(forKey: wordTypesKey) ?? "")
    }

    func save(to defaults: UserDefaults = SharedDefaults.store) {
        defaults.set(levelsRaw, forKey: Self.levelsKey)
        defaults.set(wordTypesRaw, forKey: Self.wordTypesKey)
    }

    /// Flip one level; the last remaining level stays on (an empty scope studies nothing).
    mutating func toggle(_ level: GoetheLevel) {
        if levels.contains(level) {
            guard levels.count > 1 else { return }
            levels.remove(level)
        } else {
            levels.insert(level)
        }
    }

    mutating func toggle(_ type: GoetheWordType) {
        if wordTypes.contains(type) {
            guard wordTypes.count > 1 else { return }
            wordTypes.remove(type)
        } else {
            wordTypes.insert(type)
        }
    }
}
