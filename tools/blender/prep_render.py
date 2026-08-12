"""
prep_render.py — the preposition iconography rig.

Run headless:
    /Applications/Blender.app/Contents/MacOS/Blender --background \
        --python tools/blender/prep_render.py -- --prep auf --state dat --look flat

Every preposition image in the app comes out of this one scene: two objects (a SUBJECT
sphere and a REFERENCE form) at different transforms. The prepositions are a parameter
sweep over position, not 36 separate artworks, so adding one is a row in RELATIONS.

Color convention, matching the app's `PrepositionCasePalette`:
  - the SUBJECT is Akkusativ orange while it is moving (Wohin?) and Dativ teal at rest (Wo?)
  - the REFERENCE (bar, box, wall) is neutral charcoal, never a case color — a teal bar in an
    Akkusativ image would contradict the color coding the drill is teaching.

Two looks:
  - flat: emission shaders, no lights, orthographic. Reads as the Bauhaus pictogram.
  - dim:  matte Principled BSDF, key + fill area lights, soft contact shadow on the reference.

Both render with `film_transparent`, so output PNGs carry alpha and composite onto any
AppTheme ground without a baked-in background.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

# figur.py lives beside this file, but Blender does not reliably put a --python script's
# directory on sys.path. The figure rig owns the .usda-twin animation parsing this file's
# verifier reads (and, later, the figure builders the scenes pose).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import figur

# MARK: - Palette (exact hex from Models/Preposition.swift)

PALETTE = {
    "akkusativ": 0xE2701A,
    "dativ": 0x0E8794,
    "wechsel": 0x7B4FD6,
    "genitiv": 0x5F6B7C,
    "reference": 0x33383D,   # neutral charcoal — deliberately not a case color
    # The subject before its case is known: the question side shows the relation without
    # answering it. Deliberately *lighter* than the reference charcoal rather than the same
    # family — a grey ball on grey props is too narrow a value range to read.
    "neutral": 0xB9BEC4,
}


def srgb_to_linear(c: float) -> float:
    """Blender works in linear light; the view transform is forced to Standard below, so a
    linearized sRGB hex round-trips to that exact hex in the PNG."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(hex_value: int, alpha: float = 1.0):
    r = ((hex_value >> 16) & 0xFF) / 255
    g = ((hex_value >> 8) & 0xFF) / 255
    b = (hex_value & 0xFF) / 255
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), alpha)


# MARK: - Relations
#
# Each entry describes the two states of a two-way preposition. `subject` is the sphere's
# position; the reference form is built by `ref`. Units are Blender metres against an
# ortho camera 4 units wide, so ~1.0 reads as a quarter of the frame.
#
# Two schema extensions (formerly the Geschichte variant's; canonical since the styles
# merged, 2026-08-12):
#   - `subject_mesh`: {"file", "height", "yaw"} replaces the sphere with a converted prop
#     from tools/genprops/samples. Subject poses then place the prop's *base* (ground
#     point), not a center. The prop keeps the subject material, so runtime tinting and
#     the neutral-grey question side work exactly as for the ball.
#   - `ref` may be a LIST of (kind, spec) pairs — für needs a giver figure AND the dog.

SPHERE_R = 0.55

# The table top sits at z=0, so "resting on the table" is always z = SPHERE_R.
TABLE = ("table", {"size": (2.5, 1.5, 1.25), "at": (0, 0, 0.0)})

# MARK: - Stage conventions (die Figur führt vor)
#
# One design language across all 36 scenes: die Figur appears in every one — the actor in
# the human/relational words (walks with the dog, waits by the clock, sits at the table),
# the demonstrator in the purely spatial ones. The demonstrator always takes the same mark:
# back-left, clear of the subject's travel lane, yawed toward the action, far enough out
# that the subject stays the biggest thing in a 168pt drill canvas. One constant, so "same
# mark" is enforced by construction rather than by review.

FIGUR_HEIGHT = 1.7
FIGUR_MARK = (-2.35, 1.05, -0.75)   # back-left in x/y, standing on the figure ground


def demonstrator(pose="zeig", yaw=None, ground=FIGUR_MARK[2], side=-1, depth=FIGUR_MARK[1]):
    """The (kind, spec) pair a spatial scene appends to its ref list.

    Scenes whose ground is not the figure default (table scenes bottom out deeper) pass
    their own. `side=+1` mirrors the mark to back-right when the action owns the left
    lane (unter/über enter from the left; aus pops out of a left-standing box), and the
    default yaw flips with it so the raised arm keeps pointing at the action. `depth`
    pushes the mark further upstage for scenes whose subject sweeps the full width."""
    if yaw is None:
        yaw = 24.0 if side < 0 else 156.0
    return ("figur", {"at": (side * abs(FIGUR_MARK[0]), depth, ground),
                      "height": FIGUR_HEIGHT, "pose": pose, "yaw": yaw})

