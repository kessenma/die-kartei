//
//  SchreibblattStats+Store.swift
//  german-ai-flashcards
//
//  Reads the facts `SchreibblattStats` counts from the store: every logged sheet on this device
//  and the synced day log.
//

import Foundation
import SwiftData

extension SchreibblattStats {
    @MainActor
    static func load(in context: ModelContext, now: Date = Date()) -> SchreibblattStats {
        let sheets = (try? context.fetch(FetchDescriptor<SchreibblattSheet>())) ?? []
        let days = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        return SchreibblattStats(
            sheets: sheets.compactMap { sheet in
                sheet.loggedAt.map { logged in
                    Sheet(loggedAt: logged,
                          words: sheet.writtenWords.map { Sheet.Word(id: $0.id, german: $0.german) },
                          repetitions: sheet.repetitions,
                          strokes: sheet.strokeCount)
                }
            },
            days: days.filter { $0.sheetWordsWritten > 0 }.map { Day(start: $0.dayStart, words: $0.sheetWordsWritten) },
            now: now)
    }
}
