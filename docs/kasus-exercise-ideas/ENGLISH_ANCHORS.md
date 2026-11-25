# Die vier Fragen auf Englisch — the anchor questions, asked on an English sentence

**Status:** ideation only, no code. Measured against the shipped content on 2026-10-16.
**Companion file:** `english-anchors.html` in this folder — wireframes in the app's palette, the
same shape as `wireframes.html`. Open it in a browser.

The idea: show an **English** sentence, ring one part of it, and ask which of the four German
questions it answers. Then the same job in German. The case questions, as an English speaker
meets them:

| Case | German question | English equivalent | Role |
|---|---|---|---|
| **Nominativ** | Wer oder was? | Who or what? | the one doing it |
| **Akkusativ** | Wen oder was? | Whom or what? | the one it is done to |
| **Dativ** | Wem? | To whom? / For whom? | the receiver |
| **Genitiv** | Wessen? | Whose? | whose it is |

## What the app already does, and what it doesn't

| Piece | Asks | Stimulus |
|---|---|---|
| **Rollen**, Schritt für Schritt (`KasusConceptPanels`) | the Kasus-Check's six questions as Ja/Nein, first Ja decides | German, English behind `KasusEnglishToggle` |
| **Die Pronomen-Brücke** (`BridgeQuestion`) | „I see ___“ → „Ich sehe ___“ → „Ich sehe ___ Hund“ | English **first**, then German — but on pronoun forms, and only Nom vs. Akk |
| **Lektion ▸ Englisch zuerst** (`KasusLesson`) | the *to* test, *him* = ihn-or-ihm, `'s` / `of` | prose, not an exercise |

So wer/wen/wem/wessen exist in the app as **prose in the lessons and the Merkhilfen only**. The
Kasus-Check deliberately replaced them as the way to decide (docs/KASUS.md § Verstehen), and that
stays right: a question test can't see a Dativ verb. Idea 4 in `IDEAS.md` is the matching version
of the four questions on **German** phrases, still unbuilt. **Nothing in the app asks a question
about an English sentence.**

## The data is already there

Every one of the 716 Verstehen items (`Resources/kasus_concepts.json`) carries an English twin per
paragraph. 1595 of its 1924 targets carry `en`, their own span in that English line — and every one
of those 1595 is a **verbatim substring** of the line it belongs to, so highlighting needs no
alignment work. `KasusConceptItem.englishLine(paragraph:highlighting:)` already paints those spans
in case colors for the English toggle. An English-first exercise is a **presentation of shipped,
already-gated content**, not a new content pack.

## Where the English question works, and where it lies

All 1924 targets, bucketed by `reason`:

| What the English span answers | Targets | Share | Verdict |
|---|---|---|---|
| Wer oder was? (`subject`) | 727 | 38% | works |
| Wen oder was? (`object`) | 364 | 19% | works |
| Wessen? (`attribute`, `'s` / `of`) | 119 | 6% | works, word order flips |
| Wem? (`recipient`, the *to* test) | 82 | 4% | works |
| **A preposition decided it** (`preposition`, `inferred`, `wechselWo`) | 416 | 22% | **no question applies at all** |
| **Dativ verb** (`dativeVerb`) | 206 | 11% | **the question gives the wrong case** |
| Predicate noun (`predicate`) | 10 | 0.5% | answers „who?“ too; needs „= Subjekt“ |

1224 spans (77% of the English-spanned ones) are cleanly askable. The remaining 23% is not noise —
it is five systematic classes, and they are the reason this can never be "every English sentence":

1. **Dativ verbs.** „The father followed the woman“, „thanks the man“, „helps the brother“. An
   English brain asks *whom?* and lands on Akkusativ. 206 spans, and the lesson's own Falle card
   already says so: „*helfen* takes the Dativ although English says help **him**“.
2. **Role inverters** — *gefallen, gehören, schmecken, fehlen*. „I like the film“ = „Der Film
   gefällt mir“: the English **subject** is the German Dativ and the English object is the German
   subject. This breaks „find the English doer → Nominativ“ at the root, not at the edge.
