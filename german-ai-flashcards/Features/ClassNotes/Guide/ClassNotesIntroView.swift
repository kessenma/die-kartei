//
//  ClassNotesIntroView.swift
//  german-ai-flashcards
//
//  The Deutschkurs intro (docs/CLASS_NOTES.md ▸ Onboarding): how the learner is learning, the
//  course in a few fields, what the class hands out, and the first steps that follow. It ends by
//  creating the real course and putting the "Erste Schritte" checklist on the hub.
//
//  Leaving costs nothing at any step: Close and a swipe-down both just dismiss, and nothing is
//  saved before the last step. Someone not taking a class gets a real answer, not a dead end:
//  use it on their own, look around, or go back Home.
//
//  Opened once by itself (first visit, no course) and any time from the hub's ? menu. With a
//  course already there, the run is only "what does your class give you" and the plan, so a
//  restart never makes a second course.
//

import SwiftUI
import SwiftData

struct ClassNotesIntroView: View {
    /// What the hub does once the intro is gone.
    enum FollowUp: Equatable {
        case none
        case logClass
        case addHandout
        /// Close the intro, then leave Deutschkurs.
        case backHome
    }

    /// Whether a course exists already: the run then skips the course questions.
    let hasCourses: Bool
    /// The kind of the course the checklist is for when `hasCourses` (the hub's preferred course).
    var existingKind: ClassCourse.Kind = .course
    var defaultLevel: CEFRLevel = .a2
    /// Shows "Back to Home" on the way-out page. Off where Deutschkurs has no screen to go back to
    /// (the Mac sidebar).
    var canGoBackHome = true
    /// Called before the dismiss with the course it made (nil on a restart or a way out) and what
    /// to do next. The hub runs the follow-up from the sheet's `onDismiss`.
    var onFinish: (_ course: ClassCourse?, _ followUp: FollowUp) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    enum Step: String, CaseIterable { case kind, notInClass, basics, materials, plan }

    /// How the learner is learning. Two of these are the same `ClassCourse.Kind`; they differ in
    /// the words and the name they start with.
    enum Choice: String, CaseIterable, Identifiable {
        case university, evening, tutor, selfStudy

        var id: String { rawValue }

        var kind: ClassCourse.Kind {
            switch self {
            case .university, .evening: .course
            case .tutor: .tutor
            case .selfStudy: .selfStudy
            }
        }

        var title: String {
            switch self {
            case .university: "University or school course"
            case .evening:    "Evening class"
            case .tutor:      "Private tutor"
            case .selfStudy:  "On my own"
            }
        }

        var subtitle: String {
            switch self {
            case .university: "A semester or a quarter, with weeks and homework."
            case .evening:    "Volkshochschule, Goethe-Institut, a language school."
            case .tutor:      "One-to-one sessions, online or in person."
            case .selfStudy:  "A textbook or a reading plan you work through yourself."
            }
        }

        var systemImage: String {
            switch self {
            case .university: "building.columns.fill"
            case .evening:    "person.3.fill"
            case .tutor:      "person.fill"
            case .selfStudy:  "book.closed.fill"
            }
        }

        var defaultName: String {
            switch self {
            case .university: "Deutschkurs"
            case .evening:    "Abendkurs"
            case .tutor:      "Privatstunden"
            case .selfStudy:  "Selbststudium"
            }
        }
    }

    /// Typical term lengths. The course editor offers the same two, plus a stepper for the rest.
    private static let termPresets: [(label: String, weeks: Int)] = [("Semester", 14), ("Quarter", 10)]

