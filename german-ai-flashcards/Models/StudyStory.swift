import Foundation
import SwiftData

// MARK: - Question

/// One comprehension question generated for a story. `kind` decides the answer surface:
/// option buttons, a typed blank, or a written answer graded by the model.
nonisolated struct StoryQuestion: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case multipleChoice
        case fillInBlank
        case fillInBlankChoices
        case freeResponse

        var id: String { rawValue }

        var label: String {
            switch self {
            case .multipleChoice: "Multiple choice"
            case .fillInBlank: "Fill in the blank"
            case .fillInBlankChoices: "Blank with choices"
            case .freeResponse: "Free response"
            }
        }

        var detail: String {
            switch self {
            case .multipleChoice: "Pick the right answer from three options."
            case .fillInBlank: "Type the missing word in a story sentence."
            case .fillInBlankChoices: "Pick the missing word from three options."
            case .freeResponse: "Write an answer in German; the AI grades it."
            }
        }
    }

    var kind: Kind
    /// The question text — for the blank kinds, a story sentence containing ______.
    var question: String
    /// Answer options for the choice kinds; empty otherwise.
    var options: [String]
    /// Index into `options` of the right answer, for the choice kinds.
    var correctIndex: Int?
    /// The blank's solution word, the Musterantwort for free response, or the correct
    /// option's text for the choice kinds (kept for the reveal/missed list).
    var answer: String?
    /// The story sentence that proves the answer — shown after answering ("Im Text: …").
    var evidence: String?

    var id: String { kind.rawValue + "|" + question }
}

// MARK: - Glossary

/// A hard word from the story with its English meaning, shown under the text.
nonisolated struct GlossaryEntry: Codable, Hashable, Identifiable {
    var german: String
    var english: String
    var id: String { german.lowercased() }
}

// MARK: - Genre

/// Optional story flavor; each maps to a prompt instruction. E-Mail/Brief doubles as
/// Schreiben-exam format exposure. Raw values are stable identifiers persisted on saved
/// stories — never rename an existing one; only append new cases.
enum StoryGenre: String, CaseIterable, Codable, Identifiable {
    case alltag = "Alltag"
    case dialog = "Dialog"
    case brief = "E-Mail"
    case krimi = "Krimi"
    case maerchen = "Märchen"
    case abenteuer = "Abenteuer"
    case romanze = "Romanze"
    case scifi = "SciFi"
    case comedy = "Comedy"
    case tagebuch = "Tagebuch"
    case fabel = "Fabel"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alltag: "Everyday scene"
        case .dialog: "Dialogue"
        case .brief: "E-Mail exchange"
        case .krimi: "Mini mystery"
        case .maerchen: "Fairy tale"
        case .abenteuer: "Adventure"
        case .romanze: "Romance"
        case .scifi: "Sci-fi"
        case .comedy: "Comedy"
        case .tagebuch: "Diary entry"
        case .fabel: "Fable"
        }
    }

    /// True for formats where each line/turn is spoken by a named person — these get the
    /// speaker-prefix instruction and drive two-voice playback in listening mode.
    var hasNamedSpeakers: Bool {
        self == .dialog || self == .brief
    }

    var promptInstruction: String {
        switch self {
        case .alltag:
            "Schreibe eine Alltagsgeschichte: eine realistische Szene aus dem täglichen Leben."
        case .dialog:
            "Schreibe die Geschichte überwiegend als Dialog zwischen zwei Personen mit deutschen Vornamen. Beginne JEDE Sprechzeile mit dem Namen der sprechenden Person und einem Doppelpunkt, z. B. „Lena: Hallo, wie geht es dir?“ — genau eine Sprechzeile pro Zeile."
        case .brief:
            "Schreibe die Geschichte als kurzen E-Mail-Wechsel zwischen zwei Personen mit deutschen Vornamen, mit Anrede und Gruß. Beginne JEDE Nachricht mit dem Namen des Absenders und einem Doppelpunkt, z. B. „Kyle: Liebe Marie, …“."
        case .krimi:
            "Schreibe eine kleine Krimi-Geschichte mit einem Rätsel, das sich am Ende auflöst."
        case .maerchen:
            "Schreibe die Geschichte im Stil eines kurzen Märchens."
        case .abenteuer:
            "Schreibe eine spannende Abenteuergeschichte mit einer Reise oder einer mutigen Aufgabe."
        case .romanze:
            "Schreibe eine leichte, warmherzige Liebesgeschichte über zwei Menschen, die sich näherkommen."
        case .scifi:
            "Schreibe eine kurze Science-Fiction-Geschichte in der Zukunft oder im Weltraum, mit einer einfachen, klaren Idee."
        case .comedy:
            "Schreibe eine humorvolle, lustige Geschichte mit einem komischen Missverständnis oder einer witzigen Situation."
        case .tagebuch:
            "Schreibe die Geschichte als persönlichen Tagebucheintrag in der Ich-Form, mit Datum und ehrlichen Gedanken."
        case .fabel:
            "Schreibe eine kurze Fabel mit sprechenden Tieren und einer klaren Moral am Ende."
        }
    }
}

