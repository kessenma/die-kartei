//
//  TutorSceneLab.swift
//  german-ai-flashcards
//
//  Candidate pictures for the onboarding download pitch, judged side by side on a real device.
//
//  The onboarding wizard is forbidden from saying model, LLM or inference — its own header says
//  so, and the reason is a first-time user who saw "Download … (~5.0 GB)" and had no idea why an
//  app would need that. That constraint rules out the entire default iconography: no chips, no
//  brains, no gears, no cloud with an arrow through it. What is left has to picture something
//  *arriving*.
//
//  Four candidates; `fuellen` is the one that survived review. The other three are kept only as
//  the comparison that made the case, and go the moment it is settled.
//
//  Authored in `tools/blender/tutor_render.py`; regenerate with `--all`. Nothing here ships.
//  This is a tuning surface in the same spirit as `PrepositionSceneGalleryView` and
//  `FigurGalleryView`, and it lives beside them at the bottom of the preposition hub because
//  that is where motion gets judged on hardware rather than in the simulator.
//
//  The copy under each canvas is lifted verbatim from `OnboardingWizardView`, not paraphrased.
//  A picture that looks good under invented placeholder text is not evidence of anything — and
//  the download button below is a real one for the same reason: the sequence is supposed to be
//  something the learner sets off, so the test has to include the press.
//

import RealityKit
import SwiftUI

// MARK: - One clock

/// The run's shape, in one place, because three views read it: the canvas drives geometry from
/// it, the backdrop draws to it, and the lab starts it.
enum TutorRun {
    /// How long the whole pass takes when nothing is scrubbing it. A judging cadence, not a
    /// product one — a real download sets its own, and that is the whole argument for this
    /// candidate.
    static let seconds: TimeInterval = 4.5

    /// The beat before the figure: a download icon appears, a hand reaches in and taps it, the
    /// tap lands. Only then does anything start drawing.
    ///
    /// It is a *depiction* of the press, not the press itself — the wizard's own Download button
    /// is what a learner actually taps, and the scene has no business intercepting it. What this
    /// buys is the causal link: the figure does not simply appear, it appears *because the
    /// download was started*. Without it the sequence is a nice animation with no reason to run.
    static let prologue: TimeInterval = 2.0

    /// The share of progress the outline gets before the fill starts. Must match `DRAW_SHARE` in
    /// `tools/blender/tutor_render.py`, which orders the strokes on the same assumption.
    ///
    /// The two phases used to overlap, with the outline running a fixed multiple ahead of the
    /// fill. That read as a single event with a fringe on it. Separated, it reads as two: a
    /// sketch, and then the thing itself arriving inside it.
    static let drawShare = 0.35

    static func progress(from start: Date?, at beat: Date) -> Double {
        guard let start else { return 0 }
        return min(1, max(0, beat.timeIntervalSince(start) / seconds))
    }

    static func draw(_ progress: Double) -> Double { min(1, progress / drawShare) }

    static func pour(_ progress: Double) -> Double {
        paced(max(0, (progress - drawShare) / (1 - drawShare)))
    }

    /// The fill is not linear in time: it covers 86 % of the figure in the first three quarters
    /// of the pour and spends the last quarter on the head alone.
    ///
    /// This is the only place the scene says anything about what is being downloaded, and it says
    /// it with pacing rather than with a symbol. A brain or a set of gears would put machine-
    /// learning vocabulary back on the one screen built to avoid it; a head that visibly takes
    /// its time to arrive says "the part that thinks" and stays inside the picture.
    private static func paced(_ fraction: Double) -> Double {
        let knee = 0.75, height = 0.86
        return fraction < knee
            ? fraction * (height / knee)
            : height + (fraction - knee) * ((1 - height) / (1 - knee))
    }
}

// MARK: - The scene

/// Two readings of "make the background tiles download icons", kept side by side because the
/// brief allows both and only a screen can choose: keep the poster's solid square and put the
/// glyph on it, or let the glyph *be* the tile and give it the same hard offset shadow.
enum TutorTileStyle: String, CaseIterable, Identifiable {
    case quadrat, symbol
    var id: String { rawValue }
    var label: String { self == .quadrat ? "Quadrat" : "Symbol" }
}

/// The one surviving candidate's fixed facts. Three others — a teacher assembling from parts, a
/// cast on a tray, a block landing on a plinth — were built alongside it and cut; the comparison
/// did its job and the picker that carried it is gone. `tools/blender/tutor_render.py` can still
/// build all four if the argument ever reopens.
enum TutorScene {
    static let asset = "tutor-fuellen"
    /// Prim-name prefixes that wear the tutor's accent rather than the cast's ink: the fill slabs
    /// and the six-part figure are the thing being downloaded. `strich_*` — the outline — keeps
    /// the ink, which is what makes the sketch read as a sketch.
    static let branded = ["fuell", "figur"]
    static let target = SIMD3<Float>(0, 0.90, 0)
    static let distance: Float = 5.4
}

// MARK: - Lab

/// The wizard's welcome step, rebuilt around the scene.
///
/// Copy, order and furniture are lifted from `OnboardingWizardView.welcomePage` rather than
/// approximated: the same headline, the same three paragraphs, the same three capability rows
/// with the same symbols and tints. A picture that looks good under invented placeholder text is
/// not evidence of anything, and neither is one judged against copy that is nearly right.
///
/// The one deliberate departure is the action bar. The real welcome step says "Weiter" and the
/// Download button lives one step later, on the pitch; here it is Download, because the scene is
/// a picture of a download starting and the press is half of what is being judged.
struct TutorSceneLabView: View {
    /// Only used to push the real Model screen. Optional so the preview can stand alone; without
    /// them the Download button still renders, disabled, rather than lying about where it goes.
    var modelManager: MLXModelManager?
    var mlxService: MLXGenerationService?

