// Run the German grammar eval against Apple Intelligence's on-device model
// (FoundationModels framework) and emit raw responses for the shared scorer.
//
// Build + run (from training/):
//   swiftc scripts/eval_apple_intelligence.swift -o /tmp/eval_ai
//   /tmp/eval_ai --eval-file data/eval/grammar_eval_v0.json --out results/apple_ai_core.responses.json
//   /tmp/eval_ai --eval-file data/eval/grammar_eval_v1_extra.json --out results/apple_ai_ext.responses.json
//
// Then score with the exact same rubric as every MLX model:
//   .venv/bin/python scripts/run_baseline_eval.py \
//       --responses results/apple_ai_core.responses.json --tag baseline --model apple-intelligence
//
// Requires macOS 26+/Xcode 26 with Apple Intelligence enabled and the model downloaded.
// Prompts mirror run_baseline_eval.py's CORRECTION_SYSTEM / CLOZE_SYSTEM verbatim so the
// only variable vs. the MLX runs is the model itself.

import Foundation
import FoundationModels

// ---- prompts (kept in lockstep with run_baseline_eval.py) ----
let CORRECTION_SYSTEM = """
You are a meticulous German teacher reviewing one line a student said during a spoken conversation. \
The student's level is B1. Correct clear grammar mistakes, but ignore minor style issues. \
The student uses the du form. \
They may have mixed in an English word they didn't know — in your correction, replace it with the correct German word.

If the sentence is already correct and natural German, reply with exactly:
OK

Otherwise reply in EXACTLY this format and nothing else:
FIX: <the full corrected sentence in natural German>
WHY: <one short explanation in English, at most 18 words>
"""

let CLOZE_SYSTEM = """
Du bist ein präziser Deutschlehrer. Antworte nur mit dem fehlenden Wort oder der fehlenden Form, \
ohne Erklärung und ohne zusätzliche Wörter.
"""

// ---- args ----
var evalPath = "", outPath = "", limit = 0
do {
    let a = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < a.count {
        switch a[i] {
        case "--eval-file": i += 1; evalPath = i < a.count ? a[i] : ""
        case "--out":       i += 1; outPath = i < a.count ? a[i] : ""
        case "--limit":     i += 1; limit = i < a.count ? (Int(a[i]) ?? 0) : 0
        default: break
        }
        i += 1
    }
}
func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
guard !evalPath.isEmpty, !outPath.isEmpty else {
    err("usage: eval_apple_intelligence --eval-file <path> --out <path> [--limit N]")
    exit(2)
}

// ---- eval items (only the fields we need to prompt; scoring stays in Python) ----
struct EvalItem: Decodable { let id: String; let mode: String; let input: String; let partner: String? }
struct EvalFile: Decodable { let items: [EvalItem] }

var items = try JSONDecoder().decode(EvalFile.self, from: Data(contentsOf: URL(fileURLWithPath: evalPath))).items
if limit > 0 { items = Array(items.prefix(limit)) }

func userPrompt(_ item: EvalItem) -> String {
    guard item.mode == "correction" else { return item.input }
    if let p = item.partner, !p.isEmpty {
        return "The conversation partner just said: \"\(p)\"\nThe student replied: \"\(item.input)\"\n\nEvaluate only the student's reply."
    }
    return "The student said: \"\(item.input)\"\n\nEvaluate the student's sentence."
}

// ---- availability ----
switch SystemLanguageModel.default.availability {
case .available:
    break
case .unavailable(let reason):
    err("Apple Intelligence unavailable: \(reason)")
    exit(1)
@unknown default:
    err("Apple Intelligence availability unknown")
    exit(1)
}

// ---- run ----
struct OutItem: Encodable { let id: String; let response: String }
struct OutFile: Encodable { let model: String; let results: [OutItem] }

var out: [OutItem] = []
for (idx, item) in items.enumerated() {
    let sys = item.mode == "correction" ? CORRECTION_SYSTEM : CLOZE_SYSTEM
    let maxTok = item.mode == "cloze" ? 150 : 400
    // Fresh session per item — stateless, matching the Python harness (no context carryover).
    let session = LanguageModelSession(instructions: sys)
    var response: String
    do {
        let r = try await session.respond(
            to: userPrompt(item),
            options: GenerationOptions(temperature: 0, maximumResponseTokens: maxTok)
        )
        response = r.content
    } catch {
        // Guardrail refusals / errors are recorded verbatim so they score honestly as failures.
        response = "<<ERROR: \(error)>>"
    }
    out.append(OutItem(id: item.id, response: response))
    err("[\(idx + 1)/\(items.count)] \(item.id)")
}

let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
try enc.encode(OutFile(model: "apple-intelligence-ondevice", results: out))
    .write(to: URL(fileURLWithPath: outPath))
err("wrote \(out.count) responses to \(outPath)")
