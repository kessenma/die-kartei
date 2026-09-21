# Job prep — interview practice + studying a job ad

**What:** a Home entry (the wide tile under the six category tiles) that fronts two things: the
interview mode of the conversation feature, one tap from Home instead of a choice inside the
conversation Type picker, and a new **job description study** reader. The reader shows a posting
the way a tutor reads it with you: word by word. Double-tap a word (or select a phrase) to
translate it on-device, every lookup is kept with the posting under „Unbekannte Wörter“, and saved
words build the posting's own flashcard deck. From the posting the learner can start an interview
for it, prefilled.

**Why:** a tutoring session where the tutor and learner read a real Stellenanzeige line by line,
translating what the learner didn't know. Job ads are dense, formulaic German (Aufgaben, Profil,
Wir bieten) that no flashcard topic covers, and they are the text a job-seeking learner actually
has to understand.

**Feasibility:** high; everything is recombined from what ships. The reading toolkit
(`SelectableGermanText` → `WordInspectorModel` → per-document deck + persisted lookups) is the
stories' and is document-agnostic; the posting capture (in-app clipper, PDF snapshot store, URL
dedup) is the interview mode's.

## Data model

`Models/JobPosting.swift` — `@Model JobPosting`, registered in the schema. Every property is
defaulted or set in `init` (additive migration; the container deletes the store on a failed one).

| field | meaning |
|---|---|
| `title`, `company?`, `location?`, `sourceURL?` | what the row and the interview setup show |
| `sourceKindRaw` | `link` / `pdf` / `paste` / `chat` |
| `text` | the full posting, uncapped (`[Seite N]` markers stripped) |
| `snapshotFile?` | this posting's own PDF in `JobPostingSnapshotStore` |
| `lookupsData?` | `[GlossaryEntry]`, newest first, via `lookups` / `recordLookup` |
| `deckIDRaw?` | the posting's `SavedDeck`, created on first save |
| `modelRaw?` | the tutor that answered the lookups |
| `readingSeconds`, `lastOpenedAt?` | time on the reading screen (not yet on the streak) |
| `adoptedFromChatIDRaw?` | the interview chat it was adopted from |

Related additions: `ChatConversation.jobPostingIDRaw` (defaulted nil) + `ConversationConfig.jobPostingID`
link an interview to its posting; `SavedDeck.Kind.job` (`generatorRaw == "job"`, browsable, shown
with a briefcase in the Library); `ChatConversation.makeConfig(modelManager:decks:)` hoisted from
`ConversationListView` so the hub can resume chats; `ConversationRow` made internal.

## Screens — `Features/JobPrep/`

- **`JobPrepTile`** (`Features/Home/`): the full-width card under the hub grid. Teal, `briefcase.fill`,
  glyph `◧` on Grundform. Pushes the hub.
- **`JobPrepHubView`**: two hero rows (Interview practice → `ConversationSetupView` with
  `fixedMode: .interview`, the Type picker hidden and the title "Interview practice"; Study a job
  ad → the import sheet), then Job postings, Job decks (launch straight into the card player), and
  Past interviews (`modeRaw == "Interview"`; the predicate literal must track
  `ConversationMode.interview.rawValue`).
- **`JobPostingImportView`**: four sources. *Link* reuses `JobPostingClipperView` with
  `capOverride: studyCap`, `useButtonTitle: "Study this posting"`, `showsBudget: false` (the
  clipper's section picker, highlights, "Use entire page text", and PDF snapshot all as in the
  interview flow; no tutor context window, so no budget). *PDF file* via `fileImporter` +
  `PDFTextExtractor` (scanned PDFs rejected; the file becomes the snapshot). *Paste text*. *From an
  interview*: the chat's `jobContext` (or its PDF's text), with the PDF **duplicated** so deleting
  the chat spares the study copy; the chat gets `jobPostingIDRaw` set. PDF/paste/chat go through
  `JobPostingReviewView` for the details; the link path collected them in the clipper's panel.
  A link already saved prompts Open it / Save another copy (`JobURL.same`).
  **Cookie notices:** the collapsed panel sits exactly where sites pin their consent bar. On
  every analysis the clipper asks what is under that strip (`JobPostingScripts.consentOverlay`,
  `elementsFromPoint` → nearest fixed/sticky ancestor that reads like a consent notice and has a
  button); when one is there the panel hides itself (`panelAutoHidden`) and a strip under the
  address bar says why, with Show. It comes back when the notice is gone. The toolbar toggle
  (`togglePanel`) is the learner's override and cancels the automatic behavior. Sticky "apply"
  bars are deliberately not matched, or the panel would never return.
- **`JobPostingDetailView`**: header (source chip, employer, word count, time, share PDF), the
  surface picker when more than one applies, the reading surface, „Unbekannte Wörter“ (speak,
  swipe to remove, **Add all to deck**), Flashcards (Study n cards → `ActivityRouter`), and
  Interview (start one prefilled from this posting; earlier ones for it, matched by
  `jobPostingID` or the same link). The text surface lives in the list; the PDF and live-page
  surfaces take the whole screen with a bottom bar (lookup count, deck, timer) that opens the
  same sections as a sheet.