RELATIONS = {
    "auf": {
        "ref": [TABLE, demonstrator(ground=-1.36)],
        # "Das Buch liegt auf dem Tisch." Wohin: mid-flight above. Wo: resting on the top.
        "akk": {"subject": (0, 0, 1.75), "arrow": "down"},
        "dat": {"subject": (0, 0, 0.11 + SPHERE_R)},
    },
    "in": {
        # „Der Hund springt in die Kiste." / „Der Hund sitzt in der Kiste."
        # The cardboard box, sized so a seated dog peeks over the rim (floor top -0.62,
        # wall top 0.45, dog 1.3 tall). Promoted from the story set 2026-08-12; the
        # ball-in-box original retired with the style toggle.
        "ref": [
            ("openbox", {"size": (2.4, 1.7, 0.95), "at": (0, 0, -0.275), "flaps": True}),
            demonstrator(ground=-0.75),
        ],
        "subject_mesh": {"file": "hund", "height": 1.05, "yaw": 0},
        "akk": {"subject": (0, 0, 1.0), "arrow": "down"},
        "dat": {"subject": (0, 0, -0.62)},
    },
    "unter": {
        # The table earns its legs here — a floating bar can't show "underneath" as a
        # place you'd actually be. The ball enters from the left, so the mark mirrors.
        "ref": [TABLE, demonstrator(ground=-1.36, side=+1)],
        "akk": {"subject": (-2.0, 0, -0.72), "arrow": "right"},
        "dat": {"subject": (0, 0, -0.72)},
    },
    "über": {
        "ref": [TABLE, demonstrator(ground=-1.36, side=+1)],
        # Tight to the table: too much air and it reads as "in the sky", not "above the table".
        "akk": {"subject": (-2.2, 0, 1.02), "arrow": "right"},
        "dat": {"subject": (0, 0, 1.02)},
    },
    "neben": {
        "ref": [TABLE, demonstrator(ground=-1.36)],
        # On the floor beside the table, not floating at table-top height — at top height the
        # sphere merges into the corner of the top and the relation stops reading.
        "akk": {"subject": (2.72, 0, -0.81), "arrow": "left"},
        "dat": {"subject": (2.05, 0, -0.81)},
    },
    "zwischen": {
        "ref": [
            ("twobars", {"size": (0.42, 1.2, 1.7), "gap": 1.5, "at": (0, 0, 0.0)}),
            demonstrator(ground=-0.85),
        ],
        "akk": {"subject": (0, 0, 2.0), "arrow": "down"},
        "dat": {"subject": (0, 0, 0.0)},
    },
    "an": {
        # „Der Mann hängt das Bild an die Wand." / „Das Bild hängt an der Wand." — the
        # picture (one joined, tintable mesh) travels onto the wall face and hangs there,
        # with die Figur reaching toward it. The frame sits proud of the face (x = wall
        # face + frame depth), not embedded in it.
        "ref": [
            ("wall", {"size": (0.3, 2.4, 2.2), "at": (-0.9, 0, 0.5)}),
            ("figur", {"at": (0.9, 0.55, -0.52), "pose": "zeig", "yaw": 180}),
        ],
        "subject_build": "bild",
        "akk": {"subject": (1.3, 0, 0.6), "arrow": "left"},
        "dat": {"subject": (-0.68, 0, 0.75)},
    },
    "vor": {
        # Wider and lower than an `an` wall, so the sphere can overlap it in screen space —
        # depth only reads if the two shapes actually cross.
        "ref": [
            ("wall", {"size": (2.4, 0.28, 1.9), "at": (0, 0, 0.35)}),
            demonstrator(ground=-0.52),
        ],
        "akk": {"subject": (0, -2.9, -0.15), "arrow": "toward"},
        "dat": {"subject": (0, -1.25, -0.15)},
    },
    "hinter": {
        # Same wall. The whole read is occlusion: the sphere sits *behind* it and is partly
        # hidden, which is the only honest way to say "behind" in a single frame.
        "ref": [
            ("wall", {"size": (2.4, 0.28, 1.9), "at": (0, 0, 0.35)}),
            demonstrator(ground=-0.52),
        ],
        # Parked at the wall's right edge in *screen* space (screen_x ≈ 0.93·X + 0.36·Y at this
        # camera), so it is half-occluded. Fully behind reads as absent; fully clear reads as
        # "beside". Half is the only pose that says "behind".
        "akk": {"subject": (0.72, 2.9, -0.15), "arrow": "away"},
        "dat": {"subject": (0.72, 1.25, -0.15)},
    },
    "entlang": {
        "ref": [
            ("path", {"at": (0, 0, -0.55), "length": 3.6, "count": 7}),
            demonstrator(ground=-0.55),
        ],
        "akk": {"subject": (-1.7, 0, 0.0), "arrow": "right"},
        "dat": {"subject": (0.9, 0, 0.0)},
    },

    # MARK: The rule itself
    #
    # Not a preposition — the Wohin/Wo demo for the rules sheet. The two-way rule is general, so
    # illustrating it with `in` (a ball dropping into a box) taught one preposition rather than
    # the rule. A ball crossing an open plane and stopping says the whole thing: travelling is
    # Akkusativ, stopped is Dativ, and nothing else is in the frame to distract from that.
    #
    # It lives in RELATIONS so it inherits the same camera, lights, palette and loop machinery.
    # No preposition is named `wohinwo`, so it never reaches the drill.
    "wohinwo": {
        "ref": ("ground", {"at": (0, 0, 0.0)}),
        # No arrow: this one shows motion by actually moving.
        "akk": {"subject": (-1.95, 0, SPHERE_R)},
        "dat": {"subject": (1.95, 0, SPHERE_R)},
    },

    # MARK: Fixed-case relations
    #
    # One pose, not two: these prepositions don't switch case, so there is no contrast to
    # animate. `governs` fixes the resolved color — a fixed-case subject is always its own
    # case, where a two-way one borrows whichever case it is currently in.
    #
    # The arrow belongs to the *depiction* here rather than to a motion state, so it is drawn
    # on the resolved render and suppressed on the neutral one (an arrow implies movement,
    # which would hint Akkusativ before the learner has answered).

    # `motion` is the live scene's choreography, published through the manifest (remapped to
    # Y-up by `write_manifest`, same as akkOffset). Vectors are deltas from the resting subject.
    # The kind decides whether it loops: through/orbit/bounce/carry/idle repeat because their
    # meaning repeats; shuttle and abandon play once, because their return leg would state the
    # *opposite* relation (a ball that pops back into the box says "hinein", not "aus").

    "durch": {
        "governs": "akkusativ",
        "ref": [
            ("portal", {"size": (2.6, 0.4, 2.4), "at": (0.15, 0, 0.3), "opening": (1.35, 1.5)}),
            demonstrator(ground=-0.9, depth=1.4),
        ],
        # Through the OPENING: the hole's axis runs in depth, so the travel does too —
        # along the wall's width the ball shears through the solid frame "against the
        # grain" (Kyle, 2026-08-12). The swung "toward" arrow says depth without
        # foreshortening to a stub.
        "dat": {"subject": (0, 0, 0.25), "arrow": "toward"},
        # Ping-pong through the opening — a pass in either direction is still "durch".
        "motion": {"kind": "through", "from": (0, -2.4, 0)},
    },
    "um": {
        # „Der Ball rollt um den Tisch." — the orbit around a real table instead of the old
        # abstract ring, with the Mann seated at it on a stool (the „Wir sitzen um den
        # Tisch" sentence stays as the extra, and the picture now shows the sitting too).
        # No arrow: a straight one cannot say "around", and the orbit already does.
        # Table legs bottom out at z=-1.36, so the ground ball sits at -0.81 (like neben).
        "governs": "akkusativ",
        "ref": [
            TABLE,
            ("slab", {"size": (0.78, 0.78, 1.22), "at": (0, 1.45, -0.75)}),
            ("figur", {"at": (0, 1.45, -0.21), "pose": "sitz", "yaw": 180}),
        ],
        "dat": {"subject": (2.3, 0, -0.81)},
        "motion": {"kind": "orbit", "center": (-2.3, 0, 0)},
    },
    "gegen": {
        "governs": "akkusativ",
        # A side-on wall like `an`'s, so the impact can be shown across the frame rather than
        # into it — depth arrows foreshorten at this camera.
        "ref": [
            ("wall", {"size": (0.3, 2.4, 2.2), "at": (0.95, 0, 0.5)}),
            demonstrator(ground=-0.52),
        ],
        # The resting pose already touches the wall, so the strike is authored as a wind-up
        # *back* from it; the impact point is the rest contact itself.
        "dat": {"subject": (0.25, 0, 0.75), "arrow": "right"},
        "motion": {"kind": "bounce", "back": (-0.9, 0, 0)},
    },
    "bis": {
        "governs": "akkusativ",
        "ref": [
            ("goal", {"at": (0, 0, -0.55), "length": 3.0, "count": 6}),
            demonstrator(ground=-0.55),
        ],
        "dat": {"subject": (0.2, 0, 0.0), "arrow": "right"},
        # Travels the path and STOPS at the marker — arriving and staying is the meaning.
        "motion": {"kind": "shuttle", "from": (-1.8, 0, 0), "to": (1.05, 0, 0)},
    },
    "aus": {
        "governs": "dativ",
        # Flaps make it a cardboard box — "moving out" — without a texture in sight.
        "ref": [
            ("openbox", {"size": (1.9, 1.4, 1.5), "at": (-0.9, 0, 0.0), "flaps": True}),
            demonstrator(ground=-0.75, depth=-1.0),
        ],
        "dat": {"subject": (1.15, 0, 0.55), "arrow": "right"},
        # Starts inside the cavity and arcs over the wall (top z=0.75, ball r=0.55). The
        # runtime's arc path rises before it drifts, so the ball clears the wall instead of
        # shaving through it.
        "motion": {"kind": "shuttle", "from": (-2.05, 0, -0.62), "arc": 1.6},
    },
    "bei": {
        # „Der Hund ist beim Mann." — side by side, both facing out, at rest. `mit` is the
        # same pair in motion, which is the actual difference between "at someone's place"
        # and "along with someone"; `gegenüber` is the same pair facing each other across
        # a gap.
        "governs": "dativ",
        "ref": ("figur", {"at": (-0.55, 0, -0.75), "pose": "steh", "yaw": 0}),
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": 0},
        "dat": {"subject": (0.9, 0, -0.75)},
        # Being somewhere is the whole meaning; the idle bob only keeps the scene alive.
        "motion": {"kind": "idle"},
    },
    "mit": {
        # „Der Mann geht mit dem Hund spazieren." — the pair stroll together (carry). Die
        # Figur walks in the geh stride, yawed to face the travel (+X); the runtime slides
        # every figur_* piece in step with the dog, off-beat bob and all.
        "governs": "dativ",
        "ref": ("figur", {"at": (-0.75, 0, -0.75), "pose": "steh", "yaw": -90}),
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": 140},
        "dat": {"subject": (0.75, 0, -0.75), "arrow": "right", "arrow_base": (1.9, 0, -0.2)},
        "motion": {"kind": "carry", "delta": (0.9, 0, 0)},
        # The stride itself: baked counter-swing on the legs and arms (children of the
        # `figur` group — the runtime translates only the parent, so nothing fights).
        # Plays on the reveal only; see playsClips in PrepositionSceneView.
        "ambient": [
            {"prim": "figur_leg_l", "op": "swing_x", "amplitude": 20, "period": 0.9},
            {"prim": "figur_leg_r", "op": "swing_x", "amplitude": 20, "period": 0.9, "phase": 0.5},
            {"prim": "figur_arm_l", "op": "swing_x", "amplitude": 15, "period": 0.9, "phase": 0.5},
            {"prim": "figur_arm_r", "op": "swing_x", "amplitude": 15, "period": 0.9},
        ],
    },
    "nach": {
        # „Der Hund läuft nach Hause." — a destination that is a *place*: the house, with
        # the Mann waiting at the door. The dog arrives and stays; arriving is the meaning.
        "governs": "dativ",
        "ref": [
            ("mesh", {"file": "house", "at": (2.45, 0.9, -0.75), "height": 3.0, "yaw": -14}),
            ("figur", {"at": (1.15, -0.7, -0.75), "pose": "steh", "yaw": 90}),
        ],
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": 140},
        "dat": {"subject": (-1.35, 0, -0.75), "arrow": "right"},
        "motion": {"kind": "shuttle", "from": (-1.2, 0, 0), "to": (1.5, 0, 0)},
    },
    "zu": {
        # „Der Hund läuft zum Mann." — a destination that is a *someone*. Same idea as
        # nach, different target: the dog runs right up to die Figur and stays.
        "governs": "dativ",
        "ref": ("figur", {"at": (1.75, 0, -0.75), "pose": "steh", "yaw": 90}),
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": 140},
        "dat": {"subject": (-1.0, 0, -0.75), "arrow": "right"},
        "motion": {"kind": "shuttle", "from": (-1.2, 0, 0), "to": (1.35, 0, 0)},
    },
    "von": {
        # „Der Ball rollt vom Mann weg." — the mirror of zu: leaving the someone, ending
        # at rest away from him. Departure, not arrival.
        "governs": "dativ",
        "ref": ("figur", {"at": (-1.7, 0, -0.75), "pose": "steh", "yaw": -90}),
        "dat": {"subject": (0.95, 0, -0.2), "arrow": "right"},
        "motion": {"kind": "shuttle", "from": (-1.75, 0, 0)},
    },
    "gegenüber": {
        # „Der Hund steht dem Mann gegenüber." — facing each other across a clear gap.
        # The gap and the facing are what separate this from bei; nothing travels, the
        # standoff is the meaning.
        "governs": "dativ",
        "ref": ("figur", {"at": (-1.65, 0, -0.75), "pose": "steh", "yaw": -90}),
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": 0},
        "dat": {"subject": (1.35, 0, -0.75)},
        "motion": {"kind": "idle"},
    },
    "für": {
        # „Das Geschenk ist für den Hund." — giver left, dog right, the gift between them
        # wearing the case color. The gift is the object of für, so it is the subject.
        # Promoted from the story set 2026-08-12.
        "governs": "akkusativ",
        "ref": [
            ("figur", {"at": (-2.05, 0, -0.75), "pose": "zeig", "yaw": 0}),
            ("mesh", {"file": "hund", "at": (1.55, 0, -0.75), "height": 0.95, "yaw": 12}),
        ],
        "subject_mesh": {"file": "gift", "height": 0.85, "yaw": 0},
        "dat": {"subject": (0.3, 0, -0.75), "arrow": "right", "arrow_base": (-1.05, 0, -0.15)},
        "motion": {"kind": "shuttle", "from": (-1.75, 0, 0), "arc": 1.0},
    },
    "ohne": {
        # „Der Mann geht ohne den Hund spazieren." — the man walks off, the dog stays.
        # The dog is the object of ohne and wears the case color. The arrow belongs to the
        # *figure* (it is the one leaving), hence the base override — hung on the dog it
        # would say the dog is going somewhere, which is exactly what ohne denies.
        # Die Figur strides away in geh, facing where it is going.
        "governs": "akkusativ",
        "ref": ("figur", {"at": (0.95, 0, -0.75), "pose": "steh", "yaw": -90}),
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": 172},
        "dat": {"subject": (-1.55, 0, -0.75), "arrow": "right", "arrow_base": (1.8, 0, -0.1)},
        "motion": {"kind": "abandon", "delta": (1.1, 0, 0)},
        "ambient": [
            {"prim": "figur_leg_l", "op": "swing_x", "amplitude": 20, "period": 0.9},
            {"prim": "figur_leg_r", "op": "swing_x", "amplitude": 20, "period": 0.9, "phase": 0.5},
            {"prim": "figur_arm_l", "op": "swing_x", "amplitude": 15, "period": 0.9, "phase": 0.5},
            {"prim": "figur_arm_r", "op": "swing_x", "amplitude": 15, "period": 0.9},
        ],
    },
    "außer": {
        # „Alle Bälle sind da außer einem." — a cluster of like balls, and the subject
        # plucked out of it and set apart. The loop plucks it again and again — always the
        # one left out. Die Figur presents the cluster from its mark.
        "governs": "dativ",
        "ref": [
            ("cluster", {"at": [(1.02, 0.34), (1.85, 0.24), (1.38, -0.44)], "z": -0.33, "r": 0.42}),
            demonstrator(),
        ],
        "dat": {"subject": (-0.95, 0, -0.2)},
        # from = nestled in the cluster's gap; the arc is the pluck.
        "motion": {"kind": "shuttle", "from": (2.3, 0, -0.12), "arc": 1.0},
    },
    "seit": {
        # „Der Mann wartet seit einer Stunde." — the man waits, the street clock's hand
        # keeps turning. The hand is the set's one baked clip (rotation is beyond the
        # runtime's translate-only choreography); it also spins on the question side,
        # which is safe because a turning clock answers nothing. The clock is the
        # subject — the time phrase is what wears the dative color.
        "governs": "dativ",
        "ref": ("figur", {"at": (-1.15, 0, -0.75), "pose": "steh", "yaw": -55}),
        "subject_build": "uhr",
        "dat": {"subject": (1.05, 0, -0.75)},
        "motion": {"kind": "idle"},
        "ambient": [{"prim": "uhr_zeiger", "op": "rotate_y", "period": 6.0}],
    },
    "während": {
        "governs": "genitiv",
        # One thing inside another's span: the ball travels within the slab's extent and never
        # leaves it — "during" as containment in time.
        "ref": [
            ("slab", {"size": (3.5, 1.3, 0.26), "at": (0, 0, -0.5)}),
            demonstrator(ground=-0.63),
        ],
        "dat": {"subject": (1.15, 0, 0.2)},
        "motion": {"kind": "shuttle", "from": (-2.3, 0, 0), "dur": 2.4},
    },
    "trotz": {
        "governs": "genitiv",
        # An obstacle cleared and carried on past — proceeding regardless is the meaning.
        "ref": [
            ("wall", {"size": (0.3, 2.0, 1.3), "at": (-0.35, 0, 0.05)}),
            demonstrator(ground=-0.75),
        ],
        "dat": {"subject": (1.25, 0, -0.2), "arrow": "right"},
        "motion": {"kind": "shuttle", "from": (-2.55, 0, 0), "arc": 1.9},
    },
    "wegen": {
        # „Wegen des Hügels rollt der Ball hinunter." — cause as visible physics (Kyle's
        # call, 2026-08-12, replacing the shove-block): the ball starts on the slope and
        # comes down BECAUSE of the hill. The straight shuttle chord from the slope's top
        # stays above the wedge face (convex), so nothing clips.
        "governs": "genitiv",
        "ref": [
            ("huegel", {"size": (2.0, 1.2, 1.35), "at": (-1.7, 0, -0.75)}),
            demonstrator(ground=-0.75, side=+1, depth=1.05),
        ],
        "dat": {"subject": (0.7, 0, -0.2)},
        "motion": {"kind": "shuttle", "from": (-3.0, 0, 0.8), "dur": 1.5},
    },
    "statt": {
        "governs": "genitiv",
        # Substitution as a scene: the pedestal is the role, the displaced block is what held
        # it, the ball takes its place. The first Genitiv-slate subject in the set.
        "ref": [
            ("pedestal", {"size": (1.7, 1.3, 0.26), "at": (-0.5, 0, 0.0),
                          "out": (0.72, 0.72, 0.72), "out_at": (1.45, 0, 0.36)}),
            demonstrator(ground=-0.75, depth=0.6),
        ],
        "dat": {"subject": (-0.5, 0, 0.68), "arrow": "right", "arrow_base": (1.45, 0, 1.15)},
        # The ball arcs in as the block slides out — one beat, a swap.
        "motion": {"kind": "swap", "from": (-1.7, 0, 0), "arc": 0.8,
                   "delta": (0.85, 0, 0), "movers": "swapout"},
    },

    # MARK: Formal Genitiv locatives (Settings ▸ include formal)
    #
    # Regions, not journeys — but regions with life in them since the 2026-08-12 rework:
    # the ball roams its region (small orbit or slow patrol) instead of parking, which is
    # what separates "where something is" from a still. What separates them from
    # in/aus/über/unter is still the absence of an *event*: nothing enters, exits or lands.

    "innerhalb": {
        # „Der Ball rollt innerhalb der Kiste." — roams the inside, never leaves.
        "governs": "genitiv",
        "ref": [
            ("openbox", {"size": (2.6, 1.7, 1.3), "at": (0, 0, 0.0)}),
            demonstrator(ground=-0.65),
        ],
        "dat": {"subject": (0.5, 0, 0.0)},
        "motion": {"kind": "orbit", "center": (-0.5, 0, 0)},
    },
    "außerhalb": {
        # „Der Ball rollt außerhalb der Kiste." — roams a patch outside; no arrow and no
        # exit motion, which is what keeps it from collapsing into `aus`. The box's flaps
        # own the upstage-left, so the Mann watches from downstage-left (aus's solution).
        "governs": "genitiv",
        "ref": [
            ("openbox", {"size": (1.9, 1.4, 1.3), "at": (-1.05, 0, 0.0)}),
            demonstrator(ground=-0.65, depth=-1.0),
        ],
        "dat": {"subject": (1.5, 0, -0.1)},
        "motion": {"kind": "orbit", "center": (-0.55, 0, 0)},
    },
    "oberhalb": {
        # „Der Ball schwebt oberhalb des Blocks." — a slow patrol above the slab.
        "governs": "genitiv",
        "ref": [
            ("slab", {"size": (2.6, 1.5, 0.3), "at": (0, 0, -0.65)}),
            demonstrator(ground=-0.8),
        ],
        "dat": {"subject": (0.7, 0, 1.05)},
        "motion": {"kind": "shuttle", "from": (-1.4, 0, 0), "dur": 2.6},
    },
    "unterhalb": {
        # „Der Ball rollt unterhalb des Blocks." — the same patrol, under the floating slab.
        "governs": "genitiv",
        "ref": [
            ("slab", {"size": (2.6, 1.5, 0.3), "at": (0, 0, 1.15)}),
            demonstrator(ground=-1.1),
        ],
        "dat": {"subject": (0.7, 0, -0.55)},
        "motion": {"kind": "shuttle", "from": (-1.4, 0, 0), "dur": 2.6},
    },
    "diesseits": {
        # „Diesseits des Flusses sitzt der Hund." — a band across the frame reads as a
        # river at this camera. The Hund on the viewer's side, the Mann beside him: for
        # dies-/jenseits the Figur MUST share the near bank — its side is the meaning —
        # so no demonstrator mark here.
        "governs": "genitiv",
        "ref": [
            ("slab", {"size": (3.6, 0.8, 0.2), "at": (0, 0.45, -0.68)}),
            ("figur", {"at": (-1.95, -0.85, -0.9), "pose": "steh", "yaw": -55}),
        ],
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": 0},
        "dat": {"subject": (0.35, -1.05, -0.9)},
        "motion": {"kind": "shuttle", "from": (-1.3, 0, 0), "dur": 2.8},
    },
    "jenseits": {
        # „Jenseits des Flusses sitzt der Hund." — the same river, the Hund on the far
        # bank (clipped by the band — hinter's occlusion trick), the Mann on the near one
        # looking across. The gap between them IS the word.
        "governs": "genitiv",
        "ref": [
            ("slab", {"size": (3.6, 0.8, 0.2), "at": (0, 0.45, -0.68)}),
            ("figur", {"at": (-2.0, -1.0, -0.9), "pose": "steh", "yaw": -35}),
        ],
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": 25},
        "dat": {"subject": (-0.15, 1.6, -0.85)},
        "motion": {"kind": "shuttle", "from": (1.2, 0, 0), "dur": 2.8},
    },
    "beiderseits": {
        # „Beiderseits des Zauns stehen der Mann und der Hund." — the set's last word to
        # get a scene at all. The fence divides near from far; the Mann stands behind it
        # (head and torso above the rails), the Hund sits in front. Nothing travels —
        # being on both sides is the whole meaning.
        "governs": "genitiv",
        "ref": [
            ("fence", {"at": (0, 0.35, -0.75), "length": 3.4, "height": 1.1}),
            ("figur", {"at": (-0.9, 1.5, -0.75), "pose": "steh", "yaw": -25}),
        ],
        "subject_mesh": {"file": "hund", "height": 0.95, "yaw": -15},
        "dat": {"subject": (0.85, -0.8, -0.75)},
        "motion": {"kind": "idle"},
    },
}

