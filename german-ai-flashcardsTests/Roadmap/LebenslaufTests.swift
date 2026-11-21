//
//  LebenslaufTests.swift
//  german-ai-flashcardsTests
//
//  Roadmap phase 7 (item 18): facts from a résumé, one fact per turn, the posting-less interview,
//  and the probe's marks.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite struct LebenslaufTests {

    private let cv = """
    Kyle Beispiel
    Berufserfahrung
    2021–2024 iOS-Entwickler bei Muster GmbH, Berlin: Swift, SwiftUI, Barrierefreiheit
    - Leitung der App-Neuentwicklung mit 4 Personen
    2018–2021 Support-Ingenieur, First-Level-Support und Datenbanken
    Ausbildung
    2014–2018 B.Sc. Informatik
    Sprachen: Englisch (Muttersprache), Deutsch (B1)
    """

    @Test func heuristicFactsKeepDatedAndBulletedLines() {
        let facts = ResumePrompts.heuristicFacts(cv)
        #expect(facts.contains { $0.hasPrefix("2021–2024 iOS-Entwickler") })
        #expect(facts.contains { $0.hasPrefix("Leitung der App-Neuentwicklung") })
        #expect(!facts.contains("Berufserfahrung"))
    }

    @Test func parseFacts() {
        let raw = "<think>x</think>\n- 2021–2024 iOS-Entwickler bei Muster GmbH\n- B.Sc. Informatik 2018\n- \n- Swift"
        #expect(ResumePrompts.parseFacts(raw) == ["2021–2024 iOS-Entwickler bei Muster GmbH", "B.Sc. Informatik 2018"])
    }

    @Test func theFactThatMatchesThePoint() {
        let facts = ["2021–2024 iOS-Entwickler bei Muster GmbH: Swift, SwiftUI",
                     "Leitung der App-Neuentwicklung mit 4 Personen",
                     "Support-Ingenieur, Datenbanken"]
        #expect(ResumePrompts.bestFact(for: "Erfahrung mit Swift und SwiftUI", facts: facts) == facts[0])
        #expect(ResumePrompts.bestFact(for: "Projekte leiten und Teams führen", facts: facts) == nil
                || ResumePrompts.bestFact(for: "Projekte leiten und Teams führen", facts: facts) == facts[1])
        #expect(ResumePrompts.bestFact(for: "Kenntnisse in Datenbanken", facts: facts) == facts[2])
        #expect(ResumePrompts.bestFact(for: "Reisebereitschaft", facts: facts) == nil)
    }

    @Test func aPostinglessInterviewRunsOnTheProfile() {
        var config = ConversationConfig(model: .hero)
        config.mode = .interview
        config.resumeProfile = "Ich bin iOS-Entwickler mit drei Jahren Erfahrung in Swift."
        config.resumeFacts = ["2021–2024 iOS-Entwickler bei Muster GmbH: Swift, SwiftUI"]
        let prompt = ConversationPrompts.systemPrompt(for: config)
        #expect(prompt.contains("no specific posting"))
        #expect(prompt.contains("never invent"))
        #expect(prompt.contains(ResumePrompts.generalPlan[0]))
        let note = ConversationPrompts.interviewProgressNote(for: config, candidateTurns: 1)
        #expect(note?.contains("Werdegang") == true)
    }

    @Test func withAPostingTheFactJoinsThePlanPoint() {
        var config = ConversationConfig(model: .hero)
        config.mode = .interview
        config.jobContext = "Ihre Aufgaben\n- Entwicklung von iOS-Apps mit Swift und SwiftUI\n- Betreuung von Datenbanken"
        config.resumeProfile = "iOS-Entwickler."
        config.resumeFacts = ["2021–2024 iOS-Entwickler: Swift, SwiftUI", "Support-Ingenieur, Datenbanken"]
        let note = ConversationPrompts.interviewProgressNote(for: config, candidateTurns: 1) ?? ""
        #expect(note.contains("From their résumé"))
        #expect(ConversationPrompts.systemPrompt(for: config).contains("The candidate's profile"))
    }

    @Test func probeMarks() {
        #expect(ResumeProbe.factUsed(question: "Sie waren iOS-Entwickler bei Muster. Was haben Sie mit SwiftUI gebaut?",
                                     fact: "2021–2024 iOS-Entwickler bei Muster GmbH: Swift, SwiftUI"))
        #expect(!ResumeProbe.factUsed(question: "Erzählen Sie mir von Ihren Hobbys.", fact: "iOS-Entwickler bei Muster GmbH"))
        #expect(ResumeProbe.possibleInventions(question: "2019 waren Sie bei SAP?", known: cv) == ["2019", "SAP"])
        #expect(ResumeProbe.possibleInventions(question: "2021 bei Muster", known: cv).isEmpty)
    }
}
