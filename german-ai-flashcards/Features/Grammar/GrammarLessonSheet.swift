//
//  GrammarLessonSheet.swift
//  german-ai-flashcards
//
//  A 30-second explanation for a grammar structure — the just-in-time mini-lesson.
//  Presented from the Today plan and the Grammar hub for weak spots that have no
//  ready-made drill; reuses `GrammarFocus.explanation`.
//

import SwiftUI

struct GrammarLessonSheet: View {
    let focus: GrammarFocus

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focus.germanLabel)
                            .font(.title2.weight(.bold))
                        Text(focus.englishLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(focus.explanation)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("Try to use it in your next conversation — the coach is watching for it.", systemImage: "lightbulb")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Quick lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
