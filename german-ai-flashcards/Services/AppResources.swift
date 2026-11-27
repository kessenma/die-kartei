//
//  AppResources.swift
//  german-ai-flashcards
//
//  Where bundled data files (word lists, exercise banks) load from. The iOS app reads its own
//  bundle. When these files are compiled into DieKarteiCore (the Android build), the host sets
//  `bundle` to wherever it packaged the same JSON files.
//

import Foundation

nonisolated enum AppResources {
    #if SWIFT_PACKAGE
    nonisolated(unsafe) static var bundle: Bundle = .main
    #else
    static var bundle: Bundle { .main }
    #endif

    static func url(_ name: String, _ ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }
}
