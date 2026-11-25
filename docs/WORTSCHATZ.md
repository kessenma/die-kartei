# Wortschatz — the Goethe word box

The bundled Goethe-Institut A1/A2/B1 word lists, studied as one box. Replaces the three per-level
"Goethe A1/A2/B1 Vocabulary" screens. Design borrowed, with credit in Settings ▸ Sources, from
[Wortkiste](https://github.com/matchaDataHub/wortkiste) (MIT, matchaDataHub): one deck, one
"due today" number, one Start button; scope that never discards progress; a daily new-word
budget; a Leitner box chart; Again re-queuing inside a session; the article hidden on the German
front; per-word status in the browse list.

Status legend: ✅ done · ⬜ open

## Where things live

| Piece | File |
|---|---|
| Word index (one record per headword, tagged with its levels) | `Services/A1VocabService.swift` (`GoetheWord`, `GoetheVocabService.index` / `orderedWords`) |
| Scope, status, Karteikasten buckets, counts | `Services/WortschatzService.swift` |
| Merged SRS deck, session builders, preview | `Services/DeckStore.swift` (`fetchOrCreateWortschatzDeck`, `wortschatzSession`, `wortschatzPreviewSession`, `wortschatzSummary`) |
| One-time merge of the old per-level SRS decks | `Services/WortschatzMergeService.swift` |
| Hub, scope chips, chart, browse, word sheet, info | `Features/Wortschatz/` |
| Today plan step | `Services/TodayPlanner.swift` (`.wortschatz`), `Features/Home/TodayView.swift` |
| Prefs and keys | `Models/CardStudyPrefs.swift` |
| Developer tools | `Services/WortschatzDebugSeeder.swift`, Settings ▸ Developer |
| Data merge script (Wortkiste plurals / verb forms) | `scripts/merge_wortkiste_forms.py` |

## Data model

**Lists are cumulative.** A2 holds 483 of A1's 585 words, B1 holds 821 of A2's. Union: 2,825
unique headwords (A1 579 after its six duplicates, A2 adds 726, B1 adds 1,487).

**Level membership is derived, never stored.** `GoetheVocabService.index` walks A1 → A2 → B1
once. The first list a word appears on defines it (word, translation, word type); later lists
add their level and only fill what the earlier row left empty (the A2 list drops the article on
twenty A1 nouns). Exact-string keys collapse the six intra-A1 duplicates. `orderedWords` is
introduction order: the A1 list, then the words A2 adds, then B1's. That order is the SRS deck's
`sortOrder` and the order new words are introduced in.

`GoetheWordType` is derived too: `article != nil` ⇒ noun (A2/B1 leave `wordType` empty for most
nouns), else the raw `verb`/`adj`/`adv`, else `other`.

**One SRS deck.** `generatorRaw == "goethe-srs"`, topic `"Goethe Vocabulary"`
(`DeckStore.wortschatzTopic`), one `SavedCard` per headword with a translation. Backfilled on
open with any word the lists gain; duplicate rows collapse. Hidden from the Library
(`isBrowsableContent`), like before. The per-level stats decks (`generatorRaw == "goethe"`) stay:
the matching game writes its results there.

**Plural and verb forms** come from Wortkiste via the script (628 `plural` and 208 `verbForms`
keys across the three JSONs, 409 headwords). They are read through the index and attached to
`VocabCard.forms` at session build time; `SavedCard` stores no forms. Plural notation is
Wortkiste's ("-en", "¨-e", "only sg."); `GoetheVocabService.formsLine` turns it into the card
caption ("Plural: -en", "nur Singular"). Re-run the script after touching the lists; it is
idempotent and never changes existing keys.

## The merge (`wortschatz.merge.v1`)

Runs once at launch, right after `StudyTimeBackfillService`, in the same shape: flag set before
the pass, `run(in:)` public. For every word across the old `"A1 Vocabulary"` /
`"A2 Vocabulary"` / `"B1 Vocabulary"` SRS decks (and across the duplicate rows inside them):

- the copy with the greatest `(interval, repetitions, totalReviews)` supplies ease, interval,
  repetitions and next-review date;
- `totalReviews` and `lapses` are summed, `leitnerBox` is the max;
- the old decks' `QuizResult`s are reparented to the merged deck before the old decks are
  deleted, so history and the streak calendar keep them. The Leitner session counter
  (`quizResults.count`) jumps once because of that.

A fresh install has nothing to merge; the hub creates the deck on first open.

## Sessions

`DeckStore.wortschatzSession(scope:style:newBudget:sessionCap:)`:

1. cards in scope = merged deck ∩ `scope.contains(index[word])`;
2. **due** = not new and due under the chosen scheduler (Anki: `nextReviewDate <= now`, or no
   date at all; Leitner: `LeitnerService.isDue(box:sessionNumber:)`), shuffled;
3. **new** = `totalReviews == 0`, in `sortOrder`, up to `min(newBudget, cap − due)`;
4. `cards` is built *from* the chosen `SavedCard`s, so the player's index-aligned `savedCards`
   cannot drift (the old `compactMap` could).

`topic` is `"A1 Vocabulary"` when one level is in scope (the badge and result labels read as
before), else `"Goethe Vocabulary"`. The session sets `autoStart`, so the player skips its setup
screen; the hub *is* the setup screen. A paused session still shows the resume prompt.

Leitner box 0 is treated as **new** (budgeted), never due. A card reviewed only under the other
scheduler has no schedule here and counts as due, so switching styles never strands a word.

**Vorschau** (`wortschatzPreviewSession`) flips through in-scope words with `deckID == nil`: no
quiz mode, no results, no pause, nothing logged. Non-counting by construction.

## Daily new-word budget

`StudyDay.newWordsIntroduced` and `newWordsBonus` (defaulted, additive; neither counts toward
`hasActivity`). A card's first rating in a Wortschatz session records one introduced word
(`ankiAdvance` / `leitnerAdvance` → `StudyLogService.recordNewWords`). "Learn 10 more" adds a
bonus for the day. Remaining = `newPerDay + bonus − introduced`.

## Today section

`SavedCard.lastReviewedAt` / `lastReviewWasCorrect` / `firstReviewedAt` (optional, stamped by
`SavedCard.noteReview` from both schedulers and the conversation re-encounter) let the hub list
the words rated today, missed ones first, with a right/missed mark and the next-due badge, plus
a "N right · M missed · K new" header. Browse has a matching "Today" filter. Per distinct word: a
re-queued card counts once, with the result of its last pass.

## Status

One place, `WortschatzService`, used by the chart, the browse badge, the word sheet and Today.

| Status | Rule |
|---|---|
| Neu | `totalReviews == 0` |
| Fällig | not new, and due under the current style (see Sessions) |
| Bekannt | `interval >= 21 \|\| repetitions >= 3` — the pyramid's own learned rule |
| Schwierig | not known, and `lapses > 0` or the der/die/das or matching game has it tricky |
| scheduled | otherwise; badge "in 5 T." (Anki) or "Box 3" (Leitner) |

Karteikasten buckets (always seven, zeros included): Neu · five middle compartments · Bekannt.
Under Anki the middle five are interval bands (≤1, ≤3, ≤7, ≤14, <21 days); under Leitner they
are boxes 1–5.

**Leitner now writes `repetitions` and `interval`** (`LeitnerService.markCorrect` bumps both,
`markWrong` resets repetitions), so a word drilled only in Leitner can reach Bekannt and credit
the pyramid — three correct in a row, the same bar Anki uses. Applies to every deck.

## Player changes (every deck)

- **Again re-queue** (`cards.repeatMissed`, default on): a card rated Again (Anki) or wrong
  (Leitner) is reinserted `requeueGap + 1` positions ahead, at most twice. `sessionDueCount` is
  the fixed denominator (HUD, summary, `StudyLogService.record(.cards)`); `sessionLapses` is the
  missed list, one entry per card however often it came back. Persisted in
  `DeckSessionProgress` (optional fields). "Try Again" dedupes the queue first.
- **Direction** (`cards.germanFirst`): the player's `showGermanFirst` is `@AppStorage` now; the
  setup picker, the in-session menu and Settings ▸ Cards write the same key.
- **der / die / das?** (`cards.articleQuiz`, default on): `FlashCardView.hidesArticleUntilFlipped`.
  While the German side is up and unflipped, the word shows a muted "der / die / das?" prefix;
  the gender tab, the gender badge, TTS, the fullscreen picture caption and the example sentence
  all wait for the flip. `FullscreenCardView` gets the same flag.
- **Forms line**: `VocabCard.forms` renders as a caption under the German word once revealed.
- **Settings sheet**: `CardSettingsSheet` opens from the setup screen and the in-session menu;
  `SettingsRoute.cards` deep-links to Settings ▸ Cards (the hub's options offer it).

## Today

`TodaySnapshot.wortschatz` (due + new under the persisted scope, style and budget) adds a
`.wortschatz` step ahead of the general review, only when something is waiting, and only once the
box has been opened (no deck ⇒ nil). The general "Review N due" **excludes** the Goethe deck so
the two never double-count and the 60-card daily review is not flooded with Goethe words.

## Prefs

| Key | Default |
|---|---|
| `wortschatz.levels`, `wortschatz.wordTypes` | all (comma-joined raw values; empty ⇒ all) |
| `wortschatz.style` | Anki (Leitner selectable; never plain flip) |
| `wortschatz.newPerDay` | 15 (5/10/15/20/30/50) |
| `wortschatz.sessionCap` | 40 (20/40/60/100) |
| `cards.germanFirst` / `cards.articleQuiz` / `cards.repeatMissed` | true |
| `wortschatz.merge.v1` | merge-done flag |

## Debug launch arguments (DEBUG)

```
xcrun simctl launch <udid> kyle-essenmacher.german-ai-flashcards -wortschatz.debugOpen 1
```

- `-wortschatz.debugOpen 1` — presents the hub at launch (it is two taps deep otherwise).
- `-wortschatz.debugOpenSession 1` — starts a box session at launch, to check the card front.
- `-wortschatz.debugLegacyDecks 1` — recreates the three old per-level SRS decks with divergent
  progress and clears the merge flag; the merge then runs in the same launch.
- `-wortschatz.debugMerge 1` — re-runs the merge now.
- `-wortschatz.debugSeed 1` / `-wortschatz.debugRestore 1` — spread the box over new / due /
  known / lapsed (reversible from `Application Support/Developer/wortschatz-seed-backup.json`).

The same tools sit in Settings ▸ Developer.

## Removed

`Features/A1/A1VocabView.swift` (`GoetheLevelPickerView`, `GoetheVocabListView`, `A1EntryRow`,
`A1WordTypeFilter`), `DeckStore.goetheSession` and `fetchOrCreateGoetheSRSDeck(for:)`. The four
literal `["goethe", "goethe-srs", …]` deck filters now read `SavedDeck.isBrowsableContent`.

## Open

- ⬜ The A2/B1 lists have no example sentences for most words and no word type for many; the
  index fills gaps from other levels, but 1,487 B1-only words still have none.
- ⬜ 42 Wortkiste words are missing from the Goethe JSONs altogether (Jahr, Minute, Monat, Nacht,
  Café, …): the lists themselves have gaps worth a separate pass.
- ⬜ Device verdict on the hub, browse and article-quiz card in all four themes.
