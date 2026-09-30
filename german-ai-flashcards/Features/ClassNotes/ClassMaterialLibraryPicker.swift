//
//  ClassMaterialLibraryPicker.swift
//  german-ai-flashcards
//
//  The fourth door into a course: a text the app already has. A short story, a paper or a web
//  page, a photo scan, or the vocab sheet behind a document deck becomes a handout of the course,
//  filed under the entry the import sheet was opened for. It is a copy, so the handout's lookups,
//  translation and vocab list stay its own; `originIDRaw` remembers where it came from.
//
//  What comes along: a story's lookups (they are this learner's), and the deck that goes with the
//  text (a story's or paper's saved words, a document deck's cards) as the handout's vocab list,
//  put on the course too when no other course has it.
//

import SwiftUI
import SwiftData

struct ClassMaterialLibraryPicker: View {
    let course: ClassCourse
    let entry: ClassEntry
    var onAttached: (ClassMaterial) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \StudyStory.createdAt, order: .reverse) private var stories: [StudyStory]
    @Query(sort: \StudyPaper.createdAt, order: .reverse) private var papers: [StudyPaper]
    @Query(sort: \SavedDeck.createdAt, order: .reverse) private var decks: [SavedDeck]

    @State private var search = ""

    private let accent = ClassNotesTile.tint

    /// What this course already holds, by where it came from.
    private var onCourse: Set<UUID> { Set(course.materials.compactMap(\.originID)) }

    private func matches(_ title: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || title.localizedCaseInsensitiveContains(query)
    }

    private var readyStories: [StudyStory] {
        stories.filter { $0.generationComplete && !$0.storyText.isEmpty && matches($0.title) }
    }
    private var readPapers: [StudyPaper] {
        papers.filter { $0.sourceKind != .photo && !$0.fullText.isEmpty && matches($0.title) }
    }
    private var scans: [StudyPaper] {
        papers.filter { $0.sourceKind == .photo && !$0.fullText.isEmpty && matches($0.title) }
    }
    /// Document decks that kept their document (the ones made since decks began keeping it).
    private var vocabSheets: [SavedDeck] {
        decks.filter { $0.kind == .document && !($0.sourceText ?? "").isEmpty && matches($0.topic) }
    }

    private var isEmpty: Bool {
        readyStories.isEmpty && readPapers.isEmpty && scans.isEmpty && vocabSheets.isEmpty
    }

    var body: some View {
        List {
            if isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "Nothing to bring over yet" : "No match",
                    systemImage: "tray",
                    description: Text(search.isEmpty
                        ? "Short stories, papers, photo scans and the documents you make flashcards from show up here."
                        : "Nothing in the app is called that.")
                )
                .listRowBackground(Color.clear)
            }
            if !vocabSheets.isEmpty {
                Section {
                    ForEach(vocabSheets) { deck in
                        row(deck.topic,
                            "\(deck.cards.count) cards · \(ClassMaterial.SourceKind.forFile(deck.sourceFile).label)",
                            "doc.plaintext", id: deck.id) {
                            attach(ClassLibraryBridge.material(from: deck, course: course))
                        }
                    }
                } header: {
                    Text("Vokabellisten · Flashcard documents").themedSectionHeader()
                } footer: {
                    Text("Its cards come along as the handout's vocab list.")
                        .font(.caption2)
                }
                .themedListRow()
            }
            if !readyStories.isEmpty {
                Section {
                    ForEach(readyStories) { story in
                        row(story.title,
                            "\(story.level.rawValue) · \(story.createdAt.formatted(date: .abbreviated, time: .omitted))",
                            "book.pages", id: story.id) {
                            attach(ClassLibraryBridge.material(from: story, course: course))
                        }
                    }
                } header: {
                    Text("Geschichten · Short stories").themedSectionHeader()
                }
                .themedListRow()
            }
            if !readPapers.isEmpty {
                Section {
                    ForEach(readPapers) { paper in
                        row(paper.title, "\(paper.wordCount) Wörter", paper.sourceSymbol, id: paper.id) {
                            attach(ClassLibraryBridge.material(from: paper, course: course))
                        }
                    }
                } header: {
                    Text("Papers & links").themedSectionHeader()
                }
                .themedListRow()
            }
            if !scans.isEmpty {
                Section {
                    ForEach(scans) { paper in
                        row(paper.title, "\(paper.wordCount) Wörter", "camera", id: paper.id) {
                            attach(ClassLibraryBridge.material(from: paper, course: course))
                        }
                    }
                } header: {
                    Text("Photo scans").themedSectionHeader()
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .searchable(text: $search, prompt: "Search titles")
        .navigationTitle("From the app")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ subtitle: String, _ symbol: String, id: UUID,
                     action: @escaping () -> Void) -> some View {
        let added = onCourse.contains(id)
        return Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: appTheme.innerRadius(8)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).lineLimit(2)
                    Text(added ? "Already on \(course.name)" : subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(added ? AnyShapeStyle(.secondary) : AnyShapeStyle(accent))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
    }

    private func attach(_ material: ClassMaterial) {
        modelContext.insert(material)
        material.entry = entry
        entry.updatedAt = .now
        course.updatedAt = .now
        try? modelContext.save()
        onAttached(material)
    }
}