STATE_COLOR = {
    "akk": PALETTE["akkusativ"],
    "dat": PALETTE["dativ"],
    # The question side: relation shown, case withheld.
    "neutral": PALETTE["neutral"],
}


def subject_color(relation, state):
    """A two-way preposition takes the color of the case it is currently in; a fixed-case one
    always takes its own, whichever resolved state was asked for."""
    if state == "neutral":
        return PALETTE["neutral"]
    if governs := relation.get("governs"):
        return PALETTE[governs]
    return STATE_COLOR[state]


# MARK: - Scene construction


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name: str, hex_value: int, look: str):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")

    if look == "flat":
        # Emission at strength 1 renders the literal color with no lighting response.
        shader = nodes.new("ShaderNodeEmission")
        shader.inputs["Color"].default_value = rgba(hex_value)
        shader.inputs["Strength"].default_value = 1.0
    else:
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        shader.inputs["Base Color"].default_value = rgba(hex_value)
        shader.inputs["Roughness"].default_value = 0.62
        if "Specular IOR Level" in shader.inputs:
            shader.inputs["Specular IOR Level"].default_value = 0.25

    links.new(shader.outputs[0], out.inputs["Surface"])
    return mat


# Render quality vs. shipped-geometry size: a 96×48 sphere is right for a still, but it makes
# a 427 KB USDZ. At 32×16 the silhouette is identical on screen and the file is 49 KB.
SPHERE_LOD = {"high": (96, 48), "low": (32, 16)}
_LOD = "high"