// MARK: - Speaker

/// One named speaker in a dialogue/e-mail story, with an inferred voice role. Used to assign
/// distinct TTS voices per speaker in listening mode; populated only for `hasNamedSpeakers` genres.
nonisolated struct StorySpeaker: Codable, Hashable, Identifiable {
    /// Voice role the character maps to — the learner sets one downloaded voice per role.
    enum Role: String, Codable, CaseIterable {
        case male, female, boy, girl
    }

    /// The name exactly as it prefixes the character's lines ("Kyle" in "Kyle: …").
    var name: String
    var role: Role
    var id: String { name.lowercased() }
}

// MARK: - Illustration

/// One generated illustration for a story. The PNG lives on disk under
/// `StoryImageStore.directory(for: story.id)`; this record is what's persisted on the story.
nonisolated struct StoryImageRecord: Codable, Hashable, Identifiable {
    /// File name within the story's image directory ("00.png", "01.png", …).
    var fileName: String
    /// The full positive Stable Diffusion prompt that produced the image, for provenance.
    var prompt: String
    /// Which paragraph the image follows in the read view; nil = the header/hero image.
    var paragraphAnchorIndex: Int?
    var id: String { fileName }
}

// MARK: - Story

/// An AI-written German short story with comprehension questions — reading/listening practice
/// in the shape of the Goethe exams' Lesen/Hören sections. Always generated in German;
/// `englishText` is an on-demand translation the learner can reveal, never the source.
@Model
final class StudyStory {
    var id: UUID
    var createdAt: Date
    /// Model-generated German title (falls back to the topic).
    var title: String
    /// What the learner asked for.
    var topic: String
    /// `CEFRLevel` raw value the story was written at.
    var levelRaw: String
    /// `StoryGenre` raw value.
    var genreRaw: String?
    var storyText: String
    /// Cached English translation, generated once on first reveal.
    var englishText: String?
    /// Encoded `[GlossaryEntry]`.
    var glossaryData: Data?
    /// Encoded `[StoryQuestion]`.
    var questionsData: Data?
    /// Encoded `[StorySpeaker]` — the named speakers of a dialogue/e-mail story and their
    /// voice roles, used to assign per-speaker TTS voices. Nil for narrative genres.
    var speakersData: Data?
    /// Encoded `[StoryImageRecord]` — generated illustrations, if the learner asked for them.
    var imagesData: Data?
    /// Encoded `[GlossaryEntry]` — words the learner double-tapped while reading, in the surface
    /// form the story uses them in. Kept per story so the words this reader personally stumbled
    /// over are listed under the glossary, marked in the text, and answer a second tap straight
    /// from here instead of pulling the model back into memory.
    var lookupsData: Data?
    /// The model that wrote the story (the hero, but stored like `StudyPaper.modelRaw`).
    var modelRaw: String?
    /// Linked deck of words saved while reading (`SavedDeck.id`), created on first save.
    var deckIDRaw: String?
    /// True once story + questions + glossary finished generating.
    var generationComplete: Bool
    /// Best quiz score in percent, for the list row.
    var bestScore: Int?
    /// True when the last study session used listening mode (labels results/rows).
    var lastStudiedAsListening: Bool

    init(topic: String, level: CEFRLevel, genre: StoryGenre, createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.title = topic
        self.topic = topic
        self.levelRaw = level.rawValue
        self.genreRaw = genre.rawValue
        self.storyText = ""
        self.englishText = nil
        self.glossaryData = nil
        self.questionsData = nil
        self.speakersData = nil
        self.imagesData = nil
        self.lookupsData = nil
        self.modelRaw = nil
        self.deckIDRaw = nil
        self.generationComplete = false
        self.bestScore = nil
        self.lastStudiedAsListening = false
    }

