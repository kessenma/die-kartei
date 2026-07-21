//
//  ActivityRouter.swift
//  german-ai-flashcards
//

import Foundation
import Observation

/// Owns the currently-presented learning activity (the "spoke" in the hub-and-spoke
/// navigation). Deliberately dumb: any launcher — a Home tile, a Library row, a level
/// picker — sets `active`, and `ContentView` presents it through a single
/// `.fullScreenCover(item:)`. Setting `active = nil` dismisses back to the hub.
@Observable
final class ActivityRouter {
    var active: Activity?

    func launch(_ activity: Activity) {
        active = activity
    }

    func dismiss() {
        active = nil
    }
}