3. **Prepositions don't transfer.** „waiting **for** the bus“ → *auf den Bus*; „answering the
   letter“ → *auf den Brief*. `Resources/verb_prepositions.json` already classifies 14 of its 42
   pairs as `fit: "trap"` for exactly this. And „a friend **of** mine“ → *von mir* (Dativ), so `of`
   is not the Genitiv either.
4. **English has no form to ask with.** *him/her/them* covers Akkusativ **and** Dativ; *whom* is
   dead in speech, so „Whom or what?“ has no native feel to lean on; „It's **me**“ is accusative
   where German is nominative (*Das bin ich*).
5. **No English counterpart at all.** Bare accusatives of time („every day“ → *jeden Tag*),
   passives („He was given a book“ → *Ihm wurde ein Buch gegeben*).

The deeper limit: **the case is a property of the German sentence.** `KasusValidator` needs German
text with located targets to prove anything. For a sentence the learner types in English there is
nothing to validate until a German twin exists; the tutor seam could write one
(`KasusConceptBank.merging`, unused), but the documented harvest is about a third of planned
phrases, and a wrongly highlighted span teaches a wrong case. Authored pairs stay the only
trustworthy source.

## The two exercises

Both read `kasus_concepts.json`, both are English-first, and the split is what makes the honest
version teachable: one exercise where the question always works, one where it doesn't.

### A · „Welche Frage?“ · Which question?

The English line alone, one span ringed. Five buttons: **Wer oder was? · Wen oder was? · Wem? ·
Wessen? · Keine Frage** („a preposition decided it“). After the pick the German twin slides in
underneath with the span in its case color, and the explanation is the target's own
(`KasusExplanation`) with its role line.

Three stages on the same item, the Pronomen-Brücke's ramp:

| Stage | Shows | Asks |
|---|---|---|
| **Englisch** | the English line only | which question the ringed part answers |
| **Beide** | English over German, spans aligned | the same question, on the German phrase |
| **Deutsch** | the German line only | the same question, English gone |

### B · „Die englische Falle“ · Where your English lies

The same screen, drawn from the classes above, where the right answer is the one the English
question does **not** suggest: „The father followed the woman“ → *whom?* feels like Akkusativ,
German is Dativ, *folgen* is on the list. The reveal names the class, not just the case, and the
inverters get the full flip („I like the film“ → „Der Film gefällt mir“: the film is the subject).
Same family name as the preposition hub's **Die Falle**, deliberately.

### Invariants

- **Every Welche-Frage round contains at least one `Keine Frage` span.** Without it the learner
  learns a false rule — that every phrase answers one of the four — when Kasus-Check step 1 says a
  preposition decides first.
- **The clean pool excludes `dativeVerb`.** A question whose English answer contradicts the German
  case is never asked in A; in B that contradiction *is* the item.
- **Only targets with an `en` span are asked** (1595 of 1924), since the ring has to land on real
  English text.
- Never single-case past Nominativ, as everywhere else in Verstehen.

## Stufen · how much help

The buttons carry their case: the German case name in its palette color above the question, the
English gloss under it, and the role symbol (⚡ 🎯 🎁 🔑) only at the easiest setting. Three signals
at most on one button, since colour plus name plus symbol plus gloss plus code word is a badge pile.
`Keine Frage` is the one button with no case colour: it stays white with a dashed border and a grey
label, never grey-filled, because Nominativ owns graphite.

**One dial, three presets, the same five options at every setting.** What changes is the number of
crutches on screen, not the number of plausible answers. If the option count moved with the
setting, first-try share would stop being comparable from round to round, and the coach's shaky
maths reads exactly that number.

| Switch | Leicht | Normal | Frei |
|---|---|---|---|
| Deutsch mitzeigen (German line under the English) | on | on | off (German only) |
| Teile markieren (ring every phrase that gets asked) | on | on | off, one ring |
| Fall über der Frage (case name on the button) | on, with the symbol | on | off |
| Englische Frage („who or what“) | on | off | off |
| Nur die Fälle der Einheit (fewer buttons) | on | off | off |
| Ganzer Satz (ask every phrase, not just one) | on | on | off, one phrase |
| Item pool | 2 askable spans, no preposition target | any | 3–4 spans, at least one preposition-governed |

