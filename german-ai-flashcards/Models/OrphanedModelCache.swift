import Foundation
// For `ModelConfiguration.name`, which is how `claimed` reads each live model's repo ID.
// Without it the property is invisible and every model reads as an orphan — see the same
// import, for the same reason, in `ModelSupersession.swift`.
import MLXLMCommon

/// Model weights sitting in the download cache that nothing in the app claims any more.
///
/// Deliberately a *sweep*, not a table. When a model is dropped from ``MLXModel`` its weights
/// stay on the phone with no case naming them, so the Settings storage bar files them under the
/// grey "Other" segment: several GB of somebody's device with nothing on any screen to explain
/// it, and no way to get it back. ``ModelSupersession`` solves that for a *retrained* build,
/// but it cannot help here — its `model` field is a hard reference to a live case, so it can
/// never name a model that no longer exists.
///
/// A hand-written list of removed repo IDs would work and would also be a thing to forget. This
/// enumerates the cache and subtracts what the app still uses, which finds the same models plus
/// abandoned partial transfers, repos left behind by builds nobody remembers, and every future
/// removal with no row to add.
///
/// Everything here is invisible unless something is genuinely on disk, so a fresh install pays
/// two directory listings and shows nothing.
enum OrphanedModelCache {

    /// Every repo ID the app still has a use for. Anything cached and not in here is an orphan.
    ///
    /// Superseded builds are excluded because they already have their own UI — the update sheet
    /// and the "Old version" storage row — and listing them twice would offer the same bytes
    /// under two different names.
    private static var claimed: Set<String> {
        var ids = Set(MLXModel.allCases.map(\.configuration.name))
        ids.formUnion(ImageGenModel.allCases.map(\.repoID))
        ids.formUnion(ModelSupersession.all.map(\.legacyRepoID))
        return ids
    }

    /// One cached repo the app can no longer load.
    struct Orphan: Identifiable {
        let repoID: String
        /// Cached snapshot plus any abandoned partial transfer, which is how the storage row
        /// reports what deleting this actually gives back.
        let bytes: Int64

        var id: String { repoID }

        /// The name this model shipped under, or the bare repo ID for anything unrecognised.
        var displayName: String { OrphanedModelCache.formerName(repoID)?.name ?? repoID }

        /// The brand logo it shipped with, or nil to fall back to a generic glyph.
        var logoName: String? { OrphanedModelCache.formerName(repoID)?.logo }
    }

    /// Models this app used to include, so a reclaim row reads "Qwen3 8B" rather than
    /// "mlx-community/Qwen3-8B-4bit".
    ///
    /// Cosmetic only. An orphan missing from this table still lists, still sizes, and still
    /// deletes — which is the point of sweeping rather than tabulating. Removed 2026-09-01 when
    /// the app narrowed to its own German tutors; the logo assets these name must stay in the
    /// catalog for as long as this table does.
    private static let formerNames: [(repoID: String, name: String, logo: String)] = [
        ("mlx-community/Mistral-7B-Instruct-v0.3-4bit", "Mistral 7B",   "logo-mistral"),
        ("mlx-community/Qwen3-8B-4bit",                 "Qwen3 8B",     "logo-qwen"),
        ("mlx-community/Qwen3-4B-4bit",                 "Qwen3 4B",     "logo-qwen"),
        ("mlx-community/Qwen3-0.6B-4bit",               "Qwen3 0.6B",   "logo-qwen"),
        ("mlx-community/Phi-4-mini-instruct-4bit",      "Phi-4 Mini",   "logo-microsoft"),
        ("mlx-community/Llama-3.2-1B-Instruct-4bit",    "LLaMA 3.2 1B", "logo-meta"),
        ("mlx-community/gemma-3-1b-it-qat-4bit",        "Gemma 3 1B",   "logo-gemma"),
    ]

    private static func formerName(_ repoID: String) -> (name: String, logo: String)? {
        formerNames.first { $0.repoID == repoID }.map { ($0.name, $0.logo) }
    }

    /// Every cached repo the app can't load, largest first.
    ///
    /// Walks both cache roots: finished snapshots under the hub cache, and abandoned transfers
    /// under the downloads root. A repo with only partials left is still worth several GB and is
    /// the one kind of orphan that can never become useful again, since after a model is removed
    /// nothing will ever resume it.
    static var all: [Orphan] {
        let claimed = self.claimed
        var bytesByRepo: [String: Int64] = [:]

        for root in [HubCacheLocation.hubCacheDirectory,
                     ResumableModelDownloader.partialsRootDirectory] {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            )) ?? []

            for entry in entries {
                guard let repoID = HubCacheLocation.repoID(fromDirectoryName: entry.lastPathComponent),
                      !claimed.contains(repoID)
                else { continue }
                let size = HubCacheLocation.directorySize(entry)
                if size > 0 { bytesByRepo[repoID, default: 0] += size }
            }
        }

        return bytesByRepo
            .map { Orphan(repoID: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    /// Total reclaimable bytes. Zero for anyone who never downloaded a since-removed model,
    /// which is what keeps every surface built on this invisible by default.
    static var totalBytes: Int64 { all.reduce(0) { $0 + $1.bytes } }

    /// Remove one orphan's weights and partials. Never called without an explicit tap: this is
    /// gigabytes of somebody's phone, and the app isn't entitled to reclaim it quietly however
    /// sure it is that the bytes are dead.
    static func delete(_ orphan: Orphan) throws {
        try HubCacheLocation.delete(repoID: orphan.repoID)
    }
}
