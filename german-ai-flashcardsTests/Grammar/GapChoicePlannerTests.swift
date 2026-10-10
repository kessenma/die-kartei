//
//  GapChoicePlannerTests.swift
//  german-ai-flashcardsTests
//
//  The planner that writes the reflexive packs: the same seed gives the same pack, every item it
//  writes passes the gate, a pack has the composition the drill needs, the English twins read,
//  and a sentence the bundle already has is never drawn.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Gap-choice planner")
struct GapChoicePlannerTests {

    @Test("The same seed gives the same pack; another seed another order")
    func determinism() {
        let a = GapChoicePlanner.pack(focus: .case, count: 40, seed: 7)
        let b = GapChoicePlanner.pack(focus: .case, count: 40, seed: 7)
        let c = GapChoicePlanner.pack(focus: .case, count: 40, seed: 8)
        #expect(a.map(\.id) == b.map(\.id) && a.map(\.sentence) == b.map(\.sentence))
        #expect(a.map { $0.gaps[0].options } == b.map { $0.gaps[0].options })
        #expect(a.count == 40 && c.count == 40 && a.map(\.id) != c.map(\.id))
        #expect(Set(a.map(\.id)).count == 40)
    }

    @Test("Every item the planner writes passes the gate", arguments: [GapChoiceFocus.case, .person])
    @MainActor
    func gated(_ focus: GapChoiceFocus) {
        let pack = GapChoicePlanner.pack(focus: focus, count: 60, seed: 11)
        #expect(pack.count == 60)
        for item in pack {
            let result = GapChoiceCheck.run(item, lexicon: KasusTestData.lexicon)
            #expect(result.passes, Comment(rawValue: "\(item.id) „\(item.filled)“: \(result.errors.joined(separator: " | "))"))
            #expect(item.id.hasPrefix("rx-s-\(focus.rawValue)-"))
            #expect(item.english.first?.isUppercase == true && item.english.hasSuffix(".") && !item.english.contains("{"))
        }
    }

    @Test("A batch-sized pack has every verb, every person and both cases")
    func composition() {
        let casePack = GapChoicePlanner.pack(focus: .case, count: 120, seed: 7)
        let personPack = GapChoicePlanner.pack(focus: .person, count: 100, seed: 7)
        #expect(GapChoiceCheck.composition(casePack).isEmpty, Comment(rawValue: GapChoiceCheck.composition(casePack).map(\.detail).joined(separator: "; ")))
        #expect(GapChoiceCheck.composition(personPack).isEmpty, Comment(rawValue: GapChoiceCheck.composition(personPack).map(\.detail).joined(separator: "; ")))
        #expect(casePack.filter { $0.kasus == .akkusativ }.count >= 40 && casePack.filter { $0.kasus == .dativ }.count >= 40)
        #expect(casePack.allSatisfy { $0.subject.person < 3 && $0.subject.number == .sg })
        #expect(Set(personPack.map { "\($0.subject.person)\($0.subject.number.rawValue)" }).count == 6)
        #expect(casePack.filter { $0.presentation == .inline }.count == 30)
        // Akkusativ oder Dativ? shows the same four buttons; the chips are the subject's own pair.
        for item in casePack {
            if item.presentation == .buttons {
                #expect(item.gaps[0].options == ["mich", "mir", "dich", "dir"])
            } else {
                #expect(item.gaps[0].options.count == 2 && item.gaps[0].options.contains(item.gaps[0].answer))
            }
        }
        for item in personPack {
            #expect(item.gaps[0].options.count == (item.presentation == .inline ? 2 : 4))
            #expect(Set(item.gaps[0].options).count == item.gaps[0].options.count)
        }
    }

    @Test("The English twin follows the pattern by person")
    func english() {
        let waschen = ReflexivVerb.named("waschen")!
        let ich = ReflexivSubject.all[0], er = ReflexivSubject.all[2], wir = ReflexivSubject.all[4]
        #expect(GapChoicePlanner.english(waschen.en.dat!, subject: ich, verb: waschen, object: .haende, tail: nil) == "I wash my hands.")
        #expect(GapChoicePlanner.english(waschen.en.dat!, subject: er, verb: waschen, object: .gesicht, tail: nil) == "He washes his face.")
        #expect(GapChoicePlanner.english(waschen.en.akk!, subject: wir, verb: waschen, object: nil, tail: nil) == "We wash ourselves.")
        let anziehen = ReflexivVerb.named("anziehen")!
        #expect(GapChoicePlanner.english(anziehen.en.dat!, subject: er, verb: anziehen, object: .jacke, tail: nil) == "He puts on his jacket.")
        let freuen = ReflexivVerb.named("freuen")!
        #expect(GapChoicePlanner.english(freuen.en.akk!, subject: ich, verb: freuen, object: nil, tail: freuen.tails[0]) == "I look forward to the holidays.")
        let kaufen = ReflexivVerb.named("kaufen")!
        #expect(GapChoicePlanner.english(kaufen.en.dat!, subject: wir, verb: kaufen, object: .auto, tail: nil) == "We buy ourselves a car.")
        let interessieren = ReflexivVerb.named("interessieren")!
        #expect(GapChoicePlanner.english(interessieren.en.akk!, subject: ich, verb: interessieren, object: nil, tail: interessieren.tails[0]) == "I am interested in music.")
        #expect(GapChoicePlanner.english(interessieren.en.akk!, subject: er, verb: interessieren, object: nil, tail: nil) == "He is interested.")
    }

    @Test("A sentence the bundle has is never drawn, and the separable prefix stands last")
    func excluding() {
        let bundled: Set<String> = ["ich wasche mir die hände."]
        let pack = GapChoicePlanner.pack(focus: .case, count: 200, seed: 3, excluding: bundled)
        #expect(!pack.contains { $0.filled.lowercased() == "ich wasche mir die hände." })
        #expect(pack.contains { $0.filled == "Ich ziehe mir die Jacke an." })
        #expect(pack.contains { $0.filled == "Du beeilst dich heute." })
        #expect(GapChoicePlanner.slugify("Hände") == "haende" && GapChoicePlanner.slugify("am Wochenende") == "am-wochenende")
    }
}
