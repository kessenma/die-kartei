//
//  KasusAIStorySection.swift
//  german-ai-flashcards
//
//  „Deine KI-Geschichten · Your AI stories“ on a unit screen (Phase 3): the „Neue Geschichte ·
//  New story (KI)“ row, then the unit's tutor-written stories, newest first, each played like a
//  bundled story and deleted with a swipe (its rounds stay in Verlauf).
//
//  The row follows `KasusStoryGenerator.availability`:
//
//    hidden          the developer toggle is off (Settings ▸ Developer): no row, and no section
//                    unless stories written earlier are still there (they stay playable and
//                    deletable)
//    ready           the row, naming the tutor that will write
//    needsDownload   the download state, pointing at Settings ▸ Model (never a tutor the device
//                    can't run)
//    tooSmall        a quiet line: even the lightest tutor needs more memory than this device has
//
//  The unit screen owns the generation sheet; this section only asks for it (`onNewStory`).
//

import SwiftUI
import SwiftData

struct KasusAIStorySection: View {
    let unit: KasusUnit
    let availability: KasusGenerationAvailability
    /// Stands in for the tutor's name on the row: the DEBUG canned writer.
    var tutorLabel: String? = nil
    let progress: KasusProgress
    /// A tutor download (or load) is under way.
    var isDownloading = false
    var onNewStory: () -> Void
    /// Settings ▸ Model, for the download state. Nil where there is no settings router.
    var onGetTutor: (() -> Void)? = nil

