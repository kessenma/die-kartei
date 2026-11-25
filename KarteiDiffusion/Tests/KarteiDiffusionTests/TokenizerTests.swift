import Foundation
import Testing
@testable import KarteiDiffusion

// The BPE tokenizer is the one piece that needs no Metal, so it's the one piece tested here: the
// ids must match Hugging Face's tokenizer.json. Reference ids come from the bake-off venv:
// `AutoTokenizer.from_pretrained("models/zimage/tokenizer").encode(s, add_special_tokens=False)`.
// Skipped when the tokenizer isn't on this machine (set KARTEI_TOKENIZER_DIR to point elsewhere).

private let tokenizerDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KARTEI_TOKENIZER_DIR"]
    ?? "/Users/ke/ws/german-flashcards/german-ai-flashcards/training/imagegen/bakeoff/models/zimage/tokenizer")
private let hasTokenizer = FileManager.default.fileExists(atPath: tokenizerDir.appendingPathComponent("tokenizer.json").path)

@Test(.enabled(if: hasTokenizer), arguments: [
    ("a single bicycle, loose watercolor painting on white paper",
     [64, 3175, 34986, 11, 20174, 3015, 3423, 18824, 389, 4158, 5567]),
    ("Bäckerei Müller, „Grüß Gott“ — 1024×1024!",
     [33, 2305, 377, 485, 72, 98918, 11, 14835, 6464, 134215, 68009, 2073, 1959, 220, 16, 15, 17, 19, 17568, 16, 15, 17, 19, 0]),
])
func tokenizerMatchesHuggingFace(text: String, expected: [Int]) throws {
    let tokenizer = try BPETokenizer(folder: tokenizerDir)
    #expect(tokenizer.encode(text, addSpecialTokens: false) == expected)
}
