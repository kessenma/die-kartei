//
//  StoryStudyService+Prompt.swift
//  german-ai-flashcards
//
//  The story prompt, the TITEL:/GESCHICHTE: parser and the word count, kept free of MLX and
//  SwiftData so `training/kasus_cli` compiles the same prompt and parser the app sends and reads
//  (the Kasus story check parses through `parseStory`).
//

import Foundation

extension StoryStudyService {

    static func storyPrompt(topic: String, level: CEFRLevel, genre: StoryGenre, weaveWords: [String] = []) -> (system: String, user: String) {
        let system = """
        Du bist Autor von Lerngeschichten für Deutschlernende (Niveau \(level.rawValue)). \
        Schreibe eine kurze, in sich geschlossene Geschichte AUF DEUTSCH. \
        Antworte GENAU in diesem Format, ohne weitere Erklärungen:
        TITEL: <kurzer Titel>
        GESCHICHTE:
        <die Geschichte, in Absätze gegliedert>
        """
        var user = """
        Thema: \(topic)
        \(genre.promptInstruction)
        Länge: \(level.storyWordRange.lowerBound)–\(level.storyWordRange.upperBound) Wörter.
        \(level.storyConstraints)
        """
        if !weaveWords.isEmpty {
            user += "\nBaue einige dieser Wörter natürlich in die Geschichte ein: \(weaveWords.joined(separator: ", "))."
        }
        return (system, user)
    }

    /// Split raw output into title and body via the TITEL:/GESCHICHTE: markers, tolerating
    /// output that skips them entirely.
    static func parseStory(_ raw: String) -> (title: String?, text: String) {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        var title: String?
        var bodyLines: [String] = []
        var inBody = false

        for line in cleaned.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if !inBody, upper.hasPrefix("TITEL:") {
                title = String(trimmed.dropFirst("TITEL:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if !inBody, upper.hasPrefix("GESCHICHTE:") {
                inBody = true
                let rest = String(trimmed.dropFirst("GESCHICHTE:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { bodyLines.append(rest) }
                continue
            }
            if inBody {
                bodyLines.append(line)
            } else if !trimmed.isEmpty, title != nil {
                // Title seen but no GESCHICHTE marker — everything after the title is body.
                inBody = true
                bodyLines.append(line)
            } else if !trimmed.isEmpty {
                // No markers at all — treat the whole output as body.
                inBody = true
                bodyLines.append(line)
            }
        }

        var text = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        if var t = title {
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "*#_\"„“» «"))
            title = t.isEmpty ? nil : t
        }
        return (title, text)
    }

    static func wordCount(of text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
