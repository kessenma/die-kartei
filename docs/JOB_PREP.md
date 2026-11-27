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

## Lebenslauf (built 2026-11-20, roadmap item 18)

Job prep ▸ Lebenslauf (`Features/JobPrep/Resume/ResumeView.swift`). The résumé is imported by
paste, PDF (`PDFTextExtractor`; a scanned PDF's first four pages go through `PhotoOCRService`) or
photo, and kept whole in `Resume.fullText`, uncapped.

- **Kurzprofil**: the tutor writes a German digest of at most ~500 characters once
  (`ResumePrompts.kurzprofilSystem`: role, years, skills, two achievements, education, languages,
  nothing invented). The learner reads and edits it; that exact text is what the recruiter gets.
- **Facts**: one role, project, degree or skill per line. A heuristic split (dated or bulleted
  lines) fills them at import; "Split the facts with the tutor" replaces them; the learner edits.
- **One budget, two parts**: in the interview setup the Kurzprofil takes a fixed slice
  (`ResumePrompts.kurzprofilSlice`: 500, 300 under Memory Saver) and the posting gets
  `JobContextBudget.characters(for:)` minus that. The setup's Lebenslauf section shows both.
- **A fact per turn**: `interviewProgressNote` adds the one fact that shares the most content words
  with the plan point coming up (`ResumePrompts.bestFact`), so the recruiter can ask about it by
  name. The persona says the profile is all it knows and to invent no employers, dates or numbers.
- **Without a posting**: with the résumé on, a posting is optional. The recruiter runs a general
  interview over `ResumePrompts.generalPlan` (Werdegang, Stärken, a gap or change in the CV, goals).
- **Career words**: the tutor picks 8–12 words from the résumé (`deutsch = english`), saved to the
  "Lebenslauf" deck through `DeckCardAdder` (the `CardKind` path).
- **Privacy (decided for now: on this device only)**: `Resume` is in `AppSchema` but not in
  `SyncRegistry`, so it never syncs; the chat stores only `usesResume` (synced) and re-reads the
  local résumé on resume. Never part of cloud pictures or the coach hand-off. Syncing it is open
  for Kyle to decide.
- **Measure first**: Settings ▸ Developer ▸ Lebenslauf-Probe runs the chosen tutor over the
  learner's own résumé for each general plan point and marks whether the question named the fact
  and which years or names in it the résumé doesn't have (`ResumeProbe`). Runs on a device or the
  Mac; read the questions too. No numbers yet.

## Sammeln · Collect, the word count, and the Pencil (built 2026-11-27, branch `job-vocab`)

Saving words from an ad used to be one at a time: double-tap, wait for the tutor, Save, next word.
This adds a bulk path beside it. Every way in ends in the same sheet.

- **Collect mode** (`JobPostingDetailView`, the checklist button in the toolbar). One tap picks a
  word (`SelectableGermanText.tapsToInspect` drops to 1, so no inspector, no model load); on the
  PDF and live-page surfaces their double-tap picks. Picked words get a marker-yellow wash
  (`JobReadingDecorations.markedWords` / `markedPhrases`, drawn over the saved-word wash). The tray
  at the bottom counts them (its menu removes one) and *Add to deck* opens the save sheet. The
  basket (`JobVocabBasket`) lives with the screen and is not persisted.
- **A selection** gets *Add to deck…* in its edit menu (text surface, read or collect mode;
  `onCollectSelection`). One word goes straight in. Several ask (`jobVocabSpanDialog`): *One
  phrase card*, *n word cards* (the content words, `JobVocabAnalyzer.contentWords`: no articles,
  pronouns or prepositions), or *Both*. A phrase can still be split later in the sheet (swipe ▸
  Split).
- **Apple Pencil** (`SelectableGermanText+Pencil.swift`, `PencilWordMarking`). On the text surface
  the Pencil always collects, mode or not: tap a word (toggles), run a highlighter or an underline
  over words, or circle them. Words side by side ask the phrase question; words circled apart go
  in one by one (basic words skipped). A `PencilMarkRecognizer` (Pencil touches only) begins on
  touch-down, so the text view's selection and the list's scrolling never see the Pencil; every
  scroll view above the text stops taking Pencil touches. Fingers scroll, select and double-tap as
  before. The ink is a fading marker stroke; nothing is stored. Loop detection is
  `PencilEraseLoop.isLoop` (circle to erase). PDF and live page: not yet (the Pencil reads like a
  finger there). **Device check open:** all of it; the simulator has no Pencil.
- **The save sheet** (`JobVocabSaveSheet`). A deck: the ad's own (default from a posting), any
  browsable deck (job decks first), or a new one (`generatorRaw = "job"`, so it is a job deck).
  Each row: tick, German, English, the ad's sentence (saved as the card's example). English the app
  already has is filled in first (`JobVocabKnown`): words looked up in any posting, then cards in
  the learner's decks, then the Goethe lists, by `CardKind.matchKey` and, for single words, by stem
  with the same capitalisation („Kunden“ finds „der Kunde“; „Arbeit“ never finds
  „arbeiten“). A known word also takes the source's German with its article. The rest goes to
  the tutor in batches of 12 (`JobVocabTranslator`), which is asked for the dictionary form too
  („Kenntnissen“ → „die Kenntnis“). When it answers every line the order holds; otherwise
  an answer goes to the line it names. A dictionary form is taken only when it is recognisably the
  same word (`sameWord`: same key, same stem, or the same first five letters); a phrase keeps the
  learner's wording. Saving goes through `DeckCardAdder` (deduped, `CardKind` decides word or
  phrase) and `DocumentDeckService.makesCard` (no empty English side; the sheet says how many are
  left out), and feeds the coach like the reader's saves (`storyFeedsCoach`).
