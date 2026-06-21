import Foundation
import SwiftData

/// A comprehension question generated from a study paper (German question + optional model answer).
nonisolated struct StudyQuestion: Codable, Hashable, Identifiable {
    var question: String
    var answer: String?
    var id: String { question }
}

/// A German paper the learner uploaded to study and discuss with the AI.
@Model
final class StudyPaper {
    var id: UUID
    var title: String
    var createdAt: Date
    /// Full extracted text from the PDF or web page.
    var fullText: String
    /// Set when the source was a URL (vs. a PDF).
    var sourceURL: String?
    /// Condensed German summary used as the AI's reference during the discussion.
    var germanSummary: String?
    /// German key points (bullet list).
    var keyPoints: [String]
    /// Encoded `[StudyQuestion]`.
    var questionsData: Data?
    /// Linked generated vocab deck (`SavedDeck.id`), if one was created.
    var deckIDRaw: String?
    /// The model used to generate the study materials (and to discuss the paper).
    var modelRaw: String?
    /// True once summary/cards/questions finished generating.
    var generationComplete: Bool

    init(title: String, fullText: String, sourceURL: String? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.fullText = fullText
        self.sourceURL = sourceURL
        self.germanSummary = nil
        self.keyPoints = []
        self.questionsData = nil
        self.deckIDRaw = nil
        self.modelRaw = nil
        self.generationComplete = false
    }

    var model: MLXModel? { modelRaw.flatMap { MLXModel(rawValue: $0) } }

    var questions: [StudyQuestion] {
        guard let questionsData else { return [] }
        return (try? JSONDecoder().decode([StudyQuestion].self, from: questionsData)) ?? []
    }

    func setQuestions(_ questions: [StudyQuestion]) {
        questionsData = try? JSONEncoder().encode(questions)
    }

    var deckID: UUID? {
        get { deckIDRaw.flatMap { UUID(uuidString: $0) } }
        set { deckIDRaw = newValue?.uuidString }
    }

    /// Approximate word count, for the list display.
    var wordCount: Int {
        fullText.split { $0 == " " || $0 == "\n" }.count
    }

    /// The reference text injected into the conversation (summary + key points, or a text excerpt).
    var conversationContext: String {
        if let germanSummary, !germanSummary.isEmpty {
            var context = germanSummary
            if !keyPoints.isEmpty {
                context += "\n\nKernpunkte:\n" + keyPoints.map { "- \($0)" }.joined(separator: "\n")
            }
            return context
        }
        // Fallback to a leading excerpt if no summary was generated.
        return String(fullText.prefix(2000))
    }
}

// MARK: - Source kind & branding

extension StudyPaper {
    /// How this paper was imported, inferred from `sourceURL`.
    enum SourceKind { case photo, link, document }

    var sourceKind: SourceKind {
        if sourceURL?.hasPrefix("photo://") == true { return .photo }
        if sourceURL != nil { return .link }
        return .document
    }

    /// SF Symbol representing the import source (photo / web link / document).
    var sourceSymbol: String {
        switch sourceKind {
        case .photo: "camera"
        case .link: "link"
        case .document: "doc.text"
        }
    }

    /// Brand theme of the model that generated this paper, when known.
    var rowTheme: ModelTheme? { model?.theme }
}
