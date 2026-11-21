import Foundation
import Observation
import SwiftData

/// Draws gallery pictures of words on the learner's OpenRouter account and files each one as a
/// `WordArtwork`.
///
/// Always the cloud (`beginCloudSession`), whatever the picture-source setting: the gallery
/// styles are written for Muse Image and Nano Banana. Error policy is the cloud pictures one
/// (docs/CLOUD_PICTURES.md): an error that `stopsRun` ends the run and leaves a report with its
/// fix, any other error skips that one picture.
@Observable
@MainActor
final class WordArtGenerator {
    static let shared = WordArtGenerator()

    /// One word to draw.
    struct Job: Hashable, Sendable {
        let germanWord: String
        let english: String
        let wordType: String?
        let style: WordArtStyle

        var key: String { WordArtKey.make(germanWord) }
    }

    /// Words with a picture in flight, by `WordArtKey`, so a gallery can show a placeholder.
    private(set) var drawing: [String: Int] = [:]
    /// Progress of the current run, 0…1, and how many pictures it holds.
    private(set) var runTotal = 0
    private(set) var runDone = 0
    /// What the last run left undone, for `PictureRunReportBanner`. Nil after a clean run.
    var lastReport: PictureRunReport?
    private var runTask: Task<Void, Never>?

    var isRunning: Bool { runTask != nil }

    static var isReady: Bool { OpenRouterAccount.hasKey }

    /// " (about $0.04 on your OpenRouter account)" for `pictures`, whatever the picture source.
    static func costPhrase(pictures: Int) -> String {
        guard pictures > 0 else { return "" }
        let dollars = Double(pictures) * CloudImageModel.current.approxCostUSD
        return "about \(dollars.formatted(.currency(code: "USD").precision(.fractionLength(2)))) on your OpenRouter account"
    }

    func isDrawing(key: String) -> Bool { (drawing[key] ?? 0) > 0 }

    /// Draw `jobs`, in parallel up to the session's limit. Returns when the run ends.
    func run(_ jobs: [Job], in context: ModelContext) async {
        guard !jobs.isEmpty, runTask == nil else { return }
        let task = Task { await self.perform(jobs, in: context) }
        runTask = task
        await task.value
        runTask = nil
    }

    /// Cancelling the run cancels its in-flight requests (`PictureSession.drawInCloud` forwards
    /// cancellation), and leaves any deck run on the same service alone.
    func stop() {
        runTask?.cancel()
    }

    private func perform(_ jobs: [Job], in context: ModelContext) async {
        runTotal = jobs.count
        runDone = 0
        lastReport = nil
        for job in jobs { drawing[job.key, default: 0] += 1 }
        defer {
            for job in jobs {
                drawing[job.key, default: 1] -= 1
                if drawing[job.key] ?? 0 <= 0 { drawing[job.key] = nil }
            }
        }

        guard let session = StoryImageService.shared.beginCloudSession() else {
            lastReport = PictureRunReport(drawn: 0, total: jobs.count, skipped: 0,
                                          stopReason: OpenRouterError.notConnected.reportReason,
                                          fix: .reconnect)
            return
        }
        defer { session.end() }

        let model = CloudImageModel.current
        var drawn = 0, skipped = 0
        var stop: OpenRouterError?
        var pending = jobs[...]

        await withTaskGroup(of: (Job, UUID, String, Result<Bool, Error>).self) { group in
            func launch(_ job: Job) {
                let id = UUID()
                let fileName = WordArtStore.newPictureName(for: id)
                let destination = WordArtStore.url(fileName: fileName, key: job.key)
                let request = CardIllustrationPrompts.artRequest(
                    englishTranslation: job.english, wordType: job.wordType, style: job.style
                )
                group.addTask { @MainActor in
                    do {
                        let ok = try await session.draw(request, saveTo: destination, onProgress: { _ in })
                        return (job, id, fileName, .success(ok))
                    } catch {
                        return (job, id, fileName, .failure(error))
                    }
                }
            }
            for _ in 0..<session.parallelism {
                guard let next = pending.popFirst() else { break }
                launch(next)
            }
            for await (job, id, fileName, result) in group {
                runDone += 1
                switch result {
                case .success(true):
                    let artwork = WordArtwork(wordKey: job.key, germanWord: job.germanWord, english: job.english,
                                              kind: .ai, fileName: fileName, styleRaw: job.style.rawValue)
                    artwork.id = id
                    artwork.modelID = model.rawValue
                    artwork.prompt = CardIllustrationPrompts.artPrompt(
                        englishTranslation: job.english, wordType: job.wordType, style: job.style)
                    context.insert(artwork)
                    try? context.save()
                    drawn += 1
                case .success(false):
                    break
                case .failure(let error):
                    if let error = error as? OpenRouterError, error.stopsRun {
                        stop = error
                        group.cancelAll()
                        pending = []
                    } else {
                        skipped += 1
                    }
                }
                if stop == nil, !Task.isCancelled, let next = pending.popFirst() { launch(next) }
            }
        }

        let report = PictureRunReport(drawn: drawn, total: jobs.count, skipped: skipped,
                                      stopReason: stop?.reportReason, fix: stop?.reportFix)
        lastReport = report.isWorthShowing ? report : nil
    }
}
