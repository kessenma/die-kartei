import Foundation

/// The look the learner wants for flashcard pictures, and how busy those pictures may get.
///
/// Stored in `UserDefaults` for the same reason as `ImageGenQuality`: both the SwiftUI pickers
/// (via `@AppStorage`) and `DeckIllustrationService` (via `current`, in a service with no manager
/// reference) need it, and there is nothing worth threading through. Read fresh per picture, so a
/// change mid-run applies from the next card onward.
///
/// Deliberately card-only. Story illustrations take their look from the story's `StoryGenre`, and
/// the two shouldn't fight over one setting.
nonisolated enum CardImageStyle: String, CaseIterable, Identifiable {
    case stickFigure
    case lineArt
    case flatIcon
    case cartoon
    case storybook
    case watercolor
    case chalkboard
    case photo

    static let defaultsKey = "cardImageStyle"

    /// The learner's current choice. `.flatIcon` is the default because it's the look every
    /// picture drawn before this setting existed already has.
    static var current: CardImageStyle {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(CardImageStyle.init(rawValue:)) ?? .flatIcon
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stickFigure: "Stick Figure"
        case .lineArt:     "Line Art"
        case .flatIcon:    "Flat Icon"
        case .cartoon:     "Cartoon"
        case .storybook:   "Storybook"
        case .watercolor:  "Watercolor"
        case .chalkboard:  "Chalkboard"
        case .photo:       "Photo"
        }
    }

    var subtitle: String {
        switch self {
        case .stickFigure: "Crude black marker doodle"
        case .lineArt:     "Clean black outlines, no color"
        case .flatIcon:    "Simple flat shapes, bright colors"
        case .cartoon:     "Bold outlines, cheerful colors"
        case .storybook:   "Soft hand-drawn children's book"
        case .watercolor:  "Loose brush washes on paper"
        case .chalkboard:  "White chalk on a green board"
        case .photo:       "A realistic photograph"
        }
    }

    /// Style words appended to the subject. English on purpose: both image models were trained
    /// on English captions.
    var promptFragment: String {
        switch self {
        case .stickFigure:
            "black and white stick figure doodle, crude simple line drawing, thick black marker strokes on plain white paper, no shading"
        case .lineArt:
            "clean black ink line art, bold even outlines, coloring book style, flat white background, no shading"
        case .flatIcon:
            "simple flat vector illustration, bold solid shapes, soft bright colors, clean minimal background"
        case .cartoon:
            "friendly cartoon illustration, bold clean outlines, bright cheerful colors, comic style"
        case .storybook:
            "soft children's storybook illustration, gentle warm colors, hand drawn, cozy"
        case .watercolor:
            "loose watercolor painting on white paper, soft washes of color, visible brush strokes"
        case .chalkboard:
            "white chalk drawing on a dark green chalkboard, simple chalky strokes"
        case .photo:
            "realistic photograph, natural lighting, sharp focus, plain background"
        }
    }

    /// What this style must not look like. Appended to the shared negative prompt — the only
    /// steering available, since the palettized repos ship no safety checker to lean on.
    var negativeFragment: String {
        switch self {
        case .stickFigure:
            "color, shading, gradient, texture, realistic, 3d render, photograph, fine detail"
        case .lineArt:
            "color, shading, gradient, photograph, 3d render, texture"
        case .flatIcon:
            "photograph, realistic, 3d render, gradient mesh, noise, texture"
        case .cartoon:
            "photograph, realistic, gritty, dark, muted"
        case .storybook:
            "photograph, realistic, harsh contrast, 3d render, neon"
        case .watercolor:
            "photograph, 3d render, hard vector edges, flat digital"
        case .chalkboard:
            "photograph, realistic, glossy, colorful paint"
        case .photo:
            "illustration, drawing, cartoon, painting, sketch, 3d render, clip art"
        }
    }
}

/// How much the picture is allowed to put in the frame. Separate from `CardImageStyle` because
/// clutter is the failure mode regardless of look: asked for "membership card" in any style, a
/// small diffusion model happily draws a desk covered in office props.
nonisolated enum CardImageDetail: String, CaseIterable, Identifiable {
    /// One object, empty background, nothing else.
    case justTheWord
    /// The object with a little context around it.
    case littleScene

    static let defaultsKey = "cardImageDetail"

    static var current: CardImageDetail {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(CardImageDetail.init(rawValue:)) ?? .justTheWord
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .justTheWord: "Just the word"
        case .littleScene: "A little scene"
        }
    }

    var caption: String {
        switch self {
        case .justTheWord:
            "One thing, plain background, nothing else in the frame. The most reliable memory hook."
        case .littleScene:
            "The word with a bit of context around it. More interesting, more chance of clutter."
        }
    }

    var promptFragment: String {
        switch self {
        case .justTheWord:
            "one single subject, isolated on a plain empty background, centered, nothing else in the frame"
        case .littleScene:
            "one clear main subject, simple uncluttered background, a hint of context"
        }
    }

    var negativeFragment: String {
        switch self {
        case .justTheWord:
            "collage, montage, grid of objects, many objects, multiple panels, split image, cluttered, busy background, scenery, extra props, border, frame"
        case .littleScene:
            "collage, montage, grid of objects, multiple panels, split image, cluttered"
        }
    }
}
