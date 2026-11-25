//
//  VerbSceneGalleryView.swift
//  german-ai-flashcards
//
//  Verb-Szenen: every verb pair's 3D scene, one per page, with a Frage/Antwort switch, so the
//  39 verb scenes can be judged on the phone without playing a round to reach each one. Frage
//  is the question side (the key pose, clips held); Antwort is the reveal (clips playing). The
//  question side is the one still unchecked on a device (docs/VERB_PREPOSITIONS.md).
//
//  The same arrangement as `PrepositionSceneGalleryView`: ONE canvas above the pager, re-posed
//  per page, never a canvas per page (PREPOSITION_3D.md, "One RealityKit canvas per screen").
//  Reached from the preposition hub's „In Arbeit“ section.
//

import SwiftUI

struct VerbSceneGalleryView: View {
    @Environment(\.appTheme) private var appTheme

    @State private var index = 0
    @State private var showsAnswer = true
    /// Restarts the current scene's clock, no view identity change involved.
    @State private var replay = 0

    /// Class-sheet order: the Akkusativ pairs, then the Dativ ones.
    private let pairs = VerbPrepositionService.all()

    /// Pairs by scene, for the "shared with" line: 42 pairs act in 39 scenes.
    private let pairsByScene = Dictionary(grouping: VerbPrepositionService.all(), by: \.scene)

    private var current: VerbPreposition? {
        pairs.indices.contains(index) ? pairs[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Side", selection: $showsAnswer) {
                Text("Frage").tag(false)
                Text("Antwort").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let pair = current {
                PrepositionSceneView(
                    word: pair.sceneKey,
                    mode: showsAnswer ? .resolved(pair.governs) : .neutral,
                    restartToken: replay
                )
                .frame(height: 280)
                .padding(.horizontal)
            }

            TabView(selection: $index) {
                ForEach(Array(pairs.enumerated()), id: \.element.verb) { position, pair in
                    pairCard(pair)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pager
        }
        .background {
            ThemedBackground().ignoresSafeArea()
        }
        .navigationTitle("Verb-Szenen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(Array(pairs.enumerated()), id: \.element.verb) { position, pair in
                        Button(pair.verb) { index = position }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Jump to a pair")

                Button {
                    replay += 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Replay animation")
            }
        }
    }

    // MARK: - One pair (text only; the scene lives above the pager)

    private func pairCard(_ pair: VerbPreposition) -> some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            Text(showsAnswer ? pair.verb : pair.gappedVerb)
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(showsAnswer ? pair.governs.color : .primary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(pair.english)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                if showsAnswer {
                    Text(pair.answerLine)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(pair.governs.color, in: appTheme.pillShape)
                }
                // Which scene is playing: this screen exists to tune them.
                Text(pair.scene)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)

            if let shared = sharedLine(pair) {
                Text(shared)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let example = pair.example {
                VStack(spacing: 4) {
                    Text(showsAnswer ? example.german : example.blanked)
                        .font(.body)
                        .multilineTextAlignment(.center)
                    Text(example.english)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    private func sharedLine(_ pair: VerbPreposition) -> String? {
        let others = (pairsByScene[pair.scene] ?? []).filter { $0.verb != pair.verb }.map(\.verb)
        return others.isEmpty ? nil : "Same scene as " + others.joined(separator: ", ")
    }

    // MARK: - Pager

    private var pager: some View {
        HStack {
            Button {
                withAnimation { index = max(0, index - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .disabled(index == 0)

            Spacer()

            Text("\(min(index + 1, pairs.count)) / \(pairs.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation { index = min(pairs.count - 1, index + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .disabled(index >= pairs.count - 1)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

#Preview {
    NavigationStack {
        VerbSceneGalleryView()
    }
}
