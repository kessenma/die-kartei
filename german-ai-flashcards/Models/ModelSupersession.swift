import Foundation
// For `ModelConfiguration.name`, which is how `valid` compares a retired repo ID against the live
// one. Without it the property is invisible and the safety filter silently can't be written.
import MLXLMCommon

/// One retired build of a model the app still ships under the same name.
///
/// When a fine-tune is retrained, ``MLXModel/configuration`` is pointed at a new HuggingFace repo
/// while the enum case and its `rawValue` stay exactly where they are. That `rawValue` is what
/// UserDefaults (`selectedMLXModel`, `lastLoadedModel`, …) and every SwiftData record
/// (`SavedDeck.generatorRaw`, `ChatConversation.modelRaw`, `StudyStory.modelRaw`, …) store, so
/// renaming it would orphan a year of the learner's decks, chats and jobs to buy nothing.
///
/// The price of keeping the name is that the *old* repo directory stays in the hub cache with
/// nothing referencing it. Nothing sizes it, nothing offers to delete it, and the Settings storage
/// bar files it under "Other" — because that section builds its list from `MLXModel.allCases`, and
/// after the swap no case names that directory. On the E4B tutor that is 4.8 GB of somebody's phone
/// spent on weights the app will never load again.
///
/// This table is the app's memory of those directories. It is the only remaining reason the app can
/// name, size, and delete a repo ID that appears nowhere else in the code.
///
/// **The next retrain is one row.** Retrain, swap the ID in `ModelConfiguration.swift`, then paste
/// the ID you just replaced in here with a line on what changed. The launch sheet, the Settings
/// banner and the Storage row are all driven off this table and need no edit. Models with no row
/// cost nothing — the filesystem is touched once per row, and there is one row.
///
/// Rows are safe to delete eventually. The only people a row can still reach are those who had the
/// old build downloaded when the swap shipped and have neither updated nor deleted it since.
struct ModelSupersession: Identifiable {

    /// The model that still ships under this name — this row's replacement build.
    let model: MLXModel

    /// The repo the app used to download for `model`, which may still be sitting in the hub cache.
    ///
    /// Deliberately the only ID stored here. The replacement is always `model.configuration.name`,
    /// so there is no second copy of it in this file to fall out of step with the one that actually
    /// downloads.
    let legacyRepoID: String

    /// One learner-facing sentence on what the new build does better. The update sheet's subtitle.
    let whatChanged: String

    /// What the new build is measurably better at, as short bullets for the update sheet.
    let improvements: [String]

    /// When the swap shipped. Nothing reads it; it is what tells the next person whether this row
    /// is old enough to delete.
    let retiredOn: String

    var id: String { legacyRepoID }

    // MARK: - The table

    static let all: [ModelSupersession] = [
        ModelSupersession(
            model: .gemma4_E4B_german,
            legacyRepoID: "kessenma/gemma4-e4b-german-tutor-4bit",
            whatChanged: "Retrained on a much larger set of German examples. Same size, same "
                       + "speed, sharper corrections.",
            improvements: [
                "Scores 91% on this app's German grammar test, up from 85%.",
                "It no longer \"corrects\" sentences that were already right. On the 24 correct "
                + "sentences in the test it invented nothing, where the old one flagged two.",
                "Much better on da-/wo-compounds, the hardest of the areas it's trained for.",
                "Sounds more like someone talking and less like a textbook.",
                "Same download size and the same memory, so nothing changes about how it runs here.",
                "Your decks, chats, stories and progress are untouched. Only the model changes.",
            ],
            retiredOn: "2026-08-12"
        ),
    ]

    // MARK: - Cache state

    /// Rows whose replacement actually shipped.
    ///
    /// A row whose `legacyRepoID` still equals the model's live configuration means someone added
    /// the row but forgot to swap the ID in `ModelConfiguration.swift`. Acting on that row would
    /// offer to delete the directory the app is about to load out of, so drop it rather than trust
    /// it. It also makes this whole mechanism provably inert until the swap lands, which is what
    /// lets it be built and shipped a step ahead of the model.
    private static var valid: [ModelSupersession] {
        all.filter { $0.legacyRepoID != $0.model.configuration.name }
    }

    /// Whether the complete retired build is on this device.
    ///
    /// The strict gate: the launch sheet and the Settings banner appear only for someone who
    /// actually has the whole thing, so a fresh install — which has no hub cache at all — never
    /// sees a word about any of this.
    var isOnDisk: Bool { HubCacheLocation.isDownloaded(repoID: legacyRepoID) }

    /// Bytes this row would reclaim: the cached repo *plus* whatever a download that never finished
    /// left behind.
    ///
    /// Both, because `HubCacheLocation.delete(repoID:)` removes both.
    /// `HubCacheLocation.cachedSizeBytes` alone would miss the partials, which live under a
    /// different cache root and on an abandoned transfer of this model can be several GB on their
    /// own — exactly the bytes someone hunting for space most wants back.
    var reclaimableBytes: Int64 {
        let repo = HubCacheLocation.cachedSizeBytes(repoID: legacyRepoID) ?? 0
        let partials = HubCacheLocation.directorySize(
            ResumableModelDownloader.partialsDirectory(forRepo: legacyRepoID)
        )
        return repo + partials
    }

    /// Complete retired builds on this device — the gate for the update sheet and the tutor banner.
    static var onDisk: [ModelSupersession] { valid.filter(\.isOnDisk) }

    /// Anything of a retired build that is costing disk space, complete or not.
    ///
    /// Looser than ``onDisk`` on purpose, and used only by the Storage breakdown, which reports
    /// what a directory *costs* rather than whether it is usable. An abandoned 3 GB partial is
    /// exactly as expensive as a finished download and, unlike a finished download, can never
    /// become useful: after the swap nothing in the app will ever resume it.
    static var occupyingSpace: [ModelSupersession] { valid.filter { $0.reclaimableBytes > 0 } }

    /// Remove the retired build and its partials.
    ///
    /// Never called without an explicit tap. This is several GB of somebody's phone and the app is
    /// not entitled to reclaim it quietly, however sure it is that the bytes are dead.
    func delete() throws { try HubCacheLocation.delete(repoID: legacyRepoID) }

    // MARK: - Launch-sheet memory

    /// Keyed by repo ID rather than one global flag, so the next supersession gets its own one-time
    /// sheet without anyone having to remember to reset anything.
    private var seenKey: String { "modelUpdate.seen." + legacyRepoID }

    var hasSeenUpdateSheet: Bool { UserDefaults.standard.bool(forKey: seenKey) }

    func markUpdateSheetSeen() { UserDefaults.standard.set(true, forKey: seenKey) }

    /// The one retired build worth raising at launch: on disk, and never raised before. Nil for
    /// everyone else, which is nearly everyone.
    static var launchPrompt: ModelSupersession? {
        onDisk.first { !$0.hasSeenUpdateSheet }
    }
}