    /// When the press was depicted, and when the figure's own run begins — the second is simply
    /// the first plus the prologue, so there is still one press and one clock behind everything.
    @State private var prologueStart: Date?
    @State private var runStart: Date?
    @State private var runToken = 0
    /// When the figure finished waking up. The poster does not begin until then — it is the
    /// closing beat, not scenery the figure is drawn on top of.
    @State private var tilesStart: Date?

    @State private var scrubs = false
    @State private var progress = 0.35
    @State private var distance: Float = TutorScene.distance
    /// How loudly the poster reads behind a charcoal figure. The one thing a render cannot
    /// settle: the tiles' own ink and the figure are close in value, so the balance is a
    /// judgement made on a real screen.
    @State private var backdrop = 0.55
    @State private var tileStyle: TutorTileStyle = .symbol
    @State private var showsControls = false
    /// The "maybe later" accordion. Collapsed by default: it is the answer to a question most
    /// people will not ask, and open it would read as the screen arguing with its own offer.
    @State private var showsLater = false
    @State private var starter: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss

    /// The tutor this phone would actually be pitched — never the raw hero, same rule the wizard
    /// follows. Its accent is what the arriving figure wears, so the test includes the question
    /// "does this read as branded?"
    private var tutor: MLXModel { ModelReadiness.current.fittingTutor ?? .hero }

    var body: some View {
        NavigationStack { page }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                stage
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)

