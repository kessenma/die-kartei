import DieKarteiCore
import Foundation
import ImageIO
import Vision

/// Extracts German text from a photo using Apple's on-device Vision text recognizer,
/// then cleans the raw OCR output into readable study text with an MLX model.
/// Beta feature — the AI cleanup step may make mistakes.
@Observable
@MainActor
final class PhotoOCRService {

    enum Phase: Equatable {
        case idle
        case scanning
        case cleaning
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var statusText: String = ""
    /// The model used for the cleanup pass (set when cleanup starts; shown in the progress sheet).
    private(set) var model: MLXModel?

    var isRunning: Bool {
        switch phase {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    // MARK: - OCR (Apple Vision)

    /// Recognize German text in the photo. Tries the photo's embedded orientation first and
    /// falls back to rotations, since photos of book pages are often taken sideways.
    func extractText(from imageData: Data) async -> Result<String, Error> {
        phase = .scanning
        progress = 0.02
        statusText = "Reading text…"

        do {
            var best = try await recognize(imageData, orientation: nil)
            if best.count < 80 {
                for orientation: CGImagePropertyOrientation in [.right, .left, .down] {
                    let candidate = (try? await recognize(imageData, orientation: orientation)) ?? ""
                    if candidate.count > best.count { best = candidate }
                    if best.count >= 80 { break }
                }
            }
            let trimmed = best.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw PhotoOCRError.noTextFound }
            progress = 0.1
            return .success(trimmed)
        } catch {
            phase = .failed(error.localizedDescription)
            return .failure(error)
        }
    }

    private func recognize(_ data: Data, orientation: CGImagePropertyOrientation?) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [
            Locale.Language(identifier: "de-DE"),
            Locale.Language(identifier: "en-US")
        ]
        request.usesLanguageCorrection = true

        let observations: [RecognizedTextObservation]
        if let orientation {
            observations = try await request.perform(on: data, orientation: orientation)
        } else {
            observations = try await request.perform(on: data)
        }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    // MARK: - AI cleanup

    /// Reformat raw OCR text into clean study text using the given model.
    /// Falls back to the raw text if the model can't load or a chunk fails.
    func cleanupText(_ raw: String, mlxService: MLXGenerationService, model: MLXModel) async -> String {
        phase = .cleaning
        self.model = model
        statusText = "Loading \(model.rawValue)…"

        if !mlxService.isModelLoaded || mlxService.currentModel != model {
            await mlxService.loadModel(model)
        }
        guard mlxService.isModelLoaded, mlxService.currentModel == model else {
            // Cleanup is best-effort: study generation can still run on the raw text.
            phase = .done
            return raw
        }

        statusText = "Tidying up the scanned text…"
        let chunks = PDFTextExtractor.chunk(raw, maxChars: 1200)
        let chunkCap = min(chunks.count, 6)
        var cleaned: [String] = []

        let system = """
        Du bekommst rohen OCR-Text aus einem Foto von deutschem Lernmaterial (z.B. Buchseite, \
        Vokabelliste, Tabelle). Rekonstruiere daraus sauberen, lesbaren Text: korrigiere \
        offensichtliche Scanfehler und führe zusammengehörige Tabellenspalten zeilenweise zusammen \
        (z.B. „abfahren – fährt ab – fuhr ab – ist abgefahren“). \
        Lass nichts weg und erfinde nichts dazu. Gib NUR den bereinigten Text aus, ohne Erklärungen.
        """

        for (index, chunk) in chunks.prefix(chunkCap).enumerated() {
            do {
                let out = try await mlxService.generateText(
                    system: system,
                    user: "OCR-Text:\n\n\(chunk)",
                    model: model,
                    maxTokens: 700
                )
                let visible = ConversationPrompts.stripThinkBlocks(out)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cleaned.append(visible.isEmpty ? chunk : visible)
            } catch {
                cleaned.append(chunk)  // keep the raw chunk if cleanup fails
            }
            progress = 0.1 + 0.85 * (Double(index + 1) / Double(chunkCap))
        }
        if chunks.count > chunkCap {
            cleaned.append(contentsOf: chunks.suffix(from: chunkCap))
        }

        progress = 1
        phase = .done
        statusText = "Scan complete."
        return cleaned.joined(separator: "\n\n")
    }
}

private enum PhotoOCRError: LocalizedError {
    case noTextFound

    var errorDescription: String? {
        "No readable text was found in that photo. Try a sharper, closer shot."
    }
}
