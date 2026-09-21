import Foundation

/// The key model and the two planes the keyboard shows.
///
/// QWERTY rather than QWERTZ on purpose: the person typing here is a native English speaker whose
/// muscle memory is QWERTY, and they draft in English at least as often as in German. German is
/// reached through long-press accents instead, which costs nothing when typing English and is
/// faster than switching to a German system keyboard when typing German.
enum Key: Equatable {
    case character(String)
    case shift
    case backspace
    case plane(Plane, label: String)
    case space
    case `return`
    case globe

    /// What the key types when tapped, if anything.
    var output: String? {
        if case .character(let s) = self { return s }
        if case .space = self { return " " }
        if case .return = self { return "\n" }
        return nil
    }

    /// Relative width. Letters are 1; the furniture around them is wider.
    var weight: Double {
        switch self {
        case .character: return 1
        case .shift, .backspace: return 1.5
        case .plane: return 1.4
        case .globe: return 1.2
        case .space: return 4
        case .return: return 2
        }
    }
}

enum Plane {
    case letters
    case numbers
    case symbols
}

enum KeyLayout {

    /// Long-press alternates. German needs four characters English doesn't have, and they are put
    /// exactly where a German speaker expects to find them. The accented vowels come along because
    /// the model sometimes returns loan words (Café, Attaché) that are wrong without them.
    static let alternates: [String: [String]] = [
        "a": ["ä", "à", "á", "â"],
        "o": ["ö", "ô", "ó", "ò"],
        "u": ["ü", "ù", "ú", "û"],
        "s": ["ß"],
        "e": ["é", "è", "ê", "ë"],
        "i": ["í", "ì", "î"],
        "n": ["ñ"],
        "c": ["ç"],
        "y": ["ÿ"],
        // German quotation marks, which no iOS keyboard offers without a detour.
        "\"": ["„", "“", "”", "«", "»"],
        "'": ["‚", "‘", "’"],
        "-": ["–", "—"],
        "/": ["\\"],
        "?": ["¿"],
        "!": ["¡"],
        "€": ["$", "£", "¥", "¢"],
    ]

    static func rows(for plane: Plane) -> [[Key]] {
        switch plane {
        case .letters: return letters
        case .numbers: return numbers
        case .symbols: return symbols
        }
    }

    private static let letters: [[Key]] = [
        row("qwertyuiop"),
        row("asdfghjkl"),
        [.shift] + row("zxcvbnm") + [.backspace],
        bottom(planeLabel: "123", plane: .numbers),
    ]

    private static let numbers: [[Key]] = [
        row("1234567890"),
        // € first: this keyboard is for writing German mail, so it is the currency that comes up.
        [.character("-"), .character("/"), .character(":"), .character(";"),
         .character("("), .character(")"), .character("€"), .character("&"),
         .character("@"), .character("\"")],
        [.plane(.symbols, label: "#+=")] + row(".,?!'") + [.backspace],
        bottom(planeLabel: "ABC", plane: .letters),
    ]

    private static let symbols: [[Key]] = [
        [.character("["), .character("]"), .character("{"), .character("}"),
         .character("#"), .character("%"), .character("^"), .character("*"),
         .character("+"), .character("=")],
        [.character("_"), .character("\\"), .character("|"), .character("~"),
         .character("<"), .character(">"), .character("$"), .character("£"),
         .character("¥"), .character("•")],
        [.plane(.numbers, label: "123")] + row(".,?!'") + [.backspace],
        bottom(planeLabel: "ABC", plane: .letters),
    ]

    private static func row(_ characters: String) -> [Key] {
        characters.map { .character(String($0)) }
    }

    private static func bottom(planeLabel: String, plane: Plane) -> [Key] {
        [.plane(plane, label: planeLabel), .globe, .space, .return]
    }
}
