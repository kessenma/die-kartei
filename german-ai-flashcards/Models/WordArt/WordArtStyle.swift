import Foundation

/// The looks a word's gallery pictures can be drawn in. Separate from `CardImageStyle` on purpose:
/// that one is the deck-wide flashcard setting (and what a Mac picture order carries), while these
/// are per-picture choices made in the Bildermappe, to draw from, trace or paint by number.
///
/// Prompt fragments describe a look, never an artist. English, because the image models were
/// trained on English captions.
nonisolated enum WordArtStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Few confident lines: the reference for Quick Draw's copy mode.
    case skizze
    /// Black ground, one flat accent colour, contour-line hatching.
    case kontur
    case anime
    case volkskunst
    case bauhaus
    case grimm
    case kaiserlich
    case illusion
    case theater
    /// Flat colour areas and bold shapes, made to be turned into paint-by-number regions.
    case malvorlage

    var id: String { rawValue }

    /// German identity word · English, like the app's headings.
    var label: String {
        switch self {
        case .skizze:     "Skizze · Sketch"
        case .kontur:     "Kontur · Contour"
        case .anime:      "Anime"
        case .volkskunst: "Volkskunst · Folklore"
        case .bauhaus:    "Bauhaus"
        case .grimm:      "Märchenstich · Fairy-tale engraving"
        case .kaiserlich: "Kaiserlich · Imperial grandeur"
        case .illusion:   "Illusion · Illusionistic"
        case .theater:    "Theater · Theatrical"
        case .malvorlage: "Malvorlage · Paint by number"
        }
    }

    var shortLabel: String {
        switch self {
        case .skizze:     "Skizze"
        case .kontur:     "Kontur"
        case .anime:      "Anime"
        case .volkskunst: "Volkskunst"
        case .bauhaus:    "Bauhaus"
        case .grimm:      "Märchenstich"
        case .kaiserlich: "Kaiserlich"
        case .illusion:   "Illusion"
        case .theater:    "Theater"
        case .malvorlage: "Malvorlage"
        }
    }

    var subtitle: String {
        switch self {
        case .skizze:     "A few clean lines, quick to copy"
        case .kontur:     "Black ground, one bold colour, contour hatching"
        case .anime:      "Clean cel shading, expressive and bright"
        case .volkskunst: "Painted folk motifs and paper-cut shapes"
        case .bauhaus:    "Circles, squares and primary colours"
        case .grimm:      "Old storybook engraving, fine cross-hatching"
        case .kaiserlich: "Gilded, baroque and grand"
        case .illusion:   "Trompe-l'œil depth that fools the eye"
        case .theater:    "A lit stage with painted scenery"
        case .malvorlage: "Flat colour areas, made to paint by number"
        }
    }

    var symbol: String {
        switch self {
        case .skizze:     "scribble"
        case .kontur:     "circle.lefthalf.striped.horizontal"
        case .anime:      "sparkles"
        case .volkskunst: "leaf"
        case .bauhaus:    "circle.square"
        case .grimm:      "book.closed"
        case .kaiserlich: "crown"
        case .illusion:   "cube.transparent"
        case .theater:    "theatermasks"
        case .malvorlage: "paintpalette"
        }
    }

    var promptFragment: String {
        switch self {
        case .skizze:
            "a quick reference sketch made of a few confident black contour lines on plain white paper, simplified shapes that are easy to copy in under a minute, no shading, no color, no background"
        case .kontur:
            "bold graphic illustration on a solid black background, the subject as one flat acid-yellow or crimson silhouette filled with fine parallel contour-line hatching that follows its form, classical sculpture feel, strictly limited palette of black, yellow and crimson, high contrast"
        case .anime:
            "anime illustration, clean line art, cel shading, expressive and bright, simple soft background"
        case .volkskunst:
            "European folk art illustration, painted folk motifs, paper-cut silhouettes, symmetrical flowers and leaves, warm red, green and ochre on cream"
        case .bauhaus:
            "Bauhaus style poster illustration, built from circles, squares and triangles, primary red, yellow and blue with black and off-white, flat geometric composition"
        case .grimm:
            "nineteenth-century fairy-tale book engraving, fine black cross-hatching on aged cream paper, slightly eerie storybook mood, monochrome"
        case .kaiserlich:
            "imperial grandeur, baroque oil painting, gilded ornament, rich crimson and gold, dramatic lighting, regal and monumental"
        case .illusion:
            "illusionistic trompe-l'oeil painting, the subject appears to step out of a painted frame, deep convincing perspective, realistic painted shadows"
        case .theater:
            "a theatrical stage scene, the subject lit by a single spotlight, painted canvas backdrop, velvet curtains at the edges, dramatic shadows"
        case .malvorlage:
            "simple flat vector illustration for a paint-by-number picture, large clear color areas with crisp edges, about twelve distinct flat colors, bold simple shapes, plain light background"
        }
    }

    var negativeFragment: String {
        switch self {
        case .skizze:     "color, shading, gradient, texture, background, photograph, fine detail"
        case .kontur:     "photograph, gradient, many colors, pastel, white background"
        case .anime:      "photograph, realistic, 3d render, gritty"
        case .volkskunst: "photograph, 3d render, neon, realistic"
        case .bauhaus:    "photograph, realistic, ornament, gradient, texture"
        case .grimm:      "color, photograph, 3d render, glossy"
        case .kaiserlich: "flat vector, cartoon, minimal, photograph"
        case .illusion:   "flat vector, cartoon, abstract"
        case .theater:    "photograph, flat vector, bright daylight"
        case .malvorlage: "gradient, texture, noise, shading, photograph, fine detail, thin lines, outlines of text"
        }
    }

    /// Styles offered first in pickers: the ones the drawing modes rely on.
    static let drawingStyles: [WordArtStyle] = [.skizze, .kontur, .malvorlage]
}