    @State private var step: Step
    /// `hasCourses` and `existingKind` as they were when the intro opened. The course the last
    /// step creates must not turn this run into a restart while the sheet is still sliding away.
    @State private var startedWithCourses: Bool
    @State private var startKind: ClassCourse.Kind
    @State private var choice: Choice?
    @State private var visitedNotInClass = false
    @State private var name = ""
    @State private var levelRaw = ""
    @State private var goal = ""
    /// Weeks from today for a dated course; 0 for no dates.
    @State private var termWeeks = 14
    @State private var materials: Set<ClassNotesGuide.Material> = []
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    init(
        hasCourses: Bool,
        existingKind: ClassCourse.Kind = .course,
        defaultLevel: CEFRLevel = .a2,
        canGoBackHome: Bool = true,
        onFinish: @escaping (_ course: ClassCourse?, _ followUp: FollowUp) -> Void = { _, _ in }
    ) {
        self.hasCourses = hasCourses
        self.existingKind = existingKind
        self.defaultLevel = defaultLevel
        self.canGoBackHome = canGoBackHome
        self.onFinish = onFinish
        var first: Step = hasCourses ? (existingKind == .selfStudy ? .plan : .materials) : .kind
        #if DEBUG
        // `-classNotes.debugIntroStep basics`: open on one step, for screenshots on a simulator
        // that can't tap. The course questions only exist without a course.
        if let raw = UserDefaults.standard.string(forKey: "classNotes.debugIntroStep"),
           let forced = Step(rawValue: raw), hasCourses == false || [.materials, .plan].contains(forced) {
            first = forced
        }
        #endif
        _step = State(initialValue: first)
        _startedWithCourses = State(initialValue: hasCourses)
        _startKind = State(initialValue: existingKind)
    }

    /// The kind the run is about: the pick, or the existing course's on a restart.
    private var kind: ClassCourse.Kind { startedWithCourses ? startKind : (choice?.kind ?? .course) }

    /// The steps this run shows. The indicator counts these, so a restart never claims "1 of 5".
    private var steps: [Step] {
        var s: [Step] = []
        if !startedWithCourses {
            s.append(.kind)
            if visitedNotInClass || step == .notInClass { s.append(.notInClass) }
            if step != .notInClass { s.append(.basics) }
        }
        if kind != .selfStudy, step != .notInClass { s.append(.materials) }
        if step != .notInClass { s.append(.plan) }
        return s
    }

