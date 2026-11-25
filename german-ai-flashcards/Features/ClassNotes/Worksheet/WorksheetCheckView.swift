//
//  WorksheetCheckView.swift
//  german-ai-flashcards
//
//  "Prüfen · Check my answers": the optional second opinion before the homework goes to the
//  teacher. Handwriting is read first and confirmed by the learner; then each answer is checked by
//  the teacher's key, the article rules or the tutor (`WorksheetGrader`), and the verdicts are
//  listed page by page. Nothing here is ever drawn into the PDF she receives.
//

import SwiftUI

struct WorksheetCheckView: View {
    @Bindable var session: WorksheetSession
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// One page ("Check this page"): read its handwriting or check it straight away, and list
    /// only its answers. Nil checks every page.
    var page: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    @State private var readings: [WorksheetInkReading] = []
    @State private var confirmed: [String: String] = [:]
    @State private var readingInk = false
    @State private var readInk = false
    @State private var useTutor = true
    @State private var status: String?
    @State private var running = false
    @State private var started = false
    /// Unsure readings the learner has looked at ("Looks right", a tap on an alternative, an edit).
    @State private var acknowledged: Set<String> = []
    /// The answer being corrected in the results ("Fix"), and its text so far.
    @State private var editingKey: String?
    @State private var editText = ""

    /// Unsure readings still to be looked at before "These are right" can be pressed.
    private var unsureLeft: Int {
        readings.filter { !$0.isSure && !acknowledged.contains($0.key) }.count
    }

    /// The pages in scope.
    private var plans: [WorksheetPagePlan] {
        session.setup.pages.filter { page == nil || $0.page == page }
    }

    private var tutorAvailable: Bool { !DocumentTutorChoice.downloaded.isEmpty }

