import Foundation
import SwiftData

/// Builds the word inspector the handout reader uses: double-tapped words are translated 1:1 by
/// the tutor, remembered with the handout, and can be saved into the course's deck. The class twin
/// of `JobWordInspector`.
enum ClassWordInspector {
    /// `model` is the tutor the lookups run on; `feedsCoach` gates the learner-profile hand-off;
    /// `onSaved` lets the caller count saves.
    @MainActor
    static func make(
        material: ClassMaterial,
        course: ClassCourse?,
        mlxService: MLXGenerationService,
        model: MLXModel,
        feedsCoach: Bool = true,
        onSaved: @escaping () -> Void = {},
        context: ModelContext
    ) -> WordInspectorModel {
        let inspector = WordInspectorModel(
            mlxService: mlxService,
            model: model,
            isWordSaved: { word in
                guard let course else { return false }
                return ClassDeckStore.isWordSaved(word, course: course, context: context)
            },
            onSave: { german, english in
                guard let course else { return }
                ClassDeckStore.saveWord(
                    german: german, english: english, course: course,
                    feedsCoach: feedsCoach, context: context
                )
                onSaved()
            },
            // Every word the model had to translate is kept with the handout, so it's listed under
            // "Unbekannte Wörter", marked in the text, and answered without a model load next time.
            onLookup: { german, english in
                material.recordLookup(german: german, english: english)
                if material.modelRaw == nil { material.modelRaw = model.rawValue }
                try? context.save()
            }
        )
        inspector.knownTranslations = knownTranslations(for: material)
        return inspector
    }

    /// Everything a double-tap can be answered with without the model: every word already looked
    /// up in this handout, which survives app restarts.
    static func knownTranslations(for material: ClassMaterial) -> [String: KnownTranslation] {
        var known: [String: KnownTranslation] = [:]
        for entry in material.lookups where known[entry.german.lowercased()] == nil {
            known[entry.german.lowercased()] = KnownTranslation(
                german: entry.german, english: entry.english, source: .earlierLookup
            )
        }
        return known
    }
}
