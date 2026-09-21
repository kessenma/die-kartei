import Foundation
import SwiftData

/// Builds the word inspector the job-posting reader uses on every surface: double-tapped words
/// are translated 1:1 by the tutor, remembered with the posting, and can be saved into the
/// posting's own deck. The job twin of `StoryWordInspector`.
enum JobWordInspector {
    /// `model` is the tutor the lookups run on; `feedsCoach` gates the learner-profile hand-off;
    /// `onSaved` lets the caller count saves against the current session.
    @MainActor
    static func make(
        posting: JobPosting,
        mlxService: MLXGenerationService,
        model: MLXModel,
        feedsCoach: Bool = true,
        onSaved: @escaping () -> Void = {},
        context: ModelContext
    ) -> WordInspectorModel {
        let inspector = WordInspectorModel(
            mlxService: mlxService,
            model: model,
            isWordSaved: { word in JobDeckStore.isWordSaved(word, posting: posting, context: context) },
            onSave: { german, english in
                JobDeckStore.saveWord(
                    german: german, english: english, posting: posting,
                    feedsCoach: feedsCoach, context: context
                )
                onSaved()
            },
            // Every word the model had to translate is kept with the posting, so it's listed under
            // "Unbekannte Wörter", marked in the text, and answered without a model load next time.
            onLookup: { german, english in
                posting.recordLookup(german: german, english: english)
                if posting.modelRaw == nil { posting.modelRaw = model.rawValue }
                try? context.save()
            }
        )
        inspector.knownTranslations = knownTranslations(for: posting)
        return inspector
    }

    /// Everything a double-tap can be answered with without the model: every word already looked
    /// up in this posting, which survives app restarts.
    static func knownTranslations(for posting: JobPosting) -> [String: KnownTranslation] {
        var known: [String: KnownTranslation] = [:]
        for entry in posting.lookups where known[entry.german.lowercased()] == nil {
            known[entry.german.lowercased()] = KnownTranslation(
                german: entry.german, english: entry.english, source: .earlierLookup
            )
        }
        return known
    }
}