    /// Pages with ink at blanks that have no typed answer yet.
    private var inkPages: [WorksheetPagePlan] {
        plans.filter { plan in
            !session.isRedo
                && session.parts[plan.page]?.exercise.verdict == .interactive
                && WorksheetInkStore.read(session.material.id, page: plan.page) != nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your teacher's answer key comes first when the sheet has one. Then the app's own rules: articles after a preposition, and a group put into a case (ein Brot → mit einem Brot). Anything else goes to your tutor model. When the app or the tutor isn't sure, it says \"prüfen\" rather than calling it wrong.")
                        .font(.subheadline)
                } footer: {
                    Text("The PDF you share shows only your answers, unless you pick Share ▸ With the check marks.")
                        .font(.caption2)
                }
                .themedListRow()

                if !inkPages.isEmpty {
                    handwritingSection
                }

                Section {
                    DocumentTutorPicker(modelManager: modelManager)
                    Toggle("Ask the tutor what the rules can't check", isOn: $useTutor)
                        .disabled(!tutorAvailable)
                    Button {
                        Task { await runCheck() }
                    } label: {
                        HStack {
                            Label("Check my answers", systemImage: "checkmark.seal")
                            if running { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(running || (!readings.isEmpty && !readInk))
                    if let status {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Prüfen · Check").themedSectionHeader()
                } footer: {
                    if !tutorAvailable {
                        Text("No tutor is downloaded, so only the teacher's key and the article rules check. Download one under Settings ▸ Model & Downloads.")
                            .font(.caption2)
                    }
                }
                .themedListRow()

                resultsSections
            }
            .themedListScreen()
            .navigationTitle(page.map { "Check page \($0)" } ?? "Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(running)
        .task { await startForOnePage() }
    }

    /// From a page's own button: one tap should be enough. Handwriting is read first (and waits
    /// for the learner's confirmation); a page answered in the app is checked at once.
    private func startForOnePage() async {
        guard page != nil, !started else { return }
        started = true
        if !inkPages.isEmpty {
            await readHandwriting()
            if readings.isEmpty { await runCheck() }
        } else {
            await runCheck()
        }
    }

    // MARK: - Handwriting

    private var handwritingSection: some View {
        Section {
            if readings.isEmpty {
                Button {
                    Task { await readHandwriting() }
                } label: {
                    HStack {
                        Label("Read my handwriting", systemImage: "text.viewfinder")
                        if readingInk { Spacer(); ProgressView() }
                    }
                }
                .disabled(readingInk)
            } else if readInk {
                // Confirmed: folded away, one tap from coming back. Changing a reading here
                // re-checks it.
                HStack {
                    Label(readings.count == 1 ? "1 reading confirmed" : "\(readings.count) readings confirmed",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Change") { readInk = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                ForEach(readings.sorted { ($0.isSure ? 1 : 0, $0.page) < ($1.isSure ? 1 : 0, $1.page) }) { reading in
                    readingRow(reading)
                }
                Button {
                    confirmReadings()
                } label: {
                    Label(unsureLeft > 0
                              ? (unsureLeft == 1 ? "Look at the unsure reading first" : "Look at the \(unsureLeft) unsure readings first")
                              : "These are right · check them",
                          systemImage: "checkmark.circle")
                }
                .disabled(unsureLeft > 0 || running)
            }
        } header: {
            Text("Lies ich das richtig? · Confirm what you wrote").themedSectionHeader()
        } footer: {
            if !readInk, !readings.isEmpty {
                Text("Read on this device. A reading marked ? needs a look: fix it, pick another, or tap Looks right. Answers you typed in the app aren't read again.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private func confirmReadings() {
        let checkedBefore = readings.contains { session.answer($0.key)?.check != nil }
        var changed: Set<String> = []
        for reading in readings {
            let text = (confirmed[reading.key] ?? reading.best).trimmingCharacters(in: .whitespacesAndNewlines)
            // Left out ("Skip" on ink that couldn't be read): no answer, nothing to check.
            guard !text.isEmpty else { continue }
            if session.answer(reading.key)?.text != text || session.answer(reading.key)?.source != .ink {
                session.setText(text, for: reading.key, source: .ink)
                changed.insert(reading.key)
            }
        }
        readInk = true
        // A correction after a check re-checks only what changed; the first confirmation of a
        // page's readings checks the page.
        if checkedBefore {
            if !changed.isEmpty { Task { await runCheck(only: changed) } }
        } else if page != nil {
            Task { await runCheck() }
        }
    }

    private func readingRow(_ reading: WorksheetInkReading) -> some View {
        let needsLook = !reading.isSure && !acknowledged.contains(reading.key)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let image = reading.image {
                    Image(decorative: image, scale: 3)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 160, maxHeight: 44)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                TextField(reading.isUnread ? "Couldn't read it: type or pick" : "What you wrote", text: Binding(
                    get: { confirmed[reading.key] ?? reading.best },
                    set: {
                        confirmed[reading.key] = $0
                        acknowledged.insert(reading.key)
                    }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .fontWeight(.semibold)
                if needsLook {
                    // Nothing to accept on ink that wasn't read: it can only be left out.
                    Button(reading.isUnread ? "Skip" : "Looks right") { acknowledged.insert(reading.key) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                } else if !reading.isSure {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Looked at")
                }
            }
            let picks = Self.picks(for: reading)
            if picks.count > 1 || (reading.isUnread && !picks.isEmpty) {
                // A matching exercise's letters fit on one line; a word bank scrolls.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(picks, id: \.self) { candidate in
                            let chosen = (confirmed[reading.key] ?? reading.best) == candidate
                            Button(candidate) {
                                confirmed[reading.key] = candidate
                                acknowledged.insert(reading.key)
                            }
                            .buttonStyle(.bordered)
                            .tint(chosen ? .accentColor : nil)
                            .controlSize(.mini)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                if needsLook {
                    Label(reading.isUnread ? "Couldn't read this" : "Unsure reading", systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                }
                Text("Seite \(reading.page)").foregroundStyle(.secondary)
            }
            .font(.caption2)
        }
        .padding(.vertical, 2)
        .background(needsLook ? Color.orange.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// One-tap answers under a reading: a matching exercise's letters in the sheet's order;
    /// otherwise the recognizer's readings, then the sheet's own words, each once.
    static func picks(for reading: WorksheetInkReading) -> [String] {
        if WorksheetInkReader.isLetters(reading.options) { return reading.options }
        var out: [String] = []
        for candidate in reading.candidates + reading.options where !candidate.isEmpty && !out.contains(candidate) {
            out.append(candidate)
        }
        return out
    }

    private func readHandwriting() async {
        readingInk = true
        defer { readingInk = false }
        var found: [WorksheetInkReading] = []
        for plan in inkPages {
            guard let part = session.parts[plan.page],
                  let ink = WorksheetInkStore.read(session.material.id, page: plan.page) else { continue }
            let keys = part.exercise.items.flatMap { item -> [String] in
                var keys = item.gaps.map(\.key)
                if item.writeBelow { keys.append(item.writeKey) }
                return keys
            }.filter { (session.answer($0)?.text ?? "").isEmpty || session.answer($0)?.source == .ink }
            let allowed = WorksheetCheckRunner.allowedAnswers(in: part.exercise)
            #if canImport(PencilKit)
            let page = plan.page
            let readingsOnPage = await Task.detached(priority: .userInitiated) {
                WorksheetInkReader.read(ink: ink, page: page, part: part, keys: keys, allowed: allowed)
            }.value
            found += readingsOnPage
            #endif
        }
        readings = found
        if found.isEmpty { status = "No handwriting found at the blanks." }
    }

    // MARK: - Checking

    /// Check every answer in scope, or only `keys` (a reading or an answer just corrected).
    private func runCheck(only keys: Set<String>? = nil) async {
        running = true
        defer { running = false }
        status = "Checking…"
        session.flush()
        let lexicon = WorksheetCheckRunner.lexicon(for: session)
        var open: [Int: Set<String>] = [:]
        var counts = (rules: 0, key: 0, tutor: 0)

        for plan in plans {
            guard let exercise = session.parts[plan.page]?.exercise, exercise.verdict == .interactive else { continue }
            for section in exercise.sections {
                for item in section.items {
                    for key in item.gaps.map(\.key) + item.choices.map(\.key) + (item.writeBelow ? [item.writeKey] : [])
                    where keys?.contains(key) ?? true {
                        guard let answer = session.answer(key), let given = WorksheetCheckRunner.given(answer, key: key, item: item) else { continue }
                        if let solution = session.setup.key?[key] {
                            let check = WorksheetKeyCheck.check(given, key: solution)
                            if check.outcome == .right
                                || WorksheetKeyCheck.isClosedSet(slot: key, item: item, options: section.options) {
                                session.setCheck(check, for: key)
                                counts.key += 1
                                continue
                            }
                            // An open blank in other words: "prüfen" with her answer, unless the
                            // rules or the tutor below can say more.
                            session.setCheck(WorksheetKeyCheck.mismatch(given, key: solution), for: key)
                        } else if let sample = session.setup.samples?[key] {
                            let check = WorksheetKeyCheck.example(given, sample: sample)
                            session.setCheck(check, for: key)
                            if check.outcome == .right {
                                counts.key += 1
                                continue
                            }
                        }
                        let candidates = WorksheetCheckRunner.candidates(for: key, item: item, options: section.options)
                        let directions = [exercise.instruction, section.heading].compactMap { $0 }.joined(separator: " ")
                        if let check = WorksheetArticleRules.check(
                            answer: given, caseTag: answer.kasus, slot: key, in: item, exercise: exercise,
                            candidates: candidates, lexicon: lexicon
                        ) {
                            session.setCheck(check, for: key)
                            counts.rules += 1
                        } else if let task = WorksheetGroupRules.task(slot: key, in: item, directions: directions,
                                                                      lexicon: lexicon) {
                            session.setCheck(WorksheetGroupRules.check(answer: given, task: task), for: key)
                            counts.rules += 1
                        } else {
                            open[plan.page, default: []].insert(key)
                        }
                    }
                }
            }
        }

        if useTutor, tutorAvailable, !open.isEmpty {
            let model = DocumentTutorChoice.current(modelManager)
            if !mlxService.isModelLoaded || mlxService.currentModel != model {
                status = "Loading \(model.rawValue)…"
                await mlxService.loadModel(model)
            }
            if mlxService.isModelLoaded, mlxService.currentModel == model {
                for (page, keys) in open.sorted(by: { $0.key < $1.key }) {
                    guard let exercise = session.parts[page]?.exercise else { continue }
                    let references = (session.setup.samples ?? [:]).merging(session.setup.key ?? [:]) { _, key in key }
                    let questions = WorksheetTutorCheck.questions(for: exercise, answers: session.answers, open: keys,
                                                                  references: references)
                    guard !questions.isEmpty else { continue }
                    status = "Asking \(model.rawValue) about page \(page)…"
                    let prompt = WorksheetTutorCheck.prompt(instruction: exercise.instruction, nouns: exercise.nouns,
                                                            questions: questions)
                    let reply = (try? await mlxService.generateText(
                        system: WorksheetTutorCheck.system, user: prompt, model: model,
                        maxTokens: 40 + questions.count * 40
                    )).map(ConversationPrompts.stripThinkBlocks) ?? ""
                    for (key, check) in WorksheetTutorCheck.parse(reply, questions: questions) {
                        session.setCheck(check, for: key)
                        counts.tutor += 1
                    }
                }
            } else {
                status = mlxService.loadError ?? "Couldn't load \(model.rawValue)."
                return
            }
        }
        session.flush()
        let total = counts.rules + counts.key + counts.tutor
        let left = useTutor && tutorAvailable ? 0 : open.values.reduce(0) { $0 + $1.count }
        status = total == 0 ? "Nothing to check yet." : "Checked \(total)" + (left > 0 ? "; \(left) left for your teacher." : ".")
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSections: some View {
        ForEach(plans) { plan in
            if let exercise = session.parts[plan.page]?.exercise, exercise.verdict == .interactive {
                let rows = resultRows(exercise)
                if !rows.isEmpty {
                    Section {
                        ForEach(rows, id: \.key) { row in
                            resultRow(row)
                        }
                    } header: {
                        Text(exercise.displayTitle).themedSectionHeader()
                    }
                    .themedListRow()
                }
            }
        }
    }

    private struct ResultRow {
        var key: String
        var line: String
        var check: WorksheetCheck
        var stale: Bool
        /// The answer as text, for "Fix"; nil for a choice, which is fixed with a tap on the page.
        var text: String?
    }

    private func resultRows(_ exercise: WorksheetExercise) -> [ResultRow] {
        exercise.items.flatMap { item -> [ResultRow] in
            let keys = item.gaps.map(\.key) + item.choices.map(\.key) + (item.writeBelow ? [item.writeKey] : [])
            return keys.compactMap { key in
                guard let answer = session.answer(key), let check = answer.check else { return nil }
                let given = WorksheetCheckRunner.given(answer, key: key, item: item) ?? ""
                let line = key.hasSuffix(".w") ? given : WorksheetTutorCheck.render(item, answers: session.answers)
                let isChoice = item.choices.contains { $0.key == key }
                return ResultRow(key: key, line: line, check: check, stale: given != check.answer,
                                 text: isChoice ? nil : answer.text)
            }
        }
    }

    private func resultRow(_ row: ResultRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(row.check.outcome))
                .foregroundStyle(color(row.check.outcome))
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.line).font(.subheadline)
                if let correction = row.check.correction, row.check.outcome != .right {
                    Text("→ \(correction)").font(.subheadline.weight(.semibold))
                }
                if let reason = row.check.reason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                Text(row.stale ? "Changed since the check" : source(row.check.by))
                    .font(.caption2)
                    .foregroundStyle(row.stale ? .orange : .secondary)
                if row.check.outcome != .right {
                    AskTeacherButton(
                        prefill: "„\(row.line)“: why" + (row.check.correction.map { " „\($0)“" } ?? " not like this") + "?",
                        context: "Übung · " + (session.material.title.isEmpty ? "Worksheet" : session.material.title)
                    )
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                if editingKey == row.key {
                    fixEditor(row)
                }
            }
            Spacer(minLength: 0)
            if row.text != nil, editingKey != row.key {
                Button {
                    editText = row.text ?? ""
                    editingKey = row.key
                } label: {
                    Label("Fix", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Correct this answer or its reading, then check it again")
            }
        }
    }

    /// Correct one answer (a misread word, a typo) and check just that one again. The crop of the
    /// handwriting is shown when the answer came from the ink.
    private func fixEditor(_ row: ResultRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = readings.first(where: { $0.key == row.key })?.image {
                Image(decorative: image, scale: 3)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 50)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            TextField("Your answer", text: $editText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { saveFix(row) }
            HStack(spacing: 10) {
                Button {
                    saveFix(row)
                } label: {
                    Label("Check again", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || running)
                Button("Cancel") { editingKey = nil }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(.top, 6)
    }

    private func saveFix(_ row: ResultRow) {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let source = session.answer(row.key)?.source ?? .typed
        session.setText(text, for: row.key, source: source)
        if source == .ink { confirmed[row.key] = text }
        editingKey = nil
        Task { await runCheck(only: [row.key]) }
    }

    private func icon(_ outcome: WorksheetCheck.Outcome) -> String {
        switch outcome {
        case .right: "checkmark.circle.fill"
        case .unsure: "questionmark.circle"
        case .wrong: "xmark.circle"
        }
    }

    private func color(_ outcome: WorksheetCheck.Outcome) -> Color {
        switch outcome {
        case .right: Color.teal
        case .unsure: Color.secondary
        case .wrong: Color.orange
        }
    }

    private func source(_ checker: WorksheetCheck.Checker) -> String {
        switch checker {
        case .key: "Teacher's key"
        case .rules: "Article rules"
        case .tutor: "Tutor · prüfen means ask your teacher"
        }
    }
}

// MARK: - Runner helpers

enum WorksheetCheckRunner {
    /// The answer as text: a choice is the option it picked.
    static func given(_ answer: WorksheetAnswer, key: String, item: WorksheetItem) -> String? {
        if let choice = item.choices.first(where: { $0.key == key }) {
            guard let picked = answer.choice, choice.options.indices.contains(picked) else { return nil }
            return choice.options[picked].text
        }
        guard let text = answer.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// For each short blank in a section that offers its answers (letters, a word bank, a named
    /// set), those answers: what a handwriting reading is matched to.
    static func allowedAnswers(in exercise: WorksheetExercise) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for section in exercise.sections {
            guard let choices = section.options?.choices, !choices.isEmpty else { continue }
            for item in section.items {
                for gap in item.gaps where !gap.isLong { out[gap.key] = choices }
            }
        }
        return out
    }

    /// The articles a slot chooses between: a choice's options, or the section's named set.
    static func candidates(for key: String, item: WorksheetItem, options: WorksheetOptions?) -> [String] {
        if let choice = item.choices.first(where: { $0.key == key }) { return choice.options.map(\.text) }
        guard item.gaps.contains(where: { $0.key == key && !$0.isLong }) else { return [] }
        switch options {
        case .closedSet(let words)?, .articles(let words)?: return words
        default: return []
        }
    }

    /// The preposition table and the dictionary's genders for every noun-like word on the pages,
    /// looked up here on the main actor so the rules can stay pure.
    static func lexicon(for session: WorksheetSession) -> WorksheetArticleRules.Lexicon {
        var lexicon = WorksheetArticleRules.Lexicon()
        for preposition in PrepositionService.all() {
            lexicon.prepositions[preposition.word.lowercased()] = preposition.governs
        }
        var words: Set<String> = []
        for part in session.parts.values {
            for item in part.exercise.items {
                for word in item.words where word.text.first?.isUppercase == true { words.insert(word.text) }
            }
            for noun in part.exercise.nouns {
                if let lemma = noun.split(separator: " ").last { words.insert(String(lemma)) }
            }
        }
        var forms = words
        for word in words {
            for ending in ["e", "en", "n", "er", "s", "es"] where word.hasSuffix(ending) && word.count > ending.count + 2 {
                forms.insert(String(word.dropLast(ending.count)))
            }
        }
        for form in forms {
            if let found = WiktionaryValidator.shared.nounArticle(for: form) {
                lexicon.genders[form] = found.article.gender
            }
        }
        return lexicon
    }
}
