import Foundation
import os

// Two helpers the vendored files use that upstream keeps in files this copy leaves out
// (Protocol.swift's JSON emitter, LTXMedia.swift). See VENDORED.md.

/// Upstream's `Emitter` writes JSON lines to the app over stdout. Here there's no stdout protocol,
/// only the log, so `log` goes to os.Logger.
public final class Emitter: @unchecked Sendable {
    public static let shared = Emitter()
    private let logger = Logger(subsystem: "com.germanflashcards", category: "KarteiDiffusion")
    public func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}

/// Python's `round`: halves go to the even neighbour (LTXMedia.swift upstream).
func roundHalfEven(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrEven))
}
