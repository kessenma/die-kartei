//
//  GeneratedKasusStory.swift
//  german-ai-flashcards
//
//  A tutor-written Kasus story that passed the check (Phase 3). The story itself is stored in the
//  bundled stories' own format (`KasusStory`, source generated), so it plays in Lesen, Markieren
//  and Endungen exactly like a bundled one, is validated again at play time, and its rounds file
//  under its id like any other (`KasusRound.storyID`). The plan that produced it is kept beside
//  it, so a story always says what it was asked to contain.
//
//  Additive, with every field defaulted: the store recreates itself when a migration fails, so a
//  new model must never be the thing that makes one fail.
//

import Foundation
import SwiftData

@Model
final class GeneratedKasusStory {
    /// The story's id („kg-dativ-a2-3f9a1c0b“), the same as `KasusStory.id`: what its rounds key on.
    var id: String = ""
    var date: Date = Date()
    /// A `KasusUnit` raw value.
    var unitRaw: String = ""
    /// A `CEFRLevel` raw value.
    var level: String = ""
    /// The tutor that wrote it: an `MLXModel` raw value.
    var modelID: String = ""
    /// The title, for lists that shouldn't decode the story.
    var title: String = ""
    /// Encoded `KasusStoryPlan`.
    var planData: Data? = nil
    /// Encoded `KasusStory`, source generated.
    var storyData: Data? = nil
    /// The check's line when it passed („PASS · 6/6 placed · …“, `KasusCheckResult.summaryLine`).
    var validatorSummary: String = ""
    /// 1 when the first try passed, 2 after the retry.
    var attempts: Int = 1
    /// Seconds the passing write took.
    var generationSeconds: Double = 0

    init(id: String, unitRaw: String, level: String, modelID: String, title: String,
         planData: Data?, storyData: Data?, validatorSummary: String, attempts: Int,
         generationSeconds: Double, date: Date = Date()) {
        self.id = id
        self.unitRaw = unitRaw
        self.level = level
        self.modelID = modelID
        self.title = title
        self.planData = planData
        self.storyData = storyData
        self.validatorSummary = validatorSummary
        self.attempts = attempts
        self.generationSeconds = generationSeconds
        self.date = date
    }

    /// The playable story, or nil if the data doesn't decode.
    var story: KasusStory? {
        storyData.flatMap { try? JSONDecoder().decode(KasusStory.self, from: $0) }
    }

    var plan: KasusStoryPlan? {
        planData.flatMap { try? JSONDecoder().decode(KasusStoryPlan.self, from: $0) }
    }

    var unit: KasusUnit? { KasusUnit(rawValue: unitRaw) }
}
