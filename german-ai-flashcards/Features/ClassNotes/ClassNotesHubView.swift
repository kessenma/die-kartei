//
//  ClassNotesHubView.swift
//  german-ai-flashcards
//
//  The Deutschkurs landing page: the courses the learner is taking, two front doors (log a class,
//  add a handout), the homework still open, this week's entries across courses, and the decks the
//  courses have built. Everything here is a companion to a class that happens elsewhere; the app
//  never teaches the course, it keeps what the course produced and, later, feeds it to the tutors.
//

import SwiftUI
import SwiftData

struct ClassNotesHubView: View {
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Open the intro as soon as the hub appears, whatever the seen flag says (the debug screen,
    /// or any future "Try it" link).
    var presentsIntro = false

    @Query(sort: \ClassCourse.sortOrder) private var allCourses: [ClassCourse]
    @Query(sort: \ClassEntry.date, order: .reverse) private var allEntries: [ClassEntry]
    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(ActivityRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var showCourseEditor = false
    /// "Add a handout" with no course yet: the course editor first, then the import.
    @State private var showFirstCourseEditor = false
    /// The course that editor produced (or Skip created), picked up once it has dismissed.
    @State private var courseAwaitingHandout: ClassCourse?
    @State private var showEntryEditor = false
    @State private var showHelp = false
    @State private var showHandoutCoursePicker = false
    @State private var importTarget: ClassHandoutTarget?
    /// An entry just created, pushed straight into its detail.
    @State private var openedEntry: ClassEntry?
    /// A handout's homework, opened from the Homework list.
    @State private var openedWorksheet: ClassMaterial?
    /// The course the learner logged for last; the editor and the handout door start from it.
    @AppStorage("classNotes.lastCourseID") private var lastCourseID = ""

    // Onboarding (docs/CLASS_NOTES.md ▸ Onboarding): the intro and the "Erste Schritte" checklist.
    @AppStorage(ClassNotesGuide.Keys.introSeen) private var introSeen = false
    @AppStorage(ClassNotesGuide.Keys.kind) private var guideKindRaw = ""
    @AppStorage(ClassNotesGuide.Keys.materials) private var guideMaterialsRaw = ""
    @AppStorage(ClassNotesGuide.Keys.shownAt) private var guideShownAt: Double = 0
    @AppStorage(ClassNotesGuide.Keys.hiddenAt) private var guideHiddenAt: Double = 0
    @State private var showIntro = false
    @State private var introOffered = false
    /// What the intro asked for on its way out, run once its sheet is gone.
    @State private var introFollowUp: ClassNotesIntroView.FollowUp = .none
    /// The checklist's done-state, fetched outside `body` (see `refreshGuide`).
    @State private var guideSnapshot: ClassNotesGuide.Snapshot = .empty
    /// A handout opened from the checklist's "Save a word", with the double-tap hint.
    @State private var hintedMaterial: ClassMaterial?
    /// The course a vocab list is being turned into a deck for (the checklist's "vocab list").
    @State private var documentDeckCourse: ClassCourse?

    private var courses: [ClassCourse] { allCourses.filter { !$0.isArchived } }
    private var archivedCourses: [ClassCourse] { allCourses.filter(\.isArchived) }
    private var classDecks: [SavedDeck] { decks.filter { $0.courseID != nil && !$0.cards.isEmpty } }
    private var openHomework: [ClassEntry] {
        allEntries.filter(\.hasOpenHomework).sorted(by: ClassCourse.homeworkOrder)
    }
    /// Today and the six days before it, the same rolling window as the week in review.
    private var thisWeek: [ClassEntry] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
        return allEntries.filter { $0.date >= start }
    }
    private var preferredCourse: ClassCourse? {
        courses.first { $0.id.uuidString == lastCourseID } ?? courses.first
    }
    private var deckStore: DeckStore { DeckStore(modelContext: modelContext) }

    private var guideVisible: Bool {
        ClassNotesGuide.isChecklistVisible(shownAt: guideShownAt, hiddenAt: guideHiddenAt)
    }
    private var guideKind: ClassCourse.Kind {
        ClassCourse.Kind(rawValue: guideKindRaw) ?? preferredCourse?.kind ?? .course
    }
    private var guideItems: [ClassNotesGuide.Item] {
        ClassNotesGuide.items(kind: guideKind, materials: ClassNotesGuide.Material.parse(guideMaterialsRaw))
    }

    var body: some View {
        List {
            if guideVisible {
                ClassNotesGuideSection(
                    items: guideItems,
                    snapshot: guideSnapshot,
                    kind: guideKind,
                    onShowMe: showMe,
                    onHide: { withAnimation { ClassNotesGuide.hideChecklist() } }
                )
            }
            coursesSection
            if !courses.isEmpty {
                practiceSection
            }
            if !openHomework.isEmpty {
                homeworkSection
            }
            if !thisWeek.isEmpty {
                weekSection
            }
            if !classDecks.isEmpty {
                decksSection
            }
            if !archivedCourses.isEmpty {
                archivedSection
            }
        }
        .themedListScreen()
        .navigationTitle(ClassNotesTile.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        showHelp = true
                    } label: {
                        Label("How it works", systemImage: "book")
                    }
                    Button {
                        showIntro = true
                    } label: {
                        Label("Take the tour", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("How class notes work")
                Button {
                    showEntryEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Log a class")
            }
        }
        .navigationDestination(item: $openedEntry) { entry in
            ClassEntryDetailView(entry: entry, modelManager: modelManager, mlxService: mlxService)
        }
        .navigationDestination(item: $openedWorksheet) { material in
            WorksheetView(material: material, modelManager: modelManager, mlxService: mlxService)
        }
        .navigationDestination(item: $hintedMaterial) { material in
            ClassMaterialDetailView(material: material, modelManager: modelManager, mlxService: mlxService,
                                    showsSaveWordHint: true)
        }
        .sheet(isPresented: $showEntryEditor) {
            ClassEntryEditorView(entry: nil, course: preferredCourse) { entry in
                // Let the editor finish dismissing before the push.
                DispatchQueue.main.async { openedEntry = entry }
            }
        }
        .sheet(isPresented: $showCourseEditor) {
            ClassCourseEditorView(course: nil, defaultLevel: modelManager.germanLevel)
        }
        .sheet(isPresented: $showFirstCourseEditor, onDismiss: {
            // The import sheet waits for the editor to be fully gone; presenting it from the
            // editor's save would race the dismissal.
            guard let course = courseAwaitingHandout else { return }
            courseAwaitingHandout = nil
            startHandout(in: course)
        }) {
            ClassCourseEditorView(
                course: nil,
                defaultLevel: modelManager.germanLevel,
                onSaved: { course in courseAwaitingHandout = course },
                onSkip: { courseAwaitingHandout = makeDefaultCourse() }
            )
        }
        .sheet(item: $importTarget) { target in
            ClassMaterialImportView(course: target.course, entry: target.entry) { _ in
                DispatchQueue.main.async { openedEntry = target.entry }
            }
        }
        .sheet(isPresented: $showHelp) {
            ClassNotesHelpSheet()
        }
        .sheet(isPresented: $showIntro, onDismiss: runIntroFollowUp) {
            ClassNotesIntroView(
                hasCourses: !allCourses.isEmpty,
                existingKind: preferredCourse?.kind ?? .course,
                defaultLevel: modelManager.germanLevel,
                canGoBackHome: canGoBackHome,
                onFinish: { course, followUp in
                    if let course { lastCourseID = course.id.uuidString }
                    introFollowUp = followUp
                }
            )
        }
        .sheet(item: $documentDeckCourse) { course in
            DocumentDeckImportView(modelManager: modelManager, mlxService: mlxService, course: course) { _ in }
        }
        .task { await offerIntroIfNeeded() }
        .onAppear(perform: refreshGuide)
        // A sheet closing or a study session ending doesn't re-run onAppear; what they change does.
        .onChange(of: allCourses.count) { refreshGuide() }
        .onChange(of: allEntries.count) { refreshGuide() }
        .onChange(of: decks.count) { refreshGuide() }
        .onChange(of: showEntryEditor) { refreshGuide() }
        .onChange(of: importTarget == nil) { refreshGuide() }
        .onChange(of: documentDeckCourse == nil) { refreshGuide() }
        .onChange(of: router.active == nil) { refreshGuide() }
        .onChange(of: guideShownAt) { refreshGuide() }
        .confirmationDialog("Which course is the handout from?", isPresented: $showHandoutCoursePicker, titleVisibility: .visible) {
            ForEach(courses) { course in
                Button(course.name) { startHandout(in: course) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Onboarding

    /// The Mac shows Deutschkurs as a sidebar place, with no Home screen under it to go back to.
    private var canGoBackHome: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    /// The intro opens by itself once, for someone with no course at all (a finished one counts:
    /// that learner knows the room). The flag is written before it shows, so a crash or a Close
    /// never turns it into a nag.
    private func offerIntroIfNeeded() async {
        if presentsIntro {
            guard !introOffered else { return }
            introOffered = true
            showIntro = true
            return
        }
        guard ClassNotesGuide.shouldAutoShowIntro(seen: introSeen, courseCount: allCourses.count) else { return }
        // A new device with iCloud Sync on: courses made elsewhere may still be on their way.
        if SyncManager.shared.isRunning {
            await SyncManager.shared.waitForFirstFetch(timeout: .seconds(10))
        }
        guard ClassNotesGuide.shouldAutoShowIntro(seen: introSeen, courseCount: allCourses.count) else { return }
        introSeen = true
        // A sheet presented while the push into this screen is still settling can be dropped.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled, allCourses.isEmpty else { return }
        showIntro = true
    }

    /// Runs from the intro sheet's `onDismiss`, so the next sheet or the pop never races it.
    private func runIntroFollowUp() {
        let followUp = introFollowUp
        introFollowUp = .none
        refreshGuide()
        switch followUp {
        case .none: break
        case .logClass: showEntryEditor = true
        case .addHandout: startHandout()
        case .backHome: dismiss()
        }
    }

    /// Re-reads the checklist's done-state. Fetches, not `body` reads: a filtered query read in
    /// `body` loops once a screen is pushed over the hub.
    private func refreshGuide() {
        guard guideVisible else { return }
        let fresh = ClassNotesGuide.Snapshot.make(context: modelContext)
        if fresh != guideSnapshot { guideSnapshot = fresh }
    }

    /// Where each open checklist step is done.
    private func showMe(_ item: ClassNotesGuide.Item) {
        switch item {
        case .course:
            showCourseEditor = true
        case .logClass:
            showEntryEditor = true
        case .handout, .homework:
            startHandout()
        case .saveWord:
            if let material = newestHandout() {
                hintedMaterial = material
            } else {
                showEntryEditor = true
            }
        case .vocabList:
            if let course = preferredCourse {
                documentDeckCourse = course
            } else {
                showCourseEditor = true
            }
        case .studyDeck:
            if let deck = studyDeck() {
                router.launch(.cardDeck(deckStore.session(for: deck, style: modelManager.flashcardStyle)))
            }
        }
    }

    /// The handout added last, on any course.
    private func newestHandout() -> ClassMaterial? {
        var descriptor = FetchDescriptor<ClassMaterial>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// The preferred course's own deck if it has cards, else any course deck that does.
    private func studyDeck() -> SavedDeck? {
        if let course = preferredCourse, let own = ClassDeckStore.deck(for: course, context: modelContext), !own.cards.isEmpty {
            return own
        }
        return classDecks.first
    }

    // MARK: - Courses

    @ViewBuilder
    private var coursesSection: some View {
        Section {
            if courses.isEmpty {
                Button {
                    showEntryEditor = true
                } label: {
                    JobPrepHeroRow(
                        title: "Log your first class",
                        subtitle: "What you covered, the new words, the homework. Your course is created with it.",
                        systemImage: "graduationcap.fill",
                        accent: ClassNotesTile.tint
                    )
                }
                .buttonStyle(.plain)
            } else {
                ForEach(courses) { course in
                    NavigationLink {
                        ClassCourseDetailView(course: course, modelManager: modelManager, mlxService: mlxService)
                    } label: {
                        ClassCourseRow(course: course, deck: ClassDeckStore.deck(for: course, context: modelContext))
                    }
                }
            }
            Button {
                showCourseEditor = true
            } label: {
                Label(courses.isEmpty ? "Set up a course first instead" : "Add a course", systemImage: "plus.circle")
            }
        } header: {
            Text("Kurse · Courses").themedSectionHeader()
        } footer: {
            if courses.isEmpty {
                Text("A course is anything with a teacher and a rhythm: a semester at university, a private tutor, a Volkshochschule class. Each keeps its own notes, handouts, and flashcard deck.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private var archivedSection: some View {
        Section {
            ForEach(archivedCourses) { course in
                NavigationLink {
                    ClassCourseDetailView(course: course, modelManager: modelManager, mlxService: mlxService)
                } label: {
                    ClassCourseRow(course: course, deck: ClassDeckStore.deck(for: course, context: modelContext))
                }
            }
        } header: {
            Text("Finished courses").themedSectionHeader()
        }
        .themedListRow()
    }

    // MARK: - Practice

    private var practiceSection: some View {
        Section {
            Button {
                showEntryEditor = true
            } label: {
                JobPrepHeroRow(
                    title: "Log a class",
                    subtitle: "What today's class covered: grammar, topics, new words, homework.",
                    systemImage: "square.and.pencil",
                    accent: ClassNotesTile.tint
                )
            }
            .buttonStyle(.plain)

            Button {
                startHandout()
            } label: {
                JobPrepHeroRow(
                    title: "Add a handout",
                    subtitle: "A PDF, a photo of a page, or pasted text. Read it word by word, save the words.",
                    systemImage: "doc.text.viewfinder",
                    accent: ClassNotesTile.tint
                )
            }
            .buttonStyle(.plain)
        } header: {
            Text("Nach dem Unterricht · After class").themedSectionHeader()
        } footer: {
            Text("A handout is filed under today's entry for the course; log the class afterwards to add what was covered.")
                .font(.caption2)
        }
        .themedListRow()
    }

    /// "Add a handout" needs a course and an entry for today. One course: straight in; several:
    /// ask which; none: set one up first (what kind of class, how many weeks), or skip to a
    /// plain default.
    private func startHandout() {
        if courses.count > 1 {
            showHandoutCoursePicker = true
        } else if let course = courses.first {
            startHandout(in: course)
        } else {
            showFirstCourseEditor = true
        }
    }

    private func makeDefaultCourse() -> ClassCourse {
        let course = ClassCourse(name: "Deutschkurs")
        course.sortOrder = (allCourses.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(course)
        return course
    }

    private func startHandout(in course: ClassCourse) {
        lastCourseID = course.id.uuidString
        importTarget = ClassHandoutTarget(course: course, entry: ClassEntryStore.todayEntry(in: course, context: modelContext))
    }

    // MARK: - Homework

    private var homeworkSection: some View {
        Section {
            ForEach(openHomework) { entry in
                ClassHomeworkRow(entry: entry, showsCourse: courses.count > 1) { material in
                    openedWorksheet = material
                }
            }
        } header: {
            Text("Hausaufgaben · Homework").themedSectionHeader()
        } footer: {
            Text("Tick it off when it's done; it drops off this list and stays with the entry.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - This week

    private var weekSection: some View {
        Section {
            ForEach(thisWeek) { entry in
                NavigationLink {
                    ClassEntryDetailView(entry: entry, modelManager: modelManager, mlxService: mlxService)
                } label: {
                    ClassEntryRow(entry: entry, showsCourse: courses.count > 1)
                }
            }
            .onDelete(perform: deleteWeekEntries)
        } header: {
            Text("Diese Woche · This week").themedSectionHeader()
        } footer: {
            Text("Earlier entries live under each course.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private func deleteWeekEntries(at offsets: IndexSet) {
        for index in offsets {
            ClassEntryStore.delete(thisWeek[index], context: modelContext)
        }
        try? modelContext.save()
    }

    // MARK: - Decks

    private var decksSection: some View {
        Section {
            ForEach(classDecks) { deck in
                Button {
                    router.launch(.cardDeck(deckStore.session(for: deck, style: modelManager.flashcardStyle)))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: deck.kindSymbol ?? "rectangle.stack.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deck.topic.replacingOccurrences(of: "Class: ", with: ""))
                                .font(.body)
                                .lineLimit(1)
                            let owner = allCourses.first { $0.id == deck.courseID }?.name
                            Text([owner, "\(deck.cards.count) cards"].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(deck.cards.isEmpty)
            }
        } header: {
            Text("Kursdecks · Class decks").themedSectionHeader()
        } footer: {
            Text("Each course's own word deck, plus decks made from its vocab sheets and handouts. Also under Library ▸ Decks.")
                .font(.caption2)
        }
        .themedListRow()
    }
}

// MARK: - Targets

/// Where a handout goes: a course, and its entry for today.
struct ClassHandoutTarget: Identifiable {
    let id = UUID()
    let course: ClassCourse
    let entry: ClassEntry
}

/// The fetch-or-create and delete helpers the hub, course, and entry screens share.
enum ClassEntryStore {
    /// The course's entry for today, created (and inserted) if there is none.
    @MainActor
    static func todayEntry(in course: ClassCourse, context: ModelContext) -> ClassEntry {
        let today = Calendar.current.startOfDay(for: .now)
        if let existing = course.entries.filter({ $0.date == today }).sorted(by: { $0.createdAt < $1.createdAt }).first {
            return existing
        }
        let entry = ClassEntry(date: today)
        // The same id on every device for (course, day): two devices filing today's first handout
        // offline create one entry, not two.
        let derived = SyncNameUUID.make("class-entry", course.id.uuidString, SyncDayKey.key(for: today))
        // Only if no row has it yet (an entry made today and later moved to another date keeps it).
        if (try? context.fetchCount(FetchDescriptor<ClassEntry>(predicate: #Predicate { $0.id == derived }))) == 0 {
            entry.id = derived
        }
        context.insert(entry)
        entry.course = course
        course.updatedAt = .now
        try? context.save()
        return entry
    }

    /// Delete an entry with its handouts. The cascade removes the rows; the files are ours to remove.
    @MainActor
    static func delete(_ entry: ClassEntry, context: ModelContext) {
        for material in entry.materials {
            ClassMaterialStore.delete(material.snapshotFile)
            WorksheetInkStore.deleteAll(for: material.id)
        }
        context.delete(entry)
    }

    /// Delete a handout and its original file.
    @MainActor
    static func delete(_ material: ClassMaterial, context: ModelContext) {
        ClassMaterialStore.delete(material.snapshotFile)
        WorksheetInkStore.deleteAll(for: material.id)
        context.delete(material)
    }

    /// Delete a course with every entry and handout. Its deck stays: library content the learner built.
    @MainActor
    static func delete(_ course: ClassCourse, context: ModelContext) {
        for material in course.materials {
            ClassMaterialStore.delete(material.snapshotFile)
            WorksheetInkStore.deleteAll(for: material.id)
        }
        context.delete(course)
    }
}

// MARK: - Rows

/// One course: its kind, who teaches it or what it is for, and how much it has produced.
struct ClassCourseRow: View {
    let course: ClassCourse
    var deck: SavedDeck? = nil

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: course.kind.systemImage)
                .font(.title3)
                .foregroundStyle(ClassNotesTile.tint)
                .frame(width: 32, height: 32)
                .background(ClassNotesTile.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(.body)
                    .lineLimit(1)
                Text(course.subtitleLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    let entries = course.entries.count
                    Text("\(entries) \(entries == 1 ? "entry" : "entries")")
                    let open = course.openHomework.count
                    if open > 0 {
                        Label("\(open)", systemImage: "checklist")
                            .labelStyle(.titleAndIcon)
                    }
                    if let deck, !deck.cards.isEmpty {
                        Label("\(deck.cards.count)", systemImage: "rectangle.stack.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    if let week = course.currentWeekLabel {
                        Text(week)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

/// One entry in a list: the day, its title, and what it holds, as small pills.
struct ClassEntryRow: View {
    let entry: ClassEntry
    var showsCourse = false

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.displayTitle)
                    .font(.body)
                    .lineLimit(1)
                Spacer()
                Text(entry.dateLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showsCourse, let course = entry.course {
                Text(course.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let parts = entry.summaryParts
            if !parts.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(parts, id: \.self) { part in
                        Text(part)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(part == "Hausaufgabe" ? ClassNotesTile.tint : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill), in: appTheme.pillShape)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// An open homework item: the assignment, when it's due, and the tick that closes it.
struct ClassHomeworkRow: View {
    @Bindable var entry: ClassEntry
    var showsCourse = false
    /// Opens a handout's worksheet. With it, the row opens the exercises and only the circle
    /// ticks them off; without it the whole row is the checkbox, as for written-down homework.
    var onOpenWorksheet: ((ClassMaterial) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    private var worksheet: ClassMaterial? {
        entry.materials.first { $0.worksheetData != nil }
    }

    var body: some View {
        if let onOpenWorksheet, let worksheet {
            worksheetRow(worksheet, open: onOpenWorksheet)
        } else {
            toggle
        }
    }

    // MARK: - With exercises

    private func worksheetRow(_ material: ClassMaterial, open: @escaping (ClassMaterial) -> Void) -> some View {
        let setup = material.worksheet
        let sent = setup?.status == .sent
        let started = material.worksheetAnswersData != nil || !WorksheetInkStore.pagesWithInk(material.id).isEmpty
        return HStack(alignment: .top, spacing: 12) {
            Button {
                setDone(!entry.homeworkDone)
            } label: {
                Image(systemName: entry.homeworkDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.homeworkDone ? ClassNotesTile.tint : .secondary)
                    .padding(.top, 1)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(entry.homeworkDone ? "Done. Mark as not done" : "Mark as done")

            Button {
                open(material)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    details
                    Label(sent ? "Open the sent homework" : (started ? "Continue the exercises" : "Start the exercises"),
                          systemImage: sent ? "paperplane.fill" : (started ? "arrow.forward.circle.fill" : "play.circle.fill"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(ClassNotesTile.tint, in: appTheme.pillShape)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityHint("Opens the exercises")
        }
    }

    // MARK: - Written-down homework

    private var toggle: some View {
        Toggle(isOn: Binding(
            get: { entry.homeworkDone },
            set: { setDone($0) }
        )) {
            details
        }
        .toggleStyle(ClassCheckboxToggleStyle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.homework.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            HStack(spacing: 6) {
                if showsCourse, let course = entry.course {
                    Text(course.name)
                }
                if let due = entry.homeworkDue {
                    Text("Due \(due.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(entry.homeworkIsOverdue ? .red : .secondary)
                } else {
                    Text("From \(entry.dateLine)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func setDone(_ done: Bool) {
        entry.homeworkDone = done
        entry.updatedAt = .now
        try? modelContext.save()
    }
}

/// A leading checkbox rather than a trailing switch: this is a to-do, not a setting.
struct ClassCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? ClassNotesTile.tint : .secondary)
                    .padding(.top, 1)
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Help

struct ClassNotesHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A companion to a class you take elsewhere: a university course, a private tutor, an evening class. The app keeps what the class produced, so the words and grammar you meet in class are the ones you practise here.")
                        .font(.body)
                    point("person.3.fill", "Kurse · Courses",
                          "One per class you attend. A semester course with dates labels its entries by week; a tutor is a string of sessions with a goal.")
                    point("square.and.pencil", "Einträge · Entries",
                          "One per class: the grammar covered, the topics, the new words, your notes, and the homework. Homework stays on the front page until you tick it off.")
                    point("doc.text.viewfinder", "Handouts",
                          "A PDF, a photo of a page, or pasted text, filed under the day's entry. Read it word by word; double-tap what you don't know and save it.")
                    point("rectangle.stack.fill", "Kursdeck · Class deck",
                          "Each course builds one flashcard deck from the words you log and save. Study it here or under Library ▸ Decks.")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(ClassNotesTile.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Preview

#Preview("Class notes hub · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        NavigationStack {
            ClassNotesHubView(modelManager: MLXModelManager(), mlxService: MLXGenerationService())
        }
        .environment(ActivityRouter())
        .environment(\.appTheme, theme)
        .modelContainer(
            for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self, SavedDeck.self, SavedCard.self],
            inMemory: true
        )
    }
}
