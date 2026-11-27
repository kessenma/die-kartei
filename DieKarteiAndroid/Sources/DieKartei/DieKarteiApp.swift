import Foundation
import SkipFuse
@testable import DieKarteiCore
import SwiftUI

/// A logger for the DieKartei module.
let logger: Logger = Logger(subsystem: "com.kessenma.diekartei", category: "DieKartei")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
/* SKIP @bridge */public struct DieKarteiRootView : View {
    /* SKIP @bridge */public init() {
        // The shared services read the Goethe lists etc. from this module's resources.
        AppResources.bundle = Bundle.module
        AppDatabase.open()
    }

    public var body: some View {
        ContentView()
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
/* SKIP @bridge */public final class DieKarteiAppDelegate : Sendable {
    /* SKIP @bridge */public static let shared = DieKarteiAppDelegate()

    private init() {
    }

    /* SKIP @bridge */public func onInit() {
        logger.debug("onInit")
    }

    /* SKIP @bridge */public func onLaunch() {
        logger.debug("onLaunch")
    }

    /* SKIP @bridge */public func onResume() {
        logger.debug("onResume")
    }

    /* SKIP @bridge */public func onPause() {
        logger.debug("onPause")
        Task { @MainActor in AppDatabase.checkpoint() }
    }

    /* SKIP @bridge */public func onStop() {
        logger.debug("onStop")
    }

    /* SKIP @bridge */public func onDestroy() {
        logger.debug("onDestroy")
    }

    /* SKIP @bridge */public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}