    var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .a2 }
    var genre: StoryGenre { genreRaw.flatMap { StoryGenre(rawValue: $0) } ?? .alltag }
    var model: MLXModel? { modelRaw.flatMap { MLXModel(rawValue: $0) } }

    var questions: [StoryQuestion] {
        guard let questionsData else { return [] }
        return (try? JSONDecoder().decode([StoryQuestion].self, from: questionsData)) ?? []
    }

    func setQuestions(_ questions: [StoryQuestion]) {
        questionsData = try? JSONEncoder().encode(questions)
    }

    var glossary: [GlossaryEntry] {
        guard let glossaryData else { return [] }
        return (try? JSONDecoder().decode([GlossaryEntry].self, from: glossaryData)) ?? []
    }

    func setGlossary(_ entries: [GlossaryEntry]) {
        glossaryData = try? JSONEncoder().encode(entries)
    }

    var speakers: [StorySpeaker] {
        guard let speakersData else { return [] }
        return (try? JSONDecoder().decode([StorySpeaker].self, from: speakersData)) ?? []
    }

    func setSpeakers(_ speakers: [StorySpeaker]) {
        speakersData = try? JSONEncoder().encode(speakers)
    }

    var images: [StoryImageRecord] {
        guard let imagesData else { return [] }
        return (try? JSONDecoder().decode([StoryImageRecord].self, from: imagesData)) ?? []
    }

    func setImages(_ records: [StoryImageRecord]) {
        imagesData = try? JSONEncoder().encode(records)
    }

    /// Words looked up while reading this story, newest first.
    var lookups: [GlossaryEntry] {
        guard let lookupsData else { return [] }
        return (try? JSONDecoder().decode([GlossaryEntry].self, from: lookupsData)) ?? []
    }

    func setLookups(_ entries: [GlossaryEntry]) {
        lookupsData = try? JSONEncoder().encode(entries)
    }

    /// Record a word the learner looked up. Case-insensitively deduplicated on the German form, with
    /// a repeat lookup moving back to the top — the list stays "what I needed help with here",
    /// not a tally.
    func recordLookup(german: String, english: String) {
        let trimmed = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !english.isEmpty else { return }
        var entries = lookups.filter { $0.german.caseInsensitiveCompare(trimmed) != .orderedSame }
        entries.insert(GlossaryEntry(german: trimmed, english: english), at: 0)
        setLookups(entries)
    }

    /// The hero image shown in the story header, if one was generated.
    var headerImage: StoryImageRecord? {
        images.first { $0.paragraphAnchorIndex == nil }
    }

    /// The picture that stands for the story in a list. Normally the header image — the header is
    /// slot 0, so it's the one image every illustrated story has — but it falls back to the first
    /// inline picture, so "has a picture" and "shows a picture" can't disagree when the header slot
    /// is the one that failed to render.
    var coverImage: StoryImageRecord? {
        let all = images
        return all.first { $0.paragraphAnchorIndex == nil } ?? all.first
    }

    var deckID: UUID? {
        get { deckIDRaw.flatMap { UUID(uuidString: $0) } }
        set { deckIDRaw = newValue?.uuidString }
    }

    /// Approximate word count, for the list display.
    var wordCount: Int {
        storyText.split { $0 == " " || $0 == "\n" }.count
    }
}

// MARK: - Per-level story shape

extension CEFRLevel {
    /// Target story length in words — roughly the reading-text lengths of the level's exam.
    var storyWordRange: ClosedRange<Int> {
        switch self {
        case .a1: 80...120
        case .a2: 120...180
        case .b1: 200...280
        case .b2: 300...400
        case .c1: 400...550
        }
    }

    /// Hard constraints injected into the story prompt. The CEFR label alone doesn't hold a
    /// small model at level; tense whitelists and sentence caps do.
    var storyConstraints: String {
        switch self {
        case .a1:
            "Benutze NUR Präsens. Nur Hauptsätze, maximal 8 Wörter pro Satz. Benutze nur sehr häufige, einfache Wörter."
        case .a2:
            "Benutze Präsens und Perfekt. Kurze Sätze (maximal 12 Wörter); Nebensätze mit weil/dass sind erlaubt. Einfacher Alltagswortschatz."
        case .b1:
            "Benutze Präsens, Perfekt und Präteritum für die Erzählung. Alltagswortschatz und klare Satzstrukturen."
        case .b2:
            "Natürliches Deutsch mit abwechslungsreichen Satzstrukturen; Konjunktiv II und Meinungen sind willkommen."
        case .c1:
            "Natürliche, idiomatische Prosa mit komplexen Strukturen, Nuancen und impliziter Bedeutung."
        }
    }

    /// Output budget for the story call, sized to `storyWordRange` plus format overhead.
    var storyMaxTokens: Int {
        switch self {
        case .a1: 400
        case .a2: 550
        case .b1: 800
        case .b2: 1100
        case .c1: 1400
        }
    }
}
