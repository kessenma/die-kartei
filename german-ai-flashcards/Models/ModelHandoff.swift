import Foundation

/// Which model picks up a chat, paper or report that was made with a model this device hasn't got.
///
/// iCloud Sync brings a learner's chats and papers to every device, but downloads are per device:
/// a chat started on the Mac with the E4B tutor turns up on a 6 GB iPhone that only holds E2B, or on
/// an iPad that has no tutor at all. Before this, every follow-up path pinned the original model,
/// so the first tap either started a silent multi-GB download from inside the chat or hit "load
/// refused" with no way forward.
///
/// A chat carries no model state beyond its text (the history is plain role/content turns, cut to
/// a trailing window), so any tutor can continue any chat. This picks the one that should.
///
/// **Never write the result back to the synced record.** `ChatConversation.modelRaw` and
/// `StudyPaper.modelRaw` travel to every device, so storing "E2B" from the iPhone would flip the
/// Mac's copy to a model the Mac may not have either, and the two would trade the problem back and
/// forth. The stored model means "made with"; each device resolves its own at open time.
struct ModelHandoff: Equatable {
    /// What the content was made with, when that is still a model the app knows.
    let original: MLXModel?
    /// What runs here.
    let model: MLXModel
    /// Whether `model` can run right now with no download.
    let isReady: Bool
    /// Whether the original would run here if it were downloaded. The "get it instead" offer only
    /// makes sense when this is true.
    let originalFits: Bool

    /// The content continues on a different model than it was made with.
    var isHandoff: Bool { original != nil && original != model }

    /// Whether to offer the original as a download: it is a tutor, it isn't here, and it fits.
    var offersOriginal: Bool {
        guard isHandoff, let original, original.isGermanTutor else { return false }
        return originalFits
    }

    /// The rule, with every input passed in so tests don't touch the filesystem.
    ///
    /// Order: the original, if it is ready → the learner's own pick, if ready → the best ready
    /// tutor → Apple Intelligence. When the original was a tutor, an Apple Intelligence pick waits
    /// behind the tutors: a tutor chat handed to the 60% model while a tutor sits on disk would be a
    /// downgrade nobody chose.
    ///
    /// When nothing is ready the answer is a download, so it names a model that fits: the original
    /// if it does, else the learner's pick if it does, else the best tutor this device can run.
    static func resolve(
        original: MLXModel?,
        pick: MLXModel,
        downloaded: Set<MLXModel>,
        appleIntelligence: Bool,
        fits: (MLXModel) -> Bool
    ) -> ModelHandoff {
        func ready(_ model: MLXModel) -> Bool {
            model.isAppleIntelligence ? appleIntelligence : (downloaded.contains(model) && fits(model))
        }
        let originalFits = original.map { $0.isAppleIntelligence ? appleIntelligence : fits($0) } ?? false

        var order: [MLXModel] = []
        if let original { order.append(original) }
        if !(pick.isAppleIntelligence && original?.isGermanTutor == true) { order.append(pick) }
        order += MLXModel.germanTutors
        order.append(.appleIntelligence)

        if let model = order.first(where: ready) {
            return ModelHandoff(original: original, model: model, isReady: true, originalFits: originalFits)
        }

        let pickFits = !pick.isAppleIntelligence && fits(pick)
        let download = (originalFits && original?.isAppleIntelligence == false ? original : nil)
            ?? (pickFits ? pick : nil)
            ?? MLXModel.germanTutors.first(where: fits)
            ?? original ?? pick
        return ModelHandoff(original: original, model: download, isReady: false, originalFits: originalFits)
    }

    /// The rule against this device. Reads the hub cache once per model, so call it when a chat or
    /// paper opens, not from a view body.
    @MainActor
    static func current(original: MLXModel?, pick: MLXModel) -> ModelHandoff {
        let readiness = ModelReadiness.current
        // `readiness.tutor` joins the real downloads so `-onboarding.debugTier tutor` reaches the
        // handoff on a simulator, which has none.
        var downloaded = Set(MLXModel.germanTutors.filter(\.isDownloaded))
        if let tutor = readiness.tutor { downloaded.insert(tutor) }
        return resolve(
            original: original,
            pick: pick,
            downloaded: downloaded,
            appleIntelligence: readiness.appleIntelligence,
            fits: DeviceCapability.mayRun
        )
    }
}
