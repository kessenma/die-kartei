//
//  ClassCourseEditorView.swift
//  german-ai-flashcards
//
//  Create or edit a course: what it is, who teaches it or what it is for, its level, and its
//  dates when it has them (a start plus a length in weeks, or an end date; the two stay in step).
//  An existing course can also be archived (finished, kept) or deleted (with its entries and
//  handouts; the deck stays in the Library).
//

import SwiftUI
import SwiftData

struct ClassCourseEditorView: View {
    /// Nil creates a new course.
    var course: ClassCourse?
    /// The learner's declared level, offered as the default for a new course.
    var defaultLevel: CEFRLevel = .a2
    var onSaved: (ClassCourse) -> Void = { _ in }
    /// Called after a delete, so the screen that showed the course can leave.
    var onDeleted: () -> Void = {}
    /// The kind a new course starts on.
    var initialKind: ClassCourse.Kind = .course
    /// Set when the editor stands between the learner and something they asked for (adding a
    /// handout with no course yet): a "Skip for now" row then lets them go on without setting up.
    var onSkip: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Query(sort: \ClassCourse.sortOrder) private var courses: [ClassCourse]

    @State private var name = ""
    @State private var kind: ClassCourse.Kind = .course
    @State private var teacher = ""
    @State private var teacherEmail = ""
    @State private var courseURL = ""
    @State private var goal = ""
    @State private var levelRaw = ""
    @State private var hasDates = false
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var weeks = 14
    /// Once the learner flips the dates toggle themselves, changing the kind stops flipping it.
    @State private var datesTouched = false
    @State private var isArchived = false
    /// When it meets (roadmap item 12).
    @State private var weekdays: Set<Int> = []
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now
    @State private var hasNextSession = false
    @State private var nextSession = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var showDeleteConfirm = false
    @State private var loaded = false
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, teacher, email, link, goal }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                kindSection
                detailsSection
                levelSection
                datesSection
                scheduleSection
                if course != nil {
                    statusSection
                }
                if course == nil, onSkip != nil {
                    skipSection
                }
            }
            .themedListScreen()
            .navigationTitle(course == nil ? "New course" : "Edit course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
            .confirmationDialog(
                "Delete this course?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete course and its entries", role: .destructive) { deleteCourse() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every entry and handout goes with it. The flashcard deck stays in the Library.")
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, newKind in
                // A new course's dates follow its kind until the learner decides: a term course
                // has weeks, a tutor usually doesn't.
                guard course == nil, !datesTouched else { return }
                withAnimation { hasDates = newKind == .course }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Course name", text: $name)
                .focused($focused, equals: .name)
                .submitLabel(.next)
                .onSubmit { focused = .teacher }
        } header: {
            Text("Name").themedSectionHeader()
        } footer: {
            Text("As you'd say it: \"Deutsch A2 an der Uni\", \"HR-Deutsch mit Anna\".")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var kindSection: some View {
        Section {
            Picker("Kind", selection: $kind) {
                ForEach(ClassCourse.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("What kind of course").themedSectionHeader()
        } footer: {
            Text(kind.blurb)
                .font(.caption2)
        }
        .themedListRow()
    }

    private var detailsSection: some View {
        Section {
            TextField("Teacher or tutor", text: $teacher)
                .focused($focused, equals: .teacher)
                .submitLabel(.next)
                .onSubmit { focused = .email }
            TextField("Teacher's email", text: $teacherEmail)
                .focused($focused, equals: .email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focused = .link }
            TextField("Course page (Moodle, Canvas…)", text: $courseURL)
                .focused($focused, equals: .link)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { focused = .goal }
            TextField("Goal", text: $goal, axis: .vertical)
                .focused($focused, equals: .goal)
                .lineLimit(1...3)
        } header: {
            Text("Details").themedSectionHeader()
        } footer: {
            Text("All optional. The email and the course page become one-tap links on the course's page. The goal is what the course is for, in your words: \"pass the B1 exam\", \"HR German for job applications\"; the tutors will read it later.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var levelSection: some View {
        Section {
            Picker("Level", selection: $levelRaw) {
                Text("Not set").tag("")
                ForEach(CEFRLevel.allCases) { level in
                    Text("\(level.rawValue) · \(level.englishLabel)").tag(level.rawValue)
                }
            }
        } header: {
            Text("Level").themedSectionHeader()
        } footer: {
            Text("The level the course is pitched at, if you know it.")
                .font(.caption2)
        }
        .themedListRow()
    }

    /// Weekdays in the calendar's order, Monday first where the locale starts there.
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private var scheduleSection: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(orderedWeekdays, id: \.self) { day in
                    let on = weekdays.contains(day)
                    Button {
                        if on { weekdays.remove(day) } else { weekdays.insert(day) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? Color.accentColor : Color.primary.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            Toggle("Start time", isOn: $hasTime.animation())
            if hasTime {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
            }
            Toggle("Next session on a set date", isOn: $hasNextSession.animation())
            if hasNextSession {
                DatePicker("Next session", selection: $nextSession, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
            }
        } header: {
            Text("Wann · When it meets").themedSectionHeader()
        } footer: {
            Text("With a schedule, Today helps you prepare the day before, review the same day, and brings up the questions you saved for the teacher.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var datesSection: some View {
        Section {
            Toggle("Has dates", isOn: Binding(
                get: { hasDates },
                set: { newValue in
                    datesTouched = true
                    withAnimation { hasDates = newValue }
                }
            ))
            if hasDates {
                DatePicker("Starts", selection: startBinding, displayedComponents: .date)
                Stepper(value: weeksBinding, in: 1...60) {
                    LabeledContent("Length", value: weeks == 1 ? "1 week" : "\(weeks) weeks")
                }
                HStack(spacing: 8) {
                    ForEach(Self.termPresets, id: \.weeks) { preset in
                        Button {
                            weeksBinding.wrappedValue = preset.weeks
                        } label: {
                            Text("\(preset.label) · \(preset.weeks)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.bordered)
                        .tint(weeks == preset.weeks ? .accentColor : .secondary)
                    }
                }
                DatePicker("Ends", selection: endBinding, in: startDate..., displayedComponents: .date)
            }
        } header: {
            Text("Dates").themedSectionHeader()
        } footer: {
            Text(hasDates
                 ? "Entries are labelled by week of the course (\"Woche 5\"). Set the length or the end date; the other follows."
                 : "A semester or quarter has dates; a tutor usually doesn't. With dates, entries are labelled by week.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // The start, the length and the end stay in step through these setters rather than
    // `onChange`, so only the learner's own edits move the others: loading a course whose end
    // falls mid-week must not "tidy" it to the end of that week.

    /// Moving the start keeps the length; the end moves with it.
    private var startBinding: Binding<Date> {
        Binding(get: { startDate }, set: { newStart in
            startDate = newStart
            endDate = ClassCourse.endDate(start: newStart, weeks: weeks, calendar: .current)
        })
    }

    private var weeksBinding: Binding<Int> {
        Binding(get: { weeks }, set: { newWeeks in
            weeks = newWeeks
            endDate = ClassCourse.endDate(start: startDate, weeks: newWeeks, calendar: .current)
        })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { endDate }, set: { newEnd in
            endDate = newEnd
            weeks = ClassCourse.weeks(start: startDate, end: newEnd, calendar: .current)
        })
    }

    /// Typical term lengths, one tap each. A quarter is about ten teaching weeks, a semester
    /// about fourteen; the stepper covers everything else.
    private static let termPresets: [(label: String, weeks: Int)] = [
        ("Quarter", 10),
        ("Semester", 14),
    ]

    private var skipSection: some View {
        Section {
            Button {
                dismiss()
                onSkip?()
            } label: {
                Label("Skip for now", systemImage: "arrow.forward.circle")
            }
        } footer: {
            Text("A plain \"Deutschkurs\" is set up for you; name it and pick its kind later from its page.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private var statusSection: some View {
        Section {
            Toggle("Finished", isOn: $isArchived)
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete course", systemImage: "trash")
            }
        } header: {
            Text("Status").themedSectionHeader()
        } footer: {
            Text("A finished course leaves the front page but keeps its notes and deck.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: - Load / save

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let course {
            name = course.name
            kind = course.kind
            teacher = course.teacher ?? ""
            teacherEmail = course.teacherEmail ?? ""
            courseURL = course.courseURL ?? ""
            goal = course.goal ?? ""
            levelRaw = course.levelRaw ?? ""
            hasDates = course.startDate != nil
            datesTouched = true
            startDate = course.startDate ?? Date()
            if let end = course.endDate {
                endDate = end
                weeks = ClassCourse.weeks(start: startDate, end: end, calendar: .current)
            } else {
                endDate = ClassCourse.endDate(start: startDate, weeks: weeks, calendar: .current)
            }
            isArchived = course.isArchived
            weekdays = course.meetingWeekdays
            hasTime = course.meetingMinutes >= 0
            if course.meetingMinutes >= 0 {
                time = Calendar.current.date(bySettingHour: course.meetingMinutes / 60, minute: course.meetingMinutes % 60,
                                             second: 0, of: .now) ?? time
            }
            hasNextSession = course.nextSessionAt.map { $0 >= Calendar.current.startOfDay(for: .now) } ?? false
            if let next = course.nextSessionAt { nextSession = next }
        } else {
            levelRaw = defaultLevel.rawValue
            kind = initialKind
            hasDates = initialKind == .course
            endDate = ClassCourse.endDate(start: startDate, weeks: weeks, calendar: .current)
            focused = .name
        }
    }

    private func save() {
        focused = nil
        let target: ClassCourse
        if let course {
            target = course
        } else {
            target = ClassCourse(name: trimmedName, kind: kind)
            target.sortOrder = (courses.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(target)
        }
        target.name = trimmedName
        target.kindRaw = kind.rawValue
        target.teacher = optional(teacher)
        target.teacherEmail = optional(teacherEmail)
        target.courseURL = optional(courseURL, cap: 2_000)
        target.goal = optional(goal)
        target.levelRaw = levelRaw.isEmpty ? nil : levelRaw
        target.startDate = hasDates ? Calendar.current.startOfDay(for: startDate) : nil
        target.endDate = hasDates ? Calendar.current.startOfDay(for: endDate) : nil
        target.isArchived = isArchived
        target.meetingWeekdays = weekdays
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        target.meetingMinutes = hasTime ? (parts.hour ?? 0) * 60 + (parts.minute ?? 0) : -1
        target.nextSessionAt = hasNextSession ? Calendar.current.startOfDay(for: nextSession) : nil
        target.updatedAt = .now
        try? modelContext.save()
        dismiss()
        onSaved(target)
    }

    private func deleteCourse() {
        guard let course else { return }
        ClassEntryStore.delete(course, context: modelContext)
        try? modelContext.save()
        dismiss()
        onDeleted()
    }

    private func optional(_ text: String, cap: Int = 120) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(cap))
    }
}

// MARK: - Preview

#Preview("Course editor · 4 themes") {
    ForEach(AppTheme.allCases) { theme in
        ClassCourseEditorView(course: nil, defaultLevel: .a2)
            .environment(\.appTheme, theme)
            .inMemoryModelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self])
    }
}
