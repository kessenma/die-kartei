# Flashcards from a document

**What:** a deck from a document instead of a topic. A teacher's vocabulary sheet is paired into
cards automatically (with the sheet's ✓ "study for the quiz" marks kept, so "only the marked words"
is one toggle); in a story, a handout, or any other text the learner highlights the phrases they
want and each becomes one card. The tutor translates whatever came without English, and **a card
never has an empty English side**: a row the tutor can't translate is left out, and the learner is
told how many before anything is made (`makesCard`, below). A sheet printed
with more than two columns keeps what they say: the teacher's example sentence lands on the card,
and a noun whose plural is on its own line gets a "Plural: die Computer" caption. A document of
several pages shows a pill per page, the ones that read as a word table already on, and a field to
type the pages instead. The document comes from a file, a photo, a **link**, or pasted text, and
the deck keeps it so it can be opened again from the deck screen.
Reached from Vocabulary ▸ *Flashcards from a Document*, the Create screen's "Or from a document"
section, a course page (*Add a flashcard deck*), and a class handout (*Make a deck from this
handout*). A deck can belong to a course.

**Why:** the class handouts a learner actually gets are a story PDF, a vocab list PDF, and a
question sheet. The old path (Reading ▸ Study a Paper) mined a text for single words, one card per
word, with no way to make "in aller Frühe" one card and no way to use the list the teacher already
wrote. This turns the list into the deck it already is, and the story into the cards the learner
chooses. A tutor who teaches from slides sends a 37-page PowerPoint export where the words are on
eight of the pages and the rest is exercises and answers, which is why pages are picked rather than
swallowed whole.

## Pieces