Presets, not a matrix: six independent switches is 64 states to reason about and to pin with golden
numbers, three named presets is three. The switches stay underneath for whoever wants them. Same
shape as `KasusRolesMode`, which also **locks once an answer is in**, so a setting can't be changed
mid-item to rescue a guess. The declared `germanLevel` picks the opening preset once (A1 → Leicht,
B1+ → Normal) and is never written back, exactly as it picks the start unit today.

**Leicht marks the round.** The app already has the convention: a round that showed its answers
carries „Lösung angezeigt“ and an eye in Verlauf. An eased round gets the same treatment and stays
out of the coach's shaky-case maths, so scaffolding can't inflate the pyramid.

### Where the settings live: „Übung einstellen“

A pre-screen in front of the drill, built the way the deck and story launchers already are
(`CardDeckView+Setup` puts a single „Card settings…“ row above Start, with
`FlashcardPreviewOptionsView` as the sheet's body; `ArticleGameSetupView` is the same shape with
`@AppStorage` for its options). Panels **P1**, **P2** and **P4** in the HTML draw it.

**It is one control, not four sections.** Everything else on that screen was already decided
somewhere better:

| Looked like a section | Where it actually belongs |
|---|---|
| The unit and its cases in play | the row the learner tapped |
| Round length | `KasusDrillMeta.roundSize`, which already fixes 8 for Rollen and 10 for the Schnellrunde |
| „Classify a phrase“ vs. „find the phrase“ | two kinds in the registry, so **two launcher rows** on the unit screen |
| How much help | the only one a learner can answer, and the only one that stays |

So the screen is: a summary line, the segmented preset with a sentence saying what it means, a
**Hilfen einzeln…** row, and Start. **And most launches never see it:** the hub's Weiter row and the
coach's „Üben“ button start with the seeded preset and put „Hilfen“ in the drill's toolbar, where
Rollen's mode lives today. The setup screen is something a learner can go their whole time without
opening.

### Iconography

The rule is already written: **„Art marks a task you can play. A tinted chip marks a place you can
enter or read“** (`GrammarLauncherRow`, `docs/GRAMMAR_EXERCISES.md`). Applied to these screens:

- **The setup screen's header** wears the exercise's own `GrammarTaskArt` drawing, because the
  screen announces one task. Not a symbol.
- **„Hilfen einzeln…“** wears a 34pt `GrammarRowChip`, because it is a place you enter.
- **The segmented preset wears nothing.** A chip marks a place, not a value, and three icons on one
  control next to three words is the badge pile.
- **The sheet's switch rows get a bare 17pt glyph in the secondary colour,** not a chip. A settings
  row is neither a task nor a place, and six tinted chips in a column read as six doors. This is
  what iOS Settings does and what these rows are.
- **The answer buttons** keep `GrammarCase.symbol` at Leicht only: `bolt.fill` ⚡, `target` 🎯,
  `gift.fill` 🎁, `key.fill` 🔑, which the hub and the endings table already use for the four cases.

| Row | SF Symbol | Where it comes from |
|---|---|---|
| Header | — | `GrammarTaskArt`, a drawing |
| Hilfen einzeln… | `slider.horizontal.3` | the deck launcher's „Card settings…“ |
| Starten | `play.fill` | the deck launcher's Start |
| Deutsch mitzeigen | `rectangle.split.1x2` | new |
| Teile markieren | `highlighter` | Markieren's own symbol in the registry |
| Fall über der Frage | `tag.fill` | Rollen's own symbol in the registry |
| Englische Frage | `character.book.closed` | new |
| Nur die Fälle der Einheit | `line.3.horizontal.decrease` | new |
| Ganzer Satz | `list.number` | new |
| Schritt für Schritt | `figure.walk` | new, Rollen only |

