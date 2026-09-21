//
//  CardSettingsSheet.swift
//  german-ai-flashcards
//
//  Settings ▸ Cards, presented as a sheet from inside the player: the deck's setup screen and the
//  in-session menu both open it, so a learner can change the front side, the gender quiz, or the
//  Wortschatz budget without leaving the cards they are on.
//

import SwiftUI

struct CardSettingsSheet: View {
    @Bindable var modelManager: MLXModelManager

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                CardSettingsView(modelManager: modelManager)
            }
            .themedListScreen()
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