                explainer
                capabilities
                later
                controls
            }
            .padding()
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        // Full-bleed, behind everything including the bars. The poster was boxed inside the
        // scene's own frame before, which made it look like a picture hanging on the screen
        // rather than the room the screen is in.
        .background { backdropLayer.ignoresSafeArea() }
        .scrollContentBackground(.hidden)
        .navigationTitle("Willkommen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear(perform: armAndPlay)
        .onDisappear { starter?.cancel() }
    }

    // MARK: Scene

    private var backdropLayer: some View {
        TutorBackdrop(runStart: runStart, tilesStart: tilesStart,
                      ink: FigurScene.defaultTint, strength: backdrop, style: tileStyle)
    }

    private var stage: some View {
        ZStack {
            TutorSceneCanvas(
                asset: TutorScene.asset,
                ink: FigurScene.defaultTint,
                accent: tutor.theme.accent,
                branded: TutorScene.branded,
                scrub: scrubs ? progress : nil,
                runStart: runStart,
                runToken: runToken,
                target: TutorScene.target,
                distance: distance,
                onFinish: { tilesStart = .now }
            )
            TutorPrologue(start: prologueStart, accent: tutor.theme.accent,
                          ink: FigurScene.defaultTint)
        }
    }

    /// Blank, then plays itself.
    ///
    /// An earlier version stayed armed until the Download button was pressed, on the theory that
    /// the scene should be something a learner sets off. That was the wrong read twice over: the
    /// prologue already *depicts* the press, so the sequence is a demonstration of what tapping
    /// Download does — and a demonstration that waits to be asked shows a learner an empty
    /// rectangle and no reason to press anything. The button now goes to the Model screen instead,
    /// which leaves the redo icon as the only way to see the sequence again.
    ///
    /// The short delay is the same problem `FigurSceneView.settleDelay` exists for: a cover slides
    /// for about a third of a second, and a sequence that opens underneath that slide spends its
    /// first beat behind a moving pane.
    private func armAndPlay() {
        prologueStart = nil
        runStart = nil
        tilesStart = nil
        runToken += 1
        starter?.cancel()
        starter = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            run()
        }
    }

    private func run() {
        starter?.cancel()
        tilesStart = nil
        prologueStart = .now
        runStart = Date.now.addingTimeInterval(TutorRun.prologue)
        runToken += 1
    }

    // MARK: Copy — verbatim from OnboardingWizardView.welcomePage

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your German teacher lives on this iPhone")
                .font(.title2)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)

            Text("Most apps send what you write off to a company's servers. This one doesn't. "
                 + "Everything happens on your phone, so nothing you type ever leaves it, it "
                 + "works with no signal, and there is nothing to pay.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("The trade: that teacher is a file you download once, and it's a big one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 14) {
            capabilityRow(
                symbol: "checkmark.circle.fill",
                tint: .green,
                title: "Works right now",
                detail: "der · die · das, prepositions, matching, and the check on the next "
                      + "screen. No download, no signal needed."
            )
            capabilityRow(
                symbol: "arrow.down.circle.fill",
                tint: tutor.theme.accent,
                title: "With the teacher (~\(tutor.approximateSizeLabel), once)",
                detail: "Stories written for your level, conversation practice, and grammar "
                      + "coaching that explains what you got wrong."
            )
            capabilityRow(
                symbol: "photo.circle.fill",
                tint: .secondary,
                title: "Optional, later",
                detail: "Pictures drawn for your cards and stories. A separate, smaller download "
                      + "you can add any time."
            )
        }
        .glassCard()
    }

    private func capabilityRow(symbol: String, tint: Color, title: String,
                               detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Action bar

    /// The suggestion and the way to act on it, in that order.
    ///
    /// The brand mark sits down here rather than above the copy, and that is a rule being kept.
    /// `OnboardingWizardView.welcomePage` is explicit that the explainer carries "no logo, no
    /// brand name, no gigabyte figure above the fold": someone who does not yet know why an app
    /// wants five gigabytes is not helped by a vendor's logo. At the moment of the ask it earns
    /// its place, because it says *which* teacher and why this one.
    private var actionBar: some View {
        VStack(spacing: 10) {
            suggestion
            HStack(spacing: 10) {
                downloadButton
                // Icon only, and deliberately: the sequence plays once on arrival, since a
                // download that loops forever is a download that failed.
                Button { run() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.body)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Nochmal abspielen")
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }

    /// Names the tutor this phone should get before offering the screen where tutors are chosen.
    /// Leading with the recommendation is the whole job here: a list of four is a decision, and a
    /// decision is what a first-time user has no basis to make.
    private var suggestion: some View {
        HStack(spacing: 10) {
            tutor.logoImage
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Suggested for this iPhone")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("\(tutor.rawValue) \u{00B7} ~\(tutor.approximateSizeLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        if let modelManager, let mlxService {
            NavigationLink {
                TutorModelChoiceScreen(modelManager: modelManager, mlxService: mlxService,
                                       onDone: { dismiss() })
            } label: {
                downloadLabel
            }
            .buttonStyle(.borderedProminent)
            .tint(tutor.theme.accent)
        } else {
            Button {} label: { downloadLabel }
                .buttonStyle(.borderedProminent)
                .tint(tutor.theme.accent)
                .disabled(true)
        }
    }

    private var downloadLabel: some View {
        Label("Download \(tutor.rawValue)", systemImage: "square.and.arrow.down.fill")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
    }

    // MARK: The out

    /// Declining, as a first-class answer rather than a trapdoor.
    ///
    /// A screen whose only control commits to a five-gigabyte download is a wall, and walls get
    /// force-quit. This is the same promise `OnboardingWizardView.declinedNote` makes — the app
    /// works without a teacher, and tutors live in one findable place — but folded shut, because
    /// someone who is happy to download should not have to read a paragraph about not doing so.
    private var later: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { showsLater.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsLater ? 90 : 0))
                    Text("Download a model later")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsLater {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Explore the app first. der \u{00B7} die \u{00B7} das, prepositions and "
                         + "matching all work with no download and no signal. Stories and "
                         + "conversation practice are what need a teacher.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Points somewhere real rather than printing a path — the rule
                    // `ModelUpgradeNudge` states and the reason `SettingsRouter` exists.
                    if let modelManager, let mlxService {
                        NavigationLink {
                            TutorModelChoiceScreen(modelManager: modelManager,
                                                   mlxService: mlxService,
                                                   onDone: { dismiss() })
                        } label: {
                            HStack(spacing: 8) {
                                Text("Settings \u{25B8} Model & Downloads")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Not now \u{2014} take me to the app")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: Tuning (not part of the mock)

    @ViewBuilder
    private var controls: some View {
        DisclosureGroup("Tuning", isExpanded: $showsControls) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Vom Download-Fortschritt getrieben", isOn: $scrubs)
                    .font(.subheadline)
                if scrubs {
                    Slider(value: $progress)
                    Text("\(Int(progress * 100)) % geladen")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $distance, in: 3.0...16.0)
                Text("Kameraabstand \(distance, specifier: "%.1f")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Slider(value: $backdrop)
                Text("Plakat \(Int(backdrop * 100)) %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Picker("Kachel", selection: $tileStyle) {
                    ForEach(TutorTileStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
        .glassCard()
    }
}

/// The panel treatment every block of copy on this screen wears: Liquid Glass over the poster
/// rather than an opaque card on top of it.
///
/// `.regularMaterial` would also have been legible, and that is exactly the problem — it frosts
/// the tiles into a flat grey and the background stops being a background. Glass keeps the
/// colour and the shapes readable underneath while the text stays crisp on top, which is the
/// whole reason for putting a poster back there.
private extension View {
    func glassCard() -> some View {
        padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

// MARK: - Prologue

/// The beat that gives the rest a reason: a download icon, a hand that reaches in and taps it,
/// and the tap landing. Then it clears the stage and the figure starts drawing.
///
/// SF Symbols on a plain SwiftUI stack rather than anything in the USDZ. A hand and a download
/// glyph are interface vocabulary, not Bauhaus forms — modelling them in charcoal primitives
/// would make them worse, not more consistent, and they are gone before the figure arrives.
struct TutorPrologue: View {
    /// nil means nothing has been pressed. Everything below is measured from here.
    var start: Date?
    var accent: Color
    var ink: Color

    // Seconds from the press. The hand's travel deliberately overlaps the icon settling, so the
    // two read as one gesture rather than as a slideshow.
    private static let iconIn = (0.05, 0.35)
    private static let handIn = (0.45, 0.90)
    private static let press = (0.95, 1.06)
    private static let rays = 1.06
    private static let fadeOut = (1.45, 1.88)

    @State private var animating = false
    @State private var stopper: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(paused: !animating)) { context in
            let elapsed = start.map { context.date.timeIntervalSince($0) } ?? -1
            content(at: elapsed)
        }
        .allowsHitTesting(false)
        .onChange(of: start) { arm() }
        .onDisappear { stopper?.cancel(); animating = false }
    }

    private func arm() {
        stopper?.cancel()
        guard start != nil else { animating = false; return }
        animating = true
        stopper = Task { @MainActor in
            try? await Task.sleep(for: .seconds(TutorRun.prologue))
            guard !Task.isCancelled else { return }
            animating = false
        }
    }

    @ViewBuilder
    private func content(at elapsed: TimeInterval) -> some View {
        let appeared = ramp(elapsed, Self.iconIn.0, Self.iconIn.1)
        let leaving = ramp(elapsed, Self.fadeOut.0, Self.fadeOut.1)
        let pressed = ramp(elapsed, Self.press.0, Self.press.1)
        let alpha = appeared * (1 - leaving)
        // Squashes under the tap and springs back as the rays take over, which is the only thing
        // that makes the hand look like it made contact rather than passed by. Spelled out as a
        // local rather than inline: the type checker gives up on it inside a modifier chain.
        let squash: Double = pressed * (1 - rayAlpha(elapsed))
        let scale: Double = 0.86 + 0.14 * appeared - 0.10 * squash

        if alpha > 0.001 {
            ZStack {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(accent)
                    .scaleEffect(scale)
                    .opacity(alpha)

                hand(at: elapsed)
                    .opacity(alpha)
            }
        }
    }

    @ViewBuilder
    private func hand(at elapsed: TimeInterval) -> some View {
        let arrived = ramp(elapsed, Self.handIn.0, Self.handIn.1)
        let rays = rayAlpha(elapsed)
        // Rests just off the icon's lower-right corner, where `hand.point.up.left`'s fingertip
        // lands on it. Travels in from further out along the same diagonal.
        let restX: Double = 34, restY: Double = 44
        let travel: Double = 1 - arrived
        let offsetX: Double = restX + travel * 46
        let offsetY: Double = restY + travel * 52
        let raysScale: Double = 0.88 + 0.12 * rays
        let pointAlpha: Double = arrived * (1 - rays)

        ZStack {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(ink)
                .opacity(pointAlpha)
            // Same spot, swapped on contact: the pointing hand becomes the tap it just made.
            Image(systemName: "hand.rays")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(ink)
                .opacity(rays)
                .scaleEffect(raysScale)
        }
        .offset(x: offsetX, y: offsetY)
    }

    private func rayAlpha(_ elapsed: TimeInterval) -> Double {
        ramp(elapsed, Self.rays, Self.rays + 0.14)
    }

    private func ramp(_ value: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return value >= to ? 1 : 0 }
        let t = min(1, max(0, (value - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Backdrop

/// The drafting table the figure is drawn on, and the Bauhaus poster that tiles in behind it
/// once the figure is awake.
///
/// Two beats, and the order is the whole design. While the figure is being drawn and filled the
/// backdrop is nothing but faint graph paper, because anything louder would compete with a
/// single charcoal line being traced. Only when the figure has stretched, jumped and waved do
/// the tiles arrive — one at a time, on the diagonal, so the poster *builds* rather than
/// flashing into place. The download finishes and its world assembles around it.
///
/// Flat SwiftUI rather than geometry in the USDZ, for three reasons: Bauhaus is a flat idiom and
/// a poster shape put in perspective stops being one; it costs no prims on a scene that already
/// carries three hundred; and it can read the palette directly instead of being re-tinted.
///
/// It is also the closest this picture comes to saying "knowledge" — a structure assembling
/// itself, rather than a brain or a set of gears, which would put machine-learning vocabulary
/// back on the one screen written to avoid it.
struct TutorBackdrop: View {
    /// The figure's run. Drives the graph paper only.
    var runStart: Date?
    /// When the poster starts tiling in. nil until the wake-up clip has finished.
    var tilesStart: Date?
    var ink: Color
    /// 0…1. The tiles' ink and the figure are close in value, so how loud the poster can be
    /// without swallowing its subject is a judgement for a real screen.
    var strength: Double
    var style: TutorTileStyle

    /// The app's Bauhaus palette, which is not a coincidence: `GenderPalette` is already blue,
    /// red and gold, and the Grundform theme's accent *is* der-blue. Borrowing it here means the
    /// poster matches the theme instead of introducing a fourth colour system.
    ///
    /// Worth knowing rather than worth worrying about: these are the der/die/das colours. No
    /// gendered word appears on this screen, and the tiles carry no text, so there is nothing to
    /// mis-read — but if this backdrop is ever reused somewhere vocabulary is shown, that stops
    /// being true.
    private static let tileColors: [(id: String, gender: Gender)] =
        [("der", .der), ("plural", .plural), ("die", .die)]

    /// Seconds between one tile landing and the next, and how long each takes to settle.
    private static let stagger = 0.085
    private static let settle = 0.32

    /// True only while something here is actually moving. Both of this view's beats are short
    /// and separated by a long stretch where the figure is the only thing changing, so running
    /// the display link throughout would spend most of its life redrawing an unchanged picture.
    @State private var animating = false
    @State private var stopper: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(paused: !animating)) { context in
            Canvas { ctx, size in
                draw(in: &ctx, size: size, at: context.date)
            } symbols: {
                // Resolved once per frame rather than per tile: sixteen tiles asking for the
                // same glyph is sixteen rasterisations of one picture.
                glyph(ink).tag("ink")
                ForEach(Self.tileColors, id: \.id) { entry in
                    glyph(GenderPalette.color(entry.gender)).tag(entry.id)
                }
            }
        }
        .allowsHitTesting(false)
        // The paper fades in over the first tenth of the run; the tiles cascade for about a
        // second. Nothing else here moves, so those are the only two windows worth a clock.
        .onChange(of: runStart) {
            animate(for: max(0, runStart?.timeIntervalSinceNow ?? 0) + TutorRun.seconds * 0.25)
        }
        .onChange(of: tilesStart) { animate(for: 2.0) }
        .onDisappear { stopper?.cancel(); animating = false }
    }

    private func animate(for seconds: TimeInterval) {
        stopper?.cancel()
        animating = true
        stopper = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            animating = false
        }
    }

    private func glyph(_ color: Color) -> some View {
        Image(systemName: "square.and.arrow.down.fill")
            .font(.system(size: 160, weight: .medium))
            .foregroundStyle(color)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, at beat: Date) {
        let tiled = tilesStart.map { beat.timeIntervalSince($0) } ?? -1
        paper(in: &ctx, size: size, at: beat, fading: tiled)
        guard tiled >= 0 else { return }
        poster(in: &ctx, size: size, elapsed: tiled)
    }

    /// Graph paper: in fast at the start, out again as the poster takes over. The pen needs
    /// something to draw on; the finished poster does not.
    private func paper(in ctx: inout GraphicsContext, size: CGSize, at beat: Date,
                       fading tiled: TimeInterval) {
        let shown = ramp(TutorRun.progress(from: runStart, at: beat), from: 0, to: 0.10)
        let gone = tiled < 0 ? 0 : ramp(tiled, from: 0, to: 0.6)
        let alpha = 0.10 * shown * (1 - gone)
        guard alpha > 0.001 else { return }

        var grid = Path()
        let step = 30.0
        for x in stride(from: 0, through: size.width, by: step) {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for y in stride(from: 0, through: size.height, by: step) {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        ctx.stroke(grid, with: .color(ink.opacity(alpha)), lineWidth: 0.75)
    }

    /// A field of extruded squares. Each tile is a flat coloured square with a solid shadow
    /// pulled down-left — the 1923 exhibition poster's trick, and the reason a grid of squares
    /// reads as depth without a single gradient.
    private func poster(in ctx: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let cell = min(size.width, size.height) / 3.4
        let cols = Int(ceil(size.width / cell))
        let rows = Int(ceil(size.height / cell))

        for row in 0..<rows {
            for col in 0..<cols {
                // Diagonal order, which is what makes a cascade out of what would otherwise be
                // a typewriter sweep — and it follows the direction the shadows already point.
                let step = Double(row + col)
                let landed = ramp(elapsed, from: step * Self.stagger,
                                  to: step * Self.stagger + Self.settle)
                guard landed > 0.001 else { continue }
                tile(in: &ctx, at: CGPoint(x: Double(col) * cell, y: Double(row) * cell),
                     cell: cell,
                     entry: Self.tileColors[(row + col) % Self.tileColors.count],
                     landed: landed)
            }
        }
    }

    private func tile(in ctx: inout GraphicsContext, at origin: CGPoint, cell: Double,
                      entry: (id: String, gender: Gender), landed: Double) {
        // Tuned against the 1923 poster: the squares are large in their cell and the shadows
        // long, so adjacent tiles almost touch and the extrusions chain into diagonal bands. A
        // first pass at half these values read as polka dots — the rhythm comes from the density.
        let pad = cell * 0.06
        let side = cell * 0.56
        let depth = cell * 0.38

        // Grows from where it lands rather than sliding in: a tile that travels reads as a
        // thing being placed, and sixteen of them travelling at once reads as confetti.
        let grow = 0.72 + 0.28 * landed
        let alpha = landed * strength

        let x = origin.x + cell - pad - side
        let y = origin.y + pad
        let mid = CGPoint(x: x + side / 2, y: y + side / 2)

        func scaled(_ point: CGPoint) -> CGPoint {
            CGPoint(x: mid.x + (point.x - mid.x) * grow, y: mid.y + (point.y - mid.y) * grow)
        }

        let face = CGRect(origin: scaled(CGPoint(x: x, y: y)),
                          size: CGSize(width: side * grow, height: side * grow))

        switch style {
        case .quadrat:
            // The silhouette of the square and its offset copy: a hexagon, which is the
            // extrusion. No gradient anywhere — that is the whole trick of the poster.
            var solid = Path()
            solid.move(to: scaled(CGPoint(x: x + side, y: y)))
            solid.addLine(to: scaled(CGPoint(x: x, y: y)))
            solid.addLine(to: scaled(CGPoint(x: x - depth, y: y + depth)))
            solid.addLine(to: scaled(CGPoint(x: x - depth, y: y + side + depth)))
            solid.addLine(to: scaled(CGPoint(x: x + side - depth, y: y + side + depth)))
            solid.addLine(to: scaled(CGPoint(x: x + side, y: y + side)))
            solid.closeSubpath()
            ctx.fill(solid, with: .color(ink.opacity(0.92 * alpha)))
            ctx.fill(Path(face), with: .color(GenderPalette.color(entry.gender)
                .opacity(0.95 * alpha)))
            symbol(in: &ctx, id: "ink", box: face.insetBy(dx: face.width * 0.20,
                                                          dy: face.height * 0.20),
                   opacity: 0.85 * alpha)

        case .symbol:
            // The glyph is the tile. Its shadow is the same glyph offset along the same
            // diagonal the squares extrude down — a hard offset, never a blur, or it stops
            // being a Bauhaus shadow and becomes a drop shadow.
            let shadow = face.offsetBy(dx: -depth * grow * 0.55, dy: depth * grow * 0.55)
            symbol(in: &ctx, id: "ink", box: shadow, opacity: 0.92 * alpha)
            symbol(in: &ctx, id: entry.id, box: face, opacity: 0.95 * alpha)
        }
    }

    /// Draw a resolved glyph to fit `box` without stretching it, at its own opacity.
    private func symbol(in ctx: inout GraphicsContext, id: String, box: CGRect, opacity: Double) {
        guard opacity > 0.001, let resolved = ctx.resolveSymbol(id: id) else { return }
        let natural = resolved.size
        guard natural.width > 0, natural.height > 0 else { return }
        let scale = min(box.width / natural.width, box.height / natural.height)
        let fitted = CGRect(x: box.midX - natural.width * scale / 2,
                            y: box.midY - natural.height * scale / 2,
                            width: natural.width * scale, height: natural.height * scale)
        ctx.drawLayer { layer in
            layer.opacity = opacity
            layer.draw(resolved, in: fitted)
        }
    }

    /// 0 before `from`, 1 after `to`, smoothstepped between — so a shape grows into place rather
    /// than appearing.
    private func ramp(_ value: Double, from: Double, to: Double) -> Double {
        guard to > from else { return value >= to ? 1 : 0 }
        let t = min(1, max(0, (value - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Canvas

/// One RealityKit surface that loads a candidate, tints the arriving thing apart from its
/// surroundings, and runs whichever kind of timeline that candidate has.
///
/// The run has no clip while it fills. The asset carries the outline as a few hundred ordered
/// stroke prims and the solid figure as 24 horizontal slabs, and this view switches their
/// visibility from a fraction. That is the point: a baked clip runs on a clock, and a download
/// does not. It also dodges needing a custom Metal shader, since RealityKit cannot clip a mesh
/// to a plane.
///
/// The fill ends by handing over to a clip: at 100 % every stroke and slab is hidden, the
/// six-part figure underneath is shown, and the wake-up plays. The two are geometrically
/// identical, so the swap is invisible — and it is the only way to get a limb to move, because a
/// stack of slabs has no limbs.
struct TutorSceneCanvas: View {
    var asset: String
    /// The cast's charcoal — light-theme ink on a dark ground, same pair the figure canvas uses.
    var ink: Color
    /// What the *arriving* thing wears.
    var accent: Color
    /// Prim-name prefixes that take the accent (see `TutorScene.branded`).
    var branded: [String]
    /// nil runs the scene's own timeline; a fraction holds it there.
    var scrub: Double?
    /// When the current pass began. nil means armed and blank — nothing has been pressed.
    var runStart: Date?
    var runToken: Int
    var target: SIMD3<Float>
    var distance: Float
    /// Fired once the wake-up clip has finished, so a caller can start whatever comes after it.
    /// Called from the run task rather than from the render loop — writing SwiftUI state out of
    /// `RealityView`'s update closure would re-enter layout on every frame.
    var onFinish: () -> Void = {}

    @State private var root = Entity()
    @State private var camera = PerspectiveCamera()
    @State private var loaded: Entity?
    @State private var playback: AnimationPlaybackController?

    /// The fill slabs, lowest first, and the outline strokes in draw order — each paired with the
    /// index authored into its prim name. Sorting by name would be enough today; the index is
    /// kept because it is what the threshold is actually made of, and a slab dropped from the
    /// bake for being empty must not shift the ones above it. The two groups are cut at very
    /// different resolutions (24 slabs, ~276 strokes), so neither can borrow the other's count.
    @State private var fillBands: [(index: Int, entity: Entity)] = []
    @State private var strokes: [(index: Int, entity: Entity)] = []
    /// The six-part figure the wake-up clip moves. Hidden for the whole fill.
    @State private var solidParts: [Entity] = []

    @State private var woke = false
    /// True only while something is actually moving. A canvas that holds a display link open
    /// after its one play-through is pure battery burn, and this one plays through exactly once.
    @State private var isRunning = false
    @State private var runner: Task<Void, Never>?
    /// When the fill actually begins, which is not always `runStart`. If the asset is still
    /// loading when the press lands, `runStart` is already in the past by the time there is
    /// anything to reveal, and driving progress from it would drop the learner into the middle
    /// of the draw. Clamping to "now" costs a late start and keeps the whole sequence.
    @State private var effectiveStart: Date?
    /// Flipped once the prims are found. The run is kicked off by *observing* this rather than by
    /// calling `start()` at the end of `load()`, and that distinction is the whole bug this view
    /// spent two rounds on.
    ///
    /// `.task` captures the view value it started with. Everything after the first `await` — the
    /// entire tail of `load()` — therefore sees the `runStart` that existed when the screen
    /// appeared, which is `nil`, no matter what the parent has set since. Calling `start()` from
    /// there took the "armed, nothing pressed" branch forever. Meanwhile the press *did* reach
    /// `start()` through `onChange`, but arrived before the asset had loaded and returned early
    /// for want of geometry. Two paths, each missing the half the other had.
    ///
    /// `onChange` actions run against the current view value, so routing both triggers through it
    /// means whichever lands second sees both facts. It is also why replay always worked: by then
    /// the asset was in memory and a single fresh `onChange` had everything.
    @State private var ready = false

    /// Set to true to trace the sequence to the console.
    private static let logs = false

    var body: some View {
        TimelineView(.animation(paused: !isRunning)) { context in
            surface(beat: context.date)
        }
        .task(id: asset) { await load() }
        .onChange(of: ready) { start() }
        .onChange(of: runToken) { start() }
        .onChange(of: scrub) { start() }
        .onChange(of: accent) { paint() }
        .onChange(of: distance) { SceneRig.aim(camera, at: target, distance: distance) }
        .onChange(of: target) { SceneRig.aim(camera, at: target, distance: distance) }
        .onDisappear {
            runner?.cancel()
            isRunning = false
            loaded?.stopAllAnimations(recursive: true)
        }
    }

    private func surface(beat: Date) -> some View {
        RealityView { content in
            camera.camera.fieldOfViewInDegrees = 30
            SceneRig.aim(camera, at: target, distance: distance)
            content.add(camera)
            for light in SceneRig.lights() { content.add(light) }
            // Content arrives via `load`: this closure runs once, so loading here would mean a
            // change of `asset` never reaching the scene.
            content.add(root)
        } update: { _ in
            // Reading the beat is what makes each tick a genuine change, so the frame gets
            // presented — and during a fill it is also the clock, since there is no clip playing
            // that RealityKit could advance on its own.
            guard !woke, scrub == nil, !fillBands.isEmpty, effectiveStart != nil else {
                _ = beat
                return
            }
            fill(to: TutorRun.progress(from: effectiveStart, at: beat))
        }
    }

    // MARK: Loading

    private func load() async {
        loaded = nil
        playback = nil
        ready = false
        fillBands = []
        strokes = []
        solidParts = []
        root.children.removeAll()

        do {
            let scene = try await Entity(named: asset, in: .main)
            scene.removeCamerasAndLights()
            loaded = scene
            collectParts(in: scene)
            paint()
            root.addChild(scene)
            log("loaded \(asset): \(strokes.count) strokes, \(fillBands.count) slabs, "
                + "\(solidParts.count) parts")
            // Never `start()` here — see `ready`. This line is the trigger.
            ready = true
        } catch {
            // Silently failing here is how a missing or renamed asset turns into "the animation
            // just does not play", which is indistinguishable from a logic bug and costs a day.
            print("[TutorScene] FAILED to load \(asset): \(error)")
        }
    }

    /// Find the strokes, the slabs and the six parts once, at load. The alternative — walking the
    /// subtree on every frame — would put a full descendant traversal inside the display link.
    private func collectParts(in scene: Entity) {
        var fill: [(Int, Entity)] = []
        var drawn: [(Int, Entity)] = []
        var solid: [Entity] = []
        var queue = [scene]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            let name = next.name.lowercased()
            if let index = index(of: name, prefix: "fuell_") {
                fill.append((index, next))
                continue   // its meshes ride along; nothing below a slab is addressed separately
            }
            if let index = index(of: name, prefix: "strich_") {
                drawn.append((index, next))
                continue
            }
            if name.hasPrefix("figur_") {
                solid.append(next)
                continue
            }
            queue.append(contentsOf: next.children)
        }
        fillBands = fill.sorted { $0.0 < $1.0 }.map { (index: $0.0, entity: $0.1) }
        strokes = drawn.sorted { $0.0 < $1.0 }.map { (index: $0.0, entity: $0.1) }
        solidParts = solid
    }

    private func log(_ message: @autoclosure () -> String) {
        guard Self.logs else { return }
        print("[TutorScene] \(message())")
    }

    private func index(of name: String, prefix: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        return Int(name.dropFirst(prefix.count))
    }

    // MARK: Running

    /// Begin the run: the fill, then the wake-up. Or hold at a scrubbed fraction. Or do nothing
    /// at all, if there is nothing loaded to run yet.
    ///
    /// That last case is the one worth spelling out, because getting it wrong is a bug that only
    /// appears on a cold start. `start()` is called from two places — the load finishing, and the
    /// press — and which lands first is a race against however long it takes RealityKit to read a
    /// 750 KB asset with three hundred prims. This used to fall through to "no bands, so it must
    /// be a clip-only scene, play the clip", which was true while three other candidates existed
    /// and is now simply wrong: it fired the wake-up into a figure whose parts were about to be
    /// hidden, and left `onFinish` — and so the poster — unreachable. The symptom was a scene
    /// that never played until you pressed replay, by which time the asset was in memory.
    ///
    /// Returning early is safe because `load()` calls `start()` itself once the prims are found.
    private func start() {
        runner?.cancel()
        woke = false
        loaded?.stopAllAnimations(recursive: true)

        guard !fillBands.isEmpty else {
            log("start: nothing loaded yet, waiting for the asset")
            return
        }
        guard scrub == nil else {
            effectiveStart = nil
            isRunning = false
            if let scrub, scrub >= 1 {
                woke = true
                showSolid()
            } else {
                fill(to: scrub ?? 0)
            }
            return
        }
        guard let runStart else {
            // Armed: a blank page, waiting for a press. Not a paused animation — there is
            // nothing on screen to pause.
            log("start: armed, nothing pressed")
            effectiveStart = nil
            isRunning = false
            fill(to: 0)
            return
        }

        // `runStart` is handed over already offset by the prologue, so the wait is whatever is
        // left of that plus the run itself. Reading it here rather than adding the constant
        // keeps one definition of when the figure begins.
        effectiveStart = max(runStart, .now)
        isRunning = true
        fill(to: 0)
        log("start: running in \(String(format: "%.2f", max(0, runStart.timeIntervalSinceNow)))s")
        let lead = max(0, effectiveStart?.timeIntervalSinceNow ?? 0)
        runner = Task { @MainActor in
            try? await Task.sleep(for: .seconds(lead + TutorRun.seconds))
            guard !Task.isCancelled else { return }
            let tail = wake()
            try? await Task.sleep(for: .seconds(tail + 0.4))
            guard !Task.isCancelled else { return }
            isRunning = false
            onFinish()
        }
    }

    /// Hand the scene over to the six-part figure and play the wake-up. Returns the clip's length
    /// so the caller knows how long to keep the timeline alive.
    @discardableResult
    private func wake() -> TimeInterval {
        log("wake")
        woke = true
        showSolid()
        guard let scene = loaded, let clip = clip(of: scene) else { return 0 }
        playback = scene.playAnimation(clip)
        return clip.definition.duration
    }

    /// Same clip-selection rule as `FigurSceneView`, and it is load-bearing for the same reason:
    /// a Blender-authored USD exposes its motion many ways, and looping over `availableAnimations`
    /// ends on the root's empty "default subtree animation", which pins everything at the bind
    /// pose — a scene that appears fully built, having moved not at all.
    private func clip(of scene: Entity) -> AnimationResource? {
        let clips = scene.availableAnimations
        return clips.first { $0.name == "global scene animation" }
            ?? clips.max { $0.definition.duration < $1.definition.duration }
    }

    // MARK: Fill

    /// Draw first, then fill: the outline owns the first `drawShare` of progress and the solid
    /// owns the rest, with the head deliberately slowest (see `TutorRun.pour`).
    private func fill(to progress: Double) {
        reveal(strokes, upTo: TutorRun.draw(progress))
        reveal(fillBands, upTo: TutorRun.pour(progress))
        for part in solidParts where part.isEnabled { part.isEnabled = false }
    }

    /// Assign only what actually changes. There are close to 300 stroke prims, and writing
    /// `isEnabled` on every one of them every frame is ~18k component writes a second to say
    /// nothing — the comparison is free by contrast.
    private func reveal(_ pieces: [(index: Int, entity: Entity)], upTo progress: Double) {
        guard let top = pieces.last?.index else { return }
        let count = Double(top + 1)
        for piece in pieces {
            let wanted = progress >= Double(piece.index + 1) / count
            if piece.entity.isEnabled != wanted { piece.entity.isEnabled = wanted }
        }
    }

    private func showSolid() {
        for piece in fillBands where piece.entity.isEnabled { piece.entity.isEnabled = false }
        for piece in strokes where piece.entity.isEnabled { piece.entity.isEnabled = false }
        for part in solidParts { part.isEnabled = true }
    }

    // MARK: Paint

    private func paint() {
        guard let scene = loaded else { return }
        recolor(scene, with: ink)
    }

    /// Walk down, switching ink for accent the moment a branded subtree starts. Written as its
    /// own walk rather than reusing `tintEveryModel`, which paints a whole subtree one colour —
    /// on a scene with two casts in it that recolours both, which is exactly the confusion the
    /// separate prim prefixes exist to prevent.
    private func recolor(_ entity: Entity, with color: Color) {
        var color = color
        let name = entity.name.lowercased()
        if branded.contains(where: name.hasPrefix) { color = accent }
        if let model = entity as? ModelEntity, var component = model.model {
            let tint = UIColor(color)
            component.materials = component.materials.map { material in
                guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                pbr.baseColor = .init(tint: tint)
                return pbr
            }
            model.model = component
        }
        for child in entity.children { recolor(child, with: color) }
    }
}

#Preview {
    NavigationStack { TutorSceneLabView() }
}

// MARK: - Where Download goes

/// The real Model screen, reached from the scene's Download button.
///
/// Not a second pitch and not a copy of one: `ModelSettingsView` already leads with the tutor
/// that fits this device, as a full card with a Recommended badge, and collapses the other three
/// behind "Other sizes". The suggestion this screen makes is therefore the same suggestion the
/// destination makes, which is the only way a recommendation survives the tap that acts on it.
private struct TutorModelChoiceScreen: View {
    var modelManager: MLXModelManager
    var mlxService: MLXGenerationService
    /// Leaves onboarding entirely and lands on Home. This screen is the second exit, and the one
    /// most people will take: a tutor downloads for minutes, and making someone watch it here
    /// would be the one part of onboarding that genuinely wastes their time. Home's
    /// `ModelUpgradeNudge` picks the download up and reports it there.
    var onDone: () -> Void

    var body: some View {
        Form {
            ModelSettingsView(modelManager: modelManager, mlxService: mlxService)
        }
        .themedListScreen()
        .navigationTitle("Choose your tutor")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { exitBar }
    }

    private var exitBar: some View {
        VStack(spacing: 6) {
            Button {
                onDone()
            } label: {
                Text(mlxService.isLoading ? "Continue \u{2014} it keeps downloading" : "Continue to the app")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if mlxService.isLoading {
                Text("You can use everything that works offline while it lands.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }
}