def add_sphere(location, mat):
    segments, rings = SPHERE_LOD[_LOD]
    bpy.ops.mesh.primitive_uv_sphere_add(radius=SPHERE_R, segments=segments, ring_count=rings,
                                         location=location)
    obj = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    obj.name = "subject"
    return obj


def add_box(size, at, mat, name="reference"):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    obj = bpy.context.active_object
    obj.scale = Vector(size)
    obj.data.materials.append(mat)
    obj.name = name
    return obj


def build_reference(kind, spec, mat):
    """The neutral form the subject is positioned against."""
    if kind == "slab":
        return [add_box(spec["size"], spec["at"], mat)]

    if kind == "twobars":
        w, d, h = spec["size"]
        gap = spec["gap"]
        x, y, z = spec["at"]
        return [
            add_box((w, d, h), (x - gap / 2 - w / 2, y, z), mat, "reference.l"),
            add_box((w, d, h), (x + gap / 2 + w / 2, y, z), mat, "reference.r"),
        ]

    if kind == "openbox":
        # Three slabs: floor + two walls, open at the top so the subject can drop in.
        w, d, h = spec["size"]
        x, y, z = spec["at"]
        t = 0.26
        parts = [
            add_box((w, d, t), (x, y, z - h / 2), mat, "reference.floor"),
            add_box((t, d, h), (x - w / 2 + t / 2, y, z), mat, "reference.wl"),
            add_box((t, d, h), (x + w / 2 - t / 2, y, z), mat, "reference.wr"),
        ]
        if spec.get("flaps"):
            # Outward-tilted flaps on the wall tops: the cardboard-box read, no texture needed.
            fl = 0.6
            for sign, name in ((-1, "reference.flapl"), (1, "reference.flapr")):
                wall_x = x + sign * (w / 2 - t / 2)
                flap = add_box((fl, d * 0.94, t * 0.7),
                               (wall_x + sign * fl * 0.36, y, z + h / 2 + fl * 0.22),
                               mat, name)
                flap.rotation_euler = (0, sign * math.radians(-52), 0)
                parts.append(flap)
        return parts

    if kind == "cluster":
        # A group of like balls, slightly smaller than the subject — außer's "alle".
        r = spec.get("r", 0.42)
        z = spec.get("z", -0.33)
        parts = []
        for i, (x, y) in enumerate(spec["at"]):
            segments, rings = SPHERE_LOD[_LOD]
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=segments, ring_count=rings,
                                                 location=(x, y, z))
            obj = bpy.context.active_object
            bpy.ops.object.shade_smooth()
            obj.data.materials.append(mat)
            obj.name = f"reference.member{i}"
            parts.append(obj)
        return parts

    if kind == "table":
        # A top plus four legs. Worth the extra geometry over a floating slab: `auf`, `unter`
        # and `neben` all ship "…dem Tisch" example sentences, so the picture and the German
        # reinforce each other instead of running on separate tracks.
        w, d, h = spec["size"]
        x, y, z = spec["at"]
        top_t, leg = 0.22, 0.17
        parts = [add_box((w, d, top_t), (x, y, z), mat, "reference.top")]
        for i, (dx, dy) in enumerate([(-1, -1), (1, -1), (-1, 1), (1, 1)]):
            parts.append(add_box(
                (leg, leg, h),
                (x + dx * (w / 2 - leg), y + dy * (d / 2 - leg), z - top_t / 2 - h / 2),
                mat, f"reference.leg{i}",
            ))
        return parts

    if kind == "wall":
        # A standing plane on a base, for the prepositions that push against a vertical
        # boundary — an, vor, hinter, gegen.
        w, d, h = spec["size"]
        x, y, z = spec["at"]
        return [
            add_box((w, d, h), (x, y, z), mat, "reference.wall"),
            add_box((w * 1.15, d * 2.6, 0.16), (x, y, z - h / 2), mat, "reference.base"),
        ]

    if kind == "figure":
        # Capsule body + sphere head. The fixed-case prepositions are person-shaped ideas —
        # "mit dem Bus", "bei meinen Eltern" — and a ball cannot say "person".
        return _figure(spec["at"], spec.get("scale", 1.0), mat)

    if kind == "pair":
        # Two figures facing each other across the frame — für's giver and receiver.
        scale = spec.get("scale", 1.0)
        return (_figure(spec["a"], scale, mat, prefix="reference.a")
                + _figure(spec["b"], scale, mat, prefix="reference.b"))

    if kind == "pedestal":
        # statt's stage: the platform is the role, the block beside it the thing displaced
        # from it. The block is named `swapout` — no dots, because USD prim names mangle
        # them — so the runtime can slide exactly it and nothing else.
        w, d, t = spec["size"]
        x, y, z = spec["at"]
        return [
            add_box((w, d, t), (x, y, z), mat, "reference.base"),
            add_box(spec["out"], spec["out_at"], mat, "swapout"),
        ]

    if kind == "ground":
        # Wide enough to bleed past the ortho frame on both sides, so it reads as an open plane
        # rather than a slab the ball is standing on the end of.
        w, d, h = spec.get("size", (7.6, 2.2, 0.28))
        x, y, z = spec["at"]
        return [add_box((w, d, h), (x, y, z - h / 2), mat, "reference.ground")]

    if kind == "portal":
        # A wall with a hole punched through it: four boxes framing an opening. `durch` is the
        # one relation where the subject has to be *inside* the reference, not against it.
        w, d, h = spec["size"]
        x, y, z = spec["at"]
        ow, oh = spec.get("opening", (1.3, 1.3))
        side = (w - ow) / 2
        cap = (h - oh) / 2
        return [
            add_box((side, d, h), (x - ow / 2 - side / 2, y, z), mat, "reference.pl"),
            add_box((side, d, h), (x + ow / 2 + side / 2, y, z), mat, "reference.pr"),
            add_box((ow, d, cap), (x, y, z + oh / 2 + cap / 2), mat, "reference.ptop"),
            add_box((ow, d, cap), (x, y, z - oh / 2 - cap / 2), mat, "reference.pbot"),
        ]

    if kind == "ring":
        # Dashes in a circle around a central block — the only honest way to draw "around"
        # in one frame, since a single arrow can only ever point one way.
        radius = spec.get("radius", 1.5)
        count = spec.get("count", 12)
        x, y, z = spec["at"]
        parts = [add_box(spec.get("core", (0.9, 0.9, 1.0)), (x, y, z), mat, "reference.core")]
        for i in range(count):
            angle = 2 * math.pi * i / count
            box = add_box((0.26, 0.26, 0.1),
                          (x + radius * math.cos(angle), y + radius * math.sin(angle), z - 0.5),
                          mat, f"reference.ring{i}")
            box.rotation_euler = (0, 0, angle)
            parts.append(box)
        return parts

    if kind == "goal":
        # A path that stops at something: the shared shape behind bis / nach / zu, where the
        # point is the destination rather than the journey.
        length = spec.get("length", 3.2)
        count = spec.get("count", 6)
        x, y, z = spec["at"]
        dash = length / (count * 2 - 1)
        parts = []
        for i in range(count):
            parts.append(add_box(
                (dash, 0.34, 0.1),
                (x - length / 2 + dash / 2 + i * dash * 2, y, z),
                mat, f"reference.dash{i}",
            ))
        parts.append(add_box((0.3, 1.1, 1.5), (x + length / 2 + 0.5, y, z + 0.7),
                             mat, "reference.goal"))
        return parts

    if kind == "path":
        # A dashed trajectory, for the words that are about travel rather than position —
        # entlang, durch, bis, nach, von, zu.
        length = spec.get("length", 3.4)
        count = spec.get("count", 7)
        x, y, z = spec["at"]
        dash = length / (count * 2 - 1)
        parts = []
        for i in range(count):
            parts.append(add_box(
                (dash, 0.34, 0.1),
                (x - length / 2 + dash / 2 + i * dash * 2, y, z),
                mat, f"reference.dash{i}",
            ))
        return parts

    # MARK: Cast references (see tools/genprops/PROPS_PLAN.md)

    if kind == "fence":
        # Posts + two rails. bis stops at it, trotz hops it, entlang runs along it,
        # innerhalb rings it.
        length = spec.get("length", 3.4)
        height = spec.get("height", 1.1)
        count = spec.get("count", 5)
        x, y, z = spec["at"]
        parts = []
        for i in range(count):
            px = x - length / 2 + i * (length / (count - 1))
            parts.append(add_box((0.14, 0.14, height), (px, y, z + height / 2),
                                 mat, f"reference.post{i}"))
        for j, rz in enumerate((0.38, 0.78)):
            parts.append(add_box((length, 0.1, 0.14), (x, y, z + rz * height),
                                 mat, f"reference.rail{j}"))
        return parts

    if kind == "hoop":
        # A standing torus on a base — durch's circus hoop.
        radius = spec.get("radius", 1.15)
        x, y, z = spec["at"]
        bpy.ops.mesh.primitive_torus_add(
            location=(x, y, z + radius + 0.25), rotation=(0, math.radians(90), 0),
            major_radius=radius, minor_radius=0.09,
            major_segments=48, minor_segments=12,
        )
        ring = bpy.context.active_object
        ring.data.materials.append(mat)
        ring.name = "reference.hoop"
        bpy.ops.object.shade_smooth()
        base = add_box((0.5, 0.7, 0.25), (x, y, z + 0.125), mat, "reference.hoopbase")
        return [ring, base]

    if kind == "doorframe":
        # A door standing in its frame, ajar — vor's waiting spot. The slab is named
        # doorslab so a runtime hinge can swing exactly it later.
        w, h = spec.get("opening", (1.1, 1.9))
        x, y, z = spec["at"]
        t = 0.18
        parts = [
            add_box((t, 0.3, h), (x - w / 2 - t / 2, y, z + h / 2), mat, "reference.jambl"),
            add_box((t, 0.3, h), (x + w / 2 + t / 2, y, z + h / 2), mat, "reference.jambr"),
            add_box((w + 2 * t, 0.3, t), (x, y, z + h + t / 2), mat, "reference.lintel"),
        ]
        # The slab's origin sits on its hinge edge (mesh shifted half a unit, pre-scale), so
        # both this authored ajar pose and any future runtime hinge swing about the jamb —
        # a door rotating around its own center reads as a revolving panel, not a door.
        door = add_box((w * 0.96, 0.08, h * 0.98), (x - w / 2, y, z + h / 2), mat, "doorslab")
        door.data.transform(Matrix.Translation((0.5, 0, 0)))
        door.rotation_euler = (0, 0, math.radians(spec.get("ajar", 38)))
        parts.append(door)
        return parts

    if kind == "shelf":
        # A wall with a jutting shelf board — oberhalb's perch.
        x, y, z = spec["at"]
        return [
            add_box((0.26, 1.8, 2.6), (x, y, z + 1.3), mat, "reference.shelfwall"),
            add_box((1.35, 1.1, 0.14), (x + 0.65, y, z + spec.get("height", 1.7)),
                    mat, "reference.board"),
        ]

    if kind == "windowwall":
        # A wall with a window opening high up — unterhalb sleeps beneath it. The portal
        # geometry, hoisted.
        w, d, h = spec.get("size", (2.8, 0.3, 2.6))
        ow, oh = spec.get("opening", (1.1, 0.95))
        oz = spec.get("sill", 1.35)   # opening bottom, above the wall base
        x, y, z = spec["at"]
        side = (w - ow) / 2
        return [
            add_box((side, d, h), (x - ow / 2 - side / 2, y, z + h / 2), mat, "reference.wwl"),
            add_box((side, d, h), (x + ow / 2 + side / 2, y, z + h / 2), mat, "reference.wwr"),
            add_box((ow, d, oz), (x, y, z + oz / 2), mat, "reference.wwsill"),
            add_box((ow, d, h - oz - oh), (x, y, z + oz + oh + (h - oz - oh) / 2),
                    mat, "reference.wwtop"),
        ]

    if kind == "tree":
        # Foliage ball on a trunk — the Baum the generator couldn't draw (both seeds failed;
        # see PROPS_PLAN.md). um orbits it, hinter hides behind it, beiderseits plants two.
        x, y, z = spec["at"]
        scale = spec.get("scale", 1.0)
        trunk_h = 0.9 * scale
        bpy.ops.mesh.primitive_cylinder_add(radius=0.16 * scale, depth=trunk_h,
                                            location=(x, y, z + trunk_h / 2))
        trunk = bpy.context.active_object
        trunk.data.materials.append(mat)
        trunk.name = "reference.trunk"
        bpy.ops.object.shade_smooth()
        segments, rings = SPHERE_LOD[_LOD]
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.72 * scale, segments=segments,
                                             ring_count=rings,
                                             location=(x, y, z + trunk_h + 0.5 * scale))
        crown = bpy.context.active_object
        crown.data.materials.append(mat)
        crown.name = "reference.crown"
        bpy.ops.object.shade_smooth()
        return [trunk, crown]

    if kind == "mesh":
        # A converted prop from tools/genprops/samples, placed like any primitive. This is
        # how the story cast (hund, katze, sofa, hütte…) enters a scene as a *reference*;
        # subject-role props are a separate concern (they must stay tintable).
        import os
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "genprops", "samples", spec["file"] + ".usdz")
        before = set(bpy.context.scene.objects)
        bpy.ops.wm.usd_import(filepath=os.path.normpath(path))
        # Older sample USDZs carry their judge camera + suns; drop them or they pollute the
        # scene's lighting and pile up in the export.
        for stray in [o for o in bpy.context.scene.objects
                      if o not in before and o.type in ("CAMERA", "LIGHT")]:
            bpy.data.objects.remove(stray, do_unlink=True)
        imported = [o for o in bpy.context.scene.objects
                    if o not in before and o.type == "MESH"]
        if not imported:
            raise ValueError(f"mesh kind: nothing imported from {path}")
        bpy.ops.object.select_all(action="DESELECT")
        for o in imported:
            o.select_set(True)
        bpy.context.view_layer.objects.active = imported[0]
        if len(imported) > 1:
            bpy.ops.object.join()
        prop = bpy.context.view_layer.objects.active
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

        # Scale to the requested height, face the requested way, stand at `at`.
        corners = [prop.matrix_world @ Vector(c) for c in prop.bound_box]
        zmin = min(v.z for v in corners)
        h = max(v.z for v in corners) - zmin
        s = spec.get("height", 1.4) / h if h > 0 else 1.0
        prop.scale = (s,) * 3
        bpy.ops.object.transform_apply(scale=True)
        prop.rotation_euler = (0, 0, math.radians(spec.get("yaw", 0)))
        bpy.ops.object.transform_apply(rotation=True)
        corners = [prop.matrix_world @ Vector(c) for c in prop.bound_box]
        center = sum(corners, Vector()) / 8
        x, y, z = spec["at"]
        prop.location += Vector((x - center.x, y - center.y,
                                 z - min(v.z for v in corners)))
        bpy.ops.object.transform_apply(location=True)

        # Reference role: retint to the scene's charcoal so imported and primitive props
        # are indistinguishable in the palette.
        prop.data.materials.clear()
        prop.data.materials.append(mat)
        prop.name = f"reference.{spec['file']}"
        return [prop]

    if kind == "figur":
        # Die Figur — the Bauhaus figure (figur.py), posed and placed under ONE parent
        # Xform named `figur`. The runtime's piece walk sees a single unit to fly in, and
        # `movers: "figur"` translates the parent — which leaves the six children free to
        # carry baked walk-cycle clips (mit/ohne) without fighting the runtime: the prim
        # the clip rotates and the prim the choreography translates differ by construction.
        # (Changed from flat parts 2026-08-12 to unlock the walk; the standalone figur.usdz
        # for FigurSceneView stays flat — its contract is figur.py's.)
        figur._LOD = _LOD                     # dense for stills, light for the shipped USDZ
        parts, p = figur.build_figure(spec.get("preset", "standard"),
                                      spec.get("height", FIGUR_HEIGHT), mat=mat)
        figur.apply_pose(parts, p, spec.get("pose", "steh"))
        bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
        group = bpy.context.active_object
        group.name = "figur"
        for part in parts:
            part.parent = group
        group.rotation_euler = (0, 0, math.radians(spec.get("yaw", 0.0)))
        group.location = Vector(spec["at"])
        return [group]

    if kind == "frame":
        # A thin picture frame — kept as a *reference* variant; an's tintable subject is
        # the joined `add_subject_bild` below.
        w, h = spec.get("size", (1.0, 0.8))
        x, y, z = spec["at"]
        t = 0.1
        return [
            add_box((w, 0.08, t), (x, y, z - h / 2 + t / 2), mat, "reference.fb"),
            add_box((w, 0.08, t), (x, y, z + h / 2 - t / 2), mat, "reference.ft"),
            add_box((t, 0.08, h - 2 * t), (x - w / 2 + t / 2, y, z), mat, "reference.fl"),
            add_box((t, 0.08, h - 2 * t), (x + w / 2 - t / 2, y, z), mat, "reference.fr"),
        ]

    if kind == "huegel":
        # A wedge ramp — cause as visible physics: wegen's ball is up there, and the hill
        # is why it comes down. Tall face on the left, slope descending to +X; built from
        # explicit vertices because none of the primitives make a right wedge cleanly.
        w, d, h = spec.get("size", (2.0, 1.2, 1.35))
        x, y, z = spec["at"]
        verts = [(x - w / 2, y - d / 2, z), (x + w / 2, y - d / 2, z),
                 (x - w / 2, y - d / 2, z + h),
                 (x - w / 2, y + d / 2, z), (x + w / 2, y + d / 2, z),
                 (x - w / 2, y + d / 2, z + h)]
        faces = [(0, 1, 2), (3, 5, 4), (0, 2, 5, 3), (0, 3, 4, 1), (1, 4, 5, 2)]
        mesh = bpy.data.meshes.new("reference.huegel")
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        obj = bpy.data.objects.new("reference.huegel", mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(mat)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        return [obj]

    raise ValueError(f"unknown reference kind: {kind}")


# MARK: - Built subjects
#
# Subjects that are neither the sphere nor an imported prop: primitive constructions that
# must end up as ONE mesh named `subject`, because the runtime tints and travels exactly one
# prim. Each takes (at, mat, ref_mat) — the second material is for parts that stay charcoal.


def _join_as_subject(parts, origin):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    subject = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.scene.cursor.location = Vector(origin)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)
    subject.name = "subject"
    subject.data.name = "subject"
    return subject


