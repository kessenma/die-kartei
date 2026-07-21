import Foundation
import os

@Observable
class GenerationCoordinator {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "de.germanflashcards", category: "Generation")

    private func memFootprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) / 1_048_576 : -1
    }
    // MARK: - Shared UI State

    var generatedCards: [VocabCard] = []
    var isGenerating = false
    var errorMessage: String?
    var generationProgress: Double = 0
    var cardsGenerated: Int = 0
    var cardsRequested: Int = 0
    var uniqueShortfall: (requested: Int, generated: Int)?

    var generationStartTime: Date?
    var lastGenerationTimeSeconds: Double = 0
    var currentBatchSize: Int = 0
    var currentBatchIndex: Int = 0
    var stopRequested: Bool = false
    var wasStoppedEarly: Bool = false

    func stopGeneration() {
        stopRequested = true
        mlxService.isStopRequested = true
    }

    var lastTopic: String = ""
    var lastWordCount: Int = 0
    var lastIncludeExamples: Bool = false
    var lastIncludeGender: Bool = true
    var lastWordTypeFilter: WordTypeFilter = .all
    var lastIncludeConjugations: Bool = false
    var lastSelectedTenses: [String] = []
    var lastGeneratorRaw: String = ""

    // MARK: - Validation
    var validationResults: [ValidationResult] = []
    var isValidating = false

    // MARK: - Draft pictures

    /// The `CardImageTiming.everyCard` phase: pictures drawn straight after the words, before the
    /// "keep which cards?" review, so the review has them and the deck opens complete.
    ///
    /// Deliberately not folded into `generateVocab` — the batch queue shares that method and does
    /// its own picture pass at the end of the queue, where it doesn't cost the run a 5 GB model
    /// swap per deck. Only the interactive Home flow calls this.
    var isDrawingImages = false
    /// When the picture phase began, so the overlay's clock keeps running across the handover
    /// instead of restarting (`generationStartTime` is cleared once the words are done).
    private(set) var drawingImagesStartTime: Date?
    /// Scratch directory id for the pictures of this run, until they're adopted into a saved deck.
    private(set) var draftImageID: UUID?
    /// Draft file names by German word, lowercased. Empty until the draft phase finishes.
    private(set) var draftImages: [String: String] = [:]
    /// Set when the learner stopped the draft run, so the flow doesn't turn around and offer to
    /// draw the very cards they just declined.
    private(set) var draftImagesStopped = false

    /// Draw a picture for every generated card, keeping the generation overlay up while it runs.
    func drawDraftImages() async {
        guard !generatedCards.isEmpty else { return }

        discardDraftImages()
        let draftID = UUID()
        draftImageID = draftID
        drawingImagesStartTime = Date()
        isDrawingImages = true
        defer { isDrawingImages = false }

        draftImages = await DeckIllustrationService.shared.illustrateDraft(
            cards: generatedCards, draftID: draftID, mlxService: mlxService
        )
        draftImagesStopped = DeckIllustrationService.shared.wasStopped
        if draftImages.isEmpty {
            // Nothing landed — don't leave an empty directory behind for the flow to reason about.
            discardDraftImages()
        }
    }

    /// Forget this run's draft pictures and delete them from disk. Called once they've been
    /// adopted into a deck, and when the learner discards the generated cards outright.
    func discardDraftImages() {
        if let draftImageID {
            CardImageStore.discardDraft(draftImageID)
        }
        draftImageID = nil
        draftImages = [:]
        draftImagesStopped = false
    }

    // MARK: - Backends

    let mlxService: MLXGenerationService
    let modelManager: MLXModelManager

    // MARK: - Availability

    var isAvailable: Bool {
        mlxService.isModelLoaded
    }

    var unavailabilityReason: String? {
        if mlxService.isLoading {
            return "Model is loading, please wait..."
        }
        if !mlxService.isModelLoaded {
            return "Model not loaded. Go to Settings to load \(modelManager.selectedMLXModel.rawValue)."
        }
        return nil
    }

    /// Pass `mlxService` to share an already-loaded model with another coordinator (the batch
    /// queue does this so its runs never load a second copy); by default each coordinator owns
    /// its own service.
    @MainActor
    init(modelManager: MLXModelManager, mlxService: MLXGenerationService? = nil) {
        self.modelManager = modelManager
        self.mlxService = mlxService ?? MLXGenerationService()
    }

    // MARK: - Generation

    /// `model` pins a specific generator (the batch queue passes the model chosen when the job
    /// was queued); nil uses the current selection.
    func generateVocab(
        topic: String,
        count: Int,
        includeExamples: Bool,
        includeGender: Bool,
        wordTypeFilter: WordTypeFilter = .all,
        includeConjugations: Bool = false,
        selectedTenses: [String] = [],
        model: MLXModel? = nil
    ) async {
        let resolvedModel = model ?? modelManager.selectedMLXModel
        isGenerating = true
        errorMessage = nil
        generatedCards = []
        generationProgress = 0
        cardsGenerated = 0
        cardsRequested = count
        uniqueShortfall = nil
        validationResults = []
        discardDraftImages()   // a previous run's pictures belong to cards that no longer exist
        generationStartTime = Date()
        stopRequested = false
        wasStoppedEarly = false
        mlxService.isStopRequested = false
        mlxService.lastBatchEndedEarly = false
        lastTopic = topic
        lastWordCount = count
        lastIncludeExamples = includeExamples
        lastIncludeGender = includeGender
        lastWordTypeFilter = wordTypeFilter
        lastIncludeConjugations = includeConjugations
        lastSelectedTenses = selectedTenses
        lastGeneratorRaw = resolvedModel.rawValue

        await generateWithMLX(
            topic: topic, count: count,
            includeExamples: includeExamples, includeGender: includeGender,
            wordTypeFilter: wordTypeFilter,
            includeConjugations: includeConjugations,
            selectedTenses: selectedTenses,
            model: resolvedModel
        )

        if let start = generationStartTime, !generatedCards.isEmpty {
            let elapsed = Date().timeIntervalSince(start)
            lastGenerationTimeSeconds = elapsed
            modelManager.recordGenerationTime(elapsed, cardCount: generatedCards.count, for: resolvedModel)
        } else {
            lastGenerationTimeSeconds = 0
        }
        generationStartTime = nil

        // Check the generated cards against the Wiktionary dictionary, applying every article
        // fix the dictionary (or a gender rule) can settle on its own. The user sees corrected
        // cards and a count of what changed, rather than a queue of warnings to work through.
        if !generatedCards.isEmpty {
            isValidating = true
            let outcome = WiktionaryValidator.shared.validateAndCorrect(generatedCards)
            generatedCards = outcome.cards
            validationResults = outcome.results
            if !outcome.corrections.isEmpty {
                let summary = outcome.corrections
                    .map { "\($0.germanWord): \($0.from ?? "—")→\($0.to)" }
                    .joined(separator: ", ")
                logger.info("[validation] auto-corrected \(outcome.corrections.count, privacy: .public) article(s) — \(summary, privacy: .public)")
            }
            isValidating = false
        }

        isGenerating = false
    }

    // MARK: - MLX Backend

    private func maxBatchSize(includeConjugations: Bool, tenseCount: Int) -> Int {
        if includeConjugations && tenseCount > 1 { return 5 }
        if includeConjugations { return 5 }
        return 10
    }

    /// Distributes `total` into evenly-sized batches, each ≤ `maxBatch`.
    /// e.g. total=15, max=10 → [8, 7]; total=30, max=10 → [10, 10, 10]
    private func computeBatchSizes(total: Int, maxBatch: Int) -> [Int] {
        guard total > 0, maxBatch > 0 else { return [] }
        let k = (total + maxBatch - 1) / maxBatch
        let base = total / k
        let remainder = total % k
        return (0..<k).map { $0 < remainder ? base + 1 : base }
    }

    private func generateWithMLX(
        topic: String, count: Int,
        includeExamples: Bool, includeGender: Bool,
        wordTypeFilter: WordTypeFilter,
        includeConjugations: Bool, selectedTenses: [String],
        model: MLXModel
    ) async {
        // Auto-load model if needed
        if !mlxService.isModelLoaded || mlxService.currentModel != model {
            await mlxService.loadModel(model)
            guard mlxService.isModelLoaded else {
                errorMessage = mlxService.loadError ?? "Failed to load model."
                return
            }
        }

        let maxBatch = maxBatchSize(includeConjugations: includeConjugations, tenseCount: selectedTenses.count)
        let batches = computeBatchSizes(total: count, maxBatch: maxBatch)
        let totalBatches = batches.count
        var allCards: [VocabCard] = []
        var seen = Set<String>()

        let fp0 = memFootprintMB()
        let batchPlan = batches.map(String.init).joined(separator: "+")
        logger.info("[\(model.rawValue, privacy: .public)] Generation session — count=\(count, privacy: .public), batches=\(batchPlan, privacy: .public), conjugations=\(includeConjugations, privacy: .public), footprint=\(fp0, privacy: .public) MB")

        generationProgress = 0.05

        do {
            for (batchIndex, plannedCount) in batches.enumerated() {
                guard !stopRequested else { break }

                let remaining = count - allCards.count
                guard remaining > 0 else { break }
                let batchCount = min(plannedCount, remaining)

                let fpBefore = memFootprintMB()
                logger.info("[\(model.rawValue, privacy: .public)] Batch \(batchIndex + 1, privacy: .public)/\(totalBatches, privacy: .public) — requesting \(batchCount, privacy: .public) cards, footprint=\(fpBefore, privacy: .public) MB")

                currentBatchSize = batchCount
                currentBatchIndex = batchIndex
                let batchTimeoutSeconds = Double(batchCount) * 30.0 + 60.0
                let cards = try await mlxService.generateCards(
                    topic: topic, count: batchCount,
                    includeExamples: includeExamples,
                    includeGender: includeGender,
                    wordTypeFilter: wordTypeFilter,
                    includeConjugations: includeConjugations,
                    selectedTenses: selectedTenses,
                    model: model,
                    timeoutSeconds: batchTimeoutSeconds,
                    excludeWords: Array(seen)
                )

                // Post-processing: clean up model output
                let cleaned = cards.map { card -> VocabCard in
                    var c = card
                    let isVerb = (c.wordType?.lowercased() == "verb")
                    let isNoun = (c.wordType?.lowercased() == "noun")

                    if !isNoun { c.article = nil }
                    if let article = c.article,
                       article.lowercased() == "null" || article.trimmingCharacters(in: .whitespaces).isEmpty {
                        c.article = nil
                    }
                    // The model sometimes bakes the article into the word itself ("der Flug"
                    // alongside article "der"), which doubles on display and defeats dedup.
                    if isNoun {
                        let parts = c.germanWord
                            .trimmingCharacters(in: .whitespaces)
                            .split(separator: " ", maxSplits: 1)
                        if parts.count == 2, ["der", "die", "das"].contains(parts[0].lowercased()) {
                            c.germanWord = String(parts[1])
                            if c.article?.isEmpty != false {
                                c.article = parts[0].lowercased()
                            }
                        }
                    }
                    if let sentence = c.exampleSentence,
                       sentence.lowercased() == "null" || sentence.trimmingCharacters(in: .whitespaces).isEmpty {
                        c.exampleSentence = nil
                    }
                    if !includeConjugations || !isVerb {
                        c.conjugations = nil
                    }
                    return c
                }

                // Deduplicate against all previous cards
                for card in cleaned {
                    let key = card.germanWord.lowercased()
                    if !seen.contains(key) {
                        seen.insert(key)
                        allCards.append(card)
                    }
                }

                let fpAfter = memFootprintMB()
                logger.info("[\(model.rawValue, privacy: .public)] Batch \(batchIndex + 1, privacy: .public) done — got \(cards.count, privacy: .public) cards, total=\(allCards.count, privacy: .public), footprint=\(fpAfter, privacy: .public) MB")

                // Update progress
                let batchFraction = Double(batchIndex + 1) / Double(totalBatches)
                generationProgress = 0.05 + batchFraction * 0.95
                cardsGenerated = allCards.count
                cardsRequested = count

                // Update cards incrementally so the user sees them appear
                generatedCards = Array(allCards.prefix(count))

                // Exit batch loop if the service flagged an early exit (timeout or user stop)
                if mlxService.lastBatchEndedEarly {
                    if stopRequested {
                        wasStoppedEarly = true
                    } else {
                        let timeoutSec = Int(Double(batchCount) * 30.0 + 60.0)
                        let timeoutSecVal = timeoutSec
                        logger.warning("[\(model.rawValue, privacy: .public)] Batch \(batchIndex + 1, privacy: .public) timed out after \(timeoutSecVal, privacy: .public)s — stopping with \(allCards.count, privacy: .public) cards")
                        if allCards.count < count {
                            errorMessage = "Batch \(batchIndex + 1) timed out — keeping \(allCards.count) card\(allCards.count == 1 ? "" : "s") from completed batches."
                        }
                    }
                    break
                }
            }

            generatedCards = Array(allCards.prefix(count))
            cardsGenerated = generatedCards.count
            generationProgress = 1.0

            if !wasStoppedEarly && generatedCards.count < count {
                uniqueShortfall = (requested: count, generated: generatedCards.count)
            }
        } catch {
            let fpErr = memFootprintMB()
            logger.error("[\(model.rawValue, privacy: .public)] Generation error — cards so far=\(allCards.count, privacy: .public), footprint=\(fpErr, privacy: .public) MB, error=\(error.localizedDescription, privacy: .public)")
            // If we got some cards before the error, keep them
            if !allCards.isEmpty {
                generatedCards = Array(allCards.prefix(count))
                cardsGenerated = generatedCards.count
                generationProgress = 1.0
                if generatedCards.count < count {
                    uniqueShortfall = (requested: count, generated: generatedCards.count)
                }
                errorMessage = "Got \(generatedCards.count) of \(count) cards. The model produced invalid output for the remaining cards — try generating again."
            } else {
                errorMessage = "Generation failed: \(error.localizedDescription)"
            }
        }
    }
}
