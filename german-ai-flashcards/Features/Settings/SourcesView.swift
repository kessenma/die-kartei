import SwiftUI

struct SourcesView: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        List {
            // MARK: - Goethe-Institut Word Lists
            Section {
                HStack(spacing: 12) {
                    Image("logo-goethe")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))

                    Text(
                        "The A1, A2, and B1 vocabulary decks are built from the official word lists published by the Goethe-Institut for their German language certification exams. These lists define the vocabulary expected at each CEFR level."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                levelRow(
                    level: "A1",
                    exam: "Start Deutsch 1",
                    wordCount: "~585 words",
                    url: URL(string: "https://www.goethe.de/pro/relaunch/prf/de/A1_SD1_Wortliste_02.pdf")!
                )
                levelRow(
                    level: "A2",
                    exam: "Goethe-Zertifikat A2",
                    wordCount: "~1,200 words",
                    url: URL(string: "https://www.goethe.de/pro/relaunch/prf/de/Goethe-Zertifikat_A2_Wortliste.pdf")!
                )
                levelRow(
                    level: "B1",
                    exam: "Goethe-Zertifikat B1",
                    wordCount: "~2,300 words",
                    url: URL(string: "https://www.goethe.de/pro/relaunch/prf/de/Goethe-Zertifikat_B1_Wortliste.pdf")!
                )
            } header: {
                Text("Goethe-Institut Word Lists")
                    .themedSectionHeader()
            }
            .themedListRow()

            // MARK: - Wortkiste
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)

                    Text(
                        "The plural and Perfekt forms on Goethe cards, and the due-today word box behind the Wortschatz screen, follow Wortkiste, an open-source word box for the same exams by matchaDataHub, released under the MIT license."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://github.com/matchaDataHub/wortkiste")!) {
                    Label("Wortkiste on GitHub", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
            } header: {
                Text("Wortkiste")
                    .themedSectionHeader()
            }
            .themedListRow()

            // MARK: - Wiktionary / Kaikki
            Section {
                HStack(spacing: 12) {
                    Image("logo-wiktionary")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))

                    Text(
                        "AI-generated flashcards are validated against a dictionary derived from Wiktionary data. The raw data is provided by Kaikki.org and processed into a compact SQLite database bundled with the app. Gender, part of speech, and English translations are cross-checked after each generation."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://kaikki.org/dictionary/German/index.html")!) {
                    Label("German Wiktionary data on Kaikki.org", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Academic Citation")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Text(
                        "Tatu Ylonen: Wiktextract: Wiktionary as Machine-Readable Structured Data, Proceedings of the 13th Conference on Language Resources and Evaluation (LREC), pp. 1317–1325, Marseille, 20–25 June 2022."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Wiktionary (via Kaikki.org / Wiktextract)")
                    .themedSectionHeader()
            }
            .themedListRow()

            // MARK: - Correcting Issues
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                        .frame(width: 40, height: 40)

                    Text(
                        "Validation badges appear below each card when the app detects a potential issue. An orange \"Should be…\" badge means the article may be wrong; a grey \"Not in dictionary\" badge means the word wasn't found in the Wiktionary data."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Tap any orange or grey badge on a card to open the correction sheet.", systemImage: "hand.tap")
                        .font(.footnote)
                    Label("On the setup screen, tap \"Fix Issues\" to correct all flagged cards before you start.", systemImage: "list.bullet.clipboard")
                        .font(.footnote)
                    Label("Once corrected, the badge turns green and the new article is saved to the deck.", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Correcting Validation Issues", systemImage: "pencil.circle")
                    .themedSectionHeader()
            } footer: {
                Text("Corrections are saved immediately. Re-opening the deck from the library will show the updated articles.")
            }
            .themedListRow()

            // MARK: - AI Generation
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Flashcards are generated on your device by models fine-tuned for this app: two built on Google's Gemma 4, two on IBM's Granite. Both base families are open-weight. They run through MLX, an open-source framework by Apple machine learning research to run machine learning models locally on Apple devices. On supported iPhones you can use Apple's built-in on-device model instead."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .imageScale(.small)
                        Text("MLX open-source models — downloaded and run locally")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://opensource.apple.com/projects/mlx")!) {
                        Label("MLX Swift package documentation", systemImage: "arrow.up.right.square")
                            .font(.footnote)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("AI-Generated Content", systemImage: "sparkles")
                    .themedSectionHeader()
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Sources")
        .contentMargins(.bottom, 120, for: .scrollContent)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func levelRow(level: String, exam: String, wordCount: String, url: URL) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(level)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(5)))
                .foregroundStyle(.tint)
                .frame(width: 40, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(exam)
                    .font(.footnote)
                Link(destination: url) {
                    Label("PDF word list", systemImage: "arrow.up.right.square")
                        .font(.caption2)
                }
                Text(wordCount)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SourcesView()
    }
}