def add_subject_uhr(at, mat, ref_mat):
    """Die Standuhr — seit's subject. A street clock: pole and face joined into one teal
    mesh, the hand parented *under* it as `uhr_zeiger`. A child of the subject rides the
    idle bob and is exempt from the runtime's fly-in piece walk; it keeps the reference
    charcoal (the tint touches only the subject mesh), and `bake_ambient` spins it about
    the face normal — the one baked clip in the set."""
    x, y, z = at
    pole_h, face_r, face_t = 1.35, 0.62, 0.16
    centre = (x, y, z + pole_h + face_r * 0.85)

    bpy.ops.mesh.primitive_cylinder_add(radius=0.07, depth=pole_h,
                                        location=(x, y, z + pole_h / 2))
    pole = bpy.context.active_object
    pole.data.materials.append(mat)
    bpy.ops.mesh.primitive_cylinder_add(radius=face_r, depth=face_t, location=centre,
                                        rotation=(math.radians(90), 0, 0))
    face = bpy.context.active_object
    face.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    subject = _join_as_subject([face, pole], (x, y, z))

    # The hand: pivot exactly at the face centre, blade reaching up. Slightly proud of the
    # face toward the camera so it never z-fights.
    bpy.ops.mesh.primitive_cube_add(
        size=1.0, location=(centre[0], centre[1] - face_t * 0.75, centre[2] + 0.2))
    hand = bpy.context.active_object
    hand.scale = Vector((0.07, 0.05, 0.44))
    hand.data.materials.append(ref_mat)
    bpy.ops.object.transform_apply(scale=True)
    bpy.context.scene.cursor.location = Vector((centre[0], centre[1] - face_t * 0.75, centre[2]))
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = (0, 0, 0)
    hand.name = "uhr_zeiger"
    hand.data.name = "uhr_zeiger"
    hand.parent = subject
    hand.matrix_parent_inverse = subject.matrix_world.inverted()
    return subject


