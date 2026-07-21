import Foundation

/// Turns a story's text into ordered `SpeechService.Segment`s for playback, keeping each segment's
/// UTF-16 offset into the full story so read-along highlighting and "start from here" line up.
///
/// Two granularities:
///  • `.line`     — one segment per line (dialogue/e-mail) or the whole text (narrative). Used by
///                  the inline listen control, matching the original behavior.
///  • `.sentence` — one segment per sentence, so the follow-along player can highlight, auto-scroll,
///                  skip, and start playback sentence by sentence.
///
/// For dialogue/e-mail genres each speaker keeps its own voice (from the story's roster, falling
/// back to the role voices by first appearance); narrative genres read in the app's selected voice.
enum StorySpeechSegmenter {
    enum Granularity { case line, sentence }

    static func segments(
        for story: StudyStory,
        modelManager: MLXModelManager,
        granularity: Granularity
    ) -> [SpeechService.Segment] {
        let text = story.storyText
        let ns = text as NSString
        guard ns.length > 0 else { return [] }

        // Narrative: single voice (nil → the app's selected voice at speak time).
        guard story.genre.hasNamedSpeakers else {
            switch granularity {
            case .line:
                return [SpeechService.Segment(text: text)]
            case .sentence:
                return sentenceSegments(in: text, range: NSRange(location: 0, length: ns.length), voiceIdentifier: nil)
            }
        }

        // Dialogue/e-mail: resolve a voice per speaker, roster first then role-ordered fallbacks.
        var voiceByName: [String: String?] = [:]
        for speaker in story.speakers {
            voiceByName[speaker.name.lowercased()] = modelManager.voiceIdentifier(for: speaker.role)
        }
        let fallbacks: [String?] = [
            modelManager.voiceMaleIdentifier, modelManager.voiceFemaleIdentifier,
            modelManager.voiceBoyIdentifier, modelManager.voiceGirlIdentifier,
        ].map { $0 ?? modelManager.selectedVoiceIdentifier }
        var nextFallback = 0

        func voice(for name: String) -> String? {
            let key = name.lowercased()
            if let known = voiceByName[key] { return known }
            let assigned = fallbacks[nextFallback % fallbacks.count]
            nextFallback += 1
            voiceByName[key] = assigned
            return assigned
        }

        var segments: [SpeechService.Segment] = []
        var offset = 0
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let lineLength = (line as NSString).length
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let voiceID = speakerName(in: line).map { voice(for: $0) } ?? nil
                switch granularity {
                case .line:
                    segments.append(SpeechService.Segment(text: line, voiceIdentifier: voiceID, rangeOffset: offset))
                case .sentence:
                    segments.append(contentsOf: sentenceSegments(
                        in: text,
                        range: NSRange(location: offset, length: lineLength),
                        voiceIdentifier: voiceID
                    ))
                }
            }
            offset += lineLength + (index < lines.count - 1 ? 1 : 0) // account for the split "\n"
        }
        return segments.isEmpty ? [SpeechService.Segment(text: text)] : segments
    }

    /// Split `range` of `fullText` into sentence segments, each tagged with `voiceIdentifier` and its
    /// true offset in the full string (so highlight ranges reported back land in the right place).
    private static func sentenceSegments(
        in fullText: String,
        range: NSRange,
        voiceIdentifier: String?
    ) -> [SpeechService.Segment] {
        let ns = fullText as NSString
        var result: [SpeechService.Segment] = []
        ns.enumerateSubstrings(in: range, options: .bySentences) { sub, subRange, _, _ in
            guard let sub, !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(SpeechService.Segment(text: sub, voiceIdentifier: voiceIdentifier, rangeOffset: subRange.location))
        }
        // Fall back to the whole range if the tokenizer produced nothing (e.g. no terminal punctuation).
        if result.isEmpty {
            let sub = ns.substring(with: range)
            if !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(SpeechService.Segment(text: sub, voiceIdentifier: voiceIdentifier, rangeOffset: range.location))
            }
        }
        return result
    }

    /// The speaker label of a `Name: …` line, or nil for narration. Lenient (a short, letters-only
    /// prefix before the first colon) since it only runs on dialogue/e-mail stories.
    static func speakerName(in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let prefix = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
        guard (1...30).contains(prefix.count), prefix.first?.isLetter == true else { return nil }
        let allowed = prefix.allSatisfy { $0.isLetter || $0.isWhitespace || $0 == "-" || $0 == "." || $0 == "'" }
        return allowed ? prefix : nil
    }
}
