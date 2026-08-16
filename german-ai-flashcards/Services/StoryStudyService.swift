import CoreGraphics
import Foundation
import SwiftData

/// Generates a short German story plus comprehension questions and a glossary, and later
/// grades free-response answers and translates the story on demand.
///
/// Exclusive to the hero model (the in-house German fine-tune) — enforced, unlike the paper
/// feature's recommended-but-optional model: level-controlled prose and consistent answer keys
/// are the whole feature, and only the hero is trusted with them. Loosening the gate later is
/// a one-line edit here.
@Observable
@MainActor
final class StoryStudyService {

    /// The one model allowed to write and grade stories.
    static let requiredModel: MLXModel = .hero

    enum Phase: Equatable {
        case idle
        case loadingModel
        case writing
        case questions
        case glossary
        case illustrating
        case done
        case failed(String)
    }

    /// Sub-steps of the illustration phase, so the overlay can say what the wait is for.
    enum ImageStage: Equatable {
        case planning          // LLM is writing the scene descriptions
        case loadingPipeline   // diffusion pipeline is loading
        case rendering         // an image is actually being drawn
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var statusText: String = ""

    /// How many illustrations this run will attempt (0 when the story has no pictures).
    private(set) var imageTarget = 0
    /// Index of the illustration currently being drawn.
    private(set) var imageSlot = 0
    /// 0…1 progress of the current illustration's diffusion steps.
    private(set) var imageStep: Double = 0
    private(set) var imageStage: ImageStage = .planning
    /// The picture being drawn right now, decoded mid-diffusion. Nil on devices without the
    /// headroom for previews (see ``ImageGenPreview``) and between pictures.
    private(set) var imagePreview: CGImage?
    /// Bumped with every preview, so the overlay can cross-fade one into the next. A `CGImage`
    /// gives SwiftUI nothing to compare, and there's no other signal that a *new* one arrived.
    private(set) var imagePreviewID = 0
    /// The last preview of each slot — the finished pictures, for the overlay's filmstrip.
    /// Sized to the run's illustration count; entries stay nil when previews are off.
    private(set) var imageThumbs: [CGImage?] = []
    /// True while the on-demand English translation is generating.
    private(set) var isTranslating = false

    /// True once the learner asked this run to stop — a stop during illustration still ends in
    /// `.done`, so callers use this to skip optional follow-up work like the translation pass.
    var wasStopped: Bool { stopRequested }

