//
//  KasusLessonTests.swift
//  german-ai-flashcardsTests
//
//  Verstehen · Lektion: every unit has its cards, every string renders cleanly, each worked
//  example runs the Kasus-Check in order, the English bridge and the „to“ test are there, and the
//  Merkhilfen are clean and distinct.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Kasus lessons")
struct KasusLessonTests {

    @Test("Every unit has four to six cards, all clean markup", arguments: KasusUnit.allCases)
    func cards(_ unit: KasusUnit) {
        let cards = KasusLesson.cards(for: unit)
        #expect((4...6).contains(cards.count), Comment(rawValue: "\(unit): \(cards.count)"))
        #expect(Set(cards.map(\.title)).count == cards.count, Comment(rawValue: "\(unit) titles"))
        #expect(cards.first?.showsColorKey == true, Comment(rawValue: "\(unit) color key"))
        for card in cards {
            #expect(!card.title.isEmpty && !card.english.isEmpty)
            #expect(!card.lines.isEmpty, Comment(rawValue: card.title))
            for text in card.lines { #expect(RichMarkup.problems(text).isEmpty, Comment(rawValue: "\(unit) „\(card.title)“: \(text)")) }
            if let example = card.example {
                #expect(RichMarkup.problems(example.de).isEmpty, Comment(rawValue: example.de))
                #expect(RichMarkup.problems(example.en).isEmpty, Comment(rawValue: example.en))
                #expect(!example.en.isEmpty, Comment(rawValue: "\(unit) „\(card.title)“ has no English twin"))
                for step in example.steps { #expect(RichMarkup.problems(step.line).isEmpty, Comment(rawValue: step.line)) }
                let steps = example.steps.map(\.checkStep)
                #expect(steps == steps.sorted(), Comment(rawValue: "\(unit) „\(card.title)“ steps out of Check order"))
                #expect(steps.allSatisfy { (1...6).contains($0) })
            }
        }
        #expect(cards.last?.mnemonic != nil, Comment(rawValue: "\(unit): the last card carries a memory aid"))
    }

    @Test("The English bridge and the „to“ test are in the lessons")
    func bridges() {
        let nominativ = KasusLesson.cards(for: .nominativ).flatMap(\.lines).joined(separator: " ")
        #expect(nominativ.contains("**he**") || nominativ.contains("**He**"))
        #expect(nominativ.contains("**him**"))
        let dativ = KasusLesson.cards(for: .dativ).flatMap(\.lines).joined(separator: " ")
        #expect(dativ.contains("**to**"))
        #expect(dativ.contains("gefallen"))
        let genitiv = KasusLesson.cards(for: .genitiv).flatMap(\.lines).joined(separator: " ")
        #expect(genitiv.contains("**'s**") || genitiv.contains("'s"))
        #expect(KasusLesson.practiceLabel.contains("Rollen"))
    }

    @Test("Every lesson scene is shipped, with its still, and sits under the sentence it acts out")
    func scenes() {
        var used = Set<String>()
        for unit in KasusUnit.allCases {
            for card in KasusLesson.cards(for: unit) {
                guard let example = card.example, let scene = example.scene else { continue }
                used.insert(scene.asset)
                #expect(PrepositionScene.exists(for: scene.asset), Comment(rawValue: scene.asset))
                #expect(PrepositionScene.image(for: scene.asset, state: "dat") != nil, Comment(rawValue: scene.asset))
                #expect(PrepositionScene.pose(for: scene.asset)?.animates == true, Comment(rawValue: scene.asset))
                // The picture and the sentence agree on who's in it.
                let plain = KasusRich.plain(example.de)
                switch scene {
                case .geben:  #expect(plain.contains("Mann") && plain.contains("Kind") && plain.contains("Ball"), Comment(rawValue: plain))
                case .helfen: #expect(plain.contains("Nachbarin") && plain.contains("Kind"), Comment(rawValue: plain))
                case .jagenHund, .jagenKatze:
                    #expect(plain.contains("Hund") && plain.contains("Katze") && plain.contains("jagt"), Comment(rawValue: plain))
                case .leine:  #expect(plain.contains("Hund") && plain.contains("des Kindes"), Comment(rawValue: plain))
                default:      Issue.record("unknown scene \(scene.asset)")
                }
            }
        }
        // jagen-hund is the Wer picture pair's other half; every other scene sits on a card.
        #expect(used == Set(KasusLessonScene.all.map(\.asset)).subtracting([KasusLessonScene.jagenHund.asset]))
        for scene in KasusLessonScene.all {
            #expect(PrepositionScene.image(for: scene.asset, state: "neutral") != nil, Comment(rawValue: scene.asset))
        }
        #expect(KasusMnemonics.modelSentence.scene == .geben)
    }

    @Test("The memory aids are distinct, clean, and each unit gets one or two")
    func mnemonics() {
        let all = KasusMnemonics.all
        #expect(all.count == 12)
        #expect(Set(all.map(\.id)).count == all.count)
        for aid in all {
            #expect(RichMarkup.problems(aid.title).isEmpty, Comment(rawValue: aid.title))
            #expect(RichMarkup.problems(aid.line).isEmpty, Comment(rawValue: aid.line))
            #expect(RichMarkup.problems(aid.why).isEmpty, Comment(rawValue: aid.why))
        }
        for unit in KasusUnit.allCases {
            let aids = KasusMnemonics.forUnit(unit)
            #expect((1...2).contains(aids.count), Comment(rawValue: "\(unit)"))
            #expect(aids.allSatisfy { aid in all.contains { $0.id == aid.id } })
        }
        #expect(KasusMnemonics.toTest.cases == [.dativ])
        #expect(KasusMnemonics.roleHooks.cases.isEmpty)
    }
}