def add_subject_bild(at, mat, ref_mat=None):
    """Das Bild — an's subject. The picture frame joined into one tintable mesh; four loose
    frame sides would leave three behind when the runtime travels the subject to the wall.
    Thin in x, because it hangs on an `an`-style wall (whose face is a y–z plane).
    `at` is the frame's centre."""
    w, h, t, d = 1.05, 0.8, 0.1, 0.09
    x, y, z = at
    parts = [
        add_box((d, w, t), (x, y, z - (h - t) / 2), mat, "subject"),
        add_box((d, w, t), (x, y, z + (h - t) / 2), mat, "subject"),
        add_box((d, t, h - 2 * t), (x, y - (w - t) / 2, z), mat, "subject"),
        add_box((d, t, h - 2 * t), (x, y + (w - t) / 2, z), mat, "subject"),
    ]
    return _join_as_subject(parts, (x, y, z))


SUBJECT_BUILDERS = {"uhr": add_subject_uhr, "bild": add_subject_bild}


# Canned specs for `--refprobe`: each new kind rendered with a resting ball, so a reference
# can be judged in isolation before any relation is authored against it.
REF_PROBES = {
    "fence": ({"at": (0, 0, -0.75), "length": 3.4, "height": 1.1}, (1.4, 0, -0.2)),
    "hoop": ({"at": (0, 0, -0.75), "radius": 1.15}, (1.9, 0, -0.2)),
    "doorframe": ({"at": (-0.4, 0, -0.75)}, (1.3, 0, -0.2)),
    "shelf": ({"at": (-1.1, 0, -0.75), "height": 1.7}, (0.6, 0, -0.2)),
    "windowwall": ({"at": (-0.3, 0, -0.75)}, (1.5, 0, -0.2)),
    "frame": ({"at": (0, 0, 0.75)}, (1.6, 0, -0.2)),
    "tree": ({"at": (-0.6, 0, -0.75), "scale": 1.1}, (1.3, 0, -0.2)),
    # The imported-prop path, exercised with the doghouse (aus/nach's reference).
    "mesh": ({"file": "huette", "at": (-0.8, 0, -0.75), "height": 1.5, "yaw": 0},
             (1.4, 0, -0.2)),
    # Die Figur at the demonstrator's mark, pointing at the resting ball.
    "figur": ({"at": FIGUR_MARK, "height": FIGUR_HEIGHT, "pose": "zeig", "yaw": 24},
              (0.9, 0, -0.2)),
}


def _figure(at, scale, mat, prefix="reference"):
    """One standing figure: capsule body + sphere head, named under `prefix`."""
    x, y, z = at
    body_h = 1.15 * scale
    bpy.ops.mesh.primitive_cylinder_add(radius=0.3 * scale, depth=body_h,
                                        location=(x, y, z + body_h / 2))
    body = bpy.context.active_object
    body.data.materials.append(mat)
    body.name = f"{prefix}.body"
    bpy.ops.object.shade_smooth()

    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.29 * scale, segments=48, ring_count=24,
                                         location=(x, y, z + body_h + 0.22 * scale))
    head = bpy.context.active_object
    head.data.materials.append(mat)
    head.name = f"{prefix}.head"
    bpy.ops.object.shade_smooth()
    return [body, head]


def add_ghost(location, mat_hex, look):
    """A faint copy of the subject at its starting pose, so a *still* can imply motion without
    an arrow. Only used on the Akkusativ stills."""
    ghost_mat = make_material("ghost", mat_hex, look)
    node = ghost_mat.node_tree.nodes["Emission" if look == "flat" else "Principled BSDF"]
    color = list(node.inputs[0].default_value)
    color[3] = 1.0
    node.inputs[0].default_value = color
    if "Alpha" in node.inputs:
        node.inputs["Alpha"].default_value = 0.22
    ghost_mat.blend_method = "BLEND" if hasattr(ghost_mat, "blend_method") else ghost_mat.blend_method

    segments, rings = SPHERE_LOD[_LOD]
    bpy.ops.mesh.primitive_uv_sphere_add(radius=SPHERE_R * 0.94, segments=segments,
                                         ring_count=rings, location=location)
    obj = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(ghost_mat)
    obj.name = "ghost"
    return obj


def add_arrow(direction, subject_at, mat, base_override=None):
    """A slim motion arrow, only ever drawn in the Akkusativ (moving) state.

    Offset to the side of the subject rather than under it: an arrow directly beneath the
    sphere reads as a stem, turning the whole pictogram into a lollipop.

    `base_override` pins the shaft's center to an absolute position instead of hanging it off
    the subject — for the scenes where the arrow belongs to someone else (ohne's departing
    figure) or to the space between two things (für's giver → receiver).
    """
    shaft_len, head_len, head_r = 0.78, 0.34, 0.21
    sx, sy, sz = subject_at

    # Direction vector plus where to hang the arrow relative to the subject. vor/hinter travel
    # along the view axis, so their arrows are swung ~35° off it — a pure -Y arrow foreshortens
    # to a stub against this camera and reads as a lollipop rather than a direction.
    presets = {
        "down":   (Vector((0, 0, -1)),           Vector((-1.15, 0, -0.30))),
        "right":  (Vector((1, 0, 0)),            Vector((0.95, 0, 0))),
        "left":   (Vector((-1, 0, 0)),           Vector((-0.95, 0, 0))),
        "toward": (Vector((-0.58, -0.82, 0)),    Vector((0.92, -0.18, 0.10))),
        "away":   (Vector((0.58, 0.82, 0)),      Vector((-0.92, 0.18, 0.10))),
    }
    axis, offset = presets[direction]
    axis = axis.normalized()
    base = Vector(base_override) if base_override else Vector((sx, sy, sz)) + offset
    rot = axis.to_track_quat("Z", "Y").to_euler()

    bpy.ops.mesh.primitive_cylinder_add(radius=0.075, depth=shaft_len, location=base,
                                        rotation=rot)
    shaft = bpy.context.active_object
    shaft.data.materials.append(mat)

    head_at = base + axis * (shaft_len / 2 + head_len / 2)
    bpy.ops.mesh.primitive_cone_add(radius1=head_r, depth=head_len, location=head_at,
                                    rotation=rot)
    head = bpy.context.active_object
    head.data.materials.append(mat)
    return [shaft, head]