- **Häufige Wörter · Word count** (`JobVocabAnalysisView`; Job prep hub, and *Wortliste* on a
  posting for that ad alone). Choose ads (`JobPostingMultiPicker`, default the dozen most recent),
  or bring in several at once (`JobPostingBulkImportView`: several PDFs from Files, or links one
  per line read with `WebTextExtractor.fetch`, no browser, no page copy; a site that needs its
  browser says so per link). Two tabs:
  - *Wörter*: every word, grouped by form, sorted by how many ads use it, then by count. Each row:
    „3 of 4 ads“ with a bar, the count, the other spellings, a deck mark, its Goethe level,
    and a quote button for the sentences it stands in, ad by ad (`JobVocabContextSheet`). Filters
    (menu, remembered): hide basic words (`GermanBasicWords`: articles, pronouns, prepositions,
    conjunctions, sein/haben/werden and the modals, small adverbs; on by default), hide words in my
    decks (on), group word forms (on), hide Goethe words up to A1/A2/B1 (off). With several ads a
    stepper sets „in at least n ads” (starts at 2 with three ads or more). The footer gives the
    share of the text's content words the learner's decks already cover.
  - *Wendungen*: two-to-six-word runs („sehr gute Deutschkenntnisse in Wort und Schrift“) that start and end on a content word, in two ads or more
    (twice or more in one ad), a run inside a longer, equally common one left out.
  Tick, *Tick all*, then *Add to deck*: the same sheet.
- **Counting** (`Services/JobVocab/`, pure, runs off the main actor). Sentences are lines first
  (bullets carry no full stops), then `NLTokenizer` sentences. Words are letter runs keeping inner
  hyphens („Full-Stack-Entwickler“); single letters („m/w/d“) drop out. Forms are grouped by
  a CISTEM stem (`GermanStem`, plus „-nisse(n)“ → „-nis“) because `NLTagger` has no German lemmas
  (its German schemes are language, script and token type). A capitalised word stays apart from
  a lowercase one with the same stem, unless it was only ever first on its line. The list shows
  the shortest spelling, usually the base form; the tutor gives the real dictionary form on save.

Simulator: `-jobPrep.debugOpen hub|count|phrases|formulas|posting|collect|pdf|save` seeds three sample postings
(each with a PDF copy rendered from its text)
(titles start „[debug]“, refused while iCloud Sync runs) and opens that screen; `collect` opens the
first in Collect mode with four words picked, `pdf` the same on its PDF, `save` the save sheet for them (`JobVocabDebug.swift`).

