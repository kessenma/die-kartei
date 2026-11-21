//
//  WorksheetInkStore.swift
//  german-ai-flashcards
//
//  Where the Pencil writing on a worksheet's slides lives: one `PKDrawing.dataRepresentation()`
//  per page at `Application Support/ClassNotes/Worksheets/<material id>/p<N>.drawing`.
//
//  Under ClassNotes on purpose: `FileSyncDocument` syncs that folder, subfolders included, so ink
//  written on the iPad reaches the Mac's export with no model field naming it — the path is
//  derived from the handout's synced id and the page number. On disk rather than on the model for
//  `SchreibblattInkStore`'s reason (an autosaved blob would rewrite the SQLite row every few
//  seconds). Every save re-uploads the whole page file, so callers debounce, skip unchanged ink,
//  and delete a page's file when its ink is erased rather than writing an empty drawing.
//
//  PencilKit-free so the store compiles everywhere; callers turn the bytes into a `PKDrawing`.
//

import Foundation

nonisolated enum WorksheetInkStore {
    static let fileExtension = "drawing"

    static func folder(for materialID: UUID) -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("ClassNotes", isDirectory: true)
            .appendingPathComponent("Worksheets", isDirectory: true)
            .appendingPathComponent(materialID.uuidString, isDirectory: true)
    }

    static func url(for materialID: UUID, page: Int) -> URL {
        folder(for: materialID).appendingPathComponent("p\(page).\(fileExtension)")
    }

    static func read(_ materialID: UUID, page: Int) -> Data? {
        try? Data(contentsOf: url(for: materialID, page: page))
    }

    /// Write a page's ink. Nil or empty data removes the file: an erased page shouldn't keep a
    /// file that syncs and renders as nothing. Unchanged bytes are not rewritten, since a write
    /// is a re-upload. True when the disk now holds `data`.
    @discardableResult
    static func write(_ data: Data?, for materialID: UUID, page: Int) -> Bool {
        let target = url(for: materialID, page: page)
        guard let data, !data.isEmpty else {
            try? FileManager.default.removeItem(at: target)
            return true
        }
        if let existing = try? Data(contentsOf: target), existing == data { return true }
        do {
            try FileManager.default.createDirectory(at: folder(for: materialID), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The pages that have ink, ascending.
    static func pagesWithInk(_ materialID: UUID) -> [Int] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder(for: materialID).path)) ?? []
        return names.compactMap { name -> Int? in
            guard name.hasPrefix("p"), name.hasSuffix("." + fileExtension) else { return nil }
            return Int(name.dropFirst().dropLast(fileExtension.count + 1))
        }.sorted()
    }

    /// Best effort, beside the handout's own file when the handout goes.
    static func deleteAll(for materialID: UUID) {
        try? FileManager.default.removeItem(at: folder(for: materialID))
    }
}
