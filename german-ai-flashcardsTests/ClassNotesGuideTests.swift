//
//  ClassNotesGuideTests.swift
//  german-ai-flashcardsTests
//
//  The Deutschkurs onboarding's rules (docs/CLASS_NOTES.md ▸ Onboarding): which checklist items a
//  learner sees for how they learn and what their class hands out, when each counts as done from
//  real data, and when the intro and the checklist show.
//

import Foundation
import SwiftData
import Testing
@testable import Die_Kartei

@MainActor
@Suite struct ClassNotesGuideTests {

    // MARK: Items

    @Test func aCourseThatHandsOutEverythingGetsEveryItem() {
        let items = ClassNotesGuide.items(kind: .course, materials: [.handouts, .vocab, .homework])
        #expect(items == [.course, .logClass, .handout, .saveWord, .vocabList, .homework, .studyDeck])
    }

    @Test func mostlyTalkingKeepsOnlyTheCore() {
        let items = ClassNotesGuide.items(kind: .tutor, materials: [.talking])
        #expect(items == [.course, .logClass, .saveWord, .studyDeck])
    }

    @Test func selfStudyHasNoClassesToLogAndNoHomework() {
        let items = ClassNotesGuide.items(kind: .selfStudy, materials: [.handouts, .vocab, .homework])
        #expect(!items.contains(.logClass))
        #expect(!items.contains(.homework))
        #expect(items.first == .course)
        #expect(items.last == .studyDeck)
    }

    @Test func materialsRoundTripThroughTheirStoredForm() {
        let all = Set(ClassNotesGuide.Material.allCases)
        #expect(ClassNotesGuide.Material.parse(ClassNotesGuide.Material.serialize(all)) == all)
        #expect(ClassNotesGuide.Material.parse("") == [])
        #expect(ClassNotesGuide.Material.parse("vocab,nonsense") == [.vocab])
    }

    // MARK: When things show

    @Test func theIntroOpensByItselfOnlyOnceAndOnlyWithNoCourse() {
        #expect(ClassNotesGuide.shouldAutoShowIntro(seen: false, courseCount: 0))
        #expect(!ClassNotesGuide.shouldAutoShowIntro(seen: true, courseCount: 0))
        #expect(!ClassNotesGuide.shouldAutoShowIntro(seen: false, courseCount: 1))
    }

    @Test func theChecklistShowsFromItsLastShowUntilItsNextHide() {
        #expect(!ClassNotesGuide.isChecklistVisible(shownAt: 0, hiddenAt: 0))
        #expect(ClassNotesGuide.isChecklistVisible(shownAt: 100, hiddenAt: 0))
        #expect(!ClassNotesGuide.isChecklistVisible(shownAt: 100, hiddenAt: 200))
        // A restart after a hide brings it back.
        #expect(ClassNotesGuide.isChecklistVisible(shownAt: 300, hiddenAt: 200))
    }

    @Test func showingAndHidingWriteTheStamps() throws {
        let defaults = try #require(UserDefaults(suiteName: "ClassNotesGuideTests.\(UUID().uuidString)"))
        ClassNotesGuide.showChecklist(kind: .tutor, materials: [.vocab],
                                      defaults: defaults, now: Date(timeIntervalSinceReferenceDate: 100))
        #expect(defaults.string(forKey: ClassNotesGuide.Keys.kind) == "tutor")
        #expect(defaults.string(forKey: ClassNotesGuide.Keys.materials) == "vocab")
        #expect(defaults.double(forKey: ClassNotesGuide.Keys.shownAt) == 100)
        ClassNotesGuide.hideChecklist(defaults: defaults, now: Date(timeIntervalSinceReferenceDate: 150))
        #expect(!ClassNotesGuide.isChecklistVisible(
            shownAt: defaults.double(forKey: ClassNotesGuide.Keys.shownAt),
            hiddenAt: defaults.double(forKey: ClassNotesGuide.Keys.hiddenAt)))
    }

    // MARK: Done, from the data

    @Test func doneFollowsTheData() throws {
        let container = ModelContainer.inMemory([ClassCourse.self, ClassEntry.self, ClassMaterial.self,
                                                 SavedDeck.self, SavedCard.self])
        let context = container.mainContext

        #expect(ClassNotesGuide.Snapshot.make(context: context) == .empty)

        // A course, and an empty entry (which doesn't count as a logged class).
        let course = ClassCourse(name: "Deutschkurs")
        context.insert(course)
        let entry = ClassEntry(date: .now)
        context.insert(entry)
        entry.course = course
        try context.save()
        var s = ClassNotesGuide.Snapshot.make(context: context)
        #expect(ClassNotesGuide.isDone(.course, in: s))
        #expect(!ClassNotesGuide.isDone(.logClass, in: s))

        // Something written in it makes it a logged class.
        entry.title = "Kapitel 1"
        try context.save()
        s = ClassNotesGuide.Snapshot.make(context: context)
        #expect(ClassNotesGuide.isDone(.logClass, in: s))
        #expect(!ClassNotesGuide.isDone(.saveWord, in: s))

        // A word saved into the course's own deck: there is something to study, not yet studied.
        ClassDeckStore.saveWord(german: "der Apfel", english: "the apple", course: course, feedsCoach: false, context: context)
        try context.save()
        s = ClassNotesGuide.Snapshot.make(context: context)
        #expect(ClassNotesGuide.isDone(.saveWord, in: s))
        #expect(s.hasStudyableDeck)
        #expect(!ClassNotesGuide.isDone(.studyDeck, in: s))

        // One review is a study.
        let deck = try #require(ClassDeckStore.deck(for: course, context: context))
        deck.cards.first?.lastReviewedAt = .now
        try context.save()
        s = ClassNotesGuide.Snapshot.make(context: context)
        #expect(ClassNotesGuide.isDone(.studyDeck, in: s))

        // An archived course alone no longer counts as having one.
        course.isArchived = true
        try context.save()
        s = ClassNotesGuide.Snapshot.make(context: context)
        #expect(!ClassNotesGuide.isDone(.course, in: s))
    }
}
