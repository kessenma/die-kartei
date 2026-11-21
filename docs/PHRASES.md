# Wortgruppen · Phrases as flashcards

A card can hold a phrase, not just a word: "eine Störung beheben", "fundierte Kenntnisse in
Python", "der Meinung sein". Teachers teach chunks as much as words, and the hard part of a chunk
is which words go together, not what each word means.

Built 2026-11-16 (plan: `~/.claude/plans/can-we-plan-out-wobbly-moth.md`): the phrase type and
the bugs it fixes, the gap face, phrase cards from a lesson's answer key and from German-explanation
tables, "Make this sentence a card", and "Save phrase" → deck. The teacher's key itself is in
docs/WORKSHEETS.md, *The teacher's key*. **Device check open:** the gap face in Default, Anki and
Leitner on a small phone (with the rating row under it), the Save-phrase toggle, the sentence
button, a workbook's Wortgruppen in the Wörter sheet.

Not built: word-order tiles, typed answers graded word by word, linking a word card to its phrases.

## The rule (`Services/CardKind.swift`)

One `nonisolated enum` decides, from the German text alone, whether a card is one word or a
phrase. Every save path goes through it; there used to be eight private `splitArticle` copies.

- `CardKind.split(_:)` strips a leading der/die/das **only when one word follows**: "das Ticket"
  → Ticket + das. Anything longer is a phrase and stays whole, with no article: "der Meinung
  sein", "Das ist gut".
- What a sheet prints beside a word doesn't count as a word: a dash for "no plural"
  ("die Berufserfahrung —"), a trailing bracketed note ("die Kenntnisse (Pluralform)"), plural
  notation after a comma ("der Tisch, -e", "der Tisch, die Tische"). Hyphens keep a word whole
  ("der First-Level-Support"). "sich" + one word is a reflexive verb, not a phrase.
- A phrase is stored with `wordType == CardKind.phrase` (`"phrase"`). That is a new **value** of
  an existing synced field, so no codec change. It is deliberately not a `WordClass` case: that
  enum is the parser's four word classes, and its tests pin it.
- `CardKind.isPhrase(germanWord:article:wordType:)` reads a stored card with its article put back
  in front, so a phrase an older save split ("Meinung sein" + der) still reads as a phrase.
- `CardKind.matchKey(_:)` is the "already saved" key: a leading article stripped whatever follows,
  lowercased. Looser than `split` on purpose, so old split cards and new whole ones match.

Known edge: a phrase with a comma followed by an article ("Ja, die Sache …") is read as plural
notation and treated as one word. Rare in practice.

## Invariants

1. **A phrase never has an article.** Nothing splits one off, the dictionary check never gives it
   a gender, and so it never reaches the flip card's article quiz or the der/die/das game.
2. **A phrase is never checked against the dictionary.** `WiktionaryValidator.evaluate` returns
   `.unchecked` for it (no badge). Before this, a noun-tagged phrase got a gender from its *last*
   word's suffix ("das Ziel der Ausbildung" → die, from -ung), written back on every deck open,
   and every other phrase carried a "Not in dictionary" badge.
3. **Chat review credits a phrase only when all of it was used.** `ConversationPrompts
   .matchedWords` needs every content word of a phrase (articles, pronouns and jdm./etw.
   placeholders may change); single words match as before. It used to match the last word alone,
   so saying "Python" advanced "fundierte Kenntnisse in Python" in spaced review.
4. **Cards saved before the rule are repaired on open.** `PhraseRepair.apply(to:)` runs in
   `DeckStore.session(for:)` (so deck mix too) and `resumeSession`, before validation: a
   multi-word card gets its article back in front, `article = nil`, `wordType = "phrase"`.
   Idempotent. Skips singleton decks (Goethe, past tense: card ids derive from the German) and a
   verb that came with its conjugation table.

## Where phrases go and don't

| Place | Phrase behaviour |
|---|---|
| Flip card, Anki, Leitner, quiz, matching, deck mix | Work (self-rated). |
| Article quiz, der/die/das game | Skipped: no article. `deckQuestions` also guards explicitly. |
| Dictionary check | `.unchecked`, no badge. |
| Document decks | `WordClassTagger` skips phrase rows; `merge` stores `"phrase"`. A row whose German the tutor reworded while translating keeps its English by position when the tutor answered every line (`DocumentDeckService.assign`); it used to be dropped silently. |
| Spiele | Filtered out, with the reason shown (unchanged). |
| Wortschatz, pyramid | No phrases (the Goethe lists have none). |
| Card pictures | `"phrase"` falls into the "a simple scene depicting …" prompt. |
| Word-class colour | Indigo (`WordClassPalette`). |

## The gap face (`PhraseGapPlanner`, `PhraseGapCardView`)

