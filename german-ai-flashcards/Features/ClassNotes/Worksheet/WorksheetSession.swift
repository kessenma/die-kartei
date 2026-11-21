//
//  WorksheetSession.swift
//  german-ai-flashcards
//
//  The state of one open worksheet: which page is up, every page's parse, the learner's answers
//  (saved to the handout a moment after they stop typing, and on leaving), which gap the chip tray
//  is filling, and the preview of the current slide with the answers drawn in. The views read it;
//  the PDF itself stays inside `WorksheetDocumentActor`.
//

import CoreGraphics
import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class WorksheetSession {
    let material: ClassMaterial
    let pdfData: Data
    let document: WorksheetDocumentActor
    private let context: ModelContext

    private(set) var setup: WorksheetSetup
    private(set) var answers: [String: WorksheetAnswer]
    private(set) var parts: [Int: WorksheetPagePart] = [:]
    var index = 0 {
        didSet {
            focusedKey = nil
            refreshPreview()
        }
    }
    /// The gap the chip tray fills and the preview rings.
    var focusedKey: String?
    /// The current slide with the answers drawn in, re-rendered shortly after each change.
    private(set) var preview: CGImage?
    /// Bumped when a page's ink is saved, so the preview re-renders with it.
    private(set) var inkRevision = 0
    /// "Lösungen": her answer key shown on the Pencil slide, for marking your own work. Off each
    /// time the worksheet opens; shared by the page and full screen. Never in the export.
    var showsKey = false

    private var saveTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    /// Her review plan's redo (docs/WORKSHEETS.md ▸ Wiederholen): the answers start empty, nothing
    /// is saved to the handout, and the Pencil ink is left alone. Typed answers only.
    let isRedo: Bool

    /// Nil when the handout has no worksheet or its PDF is gone.
    init?(material: ClassMaterial, context: ModelContext, redo: Bool = false) {
        guard let setup = material.worksheet, !setup.pages.isEmpty,
              let url = material.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        self.material = material
        self.context = context
        self.pdfData = data
        self.document = WorksheetDocumentActor(data: data)
        self.setup = setup
        self.isRedo = redo
        self.answers = redo ? [:] : material.worksheetAnswers
    }

    // MARK: - Loading

    func load() async {
        for plan in setup.pages {
            if let part = await document.page(plan.page) { parts[plan.page] = part }
        }
        if setup.parserVersion != WorksheetParser.version, !isRedo {
            answers = WorksheetRekey.rekey(answers, plans: setup.pages, parts: parts)
            setup.parserVersion = WorksheetParser.version
            setup.pages = setup.pages.map { WorksheetRekey.refreshAnchors($0, part: parts[$0.page]) }
            material.worksheet = setup
            scheduleSave(immediately: true)
        }
        // A worksheet set up before the key reader existed: read her Lösungen pages once.
        if setup.key == nil {
            let reading = await document.answerKey()
            setup.key = reading.key
            setup.samples = reading.samples.isEmpty ? nil : reading.samples
            material.worksheet = setup
            scheduleSave(immediately: true)
        }
        refreshPreview()
    }

    // MARK: - Pages

    var plan: WorksheetPagePlan? { setup.pages.indices.contains(index) ? setup.pages[index] : nil }
    var part: WorksheetPagePart? { plan.flatMap { parts[$0.page] } }

    /// The page's exercise when it can be answered in the app.
    var exercise: WorksheetExercise? {
        guard let part, part.exercise.verdict == .interactive else { return nil }
        return part.exercise
    }

    func setMode(_ mode: WorksheetPagePlan.Mode) {
        guard setup.pages.indices.contains(index) else { return }
        setup.pages[index].mode = mode
        material.worksheet = setup
        try? context.save()
    }

    /// The paper around this page's slide for notes. Ink already written there is kept either way:
    /// it is in the page's drawing, outside the slide, and shows again when the side comes back.
    func setNotes(_ notes: WorksheetNotesMargins) {
        guard setup.pages.indices.contains(index) else { return }
        setup.pages[index].notes = notes.isEmpty ? nil : notes
        material.worksheet = setup
        try? context.save()
    }

    /// "3 of 8": answerable parts with an answer, on one page.
    func progress(page: Int) -> (done: Int, total: Int) {
        guard let exercise = parts[page]?.exercise, exercise.verdict == .interactive else {
            let inked = !isRedo && WorksheetInkStore.read(material.id, page: page) != nil
            return (inked ? 1 : 0, 1)
        }
        let keys = exercise.answerKeys
        return (keys.filter { answers[$0].map { !$0.isEmpty } ?? false }.count, keys.count)
    }

    var overallProgress: (done: Int, total: Int) {
        setup.pages.reduce((0, 0)) { sum, plan in
            let p = progress(page: plan.page)
            return (sum.0 + p.done, sum.1 + p.total)
        }
    }

    // MARK: - Answers

    func answer(_ key: String) -> WorksheetAnswer? { answers[key] }

    func setText(_ text: String, for key: String, source: WorksheetAnswer.Source = .typed) {
        update(key) { $0.text = text; $0.source = source }
    }

    func setChoice(_ choice: Int?, for key: String) {
        update(key) { $0.choice = $0.choice == choice ? nil : choice }
    }

    func toggleMark(_ word: Int, for key: String) {
        update(key) { answer in
            var marks = Set(answer.marks ?? [])
            if marks.contains(word) { marks.remove(word) } else { marks.insert(word) }
            answer.marks = marks.isEmpty ? nil : marks.sorted()
        }
    }

    func setCase(_ kasus: GrammarCase?, for key: String) {
        update(key) { $0.caseTag = $0.caseTag == kasus?.rawValue ? nil : kasus?.rawValue }
    }

    /// Record a check without touching `at`: the app's opinion isn't an edit of the answer.
    func setCheck(_ check: WorksheetCheck?, for key: String) {
        guard var answer = answers[key] else { return }
        answer.check = check
        answers[key] = answer
        scheduleSave()
    }

    private func update(_ key: String, _ change: (inout WorksheetAnswer) -> Void) {
        var answer = answers[key] ?? WorksheetAnswer()
        change(&answer)
        answer.at = .now
        if answer.isEmpty {
            answers[key] = nil
        } else {
            answers[key] = answer
        }
        scheduleSave()
        refreshPreview()
    }

    // MARK: - Saving

    /// A moment after the last change: typing a word is several changes, one save.
    func scheduleSave(immediately: Bool = false) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .seconds(0.8)) }
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        // A redo is practice: the handout keeps the answers she will see.
        guard !isRedo else { return }
        material.worksheetAnswers = answers
        material.entry?.updatedAt = .now
        try? context.save()
    }

    /// Ink was saved for a page: the preview and the progress pick it up.
    func inkSaved() {
        inkRevision += 1
        refreshPreview()
    }

    // MARK: - Sent

    var isSent: Bool { setup.status == .sent }

    func markSent(_ sent: Bool) {
        setup.status = sent ? .sent : .working
        setup.sentAt = sent ? .now : nil
        material.worksheet = setup
        if let entry = material.entry {
            entry.homeworkDone = sent
            entry.updatedAt = .now
        }
        flush()
    }

    // MARK: - Her answer key

    /// Her answers (and examples) for a page's blanks and choices, from her Lösungen pages.
    func herAnswers(page: Int) -> [String: WorksheetRenderer.KeyAnswer] {
        guard let exercise = parts[page]?.exercise else { return [:] }
        let key = setup.key ?? [:]
        let samples = setup.samples ?? [:]
        var out: [String: WorksheetRenderer.KeyAnswer] = [:]
        for item in exercise.items {
            for slot in item.gaps.map(\.key) + item.choices.map(\.key) {
                if let answer = key[slot] {
                    out[slot] = WorksheetRenderer.KeyAnswer(text: answer, isExample: false)
                } else if let example = samples[slot] {
                    out[slot] = WorksheetRenderer.KeyAnswer(text: example, isExample: true)
                }
            }
        }
        return out
    }

    /// What the slide under the Pencil shows of her key right now.
    func shownKey(page: Int) -> [String: WorksheetRenderer.KeyAnswer] {
        showsKey ? herAnswers(page: page) : [:]
    }

    // MARK: - Preview and export

    func refreshPreview() {
        previewTask?.cancel()
        guard let plan else { preview = nil; return }
        let answers = answers
        let ink = isRedo ? nil : WorksheetInkStore.read(material.id, page: plan.page)
        let outlines = WorksheetDebug.outlinesGaps
        previewTask = Task { [document] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let image = await document.render(page: plan.page, answers: answers, ink: ink,
                                              width: 960, scale: 2, outlinesGaps: outlines)
            guard !Task.isCancelled else { return }
            self.preview = image
        }
    }

    var exportSnapshot: WorksheetExport.Snapshot {
        WorksheetExport.Snapshot(
            pdfData: pdfData,
            materialID: material.id,
            title: material.title,
            pages: setup.pages,
            answers: answers,
            outlinesGaps: WorksheetDebug.outlinesGaps
        )
    }
}

