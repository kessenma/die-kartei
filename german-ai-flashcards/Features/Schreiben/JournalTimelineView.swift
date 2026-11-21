//
//  JournalTimelineView.swift
//  german-ai-flashcards
//
//  Every entry, newest first, by month. The rows read only scalar fields off the row (title,
//  first line, counts), never the ink, so listing never opens a file.
//

import SwiftData
import SwiftUI

struct JournalTimelineView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\JournalEntry.day, order: .reverse),
                  SortDescriptor(\JournalEntry.updatedAt, order: .reverse)])
    private var entries: [JournalEntry]

    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all, tagebuch, aufsatz
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "Alle"
            case .tagebuch: "Tagebuch"
            case .aufsatz: "Aufsatz"
            }
        }
    }

    private var shown: [JournalEntry] {
        switch filter {
        case .all: entries
        case .tagebuch: entries.filter { $0.kind == .tagebuch }
        case .aufsatz: entries.filter { $0.kind == .aufsatz }
        }
    }

    /// (month label, entries) newest month first.
    private var months: [(label: String, entries: [JournalEntry])] {
        let cal = Calendar.current
        var order: [DateComponents] = []
        var groups: [DateComponents: [JournalEntry]] = [:]
        for entry in shown {
            let key = cal.dateComponents([.year, .month], from: entry.day)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        return order.map { key in
            let date = cal.date(from: key) ?? .now
            return (label: date.formatted(.dateTime.month(.wide).year()), entries: groups[key] ?? [])
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { f in Text(f.label).tag(f) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if shown.isEmpty {
                Section {
                    ContentUnavailableView("Noch nichts geschrieben", systemImage: "square.and.pencil",
                                           description: Text("Your entries and essays will be listed here, month by month."))
                }
                .listRowBackground(Color.clear)
            }

            ForEach(months, id: \.label) { month in
                Section {
                    ForEach(month.entries) { entry in
                        NavigationLink {
                            JournalEntryView(entry: entry, modelManager: modelManager, mlxService: mlxService)
                        } label: {
                            JournalEntryRow(entry: entry)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { JournalEntryStore.delete(month.entries[index], in: modelContext) }
                    }
                } header: {
                    Text(month.label).themedSectionHeader()
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Alle Einträge")
    }
}

// MARK: - Row

/// One entry in a list: kind, title or first line, date, and what has happened to it.
struct JournalEntryRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .font(.title3)
                .foregroundStyle(SchreibenTile.tint)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.dateLine)
                    Text("·")
                    Text("\(entry.wordCount) \(entry.wordCount == 1 ? "word" : "words")")
                    if entry.hasInk {
                        Image(systemName: "pencil.tip").accessibilityLabel("Handwritten")
                    }
                    if entry.hasCheck {
                        Image(systemName: entry.checkIsStale ? "checkmark.circle.trianglebadge.exclamationmark" : "checkmark.circle")
                            .accessibilityLabel(entry.checkIsStale ? "Checked, edited since" : "Checked")
                    }
                    if entry.sharedWithCoachAt != nil {
                        Image(systemName: "person.crop.circle.badge.checkmark").accessibilityLabel("Shared with the coach")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
