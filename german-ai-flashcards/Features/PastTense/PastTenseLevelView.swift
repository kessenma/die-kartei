import SwiftUI
import SwiftData

struct PastTenseLevelView: View {
    let level: PastTenseLevel
    var onStartStudy: (_ cards: [VocabCard], _ topic: String, _ style: FlashcardStyle, _ subDeckLabel: String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filter: PastTenseFilter = .all
    @State private var cardCount = 20
    @State private var selectedStyle: FlashcardStyle = .default
    @State private var showingGuide = false
    @State private var allEntries: [PastTenseVerbEntry] = []
    @State private var isLoading = true

    private let cardCountOptions = [10, 20, 30, 50]

    private var filteredEntries: [PastTenseVerbEntry] {
        allEntries.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.infinitive.localizedCaseInsensitiveContains(searchText) ||
                entry.translation.localizedCaseInsensitiveContains(searchText) ||
                entry.pastParticiple.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .sein: matchesFilter = entry.auxiliary == "sein"
            case .haben: matchesFilter = entry.auxiliary == "haben"
            case .separable: matchesFilter = entry.isSeparable
            case .irregular: matchesFilter = !entry.isRegular
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            } else {
                studySection
                verbListSection
            }
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .searchable(text: $searchText, prompt: "Search verbs or translations")
        .navigationTitle("\(level.rawValue) Past Tense")
        .navigationBarTitleDisplayMode(.large)
        .task {
            let entries = PastTenseVerbService.entries(for: level)
            allEntries = entries
            isLoading = false
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingGuide = true
                } label: {
                    Image(systemName: "book.closed")
                }
            }
        }
        .sheet(isPresented: $showingGuide) {
            SeinHabenGuideView()
        }
    }

    @ViewBuilder
    private var studySection: some View {
        Section {
            Picker("Filter", selection: $filter) {
                ForEach(PastTenseFilter.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            Picker("Cards to study", selection: $cardCount) {
                ForEach(cardCountOptions, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
                Text("All (\(filteredEntries.count))").tag(filteredEntries.count)
            }

            Picker("Study mode", selection: $selectedStyle) {
                ForEach(FlashcardStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            Button(action: startStudy) {
                Label("Study \(min(cardCount, filteredEntries.count)) Verbs", systemImage: "rectangle.stack.fill")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(filteredEntries.isEmpty)
        } header: {
            HStack {
                Text("Study")
                Spacer()
                Text("\(filteredEntries.count) verbs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Front shows infinitive · Back reveals auxiliary (sein/haben), past participle, and example sentence.")
        }
    }

    @ViewBuilder
    private var verbListSection: some View {
        Section("Verb List") {
            ForEach(filteredEntries) { entry in
                PastTenseVerbRow(entry: entry)
            }
        }
    }

    private func startStudy() {
        let pool = filteredEntries.shuffled().prefix(cardCount)
        let cards = PastTenseVerbService.toVocabCards(Array(pool))
        guard !cards.isEmpty else { return }
        let filterSuffix = filter == .all ? "" : " · \(filter.label)"
        let label = "\(cards.count) verbs\(filterSuffix)"
        onStartStudy(cards, "\(level.rawValue) Past Tense Verbs", selectedStyle, label)
    }
}

private struct PastTenseVerbRow: View {
    let entry: PastTenseVerbEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.infinitive)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("→ \(entry.pastParticiple)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                auxiliaryBadge
            }

            HStack(spacing: 6) {
                Text(entry.translation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if entry.isSeparable {
                    let label = entry.prefix.map { "\($0)-" } ?? "trennbar"
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(Capsule().stroke(Color.orange.opacity(0.5), lineWidth: 1))
                }

                if !entry.isRegular {
                    Text("unreg.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(Capsule().stroke(Color.red.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var auxiliaryBadge: some View {
        Text(entry.auxiliary)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(entry.auxiliary == "sein" ? Color.green : Color.blue, in: Capsule())
    }
}

enum PastTenseFilter: CaseIterable {
    case all, sein, haben, separable, irregular

    var label: String {
        switch self {
        case .all: return "All"
        case .sein: return "sein"
        case .haben: return "haben"
        case .separable: return "Trennbar"
        case .irregular: return "Unreg."
        }
    }
}
