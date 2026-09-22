# Deutschkurs — class notes, handouts, homework

**What:** a Home entry (the second wide tile under the six category tiles, beneath Job prep) for
learners who take a German class somewhere else: a semester course at a university, a private
tutor, a Volkshochschule evening class. The app keeps what the class produced. One **course** owns
dated **entries** (the grammar covered, topics, new words, notes, homework) and **handouts** (a
PDF, a photo of a page, or pasted text, read word by word with the same toolkit as a job posting),
and builds one **flashcard deck** per course from the words logged and saved. Homework stays on
the front page until it is ticked off.

**Why:** the app is a self-contained tutor, but many learners are also enrolled somewhere, and
the words and grammar their class introduces this week are exactly what they should be practising.
Two courses at once are the norm, not the exception (the designing learner has a semester course
and an independent HR-German tutor), and they are organized differently: the semester course by
chapter and week, the tutor by session and goal. So the course is a first-class object rather than
a name on an entry, and a dated course labels its entries "Woche N".

**Feasibility:** high; the capture side recombines what ships. Import is `PDFTextExtractor` +
`PhotoOCRService` + a paste screen, with one addition (scanned PDFs, the common handout, are now
read page by page instead of rejected). Reading is the job-posting text surface and word
inspector. The deck is a `JobDeckStore` twin keyed on the course.

**Not built yet (the follow-on):** the tutors do not read any of this. `ClassEntry.tutorContext`
renders an entry for a prompt and is the hook; see "Later".

## Data model

Three `@Model`s, registered in the schema. Every property is defaulted or set in `init` (additive
migration; the container deletes the store on a failed one). Inverses are declared on the to-many
side only, as `SavedDeck.cards` does.

**`Models/ClassCourse.swift`**

| field | meaning |
|---|---|
| `name`, `kindRaw` | the course, and `Kind`: `course` (group) / `tutor` / `selfStudy` |
| `teacher?`, `teacherEmail?`, `courseURL?`, `goal?` | who teaches it (+ a `mailto:` link), the course page online (Moodle, Canvas; `pageURL` assumes https), what it is for |
| `levelRaw?` | `CEFRLevel` the course is pitched at |
| `startDate?`, `endDate?` | a semester has dates; `weekNumber(for:)` and `currentWeekLabel` ("Woche 7 von 20") derive from them |
| `isArchived` | finished: off the hub's front page, notes and deck kept |
| `deckIDRaw?` | the course's one `SavedDeck`, created on the first word saved |
| `sortOrder` | hub order |
| `entries` | cascade → `ClassEntry` |

**`Models/ClassEntry.swift`**

| field | meaning |
|---|---|
| `date` | the class day, stored as `startOfDay` (so "today's entry" is an equality) |
| `title` | optional; `displayTitle` falls back to "Woche N" or the date |
| `grammarFocusRaws`, `topics` | `GrammarFocus` raw values the class covered; free-text themes |
| `wordsData?` | `[ClassWord]` (`german`, `english`, `addedToDeck`); `ClassWord.parseList` reads a pasted list |
| `notes` | free text |
| `homework`, `homeworkDue?`, `homeworkDone` | the assignment; `hasOpenHomework`, `homeworkIsOverdue` |
| `course` | the owning `ClassCourse` |
| `materials` | cascade → `ClassMaterial` |
| `tutorContext` | the entry as a prompt block (German labels, ≤ 2000 chars); not injected yet |

**`Models/ClassMaterial.swift`** (the `JobPosting` twin)

| field | meaning |
|---|---|
| `title`, `sourceKindRaw` | `pdf` / `photo` / `paste` |
| `text` | the handout as text, `[Seite N]` markers stripped (`JobPosting.cleanedText`) |
| `snapshotFile?` | the original in `ClassMaterialStore` (`Application Support/ClassNotes/<UUID>.pdf|.jpg`) |
| `lookupsData?` | `[GlossaryEntry]`, newest first, via `lookups` / `recordLookup` |
| `modelRaw?` | the tutor that answered the lookups |
| `entry` | the owning `ClassEntry` |