def setup_camera(look):
    """`flat` reads as a diagram, so it stays dead-on. `dim` is a scene, so it gets a raked
    three-quarter view — without it the slab's top face is perpendicular to the camera and no
    amount of lighting can reveal an edge that isn't pointed at the lens.

    Still orthographic in both: perspective would taper the reference forms and make the same
    relation look different depending on where it sat in frame.
    """
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 5.7 if look == "dim" else 4.6
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)

    target = Vector((0, 0, 0.45))
    if look == "flat":
        cam.location = (0, -10, 0.55)
        cam.rotation_euler = (math.pi / 2, 0, 0)
    else:
        azimuth, elevation, distance = math.radians(21), math.radians(17), 11.0
        cam.location = (
            distance * math.sin(azimuth) * math.cos(elevation),
            -distance * math.cos(azimuth) * math.cos(elevation),
            target.z + distance * math.sin(elevation),
        )
        cam.rotation_euler = (Vector(cam.location) - target).to_track_quat("Z", "Y").to_euler()

    bpy.context.scene.camera = cam
    return cam


# Overall light intensity. Contrast should come from the key:rim:fill *ratio*; turning the
# absolute level up instead over-exposes the surfaces and drags every color toward white,
# which is how the charcoal reference first drifted from #33383D to #474D52.
LIGHT_SCALE = 0.55


def setup_lights(look):
    if look == "flat":
        return  # emission shaders need no lights

    # High key-to-fill ratio (~7:1) is where the contrast comes from. A soft, even wash makes
    # everything legible and nothing dramatic.
    key_data = bpy.data.lights.new("key", type="AREA")
    key_data.energy = 2600 * LIGHT_SCALE
    key_data.size = 3.0          # smaller than the old 6 → crisper terminator and shadow edge
    key = bpy.data.objects.new("key", key_data)
    key.location = (-4.6, -4.2, 6.4)
    key.rotation_euler = (math.radians(42), 0, math.radians(-42))
    bpy.context.collection.objects.link(key)

    # Rim from behind-right: this is what draws the bright edge on the sphere and picks the far
    # corner of the slab out of the background.
    rim_data = bpy.data.lights.new("rim", type="AREA")
    rim_data.energy = 1700 * LIGHT_SCALE
    rim_data.size = 1.6
    rim = bpy.data.objects.new("rim", rim_data)
    rim.location = (4.8, 4.4, 2.6)
    rim.rotation_euler = (math.radians(74), 0, math.radians(133))
    bpy.context.collection.objects.link(rim)

    # Just enough fill to keep the shadow side from going to pure black.
    fill_data = bpy.data.lights.new("fill", type="AREA")
    fill_data.energy = 360 * LIGHT_SCALE
    fill_data.size = 9
    fill = bpy.data.objects.new("fill", fill_data)
    fill.location = (4.2, -6.4, 0.6)
    fill.rotation_euler = (math.radians(84), 0, math.radians(36))
    bpy.context.collection.objects.link(fill)


def setup_render(look, size):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    # Alpha instead of a baked background: the app composites these onto whatever theme
    # ground is behind them, light or dark.
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    # Standard, NOT AgX: a film-emulation transform would shift every hex away from the
    # palette, which is the whole reason we left Midjourney.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 256
        # EEVEE's soft shadows are stochastic; at the default ray/step counts the contact
        # shadows inside the open box and between the bars come out visibly blotchy.
        scene.eevee.use_shadows = True
        scene.eevee.shadow_ray_count = 4
        scene.eevee.shadow_step_count = 8
        scene.eevee.shadow_resolution_scale = 2.0


def build(prep, state, look, size, ghost=False):
    clear_scene()
    setup_render(look, size)

    relation = RELATIONS[prep]
    ref_mat = make_material("reference", PALETTE["reference"], look)
    subject_mat = make_material("subject", subject_color(relation, state), look)

    # A relation may stand its subject against several forms (für: a giver AND the dog).
    refs = relation["ref"] if isinstance(relation["ref"], list) else [relation["ref"]]
    for kind, spec in refs:
        build_reference(kind, spec, ref_mat)

    # `neutral` is the question side: the relation resolved, the case withheld. It borrows the
    # resting pose and drops the arrow, because the color *and* any motion cue are exactly what
    # would answer the question being asked. A fixed-case relation has one pose, so both
    # resolved states fall back to it.
    pose = relation["dat"] if state == "neutral" else (relation.get(state) or relation["dat"])
    if mesh_spec := relation.get("subject_mesh"):
        add_subject_mesh(mesh_spec, pose["subject"], subject_mat)
    elif builder := relation.get("subject_build"):
        SUBJECT_BUILDERS[builder](pose["subject"], subject_mat, ref_mat)
    else:
        add_sphere(pose["subject"], subject_mat)
    if pose.get("arrow") and state != "neutral":
        add_arrow(pose["arrow"], pose["subject"], subject_mat,
                  base_override=pose.get("arrow_base"))
    if ghost and state == "akk":
        add_ghost(relation["dat"]["subject"], STATE_COLOR[state], look)

    setup_camera(look)
    setup_lights(look)


