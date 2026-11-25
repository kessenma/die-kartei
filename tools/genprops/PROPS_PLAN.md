# Props Plan — sentence ↔ scene pairing for all 36 prepositions

The next round of preposition scenes: every sentence stars **der Hund**, the pilot's best
generated prop, so the deck reads as one story and the scene always depicts its own example
sentence. The object of each preposition varies gender on purpose (den Zaun, die Kiste, das
Sofa, des Baches…) — that's where the case shows, so that's where the variety has to be.

## Design rules

1. **Subject carries the case color.** The animated protagonist (dog, ball, bird, gift) is the
   `subject` entity — one flat material, tinted at runtime exactly like today's ball.
2. **References stay charcoal** and are primitives whenever primitives read well (fence, hoop,
   table, door). The GPU is for organisms and soft things only — the house pilot showed
   architectural detail fights the pictogram style.
3. **Generated props ship shape-only**, decimated ~18k faces, flattened via
   `convert_prop.py`. One material per prop or runtime tinting breaks.
4. **Rigging tiers:** ambient clips (tail wag) bake into the USDZ and just play; event
   animations (gift lid on reveal) need the runtime-hinge extension — decide per prop.
5. ~~**The ball set stays.**~~ **Superseded 2026-08-12 (Kyle's call, reversing his
   2026-07-30 one):** the styles merged into one curated set per word — the four authored
   story scenes became canonical, `PrepositionSceneStyle`/`storyRelations`/the pickers were
   deleted, and the whole 36-word set was reworked in one pass under the „Die Figur führt
   vor" design language (see docs/PREPOSITION_3D.md, 2026-08-12 section). There is no
   variants block and no style option.
6. **Sentences append, never replace — and order is the contract.** A word's scene sentence
   joins its `examples` array in `prepositions.json` **first** in the same commit its scene
   lands; array position, not a style field, is what makes it the primary the drill reveal
   and gallery show. The other sentences stay listed as extras.

## The table

Status: ✅ have · 🔨 generate · 🧱 build in rig (primitives)