Related additions: `SavedDeck.Kind.classNotes` (`generatorRaw == "class"`, browsable, shown with a
graduation cap in the Library; also added to `DeckStore.resumeSession`); `CameraPickerView` moved
from `PhotoScanListView` to `Features/Shared/`; `PDFTextExtractor.pageImages(from:limit:width:)`;
`Services/ScannedPDFReader` (renders up to 12 pages and runs `PhotoOCRService` over each).

**Deleting** cascades course → entries → handouts, but the files are ours: `ClassEntryStore`
(in `ClassNotesHubView.swift`) deletes every snapshot before `context.delete`. Decks stay.

## Screens — `Features/ClassNotes/`

- **`ClassNotesTile`** (`Features/Home/`): the full-width card under Job prep. Brown,
  `graduationcap.fill`, glyph `▤` on Grundform. Pushes the hub.
- **`ClassNotesHubView`**: Courses (one row each → course page; "Add a course"; with none, a
  hero "Log your first class" that creates the course with the entry), then two hero rows (Log a
  class → entry editor; Add a handout → import, asking which course when there are several, into
  the course's entry for today), open Hausaufgaben across courses (checkbox rows), Diese Woche
  (rolling 7 days, swipe to delete), Kursdecks (launch the card player), finished courses.
  Toolbar `+` and `?` (`ClassNotesHelpSheet`). `ClassEntryStore` holds fetch-or-create-today and
  the three deletes.
- **`ClassCourseEditorView`**: name, kind (segmented), teacher, goal, level, dates toggle; for an
  existing course, Finished toggle and Delete (confirmed; `onDeleted` pops the course page).
- **`ClassCourseDetailView`**: header, action rows (log / handout / study deck), open homework,
  entries grouped "Woche N" (dated) or by month, handouts, Edit.
- **`ClassEntryEditorView`**: course picker (menu when several; inline name when none; fixed
  when editing), date, title, grammar chips (`WrapLayout` + `FilterPill` over `GrammarFocus`),
  topic chips, word rows (German / English, add, delete, "Paste a list" → `ClassWordListPasteSheet`),
  notes, homework + due date. Save is off while the draft is empty. `classNotes.lastCourseID`
  remembers the course.
- **`ClassEntryDetailView`**: header (date, week pill, course), Behandelt (grammar pills open
  `GrammarLessonSheet`; topic pills), Neue Wörter (speak, "Add N to the course deck" for complete
  words, Study the course deck), Notizen, Hausaufgabe (checkbox), Handouts (+ Add a handout), Edit.
- **`ClassMaterialImportView`**: PDF (`fileImporter`; a `looksScanned` file goes through
  `ScannedPDFReader` with a page-by-page progress row), photo from the library or the camera
  (`PhotoOCRService`; the JPEG is the original), paste. All three → `ClassMaterialReviewView`
  (title + text preview, "Attach to this class") → saved under the entry.
- **`ClassMaterialDetailView`**: header (source pill, word count, entry, "Open the original" via
  Quick Look), the text surface (`JobPostingTextSurface` + `WordInspectorSheet`, built by
  `ClassWordInspector`), Unbekannte Wörter (speak, swipe to remove, Add all to the deck),
  Flashcards (+ *Make a deck from this handout*). **Vokabeln · Vocab**: the deck this text is read
  with, its words dotted in the text and answered without the model, English inline on request
  (`docs/DOCUMENT_DECKS.md`). *Translate the whole text* / *Read in English or side by side* →
  `HandoutTranslationReaderView`. Phrase selection goes through the inspector.
- **`HandoutTranslationReaderView`**: the handout in Deutsch / Beide / English (segmented,
  `handout.translation.mode`). Beide is side by side when `horizontalSizeClass == .regular`
  (iPad), English above German otherwise. Both panes bind one `topID` through
  `scrollPosition(id:anchor: .top)` over a `scrollTargetLayout`, so scrolling either moves the
  other to the same sentence; a tap on a sentence sets it; the ⋯ menu's *Highlight the top
  sentence* (`handout.translation.highlightTop`) tints that sentence in both panes. Without a
  translation the screen offers a tutor picker (downloaded models) and *Translate N sentences*
  with progress and Stop; a stopped run resumes with *Continue translating*.
  `HandoutTranslationService` sends each paragraph as numbered sentences (batches of 8) and
  parses numbered lines; a batch whose numbering breaks is translated as a block, split with
  `NLTokenizer`, and spread over the German sentences (`HandoutTranslation.align`). Saved on
  `ClassMaterial.translationData` (`HandoutTranslation`: paragraphs of parallel sentence arrays)
  after every paragraph, with `translationModelRaw`.
- **`ClassMaterialListView`**: every handout; Library ▸ Reading ▸ Class Handouts.

## Decks

A course can hold any number of decks; `SavedDeck.courseIDRaw` links them (additive column).
- **The course's own word deck** — `ClassDeckStore` (`Features/ClassNotes/`): `"Class: <name>"`,
  `generatorRaw = "class"`, found by `course.deckID`, tagged with `courseID` on creation. `saveWord`
  (feeds `LearnerMemoryService.noteVocabEncounters(source: "class")` unless `storyFeedsCoach` is
  off), `saveWords(of: entry)` (complete words only, marks `addedToDeck`), `saveAllLookups(for:)`.
- **Decks from documents** — a vocab sheet or a handout turned into a deck (`docs/DOCUMENT_DECKS.md`),
  from the course page's *Add a flashcard deck* or a handout's *Make a deck from this handout*.
- **Linked Library decks** — `CourseDeckLinkView`; swipe on the course page to unlink.
The course page lists them all; the hub lists every course-linked deck with its course.

## Debug launch arguments (DEBUG)

- `-classNotes.debugSeed 1` — two courses: "[debug] Deutsch A2 an der Uni" (dated, 6 weeks in,
  3 entries, one overdue and one open homework, a pasted worksheet) and "[debug] HR-Deutsch mit
  Anna" (tutor, goal, 2 entries, a "photo" handout with a drawn page as its original).
- `-classNotes.debugOpen <screen>` — seeds if needed and opens `hub` (or `1`), `course`, `entry`,
  `editor`, `handout`, `story` (the Grimm story with its vocab deck linked), `translation` (that
  story's side-by-side reader; the opening is seeded in English), or `builder` (the flashcard
  builder over the real Hänsel vocab sheet) in a sheet.
- `-classNotes.debugRemove 1` — removes both courses and their files.

Only one presenting argument per launch (see `WhatsNewService`).

## Verification

- `build_sim` clean on the simulator (2026-09-21). The sim can't run MLX, so a word double-tap
  shows "Getting the model ready…" and no translation; persistence of lookups is a device check.
- Flows: Home ▸ All Activities → Deutschkurs tile → hub → Log a class (inline course name on a
  fresh install) → Save → entry pushed; entry → Edit → Paste a list (`Haus = house`,
  `gehen – to go`, `Tisch<tab>table`, `Buch: book`) → 4 rows; Add N to the course deck → deck under
  Kursdecks, the course page, and Library ▸ Decks with the graduation cap; grammar pill → quick
  lesson; Add a handout → paste → review → attach → handout row → reader; PDF via Files (a text
  PDF, then a scan: progress, then text); photo from the library; Open the original → Quick Look;
  homework checkbox on hub, course, and entry; swipe-delete an entry removes its handouts' files;
  Delete course from its editor pops to the hub, deck stays.

## Later

- **Tutors read the class.** `ConversationConfig.classContext` built from the last fortnight's
  `ClassEntry.tutorContext` (and a line in `LearnerMemoryService.briefing`), gated by a
  `classFeedsCoach` setting like `storyFeedsCoach`.
- **Today plan.** "Review this week's class words" (the course deck's due cards) and "practise
  <grammar covered in class>" through `GrammarExerciseService.category(for:)`.
- **Weekly recap** conversation seeded from the course's entries (`FUTURE_FEATURES.md` #7).
- **Tutor course ↔ Job prep.** A tutor course with a job-search goal feeds interview practice
  (`course.goal` + the class words).
- **Handout extras.** The MLX cleanup pass over OCR text (`PhotoOCRService.cleanupText`), a
  `PaperStudyService`-style summary and questions, the PDF reading surface (`JobPostingPDFSurface`
  is document-agnostic), a `StudyDay` time bucket for handout reading. `looksScanned` is a
  whole-document test, so a mixed PDF with one text page skips OCR for the rest.
