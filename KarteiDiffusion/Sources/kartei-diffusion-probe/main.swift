import Foundation
import KarteiDiffusion
import MLX

// Renders bake-off prompts with the vendored engine, for the parity check against mflux and for
// timing and memory. Build with xcodebuild (SwiftPM's command line can't compile MLX's shaders):
//
//   xcodebuild -scheme kartei-diffusion-probe -destination 'platform=macOS,arch=arm64' \
//     -derivedDataPath .build/xcode build
//   .build/xcode/Build/Products/Debug/kartei-diffusion-probe --family zimage \
//     --model <mflux dir> --prompts prompts.json --ids c1,s1 --size 512 --out out/
//
// Prints one JSON line per image: seconds (excluding the prompt's encoding) and MLX's peak.

struct Options {
    var family = FamilyLoader.Family.zImageTurbo
    var model = ""
    var prompts = ""
    var ids: [String] = []
    var size = 512
    var seed = 42
    var out = "."
    var lowRam = false
    var half = false
    var cacheLimitMB: Int?
}

func parse() -> Options {
    var o = Options()
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let a = args.next() {
        switch a {
        case "--family": o.family = args.next() == "klein" ? .flux2Klein4B : .zImageTurbo
        case "--model": o.model = args.next() ?? ""
        case "--prompts": o.prompts = args.next() ?? ""
        case "--ids": o.ids = (args.next() ?? "").split(separator: ",").map(String.init)
        case "--size": o.size = Int(args.next() ?? "") ?? 512
        case "--seed": o.seed = Int(args.next() ?? "") ?? 42
        case "--out": o.out = args.next() ?? "."
        case "--low-ram": o.lowRam = true
        case "--half": o.half = true
        case "--cache-limit-mb": o.cacheLimitMB = Int(args.next() ?? "")
        default: FileHandle.standardError.write("unknown argument \(a)\n".data(using: .utf8)!)
        }
    }
    return o
}

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    fflush(stdout)
}

let o = parse()
let gb = 1024.0 * 1024 * 1024
if let mb = o.cacheLimitMB { Memory.cacheLimit = mb * 1024 * 1024 }

let promptList = (try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: o.prompts))) as! [[String: Any]])
let wanted = o.ids.isEmpty ? promptList : promptList.filter { o.ids.contains($0["id"] as! String) }

Memory.peakMemory = 0
var t = Date()
let model = try FamilyLoader.load(o.family, modelPath: URL(fileURLWithPath: o.model))
model.lowRam = o.lowRam
model.releasesPromptReader = o.lowRam
emit(["event": "loaded", "seconds": Date().timeIntervalSince(t), "bits": model.bits ?? 0,
      "activeGB": Double(Memory.activeMemory) / gb])

// Every prompt first, as the engine does, so the encoder's work and peak are out of the timings.
t = Date()
for p in wanted { try model.encode(p["prompt"] as! String) }
model.promptsEncoded()
Memory.clearCache()
emit(["event": "encoded", "count": wanted.count, "seconds": Date().timeIntervalSince(t),
      "peakGB": Double(Memory.peakMemory) / gb, "activeGB": Double(Memory.activeMemory) / gb])

let steps = o.family == .zImageTurbo ? 9 : 4
let tag = o.family == .zImageTurbo ? "zimage" : "klein"
try FileManager.default.createDirectory(atPath: o.out, withIntermediateDirectories: true)
for (i, p) in wanted.enumerated() {
    let id = p["id"] as! String
    let request = FamilyRequest(
        prompt: p["prompt"] as! String, seed: o.seed, width: o.size, height: o.size,
        steps: steps, guidance: o.family == .zImageTurbo ? 0 : 1, flattenAlpha: true, halfPrecision: o.half
    )
    Memory.clearCache()
    Memory.peakMemory = 0
    t = Date()
    let image = try model.generate(request, phase: { _ in }, progress: { _, _ in }, isCancelled: { false })
    let seconds = Date().timeIntervalSince(t)
    let url = URL(fileURLWithPath: o.out).appendingPathComponent("\(id).png")
    try ImageOutput.writePNG(image.pixels, to: url, source: .trainedAlgorithmicMedia, metadata: ["prompt": request.prompt, "seed": o.seed])
    emit(["event": "image", "id": id, "index": i, "model": tag, "size": o.size, "seconds": seconds,
          "peakGB": Double(Memory.peakMemory) / gb, "path": url.path])
}
