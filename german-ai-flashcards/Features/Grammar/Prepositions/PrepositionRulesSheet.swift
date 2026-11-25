//
//  PrepositionRulesSheet.swift
//  german-ai-flashcards
//
//  The preposition cheat sheet — the four case groups from `prepositions.json` laid out as a
//  scannable table, plus the Wohin/Wo test and every contraction in one place. Reachable from
//  the drill's info button and the hub, so help is one tap away exactly when a word stumps you.
//

import SwiftUI

struct PrepositionRulesSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let prepositions = PrepositionService.all()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A German preposition fixes the case of whatever follows it. Learn the preposition and its case together — that pairing is what the exercises drill.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .themedListRow()

                wechselTestSection

                ForEach(PrepositionCase.allCases) { group in
                    groupSection(group)
                }

                contractionSection

                Section {
                    Label(
                        "In everyday speech trotz, während, wegen and statt often take the Dativ — „wegen dem Wetter“. The Genitiv is what writing and exams expect.",
                        systemImage: "bubble.left.and.text.bubble.right"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .themedListRow()
            }
            .themedListScreen()
            .navigationTitle("Prepositions & cases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - The two-way test

    private var wechselTestSection: some View {
        Section {
            // The rule itself, not an example of it: a ball crossing an open plane, orange while
            // it travels and teal once it stops. Demoing with `in` taught one preposition — a
            // ball dropping into a box — where the two-way rule covers all ten. Nothing else is
            // in frame, so movement-vs-rest is the only thing to read.
            PrepositionSceneView(word: "wohinwo", mode: .resolved(.wechsel), loops: true)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())

            VStack(alignment: .leading, spacing: 10) {
                testRow(
                    question: "Wohin?",
                    answer: "Akkusativ",
                    example: "Ich gehe in die Stadt.",
                    gloss: "movement toward somewhere",
                    color: PrepositionCase.akkusativ.color
                )
                testRow(
                    question: "Wo?",
                    answer: "Dativ",
                    example: "Ich bin in der Stadt.",
                    gloss: "already somewhere",
                    color: PrepositionCase.dativ.color
                )
            }
            .padding(.vertical, 2)
        } header: {
            HStack(spacing: 8) {
                Circle()
                    .fill(PrepositionCase.wechsel.color)
                    .frame(width: 10, height: 10)
                Text("The two-way test")
            }
        } footer: {
            Text("Ask the question before you pick the article — it decides the case for all ten two-way prepositions.")
        }
        .themedListRow()
    }

    private func testRow(
        question: String, answer: String, example: String, gloss: String, color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(question)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("→ \(answer) · \(gloss)")
                    .font(.subheadline)
                Text("„\(example)“")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - One section per case group

    private func groupSection(_ group: PrepositionCase) -> some View {
        Section {
            ForEach(prepositions.filter { $0.governs == group }) { prep in
                prepositionRow(prep)
            }
        } header: {
            HStack(spacing: 8) {
                Circle()
                    .fill(group.color)
                    .frame(width: 10, height: 10)
                Text("\(group.germanLabel) — \(group.englishLabel)")
            }
        } footer: {
            Text(group.questionWord ?? group.articleLine)
        }
        .themedListRow()
    }

    private func prepositionRow(_ prep: Preposition) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(prep.word)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(prep.governs.color)
                Text(prep.meaningLine)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if prep.tier == .advanced {
                    Text("formal")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            if let example = prep.examples.first {
                Text("„\(example.german)“")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = prep.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Contractions

    private var contractionSection: some View {
        Section {
            ForEach(PrepositionService.allContractions(), id: \.contraction.short) { pair in
                HStack {
                    Text(pair.contraction.long)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("=")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(pair.contraction.short)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(pair.preposition.governs.color)
                    Spacer()
                }
            }
        } header: {
            Text("Contractions")
        } footer: {
            Text("ins, im, zum, zur, am and ans are the everyday ones — the rest sound casual and are usually left uncontracted in writing.")
        }
        .themedListRow()
    }
}

#Preview {
    PrepositionRulesSheet()
}