/// Turning something the app already has into a course handout. Each returns a new, unsaved
/// `ClassMaterial`; the caller files it under an entry.
@MainActor
enum ClassLibraryBridge {
    static func material(from story: StudyStory, course: ClassCourse) -> ClassMaterial {
        let material = ClassMaterial(title: story.title, text: story.storyText, sourceKind: .story)
        material.originIDRaw = story.id.uuidString
        // The words this learner looked up in the story are theirs here too.
        if !story.lookups.isEmpty { material.setLookups(story.lookups) }
        material.modelRaw = story.modelRaw
        adopt(deckID: story.deckID, for: material, course: course, in: story.modelContext)
        return material
    }

    static func material(from paper: StudyPaper, course: ClassCourse) -> ClassMaterial {
        let kind: ClassMaterial.SourceKind = switch paper.sourceKind {
        case .photo: .photo
        case .link: .link
        case .document: .pdf
        }
        let material = ClassMaterial(title: paper.title, text: JobPosting.cleanedText(paper.fullText), sourceKind: kind)
        material.originIDRaw = paper.id.uuidString
        material.modelRaw = paper.modelRaw
        adopt(deckID: paper.deckID, for: material, course: course, in: paper.modelContext)
        return material
    }

    /// A document deck's vocab sheet, with its own copy of the original: deleting the deck later
    /// must not take the handout's file with it.
    static func material(from deck: SavedDeck, course: ClassCourse) -> ClassMaterial {
        let material = ClassMaterial(
            title: deck.topic,
            text: JobPosting.cleanedText(deck.sourceText ?? ""),
            sourceKind: .forFile(deck.sourceFile)
        )
        material.originIDRaw = deck.id.uuidString
        if let file = deck.sourceFile, ClassMaterialStore.exists(file),
           let data = try? Data(contentsOf: ClassMaterialStore.url(for: file)) {
            material.snapshotFile = ClassMaterialStore.save(data, ext: (file as NSString).pathExtension)
        }
        adopt(deck, for: material, course: course)
        return material
    }

    /// The deck that goes with the text becomes the handout's vocab list, and joins the course
    /// unless another course already has it (a deck belongs to one course at a time).
    private static func adopt(deckID: UUID?, for material: ClassMaterial, course: ClassCourse, in context: ModelContext?) {
        guard let deckID, let context else { return }
        var descriptor = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == deckID })
        descriptor.fetchLimit = 1
        adopt(try? context.fetch(descriptor).first, for: material, course: course)
    }

    private static func adopt(_ deck: SavedDeck?, for material: ClassMaterial, course: ClassCourse) {
        guard let deck, !deck.cards.isEmpty else { return }
        material.glossaryDeckID = deck.id
        if deck.courseID == nil { deck.courseID = course.id }
    }
}

// MARK: - The way back

/// The courses each story, paper or deck was brought to as a handout, keyed by its id, for the
/// lists it lives in: "Deutsch A2", or "Deutsch A2, HR-Deutsch" when it went to two.
enum ClassMaterialOrigins {
    static func courseNames(_ handouts: [ClassMaterial]) -> [UUID: String] {
        var names: [UUID: [String]] = [:]
        for handout in handouts {
            guard let origin = handout.originID, let course = handout.entry?.course?.name else { continue }
            if names[origin]?.contains(course) != true { names[origin, default: []].append(course) }
        }
        return names.mapValues { $0.joined(separator: ", ") }
    }
}

/// "On Deutsch A2": where a story or paper went as a handout.
struct OnCourseLabel: View {
    let courses: String

    var body: some View {
        Label(courses, systemImage: "graduationcap.fill")
            .font(.caption2)
            .foregroundStyle(ClassNotesTile.tint)
            .lineLimit(1)
    }
}
