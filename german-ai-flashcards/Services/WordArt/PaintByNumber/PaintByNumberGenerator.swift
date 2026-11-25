import CoreGraphics
import Foundation

/// A paint-by-number picture: numbered regions ("facets"), the colour for each number with its
/// German name, and where each number sits. Saved as `<id>.pbn.json` next to the picture.
///
/// The regions are kept as a raster, one facet id per pixel of a `side`×`side` map (zlib-compressed
/// in the file), not as vector outlines: a tap is a lookup, filling is a recolour, and the label
/// spot comes from a distance transform. The picture is rendered from it at twice the map's size.
nonisolated struct PaintByNumberTemplate: Codable, Equatable, Sendable {
    struct Swatch: Codable, Equatable, Sendable {
        /// 1-based, what the learner reads on the picture.
        let number: Int
        let red: Double, green: Double, blue: Double
        /// „dunkelrot“.
        let name: String
    }

    struct Label: Codable, Equatable, Sendable {
        /// Centre of the number, in map pixels.
        let x: Double, y: Double
        /// Radius of the largest circle that fits in the region at that spot, in map pixels.
        let room: Double
    }

    var version = 1
    let side: Int
    let difficultyRaw: String
    let palette: [Swatch]
    /// Facet id → index into `palette`.
    let facetSwatch: [Int]
    /// Facet id → where its number goes.
    let labels: [Label]
    /// `side * side` little-endian UInt16 facet ids, zlib-compressed.
    let facetMapData: Data

    var facetCount: Int { facetSwatch.count }

    /// The facet id per pixel, row by row.
    func facetMap() -> [UInt16] {
        let raw = (try? (facetMapData as NSData).decompressed(using: .zlib) as Data) ?? Data()
        var map = [UInt16](repeating: 0, count: side * side)
        guard raw.count == side * side * 2 else { return map }
        raw.withUnsafeBytes { buffer in
            for i in 0..<(side * side) {
                map[i] = UInt16(buffer[2 * i]) | (UInt16(buffer[2 * i + 1]) << 8)
            }
        }
        return map
    }

    static func encodeMap(_ map: [UInt16]) -> Data {
        var raw = Data(capacity: map.count * 2)
        for id in map {
            raw.append(UInt8(id & 0xFF))
            raw.append(UInt8(id >> 8))
        }
        return (try? (raw as NSData).compressed(using: .zlib) as Data) ?? raw
    }
}

/// Which facets are painted. `<id>.progress.json`.
nonisolated struct PaintByNumberProgress: Codable, Equatable, Sendable {
    var filled: Set<Int> = []
    var updatedAt = Date()
}

nonisolated enum PaintByNumberDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case leicht, mittel, schwer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leicht: "Leicht · Easy"
        case .mittel: "Mittel · Medium"
        case .schwer: "Schwer · Hard"
        }
    }

    /// Colours in the palette.
    var colors: Int {
        switch self {
        case .leicht: 8
        case .mittel: 14
        case .schwer: 20
        }
    }

    /// Smallest region, as a share of the picture: smaller regions merge into a neighbour.
    var minAreaFraction: Double {
        switch self {
        case .leicht: 0.004
        case .mittel: 0.0022
        case .schwer: 0.0012
        }
    }
}