Tests: `german-ai-flashcardsTests/JobVocabTests.swift` (stems, counting, basic words, the noun/verb
split, line-initial capitals, shared phrases and pruning, sentences, splitting a phrase, the
tutor's answers by position and by word, known English by stem, saving into the posting's deck
(article, example, phrase type, no duplicates), formulas (inflected, not inside other words,
longest wins, highlight and answers, counted across ads), compound splits and non-splits, coverage
by stem, PDF word boxes against PDFKit's own search, the basket, the Pencil's tap,
stroke and loop).

### Second round (same branch)

- **Pencil on the PDF** (`JobReadingPDFView+Pencil.swift`). Same gestures and the same
  `PencilWordMarking` as the text surface. A page's words come from its text layer
  (`PDFPage.string` + `characterBounds(at:)`, first and last letter per word, letter by letter for
  one that wraps), built once per page on the first mark and kept in page space, moved into view
  space per mark (`visiblePages`), so zoom doesn't matter. PDFKit's scroll views stop taking Pencil
  touches; the word tap is fingers-only while the Pencil marks. Picked words get a yellow highlight
  annotation (in memory, a layer of its own so a pick doesn't redraw the saved/looked-up washes).
  The selection strip and edit menu gain *Add to deck*; Collect mode makes the PDF's word tap a
  single tap. Covers imported PDFs and saved page copies. Live page: still not.
- **Formeln** (`JobAdGlossary`, ~85 bundled formulas with English and a note where the English
  misleads: „von Vorteil“ = nice to have, „setzen wir voraus“ = must, „leistungsgerechte
  Vergütung“ says nothing about the amount). Matched word by word on stems, so inflected uses
  count and „befristet“ is never found in „unbefristet“; where two overlap the longer wins.
  On a posting: dotted in the text surface (`JobReadingDecorations.glossary`), answered by a
  double-tap without the tutor, listed in a *Formeln* section with a plus to pick each (or all).
  In the word count: a third tab, every formula the chosen ads use with its English. In the save
  sheet: English filled from the formulas (origin „job-ad phrase“, ranked under lookups and
  decks, over the Goethe lists).
- **Compounds** (`GermanCompound`). Dictionary-based: every part must be a known word (Goethe
  lists, the learner's cards, the formulas, the ads' own words), the last part a noun, linking
  letters s/es/n/en/e/er allowed, a verb stem as first part when its infinitive is known
  (schreib- → schreiben). A word known in its own right is never split (Mitarbeiter); the ads'
  own words are parts only (`asWhole: false`) so an ad's compound still splits. No split when
  nothing fits. Shown as „Arbeit + Zeit“ under the word in the count and the save sheet; in the
  sheet a compound swipes left to *Split* (parts replace it) or right to *Add parts* (parts join it).
- **Coverage** (`JobVocabCoverage`, `JobVocabDeckWords`). On each posting, above *Every word in
  this ad*: „Your decks cover 64% of this ad“ with a bar and how many of its words are in no deck,
  recounted after a save. Word uses, basic words left out; a card covers every form of its word
  (stem, same capitalisation). The word count's „hide words in my decks“ now uses the same test,
  so „Kenntnissen“ is hidden by a „die Kenntnis“ card.
- Collect mode now also picks on the live page (its word tap went straight to the inspector).

Not built yet: the Pencil on the live page; a remembered basket; splitting compounds whose first
part is a language or nationality („Deutschkenntnisse“: „Deutsch“ is in no list).

## Later

- Lebenslauf: posting against résumé (which requirements are covered, which gaps need a prepared
  answer); a decision on syncing the résumé.
- Group Past interviews by posting once most chats carry `jobPostingIDRaw`.
- Streak: `StudyDay.jobSeconds` + a `StudyTimeBucket` / `StudyActivity` case, a teal slice on the
  calendar, backfill from `readingSeconds`.
- LLM extras: an auto-glossary of the posting (the story glossary step; `GlossaryHighlight` dotted
  underlines already render), "translate all unknown words with example sentences" via the
  batched `PaperStudyService.makeDeck(for:words:)` prompt to fill `exampleSentence`, "Discuss this
  posting" chat, whole-posting English translation, a sentence-by-sentence tutor-mode stepper.