A switch wearing the glyph of the thing it turns on (`highlighter`, `tag.fill`) is the cheap win
here: the sheet reads as a list of the screen's own parts rather than a list of jargon. The HTML
draws SVG stand-ins; **check every name in SF Symbols before it ships**, the way a What's New symbol
gets checked.

### The preset is seeded from the declared level

`modelManager.germanLevel` (`CEFRLevel`, A1–C1) already carries the contract this needs, in its own
words: *exercises **seed** from it and never write back, so running one story at B2 doesn't quietly
make you a B2 learner everywhere.* The preset follows the same rule, in three states:

- **automatisch** — derived from `germanLevel` on every render, nothing stored, so changing the
  level in Settings moves it. This is `KasusPath.next`'s habit: derive, never persist.
- **von dir gewählt** — stored (`kasus.hilfe`) the moment a preset or a switch is touched; level
  changes stop reaching it.
- **Wieder automatisch** — one row to hand it back.

| Declared level | Preset it suggests |
|---|---|
| A1, A2 | Leicht |
| B1 | Normal |
| B2, C1 | Frei |

**A first guess, not a finding.** CEFR level says what a learner can *say*; it says nothing about
whether anyone ever taught them what a direct object is, which is the whole reason Verstehen
exists. A B2 who never met the terms has to be able to turn the help back on in one tap.

**The round is the better signal.** After a Leicht round that comes out near-perfect, the next
launch offers Normal once, as a row that can be ignored. What counts as near-perfect is deliberately
not a number in this note: it gets measured on real rounds first, the way the coach's shaky
threshold was, rather than being guessed here.

Four rules the screen has to follow:

- **The one-tap paths stay one tap** (above). The hub hero is the app's spine, and a settings gate
  in front of it is friction on the main path.
- **One preset for all of Verstehen,** not one per exercise. Rollen, Wer macht was?, Die Probe and
  Welche Frage? all want the same six switches, so `kasus.hilfe` is read by the drill shell and
  `kasus.rolesMode` moves in as a seventh switch, shown only for the kinds that have it. Which
  switches a kind shows is a row in `KasusDrillMeta`, so the next exercise inherits the sheet
  instead of growing its own toggles.
- **Settings lock once an answer is in,** as `KasusRolesMode` already does, so a preset can't be
  changed mid-item to rescue a guess. Touching any switch makes the preset read „Eigene“.
- **The preset rides along on the round.** One more raw-value string on `KasusRound`, no new synced
  field, so Verlauf can print „Leicht · Hilfen an“ and the eye next to the score (panel **P3**).

This is also what makes the idea portable: once the preset and the sheet live on the shared shell,
every other exercise gets its own switches for the price of a `KasusDrillMeta` row. Worth building
before the second exercise wants it, not after.

### Why the options follow the unit, not the sentence

Measured over the 700 items that hold an askable span:

| Askable spans per item | Items | | Distinct cases per item | Items |
|---|---|---|---|---|
| 1 | 51 | | 1 | 52 |
| 2 | 457 | | 2 | **483** |
| 3 | 148 | | 3 | 144 |
| 4 | 44 | | 4 | 21 |

„Show only the cases this sentence contains“ turns **69% of the pool into a coin flip** and hands
the answer over outright on the 52 single-case items. Cutting the buttons to the **unit's**
`casesInPlay` does the same job honestly and ramps by itself: Nominativ one button, Akkusativ two,
Dativ three, Genitiv and Alle Fälle all five. The path is already the difficulty curve.

The same numbers cap „ganzer Satz“: a two-span sentence is one real ask plus one elimination, which
is why **Frei** asks a single phrase per sentence and Leicht asks them all (there the elimination is
the scaffold).

### The n/n counter

„Satz 3 · Fall 2 von 3“ over the sentence, with the asked phrase ringed solid and the phrases still
to come ringed dashed. It leaks nothing: the ring count says how many phrases get asked, never
which case any of them is, and Rollen already rings each asked phrase. Answered phrases keep their
case colour, which is the elimination hint Leicht is allowed to give.

### A second difficulty axis, not a setting

