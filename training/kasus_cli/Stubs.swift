//
//  Stubs.swift
//  kasus-cli
//
//  Stand-ins for the few app types the compiled sources name but the check never runs. None of
//  them is on the planner's, the prompt's or the check's path.
//

import SwiftUI

// The app's MLX-backed classes. kasus-cli compiles only their pure extensions
// (StoryStudyService+Prompt.swift, KasusStoryPrompt.swift's completeSentences).
@MainActor final class StoryStudyService {}
@MainActor final class KasusStoryGenerator {}

// PrepositionService.swift records rounds into SwiftData; the lookups the lexicon reads are in
// PrepositionService+Content.swift.
enum PrepositionService {}

// ConversationConfig.swift, home of CEFRLevel, names the tutor model in a chat config.
enum MLXModel: String, Codable, Hashable { case stub }

// GrammarPalette.swift's colors. Display only.
extension Color { nonisolated init(light: UInt, dark: UInt) { self.init(white: 0) } }

// KasusVerbPairs reads the 42 verb pairs through VerbPrepositionService.all(), whose file also
// builds rounds and decks. The same JSON through the same decoder type (VerbPrepositionsFile);
// `selftest` checks the count.
enum VerbPrepositionService {
    private static let file: VerbPrepositionsFile = {
        guard let url = Bundle.main.url(forResource: "verb_prepositions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(VerbPrepositionsFile.self, from: data)
        else { return VerbPrepositionsFile(verbs: [], falle: []) }
        return decoded
    }()

    static func all() -> [VerbPreposition] { file.verbs }
}
