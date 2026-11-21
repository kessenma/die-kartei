//
//  HangmanSetupView.swift
//  german-ai-flashcards
//
//  Galgenmännchen's wrapper around the shared `GameSetupView`: the motif, the clue, and whether to
//  offer a hint. Everything about picking a source lives in the shared screen.
//

import SwiftUI

struct HangmanSetupView: View {
    var modelManager: MLXModelManager

    @Environment(ActivityRouter.self) private var router
    @Environment(\.appTheme) private var appTheme

    @AppStorage("spiele.hangman.motif") private var motifRaw = HangmanMotif.default.rawValue
    @AppStorage("spiele.hangman.clue") private var clueRaw = HangmanClue.Mode.pictureFirst.rawValue
    @AppStorage("spiele.hangman.wantsHint") private var wantsHint = false

    private var motif: HangmanMotif { HangmanMotif(rawValue: motifRaw) ?? .default }
    private var clueMode: HangmanClue.Mode { HangmanClue.Mode(rawValue: clueRaw) ?? .pictureFirst }

    /// The hint is written by the tutor, so it is only offered when one is actually on the device.
    private var canHint: Bool { ModelReadiness.current.satisfies(.germanTutor) }

    var body: some View {
        GameSetupView(kind: .hangman) {
            Picker("Motiv", selection: $motifRaw) {
                ForEach(HangmanMotif.allCases) { motif in
                    Text(motif.germanTitle).tag(motif.rawValue)
                }
            }
            Text(motif.blurb)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Hinweis", selection: $clueRaw) {
                ForEach(HangmanClue.Mode.allCases) { mode in
                    Text(mode.germanTitle).tag(mode.rawValue)
                }
            }

            if canHint {
                Toggle("Tipp vom Tutor · Tutor hint", isOn: $wantsHint)
                Text("Asks the tutor for a clue in German. It never contains the word itself.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } start: { pool in
            router.launch(.hangman(HangmanSession(
                words: pool.words,
                topic: pool.label,
                deckID: pool.deckID,
                generatorRaw: pool.generatorRaw,
                motif: motif,
                clueMode: clueMode,
                allowsHint: wantsHint && canHint,
                toppedUp: pool.toppedUp
            )))
        }
    }
}
