//
//  ClassNotesGuide.swift
//  german-ai-flashcards
//
//  The rules behind the Deutschkurs onboarding (docs/CLASS_NOTES.md ▸ Onboarding): which
//  "Erste Schritte" items a learner sees, when each counts as done, and the few UserDefaults keys
//  the intro and the checklist share. Done is always read from the learner's real data, never
//  ticked by hand, so a step done before the checklist existed (or on another device) is already
//  ticked when it appears.
//

import Foundation
import SwiftData

enum ClassNotesGuide {

    // MARK: Keys

    /// UserDefaults keys. The intro flag and the checklist travel in `ProgressSyncDocument`.
    enum Keys {
        /// The intro was offered once (written before it appears, so Close never turns into a nag).
        static let introSeen = "classNotes.intro.seen"
        /// Raw `ClassCourse.Kind` the learner picked in the intro.
        static let kind = "classNotes.guide.kind"
        /// Raw `Material`s, comma separated.
        static let materials = "classNotes.guide.materials"
        /// When the checklist was last put on the hub (seconds since the reference date, 0 = never).
        static let shownAt = "classNotes.guide.shownAt"
        /// When the learner last hid it (same form).
        static let hiddenAt = "classNotes.guide.hiddenAt"

        static let all = [introSeen, kind, materials, shownAt, hiddenAt]
    }

    // MARK: What the class hands out

    /// The intro's "What does your class give you?" answers. They decide the optional items.
    enum Material: String, CaseIterable, Identifiable {
        case handouts, vocab, homework, talking

        var id: String { rawValue }

        var title: String {
            switch self {
            case .handouts: "Handouts or readings"
            case .vocab:    "Vocabulary lists"
            case .homework: "Homework sheets"
            case .talking:  "Mostly talking"
            }
        }

        var detail: String {
            switch self {
            case .handouts: "PDFs, photocopies, a story to read."
            case .vocab:    "A word list with the English, often with the test words marked."
            case .homework: "Exercises to fill in and hand back."
            case .talking:  "Not much on paper. The new words come up as you speak."
            }
        }

        var systemImage: String {
            switch self {
            case .handouts: "doc.text"
            case .vocab:    "list.bullet.rectangle"
            case .homework: "pencil.and.list.clipboard"
            case .talking:  "bubble.left.and.bubble.right"
            }
        }

        static func parse(_ raw: String) -> Set<Material> {
            Set(raw.split(separator: ",").compactMap { Material(rawValue: String($0)) })
        }

        static func serialize(_ set: Set<Material>) -> String {
            allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
        }

        /// Learning on your own: what you read is the material.
        static let selfStudyDefault: Set<Material> = [.handouts, .vocab]
    }

    // MARK: Items

    enum Item: String, CaseIterable, Identifiable {
        case course, logClass, handout, saveWord, vocabList, homework, studyDeck

        var id: String { rawValue }

        func title(for kind: ClassCourse.Kind) -> String {
            switch self {
            case .course:    kind == .selfStudy ? "Set up your study plan" : "Set up your course"
            case .logClass:  kind == .tutor ? "Log a session" : "Log a class"
            case .handout:   kind == .selfStudy ? "Add something to read" : "Add a handout"
            case .saveWord:  "Save a word to your deck"
            case .vocabList: "Turn a vocab list into flashcards"
            case .homework:  "Do homework in the app"
            case .studyDeck: "Study your deck"
            }
        }

        func detail(for kind: ClassCourse.Kind) -> String {
            switch self {
            case .course:
                "One per class you take. It keeps the notes, handouts and words together."
            case .logClass:
                "What it covered: grammar, topics, the new words, the homework."
            case .handout:
                kind == .selfStudy
                    ? "A PDF, a photo of a page, or pasted text. Read it word by word."
                    : "A PDF, a photo of a page, or pasted text, filed under the day's class."
            case .saveWord:
                "Double-tap a word you don't know in a handout, or add the new words to a class entry."
            case .vocabList:
                "Bring in the list as a PDF or photo. It is paired into German and English cards."
            case .homework:
                "Add the sheet as a PDF and turn on \"Set them up as homework\". Answer here or with the Pencil."
            case .studyDeck:
                "The words you saved, as flashcards that come back when you're about to forget them."
            }
        }

