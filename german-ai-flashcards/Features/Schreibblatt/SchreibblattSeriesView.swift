//
//  SchreibblattSeriesView.swift
//  german-ai-flashcards
//
//  A set of parts (a big selection split into sheets, `SchreibblattParts`): how far through it the
//  learner is, the part to write next, every part, and the words written so far as flashcards.
//  The hub lists a set as one row that opens this.
//
//  The sheets come from the hub's kind of `@Query` (every sheet, unfiltered) narrowed in memory,
//  so a part finished on its own screen shows here on the way back.
//

import SwiftData
import SwiftUI

struct SchreibblattSeriesView: View {
    let seriesID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(ActivityRouter.self) private var router: ActivityRouter?
    @Query private var sheets: [SchreibblattSheet]
    @State private var opened: SchreibblattSheet?
    /// Cards that still exist among the set's words, read on appear.
    @State private var existing: Set<UUID> = []

    private var parts: [SchreibblattSheet] {
        sheets.filter { $0.seriesID == seriesID }.sorted { $0.partIndex < $1.partIndex }
    }

    var body: some View {
        let parts = parts
        let done = parts.filter(\.isFinished)
        let facts = parts.map {
            SchreibblattParts.Part(index: $0.partIndex,
                                   wordIDs: $0.writtenWords.map(\.id).filter(existing.contains),
                                   isFinished: $0.isFinished)
        }
        let next = SchreibblattParts.nextPart(parts: facts, after: -1)
            .flatMap { index in parts.first { $0.partIndex == index } }
        let options = done.last.map { SchreibblattParts.practiceOptions(parts: facts, current: $0.partIndex) } ?? []

        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(done.reduce(0) { $0 + $1.writtenWords.count }) of \(parts.reduce(0) { $0 + $1.writtenWords.count }) words written · \(done.count) of \(parts.count) parts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: parts.isEmpty ? 0 : Double(done.count) / Double(parts.count))
                        .tint(SchreibblattTile.tint)
                        .accessibilityLabel("Parts done")
                }
                .padding(.vertical, 4)
                if let next {
                    Button {
                        opened = next
                    } label: {
                        Label(next.strokeCount > 0 ? "Weiter: \(next.partLabel)" : "Schreiben: \(next.partLabel)",
                              systemImage: "arrow.right.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SchreibblattTile.tint)
                    }
                } else if !parts.isEmpty {
                    Label("Alle Teile fertig", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Fortschritt · Progress").themedSectionHeader()
            }
            .themedListRow()

            if router != nil, !options.isEmpty {
                Section {
                    ForEach(options) { option in
                        Button {
                            practice(option)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(option.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "rectangle.on.rectangle.angled")
                                    .foregroundStyle(SchreibblattTile.tint)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Karten üben · Practice").themedSectionHeader()
                } footer: {
                    Text("From the parts you've finished. Only these words go into the flashcards.")
                }
                .themedListRow()
            }

            Section {
                ForEach(parts) { part in
                    NavigationLink {
                        SchreibblattSheetView(sheet: part)
                    } label: {
                        partRow(part)
                    }
                }
            } header: {
                Text("Teile · Parts").themedSectionHeader()
            } footer: {
                Text("Sheets and what you wrote on them stay on this device.")
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle(parts.first?.seriesTitle ?? "Schreibblatt")
        .navigationDestination(item: $opened) { SchreibblattSheetView(sheet: $0) }
        .onAppear {
            existing = DeckStore(modelContext: modelContext)
                .existingCardIDs(parts.flatMap { $0.writtenWords.map(\.id) })
        }
    }

    private func partRow(_ part: SchreibblattSheet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(part.partLabel).font(.body.weight(.medium))
            Text(part.writtenWords.map { ArticleGameService.bareNoun($0.german) }.formatted(.list(type: .and)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(part.summary)
                if let finishedAt = part.finishedAt {
                    Text("·")
                    Label("Fertig \(finishedAt.formatted(.dateTime.day().month(.abbreviated)))",
                          systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                } else if part.strokeCount > 0 {
                    Text("·")
                    Label("begonnen", systemImage: "hand.draw")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func practice(_ option: SchreibblattParts.PracticeOption) {
        guard let router,
              let session = DeckStore(modelContext: modelContext).practiceSession(
                  cardIDs: option.wordIDs,
                  topic: parts.first?.seriesTitle ?? "Schreibblatt",
                  label: "Schreibblatt · \(SchreibblattParts.words(option.wordIDs.count))")
        else { return }
        router.launch(.cardDeck(session))
    }
}