A phrase is hard for which words go together, so a phrase card shows with one word missing and
four to pick from. Decided by Kyle: a **face inside Default, Anki and Leitner**, not a fourth
`FlashcardStyle`, so `QuizResult`, Leitner's session count, pause/resume and deck mix are
untouched; answered by **tapping one of four**.

- **Where the gap goes** (`PhraseGapPlanner.gap`): a verb + preposition pair the app teaches
  (`VerbPrepositionService`: "sich freuen auf") → the preposition; else an infinitive ("eine
  Störung beheben", "der Meinung sein") → the verb, by the dictionary's parts of speech or a final
  lowercase -en/-ern/-eln; else a preposition ("Erfahrung mit Git") → it; else the longest content
  word, and in a whole sentence (≥ 4 words, final . ! ?) its key noun, skipping steps 2–3.
- **The choices**: the answer plus three of the same kind, so the shape never gives it away:
  prepositions from a common list; verbs from the deck's own verb cards and the other phrases'
  verbs first, then a short list of infinitives; nouns from the deck. Fewer than three → no gap, and
  the card stays a flip card. Seeded by the deck's topic, so a card asks the same thing each time.
- **Grading** (`CardDeckView.answerGap`): the pick sets `isFlipped`, so the mode's rating row
  appears. Quiz and Leitner take right/wrong as the result; Anki takes a wrong pick as Didn't
  know and leaves Hard/Good/Easy to the learner after a right one. Auto-advance waits 0.9 s and only
  after a right pick. A re-queued card asks afresh (the view's id carries `requeueCounts`).
- The example sentence stays hidden until the gap is answered (it would give the word away).
- `CardStudyPrefs.phraseGapsKey` ("Gaps on phrase cards"), default on; the setup screen shows the
  toggle only for a deck with phrase cards. Gaps are dealt in `beginSession` and, for resumed or
  auto-started sessions, on appear.

## Where phrase cards come from

- **Highlighting** in a document, handout or job ad (already there; now stored as phrases).
- **"Save phrase"** in a story, the read-aloud player, a job ad or a chat: the sheet has "Also add
  to …", on by default (`PhraseDeckTarget`): the story's deck, the job ad's deck, or for chats the
  one "Phrasen" deck (`PhraseDeckStore`, id from `SyncSingletonDecks.deckID` so two devices
  converge). With it on, a scenario is optional; the phrase still goes to the phrase library.
- **The lesson's answer key** (`KeyPhraseExtractor`, the Wörter sheet's "Wortgruppen"): a
  numbered exercise item with its blank filled by her answer. A letter becomes its option's text
  ("eine Störung" + D = beheben). An English prompt becomes the back ("to resolve faults" →
  "Störungen beheben"). Her whole-line examples are taken as they are. Skipped: a blank after a
  finished sentence or question (an answer slot), a bare letter, a stray option letter glued onto
  the line, single words, more than eight words. Sentences start unticked. On the IT workbook: 29
  (Übung 02's six noun + verb chunks, Übung 09's six with English, Übung 13's frames, sentences
  from 03, 04 and 15). `scripts/worksheet_probe.sh <pdf> --phrases` prints them.
- **German-explanation tables** (`VocabListParser`, `Page.isGloss`): under a header like "In der
  Anzeige | Einfach erklärt", "Formulierung | Bedeutung im Lerntext", a German | German row is a
  phrase with her explanation as its sentence; the tutor fills the English. A row whose right side
  reads English is paired as usual ("Wort | Bedeutung" heads ordinary lists too), a one-cell
  line under such a table is its note, never a row, and the header is a header even when a gloss
  table is already running (an iPad once turned it into a phrase). A gloss row only becomes a card
  once the tutor has given it English of its own (`DocumentDeckService.makesCard`): "Python" →
  "Python" is left out, and the builder says how many. The table rebuild (`OCRTableLayout.tableRows`,
  and the probe's copy of the gate) keeps such a page although its right column isn't English. On
  the IT workbook pages 17–19 now switch themselves on; the twelve other sheets in ~/Downloads read
  exactly as before.
- **"Make this sentence a card"**: a button beside a card's example sentence (saved decks, with a
  tutor on the device) opens the word inspector on it; saving adds a phrase card to the deck
  (`DeckCardAdder`: deduped by `CardKind.matchKey`, kind by `CardKind`).

## Tests

`german-ai-flashcardsTests/CardKindTests.swift`: the rule's cases, repair, the validator never
gendering a phrase, the article game, chat matching, the translation position fallback.
`WordClassInferenceTests.aPhraseRowIsStoredAsAPhraseWhateverItsTag` covers `merge`.
`PhraseGapPlannerTests`: where the gap goes, the choices, seeding, too few → no gap;
`PhraseGapCardRenderTests` renders the face before and after a pick to PNGs (path printed).
`WorksheetKeyReaderTests` covers `KeyPhraseExtractor`; `VocabGlossTableTests` the gloss tables.