/// Turns a picture into a `PaintByNumberTemplate`. Pure and deterministic for a given picture,
/// difficulty and seed. The pipeline follows drakarah/paintbynumbersgenerator (MIT): k-means in
/// Lab, a smoothing pass, regions by flood fill, small regions merged away, labels at the point
/// furthest from the region's edge (a raster pole of inaccessibility, as Mapbox's polylabel
/// finds for polygons).
///
/// Off the main actor: a 480² picture is a quarter-million pixels.
nonisolated enum PaintByNumberGenerator {
    static let side = 480

    static func make(from image: CGImage, difficulty: PaintByNumberDifficulty, seed: UInt64 = 7) -> PaintByNumberTemplate? {
        guard let rgba = pixels(of: image, side: side) else { return nil }
        return make(rgba: rgba, side: side, difficulty: difficulty, seed: seed)
    }

    /// The pipeline on raw RGBA bytes, `side`×`side`. Split out so tests can feed synthetic pictures.
    static func make(rgba: [UInt8], side: Int, difficulty: PaintByNumberDifficulty, seed: UInt64 = 7) -> PaintByNumberTemplate? {
        let n = side * side
        guard rgba.count >= n * 4, n > 0 else { return nil }

        // 1. Lab per pixel.
        var labs = [ColorLab.Lab](repeating: ColorLab.Lab(l: 0, a: 0, b: 0), count: n)
        for i in 0..<n {
            let r = Double(rgba[4 * i]) / 255
            let g = Double(rgba[4 * i + 1]) / 255
            let b = Double(rgba[4 * i + 2]) / 255
            labs[i] = ColorLab.lab(red: r, green: g, blue: b)
        }

        // 2. k-means → a colour label per pixel.
        let centers = kmeans(labs, k: difficulty.colors, seed: seed)
        var label = [UInt8](repeating: 0, count: n)
        for i in 0..<n { label[i] = UInt8(nearest(labs[i], in: centers)) }

        // 3. Smooth: a 3×3 majority vote, twice.
        for _ in 0..<2 { label = modeFilter(label, side: side, colors: centers.count) }

        // 4–5. Regions, with small ones merged into their neighbours.
        let minArea = max(4, Int(difficulty.minAreaFraction * Double(n)))
        var (facetOf, facetColor) = facets(label, side: side)
        mergeSmall(&facetOf, &facetColor, side: side, minArea: minArea, centers: centers)

        // 6. Compact the ids and number the colours that are left, the most-used first.
        var remap: [Int32: Int] = [:]
        var facetSwatchRaw: [Int] = []
        var map = [UInt16](repeating: 0, count: n)
        var area: [Int: Int] = [:]
        for i in 0..<n {
            let old = facetOf[i]
            let id: Int
            if let known = remap[old] { id = known } else {
                id = facetSwatchRaw.count
                remap[old] = id
                facetSwatchRaw.append(facetColor[Int(old)])
            }
            map[i] = UInt16(id)
            area[facetSwatchRaw[id], default: 0] += 1
        }
        let usedColors = area.keys.sorted { (area[$0]!, -$0) > (area[$1]!, -$1) }
        let colorIndex = Dictionary(uniqueKeysWithValues: usedColors.enumerated().map { ($1, $0) })
        let paletteLabs = usedColors.map { centers[$0] }
        let names = GermanColorName.uniqueNames(for: paletteLabs)
        let palette = paletteLabs.enumerated().map { index, lab in
            let rgb = ColorLab.rgb(lab)
            return PaintByNumberTemplate.Swatch(number: index + 1, red: rgb.red, green: rgb.green, blue: rgb.blue,
                                                name: names[index])
        }
        let facetSwatch = facetSwatchRaw.map { colorIndex[$0]! }

        // 7. Labels.
        let labels = placeLabels(map, side: side, facets: facetSwatch.count)

        return PaintByNumberTemplate(side: side, difficultyRaw: difficulty.rawValue, palette: palette,
                                     facetSwatch: facetSwatch, labels: labels,
                                     facetMapData: PaintByNumberTemplate.encodeMap(map))
    }

    // MARK: - Steps

    /// The picture drawn into an sRGB `side`×`side` RGBA buffer over white.
    static func pixels(of image: CGImage, side: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 255, count: side * side * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .high
            // Square-crop a non-square picture to its centre.
            let w = Double(image.width), h = Double(image.height)
            let scale = Double(side) / min(w, h)
            let drawW = w * scale, drawH = h * scale
            context.draw(image, in: CGRect(x: (Double(side) - drawW) / 2, y: (Double(side) - drawH) / 2,
                                           width: drawW, height: drawH))
            return true
        }
        return ok ? buffer : nil
    }

    /// k-means++ on a sample of the pixels, seeded, so the same picture gives the same palette.
    static func kmeans(_ labs: [ColorLab.Lab], k: Int, seed: UInt64, iterations: Int = 12) -> [ColorLab.Lab] {
        var rng = SeededGenerator(seed: seed)
        let stride = max(1, labs.count / 40_000)
        let sample = Swift.stride(from: 0, to: labs.count, by: stride).map { labs[$0] }
        guard !sample.isEmpty else { return [] }

        var centers = [sample[Int.random(in: 0..<sample.count, using: &rng)]]
        var nearestDistance = sample.map { $0.distance(to: centers[0]) }
        while centers.count < min(k, sample.count) {
            let total = nearestDistance.reduce(0) { $0 + $1 * $1 }
            guard total > 0 else { break }
            var target = Double.random(in: 0..<total, using: &rng)
            var pick = sample.count - 1
            for (i, d) in nearestDistance.enumerated() {
                target -= d * d
                if target <= 0 { pick = i; break }
            }
            centers.append(sample[pick])
            for i in sample.indices {
                nearestDistance[i] = min(nearestDistance[i], sample[i].distance(to: sample[pick]))
            }
        }

        for _ in 0..<iterations {
            var sums = [(l: Double, a: Double, b: Double, n: Int)](repeating: (0, 0, 0, 0), count: centers.count)
            for lab in sample {
                let c = nearest(lab, in: centers)
                sums[c].l += lab.l; sums[c].a += lab.a; sums[c].b += lab.b; sums[c].n += 1
            }
            var moved = false
            for c in centers.indices where sums[c].n > 0 {
                let count = Double(sums[c].n)
                let next = ColorLab.Lab(l: sums[c].l / count, a: sums[c].a / count, b: sums[c].b / count)
                if next.distance(to: centers[c]) > 0.5 { moved = true }
                centers[c] = next
            }
            if !moved { break }
        }
        return centers
    }

    static func nearest(_ lab: ColorLab.Lab, in centers: [ColorLab.Lab]) -> Int {
        var best = 0, bestDistance = Double.infinity
        for (i, c) in centers.enumerated() {
            let dl = lab.l - c.l, da = lab.a - c.a, db = lab.b - c.b
            let d = dl * dl + da * da + db * db
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }

    static func modeFilter(_ label: [UInt8], side: Int, colors: Int) -> [UInt8] {
        var out = label
        var counts = [Int](repeating: 0, count: max(colors, 1))
        for y in 0..<side {
            for x in 0..<side {
                for i in counts.indices { counts[i] = 0 }
                for dy in -1...1 {
                    let yy = y + dy
                    guard yy >= 0, yy < side else { continue }
                    for dx in -1...1 {
                        let xx = x + dx
                        guard xx >= 0, xx < side else { continue }
                        counts[Int(label[yy * side + xx])] += 1
                    }
                }
                let own = Int(label[y * side + x])
                var best = own
                for c in counts.indices where counts[c] > counts[best] { best = c }
                out[y * side + x] = UInt8(best)
            }
        }
        return out
    }

    /// 4-connected regions of one colour. Returns the facet per pixel and the colour per facet.
    static func facets(_ label: [UInt8], side: Int) -> (facetOf: [Int32], facetColor: [Int]) {
        let n = side * side
        var facetOf = [Int32](repeating: -1, count: n)
        var facetColor: [Int] = []
        var stack: [Int] = []
        for start in 0..<n where facetOf[start] < 0 {
            let id = Int32(facetColor.count)
            let color = label[start]
            facetColor.append(Int(color))
            facetOf[start] = id
            stack.append(start)
            while let p = stack.popLast() {
                let x = p % side, y = p / side
                if x > 0, facetOf[p - 1] < 0, label[p - 1] == color { facetOf[p - 1] = id; stack.append(p - 1) }
                if x < side - 1, facetOf[p + 1] < 0, label[p + 1] == color { facetOf[p + 1] = id; stack.append(p + 1) }
                if y > 0, facetOf[p - side] < 0, label[p - side] == color { facetOf[p - side] = id; stack.append(p - side) }
                if y < side - 1, facetOf[p + side] < 0, label[p + side] == color { facetOf[p + side] = id; stack.append(p + side) }
            }
        }
        return (facetOf, facetColor)
    }

    /// Merge every region smaller than `minArea` into the neighbour it shares the longest border
    /// with (the nearer colour on a tie), smallest first, until none is left.
    static func mergeSmall(_ facetOf: inout [Int32], _ facetColor: inout [Int], side: Int, minArea: Int,
                           centers: [ColorLab.Lab]) {
        var pixelsOf = [[Int]](repeating: [], count: facetColor.count)
        for (p, f) in facetOf.enumerated() { pixelsOf[Int(f)].append(p) }
        var alive = [Bool](repeating: true, count: facetColor.count)

        for _ in 0..<12 {
            let small = pixelsOf.indices
                .filter { alive[$0] && pixelsOf[$0].count < minArea }
                .sorted { (pixelsOf[$0].count, $0) < (pixelsOf[$1].count, $1) }
            if small.isEmpty { break }
            var mergedAny = false
            for f in small where alive[f] && pixelsOf[f].count < minArea {
                var border: [Int32: Int] = [:]
                for p in pixelsOf[f] {
                    let x = p % side, y = p / side
                    for q in [x > 0 ? p - 1 : -1, x < side - 1 ? p + 1 : -1,
                              y > 0 ? p - side : -1, y < side - 1 ? p + side : -1] where q >= 0 {
                        let g = facetOf[q]
                        if g != Int32(f) { border[g, default: 0] += 1 }
                    }
                }
                guard let target = border.max(by: { a, b in
                    if a.value != b.value { return a.value < b.value }
                    let ca = centers[facetColor[Int(a.key)]], cb = centers[facetColor[Int(b.key)]]
                    let own = centers[facetColor[f]]
                    let da = own.distance(to: ca), db = own.distance(to: cb)
                    if da != db { return da > db }
                    return a.key > b.key
                })?.key else { continue }
                let t = Int(target)
                for p in pixelsOf[f] { facetOf[p] = target }
                pixelsOf[t].append(contentsOf: pixelsOf[f])
                pixelsOf[f] = []
                alive[f] = false
                mergedAny = true
            }
            if !mergedAny { break }
        }
    }

    /// For each facet, the pixel furthest from its edge (a chamfer distance transform), and how
    /// much room the number has there.
    static func placeLabels(_ map: [UInt16], side: Int, facets: Int) -> [PaintByNumberTemplate.Label] {
        let n = side * side
        let big = Double(side * 2)
        var dist = [Double](repeating: big, count: n)
        for p in 0..<n {
            let x = p % side, y = p / side, f = map[p]
            let edge = x == 0 || y == 0 || x == side - 1 || y == side - 1
                || map[p - 1] != f || map[p + 1] != f || map[p - side] != f || map[p + side] != f
            if edge { dist[p] = 0.5 }
        }
        let diagonal = 2.0.squareRoot()
        for y in 0..<side {
            for x in 0..<side {
                let p = y * side + x
                var d = dist[p]
                if x > 0 { d = min(d, dist[p - 1] + 1) }
                if y > 0 {
                    d = min(d, dist[p - side] + 1)
                    if x > 0 { d = min(d, dist[p - side - 1] + diagonal) }
                    if x < side - 1 { d = min(d, dist[p - side + 1] + diagonal) }
                }
                dist[p] = d
            }
        }
        for y in stride(from: side - 1, through: 0, by: -1) {
            for x in stride(from: side - 1, through: 0, by: -1) {
                let p = y * side + x
                var d = dist[p]
                if x < side - 1 { d = min(d, dist[p + 1] + 1) }
                if y < side - 1 {
                    d = min(d, dist[p + side] + 1)
                    if x < side - 1 { d = min(d, dist[p + side + 1] + diagonal) }
                    if x > 0 { d = min(d, dist[p + side - 1] + diagonal) }
                }
                dist[p] = d
            }
        }
        var best = [Int](repeating: -1, count: facets)
        for p in 0..<n {
            let f = Int(map[p])
            if best[f] < 0 || dist[p] > dist[best[f]] { best[f] = p }
        }
        return best.map { p in
            guard p >= 0 else { return PaintByNumberTemplate.Label(x: 0, y: 0, room: 0) }
            return PaintByNumberTemplate.Label(x: Double(p % side) + 0.5, y: Double(p / side) + 0.5, room: dist[p])
        }
    }
}