| # | Wort | Fall | Neuer Satz | English | Subject | Reference | Status | Motion |
|---|------|------|-----------|---------|---------|-----------|--------|--------|
| 1 | bis | Akk | Der Hund rennt bis an den Zaun. | The dog runs up to the fence. | Hund | Zaun | ✅ / 🧱 | shuttle, stops at fence |
| 2 | durch | Akk | Der Hund springt durch den Reifen. | The dog jumps through the hoop. | Hund | Reifen (torus) | ✅ / 🧱 | through, arc |
| 3 | für | Akk | Das Geschenk ist für den Hund. | The present is for the dog. | Geschenk | Hund | ✅ / ✅ | shuttle arc to dog; lid opens on arrival (runtime hinge, later) |
| 4 | gegen | Akk | Der Ball rollt gegen die Wand. | The ball rolls against the wall. | Ball | Wand | ✅ / 🧱 | bounce (unchanged) |
| 5 | ohne | Akk | Der Mann geht ohne den Hund spazieren. | The man goes for a walk without the dog. | Hund | Figur | ✅ / 🧱 | abandon — figure leaves, dog stays |
| 6 | um | Akk | Der Hund läuft um den Baum. | The dog runs around the tree. | Hund | Baum | ✅ / 🧱🔨 | orbit |
| 7 | aus | Dat | Der Hund kommt aus der Hundehütte. | The dog comes out of the doghouse. | Hund | Hundehütte | ✅ / 🔨 | shuttle out the door (horizontal, no over-wall arc) |
| 8 | außer | Dat | Alle Hunde spielen außer meinem Hund. | All the dogs are playing except mine. | Hund | Hunde ×3 (instanced) | ✅ / ✅ | idle apart; cluster of instanced dogs |
| 9 | bei | Dat | Der Hund bleibt beim Kind. | The dog stays with the child. | Hund | Figur | ✅ / 🧱 | idle together + tail wag |
| 10 | gegenüber | Dat | Der Hund sitzt der Katze gegenüber. | The dog sits opposite the cat. | Hund | Katze | ✅ / 🔨 | idle face-off, both tails |
| 11 | mit | Dat | Das Kind geht mit dem Hund spazieren. | The child walks with the dog. | Hund | Figur | ✅ / 🧱 | carry stroll + wag |
| 12 | nach | Dat | Der Hund läuft nach Hause. | The dog runs home. | Hund | Hundehütte | ✅ / 🔨 | shuttle, arrives at the doghouse |
| 13 | seit | Dat | Seit einer Woche wohnt der Hund bei uns. | The dog has lived with us for a week. | Hund | Pfad | ✅ / 🧱 | slow crawl (unchanged shape) |
| 14 | von | Dat | Das Geschenk ist von der Oma. | The present is from grandma. | Geschenk | Figur | ✅ / 🧱 | shuttle away from figure |
| 15 | zu | Dat | Der Hund läuft zum Kind. | The dog runs to the child. | Hund | Figur | ✅ / 🧱 | shuttle, arrives at figure |
| 16 | an | W | Ich hänge das Bild an die Wand. / Das Bild hängt an der Wand. | I hang the picture on the wall. / The picture hangs on the wall. | Bild (frame) | Wand | 🧱 / 🧱 | travel (unchanged) |
| 17 | auf | W | Der Hund springt auf das Sofa. / Der Hund schläft auf dem Sofa. | The dog jumps onto the sofa. / The dog sleeps on the sofa. | Hund | Sofa | ✅ / 🔨 | travel: jump up vs settled |
| 18 | entlang | W | Der Hund läuft den Zaun entlang. | The dog runs along the fence. | Hund | Zaun | ✅ / 🧱 | travel along |
| 19 | hinter | W | Der Hund läuft hinter den Baum. / Der Hund versteckt sich hinter dem Baum. | The dog runs behind the tree. / The dog hides behind the tree. | Hund | Baum | ✅ / 🧱🔨 | travel + occlusion |
| 20 | in | W | Der Hund springt in die Kiste. / Der Hund sitzt in der Kiste. | The dog jumps into the box. / The dog sits in the box. | Hund | Kartonkiste (flaps) | ✅ / ✅ | travel: drop in vs seated |
| 21 | neben | W | Der Hund legt sich neben den Napf. / Der Hund liegt neben dem Napf. | The dog lies down next to the bowl. / The dog lies next to the bowl. | Hund | Napf | ✅ / 🔨 | travel |
| 22 | über | W | Der Vogel fliegt über den Zaun. / Der Vogel kreist über dem Zaun. | The bird flies over the fence. / The bird circles above the fence. | Vogel | Zaun | 🔨 / 🧱 | travel: crossing vs circling; wing hinge pair (like the lid) |
| 23 | unter | W | Der Hund kriecht unter den Tisch. / Der Hund schläft unter dem Tisch. | The dog crawls under the table. / The dog sleeps under the table. | Hund | Tisch | ✅ / 🧱 | travel (unchanged shape) |
| 24 | vor | W | Der Hund läuft vor die Tür. / Der Hund wartet vor der Tür. | The dog runs to the door. / The dog waits at the door. | Hund | Tür | ✅ / 🧱 | travel |
| 25 | zwischen | W | Der Hund legt sich zwischen die Kissen. / Der Hund schläft zwischen den Kissen. | The dog lies down between the pillows. / The dog sleeps between the pillows. | Hund | Kissen ×2 | ✅ / 🔨 | travel: drop in between |
| 26 | statt | Gen | Statt eines Knochens bekommt der Hund einen Ball. | Instead of a bone, the dog gets a ball. | Ball | Knochen (slides out) + Hund | ✅ / 🔨 | swap — bone out, ball in |
| 27 | trotz | Gen | Trotz des Zauns entkommt der Hund. | Despite the fence, the dog escapes. | Hund | Zaun | ✅ / 🧱 | shuttle arc over the fence |
| 28 | während | Gen | Während des Essens wartet der Hund. | During dinner, the dog waits. | Hund | Figur + Tisch | ✅ / 🧱 | idle: dog watching, tail wag |
| 29 | wegen | Gen | Wegen des Hundes bleibt die Katze draußen. | Because of the dog, the cat stays outside. | Katze | Hund + Tür | 🔨 / ✅🧱 | cause: dog present → cat keeps its distance |
| 30 | außerhalb | Gen | Der Hund schläft außerhalb der Hütte. | The dog sleeps outside the doghouse. | Hund | Hundehütte | ✅ / 🔨 | idle |
| 31 | innerhalb | Gen | Der Hund bleibt innerhalb des Zauns. | The dog stays inside the fence. | Hund | Zaun (enclosure) | ✅ / 🧱 | idle |
| 32 | oberhalb | Gen | Die Katze sitzt oberhalb des Hundes. | The cat sits above the dog. | Katze | Regal + Hund | 🔨 / 🧱✅ | idle, both tails |
| 33 | unterhalb | Gen | Der Hund schläft unterhalb des Fensters. | The dog sleeps below the window. | Hund | Fensterwand | ✅ / 🧱 | idle |
| 34 | diesseits | Gen | Diesseits des Baches sitzt der Hund. | On this side of the stream sits the dog. | Hund | Bach (band) | ✅ / 🧱 | idle |
| 35 | jenseits | Gen | Jenseits des Baches sitzt die Katze. | Beyond the stream sits the cat. | Katze | Bach (band) | 🔨 / 🧱 | idle, occluded base — rhymes with diesseits |
| 36 | beiderseits | Gen | Beiderseits des Weges stehen Bäume. | On both sides of the path stand trees. | Bäume ×2 (one joined mesh) | Pfad | 🧱🔨 / 🧱 | idle — two islands in ONE subject mesh so tinting hits both; beiderseits finally gets a scene |

