import Foundation
import Testing
@testable import DieKarteiCore

/// The shared rules behind the chat screens both apps run: a spoken turn (`SpeechTranscript`),
/// the saved-chats filter (`ConversationListFilter`) and Settings ▸ Conversation (`ChatPrefs`).
@MainActor
@Suite struct ChatSharedRulesTests {
    @Test("A spoken turn keeps each finished segment and replaces revised ones")
    func transcriptFolds() {
        var t = SpeechTranscript()
        t.ingest("Ich habe einen neue", isFinal: false)
        t.ingest("Ich habe einen neuen Hof", isFinal: false)
        t.ingest("Ich habe einen neuen Koffer", isFinal: true)
        #expect(t.text == "Ich habe einen neuen Koffer")
        t.ingest("der ist", isFinal: false)
        t.ingest("der ist rot", isFinal: false)
        #expect(t.text == "Ich habe einen neuen Koffer der ist rot")
        // A fresh segment without a final result banks the previous one.
        t.ingest("und groß", isFinal: false)
        #expect(t.text == "Ich habe einen neuen Koffer der ist rot und groß")
    }

    @Test("A mark replaces the recognizer's own and needs something said")
    func transcriptPunctuates() throws {
        #expect(SpeechTranscript().punctuated("?") == nil)
        var t = SpeechTranscript()
        t.ingest("Ich glaube.", isFinal: true)
        let next = try #require(t.punctuated(","))
        #expect(next.text == "Ich glaube,")
        var more = next
        more.ingest("dass es regnet", isFinal: true)
        #expect(more.text == "Ich glaube, dass es regnet")
    }

    struct Chat: FilterableChat {
        var mode: ConversationMode
        var jobCompany: String?
    }

    @Test("The chat filter narrows by type and employer, and offers only what's there")
    func filter() {
        let chats = [Chat(mode: .scenario, jobCompany: nil), Chat(mode: .interview, jobCompany: "Charité"),
                     Chat(mode: .interview, jobCompany: " charité "), Chat(mode: .interview, jobCompany: "Siemens"),
                     Chat(mode: .freestyle, jobCompany: nil)]
        #expect(ConversationListFilter.presentModes(chats) == ConversationMode.allCases.filter { [.scenario, .interview, .freestyle].contains($0) })
        #expect(ConversationListFilter.presentCompanies(chats) == ["Charité", "Siemens"])
        let byCompany = ConversationListFilter().toggling(company: "CHARITÉ")
        #expect(byCompany.mode == .interview)
        #expect(chats.filter { byCompany.matches($0) }.count == 2)
        let scenario = byCompany.toggling(mode: .scenario)
        #expect(scenario.company == nil)
        #expect(chats.filter { scenario.matches($0) }.count == 1)
        #expect(!scenario.toggling(mode: .scenario).isActive)
    }

    @Test("A new chat starts from Settings ▸ Conversation; a reopened one reads only this device's")
    func prefs() throws {
        let d = try #require(UserDefaults(suiteName: "chatprefs-\(UUID().uuidString)"))
        var fresh = ConversationConfig(model: MLXModel.allCases.first!)
        ChatPrefs.applyDefaults(to: &fresh, in: d)
        #expect(fresh.level == .a2 && fresh.formality == .du && fresh.inputMode == .speak && fresh.hintCount == 1)
        #expect(fresh.correctionsEnabled && fresh.autoPlay && !fresh.eagerAssist && fresh.genderColors)

        d.set("B1", forKey: ChatPrefs.levelKey)
        d.set(Formality.sie.rawValue, forKey: ChatPrefs.formalityKey)
        d.set(false, forKey: ChatPrefs.correctionsEnabledKey)
        d.set(ChatInputMode.type.rawValue, forKey: ChatPrefs.inputModeKey)
        d.set(3, forKey: ChatPrefs.hintCountKey)
        d.set("Kyle", forKey: ChatPrefs.learnerNameKey)
        var c = ConversationConfig(model: MLXModel.allCases.first!)
        ChatPrefs.applyDefaults(to: &c, in: d)
        #expect(c.level == .b1 && c.formality == .sie && !c.correctionsEnabled && c.inputMode == .type)
        #expect(c.hintCount == 3 && c.learnerName?.isEmpty == false)

        d.set(9, forKey: ChatPrefs.hintCountKey)
        var reopened = ConversationConfig(model: MLXModel.allCases.first!)
        reopened.level = .c1
        ChatPrefs.applyDeviceSettings(to: &reopened, in: d)
        #expect(reopened.hintCount == ChatPrefs.hintCountDefault, "out of range reads as the default")
        #expect(reopened.level == .c1, "a reopened chat keeps its own level")
    }
}
