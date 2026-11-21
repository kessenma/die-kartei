//
//  WritingSentences.swift
//  german-ai-flashcards
//
//  The pure text side of the Schreiben room: splitting a piece of writing into the sentences
//  the tutor judges one by one, guessing which language a sentence is in (a Tagebuch entry may
//  be English, German or both), and counting words the way the target lengths count them.
//
//  The splitter is deliberately plain. It knows the abbreviations German learners actually
//  write ("z.B.", "usw.", "Dr.") and keeps „quoted speech.“ inside its sentence; anything
//  cleverer would be guessing about prose the learner has not written yet.
//

import Foundation

nonisolated enum WritingSentences {

    enum Language: Equatable {
        case german, english
        /// Neither side clearly ahead, or too short to tell.
        case mixed
    }

    /// Abbreviations whose period does not end a sentence. Lowercased, without the final dot.
    static let abbreviations: Set<String> = [
        "z.b", "d.h", "u.a", "usw", "bzw", "ca", "dr", "nr", "str", "prof", "evtl", "vgl", "etc",
        "bsp", "ggf", "inkl", "max", "min", "mio", "mrd", "tel", "s", "u", "o.ä", "z.t", "a", "b",
        "mr", "mrs", "ms", "st", "vs", "e.g", "i.e",
    ]

    /// The text as sentences, in order, trimmed, with no empty ones. A newline ends a sentence
    /// too: a line of a diary is its own thought even without a full stop.
    static func split(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let scalars = Array(text)
        var i = 0
        while i < scalars.count {
            let ch = scalars[i]
            if ch.isNewline {
                flush(&current, into: &out)
                i += 1
                continue
            }
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                // Collapse "?!" / "..." into the same sentence.
                var j = i + 1
                while j < scalars.count, scalars[j] == "." || scalars[j] == "!" || scalars[j] == "?" {
                    current.append(scalars[j])
                    j += 1
                }
                // A closing quote or bracket right after the stop belongs to the sentence.
                while j < scalars.count, "“\"”»«)’'".contains(scalars[j]) {
                    current.append(scalars[j])
                    j += 1
                }
                i = j
                if ch == "." && isAbbreviationEnd(current) {
                    continue
                }
                // A number like "3.5" or an ordinal date "am 3. Mai" is not a sentence end.
                if ch == "." && continuesNumber(current, next: j < scalars.count ? scalars[j] : nil, scalars: scalars, at: j) {
                    continue
                }
                // What follows must look like a new sentence: whitespace then an uppercase
                // letter, a digit, an opening quote, or the end of the text.
                if looksLikeSentenceStart(scalars, from: j) {
                    flush(&current, into: &out)
                }
                continue
            }
            i += 1
        }
        flush(&current, into: &out)
        return out
    }

    private static func flush(_ current: inout String, into out: inout [String]) {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { out.append(trimmed) }
        current = ""
    }

    /// The word just before the final period is a known abbreviation ("z.B." / "usw.").
    private static func isAbbreviationEnd(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: CharacterSet(charactersIn: "“\"”»«)’' "))
        guard trimmed.hasSuffix(".") else { return false }
        let body = trimmed.dropLast()
        let lastWord = body.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        let lowered = lastWord.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "(„\""))
        if abbreviations.contains(lowered) { return true }
        // A single capital letter with a period: an initial ("J. Müller").
        if lowered.count == 1, lastWord.first?.isLetter == true { return true }
        return false
    }

    static let months: Set<String> = [
        "januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober",
        "november", "dezember", "jänner", "jan", "feb", "mär", "apr", "jun", "jul", "aug", "sep", "sept",
        "okt", "nov", "dez",
    ]

    /// "3." followed by a space and a lowercase word, a month ("am 3. Mai"), or "3.5" followed
    /// directly by a digit: an ordinal or a decimal, not a sentence end.
    private static func continuesNumber(_ sentence: String, next: Character?, scalars: [Character], at j: Int) -> Bool {
        guard let lastBeforeDot = sentence.dropLast().last, lastBeforeDot.isNumber else { return false }
        guard let next else { return false }
        if next.isNumber { return true }
        if next.isWhitespace {
            var k = j
            while k < scalars.count, scalars[k].isWhitespace { k += 1 }
            guard k < scalars.count else { return false }
            if scalars[k].isLowercase { return true }
            var word = ""
            while k < scalars.count, scalars[k].isLetter { word.append(scalars[k]); k += 1 }
            if months.contains(word.lowercased()) { return true }
        }
        return false
    }

    private static func looksLikeSentenceStart(_ scalars: [Character], from j: Int) -> Bool {
        guard j < scalars.count else { return true }
        guard scalars[j].isWhitespace else { return false }
        var k = j
        while k < scalars.count, scalars[k].isWhitespace { k += 1 }
        guard k < scalars.count else { return true }
        let c = scalars[k]
        return c.isUppercase || c.isNumber || "„\"“«»(".contains(c)
    }

    // MARK: - Words

    /// Words as a target length counts them: runs of letters or digits, apostrophes and hyphens
    /// inside a word kept ("gibt's", "E-Mail" are one word each).
    static func words(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if (ch == "'" || ch == "’" || ch == "-") && !current.isEmpty {
                current.append(ch)
            } else if !current.isEmpty {
                out.append(current.trimmingCharacters(in: CharacterSet(charactersIn: "'’-")))
                current = ""
            }
        }
        if !current.isEmpty { out.append(current.trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))) }
        return out.filter { !$0.isEmpty }
    }

    static func wordCount(_ text: String) -> Int { words(in: text).count }

    // MARK: - Language

    /// Short, frequent words that are unmistakably one language or the other.
    static let germanMarkers: Set<String> = [
        "der", "die", "das", "und", "ist", "nicht", "ich", "du", "wir", "ihr", "sie", "es", "ein",
        "eine", "einen", "einem", "einer", "mit", "auf", "für", "von", "zu", "im", "am", "beim",
        "habe", "hat", "haben", "bin", "sind", "war", "waren", "wird", "werden", "kann", "muss",
        "aber", "auch", "noch", "schon", "sehr", "heute", "gestern", "morgen", "dem", "den", "des",
        "mein", "meine", "dein", "sein", "wenn", "weil", "dass", "oder", "als", "nach", "über",
        "doch", "mal", "ja", "nein", "gut", "viel", "immer", "dann", "mich", "mir", "dich", "dir",
        "uns", "euch", "ihn", "ihm", "ihnen", "nur", "jetzt", "hier", "dort", "wieder", "nie", "oft",
        "etwas", "nichts", "kein", "keine", "wo", "wer", "wie", "warum", "ob", "denn", "bei", "aus",
        "seit", "bis", "durch", "ohne", "gegen", "um", "vor", "unter", "zwischen",
    ]

    /// Words that are English and not also German ("in", "an", "also", "war" are both, so they
    /// stay out of either list).
    static let englishMarkers: Set<String> = [
        "the", "and", "is", "not", "i", "you", "we", "they", "it", "a", "with", "on", "for",
        "of", "to", "at", "have", "has", "had", "am", "are", "were", "will", "would",
        "can", "must", "but", "still", "already", "very", "today", "yesterday", "tomorrow",
        "my", "your", "his", "her", "their", "if", "because", "that", "or", "than", "after", "about",
        "really", "just", "yes", "no", "good", "much", "always", "then", "this", "when", "what",
        "keep", "up", "out", "do", "did", "does", "get", "got", "make", "made", "think", "know",
        "like", "want", "need", "feel", "say", "said", "too", "more", "some", "any", "how", "why",
        "where", "who", "there", "here", "which", "while", "though", "again", "every", "never",
        "often", "sometimes", "me", "him", "them", "us", "its", "our", "myself", "been", "being",
    ]

    /// Which language a sentence is written in, from its function words. Umlauts or ß settle
    /// it for German on their own.
    static func guessLanguage(_ sentence: String) -> Language {
        let lowered = sentence.lowercased()
        if lowered.contains(where: { "äöüß".contains($0) }) { return .german }
        let tokens = words(in: lowered)
        guard !tokens.isEmpty else { return .mixed }
        var de = 0, en = 0
        for token in tokens {
            if germanMarkers.contains(token) { de += 1 }
            if englishMarkers.contains(token) { en += 1 }
        }
        if de == 0 && en == 0 {
            // No markers at all: a German noun phrase or a name. Capitalised words inside the
            // sentence lean German (nouns), otherwise undecided.
            let inner = words(in: sentence).dropFirst()
            let capitalised = inner.filter { $0.first?.isUppercase == true }.count
            return capitalised >= 1 && inner.count >= 2 ? .german : .mixed
        }
        if de > en { return .german }
        if en > de { return .english }
        return .mixed
    }
}
