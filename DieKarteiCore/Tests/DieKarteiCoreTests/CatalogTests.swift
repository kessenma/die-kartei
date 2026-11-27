import Foundation
import Testing
@testable import DieKarteiCore

/// The GGUF catalog the Android app downloads from must match what was published.
struct CatalogTests {
    @Test func everyTutorHasAGGUFFile() {
        #expect(MLXModel.ggufTutors.count == MLXModel.allCases.count - 1)
        #expect(MLXModel.appleIntelligence.gguf == nil)
        let names = MLXModel.ggufTutors.compactMap { $0.gguf?.fileName }
        #expect(Set(names).count == MLXModel.ggufTutors.count)
        for model in MLXModel.ggufTutors {
            let file = try! #require(model.gguf)
            #expect(file.sha256.count == 64 && file.sha256.allSatisfy(\.isHexDigit))
            #expect(file.downloadURL.absoluteString == "https://huggingface.co/\(file.repoID)/resolve/main/\(file.fileName)")
            #expect(file.fileName.hasSuffix("-\(file.quant).gguf"))
            // Same family as the prompt format, so the right chat template is written.
            #expect(file.fileName.hasPrefix(ChatPromptFormat(model).rawValue))
        }
    }

    /// publish_gguf.py writes every uploaded file's size and hash here; the app's table must agree.
    @Test func catalogMatchesThePublishedFiles() throws {
        let json = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("training/releases/gguf_release.json")
        let published = try JSONSerialization.jsonObject(with: Data(contentsOf: json)) as! [String: [String: Any]]
        for model in MLXModel.ggufTutors {
            let file = try #require(model.gguf)
            let entry = try #require(published[file.fileName], "\(file.fileName) was never published")
            #expect(entry["repo"] as? String == file.repoID)
            #expect((entry["bytes"] as? NSNumber)?.int64Value == file.bytes)
            #expect(entry["sha256"] as? String == file.sha256)
        }
    }
}