    @Environment(ActivityRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query private var stories: [GeneratedKasusStory]
    @State private var pendingDelete: GeneratedKasusStory?

    init(unit: KasusUnit, availability: KasusGenerationAvailability, tutorLabel: String? = nil,
         progress: KasusProgress, isDownloading: Bool = false,
         onNewStory: @escaping () -> Void, onGetTutor: (() -> Void)? = nil) {
        self.unit = unit
        self.availability = availability
        self.tutorLabel = tutorLabel
        self.progress = progress
        self.isDownloading = isDownloading
        self.onNewStory = onNewStory
        self.onGetTutor = onGetTutor
        let raw = unit.rawValue
        _stories = Query(filter: #Predicate<GeneratedKasusStory> { $0.unitRaw == raw },
                         sort: \.date, order: .reverse)
    }

    var body: some View {
        if availability != .hidden || !stories.isEmpty {
            Section {
                newStoryRow
                ForEach(stories) { row in
                    storyRow(row)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = row
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = row
                            } label: {
                                Label("Löschen · Delete", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("Deine KI-Geschichten · Your AI stories")
                    .themedSectionHeader()
            } footer: {
                if availability != .hidden {
                    Text("The tutor writes around phrases the app picked, and the app checks every answer it grades before you see the story. A story that fails the check is never shown. The tutor can still write an odd sentence now and then.")
                }
            }
            .themedListRow()
            .confirmationDialog(
                "Diese Geschichte löschen?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { row in
                Button("Löschen · Delete", role: .destructive) {
                    KasusStoryStore.delete(row, in: modelContext)
                    pendingDelete = nil
                }
                Button("Abbrechen", role: .cancel) { pendingDelete = nil }
            } message: { row in
                Text("„\(row.title)“ goes away. Your rounds on it stay in Verlauf.")
            }
        }
    }

    // MARK: - Neue Geschichte

    @ViewBuilder
    private var newStoryRow: some View {
        switch availability {
        case .hidden:
            EmptyView()
        case .ready(let model):
            Button(action: onNewStory) {
                rowLabel(
                    symbol: "wand.and.sparkles",
                    active: true,
                    subtitle: "\(tutorLabel ?? KasusGenerationCopy.shortName(model)) writes it, the app checks every answer",
                    trailing: Image(systemName: "plus.circle.fill")
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a sheet while the tutor writes a new story")
        case .needsDownload(let model):
            if isDownloading {
                HStack(spacing: 12) {
                    icon("wand.and.sparkles", active: false)
                    VStack(alignment: .leading, spacing: 4) {
                        title(active: false)
                        Text("Your tutor is loading. The row turns on when it's ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            } else if let onGetTutor {
                Button(action: onGetTutor) {
                    rowLabel(
                        symbol: "wand.and.sparkles",
                        active: false,
                        subtitle: "Needs a German tutor: \(KasusGenerationCopy.shortName(model)), one download of ~\(model.approximateSizeLabel). Tap to get it.",
                        trailing: Image(systemName: "arrow.down.circle")
                    )
                }
                .buttonStyle(.plain)
            } else {
                rowLabel(
                    symbol: "wand.and.sparkles",
                    active: false,
                    subtitle: "Needs a German tutor: \(KasusGenerationCopy.shortName(model)), one download of ~\(model.approximateSizeLabel) in Settings ▸ Model.",
                    trailing: nil
                )
            }
        case .tooSmall:
            rowLabel(
                symbol: "wand.and.sparkles",
                active: false,
                subtitle: "Writing a story takes a German tutor, and even the lightest needs more memory than this device gives an app. The stories above work as usual.",
                trailing: nil
            )
        }
    }

    private func title(active: Bool) -> some View {
        Text("Neue Geschichte · New story (KI)")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(active ? .primary : .secondary)
    }

    private func icon(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: 34, height: 34)
            .background(active ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(Color.secondary.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
    }

    private func rowLabel(symbol: String, active: Bool, subtitle: String, trailing: Image?) -> some View {
        HStack(spacing: 12) {
            icon(symbol, active: active)
            VStack(alignment: .leading, spacing: 2) {
                title(active: active)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let trailing {
                trailing
                    .font(.title3)
                    .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - The stories

    private func storyRow(_ row: GeneratedKasusStory) -> some View {
        let found = progress.isDone(storyID: row.id, unit: unit, step: .find)
        let filled = progress.isDone(storyID: row.id, unit: unit, step: .fill)
        let story = row.story
        return Button {
            guard let story else { return }
            // Pick up where it was left, like a bundled story: Endungen once Markieren is done.
            let start: KasusStep = found && !filled ? .einsetzen : .lesen
            router.launch(.kasusStory(KasusSession(generated: story, unit: unit, startStep: start)))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.pages")
                    .font(.title3)
                    .foregroundStyle(unit.color)
                    .frame(width: 34, height: 34)
                    .background(unit.color.opacity(0.12), in: RoundedRectangle(cornerRadius: appTheme.innerRadius(8), style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(unit.color)
                            .offset(x: 3, y: 3)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("„\(row.title)“")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    if story == nil {
                        Text("This story can't be read any more.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(row.level) · Markieren \(stepMark(found)) · Endungen \(stepMark(filled))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(KasusGenerationCopy.tutorName(row.modelID)) · \(row.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(story == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(story == nil)
        .accessibilityLabel("\(row.title), written by the tutor, \(row.level). Markieren \(found ? "done" : "not yet"), Endungen \(filled ? "done" : "not yet").")
    }

    /// ✓ once the step has been played, ○ before.
    private func stepMark(_ done: Bool) -> Image {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private enum KasusAIStoryPreview {
    /// An in-memory store with one generated Dativ story (the good fixture, checked for real).
    static func container() -> ModelContainer {
        let container = try! ModelContainer(
            for: GeneratedKasusStory.self, KasusRound.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let plan = KasusGenerationFixtures.plan(for: .dativ)
        let check = KasusStoryCheck.run(raw: KasusGenerationFixtures.output(for: .dativ, .good), plan: plan)
        if let story = check.story {
            let encoder = JSONEncoder()
            container.mainContext.insert(GeneratedKasusStory(
                id: story.id, unitRaw: story.unitRaw, level: story.level,
                modelID: MLXModel.gemma4_E4B_german.rawValue, title: story.title,
                planData: try? encoder.encode(plan), storyData: try? encoder.encode(story),
                validatorSummary: check.summaryLine, attempts: 1, generationSeconds: 38
            ))
        }
        return container
    }
}

private func previewSection(_ availability: KasusGenerationAvailability) -> some View {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack {
                List {
                    KasusAIStorySection(unit: .dativ, availability: availability,
                                        progress: KasusProgress(rounds: []),
                                        onNewStory: {}, onGetTutor: {})
                }
                .themedListScreen()
            }
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .environment(ActivityRouter())
    .modelContainer(KasusAIStoryPreview.container())
}

#Preview("KI-Geschichten · ready · 4 themes") { previewSection(.ready(.gemma4_E4B_german)) }
#Preview("KI-Geschichten · download · 4 themes") { previewSection(.needsDownload(.gemma4_E2B_german)) }
#Preview("KI-Geschichten · too small · 4 themes") { previewSection(.tooSmall) }
#endif
