// hoeren-cli: the Worum geht's? judge probe (training/GIST_PROBE.md).
//
//   hoeren-cli prompts <fixtures.json> <kasus_stories.json>   > results/gist-probe/prompts.jsonl
//       One record per judgeable summary, in the shape scripts/kasus_concept_probe.py reads, so the
//       MLX tutors run through that script unchanged. Summaries the app would not send (under four
//       words) are listed on stderr as gated.
//   hoeren-cli fm-run <prompts.jsonl> <out.jsonl>
//       The same prompts on Apple Intelligence (FoundationModels), written as raw_apple.jsonl.
//   hoeren-cli score <fixtures.json> <raw_*.jsonl …>
//       Parses every answer with the app's own parser and compares it with the gold labels.
//       Prints a markdown table; no thresholds.

import Foundation
import FoundationModels

struct Fixture: Decodable {
    struct Summary: Decodable {
        let type: String
        let text: String
        let gold: [String]
    }
    struct Story: Decodable {
        let id: String
        let title: String?
        let text: String?
        let keyPoints: [String]
        let summaries: [Summary]
    }
    let stories: [Story]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func readJSONL(_ path: String) -> [[String: Any]] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    return text.split(separator: "\n").compactMap {
        (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
    }
}

func writeLine(_ object: [String: Any], to handle: FileHandle) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    handle.write(data)
    handle.write("\n".data(using: .utf8)!)
}

