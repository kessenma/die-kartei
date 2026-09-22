//
//  DocumentTutorPicker.swift
//  german-ai-flashcards
//
//  The one tutor picker the document features share (flashcards from a document, a handout's
//  translation): only tutors already on this device, best first, bound to the learner's
//  document tutor. Never a download on the way to a deck or a translation.
//

import SwiftUI

@MainActor
enum DocumentTutorChoice {
    /// Tutors on this device that it can run, best first.
    static var downloaded: [MLXModel] {
        let rank: (MLXModel) -> Int = { MLXModel.germanTutors.firstIndex(of: $0) ?? MLXModel.germanTutors.count }
        return MLXModel.allCases
            .filter { $0.isDownloaded && DeviceCapability.mayRun($0) }
            .sorted { rank($0) < rank($1) }
    }

    /// The learner's document tutor when it is on the device, else the best one that is.
    static func current(_ modelManager: MLXModelManager) -> MLXModel {
        let picked = modelManager.selectedPaperModel
        if picked.isDownloaded, DeviceCapability.mayRun(picked) { return picked }
        return downloaded.first ?? picked
    }
}

/// One picker row: "Tutor" over the downloaded tutors. Renders nothing when there are none, so
/// the caller's footer can say where to download one.
struct DocumentTutorPicker: View {
    @Bindable var modelManager: MLXModelManager
    var title = "Tutor"

    var body: some View {
        let options = DocumentTutorChoice.downloaded
        if !options.isEmpty {
            Picker(title, selection: Binding(
                get: { DocumentTutorChoice.current(modelManager) },
                set: { modelManager.selectedPaperModel = $0 }
            )) {
                ForEach(options) { model in
                    Text(model.rawValue).tag(model)
                }
            }
        }
    }
}