- **`Services/VocabListParser.swift`** — pure Foundation + NaturalLanguage, so it runs on a Mac
  against a real PDF (see below). Per line: explicit separators (tab, `–`, `=`, two spaces) first;
  then two quoted segments (an idiom and its rendering); else every split point between words is
  scored: Apple's language recognizer on each side plus cues (an article, an umlaut, `(pl)` on the
  left; `to …`, `the …`, `old expression:`, `here:` on the right; a split whose left side does not
  look German is penalized, so a wrapped English line is not mistaken for a row; a left side that is
  only an article is vetoed, since "Gift" reads as English and "das Gift, -e poison" must not
  split after "das"; a plural ending ", -e" / ", ¨-er" / ", -" or a gender marker "(f)" closes
  the German column). `VocabForms.split` spells the plural out ("Gifte", "Häuser", "Äpfel") so it
  is found in a text. Lines read as
  German-only wait for the line that carries their English; English-only lines extend the row
  above. `Result.listConfidence` (rows per content line) tells a list from prose, so the builder
  opens a story in text mode. Guessed splits are flagged (`confident == false`).
  Beyond two columns (a line a rebuilt table joined with tabs): 2 cells are the pair the
  explicit-separator path already made; 3 are that pair plus the sheet's **example sentence**,
  with the last two swapped only on a clear margin, so a sheet ordered `Wort | Beispiel | Meaning`
  still lands right; 4, 6, … are that many pairs side by side, which is how a Wortliste prints two
  blocks on one line. A cell holding nothing but a plural mark ("-¨er", "-nen") is folded back onto
  the noun it belongs to rather than read as a column. `VocabForms.pluralPair` splits a first cell
  that wrapped onto its plural ("der Computer die Computer") into word and `forms` caption, and is
  kept deliberately narrow — four tokens, two articles, no slash — so a teacher's own
  "der Kieselstein/ die Kieselsteine (pl)" is left whole for `VocabForms.split` and the handout
  glossary.
  A page with three or more tab-joined lines is read in **table mode**: headers (every cell a
  header word) and furniture (a `©` line, an e-mail, a long unspaced code with digits) are skipped
  without costing `listConfidence`, and a one-cell line is slide prose — never a row, and above all
  never a pending German column that would glue onto the next row. A real row whose two columns
  happened to touch earns its way back in on a confident `.mixed` split. A row needs a word of at
  least two characters on each side, which turns away a contents table pairing "Üben" with "18–33"
  and a slide titled "Geräte und Zubehör I" splitting off a lone "I"; a cell holding `___` is an
  exercise blank, not a word. `isUsable` also turns away, in table mode and reading order alike: a
  footer on either side (`©`, an e-mail, a deck code), a German side ending on preposition +
  article ("Tätigkeiten in der | IT", a slide title broken over two cells), two numbered answer
  columns side by side ("1 Anforderungen | 1 Berlin" on a Lösungen page), and an **English side
  that is German** (`readsGerman`): an umlaut or ß, or three words or more the recognizer puts at
  0.8 German or above, with anything in brackets left out first ("to doubt (ich zweifle an der
  Wahrheit …)" is English). One word can't decide it: alone, "bonnet" reads 0.94 German. That is
  what keeps a note split on its "=" ("Nomen mit Artikel lernen. Zweite Zeile: Plural. „—“ = in
  diesem Lernkontext ohne Plural.") from becoming a card on every noun page, and it means a
  German | German table without a gloss header (below) gives no rows. In reading order a dropped
  line still counts as content, and an English line after it is its tail, never glued onto the row
  before.
  `pages(_:)` reads the sheet one `[Seite N]` at a time, so nothing dangling at the foot of a page
  reaches the head of the next, and every row carries the page it came from. `parse` is literally
  `fold(pages(_:))`, summing the raw counts rather than averaging, so `listConfidence` keeps meaning
  "rows per content line"; `fold(_:)` is public so a caller that already has the pages (the builder)
  answers "does this read as a list?" without reading the document a second time. A test pins the
  two to the same answer. `Page.looksLikeVocab` is the auto-select test: a list whose right column reads
  English (`englishShare`) **and** whose left column reads German (`germanShare`). Both take the
  larger of a per-row vote and the column read as one text — a lone "computer" or "laptop" reads
  near 50/50, a column of them does not — so a sheet that already passed cannot start failing.
  A page whose every row is a guessed split doesn't switch itself on either (a contents page read in
  reading order guesses all its lines; no real vocabulary page in the corpus has a single guess).
  A German | German table under a header like "Einfach erklärt" or "Bedeutung im Lerntext" is a
  gloss table (`Page.isGloss`, docs/PHRASES.md); its header is a header wherever it turns up, even
  inside a gloss table already running. `VocabForms.pluralPair` also takes a borrowed ending
  swapped for -en ("das Benutzerkonto die Benutzerkonten", Museum → Museen, Thema → Themen).
- **`Services/OCRTableLayout.swift`** — Vision reads a bordered table a column at a time (all the
  German, then all the English), which the parser pairs into a few cards holding half a column
  each. `PhotoOCRService` hands every recognized line with its box to `OCRTableLayout.text`, which
  rebuilds the rows from position: columns are lines sharing a left edge; on a padded table a
  line close under another is a wrapped cell's second line, unless the column beside shows one
  cell above and another below (then it is a row break); each first-column cell gathers the cells
  it overlaps; columns are joined with a tab. The rows are used only when they parse as a list
  whose right side reads English and at least as well as Vision's order, so prose keeps Vision's
  order. Covers photos, the camera and scanned PDFs (text-layer PDFs never reach OCR). A scan's
  `-"e` / `-*e` plural mark is tidied back to `-¨e`. The sheet's ✓ column is not read by OCR.