        var systemImage: String {
            switch self {
            case .course:    "graduationcap.fill"
            case .logClass:  "square.and.pencil"
            case .handout:   "doc.text.viewfinder"
            case .saveWord:  "text.badge.plus"
            case .vocabList: "list.bullet.rectangle"
            case .homework:  "pencil.and.list.clipboard"
            case .studyDeck: "rectangle.stack.fill"
            }
        }
    }

    /// The checklist for a kind of course and what it hands out, in the order to do them.
    static func items(kind: ClassCourse.Kind, materials: Set<Material>) -> [Item] {
        var items: [Item] = [.course]
        if kind != .selfStudy { items.append(.logClass) }
        if materials.contains(.handouts) { items.append(.handout) }
        items.append(.saveWord)
        if materials.contains(.vocab) { items.append(.vocabList) }
        if materials.contains(.homework), kind != .selfStudy { items.append(.homework) }
        items.append(.studyDeck)
        return items
    }

    // MARK: Done, from the data

    /// What the learner has done so far, as plain facts. Built by a fetch outside `body` (a
    /// filtered query read in `body` loops once a screen is pushed over the hub).
    struct Snapshot: Equatable {
        var hasCourse = false
        var hasEntry = false
        var hasHandout = false
        /// A course's own word deck holds a card.
        var hasSavedWord = false
        var hasDocumentDeck = false
        var hasWorksheet = false
        /// Some deck on a course has cards, so there is something to study.
        var hasStudyableDeck = false
        var hasStudied = false

        static let empty = Snapshot()

        @MainActor
        static func make(context: ModelContext) -> Snapshot {
            var s = Snapshot()
            let courses = (try? context.fetch(FetchDescriptor<ClassCourse>())) ?? []
            s.hasCourse = courses.contains { !$0.isArchived }
            let entries = (try? context.fetch(FetchDescriptor<ClassEntry>())) ?? []
            s.hasEntry = entries.contains { !$0.isEmpty }
            let materials = (try? context.fetch(FetchDescriptor<ClassMaterial>())) ?? []
            s.hasHandout = !materials.isEmpty
            s.hasWorksheet = materials.contains { $0.worksheetData != nil }
            let decks = (try? context.fetch(FetchDescriptor<SavedDeck>(
                predicate: #Predicate { $0.courseIDRaw != nil }
            ))) ?? []
            s.hasSavedWord = decks.contains { $0.generatorRaw == ClassDeckStore.generatorRaw && !$0.cards.isEmpty }
            s.hasDocumentDeck = decks.contains { $0.kind == .document }
            s.hasStudyableDeck = decks.contains { !$0.cards.isEmpty }
            s.hasStudied = decks.contains { $0.cards.contains { $0.lastReviewedAt != nil } }
            return s
        }
    }

    static func isDone(_ item: Item, in s: Snapshot) -> Bool {
        switch item {
        case .course:    s.hasCourse
        case .logClass:  s.hasEntry
        case .handout:   s.hasHandout
        case .saveWord:  s.hasSavedWord
        case .vocabList: s.hasDocumentDeck
        case .homework:  s.hasWorksheet
        case .studyDeck: s.hasStudied
        }
    }

    // MARK: When things show

    /// The intro opens by itself once, for someone with no course. Everyone else starts it from ?.
    static func shouldAutoShowIntro(seen: Bool, courseCount: Int) -> Bool {
        !seen && courseCount == 0
    }

    /// The checklist is on the hub from the last time it was put there until the learner hides it.
    /// Both stamps only move forward, so a restart on one device and a hide on another settle on
    /// whichever happened last.
    static func isChecklistVisible(shownAt: Double, hiddenAt: Double) -> Bool {
        shownAt > 0 && shownAt > hiddenAt
    }

    /// Put the checklist on the hub for this kind and these materials.
    static func showChecklist(kind: ClassCourse.Kind, materials: Set<Material>,
                              defaults: UserDefaults = .standard, now: Date = .now) {
        defaults.set(kind.rawValue, forKey: Keys.kind)
        defaults.set(Material.serialize(materials), forKey: Keys.materials)
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: Keys.shownAt)
    }

    static func hideChecklist(defaults: UserDefaults = .standard, now: Date = .now) {
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: Keys.hiddenAt)
    }
}