    var isRunning: Bool {
        switch phase {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    /// Live token count while the story streams in (mirrors the generation service).
    var streamingTokenCount: Int { mlxService.streamingTokenCount }

    private let mlxService: MLXGenerationService
    private let modelContext: ModelContext
    private let imageService: StoryImageService
    private var model: MLXModel { Self.requiredModel }
    private var stopRequested = false

    init(
        mlxService: MLXGenerationService,
        modelContext: ModelContext,
        imageService: StoryImageService? = nil
    ) {
        self.mlxService = mlxService
        self.modelContext = modelContext
        // Resolved here rather than as a default argument: default args evaluate outside
        // this init's MainActor isolation, where touching .shared is a Swift 6 error.
        self.imageService = imageService ?? .shared
    }

    /// Ask the current generation to stop. Takes effect immediately during the streamed story
    /// call; between the shorter question/glossary calls it stops at the next step boundary.
    func stop() {
        stopRequested = true
        mlxService.isStopRequested = true
        imageService.requestStop()
    }

    // MARK: - Generation

    /// `weaveWords` (optional) are learner-profile words the story should naturally work in —
    /// the batch planner's coach steering. Empty keeps the prompt exactly as before.
    func generate(
        for story: StudyStory,
        questionCount: Int,
        kinds: [StoryQuestion.Kind],
        imageCount: Int = 0,
        weaveWords: [String] = []
    ) async {
        stopRequested = false
        phase = .loadingModel
        progress = 0
        statusText = "Loading \(model.rawValue)…"
        story.modelRaw = model.rawValue
        imageTarget = ImageGenModel.current.isDownloaded ? imageCount : 0
        imageSlot = 0
        imageStep = 0
        imageStage = .planning
        imagePreview = nil
        imageThumbs = []

        guard await ensureModelReady() else {
            phase = .failed(mlxService.loadError ?? "Couldn’t load \(model.rawValue).")
            return
        }

        // 1. The story itself (streamed).
        phase = .writing
        statusText = "Geschichte wird geschrieben…"
        progress = 0.05
        guard await writeStory(for: story, weaveWords: weaveWords) else { return } // sets its own phase on failure/stop
        progress = 0.55

        // 1b. Speaker roster (dialogue/e-mail only) so listening can voice each speaker distinctly.
        if story.genre.hasNamedSpeakers, !stopRequested {
            await extractSpeakers(for: story)
        }

        // 2. Questions — one call per selected kind so each prompt carries a single JSON shape.
        phase = .questions
        var questions: [StoryQuestion] = []
        let perKind = Self.splitCount(questionCount, across: kinds.count)
        for (index, kind) in kinds.enumerated() {
            guard !stopRequested else { phase = .idle; return }
            statusText = "Fragen werden erstellt — \(kind.label)…"
            questions += await makeQuestions(for: story, kind: kind, count: perKind[index])
            progress = 0.55 + 0.3 * (Double(index + 1) / Double(kinds.count))
        }
        story.setQuestions(questions)
        try? modelContext.save()

        // 3. Glossary (non-fatal if it fails).
        guard !stopRequested else { phase = .idle; return }
        phase = .glossary
        statusText = "Glossar wird erstellt…"
        progress = 0.9
        await makeGlossary(for: story)

        // The story is complete from here on — illustrations are a bonus that can never
        // fail or roll back a finished story.
        story.generationComplete = true
        try? modelContext.save()

        // 4. Illustrations (optional, non-fatal). Runs last because the LLM must first write
        // the scene prompts, then gets unloaded to make room for the diffusion pipeline.
        if imageCount > 0, ImageGenModel.current.isDownloaded, !stopRequested {
            phase = .illustrating
            await illustrate(story: story, count: imageCount)
        }

        // Always .done past this point — even if the user stopped mid-illustration, the
        // finished story must survive (the setup job deletes stories on non-.done phases).
        progress = 1
        phase = .done
        statusText = "Fertig!"
    }

    // MARK: - Step 4: illustrations

    /// Generate up to `count` images for the finished story. Every failure path is silent:
    /// whatever images finished are kept, and the story stays complete.
    private func illustrate(story: StudyStory, count: Int) async {
        progress = 0.9
        statusText = "Illustrationen werden geplant…"
        imageStage = .planning
        imageSlot = 0
        imageStep = 0
        imagePreview = nil

        let paragraphs = story.storyText.components(separatedBy: "\n\n")
        let anchors = StoryIllustrationPrompts.anchors(imageCount: count, paragraphCount: paragraphs.count)
        guard !anchors.isEmpty else { imageTarget = 0; return }
        imageTarget = anchors.count
        imageThumbs = [CGImage?](repeating: nil, count: anchors.count)

        // Scene descriptions come from the still-loaded LLM (German story → English scenes).
        // Any unusable slot falls back to a deterministic topic-based scene.
        var scenes = [String?](repeating: nil, count: anchors.count)
        // A single picture has nothing to stay consistent with, so it skips the cast sheet and
        // spends its whole token budget on the scene itself.
        let wantsCast = anchors.count > 1
        var cast: [StoryCastMember] = []
        let request = StoryIllustrationPrompts.sceneRequest(
            title: story.title, storyText: story.storyText,
            paragraphs: paragraphs, anchors: anchors, wantsCast: wantsCast
        )
        if let raw = try? await mlxService.generateText(
            system: request.system, user: request.user, model: model,
            maxTokens: 80 + 45 * anchors.count + (wantsCast ? 60 : 0)
        ) {
            scenes = StoryIllustrationPrompts.parseScenes(raw, count: anchors.count)
            if wantsCast { cast = StoryIllustrationPrompts.parseCast(raw) }
        }
        guard !stopRequested else { return }

        // Point of no return for cheap LLM access: free the ~5 GB language model before the
        // diffusion pipeline loads — the two don't fit together on 6 GB devices. Grading and
        // translation reload the LLM lazily later.
        mlxService.unloadModel()

        statusText = "Zeichenmodell wird geladen…"
        progress = 0.92
        imageStage = .loadingPipeline
        guard await imageService.loadPipeline() else { return }
        defer { imageService.unloadPipeline() }

        // One seed for the whole story. Identical character wording is what actually holds the
        // cast together; a shared seed on top of it nudges palette and rendering to match too.
        // Derived from the story's UUID rather than `random` so a rerun of the same story is
        // reproducible. Drop back to `nil` here if the pictures come out too samey.
        let idBytes = story.id.uuid
        let seed = UInt32(idBytes.0) << 24 | UInt32(idBytes.1) << 16
            | UInt32(idBytes.2) << 8 | UInt32(idBytes.3)

        var records = story.images
        for (slot, anchor) in anchors.enumerated() {
            guard !stopRequested else { break }
            statusText = "Illustration \(slot + 1)/\(anchors.count)…"
            imageStage = .rendering
            imageSlot = slot
            imageStep = 0
            imagePreview = nil
            let scene = scenes[slot] ?? StoryIllustrationPrompts.fallbackScene(topic: story.topic, slot: slot)
            let prompt = StoryIllustrationPrompts.positivePrompt(scene: scene, genre: story.genre, cast: cast)
            let base = 0.92 + 0.08 * (Double(slot) / Double(anchors.count))
            let span = 0.08 / Double(anchors.count)
            do {
                guard let fileName = try await imageService.generateImage(
                    prompt: prompt, storyID: story.id, index: slot, seed: seed,
                    onStepProgress: { [weak self] fraction in
                        self?.progress = base + span * fraction
                        self?.imageStep = fraction
                    },
                    onPreview: { [weak self] image in
                        guard let self else { return }
                        // Filed by the slot it was drawn for, not the current one: a preview
                        // hopping to the main actor can land after the next picture has started,
                        // and the last one to arrive for a slot is that picture's finished state.
                        if slot < self.imageThumbs.count { self.imageThumbs[slot] = image }
                        guard slot == self.imageSlot else { return }
                        self.imagePreview = image
                        self.imagePreviewID += 1
                    }
                ) else { continue }
                imageStep = 1
                // Save after every image so partial results survive kill/expiration.
                records.append(StoryImageRecord(
                    fileName: fileName, prompt: prompt, paragraphAnchorIndex: anchor
                ))
                story.setImages(records)
                try? modelContext.save()
            } catch {
                continue   // per-image failure — try the next one
            }
        }
    }

    private func ensureModelReady() async -> Bool {
        if mlxService.isModelLoaded && mlxService.currentModel == model { return true }
        await mlxService.loadModel(model)
        return mlxService.isModelLoaded && mlxService.currentModel == model
    }

    // MARK: - Step 1: story

    private func writeStory(for story: StudyStory, weaveWords: [String] = []) async -> Bool {
        let level = story.level
        let prompt = Self.storyPrompt(topic: story.topic, level: level, genre: story.genre, weaveWords: weaveWords)
        do {
            var raw = try await mlxService.generateStreamedText(
                system: prompt.system, user: prompt.user, model: model,
                maxTokens: level.storyMaxTokens, temperature: 0.75
            )
            if stopRequested { phase = .idle; return false }

            var parsed = Self.parseStory(raw)
            // One retry if the model came back far short of the level's target.
            if Self.wordCount(of: parsed.text) < level.storyWordRange.lowerBound / 2 {
                statusText = "Die Geschichte war zu kurz — zweiter Versuch…"
                raw = try await mlxService.generateStreamedText(
                    system: prompt.system, user: prompt.user, model: model,
                    maxTokens: level.storyMaxTokens, temperature: 0.75
                )
                if stopRequested { phase = .idle; return false }
                let second = Self.parseStory(raw)
                if Self.wordCount(of: second.text) > Self.wordCount(of: parsed.text) { parsed = second }
            }

            guard Self.wordCount(of: parsed.text) >= 30 else {
                phase = .failed("The story came back too short. Try again — or try a simpler topic.")
                return false
            }

            story.title = parsed.title ?? story.topic
            story.storyText = parsed.text
            try? modelContext.save()
            return true
        } catch is CancellationError {
            phase = .idle
            return false
        } catch {
            phase = .failed("Story generation failed: \(error.localizedDescription)")
            return false
        }
    }

    static func storyPrompt(topic: String, level: CEFRLevel, genre: StoryGenre, weaveWords: [String] = []) -> (system: String, user: String) {
        let system = """
        Du bist Autor von Lerngeschichten für Deutschlernende (Niveau \(level.rawValue)). \
        Schreibe eine kurze, in sich geschlossene Geschichte AUF DEUTSCH. \
        Antworte GENAU in diesem Format, ohne weitere Erklärungen:
        TITEL: <kurzer Titel>
        GESCHICHTE:
        <die Geschichte, in Absätze gegliedert>
        """
        var user = """
        Thema: \(topic)
        \(genre.promptInstruction)
        Länge: \(level.storyWordRange.lowerBound)–\(level.storyWordRange.upperBound) Wörter.
        \(level.storyConstraints)
        """
        if !weaveWords.isEmpty {
            user += "\nBaue einige dieser Wörter natürlich in die Geschichte ein: \(weaveWords.joined(separator: ", "))."
        }
        return (system, user)
    }

    /// Split raw output into title and body via the TITEL:/GESCHICHTE: markers, tolerating
    /// output that skips them entirely.
    static func parseStory(_ raw: String) -> (title: String?, text: String) {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        var title: String?
        var bodyLines: [String] = []
        var inBody = false

        for line in cleaned.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if !inBody, upper.hasPrefix("TITEL:") {
                title = String(trimmed.dropFirst("TITEL:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if !inBody, upper.hasPrefix("GESCHICHTE:") {
                inBody = true
                let rest = String(trimmed.dropFirst("GESCHICHTE:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { bodyLines.append(rest) }
                continue
            }
            if inBody {
                bodyLines.append(line)
            } else if !trimmed.isEmpty, title != nil {
                // Title seen but no GESCHICHTE marker — everything after the title is body.
                inBody = true
                bodyLines.append(line)
            } else if !trimmed.isEmpty {
                // No markers at all — treat the whole output as body.
                inBody = true
                bodyLines.append(line)
            }
        }

        var text = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        if var t = title {
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "*#_\"„“» «"))
            title = t.isEmpty ? nil : t
        }
        return (title, text)
    }

    static func wordCount(of text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    // MARK: - Step 1b: speaker roster (dialogue/e-mail)

    private struct RawSpeaker: Codable { var name: String?; var role: String? }
    private struct RawSpeakerResponse: Codable { var speakers: [RawSpeaker] }

    /// Extract the named speakers of a dialogue/e-mail story and a voice role (male/female/boy/girl)
    /// for each, so listening mode can assign a distinct voice per speaker. Non-fatal: on any
    /// failure, listening falls back to appearance-order voice assignment.
    private func extractSpeakers(for story: StudyStory) async {
        statusText = "Sprecher werden erkannt…"
        let system = "Du analysierst eine Geschichte. Antworte NUR mit gültigem JSON, ohne Erklärungen."
        let user = """
        Liste alle sprechenden Personen der folgenden Geschichte auf. Für jede Person:
        - "name": genau wie im Text vor dem Doppelpunkt.
        - "role": eines von "male", "female", "boy", "girl" (nach Geschlecht und Alter der Person).
        Antworte als JSON-Objekt: {"speakers":[{"name":"Kyle","role":"male"},{"name":"Marie","role":"female"}]}

        GESCHICHTE:
        \(story.storyText)
        """
        do {
            let raw = try await mlxService.generateText(system: system, user: user, model: model, maxTokens: 200)
            guard let json = mlxService.extractJSON(from: raw, arrayKey: "speakers"),
                  let data = json.data(using: .utf8),
                  let response = try? JSONDecoder().decode(RawSpeakerResponse.self, from: data)
            else { return }

            var seen = Set<String>()
            var speakers: [StorySpeaker] = []
            for rawS in response.speakers {
                let name = (rawS.name ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " \t\"“”„:"))
                guard (1...40).contains(name.count) else { continue }
                let role = StorySpeaker.Role(rawValue: (rawS.role ?? "").lowercased()) ?? .female
                guard seen.insert(name.lowercased()).inserted else { continue }
                speakers.append(StorySpeaker(name: name, role: role))
            }
            if !speakers.isEmpty {
                story.setSpeakers(speakers)
                try? modelContext.save()
            }
        } catch {
            // Non-fatal.
        }
    }

    // MARK: - Step 2: questions

    private struct RawQuestion: Codable {
        var question: String?
        var sentence: String?   // models sometimes use "sentence" for the blank kinds
        var options: [String]?
        var correctIndex: Int?
        var answer: String?
        var evidence: String?
    }
    private struct RawQuestionResponse: Codable { var questions: [RawQuestion] }

    private func makeQuestions(for story: StudyStory, kind: StoryQuestion.Kind, count: Int) async -> [StoryQuestion] {
        guard count > 0 else { return [] }
        let seed = kind.promptSeed
        let system = "Du bist Prüfer für Leseverstehen (Niveau \(story.level.rawValue)). Antworte NUR mit gültigem JSON, ohne Markdown und ohne Erklärungen."
        // Over-generate by one so normalization can drop a bad item and still hit the target.
        let user = """
        Erstelle genau \(count + 1) Verständnisfragen zur folgenden Geschichte.
        \(seed.instruction)
        Antworte als JSON-Objekt: {"questions":[\(seed.exampleJSON), ...]}
        Regeln:
        - Alle Fragen und Antworten AUF DEUTSCH, nur über den Inhalt der Geschichte.
        - "evidence" ist der Satz aus der Geschichte, der die Antwort belegt — wörtlich zitiert.
        - Jede Frage muss sich klar von den anderen unterscheiden.

        GESCHICHTE:
        \(story.storyText)
        """
        do {
            let raw = try await mlxService.generateText(
                system: system, user: user, model: model,
                maxTokens: 250 + (count + 1) * 130
            )
            return normalizeQuestions(raw, kind: kind, count: count, story: story.storyText)
        } catch {
            return []
        }
    }

    private func normalizeQuestions(_ raw: String, kind: StoryQuestion.Kind, count: Int, story: String) -> [StoryQuestion] {
        guard let json = mlxService.extractJSON(from: raw, arrayKey: "questions"),
              let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(RawQuestionResponse.self, from: data)
        else { return [] }

        let storyLower = story.lowercased()
        var seen = Set<String>()
        var result: [StoryQuestion] = []

        for rawQ in response.questions {
            var text = (rawQ.question ?? rawQ.sentence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 4 else { continue }
            let options = (rawQ.options ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var answer = rawQ.answer?.trimmingCharacters(in: .whitespacesAndNewlines)
            var evidence = rawQ.evidence?.trimmingCharacters(in: .whitespacesAndNewlines)
            if evidence?.isEmpty == true { evidence = nil }

            // A quote that isn't actually from the story signals a fabricated question —
            // the main wrong-answer-key guard.
            if let quote = evidence, Self.wordOverlap(of: quote, in: storyLower) < 0.5 { continue }

            var finalOptions: [String] = []
            var finalCorrectIndex: Int?

            switch kind {
            case .multipleChoice, .fillInBlankChoices:
                guard let ci = rawQ.correctIndex, options.indices.contains(ci) else { continue }
                let correct = options[ci]
                // Distinct options only, preserving order.
                for option in options where !finalOptions.contains(where: { $0.caseInsensitiveCompare(option) == .orderedSame }) {
                    finalOptions.append(option)
                }
                guard finalOptions.count >= 2,
                      let newIndex = finalOptions.firstIndex(where: { $0.caseInsensitiveCompare(correct) == .orderedSame })
                else { continue }
                finalCorrectIndex = newIndex
                answer = correct
                if kind == .fillInBlankChoices {
                    guard let blanked = Self.ensureSingleBlank(in: text, answer: correct) else { continue }
                    text = blanked
                }
            case .fillInBlank:
                guard let a = answer, !a.isEmpty else { continue }
                guard let blanked = Self.ensureSingleBlank(in: text, answer: a) else { continue }
                text = blanked
            case .freeResponse:
                guard let a = answer, !a.isEmpty else { continue }
            }

            let key = text.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(StoryQuestion(
                kind: kind, question: text, options: finalOptions,
                correctIndex: finalCorrectIndex, answer: answer, evidence: evidence
            ))
            if result.count >= count { break }
        }
        return result
    }

    /// Canonicalize a blank sentence: exactly one ______ (six underscores). If the model wrote
    /// the sentence filled-in instead, blank out the answer's first occurrence.
    static func ensureSingleBlank(in sentence: String, answer: String) -> String? {
        var s = sentence.replacingOccurrences(of: #"_{3,}"#, with: "______", options: .regularExpression)
        let blanks = s.components(separatedBy: "______").count - 1
        if blanks == 1 { return s }
        if blanks > 1 { return nil } // two blanks, one answer — unanswerable
        if let range = s.range(of: answer, options: [.caseInsensitive, .diacriticInsensitive]) {
            s.replaceSubrange(range, with: "______")
            return s
        }
        return nil
    }

    /// Fraction of the quote's significant words that appear in the story (both lowercased).
    static func wordOverlap(of quote: String, in storyLower: String) -> Double {
        let words = quote.lowercased().split { !$0.isLetter }.filter { $0.count > 3 }
        guard !words.isEmpty else { return 1 }
        let hits = words.filter { storyLower.contains($0) }.count
        return Double(hits) / Double(words.count)
    }

    /// Split `total` across `parts` as evenly as possible; earlier parts take the remainder.
    static func splitCount(_ total: Int, across parts: Int) -> [Int] {
        guard parts > 0 else { return [] }
        let base = total / parts
        let remainder = total % parts
        return (0..<parts).map { base + ($0 < remainder ? 1 : 0) }
    }

    // MARK: - Step 3: glossary

    private func makeGlossary(for story: StudyStory) async {
        let system = """
        Wähle 5–8 schwierige oder wichtige Wörter aus der Geschichte und übersetze sie ins Englische. \
        Bei Nomen gib den Artikel mit an (z.B. „die Katze = cat“). \
        Antworte mit je einem Eintrag pro Zeile, GENAU im Format:
        deutsch = english
        Keine weiteren Erklärungen.
        """
        do {
            let raw = try await mlxService.generateText(
                system: system, user: "GESCHICHTE:\n\n\(story.storyText)", model: model, maxTokens: 220
            )
            let entries = Self.parsePairs(raw).map { GlossaryEntry(german: $0.0, english: $0.1) }
            if !entries.isEmpty {
                story.setGlossary(entries)
                try? modelContext.save()
            }
        } catch {
            // Non-fatal — the story reads fine without a glossary.
        }
    }

    /// Line-based `deutsch = english` extraction (same tolerant format as the paper service).
    static func parsePairs(_ raw: String) -> [(String, String)] {
        let cleaned = ConversationPrompts.stripThinkBlocks(raw)
        var result: [(String, String)] = []
        for line in cleaned.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let sep = trimmed.range(of: "=") ?? trimmed.range(of: " - ") ?? trimmed.range(of: " — ") else { continue }
            var german = String(trimmed[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
            german = german.trimmingCharacters(in: CharacterSet(charactersIn: "-•*0123456789. )"))
            let english = String(trimmed[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            if german.count >= 2, !english.isEmpty { result.append((german, english)) }
        }
        return result
    }

    // MARK: - On-demand translation

    /// Generate (once) and cache the story's English translation. Returns false on failure.
    ///
    /// Safe to call from two places at once: if the post-generation background pass already owns
    /// this story, the second caller returns immediately and just waits for `story.englishText`
    /// to appear (SwiftData observation refreshes the reader).
    func translateIfNeeded(for story: StudyStory) async -> Bool {
        if let existing = story.englishText, !existing.isEmpty { return true }
        guard StoryTranslationTracker.shared.begin(story.id) else { return true }
        isTranslating = true
        defer {
            isTranslating = false
            StoryTranslationTracker.shared.end(story.id)
        }
        guard await ensureModelReady() else { return false }

        let system = "You are a professional German-to-English translator. You only translate — you never continue, answer, or comment on the text."
        let user = """
        Translate the following German story into natural English. Keep the paragraph breaks. \
        Output ONLY the English translation.

        \(story.storyText)
        """
        do {
            let raw = try await mlxService.generateText(
                system: system, user: user, model: model,
                maxTokens: story.level.storyMaxTokens
            )
            let cleaned = ConversationPrompts.stripThinkBlocks(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count > 20 else { return false }
            story.englishText = cleaned
            try? modelContext.save()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Free-response grading

    nonisolated struct FreeResponseGrade: Equatable {
        /// 2 = correct, 1 = right idea with language slips (counts as correct), 0 = wrong.
        var score: Int
        var feedback: String
        /// An improved German version of the learner's answer, when the model offered one.
        var correction: String?
    }

    private struct RawGrade: Codable {
        var score: Int?
        var feedback: String?
        var korrektur: String?
    }

    /// Grade a learner's written answer against the story and the Musterantwort.
    /// Content-first: meaning outweighs grammar, which keeps it fair at A1/A2.
    func gradeFreeResponse(question: StoryQuestion, learnerAnswer: String, story: StudyStory) async -> FreeResponseGrade? {
        guard await ensureModelReady() else { return nil }
        let system = "Du bist Prüfer für Deutschlernende. Bewerte inhaltlich — Bedeutung zählt mehr als Grammatik. Antworte NUR mit gültigem JSON."
        let user = """
        GESCHICHTE:
        \(story.storyText)

        FRAGE: \(question.question)
        MUSTERANTWORT: \(question.answer ?? "")
        ANTWORT DES LERNENDEN: \(learnerAnswer)

        Bewerte die Antwort des Lernenden. Antworte als JSON-Objekt:
        {"score": 0 oder 1 oder 2, "feedback": "<one short, encouraging sentence in English>", "korrektur": "<verbesserte deutsche Version der Antwort, oder leer>"}
        Skala: 2 = inhaltlich richtig, 1 = richtige Idee mit Sprachfehlern oder nur teilweise richtig, 0 = inhaltlich falsch.
        """
        do {
            let raw = try await mlxService.generateText(system: system, user: user, model: model, maxTokens: 180)
            guard let json = mlxService.extractJSON(from: raw, arrayKey: "questions"),
                  let data = json.data(using: .utf8),
                  let grade = try? JSONDecoder().decode(RawGrade.self, from: data),
                  let score = grade.score, (0...2).contains(score)
            else { return nil }
            let correction = grade.korrektur?.trimmingCharacters(in: .whitespacesAndNewlines)
            return FreeResponseGrade(
                score: score,
                feedback: grade.feedback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                correction: (correction?.isEmpty == false) ? correction : nil
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Translation tracker

/// Which stories are having their English translation written right now, shared across every
/// `StoryStudyService` instance. The setup screen's background pass and the story screen each
/// build their own service, so without this they'd happily translate the same story twice; it
/// also lets the story screen show "Translating…" for a run it didn't start.
@Observable
@MainActor
final class StoryTranslationTracker {
    static let shared = StoryTranslationTracker()

    private(set) var inFlight: Set<UUID> = []

    private init() {}

    func isTranslating(_ storyID: UUID) -> Bool { inFlight.contains(storyID) }

    /// Claim the translation of `storyID`. False means someone else already owns it.
    func begin(_ storyID: UUID) -> Bool { inFlight.insert(storyID).inserted }

    func end(_ storyID: UUID) { inFlight.remove(storyID) }
}

// MARK: - Per-kind prompt seeds

private extension StoryQuestion.Kind {
    /// The per-kind instruction + one-shot JSON example (the grammar-exercise seed trick:
    /// one concrete shape per prompt beats describing four shapes at once).
    var promptSeed: (instruction: String, exampleJSON: String) {
        switch self {
        case .multipleChoice:
            (
                "Jede Frage hat genau 3 Antwortmöglichkeiten (\"options\"); genau eine ist richtig (\"correctIndex\", 0-basiert). Die falschen Optionen müssen plausibel klingen, aber laut Geschichte eindeutig falsch sein.",
                #"{"question":"Wo arbeitet Anna?","options":["im Krankenhaus","in der Schule","im Büro"],"correctIndex":0,"evidence":"Anna arbeitet als Ärztin im Krankenhaus."}"#
            )
        case .fillInBlank:
            (
                "Jede \"question\" ist ein Satz aus der Geschichte mit GENAU EINER Lücke, geschrieben als ______ (sechs Unterstriche). \"answer\" ist das eine Wort, das in die Lücke gehört.",
                #"{"question":"Anna arbeitet im ______.","answer":"Krankenhaus","evidence":"Anna arbeitet als Ärztin im Krankenhaus."}"#
            )
        case .fillInBlankChoices:
            (
                "Jede \"question\" ist ein Satz aus der Geschichte mit GENAU EINER Lücke, geschrieben als ______ (sechs Unterstriche). \"options\" enthält 3 Wörter: das richtige und 2 plausible falsche. \"correctIndex\" (0-basiert) zeigt auf das richtige.",
                #"{"question":"Anna arbeitet im ______.","options":["Krankenhaus","Büro","Supermarkt"],"correctIndex":0,"evidence":"Anna arbeitet als Ärztin im Krankenhaus."}"#
            )
        case .freeResponse:
            (
                "Jede Frage ist eine offene Verständnisfrage zur Geschichte. \"answer\" ist eine kurze Musterantwort (1–2 Sätze).",
                #"{"question":"Warum ist Anna am Abend müde?","answer":"Sie hat die ganze Nacht im Krankenhaus gearbeitet.","evidence":"Nach der langen Nachtschicht ist Anna sehr müde."}"#
            )
        }
    }
}
