import SwiftUI
import SwiftData

/// "Coach's Notes" — a read-through of the persistent learner profile: what the coach thinks the
/// learner is strong/shaky on, the words they're building, the slip-ups it's watching, and the
/// archive of everything it has cleaned out (with restore / pin). Mirrors the on-device profile
/// that steers conversations; nothing here is sent anywhere.
struct CoachNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ActivityRouter.self) private var router
    @Query private var profiles: [LearnerProfile]
    @Query(sort: \ArchivedMemoryItem.archivedAt, order: .reverse) private var archived: [ArchivedMemoryItem]

    @State private var showResetConfirm = false

    private var profile: LearnerProfile? { profiles.first }

    private var grammarRows: [(focus: GrammarFocus, skill: GrammarSkill)] {
        guard let profile else { return [] }
        return profile.grammar
            .compactMap { key, skill in GrammarFocus(rawValue: key).map { (focus: $0, skill: skill) } }
            .sorted { $0.skill.struggle > $1.skill.struggle }
    }

    private var vocab: [VocabTouch] {
        (profile?.vocab ?? []).sorted { $0.lastSeen > $1.lastSeen }
    }
    private var slips: [LexicalSlip] {
        (profile?.slips ?? []).sorted { $0.timesSeen > $1.timesSeen }
    }
    /// Slips carrying enough context to become a fill-in-the-blank card (FUTURE #3).
    private var clozeSlips: [LexicalSlip] { slips.filter(\.isClozeReady) }

    private var isEmpty: Bool {
        (profile?.sessionCount ?? 0) == 0 && grammarRows.isEmpty && vocab.isEmpty && slips.isEmpty && archived.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                ContentUnavailableView(
                    "No coaching notes yet",
                    systemImage: "brain.head.profile",
                    description: Text("Have a conversation and end it — the coach will start noting what you're strong on, the words you're learning, and the slip-ups to watch.")
                )
            } else {
                List {
                    statsSection.themedListRow()
                    drillSection.themedListRow()
                    clozeSection.themedListRow()
                    grammarSection.themedListRow()
                    vocabSection.themedListRow()
                    slipsSection.themedListRow()
                    archiveSection.themedListRow()
                    resetSection.themedListRow()
                }
                .themedListScreen()
            }
        }
        .navigationTitle("Coach's Notes")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset coaching memory?", isPresented: $showResetConfirm) {
            Button("Reset everything", role: .destructive) {
                LearnerMemoryService.reset(in: modelContext)
                save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears everything the coach remembers about you — strengths, words, slip-ups, and the archive. It can't be undone.")
        }
    }

    // MARK: - Sections

    @ViewBuilder private var statsSection: some View {
        if let profile {
            Section {
                HStack {
                    stat("\(profile.sessionCount)", "Sessions coached")
                    Divider()
                    stat(lastPracticedLabel(profile.lastSessionAt), "Last practiced")
                }
                .padding(.vertical, 2)
            } footer: {
                Text("The coach quietly uses these notes to steer and sharpen your conversations. Everything stays on your device.")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder private var drillSection: some View {
        if !vocab.isEmpty || !slips.isEmpty {
            Section {
                NavigationLink {
                    DrillDeckView()
                } label: {
                    Label("Build a drill deck", systemImage: "rectangle.stack.badge.plus")
                }
            } footer: {
                Text("Turn your words and slip-ups into flashcards you can review with spaced repetition.")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder private var clozeSection: some View {
        if !clozeSlips.isEmpty {
            Section {
                Button {
                    router.launch(.cloze(ClozeSession.build(from: clozeSlips)))
                } label: {
                    Label("Fix your sentences", systemImage: "text.insert")
                }
            } footer: {
                Text("Fill-in-the-blank drills built from your own corrected sentences — retrieval practice on exactly the word that tripped you up. Get one right and it retires itself.")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder private var grammarSection: some View {
        if !grammarRows.isEmpty {
            Section {
                ForEach(grammarRows, id: \.focus) { row in
                    GrammarConfidenceRow(focus: row.focus, skill: row.skill)
                }
            } header: {
                Text("Grammar").themedSectionHeader()
            }
        }
    }

    @ViewBuilder private var vocabSection: some View {
        if !vocab.isEmpty {
            Section {
                ForEach(vocab) { item in
                    HStack(spacing: 8) {
                        if item.pinned {
                            Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                        }
                        Text(item.german).font(.callout)
                        Spacer()
                        if !item.english.isEmpty {
                            Text(item.english).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            LearnerMemoryService.setVocabPinned(item.id, pinned: !item.pinned, in: modelContext); save()
                        } label: {
                            Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            LearnerMemoryService.archiveVocab(id: item.id, in: modelContext); save()
                        } label: {
                            Label("Remove", systemImage: "archivebox")
                        }
                    }
                }
            } header: {
                Text("Words you're building").themedSectionHeader()
            } footer: {
                Text("Words the coach weaves back into future chats. Swipe to pin (never forgotten) or remove.")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder private var slipsSection: some View {
        if !slips.isEmpty {
            Section {
                ForEach(slips) { slip in
                    HStack(spacing: 8) {
                        if slip.pinned {
                            Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(slip.wrong).strikethrough().foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                Text(slip.right).foregroundStyle(.primary)
                            }
                            .font(.callout)
                            if !slip.note.isEmpty {
                                Text(slip.note).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if slip.timesSeen > 1 {
                            Text("×\(slip.timesSeen)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            LearnerMemoryService.setSlipPinned(slip.id, pinned: !slip.pinned, in: modelContext); save()
                        } label: {
                            Label(slip.pinned ? "Unpin" : "Pin", systemImage: slip.pinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            LearnerMemoryService.archiveSlipItem(id: slip.id, in: modelContext); save()
                        } label: {
                            Label("Remove", systemImage: "archivebox")
                        }
                    }
                }
            } header: {
                Text("Slip-ups it's watching").themedSectionHeader()
            } footer: {
                Text("Repeated word-level mistakes. The coach pays extra attention to these when correcting, and drops one automatically once you use it correctly.")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder private var archiveSection: some View {
        if !archived.isEmpty {
            Section {
                NavigationLink {
                    MemoryArchiveView()
                } label: {
                    Label("Archive", systemImage: "archivebox")
                        .badge(archived.count)
                }
            } footer: {
                Text("Notes the coach has cleaned out. You can review and restore any of them.")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset what the coach remembers", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func lastPracticedLabel(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.relative(presentation: .named))
    }

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - Grammar confidence row

private struct GrammarConfidenceRow: View {
    let focus: GrammarFocus
    let skill: GrammarSkill

    @Environment(ActivityRouter.self) private var router
    @State private var showLesson = false

    private var confidence: Double { max(0, min(1, 1 - skill.struggle)) }

    /// Shaky structures get a just-in-time mini-lesson: a 30-second explanation plus, when one
    /// exists, a one-tap drill — turning a diagnostic bar into something actionable (FUTURE #4).
    private var isShaky: Bool { skill.struggle >= GrammarSkill.shakyThreshold }
    private var drill: GrammarCategory? { GrammarExerciseService.category(for: focus) }

    private var color: Color {
        switch skill.struggle {
        case ..<0.15: .green
        case ..<0.4:  .yellow
        default:      .orange
        }
    }

    private var status: String {
        switch skill.struggle {
        case ..<0.15: "Solid"
        case ..<0.4:  "Getting there"
        default:      "Needs work"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(focus.germanLabel).font(.callout)
                    Text(focus.englishLabel).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(status).font(.caption2.weight(.medium)).foregroundStyle(color)
            }
            ConfidenceBar(fraction: confidence, color: color)
            if let sample = skill.samples.first {
                Text(sample).font(.caption2).foregroundStyle(.secondary).italic()
            }
            if isShaky {
                lesson
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Just-in-time mini-lesson

    @ViewBuilder private var lesson: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showLesson.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "graduationcap")
                Text(showLesson ? "Hide lesson" : "Quick lesson")
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(showLesson ? 90 : 0))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)

        if showLesson {
            Text(focus.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            if let drill {
                Button {
                    router.launch(.grammarMultipleChoice(category: drill, showHints: true))
                } label: {
                    Label("Practice this", systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
                .padding(.top, 2)
            } else {
                Label("The coach is watching for this in your next chat", systemImage: "lightbulb")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}

/// A thin capsule bar filled to `fraction` of its width.
private struct ConfidenceBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray5))
                Capsule().fill(color)
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Archive screen

/// The full archive of cleaned-out memories, newest first. Each item can be restored (and is
/// pinned on restore so it won't be cleaned again) or forgotten for good.
struct MemoryArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchivedMemoryItem.archivedAt, order: .reverse) private var archived: [ArchivedMemoryItem]

    var body: some View {
        Group {
            if archived.isEmpty {
                ContentUnavailableView(
                    "Nothing archived",
                    systemImage: "archivebox",
                    description: Text("Words and slip-ups the coach cleans out will show up here.")
                )
            } else {
                List {
                    ForEach(archived) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.kind == .vocab ? "text.book.closed" : "exclamationmark.bubble")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.callout)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text("\(item.reason.label) · \(item.archivedAt.formatted(.relative(presentation: .named)))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                LearnerMemoryService.restore(item, in: modelContext); save()
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.left")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                LearnerMemoryService.forget(item, in: modelContext); save()
                            } label: {
                                Label("Forget", systemImage: "trash")
                            }
                        }
                    }
                    .themedListRow()
                }
                .themedListScreen()
            }
        }
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        try? modelContext.save()
    }
}