**„Finde den Fall“** flips the task: show the question („Wem?“) and let the learner tap the phrase
that answers it, instead of showing the phrase and asking for the question. Classifying a given
phrase and locating the right one are different skills, and the second is the one reading needs.
Same items, no new content, and the interaction exists already in Markieren's word chips. Worth a
variant rather than a dial, since it is harder at every setting.

## Pool sizes per unit, today

Items that hold at least one askable span, and the spans themselves:

| Unit | Clean items | Clean spans | Falle items | Falle spans | `Keine Frage` spans |
|---|---|---|---|---|---|
| Nominativ | 50 | 50 | 0 | 0 | 1 |
| Akkusativ | 151 | 299 | 0 | 0 | 23 |
| Dativ | 149 | 195 | 123 | 123 | 10 |
| Genitiv | 197 | 378 | 33 | 33 | 67 |
| Alle Fälle | 151 | 302 | 38 | 38 | 66 |
| **Total** | **698** | **1224** | **194** | **194** | **167** |

Exercise A clears `minimumItems` on every unit from day one. **Die englische Falle** only has a
pool on Dativ, Genitiv and Alle Fälle — which is correct, since that is where the trap lives, and
`KasusConceptBank.offered` already keeps a unit from showing an exercise it can't fill.

**The one data gap:** `Keine Frage` is thin on Nominativ (1) and Dativ (10), because most
preposition-governed targets have no `en` span — 249 of the 416 are `inferred` place phrases that
were never marked in the English line. The English text already contains them („in the forest“,
„because of the cold“, „for the man“); only the span is missing. A one-off script can propose the
spans by locating the preposition phrase in the English line, then a hand read — no LLM round, no
new sentences. That is the cheapest content work on this list.

## Build cost

Six steps, the `docs/GRAMMAR_EXERCISES.md § Adding an exercise type` list, with no new content
pack and no gate:

1. `KasusRoundStep.frage` and `.englischeFalle` with their `KasusDrillMeta` rows and
   `GrammarTaskArt` (the ringed English span is a new drawing; the Falle could reuse the
   preposition hub's).
2. `KasusDrillKind` cases pointing at the Verstehen pack.
3. One module in `Features/Grammar/Drill/`, close to `KasusRolesHero` + `KasusRoleGrid` with the
   question chips in place of the role chips and the English line as the hero.
4. A `DrillVariant` for the stage (Englisch · Beide · Deutsch) and the pool (clean · Falle).
5. `KasusDrillMetaTests`, `GrammarTaskArtTests`, `KasusDrillShellTests.modulesCompose`, a
   `-kasus.debugVerifyRecord` row, plus a pool test per unit pinning the numbers above.
6. A What's New bullet.

Recording, Verlauf, the calendar, the round detail, the unit screens, the hub dots and
`-kasus.debugOpen frage:dativ` need nothing.

## Open questions

- **Does the German stage earn its place,** or is it just Rollen with different chips? Rollen's
  `.direkt` mode is the same grid; the honest answer may be that stage 3 *is* Rollen, and this
  exercise ends at **Beide** and hands off.
- **Coach:** Rollen, Wer and the lesson never move the coach; only Die Probe does. A question
  exercise on an English stimulus is comprehension, so probably `countsTowardSkill == false` —
  but **Die englische Falle** on Dativ verbs is exactly the signal the Dativ focus wants.
- **Is `Keine Frage` one button or a second tap** („a preposition in front? Ja → which one“)?
  The second reads like the Kasus-Check and costs one more tap per item.
- **Where it lives:** a Verstehen row on each unit (next to Rollen) or one row in the Nachschlagen
  library as a warmup. Verstehen fits the dots; the library doesn't claim progress.
- **Does the dial belong to this exercise or to Verstehen as a whole?** Rollen, Wer macht was? and
  Die Probe would all take the same switches, and one `kasus.hilfe` preset read by every Verstehen
  screen beats four private toggles. Argues for building it on the shared shell, not in the module.
- **Does Leicht need its own golden numbers?** The pool filters per preset (2-span items for
  Leicht, 3–4 for Frei), so `KasusConceptFixtures` would pin three counts per unit instead of one.