    /// The materials the checklist is built from: self-study reads, it doesn't get handed things.
    private var effectiveMaterials: Set<ClassNotesGuide.Material> {
        kind == .selfStudy ? ClassNotesGuide.Material.selfStudyDefault : materials
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator
                Group {
                    switch step {
                    case .kind: kindPage
                    case .notInClass: notInClassPage
                    case .basics: basicsPage
                    case .materials: materialsPage
                    case .plan: planPage
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Nothing is saved before the last step, so leaving is always free.
                    Button("Close") { dismiss() }
                }
            }
        }
        .macSheetSize()
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        levelRaw = defaultLevel.rawValue
        if startedWithCourses {
            // A restart starts from what the learner picked last time.
            materials = ClassNotesGuide.Material.parse(
                UserDefaults.standard.string(forKey: ClassNotesGuide.Keys.materials) ?? "")
        }
        #if DEBUG
        // A step opened by `-classNotes.debugIntroStep` needs a pick behind it;
        // `-classNotes.debugIntroKind tutor|evening|selfStudy|university` chooses which.
        if !startedWithCourses, step != .kind, choice == nil {
            let raw = UserDefaults.standard.string(forKey: "classNotes.debugIntroKind") ?? ""
            pick(Choice(rawValue: raw) ?? .university, advance: false)
        }
        #endif
    }

    // MARK: - Chrome

    private var navigationTitle: String {
        switch step {
        case .kind: "Deutschkurs"
        case .notInClass: "Ohne Kurs"
        case .basics: kind == .selfStudy ? "Dein Plan" : "Dein Kurs"
        case .materials: "Was du bekommst"
        case .plan: "Erste Schritte"
        }
    }

    private var previousStep: Step? {
        switch step {
        case .kind: nil
        case .notInClass: .kind
        case .basics: visitedNotInClass ? .notInClass : .kind
        case .materials: startedWithCourses ? nil : .basics
        case .plan: kind != .selfStudy ? .materials : (startedWithCourses ? nil : .basics)
        }
    }

    /// "Step 2 of 4" with a bar, and Back where there is a step to go back to. Back lives here
    /// rather than in the toolbar, where on iOS it would crowd Close in the same corner.
    @ViewBuilder
    private var stepIndicator: some View {
        let all = steps
        if step == .notInClass {
            // A side road, not a step on the way: no count, just the way back.
            HStack {
                Spacer()
                backButton(to: .kind)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        } else if all.count > 1, let index = all.firstIndex(of: step) {
            VStack(spacing: 6) {
                HStack {
                    Text("Step \(index + 1) of \(all.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let previous = previousStep {
                        backButton(to: previous)
                    }
                }
                ProgressView(value: Double(index + 1), total: Double(all.count))
                    .controlSize(.mini)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private func backButton(to previous: Step) -> some View {
        Button {
            go(previous)
        } label: {
            Label("Back", systemImage: "chevron.backward")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.borderless)
    }

    private func actionBar<Secondary: View>(
        _ title: String,
        enabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder secondary: () -> Secondary = { EmptyView() }
    ) -> some View {
        VStack(spacing: 10) {
            Button(action: action) {
                Text(title)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!enabled)
            secondary()
        }
        .padding()
        .background(.bar)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.cornerRadius, style: .continuous))
    }

    private func go(_ next: Step) {
        withAnimation { step = next }
    }

    // MARK: - Step 1: how you're learning

    private var kindPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("A companion to a German class you take somewhere else. It keeps what each class gives you and turns the new words into flashcards.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("How are you learning German?")
                    .themedLabel(.title3.weight(.semibold), size: 22)
                VStack(spacing: 10) {
                    ForEach(Choice.allCases) { option in
                        Button {
                            pick(option, advance: true)
                        } label: {
                            choiceRow(option)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Continues to the next step")
                    }
                }
                Button {
                    visitedNotInClass = true
                    go(.notInClass)
                } label: {
                    Text("I'm not taking a class")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    private func choiceRow(_ option: Choice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: option.systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(ClassNotesTile.tint, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(11), style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .themedLabel(.headline, size: 17)
                    .foregroundStyle(.primary)
                Text(option.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: choice == option ? "checkmark.circle.fill" : "chevron.right")
                .font(choice == option ? .title3 : .caption)
                .foregroundStyle(choice == option ? AnyShapeStyle(ClassNotesTile.tint) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
    }

    private func pick(_ option: Choice, advance: Bool) {
        // A new pick resets the name only if the learner hadn't typed their own.
        let typedOwn = !name.isEmpty && !Choice.allCases.map(\.defaultName).contains(name)
        choice = option
        if !typedOwn { name = option.defaultName }
        termWeeks = option == .university ? 14 : (option == .evening ? 10 : 0)
        if option.kind == .selfStudy { materials = ClassNotesGuide.Material.selfStudyDefault }
        if advance { go(.basics) }
    }

    // MARK: - The way out

    private var notInClassPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                card {
                    Label("No class? That's fine.", systemImage: "book.closed.fill")
                        .font(.headline)
                    Text("Deutschkurs still works for anything you read. Bring in a PDF, a photo of a page or some pasted text, read it word by word, and keep the words you didn't know as a flashcard deck.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("If you join a class or find a tutor later, this is where it goes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("You can start this again any time from the ? button.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            actionBar("Use it on my own") {
                pick(.selfStudy, advance: true)
            } secondary: {
                HStack(spacing: 20) {
                    Button("Look around first") {
                        onFinish(nil, .none)
                        dismiss()
                    }
                    if canGoBackHome {
                        Button("Back to Home") {
                            onFinish(nil, .backHome)
                            dismiss()
                        }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Step 2: the course

    private var basicsPage: some View {
        Form {
            Section {
                TextField(kind == .selfStudy ? "Name of your plan" : "Name of the course", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                if kind != .course {
                    // A Form row shows only the prompt, so the prompt has to say what the field is.
                    TextField(kind == .tutor ? "What it's for" : "What you're working through",
                              text: $goal,
                              prompt: Text(kind == .tutor ? "What it's for (optional), e.g. HR German"
                                                          : "What you're reading (optional), e.g. Menschen A2"))
                }
            } header: {
                Text(kind == .selfStudy ? "Plan · Your plan" : "Kurs · Your course").themedSectionHeader()
            } footer: {
                Text(kind == .selfStudy
                     ? "You can change all of this later on its page."
                     : "The teacher, the schedule and links can go on the course page later.")
                    .font(.caption2)
            }
            .themedListRow()

            Section {
                Picker("Level", selection: $levelRaw) {
                    Text("Not set").tag("")
                    ForEach(CEFRLevel.allCases) { level in
                        Text("\(level.rawValue) · \(level.englishLabel)").tag(level.rawValue)
                    }
                }
            } header: {
                Text("Niveau · Level").themedSectionHeader()
            } footer: {
                Text("The level it's pitched at, if you know it.")
                    .font(.caption2)
            }
            .themedListRow()

            if kind == .course {
                Section {
                    Picker("Length", selection: $termWeeks) {
                        ForEach(Self.termPresets, id: \.weeks) { preset in
                            Text("\(preset.label) · \(preset.weeks)").tag(preset.weeks)
                        }
                        Text("No dates").tag(0)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Dauer · Length").themedSectionHeader()
                } footer: {
                    Text(termWeeks > 0
                         ? "Starting this week, so each class is labelled \"Woche 1\", \"Woche 2\" and so on."
                         : "Classes are just listed by date.")
                        .font(.caption2)
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .safeAreaInset(edge: .bottom) {
            actionBar("Next", enabled: !trimmedName.isEmpty) {
                nameFocused = false
                go(kind == .selfStudy ? .plan : .materials)
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - Step 3: what the class hands out

    private var materialsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(kind == .tutor ? "What does your tutor give you?" : "What does your class give you?")
                    .themedLabel(.title3.weight(.semibold), size: 22)
                Text("Pick any. This only decides which first steps you see.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    ForEach(ClassNotesGuide.Material.allCases) { material in
                        Button {
                            toggle(material)
                        } label: {
                            materialRow(material)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(materials.contains(material) ? .isSelected : [])
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            actionBar("Next") { go(.plan) }
        }
    }

    private func materialRow(_ material: ClassNotesGuide.Material) -> some View {
        let on = materials.contains(material)
        return HStack(spacing: 12) {
            Image(systemName: material.systemImage)
                .font(.title3)
                .foregroundStyle(ClassNotesTile.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(material.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(material.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on ? AnyShapeStyle(ClassNotesTile.tint) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: appTheme.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
    }

    /// "Mostly talking" and the paper kinds rule each other out.
    private func toggle(_ material: ClassNotesGuide.Material) {
        if materials.contains(material) {
            materials.remove(material)
            return
        }
        if material == .talking {
            materials = [.talking]
        } else {
            materials.remove(.talking)
            materials.insert(material)
        }
    }

    // MARK: - Step 4: the plan

    private var planItems: [ClassNotesGuide.Item] {
        ClassNotesGuide.items(kind: kind, materials: effectiveMaterials)
    }

    private var planPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(startedWithCourses ? "Your first steps, back on the Deutschkurs page." : "Your first steps")
                    .themedLabel(.title3.weight(.semibold), size: 22)
                card {
                    ForEach(Array(planItems.enumerated()), id: \.element) { index, item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.systemImage)
                                .font(.body)
                                .foregroundStyle(ClassNotesTile.tint)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(item.title(for: kind))")
                                    .font(.subheadline.weight(.semibold))
                                Text(item.detail(for: kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Text("They tick themselves off as you go, on the Deutschkurs page. Hide the list with ✕ whenever you like; the ? button brings it back.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            actionBar("Los geht's · Let's go") {
                finish(.none)
            } secondary: {
                Button(kind == .selfStudy ? "Add something to read now" : (kind == .tutor ? "Log my first session now" : "Log my first class now")) {
                    finish(kind == .selfStudy ? .addHandout : .logClass)
                }
                .font(.subheadline)
            }
        }
    }

    /// The only place anything is saved: the course (on a first run) and the checklist.
    private func finish(_ followUp: FollowUp) {
        var made: ClassCourse?
        if !startedWithCourses {
            let course = ClassCourse(name: trimmedName.isEmpty ? (choice ?? .university).defaultName : trimmedName, kind: kind)
            let existing = (try? modelContext.fetch(FetchDescriptor<ClassCourse>())) ?? []
            course.sortOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
            course.levelRaw = levelRaw.isEmpty ? nil : levelRaw
            let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind != .course, !trimmedGoal.isEmpty { course.goal = String(trimmedGoal.prefix(120)) }
            if kind == .course, termWeeks > 0 {
                let start = Calendar.current.startOfDay(for: .now)
                course.startDate = start
                course.endDate = ClassCourse.endDate(start: start, weeks: termWeeks, calendar: .current)
            }
            modelContext.insert(course)
            try? modelContext.save()
            made = course
        }
        ClassNotesGuide.showChecklist(kind: kind, materials: effectiveMaterials)
        onFinish(made, followUp)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Intro · first run · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        ClassNotesIntroView(hasCourses: false)
            .environment(\.appTheme, theme)
            .inMemoryModelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self])
    }
}

#Preview("Intro · restart") {
    ClassNotesIntroView(hasCourses: true, existingKind: .tutor)
        .inMemoryModelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self])
}
