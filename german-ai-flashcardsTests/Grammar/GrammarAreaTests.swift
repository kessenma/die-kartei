//
//  GrammarAreaTests.swift
//  german-ai-flashcardsTests
//
//  The hub's rooms hold their contracts: the three case foci belong to the path and every other
//  focus to exactly one room (the flames depend on it); a room shelves each structure once; every
//  non-case topic ships with a focus and a shelf row, and the in-place upgrade predicate
//  (`GrammarRoute.hasExercise`) marks exactly the drill-less structures as Lektion rows.
//

import Foundation
import Testing
@testable import Die_Kartei

@Suite("Grammar areas")
struct GrammarAreaTests {

    @Test("Every non-case focus lives in exactly one area")
    func partition() {
        let pathFoci: Set<GrammarFocus> = [.akkusativ, .dativ, .genitiv]
        for focus in GrammarFocus.allCases {
            let homes = GrammarArea.allCases.filter { $0.foci.contains(focus) }
            if pathFoci.contains(focus) {
                #expect(homes.isEmpty, "\(focus.rawValue) belongs to the path, not a room")
            } else {
                #expect(homes.count == 1, "\(focus.rawValue) needs exactly one room, has \(homes.count)")
            }
        }
    }

    @Test("A room shelves only its own structures, once each; an own-hub area shelves nothing")
    func shelves() {
        for area in GrammarArea.allCases {
            var seen: Set<GrammarFocus> = []
            for row in area.rows {
                if case .struktur(let focus) = row {
                    #expect(area.foci.contains(focus), "\(area.rawValue) shelves \(focus.rawValue) it doesn't own")
                    #expect(seen.insert(focus).inserted, "\(focus.rawValue) shelved twice in \(area.rawValue)")
                }
            }
            #expect(area.hasOwnHub == area.rows.isEmpty,
                    "\(area.rawValue): an area keeps its own hub or a shelf, never both or neither")
            #expect(!area.levelLabel.isEmpty)
        }
    }

    @Test("Every non-case topic has a focus and a shelf row, and upgrades in place")
    @MainActor
    func topicsShelved() {
        for topic in GrammarTopic.allCases where topic.unit == nil {
            guard let focus = topic.focus else {
                Issue.record("\(topic.key) must ship with a GrammarFocus")
                continue
            }
            let shelved = GrammarArea.allCases.contains { area in
                area.rows.contains { row in
                    if case .struktur(let shelvedFocus) = row { shelvedFocus == focus } else { false }
                }
            }
            #expect(shelved, "\(topic.key) has no room row")
            #expect(GrammarRoute(focus).hasExercise, "\(topic.key) should render as a topic row, not a Lektion")
        }
    }

    @Test("Lektion rows are exactly the drill-less structures")
    @MainActor
    func lektionRows() {
        let lessonOnly = Set(GrammarFocus.allCases.filter { !GrammarRoute($0).hasExercise })
        #expect(lessonOnly == [.perfekt, .praeteritum, .futur, .konjunktiv2, .modalverben, .adjektivendungen])
    }

    @Test("A verb-pair focus routes to the hub's verb track; place and time keep the pick")
    @MainActor
    func verbTrack() {
        #expect(GrammarRoute(.verbenPraepositionen) == .prepositionHub(verbTrack: true))
        #expect(GrammarRoute(.praepositionen) == .prepositionHub(verbTrack: false))
        #expect(GrammarRoute(.wechselpraepositionen) == .prepositionHub(verbTrack: false))
    }
}
