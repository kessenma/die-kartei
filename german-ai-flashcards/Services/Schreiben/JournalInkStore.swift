//
//  JournalInkStore.swift
//  german-ai-flashcards
//
//  Where a journal entry's handwriting lives: one `PKDrawing.dataRepresentation()` per page at
//  `Application Support/Journal/<entry id>/p<N>.drawing`. Today an entry has one page (`p0`)
//  that grows downward; the page number is in the name so more can arrive without renaming.
//
//  Its own root, `Journal`, so `FileSyncDocument` carries the ink to the learner's other devices
//  with no model field naming it: the path is the entry's synced id. On disk rather than on the
//  model for `SchreibblattInkStore`'s reason (an autosaved blob would rewrite the SQLite row on
//  every stroke). Every save is a re-upload, so callers skip unchanged ink and an erased page
//  deletes its file.
//
//  PencilKit-free so the store compiles everywhere; callers turn the bytes into a `PKDrawing`.
//

import Foundation

nonisolated enum JournalInkStore {
    static let rootName = "Journal"
    static let fileExtension = "drawing"

    /// The page's width in points. The height is the entry's `inkHeight`.
    static let pageWidth: CGFloat = 768
    /// The height a fresh page starts with (`PencilPad.defaultSize`), and the step more room adds.
    static let initialHeight = 1024
    static let heightStep = 512
    static let maxHeight = 8192

    static var root: URL {
        URL.applicationSupportDirectory.appendingPathComponent(rootName, isDirectory: true)
    }

    static func folder(for entryID: UUID) -> URL {
        root.appendingPathComponent(entryID.uuidString, isDirectory: true)
    }

    static func url(for entryID: UUID, page: Int = 0) -> URL {
        folder(for: entryID).appendingPathComponent("p\(page).\(fileExtension)")
    }

    static func read(_ entryID: UUID, page: Int = 0) -> Data? {
        try? Data(contentsOf: url(for: entryID, page: page))
    }

    /// Write a page's ink. Nil or empty data removes the file: an erased page shouldn't keep a
    /// file that syncs and renders as nothing. Unchanged bytes are not rewritten, since a write
    /// is a re-upload. True when the disk now holds `data`.
    @discardableResult
    static func write(_ data: Data?, for entryID: UUID, page: Int = 0) -> Bool {
        let target = url(for: entryID, page: page)
        guard let data, !data.isEmpty else {
            try? FileManager.default.removeItem(at: target)
            return true
        }
        if let existing = try? Data(contentsOf: target), existing == data { return true }
        do {
            try FileManager.default.createDirectory(at: folder(for: entryID), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func hasInk(_ entryID: UUID, page: Int = 0) -> Bool {
        FileManager.default.fileExists(atPath: url(for: entryID, page: page).path)
    }

    /// Best effort, when the entry goes.
    static func deleteAll(for entryID: UUID) {
        try? FileManager.default.removeItem(at: folder(for: entryID))
    }

    /// Bytes on disk under the root, for Settings ▸ Speicher style footers.
    static func totalBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
