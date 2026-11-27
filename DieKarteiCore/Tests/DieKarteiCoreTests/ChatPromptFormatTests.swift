import Foundation
import Testing
@testable import DieKarteiCore

/// The Android prompt format must equal what each tutor's own chat template renders, which is
/// what the evals scored. Fixtures: training/scripts/render_chat_fixtures.py.
struct ChatPromptFormatTests {
    struct Fixture: Decodable {
        struct Message: Decodable { let role: String; let content: String }
        let family: String
        let `case`: String
        let messages: [Message]
        let prompt: String
    }

    static let fixtures: [Fixture] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("chat_template_fixtures.json")
        return (try? JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))) ?? []
    }()

    @Test func everyFamilyHasFixtures() {
        for format in ChatPromptFormat.allCases {
            #expect(Self.fixtures.contains { $0.family == format.rawValue }, "no fixtures for \(format)")
        }
    }

    @Test(arguments: fixtures.indices)
    func rendersLikeTheModelsTemplate(_ index: Int) throws {
        let fixture = Self.fixtures[index]
        let format = try #require(ChatPromptFormat(rawValue: fixture.family))
        let messages = fixture.messages.map { (role: ChatRole(rawValue: $0.role)!, content: $0.content) }
        #expect(format.render(messages) == fixture.prompt, "\(fixture.family)/\(fixture.case)")
    }

    @Test func modelsMapToTheirFamilies() {
        #expect(ChatPromptFormat(.gemma4_E4B_german) == .gemma4)
        #expect(ChatPromptFormat(.gemma4_E2B_german) == .gemma4)
        #expect(ChatPromptFormat(.granite41_3B_german) == .granite)
        #expect(ChatPromptFormat(.granite2B_german) == .granite)
    }

    /// What every chat prompt passes through first: Gemma's template rejects anything but strict
    /// user/assistant alternation starting on the user.
    @Test func normalizerGivesTheShapeTemplatesAccept() {
        let turns: [ChatTurnNormalizer.Turn] = [
            (role: .assistant, content: "Hallo!"),
            (role: .user, content: "Hi"),
            (role: .user, content: "Wie geht's?"),
            (role: .assistant, content: "Gut."),
        ]
        let normalized = ChatTurnNormalizer.normalized(turns, openerSeed: "Fang an.")
        #expect(normalized.map(\.role) == [.user, .assistant, .user, .assistant, .user])
        #expect(normalized[2].content == "Hi\n\nWie geht's?")
    }
}
