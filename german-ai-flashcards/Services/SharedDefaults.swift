//
//  SharedDefaults.swift
//  german-ai-flashcards
//
//  The settings store the shared code reads and writes. iOS: `UserDefaults.standard`. Android:
//  the shared code is a plain Swift package there, whose own `UserDefaults.standard` is a separate
//  file the app never sees; the app sets this to Skip's store (its `UserDefaults`, which is
//  Android's SharedPreferences) at launch. Shared files use this, never `UserDefaults.standard`
//  (scripts/check_android.sh fails on it).
//

import Foundation

nonisolated enum SharedDefaults {
    nonisolated(unsafe) static var store: UserDefaults = .standard
}
