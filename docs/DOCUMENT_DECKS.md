# Flashcards from a document

**What:** a deck from a document instead of a topic. A teacher's two-column vocabulary sheet is
paired into cards automatically (with the sheet's ✓ "study for the quiz" marks kept, so "only the
marked words" is one toggle); in a story, a handout, or any other text the learner highlights the
phrases they want and each becomes one card. The tutor translates whatever came without English.
Reached from Vocabulary ▸ *Flashcards from a Document*, the Create screen's "Or from a document"
section, a course page (*Add a flashcard deck*), and a class handout (*Make a deck from this
handout*). A deck can belong to a course.

**Why:** the class handouts a learner actually gets are a story PDF, a vocab list PDF, and a
question sheet. The old path (Reading ▸ Study a Paper) mined a text for single words, one card per
word, with no way to make "in aller Frühe" one card and no way to use the list the teacher already
wrote. This turns the list into the deck it already is, and the story into the cards the learner
chooses.

## Pieces

- **`Services/VocabListParser.swift`** — pure Foundation + NaturalLanguage, so it runs on a Mac
  against a real PDF (see below). Per line: explicit separators (tab, `–`, `=`, two spaces) first;
  then two quoted segments (an idiom and its rendering); else every split point between words is
  scored: Apple's language recognizer on each side plus cues (an article, an umlaut, `(pl)` on the
  left; `to …`, `the …`, `old expression:`, `here:` on the right; a split whose left side does not
  look German is penalized, so a wrapped English line is not mistaken for a row). Lines read as
  German-only wait for the line that carries their English; English-only lines extend the row
  above. `Result.listConfidence` (rows per content line) tells a list from prose, so the builder
  opens a story in text mode. Guessed splits are flagged (`confident == false`).
- **`Services/DocumentDeckService.swift`** — the tutor's two jobs (`pair(lines:)` for a list the
  parser misread, `translate(_:)` for rows without English, both batched `deutsch = english`
  prompts) and `save(...)`: `SavedDeck` with `generatorRaw = "document"` (`Kind.document`,
  browsable, `doc.plaintext` badge) and `courseIDRaw` when a course was chosen. The model is loaded
  only when there is something for it to do; a complete sheet becomes a deck with no model in memory.
- **`Features/DocumentDeck/DocumentDeckImportView.swift`** — sources (PDF incl. scans via
  `ScannedPDFReader`, photo library, camera, paste) plus "Your documents" (class handouts, papers),
  or a `prefilled` draft that opens the builder directly. `DocumentDeckDraft` = title + text + source.
- **`Features/DocumentDeck/DocumentDeckBuilderView.swift`** — deck name, course picker, a
  segmented **Word list / From the text**. Word list: editable rows, orange dot on guessed splits,
  swipe right to swap sides, "Only marked rows (✓)", *Read the list again*, *Let the tutor pair the
  list*. From the text: `SelectableGermanText` with the selection action relabelled **Add as card**
  (`translateActionTitle`), double-tap adds a word, picked words are washed in color. *Make the
  deck · N cards* translates first when a tutor is on the device, otherwise skips the untranslated
  rows and says so.
- **Course link** — `SavedDeck.courseIDRaw` (additive). A course page lists every deck on it (its
  own word deck, document decks, linked Library decks via `CourseDeckLinkView`), swipe to unlink.
  The Deutschkurs hub lists all course decks with their course.

## Verified against the real sheet

`scripts`-free: compile the parser on a Mac with a 20-line harness (`swiftc VocabListParser.swift
main.swift` with PDFKit reading the PDF) and print the rows. On the "Hänsel und Gretel"
Vokabelliste (2 pages, 32 rows, wrapped cells, ✓ marks) every row pairs correctly, 3 are flagged as
guesses (all right), the title is picked up, `listConfidence` 0.84; the story and the question
sheet score 0.09 / 0.05 and open in text mode. The same text is the `-classNotes.debugOpen builder`
fixture (`ClassNotesDebugSeeder.vocabSheetText`).

## Later

- Two-column photos: OCR reads a table column by column at times; the tutor pairing covers it, a
  layout-aware read (Vision's bounding boxes) would do it without a model.
- Example sentences from the source text for each card (the sentence the phrase was highlighted in).
- A question sheet (`Lesejournal`) as a quiz: the comprehension questions are already extractable.
