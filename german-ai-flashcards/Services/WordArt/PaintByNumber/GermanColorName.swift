import Foundation

/// Colours in CIE Lab, and the German name nearest to one: the paint-by-number key teaches
/// "3 · dunkelrot", "5 · hellblau" while the learner paints.
nonisolated enum ColorLab {
    struct Lab: Equatable, Sendable {
        var l: Double, a: Double, b: Double

        func distance(to other: Lab) -> Double {
            let dl = l - other.l, da = a - other.a, db = b - other.b
            return (dl * dl + da * da + db * db).squareRoot()
        }
    }

    /// sRGB 0…1 → Lab (D65).
    static func lab(red: Double, green: Double, blue: Double) -> Lab {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
        let x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
        let y = (r * 0.2126 + g * 0.7152 + b * 0.0722)
        let z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return Lab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// Lab → sRGB 0…1, clamped.
    static func rgb(_ lab: Lab) -> (red: Double, green: Double, blue: Double) {
        let fy = (lab.l + 16) / 116, fx = fy + lab.a / 500, fz = fy - lab.b / 200
        func finv(_ t: Double) -> Double { let t3 = t * t * t; return t3 > 0.008856 ? t3 : (t - 16.0 / 116.0) / 7.787 }
        let x = finv(fx) * 0.95047, y = finv(fy), z = finv(fz) * 1.08883
        let r = x * 3.2406 + y * -1.5372 + z * -0.4986
        let g = x * -0.9689 + y * 1.8758 + z * 0.0415
        let b = x * 0.0557 + y * -0.2040 + z * 1.0570
        func gamma(_ c: Double) -> Double {
            let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
            return min(max(v, 0), 1)
        }
        return (gamma(r), gamma(g), gamma(b))
    }
}

nonisolated enum GermanColorName {
    struct Named: Sendable {
        let name: String
        let lab: ColorLab.Lab
    }

    /// About thirty everyday colour words a learner meets, with the shade each stands for.
    static let names: [Named] = [
        ("schwarz", 0.06, 0.06, 0.06), ("weiß", 1, 1, 1), ("grau", 0.50, 0.50, 0.50),
        ("hellgrau", 0.78, 0.78, 0.78), ("dunkelgrau", 0.28, 0.28, 0.30),
        ("rot", 0.86, 0.12, 0.12), ("dunkelrot", 0.55, 0.06, 0.09), ("weinrot", 0.45, 0.07, 0.22),
        ("rosa", 1.00, 0.75, 0.80), ("pink", 1.00, 0.30, 0.60), ("magenta", 0.85, 0.10, 0.65),
        ("orange", 1.00, 0.55, 0.05), ("apricot", 1.00, 0.76, 0.55), ("braun", 0.48, 0.28, 0.12),
        ("hellbraun", 0.72, 0.52, 0.32), ("beige", 0.93, 0.87, 0.72), ("ocker", 0.80, 0.60, 0.20),
        ("gelb", 1.00, 0.90, 0.10), ("hellgelb", 1.00, 0.97, 0.62), ("gold", 0.85, 0.68, 0.15),
        ("oliv", 0.50, 0.50, 0.12), ("grün", 0.15, 0.60, 0.20), ("hellgrün", 0.56, 0.86, 0.42),
        ("dunkelgrün", 0.05, 0.30, 0.12), ("mint", 0.66, 0.95, 0.80), ("türkis", 0.10, 0.75, 0.75),
        ("petrol", 0.05, 0.40, 0.45), ("blau", 0.10, 0.30, 0.85), ("hellblau", 0.56, 0.76, 1.00),
        ("dunkelblau", 0.05, 0.10, 0.40), ("lila", 0.55, 0.25, 0.75), ("violett", 0.38, 0.14, 0.58),
        ("flieder", 0.80, 0.70, 0.95),
    ].map { Named(name: $0.0, lab: ColorLab.lab(red: $0.1, green: $0.2, blue: $0.3)) }

    /// The nearest name to a colour.
    static func nearest(_ lab: ColorLab.Lab) -> String {
        names.min { $0.lab.distance(to: lab) < $1.lab.distance(to: lab) }?.name ?? "Farbe"
    }

    /// A name for every colour in a palette, all different: when two colours land on the same
    /// word, the lighter one becomes „hell…“ and the darker „dunkel…“ (unless the word already
    /// says so), and any still alike are numbered.
    static func uniqueNames(for palette: [ColorLab.Lab]) -> [String] {
        var names = palette.map(nearest)
        let groups = Dictionary(grouping: names.indices, by: { names[$0] })
        for (name, indices) in groups where indices.count > 1 {
            let sorted = indices.sorted { palette[$0].l > palette[$1].l }
            let plain = !name.hasPrefix("hell") && !name.hasPrefix("dunkel")
            for (rank, index) in sorted.enumerated() {
                if plain, sorted.count == 2 {
                    names[index] = (rank == 0 ? "hell" : "dunkel") + name
                } else if rank > 0 {
                    names[index] = "\(name) \(rank + 1)"
                }
            }
        }
        // A „hell…“ coined above can collide with a palette colour already called that.
        var seen: [String: Int] = [:]
        for index in names.indices {
            let name = names[index]
            seen[name, default: 0] += 1
            if let count = seen[name], count > 1 { names[index] = "\(name) \(count)" }
        }
        return names
    }
}