def add_subject_mesh(mesh_spec, at, mat):
    """A converted prop as the SUBJECT: named `subject`, wearing the subject material, its
    *base* standing at `at`. The runtime finds it by name exactly like the sphere, so
    tinting and posing carry over unchanged."""
    import os
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "genprops", "samples", mesh_spec["file"] + ".usdz")
    before = set(bpy.context.scene.objects)
    bpy.ops.wm.usd_import(filepath=os.path.normpath(path))
    # Older sample USDZs carry their judge camera + suns; drop them or they pollute the
    # scene's lighting and pile up in the export.
    for stray in [o for o in bpy.context.scene.objects
                  if o not in before and o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(stray, do_unlink=True)
    imported = [o for o in bpy.context.scene.objects if o not in before and o.type == "MESH"]
    if not imported:
        raise ValueError(f"subject_mesh: nothing imported from {path}")
    bpy.ops.object.select_all(action="DESELECT")
    for o in imported:
        o.select_set(True)
    bpy.context.view_layer.objects.active = imported[0]
    if len(imported) > 1:
        bpy.ops.object.join()
    subj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    corners = [subj.matrix_world @ Vector(c) for c in subj.bound_box]
    h = max(v.z for v in corners) - min(v.z for v in corners)
    s = mesh_spec.get("height", 1.3) / h if h > 0 else 1.0
    subj.scale = (s,) * 3
    bpy.ops.object.transform_apply(scale=True)
    subj.rotation_euler = (0, 0, math.radians(mesh_spec.get("yaw", 0)))
    bpy.ops.object.transform_apply(rotation=True)
    corners = [subj.matrix_world @ Vector(c) for c in subj.bound_box]
    center = sum(corners, Vector()) / 8
    x, y, z = at
    subj.location += Vector((x - center.x, y - center.y, z - min(v.z for v in corners)))
    bpy.ops.object.transform_apply(location=True)

    subj.data.materials.clear()
    subj.data.materials.append(mat)
    subj.name = "subject"
    return subj


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_loop(prep, look, size, out_dir):
    """The Wohin→Wo motion: the subject travels from its Akkusativ pose to its Dativ pose.
    Rendered as a frame sequence; ffmpeg turns it into a loop."""
    relation = RELATIONS[prep]
    start = Vector(relation.get("akk", relation["dat"])["subject"])
    end = Vector(relation["dat"]["subject"])

    frames = 24
    for i in range(frames):
        t = i / (frames - 1)
        # Ease-out so it settles rather than slamming down.
        eased = 1 - (1 - t) ** 2.4
        clear_scene()
        setup_render(look, size)
        ref_mat = make_material("reference", PALETTE["reference"], look)
        # Color lerps orange → teal as it comes to rest: the case change made visible.
        blend = tuple(
            a + (b - a) * eased
            for a, b in zip(rgba(PALETTE["akkusativ"]), rgba(PALETTE["dativ"]))
        )
        mat = make_material("subject", PALETTE["dativ"], look)
        node = mat.node_tree.nodes["Emission" if look == "flat" else "Principled BSDF"]
        node.inputs[0].default_value = blend

        kind, spec = relation["ref"]
        build_reference(kind, spec, ref_mat)
        add_sphere(start.lerp(end, eased), mat)
        setup_camera(look)
        setup_lights(look)
        render_to(f"{out_dir}/loop_{i:03d}")


def write_manifest(path):
    """Publish what the app needs to pose the shipped USDZ.

    Each USDZ ships the *resting* (Dativ) pose; the app lifts the subject to the Akkusativ pose
    at runtime, so it needs that delta. Blender is Z-up and the USD export converts to Y-up, so
    the offset is remapped (x, y, z) → (x, z, -y) here rather than in Swift — the rig owns the
    coordinate convention, and Swift shouldn't have to know Blender exists.
    """
    import json

    def remap(v):
        """Blender Z-up vector → app Y-up: (x, y, z) → (x, z, -y)."""
        return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]

    def entry(word, relation, prefix):
        dat = Vector(relation["dat"]["subject"])
        akk = Vector(relation["akk"]["subject"]) if "akk" in relation else dat
        d = akk - dat
        out = {
            "asset": prefix + ascii_name(word),
            "akkOffset": [round(d.x, 4), round(d.z, 4), round(-d.y, 4)],
        }
        # Fixed-case choreography rides along, vectors remapped exactly like akkOffset so
        # Swift never learns which way Blender was up.
        if motion := relation.get("motion"):
            m = {"kind": motion["kind"]}
            for key in ("from", "to", "center", "back", "impact", "delta", "push"):
                if key in motion:
                    m[key] = remap(motion[key])
            for key in ("arc", "dur"):
                if key in motion:
                    m[key] = round(motion[key], 4)
            if "movers" in motion:
                m["movers"] = motion["movers"]
            out["motion"] = m
        return out

    payload = {
        "relations": {w: entry(w, r, "prep3d-") for w, r in RELATIONS.items()},
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def ascii_name(word):
    """Asset-safe filename stem. Umlauts in bundle resource names are a unicode-normalization
    trap on Apple platforms, so `über` ships as `ueber`."""
    return (word.replace("ü", "ue").replace("ö", "oe")
                .replace("ä", "ae").replace("ß", "ss"))


def bake_ambient(specs):
    """Keyframe case-neutral idle motion into the built scene before an animated export.

    Ambient clips auto-play on BOTH sides of a drill question — the runtime plays every
    baked clip it finds, on `.repeat()` — so they may only touch prims the choreography
    never moves: never the subject, never a `movers` target. `--verify` enforces exactly
    that against the `.usda` twin, which is why an animated scene must ship one.

    Ops: `rotate_<axis>` is a continuous revolution (a clock hand); `swing_<axis>`
    oscillates by ±`amplitude` degrees (a tail). Each spec runs exactly one period over
    the exported range, so the repeat closes seamlessly.
    """
    scene = bpy.context.scene
    scene.render.fps = 24
    longest = max(int(spec.get("period", 4.0) * 24) for spec in specs)
    scene.frame_start, scene.frame_end = 1, longest + 1

    for spec in specs:
        obj = bpy.data.objects.get(spec["prim"])
        if obj is None:
            raise ValueError(f"ambient: no object named {spec['prim']!r} in the scene")
        op, _, axis = spec["op"].partition("_")
        index = "xyz".index(axis)
        obj.rotation_mode = "XYZ"
        period = int(spec.get("period", 4.0) * 24)
        base = obj.rotation_euler[index]

        if op == "rotate":
            beats = [(1, 0.0), (period + 1, math.tau)]
            interpolation = "LINEAR"
        elif op == "swing":
            amplitude = math.radians(spec.get("amplitude", 18.0))
            # phase 0.5 starts the swing on the opposite beat — legs and arms counter-swing.
            shape = (0.0, amplitude, 0.0, -amplitude, 0.0)
            if spec.get("phase", 0.0) >= 0.5:
                shape = (0.0, -amplitude, 0.0, amplitude, 0.0)
            beats = [(1 + int(step * period / 4), angle)
                     for step, angle in enumerate(shape)]
            interpolation = "BEZIER"
        else:
            raise ValueError(f"ambient: unknown op {spec['op']!r}")

        for frame, angle in beats:
            obj.rotation_euler[index] = base + angle
            obj.keyframe_insert("rotation_euler", index=index, frame=frame)
        obj.rotation_euler[index] = base
        for curve in figur.fcurves_of(obj.animation_data.action):
            for point in curve.keyframe_points:
                point.interpolation = interpolation


def export_usdz(path, animated=False, twin=None):
    """Export the built scene for RealityKit. Materials come across as USD Preview Surface,
    so the app can re-tint them per case and per theme at runtime instead of shipping a
    render per color.

    `animated` writes keyframes as USD TimeSamples (figur.py's idiom). `twin` additionally
    writes a plain-text .usda from the same scene immediately before the .usdz, because
    Blender's importer drops transform animation on re-import — the twin is the only honest
    record of which prims actually move, and `verify()` reads it.
    """
    # Geometry only: the app builds its own camera and light rig, and stowaway cameras in a
    # USDZ can hijack or crash the device renderer (three of them inside prep3d-story-fuer
    # trapped RealityKit on iPhone, 2026-07-30).
    for obj in [o for o in bpy.data.objects if o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(obj, do_unlink=True)
    if twin:
        os.makedirs(os.path.dirname(os.path.abspath(twin)), exist_ok=True)
        bpy.ops.wm.usd_export(filepath=twin, export_materials=True,
                              export_animation=animated, convert_orientation=True)
    bpy.ops.wm.usd_export(
        filepath=path,
        export_materials=True,
        export_animation=animated,
        # RealityKit expects Y-up; Blender authors Z-up.
        convert_orientation=True,
    )


def verify(path):
    """Re-import a shipped USDZ and check the contract the runtime depends on.

    Lifted from figur.py's verifier, which owns the reasoning about `merge_parent_xform=False`
    and the plain-text `.usda` twin; this checks the preposition scene contract instead of the
    six figure parts:

      - a prim named *subject* is present — the runtime tints and moves exactly that prim,
        and without it the canvas silently poses nothing,
      - zero stowaway cameras/lights (three cameras inside prep3d-story-fuer trapped
        RealityKit on iPhone, 2026-07-30),
      - if a `.usda` twin exists, its TimeSamples sit ONLY on prims the relation's `ambient`
        spec whitelists — never on the subject or anything the runtime itself moves, because
        a baked clip auto-plays on the question side and would fight the choreography.
        Blender's importer drops USD transform animation, so the twin is the only honest
        witness (see figur.usda_animation). A scene with no twin is assumed static, and an
        animated scene MUST write one.

    A render proves the picture; only this proves the file.
    """
    clear_scene()
    bpy.ops.wm.usd_import(filepath=os.path.abspath(path), merge_parent_xform=False)
    print(f"VERIFY {path} ({os.path.getsize(path)} bytes)")

    problems = []
    subject_found = False
    for obj in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        detail = ""
        if obj.type == "MESH":
            detail = f" verts={len(obj.data.vertices)} polys={len(obj.data.polygons)}"
        flag = ""
        if obj.type in ("CAMERA", "LIGHT"):
            problems.append(f"stowaway {obj.type.lower()} '{obj.name}'")
            flag = "  ← STOWAWAY"
        if "subject" in obj.name.lower():
            subject_found = True
        print(f"  {obj.name:24s} {obj.type:8s}{detail}{flag}")
    if not subject_found:
        problems.append("no prim named *subject*")

    stem = os.path.splitext(os.path.basename(path))[0]
    word = {ascii_name(w): w for w in RELATIONS}.get(stem.removeprefix("prep3d-"))
    allowed = {spec["prim"] for spec in (RELATIONS.get(word) or {}).get("ambient", [])}

    twin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders", "prep",
                        stem + ".usda")
    if os.path.exists(twin):
        ops, span = figur.usda_animation(twin)
        sampled = {p: sorted(v) for p, v in ops.items() if p and p != "root"}
        print(f"  animation: {len(sampled)} prims, frames {span[0]}..{span[1]}" if span
              else "  animation: twin carries no TimeSamples")
        for prim in sorted(sampled):
            ok = prim in allowed and "subject" not in prim.lower()
            print(f"    {prim:24s} {','.join(sampled[prim])}"
                  + ("" if ok else "  ← NOT WHITELISTED"))
            if not ok:
                problems.append(f"TimeSamples on non-ambient prim '{prim}'")
    else:
        print("  animation: no .usda twin — static export assumed (an animated scene must "
              "write a twin; Blender's importer cannot see USD transform animation)")

    print("  result:", "OK" if not problems else "FAILED — " + "; ".join(problems))
    return not problems


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--prep", default="auf", choices=sorted(RELATIONS))
    ap.add_argument("--state", default="dat", choices=["akk", "dat", "neutral"])
    ap.add_argument("--look", default="flat", choices=["flat", "dim"])
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--out", default="tools/blender/renders/out")
    ap.add_argument("--loop", action="store_true", help="render the Wohin→Wo motion sequence")
    ap.add_argument("--usdz", action="store_true", help="export the scene for RealityKit")
    ap.add_argument("--ghost", action="store_true", help="add a faint start pose to an akk still")
    ap.add_argument("--manifest", action="store_true", help="write the per-relation pose manifest")
    ap.add_argument("--refprobe", choices=sorted(REF_PROBES),
                    help="render a canned probe of one reference kind, with a resting ball")
    ap.add_argument("--verify", metavar="USDZ",
                    help="re-import a shipped USDZ and check the scene contract "
                         "(run Blender with --python-exit-code 1 to gate on the result)")
    args = ap.parse_args(argv)

    if args.verify:
        if not verify(args.verify):
            sys.exit(1)
    elif args.refprobe:
        clear_scene()
        setup_render(args.look, args.size)
        spec, ball_at = REF_PROBES[args.refprobe]
        ref_mat = make_material("reference", PALETTE["reference"], args.look)
        build_reference(args.refprobe, spec, ref_mat)
        add_sphere(ball_at, make_material("subject", PALETTE["dativ"], args.look))
        setup_camera(args.look)
        setup_lights(args.look)
        render_to(args.out)
    elif args.manifest:
        write_manifest(args.out)
    elif args.loop:
        render_loop(args.prep, args.look, args.size, args.out)
    elif args.usdz:
        global _LOD
        _LOD = "low"
        build(args.prep, args.state, args.look, args.size)
        # A scene with an `ambient` spec exports animated and leaves a .usda twin behind
        # for --verify; everything else stays a static pose.
        ambient = RELATIONS[args.prep].get("ambient")
        twin = None
        if ambient:
            bake_ambient(ambient)
            twin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders",
                                "prep", "prep3d-" + ascii_name(args.prep) + ".usda")
        export_usdz(args.out, animated=bool(ambient), twin=twin)
    else:
        build(args.prep, args.state, args.look, args.size, ghost=args.ghost)
        render_to(args.out)


if __name__ == "__main__":
    main()
