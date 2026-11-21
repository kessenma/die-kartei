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

            #if os(macOS)
            // MARK: - Mac picture models (MAC-PICTURES)
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)

                    Text(
                        "On the Mac, pictures can be drawn with Z-Image Turbo by Tongyi Lab or FLUX.2 klein 4B by Black Forest Labs, both released under the Apache 2.0 license. They run through a picture engine adapted from turbo-mlx by Stefano Rinaldo, released under the MIT license."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://github.com/rinste/turbo-mlx")!) {
                    Label("turbo-mlx on GitHub", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
            } header: {
                Text("Picture Models on the Mac")
                    .themedSectionHeader()
            }
            .themedListRow()
            #endif

            // MARK: - How the cases are taught (KASUS Verstehen)
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)

                    Text(
                        "The Grammatik lessons teach the four cases the way research on English-speaking learners suggests: the role a phrase plays before its ending, English's own cases in its pronouns as the bridge, the Kasus-Check as the way to decide, and drills where only the ending says who does what (structured input, after VanPatten's Processing Instruction). Die Probe and „Gleich oder anders?“ are the German classroom's Ersatzprobe and Umstellprobe."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Academic Citations")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Text("Nick Henry, Hillah Culman, Bill VanPatten: More on the effects of explicit information in instructed SLA: A partial replication and a response to Fernández (2008). Studies in Second Language Acquisition 31(4), 2009.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Hillah Culman, Nick Henry, Bill VanPatten: The role of explicit information in instructed SLA: An on-line study with processing instruction and German accusative case inflections. Die Unterrichtspraxis / Teaching German 42(1), 2009.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Bill VanPatten: Input Processing and Grammar Instruction in Second Language Acquisition. Ablex, 1996.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                Link(destination: URL(string: "https://grammis.ids-mannheim.de/sgt/2218")!) {
                    Label("IDS grammis: case forms, sentence relationships and the replacement test", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
                Link(destination: URL(string: "https://grammis.ids-mannheim.de/progr@mm/6858")!) {
                    Label("IDS grammis: two-way prepositions, location and destination", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
                Link(destination: URL(string: "https://www.friedrich-verlag.de/friedrich-plus/sekundarstufe/deutsch/grammatik/kasus-verstehen-und-gebrauchen-16008")!) {
                    Label("Friedrich Verlag: Kasus verstehen und gebrauchen (the Satzproben)", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
                Link(destination: URL(string: "https://germanwithantrim.com/blog/german-question-words-for-people-wer-wen-wem-wessen")!) {
                    Label("Herr Antrim: wer, wen, wem, wessen", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
                Link(destination: URL(string: "https://www.clozemaster.com/blog/german-cases/")!) {
                    Label("Clozemaster: German cases, a complete guide", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
                Link(destination: URL(string: "https://www.lingoda.com/blog/en/dative-case-german/")!) {
                    Label("Lingoda: the Dativ and the “to” test", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
                Link(destination: URL(string: "https://angelikasgerman.co.uk/how-to-memorise-those-pesky-prepositions/")!) {
                    Label("Angelika's German: the preposition songs", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
            } header: {
                Text("Wie die Fälle erklärt werden · How the cases are taught")
                    .themedSectionHeader()
            }
            .themedListRow()

            // MARK: - How adults learn a language (FSI / DLI — docs/FSI_DLI_ROADMAP.md)
            // Says only what the app does today. Each roadmap item that ships adds its clause
            // and its citation here.
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)

                    Text(
                        "Two US government schools teach adults a language full time: the Foreign Service Institute for diplomats and the Defense Language Institute for the military. What they have published backs several habits of this app. Grammar is explained early, so a wrong ending doesn't settle in. Short drills repeat until the answer comes without thinking. Feedback names the slip, and the next practice is picked from what you got wrong. Listening is practised the way the Defense Language Institute tests it: numbers heard once and typed as digits, sentences written down from dictation with missed endings shown apart from missed words, and a story's gist told in your own words after guessing which words will come up. Some practice is meant to be easy: a quick round of cards you already know after a hard session, and longer stories a level below yours, because adults need plenty of easy material to get fast. Around a class, the app follows the DLI student handbook: preview the next lesson the day before, review what you learned the same day, prepare what you want to say, keep the corrections your teacher makes, and bring her your questions and a written report, since teacher and student share the work."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Citations")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Text("Frederick H. Jackson, Marsha A. Kaplan: Lessons learned from fifty years of theory and practice in government language teaching. In James E. Alatis, Ai-Hui Tan (eds.): Georgetown University Round Table on Languages and Linguistics 1999, pp. 71–87. Georgetown University Press, 2001.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Defense Language Institute Foreign Language Center: Student Handbook. Presidio of Monterey.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                Link(destination: URL(string: "https://www.dliflc.edu/dliflc_student_handbook_20170104")!) {
                    Label("DLI Foreign Language Center: Student Handbook (PDF)", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
            } header: {
                Text("Wie Erwachsene lernen · How adults learn a language")
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

            // MARK: - Tatoeba
            Section {
                Text(
                    "The Perfekt example sentences in the past-tense deck are real sentences written by native speakers, taken from the Tatoeba corpus rather than generated. Each one is checked to be a true Perfekt clause with the right auxiliary before it reaches a card. Hören ▸ Diktat reads them aloud too."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://tatoeba.org")!) {
                    Label("Tatoeba", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("License")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Text("Tatoeba sentence data is released under CC BY 2.0 FR.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text("Tatoeba")
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
