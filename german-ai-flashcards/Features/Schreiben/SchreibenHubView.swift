//
//  SchreibenHubView.swift
//  german-ai-flashcards
//
//  The Schreiben room: today's Tagebuch page, a new entry or essay, the last few things written,
//  and the way to all of them. The rows read scalars off the row, never the ink.
//

import SwiftData
import SwiftUI

struct SchreibenHubView: View {
    let modelManager: MLXModelManager
    let mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JournalEntry.updatedAt, order: .reverse) private var entries: [JournalEntry]

    @State private var opening: JournalEntry?
    @State private var pickingPrompt = false

    private var recent: [JournalEntry] { Array(entries.prefix(5)) }
    private var todayEntry: JournalEntry? {
        let start = Calendar.current.startOfDay(for: .now)
        return entries.first { $0.kind == .tagebuch && $0.day == start }
    }

    var body: some View {
        List {
            Section {
                Button {
                    opening = todayEntry ?? JournalEntryStore.make(kind: .tagebuch, level: modelManager.germanLevel, in: modelContext)
                } label: {
                    row(todayEntry == nil ? "Heute schreiben · Write today" : "Weiterschreiben · Continue today's page",
                        "A few lines about your day or your German, in German, English or both",
                        systemImage: "book.closed")
                }
                Button {
                    opening = JournalEntryStore.make(kind: .tagebuch, level: modelManager.germanLevel, in: modelContext)
                } label: {
                    row("Neuer Eintrag · New entry", "Another page for today", systemImage: "plus.circle")
                }
                Button {
                    pickingPrompt = true
                } label: {
                    row("Neuer Aufsatz · New essay", "Write to a prompt, then have the tutor check it sentence by sentence",
                        systemImage: "doc.text")
                }
            } header: {
                Text("Schreiben").themedSectionHeader()
            } footer: {
                Text("Writing is the slow kind of practice: your own words, your own mistakes. Type, or write with the Apple Pencil on the iPad.")
            }
            .themedListRow()

            if !recent.isEmpty {
                Section {
                    ForEach(recent) { entry in
                        NavigationLink {
                            JournalEntryView(entry: entry, modelManager: modelManager, mlxService: mlxService)
                        } label: {
                            JournalEntryRow(entry: entry)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { JournalEntryStore.delete(recent[index], in: modelContext) }
                    }
                } header: {
                    Text("Zuletzt · Recent").themedSectionHeader()
                }
                .themedListRow()
            }

            Section {
                NavigationLink {
                    JournalTimelineView(modelManager: modelManager, mlxService: mlxService)
                } label: {
                    Label(entries.isEmpty ? "Alle Einträge · All entries" : "Alle Einträge · All \(entries.count)",
                          systemImage: "calendar")
                }
            } footer: {
                Text("Entries and handwriting reach your other devices through iCloud Sync when it is on.")
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle(SchreibenTile.title)
        .navigationDestination(item: $opening) { entry in
            JournalEntryView(entry: entry, modelManager: modelManager, mlxService: mlxService)
        }
        .sheet(isPresented: $pickingPrompt) {
            JournalPromptPickerView(modelManager: modelManager, mlxService: mlxService) { entry in
                opening = entry
            }
        }
    }

    private func row(_ title: String, _ subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(SchreibenTile.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