// MARK: - Re-keying

/// When a later parser numbers a page's items differently, answers follow their item by its
/// printed text (the anchor stored at setup), not by the old key. An answer whose item can't be
/// found keeps its old key: it is never dropped.
enum WorksheetRekey {
    static func rekey(_ answers: [String: WorksheetAnswer], plans: [WorksheetPagePlan],
                      parts: [Int: WorksheetPagePart]) -> [String: WorksheetAnswer] {
        var out = answers
        for plan in plans {
            guard let items = parts[plan.page]?.exercise.items else { continue }
            for (oldKey, anchor) in plan.anchors {
                guard let match = items.first(where: { $0.anchor == anchor }), match.key != oldKey else { continue }
                for (key, value) in answers where key == oldKey || key.hasPrefix(oldKey + ".") {
                    out[key] = nil
                    out[match.key + key.dropFirst(oldKey.count)] = value
                }
            }
        }
        return out
    }

    static func refreshAnchors(_ plan: WorksheetPagePlan, part: WorksheetPagePart?) -> WorksheetPagePlan {
        guard let items = part?.exercise.items else { return plan }
        var plan = plan
        plan.anchors = Dictionary(items.map { ($0.key, $0.anchor) }, uniquingKeysWith: { first, _ in first })
        return plan
    }
}

/// Debug switches read from the launch arguments (DEBUG builds only).
enum WorksheetDebug {
    /// `-classNotes.debugWorksheetRects 1`: outline every placed gap in the preview and the export.
    static var outlinesGaps: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "classNotes.debugWorksheetRects")
        #else
        false
        #endif
    }
}