## Generation queue (deduped)

One pod session, ~$1 at A6000 rates. Prompt style per the pilot: "simple minimalist toy
figurine of X, smooth solid matte gray material, no texture, plain white background, soft
studio lighting, 3d render". Verify each with a judge render before rigging.

Generated 2026-07-30 (second pod session, ~$0.37, 11 meshes incl. seed variants). Winners
live in `samples/`; raw GLBs + all seed variants in the session scratchpad.

| Prop | Used by | Height | Rig | Outcome |
|------|---------|--------|-----|---------|
| Katze (sitting cat) | gegenüber, wegen, oberhalb, jenseits | 1.2 | tail wag (reuse rig_dog approach) | ✅ seed 7 — whiskers survived, tail rests on ground |
| Vogel (small bird) | über | 0.7 | skeletal flap (rigid cut would seam the shoulder) | ⚠️ standing pose — can't say "fliegt" (Kyle's catch). Superseded by **vogelflug** (flying pose, seed 21 of the retry session; s7's right wing was a paddle): wings spread, legs tucked, arrives ~41° yawed so `rig_vogel.py --rotz -41` de-rotates before the \|x\| weights. `samples/vogelflug.usdz` + `vogelflug-flap.usdz`. The standing `vogel.usdz` stays for possible perched use. |
| Knochen (bone) | statt | 0.5 | none | ✅ seed 7 |
| Napf (food bowl) | neben | 0.45 | none | ✅ seed 7 — cleanest of the set |
| Sofa | auf | 1.1 | none | ✅ seed 7 (s21 also fine, slightly saggy) — furniture worked this time |
| Hundehütte (doghouse) | aus, nach, außerhalb | 1.5 | none | ✅ retry seed 7 (`huette2`): empty doorway, tiny threshold lump only. The first session's doorway occupant was *fused into the main shell* (974k-vert island — not deletable cleanly), hence regeneration over surgery. `samples/huette.usdz` is the retry version. |
| Kissen (pillow) | zwischen | 0.4 | none | ✅ seed 7 |
| Baum (toy tree) | um, hinter, beiderseits | 1.9 | none | ❌ both seeds (mortarboard blob / radish) — go 🧱: foliage sphere + cylinder trunk in the rig, as anticipated |

New 🧱 primitives for the rig: **fence** (posts + two rails), **hoop** (torus), **door**
(frame + slab), **shelf** (wall bracket), **window wall** (portal high in a wall),
**picture frame** (thin box) — each a `build_reference` kind, a dozen lines apiece.

## Shipped rows

**2026-07-30, vertical slice:** rows 3 (für), 5 (ohne), 11 (mit), 20 (in) are live end to end —
`STORY` dict in prep_render.py (subject_mesh + compound refs), `prep3d-story-*` assets,
`storyRelations` manifest block, `PrepositionSceneStyle` toggle (hub options + gallery
segmented picker, AppStorage `prepositions.sceneStyle`, per-word fallback to classic), and
story sentences appended to prepositions.json with `"style": "story"` (drill reveals show the
active style's sentence via `revealExamples`; card backs list both, active style first).
Remaining rows are now mechanical: author the STORY row, render, re-manifest, append the
sentence — same commit.

## Order of work

1. Rig primitives (fence, hoop, door, shelf, window, frame) — free, unblocks 14 rows.
2. Pod session: generate the 8 props, judge renders, retry the risky two (Sofa, Hütte).
3. Rig cat tail + bird wings; convert everything to USDZ.
4. Teach `build_reference` a `mesh` kind (imports a converted prop into the Blender scene)
   and the app's scene loader nothing new — props arrive via the existing USDZ path.
5. Per word: re-author RELATIONS row → render stills + USDZ → flip the sentence in
   `prepositions.json` in the same commit. Check off the table row.