- **`Services/DocumentDeckService.swift`** — the tutor's two jobs (`pair(lines:)` for a list the
  parser misread, `translate(_:)` for rows without English, both batched `deutsch = english`
  prompts) and `save(...)`: a word the sheet lists twice (a Wortliste repeating what the lesson
  pages taught) is **one card that gathers what each mention had** — the later one fills only the
  holes in the first, so it does not matter which came first — and `includeExamples` follows
  whether any card got one. **`makesCard(_:)` is the one gate every saved row passes** (`merge`
  applies it): German, and English of its own — not blank, not letterless ("—", "?"), not German
  (`readsGerman`: a sheet's note, or a tutor answering in German), and not the German again when
  there is no article to teach ("Python" → "Python" is left out, "der Server" → "server" stays).
  The builder counts with the same gate: rows the tutor will translate are counted as cards, rows
  without English of their own are counted as left out, and the line under *Make the deck* says
  both. When the tutor leaves rows untranslated, their English is written back to the list, they
  are marked left out (placeholder "No English: left out", not sent to the tutor again), the bottom
  of the list says how many, and the deck waits for a second tap — the learner can type the
  missing English first. An empty English field reads "Tutor translates" when a tutor is on the
  device, so a blank row never looks like a finished card. `SavedDeck` with `generatorRaw = "document"` (`Kind.document`,
  browsable, `doc.plaintext` badge) and `courseIDRaw` when a course was chosen. A document brought
  in from outside (file, photo, link, paste: `DocumentDeckDraft.keepsSource`) is kept with the deck
  as `sourceText` + `sourceFile` (in `ClassMaterialStore`, so it syncs like a handout's original),
  which is what lets it join a course later as a handout **and** be reopened from the deck itself
  (`SavedDeck.hasSourceFile` / `sourceFileURL`, `DeckSourceDocumentRow`); decks made before this
  kept only their cards. Deleting the deck in the Library deletes its file. The model is loaded
  only when there is something for it to do; a complete sheet becomes a deck with no model in memory.
- **`Features/DocumentDeck/DocumentDeckImportView.swift`** — sources (PDF incl. scans via
  `ScannedPDFReader`, photo library, camera, **a link**, paste) plus "Your documents" (class
  handouts, papers), or a `prefilled` draft that opens the builder directly. `DocumentDeckDraft` =
  title + text + source. *From a link* (`DocumentLinkImportView`) downloads the PDF with
  `WebTextExtractor.downloadPDF` and reads its bytes through `PDFTextExtractor.extract(from:Data)`,
  so page pills and the extra columns work exactly as for a picked file. The download checks the
  `Content-Type` and the `%PDF-` magic and caps the size: a share link, a cloud drive or anything
  behind a login answers a plain GET with an HTML page and a 200, and `WebError.notAPDF` says to
  save it as a PDF in Safari and use **PDF file** instead. A link that really is a web page falls
  back to `WebTextExtractor.fetch` and opens the builder in text mode, so a page of words works too.
  No consent gate: the analogous typed-URL fetch in Papers has none, and nothing of the learner's
  is sent anywhere.
  The file is read **once** — the bytes come out of the security-scoped URL in the importer's
  callback, and the parse takes the `Data` overload rather than re-opening the URL — and the parse
  itself runs off the main actor (`readPDF`), with a "Reading the PDF…" row while it does.
- **`Features/Cards/CardDeck/DeckSourceDocumentRow.swift`** — *Open the original* and a share
  button on the deck's setup screen, beside `MacPictureHandoffRow`. Quick Look rather than a
  `PDFView`: it is the one opener already working on both platforms, and it shows a photo-sourced
  deck's `.jpg` with no second code path. The Library's `DeckLinks` also gives a document deck a
  "From a PDF" / "From a photo" origin line, which nothing else in the Library pointed at before.
- **`Features/DocumentDeck/DocumentDeckPageStrip.swift` + `Services/PDFPageThumbnails.swift`** —
  **Seitenbilder**: each page of the picker as a small picture of itself, because "is page 23 the
  Wortliste?" is a question only a look at page 23 answers. The strip shows the pages the parser
  **read**, not every page of the file: the typed range, All/None and which rows reach the deck are
  all defined over `pages`, and a page with no text has no rows to contribute, so offering it would
  be offering nothing. Where the two counts differ the footer owns up to it ("Only pages with text
  can be read: 8 of 37 pages carry words"). The numbers are addressable because `[Seite N]` is the
  real 1-based PDF page index on both paths (`extract` writes `index + 1`; `ScannedPDFReader`
  numbers the first twelve rendered pages, which are pages 1…12).
  `PDFPageThumbnailRenderer` is an `actor` that builds its `PDFDocument` inside itself and never
  hands it out — the only PDFKit thread-safety claim worth relying on — and being an actor it
  **serializes**, so a fast scroll over 37 cards can never put 37 bitmaps in memory at once.
  `PDFPageThumbnails` in front of it caches at the card's own width (76 pt) with a 24-entry bound,
  and `purge()` runs when the picker goes away **and before either tutor job**, because the builder
  is one button from loading a multi-gigabyte model (`docs/MEMORY.md`: one heavy resident at a
  time). `PDFPage.thumbnail(of:for:)` does not document its scale, so a test pins it: it renders at
  **1x**, 76 pixels for 76 points, which puts the whole 24-page cache under a megabyte rather than
  the ~21 MB a 3x render would have cost. Eviction goes by when a page was rendered, not when it
  was last looked at — `thumbnail(page:)` is read from `body` and must not mutate observed state —
  which for a strip scrolled one way is the same order anyway. `init?(draft:)` is the whole fallback switch — it returns nil unless the draft really
  carries PDF bytes, so a handout or paper from "Your documents", a paste, a fetched web page and a
  photo's JPEG all keep the plain numbered pills.
  The magnifier opens `DocumentPagePreviewSheet`: one page at reading size through the same actor,
  `‹ ›` and swipe between pages, and the page's own *Use this page* / *Drop this page* so the
  decision is made while looking at it. An in-app page rather than Quick Look, which cannot be
  opened at page 23 and would mean writing the draft's bytes to a file before the learner has
  committed to anything; Quick Look stays right where it already is, on the whole document once a
  deck exists (`DeckSourceDocumentRow`).
- **`Features/DocumentDeck/DocumentDeckBuilderView.swift`** — deck name, course picker, a
  segmented **Word list / From the text**. Word list: editable rows, orange dot on guessed splits,
  swipe right to swap sides, "Only marked rows (✓)", *Read the list again*, *Let the tutor pair the
  list*. A row that came with an example or a plural shows them read-only on a second line, so the
  two text fields stay the only things to tap; one *Keep examples and plurals* switch decides for
  the whole deck, and `makeDeck` strips them there rather than passing a flag to `save`.
  **Seiten · Pages** (more than one page only) is `DocumentDeckPageStrip`: a picture of each page
  when the draft carries a real PDF, a `FilterPill` with its row count when it does not, the pages
  that `looksLikeVocab` already on, plus a field that reads and writes the same selection as runs
  ("8-15, 34-35") and All / None (`pageSelection` / `describe`, both tested). `rows` always holds
  every page; the strip and the ✓ toggle are filters over it, so an edit survives switching a page
  off and on. A row the learner typed has no page and is always in.

  There are now **two** row predicates and they are not interchangeable. `isOnPage` is what the deck
  is made of — every count, `cardCount`, the merge, both tutor jobs. `isVisible` is what the list
  draws: the same set minus the repeats when they are hidden, and **only** the `ForEach` and its
  delete offsets may use it. Hiding a repeat must never reach the deck's row set, because `save`
  merges a repeat into the first mention to fill its holes, so dropping it would lose that mention's
  example or plural. `mode` opens on the list when
  **any page** reads as vocabulary, not when the whole document does: a 37-page module is mostly
  exercises and scores 0.28 overall while eight of its pages score 1.00. The tutor's *pair the list*
  takes only the pages that are on, flattens the tabs (its prompt promises lines "ohne
  Trennzeichen"), and retires the pills, since it has replaced the page structure. The button counts
  the **cards the deck will hold**, not the rows: with a Wortliste on, the Shohdy module shows 80
  pairs and 40 cards, and promising 80 would be a lie the merge-dedup then corrects.
  **Dubletten** — a word the sheet lists twice (a Wortliste repeating what the lesson pages taught)
  wears a badge on every mention after the first: "2× S. 8", the ordinal and the page the first one
  was on, or "2× dabei" when the first was a hand-typed row. `repeatMarks(in:)` is a static, pure
  walk keyed on `DocumentDeckService.key` — **the same key `save` merges on and `cardCount` counts
  with**, so the badge can never promise something the deck contradicts — held in state and
  refreshed on a change to the rows, the pages or the ✓ filter rather than recomputed per render.
  A *Hide repeats* toggle appears when there are any, and the footer says a word listed twice becomes
  one card either way. Accepted consequences: a repeat is a repeat only among the rows on screen, so
  switching a page off (or the ✓ filter on) can promote one to being the only mention and its badge
  goes away; and deleting a first mention while repeats are hidden reveals one of its repeats, which
  loses nothing and does not move the card count. The badge is in the accent, never orange, because
  orange on the same row already means "the German/English split was a guess".

  **Wortart** — every row carries a word class, shown as a tappable chip (`WordClassChip`) and
  stored on the card. `WordClassInference` asks the bundled dictionary first
  (`WiktionaryValidator.partsOfSpeech`), then reads the row's own shape: an article → Nomen, a lone
  capitalized word → Nomen, an English side opening "to …" → Verb, a lowercase `-en`/`-eln`/`-ern`
  → Verb. Where the dictionary also offers a noun reading the **capital** decides, and that matters
  more than it sounds: German nominalizes freely, so `wiktionary_de.db` has a noun row for "essen"
  (das Essen), "gestern" (das Gestern) and "gut" (das Gut). Preferring the noun reading called every
  one of those a Nomen. A lowercase word with any non-noun reading is therefore not the noun; a
  lowercase word the dictionary knows *only* as a noun still reads as one, since a sheet that wrote
  a noun in lower case is likelier than a dictionary with nothing else to say. Among what is left
  the adjective beats the adverb, because German uses the bare adjective adverbially ("gut",
  "schnell") and the adjective is the one being taught. A phrase like "in aller Frühe" comes back
  nil and wears no tag, which is more honest than guessing; shape alone would call "gestern" a verb
  on its -ern ending, which is why the dictionary goes first and shape is only the fallback for a
  word nothing has heard of. `WordClassTagger` runs the pass twenty
  rows at a time with a `Task.yield()` between chunks and hands back `[UUID: WordClass]` deltas, so
  a batch landing mid-keystroke cannot overwrite what is being typed; it fills only nils, so a
  correction stays corrected. The lookup stays on the main actor because `WiktionaryValidator` is not
  thread-safe (mutable caches, one set of prepared statements, `SQLITE_OPEN_NOMUTEX`), the same
  reason `NounGenderTinter` gives. `pair(lines:)` builds fresh rows and so loses the classes; the
  builder re-runs the tagger after it. `WordClassInference.headword` is the *lookup* form and is
  deliberately **not** `DocumentDeckService.key`: that one answers "are these the same card?" and
  stays the single notion of a duplicate, this one answers "what word is this?" and never compares
  two rows.

  In `save`/`merge`, **an article always wins**: `der Tisch` is a noun because the sheet says so, a
  row with no article takes whatever was inferred, and an article arriving on a later mention
  upgrades a card the first mention only guessed at. Inference only ever speaks where there is no
  article. An inferred noun *is* stored, so `DeckStore.session(for:)`'s `validateAndCorrect` can
  fill in an article and a sheet deck starts working in the der/die/das drills — the dictionary only
  writes an article for a word it knows, and the chip is the escape hatch. The four stored strings
  ("noun", "verb", "adjective", "adverb") are exactly what `WordTypeFilter`,
  `WiktionaryValidator.evaluate` and `GoetheWordType.normalize` read, and a test pins them.
  `WordClassPalette` is now the one place a word class becomes a colour (verb blue, adjective
  purple, noun green, adverb pink), replacing the same switch written out in `FullscreenCardView`,
  `CardDeckView+CardContent` and `GoetheEntryRow`. It sits outside `GrammarPalette` on purpose:
  that file keeps gender and case codings apart so a screen can show both without one colour meaning
  two things, and a third meaning for blue and green would undo it.

  From the text: `SelectableGermanText` with the selection action relabelled **Add as card**
  (`translateActionTitle`), double-tap adds a word, picked words are washed in color. *Make the
  deck · N cards* translates first when a tutor is on the device, otherwise skips the untranslated
  rows and says so.
- **Course link** — `SavedDeck.courseIDRaw` (additive). A course page lists every deck on it (its
  own word deck, document decks, linked Library decks via `CourseDeckLinkView`), swipe to unlink.
  The Deutschkurs hub lists all course decks with their course.

## Nothing freezes while a document is read

A 37-page slide export used to lock the screen from the moment it was picked until the rows
appeared. The cause is a build setting, not a slow parser: the target compiles with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so an unannotated `enum PDFTextExtractor` *is*
main-actor and its work could not run anywhere else. `scripts/vocab_sheet_probe.sh` compiles that
file with no default isolation at all, which is why the probe was always fast and never showed it.

`PDFTextExtractor` is now `nonisolated`, and four blocking points went with it:

- **The text extract**, synchronous in `handleFile`. Now one `Task.detached`, behind "Reading the
  PDF…". The same hop went into `DocumentLinkImportView.fetch`, which was inside a `Task` but still
  on the main actor, and into the three other screens that import a PDF
  (`PaperListView`, `ClassMaterialImportView`, `JobPostingImportView`).
- **The builder's parse**, synchronous in `onAppear` — and run twice, because the `looksLikeList`
  fallback re-read the whole document. Now `.task`, one detached hop, and `VocabListParser.fold` on
  the pages already in hand.
- **`ScannedPDFReader`**, which rendered all twelve pages at 1400 points *before* its OCR loop:
  about 130 MB resident at once, on the main thread. Now one page per iteration, rendered off the
  main actor, with the same per-page progress text.
- **The `[Seite N]` strip for the text picker**, a regular-expression pass over the whole document
  that ran inside `body`, so a long document was scanned on every render. Now `readingText(_:)`,
  computed once with the parse.

The invariant: **the builder never shows its empty state while it is still reading.** It showed
"No word pairs found in this document" for as long as the parse took, which is the opposite of the
truth. While `isParsing` the rows section says "Die Liste wird gelesen…", the header drops its
count (a count of 0 is a lie), and the buttons that would fight the parse are off.

Picking pages needs none of this: `rows` always holds every page, and the pills are filters over it,
so switching a page on or off involves no parse at all.

## Verified against the real sheet

`scripts`-free: compile the parser on a Mac with a 20-line harness (`swiftc VocabListParser.swift
main.swift` with PDFKit reading the PDF) and print the rows. On the "Hänsel und Gretel"
Vokabelliste (2 pages, 32 rows, wrapped cells, ✓ marks) every row pairs correctly, 3 are flagged as
guesses (all right), the title is picked up, `listConfidence` 0.84; the story and the question
sheet score 0.09 / 0.05 and open in text mode. The same text is the `-classNotes.debugOpen builder`
fixture (`ClassNotesDebugSeeder.vocabSheetText`).

The scan path is checked the same way: render each page 1400 pt wide (as `ScannedPDFReader`
does), run `RecognizeTextRequest` with the app's settings, and feed the lines to
`OCRTableLayout.text` + the parser. On the three class sheets (Dornröschen 48 rows, Hänsel und
Gretel 32, Schneewittchen 42) every row pairs, none flagged; before, Vision's order gave 6 / 3 / 22
rows of whole columns run together. A borderless list drawn to an image-only PDF pairs 10 of 10.
The two stories, the Lesejournal and a letter come back byte-for-byte in Vision's order.

## Verified against a PowerPoint vocabulary deck

A tutor's slide export (`M01_L01_Vokabeltraining.pdf`, 37 pages) is the three-column case:
`Wort und Plural | Meaning | Beispiel`, the noun cell wrapping onto its plural, 40 words on eight
pages, 16 Übungen and two Wortliste pages around them.

```
scripts/vocab_sheet_probe.sh ~/Downloads/M01_L01_Vokabeltraining.pdf
scripts/vocab_sheet_probe.sh <pdf> --page 8          # cells and rows in full
scripts/vocab_sheet_probe.sh <pdf> --touch-gap 0     # as it read before the touch-merge
scripts/vocab_sheet_probe.sh <pdf> --rows            # every row of the pages that start on (diffable)
```

It compiles the real `VocabListParser`, `OCRTableLayout` and `PDFTextExtractor` against the file and
prints a line per page (`rows · contentLines · listConfidence · englishShare · looksLikeVocab`), the
gate internals, and the cards the deck would hold. On that PDF: **pages 8–15 and 34–35 selected,
each lesson page `listConfidence` 1.00, 40 cards, 40 with an example, 20 with a plural, 0 guessed
splits.** Pages 16–17 (German on both sides), the 16 exercise pages and the contents table are all
left off, each by a different test — `germanShare`, the `___` blank, the letterless "18–33".

The measurement that shaped the design is on page 8. Without the touch-merge the meaning cell
overlaps `der Computer` by 11.61 pt and `die Computer` by 11.53 pt, so every noun row is decided by
0.08 pt — it would look like "mostly works" and flip per font and per PDFKit version. Gaps there are
−0.01 line heights inside a noun's cell and +0.26 between two rows, which is the room `pdfTouchGap`
of 0.08 sits in.

The four class sheets are the regression baseline and are unchanged: Hänsel und Gretel 32 rows,
Dornröschen 48, Schneewittchen 42, Rotkäppchen 40, all with no flagged guesses. The two stories and
the Lesejournal select no pages and keep their reading order.

Note the harness runs on macOS PDFKit, which orders a bordered table's lines row by row where iOS
orders them column by column — a green run is necessary and not sufficient, so check the simulator.
`VocabRealSheetTests.realSheetRowsMatchTheMacProbe` does that: put the PDF in
`WORKSHEET_FIXTURE_DIR` (outside the repo, like the worksheet tests) with the probe's `--rows`
output beside it as `<name>.vocab-rows.txt`, run with `TEST_RUNNER_WORKSHEET_FIXTURE_DIR=<folder>`,
and on a mismatch the iOS reading is written beside it as `<name>.ios.vocab-rows.txt`.

## Verified against an IT workbook (Nov 2026)

`Kyle_SEC12_E01_A1_IT_Stellenangebote_Workbook02.pdf` (62 pages; noun pages 9–15, verbs 16,
German-explanation tables 17–19, Lösungen 43–51, Wortlisten 52–55). Before: pages 7 (the contents)
and 9–19, 52–55 switched on, 63 cards plus junk — the contents page's 9 rows, the note under every
noun table (8 cards with German on the English side), "Tätigkeiten in der | IT", and
"das Benutzerkonto die Benutzerkonten" as one phrase. After: pages 9–19 and 52–55, **51 cards, 40
with an example, 20 with a plural, 0 guessed**, plus the 15 gloss rows the tutor translates. (51 is
40 words plus 11 the merge doesn't recognize as repeats: "die Berufserfahrung —" on a lesson page
and "die Berufserfahrung" in the Wortliste, "die Kenntnisse (Pluralform)" and "die Kenntnisse".) The iOS
simulator reads it row for row like the Mac (`VocabRealSheetTests`). On an iPad the header
"Formulierung | Bedeutung im Lerntext" once came through as a phrase; neither the Mac nor the
simulator reads page 18 that way, so the header test now holds inside a running gloss table too.
Of the 22 other PDFs in ~/Downloads (the fairy-tale lists and stories, M01, the Präpositionen and
Verben sheets, Wortliste 02), 21 read row for row as before (`--rows`, diffed); the Präpositionen
module's title slide (page 3, a course dashboard, already switched on before) loses its two rows
pairing German topics with German ("Wetter & Small Talk | Essen & Küche"). A first draft of the
German test cost the Schneewittchen list "hernach | old expression: danach (after that)" and the
Verben list "to doubt (ich zweifle an der Wahrheit …)", hence the opener and bracket rules.

## A story read with its vocab list

A class handout can be read with a deck as its glossary (`ClassMaterial.glossaryDeckIDRaw`,
additive). The handout page's **Vokabeln · Vocab** section picks the deck (any deck on the course
with cards; defaults to the newest document deck the first time) and shows how many of its cards
were found in the text. `HandoutGlossary` turns the cards into `GlossaryEntry`s, one per listed
form (`VocabForms.split`: "der Kieselstein/ die Kieselsteine (pl)" → two forms; "zündete…an" →
"zündete"), and runs the story reader's `StoryGlossaryHighlighter` (word, lemma, inflections,
verbatim phrases). Result: dotted underlines in the text, and the inspector answers a tap from the
list (`knownTranslations`, the list winning over an earlier model lookup). Measured on the Hänsel
und Gretel story with its sheet: 31 of 32 entries found (22 before the form split).

**English inline** (`InlineGlossMode`, `@AppStorage("handout.inlineGlosses")`, Off / First time /
Every time): `SelectableGermanText.inlineGlosses` inserts " (english)" after each glossed word or
phrase in a smaller secondary face, tagged `NSAttributedString.Key.inlineGloss`; a tap on a gloss
is ignored and a selection's text drops gloss runs (`plainText(of:in:)`), so Translate never
carries the English along. Only the handout reader sets a mode: the read-along and gender ranges
of the chat and story callers are computed against the plain text and would drift. Glosses are
shortened to the first sense and 60 characters. `JobReadingDecorations` carries `glossary` and
`inlineGlosses` to the text surface.

Debug: `-classNotes.debugOpen story` opens the seeded story with the sheet's deck linked;
`-classNotes.debugOpen builder` raises the builder over the real two-column Hänsel sheet and
`-classNotes.debugOpen slides` over a five-page three-column slide module, which is the one that
shows the page strip — its draft carries a PDF synthesized from the same text
(`ClassNotesDebugSeeder.slideDeckPDF`, CoreGraphics rather than `UIGraphicsPDFRenderer`, which has
no Mac stand-in), so the page thumbnails have something real to render with no file to import.

## Later

- Example sentences for cards picked out of a running text (the sentence the phrase was highlighted
  in). A sheet that prints its own examples already keeps them.
- A question sheet (`Lesejournal`) as a quiz: the comprehension questions are already extractable.
  (The Übungen in a slide module are built: homework from the PDF itself, `docs/WORKSHEETS.md`, not
  the exercise framework, whose items need a known answer.)
- `WiktionaryValidator` behind an actor, so the word-class pass can run off the main actor
  entirely. It is chunked with a yield today, which should be invisible at 40 rows; the 400-row case
  (two Wortliste pages, a cold database) is unmeasured. Six call sites, so it is its own change.
- Page thumbnails for the photo and multi-page scan paths. A photo is a JPEG, not a PDF, and the
  scan path throws its rendered pages away after OCR.
- Opting the photo/OCR path into the touch-merge, once Vision's boxes can be trusted that finely.
- "Open in Die Kartei" for a PDF now files it as a class handout (`IncomingHandoutSheet`,
  docs/WORKSHEETS.md); a document deck straight from an opened PDF would branch there too.