- **`JobPostingListView`**: every posting; also reached from Library ▸ Reading ▸ Job Postings.

## Reading toolkit

- **`JobReadingSurface.swift`**: the contract. `JobReadingCallbacks` (`onTapWord`,
  `onTranslateSelection`, `onSavePhrase`), `JobReadingDecorations` (`savedWords`,
  `lookedUpWords`, lowercased), `JobReadingSurfaceKind` (`text` / `pdf` / `web`). The detail view
  builds one of each and hands the same values to whichever surface shows.
- **`JobDeckStore`**: the `StoryDeckStore` twin (`"Job: <title>"`, `generatorRaw = "job"`,
  `saveAllLookups`). **`JobWordInspector.make`**: the `StoryWordInspector` twin; `onLookup` →
  `posting.recordLookup`. Both feed `LearnerMemoryService.noteVocabEncounters(source: "job")`
  when `storyFeedsCoach` is on.
- **Tutor:** `StoryStudyService.followUpModel(wrote: posting.model, fallback: selectedStoryModel)`,
  so a lookup never starts a download. On the live page the lightest downloaded tutor is used
  instead (see below).
- **Phrases:** a selection can be translated (the inspector, so it lands in the lookups and can be
  saved as a card) or saved to the phrase library (`AddEditPhraseSheet`, anchored to the
  `jobInterview` scenario so the coach can work it into interview chats).

## The three surfaces (compare on a device, then keep all or some)

| surface | file | gestures | markings | needs |
|---|---|---|---|---|
| **Text** | `JobPostingTextSurface` | `SelectableGermanText`: double-tap, select → Translate / Save phrase | exact: accent wash + red dashes | nothing |
| **PDF** | `JobPostingPDFSurface` | 2-tap `UITapGestureRecognizer` on a `PDFView` subclass (`selectionForWord(at:)`); PDFKit's zoom recognizers are told to `require(toFail:)` it; edit menu via `buildMenu(with:)` + a selection strip as fallback | in-memory highlight annotations from `findString` (whole-word filtered), never written to the file | the saved copy |
| **Live page** | `JobPostingWebSurface` + `Services/JobReadingScripts.swift` | a `touchend` double-tap detector → `caretRangeFromPoint` → `dkWordTap`; `touch-action: manipulation` on the root disables double-tap zoom but keeps pinch; edit menu via a `WKWebView` subclass's `buildMenu(with:)` + a selection strip | CSS Custom Highlight API (`::highlight(dk-saved)` / `dk-lookup`), `<mark>` fallback; re-applied after every navigation | the network, and memory |

Known limits to check on a device:
- PDF: a WebKit snapshot is one tall page whose text layer includes nav/cookie text; words
  hyphenated across a line come back as their first half; the zoom deferral walks PDFKit's private
  view tree (if nothing is found, both zoom and lookup fire).
- Live page: `preventDefault` on the second `touchend` could swallow a page button under a fast
  double tap; a killed content process reloads the page and loses the scroll position.
- **Memory:** the clipper unloads the tutor before showing WebKit (`ConversationSetupView.presentClipper`)
  because the content process is the first thing iOS reclaims. The live-page surface needs both,
  so it (1) runs lookups on the lightest downloaded tutor, (2) unloads the tutor on entry when
  `MemoryPressureMonitor.shared.level` is above normal (the first lookup reloads it; a note says
  so), (3) accepts reloads. The PDF surface is the offline / low-memory equivalent.

Comparison notes (fill in after device testing):

| | Text | PDF | Live page |
|---|---|---|---|
| double-tap reliability | | | |
| markings | | | |
| memory / reloads | | | |
| keep? | | | |

## Verification

- `build_sim` after each change; the sim can't run MLX, so the inspector shows "Getting the model
  ready…" then no translation there. Persistence of lookups/saves is a device check.
- Flows: Home ▸ All Activities → Job prep tile → hub → Interview practice (no Type picker) →
  Start → chat; hub → Study a job ad → paste → review → detail → double-tap; PDF import via
  Files; adoption from a chat leaves two files under `Application Support/JobPostings`; deleting
  the chat leaves the posting readable; Practice an interview prefills; the deck appears under
  Job decks and Library ▸ Decks with the briefcase badge.

## Later

- Group Past interviews by posting once most chats carry `jobPostingIDRaw`.
- Streak: `StudyDay.jobSeconds` + a `StudyTimeBucket` / `StudyActivity` case, a teal slice on the
  calendar, backfill from `readingSeconds`.
- LLM extras: an auto-glossary of the posting (the story glossary step; `GlossaryHighlight` dotted
  underlines already render), "translate all unknown words with example sentences" via the
  batched `PaperStudyService.makeDeck(for:words:)` prompt to fill `exampleSentence`, "Discuss this
  posting" chat, whole-posting English translation, a sentence-by-sentence tutor-mode stepper.