func loadFixtures(_ path: String) -> Fixture {
    guard let data = FileManager.default.contents(atPath: path),
          let fixture = try? JSONDecoder().decode(Fixture.self, from: data) else { fail("cannot decode \(path)") }
    return fixture
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: hoeren-cli prompts|fm-run|score …") }

switch args[1] {

case "prompts":
    guard args.count == 4 else { fail("usage: hoeren-cli prompts <fixtures.json> <kasus_stories.json>") }
    let fixture = loadFixtures(args[2])
    // The judge never sees the story text, only the points and the summary, exactly as in the app.
    // The Kasus file is read only to confirm every fixture names a real story.
    guard let kasusData = FileManager.default.contents(atPath: args[3]),
          let kasus = try? JSONSerialization.jsonObject(with: kasusData) as? [String: Any],
          let stories = kasus["stories"] as? [[String: Any]] else { fail("cannot read \(args[3])") }
    let known = Set(stories.compactMap { $0["id"] as? String })
    var seed = 1000
    var gated: [String] = []
    for story in fixture.stories {
        if story.text == nil, !known.contains(story.id) { fail("unknown story \(story.id)") }
        for summary in story.summaries {
            let id = "\(story.id)|\(summary.type)"
            guard GistPrompts.isJudgeable(summary.text) else { gated.append(id); continue }
            seed += 1
            writeLine([
                "id": id, "seed": seed, "kind": "gist", "unit": summary.type,
                "system": GistPrompts.judgeSystem,
                "user": GistPrompts.judgeUser(summary: summary.text, points: story.keyPoints),
                // The app's generateText samples at 0.1.
                "temperature": 0.1, "maxTokens": 160,
                "plan": ["story": story.id, "type": summary.type, "points": story.keyPoints.count],
            ], to: .standardOutput)
        }
    }
    FileHandle.standardError.write("gated (not sent, as in the app): \(gated.joined(separator: ", "))\n".data(using: .utf8)!)

case "fm-run":
    guard args.count == 4 else { fail("usage: hoeren-cli fm-run <prompts.jsonl> <out.jsonl>") }
    let records = readJSONL(args[2])
    guard SystemLanguageModel.default.availability == .available else { fail("Apple Intelligence is not available") }
    FileManager.default.createFile(atPath: args[3], contents: nil)
    guard let out = FileHandle(forWritingAtPath: args[3]) else { fail("cannot write \(args[3])") }
    for (n, record) in records.enumerated() {
        let system = record["system"] as? String ?? ""
        let user = record["user"] as? String ?? ""
        let start = Date()
        var raw = "", failure: String? = nil
        do {
            let session = LanguageModelSession(instructions: system)
            let options = GenerationOptions(temperature: 0.1, maximumResponseTokens: record["maxTokens"] as? Int ?? 160)
            raw = try await session.respond(to: user, options: options).content
        } catch {
            failure = "\(error)"
        }
        var line: [String: Any] = [
            "id": record["id"] ?? "", "model": "apple", "repeat": 0, "seed": record["seed"] ?? 0,
            "kind": "gist", "unit": record["unit"] ?? "", "plan": record["plan"] ?? [:],
            "raw": raw, "seconds": (Date().timeIntervalSince(start) * 100).rounded() / 100,
        ]
        if let failure { line["error"] = failure }
        writeLine(line, to: out)
        print("apple \(n + 1)/\(records.count) \(record["id"] ?? "") \(raw.split(separator: "\n").first ?? "")")
    }

case "score":
    guard args.count >= 4 else { fail("usage: hoeren-cli score <fixtures.json> <raw_*.jsonl …>") }
    let fixture = loadFixtures(args[2])
    var gold: [String: [GistVerdict]] = [:]
    for story in fixture.stories {
        for s in story.summaries {
            gold["\(story.id)|\(s.type)"] = s.gold.compactMap(GistVerdict.init(rawValue:))
        }
    }
    let types = ["full", "partial", "vague", "wrong_detail", "off_topic", "german", "copied_point"]
    print("| Model | Points | Agree | False yes | Over-credit | False no | Unparseable | Score error (pts) | s / answer |")
    print("|---|---|---|---|---|---|---|---|---|")
    var byType: [String: [String: (agree: Int, total: Int)]] = [:]
    var labels: [String] = []
    for path in args[3...] {
        let rows = readJSONL(path)
        guard let label = rows.first?["model"] as? String else { continue }
        labels.append(label)
        var points = 0, agree = 0, falseYes = 0, overCredit = 0, falseNo = 0, unparseable = 0
        var scoreError = 0.0, seconds = 0.0, answers = 0
        for row in rows {
            guard let id = row["id"] as? String, let expected = gold[id] else { continue }
            let raw = row["raw"] as? String ?? ""
            let verdicts = GistPrompts.parseJudge(raw, count: expected.count)
            answers += 1
            seconds += row["seconds"] as? Double ?? 0
            let type = (row["unit"] as? String) ?? ""
            scoreError += abs(Double(GistPrompts.scoreHalves(verdicts) - GistPrompts.scoreHalves(expected)) / 2)
            for (v, g) in zip(verdicts, expected) {
                points += 1
                var cell = byType[type, default: [:]][label, default: (0, 0)]
                cell.total += 1
                guard let v else { unparseable += 1; byType[type, default: [:]][label] = cell; continue }
                if v == g { agree += 1; cell.agree += 1 }
                if g == .nein && v == .ja { falseYes += 1 }
                if v.halves > g.halves { overCredit += 1 }
                if g == .ja && v == .nein { falseNo += 1 }
                byType[type, default: [:]][label] = cell
            }
        }
        func pct(_ n: Int) -> String { points == 0 ? "–" : String(format: "%.0f%%", Double(n) / Double(points) * 100) }
        print("| \(label) | \(points) | \(pct(agree)) | \(pct(falseYes)) | \(pct(overCredit)) | \(pct(falseNo)) | \(pct(unparseable)) | \(String(format: "%.2f", answers == 0 ? 0 : scoreError / Double(answers))) | \(String(format: "%.1f", answers == 0 ? 0 : seconds / Double(answers))) |")
    }
    print("")
    print("Agreement by summary type:")
    print("")
    print("| Type | " + labels.joined(separator: " | ") + " |")
    print("|---|" + labels.map { _ in "---" }.joined(separator: "|") + "|")
    for type in types {
        let cells = labels.map { label -> String in
            guard let c = byType[type]?[label], c.total > 0 else { return "–" }
            return String(format: "%.0f%%", Double(c.agree) / Double(c.total) * 100)
        }
        print("| \(type) | " + cells.joined(separator: " | ") + " |")
    }

default:
    fail("unknown command \(args[1])")
}