// MARK: - Rendering

/// The picture as the learner sees it, from a template: painted regions in their colour, the rest
/// white, with the outlines on a separate layer drawn once.
nonisolated enum PaintByNumberRenderer {
    /// Painted regions at map size, RGBA. Unpainted regions are white; `hint` regions (the ones
    /// "Zeig mir" points at) are a pale wash of their colour.
    static func fill(_ template: PaintByNumberTemplate, map: [UInt16], filled: Set<Int>, hint: Set<Int> = []) -> CGImage? {
        let side = template.side
        var rgba = [UInt8](repeating: 255, count: side * side * 4)
        let colors: [(UInt8, UInt8, UInt8)] = template.facetSwatch.map { index in
            let s = template.palette[index]
            return (UInt8(s.red * 255), UInt8(s.green * 255), UInt8(s.blue * 255))
        }
        for p in 0..<(side * side) {
            let f = Int(map[p])
            if filled.contains(f) {
                let c = colors[f]
                rgba[4 * p] = c.0; rgba[4 * p + 1] = c.1; rgba[4 * p + 2] = c.2
            } else if hint.contains(f) {
                let c = colors[f]
                rgba[4 * p] = UInt8((Int(c.0) + 3 * 255) / 4)
                rgba[4 * p + 1] = UInt8((Int(c.1) + 3 * 255) / 4)
                rgba[4 * p + 2] = UInt8((Int(c.2) + 3 * 255) / 4)
            }
        }
        return image(rgba, width: side, height: side)
    }

    /// The outlines at `scale`× the map, transparent elsewhere.
    static func outlines(_ template: PaintByNumberTemplate, map: [UInt16], scale: Int = 2,
                         gray: UInt8 = 120) -> CGImage? {
        let side = template.side, out = side * scale
        var rgba = [UInt8](repeating: 0, count: out * out * 4)
        for y in 0..<out {
            for x in 0..<out {
                let mx = x / scale, my = y / scale
                let f = map[my * side + mx]
                // A line on the last sub-pixel before a change to the right or below.
                let right = x % scale == scale - 1 && mx < side - 1 && map[my * side + mx + 1] != f
                let below = y % scale == scale - 1 && my < side - 1 && map[(my + 1) * side + mx] != f
                if right || below {
                    let p = (y * out + x) * 4
                    rgba[p] = gray; rgba[p + 1] = gray; rgba[p + 2] = gray; rgba[p + 3] = 255
                }
            }
        }
        return image(rgba, width: out, height: out, premultiplied: true)
    }

    static func image(_ rgba: [UInt8], width: Int, height: Int, premultiplied: Bool = false) -> CGImage? {
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: (premultiplied ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
