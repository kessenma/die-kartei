import Foundation
import Observation

/// What a picture run left undone for one deck or story: how many pictures came out, how many
/// were skipped, and why the run stopped if it did. Kept until the next run of that deck or story
/// (or until the learner dismisses it), so the screen they land on can say what happened — a run
/// that drew 5 of 20 cards and stopped on an empty OpenRouter account must not look like a
/// finished deck with some blank cards.
nonisolated struct PictureRunReport: Codable, Equatable, Sendable {
    var drawn: Int
    var total: Int
    /// Pictures the model declined or that failed after retries; the run carried on past them.
    var skipped: Int
    /// Why the run stopped short on its own. Nil when it finished, or the learner stopped it.
    var stopReason: String?
    var fix: Fix?
    var date = Date()

    /// The one thing the learner can do about `stopReason`.
    enum Fix: String, Codable, Sendable {
        case addCredit
        case raiseKeyLimit
        case confirmAge
        case reconnect
    }

    /// Only runs that went wrong leave a report; a clean run clears the old one.
    var isWorthShowing: Bool { stopReason != nil || skipped > 0 }
}

extension OpenRouterError {
    /// The reason as a report states it: what happened, without the how-to-fix that
    /// `errorDescription` spells out, because the report's button is the fix.
    var reportReason: String {
        switch self {
        case .outOfCredit(let keyLimit):
            keyLimit ? "This key reached its spending limit on OpenRouter." : "Your OpenRouter credit ran out."
        case .needsAgeConfirmation:
            "Muse Image needs its one-time 18+ confirmation on OpenRouter."
        case .unauthorized:
            "OpenRouter no longer accepts the saved key."
        case .notConnected:
            "OpenRouter isn't connected on this phone."
        default:
            errorDescription ?? "The picture service stopped."
        }
    }

    /// The fix button a stopped run's report offers.
    var reportFix: PictureRunReport.Fix? {
        switch self {
        case .outOfCredit(let keyLimit): keyLimit ? .raiseKeyLimit : .addCredit
        case .needsAgeConfirmation:      .confirmAge
        case .unauthorized, .notConnected: .reconnect
        default: nil
        }
    }
}

/// The reports, keyed by deck or story id. Per device, in UserDefaults: a run's problems belong to
/// the phone that ran it and the account connected there, so they never sync.
@Observable
@MainActor
final class PictureRunReports {
    static let shared = PictureRunReports()

    private static let defaultsKey = "pictureRunReports"
    private(set) var reports: [UUID: PictureRunReport] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([UUID: PictureRunReport].self, from: data) {
            reports = stored
        }
    }

    func report(for id: UUID) -> PictureRunReport? { reports[id] }

    /// File the outcome of a run. A run with nothing to say clears what an earlier one left.
    func record(_ report: PictureRunReport, for id: UUID) {
        reports[id] = report.isWorthShowing ? report : nil
        persist()
    }

    func clear(_ id: UUID) {
        guard reports[id] != nil else { return }
        reports[id] = nil
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(reports) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
