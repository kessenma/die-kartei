# Preposition 3D Iconography — Rollout Plan

Taking the Blender rig from a test screen to the preposition exercises. Status legend: ✅ done ·
🚧 in progress · ⬜ not started

Rig: `tools/blender/prep_render.py`. Judging surface: `PrepositionRenderTestView` (reachable from
the bottom of the preposition hub; **kept deliberately** — it is where every scene is judged on
device, superseding this doc's earlier delete-before-ship note). Feature background:
[[LEARNER_MEMORY.md]] Phase 10.

---

## 2026-08-12 — One set, one cast: „Die Figur führt vor"

The Klassisch/Geschichte style split is **gone** (the four authored story scenes became the
canonical ones; `PrepositionSceneStyle`, `storyRelations`, and both pickers deleted), and all
36 words were reworked in one pass under a single design language:

- **Die Figur appears in every scene** — the Bauhaus figure (`tools/blender/figur.py`,
  imported by the prep rig): the *actor* in human/relational words (strolls with the Hund in
  mit, waits by the Standuhr in seit, sits at the Tisch in um), the *demonstrator* in purely
  spatial ones (a shared stage mark, `zeig` pose pointing at the subject — see
  `demonstrator()` in the rig; `side`/`depth` shift the mark when the action owns its lane).
- **The case-tinted subject is always one mesh** (Ball, Hund, Geschenk, Uhr, Bild) — the
  runtime tints and translates exactly one prim, so the six-part Figur is never the subject.
  Its parts stay flat (no parent) so the piece walk sees them; `movers: "figur"` strolls them.
- **Primary sentence = what's on screen.** Array order in `prepositions.json` is the contract:
  the scene-depicting sentence leads (first per case for two-way words), old sentences follow
  as extras. No marker field.
- **Ambient clips** (the Standuhr's hand) are the only baked animation: case-neutral by
  authored contract because the runtime auto-plays clips on the question side too. Every
  animated export writes a plain-text `.usda` twin, and `--verify` fails TimeSamples on any
  prim outside the relation's `ambient` whitelist.
- **Every word has a scene now** — including the formal Genitiv set (roaming orbits/patrols
  instead of parked idles) and `beiderseits` (Zaun, Mann one side, Hund the other), which had
  none. The "Abstract — no scene, ever" list below is retained as history but obsolete.
- Cast scale: Mann 1.7, Hund 0.95 (1.05 seated in the Kiste), house 3.0.

---

## The scaffold fades — it isn't withheld

An earlier draft of this plan said an icon must never appear before the learner answers, because
every preposition exercise tests something the picture gives away: the Kasus drill asks *which
case*, and a picture of a thing moving and a thing at rest announces "two-way" before they guess.

That reasoning holds for someone who already knows what two-way *means*. It's exactly backwards
for a beginner, who can't be tested on a distinction nobody has shown them yet. Withholding the
picture there doesn't preserve the exercise; it just makes the first encounter a coin flip.

Sharpening it further: **the case is encoded by the color and the two-state contrast, not by the
geometry.** A ball resting on a table doesn't say whether `auf` is fixed-Dativ or two-way. A
*teal* ball says Dativ. A *pair* of states says Wechsel. The scene itself is innocent; the case
coding on top of it is what leaks.

That splits the picture into two halves that can be shown at different times:

- **Question side — the scene, assembled, neutral.** Static, subject in neutral grey, no arrow, no
  case color. Teaches a beginner what the preposition *means* while revealing nothing about what's
  being asked. Shown for every preposition, every time, at every level.
- **Reveal — the scene resolves.** Pieces settle into place, the subject takes its case color, and
  for a two-way preposition the Wohin/Wo loop begins. This is the payoff and the teaching moment.

Because the question side carries no case information, **the default path needs no scaffold gate
at all**, and the settings collapse to one switch rather than three:

| Setting | Behavior |
|---|---|
| **Show pictures** (default on) | Neutral scene on the question, resolved scene on reveal |
| Teaching mode | Fully resolved scene on the question side too — case color and all |
| Off | Text only |

**Teaching mode is the only one that needs the mastery gate.** `recordRound` takes a `scaffolded`
flag per outcome and only feeds *unscaffolded* first-try answers to
`LearnerMemoryService.applyDrillResult`. Otherwise a learner reading answers off a colored picture
looks to the coach like someone who has mastered the Präpositionen skill, and every downstream
surface — Coach's Picks, the "Needs work" flame, the Today plan, conversation steering — inherits
that lie. Round history and streaks still count; only the skill signal is gated.

**Matching stays picture-free.** Its question isn't the case, it's the meaning, and an icon on the
German tile makes it pointing rather than recall. There's no beginner argument for it either —
the meaning is printed on the tile opposite.

## What gets a scene, and what doesn't

**Two-way (10) — full Wohin/Wo pair, animated.** The motion *is* the lesson.
`in · an · auf · hinter · neben · über · unter · vor · zwischen · entlang`
Built: `auf · in · unter · über · neben · zwischen`. Remaining: `an · hinter · vor · entlang`.
(`entlang` is really a postposition taking the Akkusativ — its scene is a half-truth, so it stays
`tier: advanced` and is the lowest priority of the four.)

**Fixed-case, spatially depictable (12) — single state, no motion pair.** These illustrate
*meaning*, not case, so they earn a spot on the cards and nowhere near the Kasus drill.
`durch · um · gegen · bis · ohne · aus · bei · mit · nach · von · zu · gegenüber`

**Abstract (14) — no scene, ever.** `für · seit · außer · statt · trotz · während · wegen` plus
the seven formal Genitiv prepositions. There is no honest picture of "despite"; invented
iconography for these would be decoration that teaches nothing and still costs load time.
*(Obsolete — every one of these has a scene as of 2026-08-12; see the section at the top. The
pictures that cracked it: für = a gift changing hands, seit = a clock still ticking, trotz = an
obstacle cleared, wegen = a shove and its consequence, beiderseits = a fence with the pair split
across it.)*

## Delivery: one live scene per screen, stills everywhere else

| Surface | Format | Why |
|---|---|---|
| Kasus drill, question side | USDZ, static, **neutral** | Meaning without the case; safe at every level |
| Kasus drill, reveal | USDZ, assemble → settle → tint → idle | The teaching moment |
| Card deck | USDZ, one canvas above the deck | See "one canvas" below |
| "Wohin oder Wo?" question | USDZ, static, **neutral** | Same split |
| "Wohin oder Wo?" answer state | USDZ, resolves | Always shown |
| Rules sheet, two-way test | USDZ, animated | The `wohinwo` demo — the rule, not an example of it |
| Hub rows, drill buttons, chips | Static `flat` PNG | Shading muds below ~40pt (verified on device) |
| Matching tiles | **Nothing** | Would leak the meaning being tested |

`RealityView` has real per-instance setup cost, so the rule is **at most one live scene visible at
a time**. Anything in a list, grid, or repeated row takes a still.

### One canvas, swapped — not one view per word

`RealityView`'s `make` closure runs **once**. Loading the USDZ there means a later change of asset
never reaches the scene, so paging to the next drill question or the next card would leave the
previous preposition on screen. The load therefore lives in `.task(id: asset)`, which re-runs on
change and swaps the entity under the same camera and lights.

That turns the canvas into a reusable surface, which is what makes the card deck work: the canvas
sits **above** the deck, outside the card's `rotation3DEffect`, and re-poses as you flip a card or
page to the next word. The card underneath stays text. One RealityKit surface serves a whole round
or a whole deck instead of one per item — and it dodges the transform problem rather than fighting
it.

## Progressive reveal — the scene assembles itself

The reveal isn't a cut from one image to another; the scene **completes**. For `zwischen` the ball
is already centered on screen while the question is up, and on answer two bars glide in from left
and right to close around it — the word's meaning arrives as a movement rather than as a picture
that was there all along.

Four beats, composable per scene:

1. **Assemble** — reference pieces travel in from off-screen to their authored positions.
2. **Settle** — the subject moves into its relation (already built as `travelPhase`).
3. **Tint** — subject lerps neutral grey → its case color. The case coding *arrives*, which is
   what makes it read as the answer rather than as decoration.

   For a two-way preposition the color follows **motion, not position**: orange while the subject
   is travelling, teal once it stops. Colouring by where it *is* — orange at one end, teal at the
   other, a gradient between — states the rule wrongly, because a ball halfway through a journey
   is not half-Dativ. Motion-based colouring also makes both ends of the loop read as Dativ,
   which is right: stopped is stopped.
4. **Idle** — two-way prepositions enter the seamless Wohin/Wo loop; fixed-case ones rest.

**Entry directions are derived, not authored.** Each piece enters from the direction it already
sits in relative to the scene center: `from = to + normalize(to - center) * distance`. The
`zwischen` bars fly outward-in, the `in` walls rise, a table lifts from below — all falling out of
the geometry with no per-preposition choreography to maintain. Stagger by ~60 ms per piece so it
reads as designed rather than mechanical.

**Risk worth naming:** a full assembly on all ten reveals of a round will wear thin fast. Mitigation
is to play the full assembly the first time a preposition appears in a session and only the settle
+ tint thereafter, keeping the whole thing under ~600 ms. This is a tuning question, not a free
win. Under Reduce Motion, skip straight to the resolved state.

## Prop library

The sphere-and-slab vocabulary is legible but generic, and it wastes a hook that's already in the
data: every entry in `prepositions.json` ships a worked example. `auf` is *"Das Buch liegt auf dem
Tisch"* — so the reference form should be a **table**, not a floating bar. When the picture shows
the thing the sentence names, the image and the German reinforce each other instead of running on
separate tracks.

All props stay built from the same primitives in the same charcoal, so nothing breaks the Bauhaus
read. They're compositions, not models — a table is a top plus four legs.

| Prop | Unlocks | Cost |
|---|---|---|
| **Table** (top + 4 legs) | `auf`, `unter`, `neben`, `über` — and matches their example sentences | ~15 lines |
| **Wall** (tall thin slab, standing) | `an` ("an die Wand"), `vor`, `hinter`, `gegen` | trivial, exists |
| **Figure** (capsule + sphere head) | `bei`, `mit`, `von`, `zu`, `nach`, `gegenüber`, `ohne` — the fixed-case set is mostly about a *person* going somewhere, which a bouncing ball can't express | ~10 lines |
| **Path** (row of flat dashes) | `entlang`, `durch`, `bis`, `nach`, `von`, `zu` — all trajectory words | ~10 lines |
| **Ghost** (start pose at low alpha) | Motion in a *still*, so the static renders can show Wohin without an arrow | ~5 lines |

The figure is the highest-value addition after the table: it's what makes Phase 3 possible at all.
"Ich fahre mit dem Bus" and "Ich wohne bei meinen Eltern" are person-shaped ideas, and today's
vocabulary has no way to say "person."

**Deliberately not adding:** literal modeled objects (a cat, a bicycle). They'd cost real modeling
time, break the abstraction, and buy less than the table does — the abstraction is carrying its
weight right now. Also not adding a second subject color: the orange/teal case coding is the
system's backbone and a third accent would dilute it.

**Wiring:** add an optional `scene` object to each entry in `prepositions.json` naming its prop
and relation, so the JSON stays the single source of truth for content *and* iconography rather
than the mapping living in a Swift or Python lookup table.

## Work

### Phase 0 — Props + scaffold plumbing ⬜
- Add table, wall, figure, path and the ghost pose to the rig; re-render the six existing
  relations against their example sentences (`auf`/`unter`/`neben`/`über` move to the table).
- `scene` block in `prepositions.json`, so content and iconography share one source.
- `PrepositionPictureMode` (`on` / `teaching` / `off`) on `MLXModelManager`, surfaced in the hub's
  options section next to the existing hint toggle.
- `scaffolded` flag threaded through `PrepositionAnswerOutcome` → `recordRound`, gating only
  `applyDrillResult` — set only in teaching mode, since the default question side is caseless.
- A neutral subject material (grey, same charcoal family) so the question-side scene can render
  before the case is known.

### Phase 1 — Shared component + the drill reveal ⬜
- `PrepositionSceneView`: the one place camera, key/rim/fill lights, runtime tint, and the loop
  phase live. Lifted from `PrepositionRenderTestView` so the three consumers don't copy-paste it.
  - `travelPhase(_:)` moves in as the standard motion: descend → dwell → rise, smoothstep eased,
    periodic and flat at both ends so the cycle closes with no snap-back.
  - Subject tint lerps Akkusativ orange → Dativ teal with the travel, so the loop states the
    case rule without a caption.
  - Honors `@Environment(\.accessibilityReduceMotion)` by falling back to the static `dat` render.
  - Pauses on `onDisappear` — a spinning scene behind a dismissed sheet is pure battery burn.
- `PrepositionScene`: owns the asset naming convention (`prep3d-<word>-<state>-<look>`) and
  answers `hasScene(for:)`, so callers never construct a name by hand and a missing asset
  degrades to text instead of a red placeholder.
- Render `an · hinter · vor` (+`entlang`, lower priority) into `RELATIONS`.
- Wire into `PrepositionCaseGameView.reveal(_:)`, **two-way prepositions only**, replacing the
  stacked Wohin/Wo example sentences with the animation plus the two sentences beneath it.

### Phase 2 — Cards and the rules sheet ⬜
- `PrepositionCardsView` back face: animated pair for two-way, static `dim` for fixed-case.
  The card is 420pt tall and the back is already dense — the scene replaces the two example
  blocks rather than joining them.
- `PrepositionRulesSheet` two-way test section: one shared `in` demo above the Wohin/Wo rows.

### Phase 3 — Fixed-case meaning icons ✅
- ✅ 11 single-state relations, with three new reference kinds: `portal` (a wall with a hole, for
  `durch` — the one relation whose subject sits *inside* the reference), `ring` (dashes circling
  a core, since a straight arrow cannot say "around"), and `goal` (a path that stops at a marker,
  shared by `bis` / `nach` / `von`).
- ✅ `governs` on those entries fixes the resolved color: a fixed-case subject is always its own
  case, where a two-way one borrows whichever case it is currently in.
- ✅ The `figure` prop is what makes the Dativ set work — `bei`, `mit`, `zu`, `von` and `nach` are
  person-shaped ideas, and a sphere cannot say "person". `bei` and `mit` are the same arrangement
  static vs. moving, which is exactly the difference between "at someone's place" and "along
  with someone"; `nach` targets a place-marker and `zu` targets a figure.

**Two things cut, deliberately:**
- **`ohne` has no scene.** There is no honest single-frame picture of absence, and the candidates
  (a ghosted sphere, a crossed-out one) teach nothing. It stays text.
- **No hub-row icons.** They were the reason the `flat` look existed; dimensional shading muds
  below ~40pt (verified on device). With no consumer, `flat` stopped being rendered at all, which
  halved the shipped PNG count. Small surfaces keep their SF Symbols.

### Phase 4 — Ship prep 🚧
- ✅ `tools/blender/render_all.sh` regenerates every shipped asset in one command, and documents
  in its own header why the set is exactly what it is.
- ✅ Asset set trimmed to what is actually read: two-way relations get neutral/akk/dat, fixed-case
  ones get neutral/dat (their `akk` render would be a byte-for-byte duplicate), `dim` only.
- ✅ USDZ exported from the **neutral** pose, so no arrow geometry ships. Arrows are a still-image
  affordance — a picture that can't move has to say "moving" somehow — and baking one into the
  live scene would leak a motion cue, and so the Akkusativ, onto the question side.
- ⬜ Move assets out of `Resources/` root into an asset catalog or folder reference.
- ⬜ Delete `PrepositionRenderTestView` and its hub row (kept for now as the one place to see
  every relation at once).
- ⬜ Measure: app size delta, `RealityView` first-frame latency on the oldest supported device,
  memory while a drill round is running.

## Verben mit Präpositionen — scene backlog 🚧 (props + gestures built, scenes not started)

Source: Kyle's class sheet „Verben mit Präpositionen" (2026-10-01), 42 pairs. **None of them are
in the app yet.** `prepositions.json` holds the 36 bare prepositions. The only verb pairs
anywhere are *warten auf* (Kasus stories, `KasusCheckSheet`) and *sich freuen auf* (one fill-in,
`praep-kontr-009`). The data and an exercise come first. This list records which pairs would need
Blender work once they exist.

**Why the existing 36 scenes can't stand in.** They show the preposition's *place* meaning. In a
verb pair the verb fixes the case and the place meaning mostly drops away. The auf scene (ball
drops *onto* the table, so Akk) would give *warten auf* the right case for the wrong reason. The
an scene would give *zweifeln an* the wrong case: it's Dat, and nothing is resting anywhere. Every
pair that gets a picture needs a new one. Grouping verbs that can share a stage brings 42 pairs
down to 25 scenes.

Fit:
- **echo**: the place meaning survives and agrees with the case (Angst *vor* = in front of it,
  Dat). These are the cheapest and most memorable, and they can often reuse an existing motion kind.
- **trap**: a two-way preposition with a fixed case and no movement (warten auf + Akk, über + Akk
  for "about"). The scene has to *show stillness* while the tint says Akkusativ. This is where the
  Wo/Wohin rule breaks, so these teach the most.
- **abstract**: a mental or social verb. It needs a new visual convention (thought bubble, speech
  arc) or stays text-only.

Seeds are starting points for the brainstorm, not decisions.

| # | Scene | Verbs (case) | Fit | Seed |
|---|---|---|---|---|
| 1 | Angst | Angst haben vor, sich fürchten vor (Dat) | echo | Figur backs away from something looming in front of it, never past it. Reuse vor's dat pose. |
| 2 | Ekel | sich ekeln vor (Dat) | echo | Same staging as 1, head turned away instead of backing off. Could be a clip on scene 1. |
| 3 | Leiden | leiden unter (Dat) | echo | Figur slumped under a raincloud or heavy block that stays over it. |
| 4 | Arbeit | arbeiten an (Dat) | echo | Figur hammering at a half-built stack. At it, nothing lands on it. |
| 5 | Hilfe | helfen bei (Dat) | echo | Figur and Mann lifting one box together. |
| 6 | Ernährung | sich ernähren von (Dat) | echo | Figur takes apples off a tree, one by one. |
| 7 | Zugehörigkeit | gehören zu, zählen zu (Dat) | echo | A stray block slides into its row (shuttle). |
| 8 | Abhängen | abhängen von (Dat) | echo | A weight hanging off a hook; ab-hängen is literally "hang off". |
| 9 | Brief | schreiben an (Akk) | echo | Letter arcs from Figur to the Mann (shuttle + arc). |
| 10 | Fürsorge | sich kümmern um, sich sorgen um (Akk) | echo | Figur circles the Hund, tending it (reuse um's orbit). sorgen = slower orbit, head down. |
| 11 | Aufpassen | aufpassen auf (Akk) | trap | Figur stands still watching the Hund play. Nothing lands on anything, still Akk. |
| 12 | Warten | warten auf (Akk) | trap | Figur at a stop tapping its foot, clock hand turning, nothing arrives. |
| 13 | Freude | sich freuen auf, sich freuen über (Akk) | trap | Two beats: wrapped gift ahead, Figur bouncing (auf = still to come), then gift opened, Figur cheering (über = already here). Reuses the Geschenk lid rig. |
| 14 | Hoffen | hoffen auf (Akk) | trap | Figur looking up, hands together. Maybe shares 13's "ahead" beat. |
| 15 | Vorbereiten | sich vorbereiten auf (Akk) | trap | Figur stretching at a start line. |
| 16 | Antworten | antworten auf (Akk) | abstract | A ball (the question) tossed to Figur, tossed back. |
| 17 | Über = about | sprechen über, reden über, nachdenken über, sich ärgern über, sich beschweren über, sich streiten über, sich wundern über (Akk) | trap | One stage: a topic object on a plinth, Figur around it, one clip per verb (talk, chin-scratch, stomp, finger-wag, two Figurs tugging, head tilt). Teaches that über meaning "about" is always Akk. Best payoff: 7 verbs, 1 asset. |
| 18 | An = in mind | denken an, sich erinnern an, sich gewöhnen an (Akk) | abstract | Thought bubble holding the object. erinnern = a faded copy; gewöhnen = Figur flinches less each loop. |
| 19 | Zweifeln | zweifeln an (Dat) | abstract | Figur inspecting a wobbly block, shaking its head. Show next to 18, because an + Akk vs an + Dat is the trap. |
| 20 | Bitten | bitten um (Akk) | abstract | Figur holds out a hand to the Mann holding the ball. |
| 21 | Mit + people | sprechen mit, schimpfen mit (Dat) | abstract | Two Figurs face to face. schimpfen = arms waving at the Hund. |
| 22 | Angeben | angeben mit (Dat) | abstract | Figur holding a trophy up, turning to show it off. |
| 23 | Von = about | erzählen von, träumen von, handeln von (Dat) | abstract | Story or dream bubble holding the object. träumen = Figur lying asleep. handeln von = a book with the object on its cover. |
| 24 | Nach = toward | fragen nach, sich sehnen nach, verlangen nach (Dat) | echo | Figur reaching or gazing toward something far off. fragen = Figur pointing, question mark. |
| 25 | Interesse | sich interessieren für (Akk) | abstract | Figur leaning in over an object with a magnifier. |

**Sheet corrections** (the data should use these): *sprechen mit* is marked "(acc)" on the Dativ
page, but mit is always Dativ. *interessieren für* is reflexive: *sich interessieren für*. In the
example, „ich zweifel an" should be „ich zweifle an". *denken an* and *nachdenken über* are both
glossed "to think about". The cards need different glosses: "to think of / have in mind" vs "to
mull over".

### Built first: shared props and die Figur's gestures (2026-10-02)

Shared pieces that many scenes use, built before any one scene. Nothing here ships yet: no word in
`RELATIONS` uses them, and the judging renders live in the gitignored `tools/blender/renders/`.

**Props** (`prep_render.py`, `VERB_PROPS`). Each is a reference kind *and* a `subject_build`,
because in a verb scene the prop is often the preposition's object and so the tinted subject.
Each comes out as one joined mesh.

| Kind | Options | Serves |
|---|---|---|
| `blase` | `style: denk` (thought cloud + dots) or `sprech` (bubble + tail), `tail_to` the head; content stands at `bubble_slot(spec, height)` | 16, 17, 18, 21, 23 |
| `wolke` | `rain`, `scale` | 3 (and the same puffs as the thought cloud) |
| `brief` | upright envelope, flap in relief | 9, 16, 17 (beschweren) |
| `buch` | `style: zu` (closed, turned to show the page edge) or `offen` (propped on its near edge by `lean`) | 15, 23, 25 |
| `spinne` | `scale`; front is -Y | 1, 2 |
| `schild` | `variant: haltestelle` (round H sign) or `wegweiser` (`arrows`) | 12, 24 |
| `freund` (subject only) | a whole Figur joined into one tintable mesh, static `pose` | 5, 9, 21: verbs whose object is a person |

**Die Figur** (`figur.py`, "Gesten"). The rig now has a joint-space layer solved by forward
kinematics, so a leaning torso carries the arms and head (the six parts stay flat and unparented;
every older contract holds). 23 looping clips in `CLIPS`, one or more per scene. Each one's
`verbs` field names its verbs: schreck, ekel, kummer, hammer, heben, pflegen, wache, warten,
vorfreude, jubel, dehnen, werfen, reden, gruebeln, stampfen, schimpfen, staunen, bitten,
sehnen, stolz, schlafen, lesen, neugier.

- In a scene: `("figur", {"clip": "schreck", …})` bakes the clip at build time. Stills show
  frame 0, the key pose, which is also what the question side holds (clips play on the reveal
  only). `pose` also accepts any `GESTEN` name as a static pose.
- A second figure: `("figur", {"name": "freund", …})`. It needs its own name, because the
  runtime matches prims by substring. Two clips in one scene should share a period, since the
  export runs to the longer one.
- `ink` recolors a figure and `accent` its torso, from `figur.INKS` (charcoal, warmgrau, kreide)
  or a hex. No app code is involved: the runtime re-tints only the subject, so a figure keeps the
  color it was exported with. The inks differ from charcoal in warmth and value only, because
  every hue already means something in the app (gender, plural gold, the case colors, the
  question side's grey). Der Freund wears charcoal with a `kreide` torso (Kyle's pick from four
  candidates, 2026-10-02).
- `--verify` whitelists all six parts of any figure with a `clip`.

**Staging rules the renders taught** (they hold for the scenes):
- The head is a sphere, so turning it is invisible. Only nods and tilts read. "Looking" is a
  torso twist or a body turn.
- A reach only reads in profile. At this camera that is yaw **-69** (facing screen-right) or
  **111** (facing left); yaw -90 already points the arm into the lens. Sideways gestures (jubel,
  dehnen, stolz, staunen) and lying down (schlafen) read from the front, yaw **-159**.
  `figur.STAGING_YAW` holds the three.
- One-armed gestures use arm_r, the near arm when facing right. A figure facing left plays its
  clip with `mirror: True`.

**Judge them:**
- `figur.py -- --geste all --fast` writes a storyboard per clip, the catalog
  `renders/figur/gesten-katalog.png`, and a looping USDZ per clip. Open the USDZ in Quick Look,
  which plays baked clips.
- `prep_render.py -- --propsheet tools/blender/renders/prep` writes `verb-props.png`, every
  prop staged with the Figur.

### The prototype: `verben.py` + its data (2026-10-02)

Built apart from the shipped preposition set first (Kyle: prototype, then plan how it joins the
existing experience). It joined the app on 2026-10-03 (docs/VERB_PREPOSITIONS.md):
- the data moved to `Resources/verb_prepositions.json`, which the rig now reads;
- `verben.py --ship` writes the scenes, stills and `verb3d-manifest.json` into `Resources/`.

- **`Resources/verb_prepositions.json`** (was `tools/blender/verben.json`) holds the 42 verbs, with the sheet's corrections, a
  scene-matched example sentence each, the prepositional `object` phrase the scene tints, and
  notes (separable verbs, contrast pairs such as sprechen über / erzählen von).
- **`tools/blender/verben.py`** holds 39 scenes. Angst/fürchten, gehören/zählen and
  sprechen/reden über each share one. It reuses prep_render's rig and adds the props bus,
  pokal, kiste, äpfel, leiter, käfer, rahmen, ball and rudel, plus the held props hammer and
  lupe.
- **Outputs**, all into the gitignored `tools/blender/renders/verben/`:
  - `--sheet` writes `verben-szenen.png`.
  - `--usdz` writes `verb3d-<id>.usdz` and checks each one.
  - `--preview` writes `verben-vorschau.mp4`.

**All motion is baked into the USDZ, unlike the shipped set.** The shipped set moves the subject
at runtime from manifest `motion` kinds. Here a moving thing sits under a still holder prim, and
its clip moves the child. For the subject, the holder keeps the name `subject` (the runtime
positions that) and the tinted mesh inside is `<scene>_bewegt`. So Quick Look shows each scene
exactly as intended. Integration needs two things from the runtime: tint the mesh *under* the
`subject` prim (it already searches descendants), and play clips on the reveal (it already does).

## Open questions

1. **How often should the full assembly play?** Ten full assemblies in a ten-question round will
   wear out its welcome. First-appearance-per-session is the proposed rule; needs feeling out on
   a real round.
2. **Is the neutral subject legible enough?** A grey ball against charcoal props is a narrow value
   range. May need the neutral to be lighter than the reference forms rather than the same family.
3. **Does the reveal's motion compete with the reveal's text?** The learner just got it wrong and
   is reading a rule and an example sentence while something moves beside it. Worth trying
   assembly-then-freeze rather than assembly-then-loop.
4. **Device floor.** Everything so far is verified in the simulator on an M1 Max. RealityKit's
   cost on the oldest supported iPhone is unmeasured.
