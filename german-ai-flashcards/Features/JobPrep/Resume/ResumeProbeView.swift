//
//  ResumeProbeView.swift
//  german-ai-flashcards
//
//  Settings ▸ Developer ▸ Lebenslauf-Probe (roadmap item 18, "measure first"): does the recruiter
//  use the fact it is given, and does it invent career details? For the chosen tutor, it writes
//  the recruiter's question for each plan point of a posting-less interview over the learner's own
//  résumé, then marks each: the fact named (content words shared), and years or capitalised names
//  that appear nowhere in the Kurzprofil or the facts (possible inventions, to read by hand).
//  Runs where the tutors run: a device or the Mac. Nothing is stored.
//

import SwiftData
import SwiftUI

nonisolated enum ResumeProbe {
    /// Content words of the fact that the question repeats.
    static func factUsed(question: String, fact: String) -> Bool {
        let f = ResumePrompts.keywords(fact)
        guard !f.isEmpty else { return false }
        let q = ResumePrompts.keywords(question)
        let shared = f.filter { w in q.contains(w) || q.contains { $0.hasPrefix(String(w.prefix(5))) && w.count >= 5 } }
        return shared.count >= min(2, f.count)
    }

    /// Years and capitalised multi-letter tokens in the question that the résumé text never has.
    static func possibleInventions(question: String, known: String) -> [String] {
        let knownLower = known.lowercased()
        let tokens = question.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        var out: [String] = []
        for t in tokens.map(String.init) {
            let isYear = t.count == 4 && Int(t).map { (1950...2035).contains($0) } == true
            // An acronym (SAP, AWS) or a name with an inner capital (MusterTech).
            let isAcronym = t.count >= 3 && t.allSatisfy { $0.isUppercase || $0.isNumber } && t.contains { $0.isLetter }
            let isNameLike = isAcronym || (t.count >= 4 && t.first?.isUppercase == true && t.dropFirst().contains { $0.isUppercase })
            if (isYear || isNameLike), !knownLower.contains(t.lowercased()), !out.contains(t) { out.append(t) }
        }
        return out
    }
}

struct ResumeProbeView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @State private var rows: [(point: String, fact: String?, question: String, used: Bool, inventions: [String])] = []
    @State private var running = false

    var body: some View {
        List {
            Section {
                Button(running ? "Running…" : "Run on \(modelManager.selectedChatModel.rawValue)") { Task { await run() } }
                    .disabled(running || ResumeStore.current(in: modelContext)?.kurzprofil.isEmpty != false)
            } footer: {
                Text("Uses your Lebenslauf. For each plan point: the fact the app picked, the recruiter's question, whether it named the fact, and years or names it used that your résumé doesn't have. Read the questions too: the marks are only a first pass.")
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Section {
                    Text(row.question).font(.callout)
                    Label(row.fact.map { "Fact: \($0)" } ?? "No matching fact", systemImage: row.used ? "checkmark.circle.fill" : "circle")
                        .font(.caption).foregroundStyle(row.used ? .green : .secondary)
                    if !row.inventions.isEmpty {
                        Label("Not in the résumé: " + row.inventions.joined(separator: ", "), systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } header: {
                    Text(row.point)
                }
            }
        }
        .navigationTitle("Lebenslauf-Probe")
    }

    private func run() async {
        guard let resume = ResumeStore.current(in: modelContext) else { return }
        running = true
        defer { running = false }
        let model = modelManager.selectedChatModel
        if !(mlxService.isModelLoaded && mlxService.currentModel == model) { await mlxService.loadModel(model) }
        guard mlxService.isModelLoaded else { return }
        var config = ConversationConfig(model: model)
        config.mode = .interview
        config.formality = .sie
        config.resumeProfile = String(resume.kurzprofil.prefix(ResumePrompts.kurzprofilSlice(saver: MemorySaver.isActive(for: model))))
        config.resumeFacts = resume.facts.map(\.text)
        let system = ConversationPrompts.systemPrompt(for: config)
        let known = resume.kurzprofil + " " + resume.facts.map(\.text).joined(separator: " ") + " " + resume.fullText
        rows = []
        for (index, point) in ResumePrompts.generalPlan.enumerated() {
            let note = ConversationPrompts.interviewProgressNote(for: config, candidateTurns: index + 1) ?? ""
            let history: [(role: ChatRole, content: String)] = [
                (.assistant, "Guten Tag! Schön, dass Sie da sind. Stellen Sie sich bitte kurz vor."),
                (.user, "Guten Tag. Gern: " + String(resume.kurzprofil.prefix(160))),
            ]
            let question = (try? await mlxService.streamChatReply(history: history, system: system + "\n\n" + note,
                                                                   model: model, maxTokens: 160, temperature: 0.7) { _ in }) ?? ""
            let fact = ResumePrompts.bestFact(for: point, facts: config.resumeFacts)
            rows.append((point: point, fact: fact, question: question,
                         used: fact.map { ResumeProbe.factUsed(question: question, fact: $0) } ?? false,
                         inventions: ResumeProbe.possibleInventions(question: question, known: known + " " + system)))
        }
    }
}
