//
//  PrepositionRenderTestView.swift
//  german-ai-flashcards
//
//  The animation gallery: every preposition that has a 3D scene, playing its resolved
//  choreography live over the word and its English.
//
//  ONE RealityKit canvas for the whole gallery, sitting above the pager — the same rule the
//  preposition card deck follows, and for the same reason. A scene inside each page means a
//  render context per page: the pager pre-instantiates neighbors, partial swipes cancel and
//  restart their load tasks (visible as blinking), and the contexts accumulate until iOS
//  throttles rendering and every animation stops. The single canvas swaps meshes in place via
//  `PrepositionSceneView`'s task(id: asset); only the text rides the TabView.
//
//  Still a tuning surface more than a shipping one (reachable from the bottom of the
//  preposition hub): it exists so motion timings can be judged on device, word by word.
//  The replay button restarts the current scene's clock via `restartToken`.
//

import SwiftUI

struct PrepositionSceneGalleryView: View {
    @Environment(\.appTheme) private var appTheme

    @State private var index = 0
    /// Restarts the current scene's choreography clock — no view identity change involved.
    @State private var replay = 0

    /// Every word with a scene, formal ones included — this screen is for judging all of them.
    private let preps: [Preposition] = PrepositionService
        .prepositions(includeAdvanced: true)
        .filter { PrepositionScene.exists(for: $0.word) }

    private var current: Preposition? {
        preps.indices.contains(index) ? preps[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // The one live canvas. Swiping changes `word`, which swaps geometry under the
            // same camera, lights, and render context.
            if let prep = current {
                PrepositionSceneView(
                    word: prep.word,
                    mode: .resolved(prep.governs),
                    loops: prep.governs == .wechsel,
                    restartToken: replay
                )
                .frame(height: 280)
                .padding(.horizontal)
            }

            TabView(selection: $index) {
                ForEach(Array(preps.enumerated()), id: \.element.word) { position, prep in
                    wordCard(prep)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pager
        }
        .background {
            ThemedBackground().ignoresSafeArea()
        }
        .navigationTitle("Animation Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    replay += 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Replay animation")
            }
        }
    }

    // MARK: - One word (text only — the scene lives above the pager)

    private func wordCard(_ prep: Preposition) -> some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            Text(prep.word)
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(prep.governs.color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(prep.meaningLine)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Text(prep.governs.germanLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(prep.governs.color, in: appTheme.pillShape)

                // Which choreography is playing — this screen exists to tune them.
                Text(motionLabel(prep.word))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 4)

            // The sentence(s) the scene is acting out: one per case for a two-way word —
            // the same selection the drill reveal shows.
            VStack(spacing: 8) {
                PrepositionExampleRows(examples: prep.revealExamples(), governs: prep.governs)
            }
            .padding(.top, 10)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    /// The scene's motion kind, straight from the manifest. Two-way relations have no spec —
    /// they animate by traveling between their two authored poses.
    private func motionLabel(_ word: String) -> String {
        PrepositionScene.pose(for: word)?.motion?.kind ?? "travel"
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

            Text("\(min(index + 1, preps.count)) / \(preps.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation { index = min(preps.count - 1, index + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .disabled(index >= preps.count - 1)
        }
        .padding(.horizontal, 24)
        // Clears the app's floating tab bar — same convention as the preposition cards pager.
        .padding(.bottom, 100)
    }
}

#Preview {
    NavigationStack {
        PrepositionSceneGalleryView()
    }
}
