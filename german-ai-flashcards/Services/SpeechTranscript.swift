//
//  SpeechTranscript.swift
//  german-ai-flashcards
//
//  The learner's spoken turn as it builds up from a speech recognizer's results. Foundation
//  only and shared with the Android app (DieKarteiCore): iOS's `SpeechRecognitionService` and
//  Android's `AndroidSpeechInput` fold results through here, so a spoken turn reads the same on
//  both.
//

import Foundation

struct SpeechTranscript: Equatable {
    // On-device recognition resets its hypothesis after each pause/utterance, so finalized
    // utterances are accumulated here to keep the whole spoken turn.
    private(set) var committed = ""
    private(set) var current = ""

    /// The turn so far: every finished segment, then the one in progress.
    var text: String {
        [committed, current].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Accumulate recognizer output across utterance resets so the whole spoken turn is kept.
    ///
    /// Recognition emits a run of results per spoken segment: partial hypotheses
    /// (`isFinal == false`) that revise the *same* segment, then a final result (`isFinal == true`)
    /// when a pause ends it. Each result is the complete hypothesis for the *current* segment
    /// only (it resets after a pause), so finalized segments fold into `committed` and the
    /// in-progress one stays in `current`.
    ///
    /// Partials *revise* earlier words — e.g. "neue Hof" → "neue Koffer" — they don't only append.
    /// So the current segment is replaced wholesale rather than merged by prefix. A prefix merge
    /// mistook such a revision for a brand-new sentence and kept both, which produced the
    /// duplicated "…neue Hof …neue Koffer" transcripts.
    mutating func ingest(_ raw: String, isFinal: Bool) {
        let segment = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            commit(segment)
            current = ""
        } else if Self.isNewSegment(segment, replacing: current) {
            // A pause began a fresh segment without a final result — bank the previous one.
            commit(current)
            current = segment
        } else {
            // Same segment, revised hypothesis — replace it, never append.
            current = segment
        }
    }

    /// The turn with `mark` (e.g. "." or "?") ending it, for the learner marking sentence
    /// boundaries while speaking — it matters in German, where "?" vs "." changes the meaning.
    /// A mark the recognizer already put there is replaced rather than stacked ("Ich glaube." +
    /// "," → "Ich glaube,"). Nil when nothing has been said yet. The caller swaps in a fresh
    /// recognizer so the in-progress utterance isn't delivered (and appended) again.
    func punctuated(_ mark: String) -> SpeechTranscript? {
        var base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = base.last, ".,!?…".contains(last) {
            base.removeLast()
        }
        guard !base.isEmpty else { return nil }
        var next = SpeechTranscript()
        next.committed = base + mark
        return next
    }

    /// Fold a finished segment into the running committed transcript.
    private mutating func commit(_ segment: String) {
        guard !segment.isEmpty else { return }
        committed = committed.isEmpty ? segment : committed + " " + segment
    }

    /// Whether `next` is a brand-new segment rather than a revision of `current`. A fresh
    /// segment starts over from scratch, so it shares no leading words with the prior hypothesis;
    /// a revision keeps most of them. Comparing on shared *words* (not raw character prefix) means
    /// the recognizer rewording a word or two no longer reads as a new segment.
    static func isNewSegment(_ next: String, replacing current: String) -> Bool {
        guard !current.isEmpty, !next.isEmpty else { return false }
        let currentWords = current.lowercased().split(separator: " ")
        let nextWords = next.lowercased().split(separator: " ")
        let sharedLeadingWords = zip(currentWords, nextWords).prefix { $0.0 == $0.1 }.count
        return sharedLeadingWords == 0 && !next.hasPrefix(current) && !current.hasPrefix(next)
    }
}
