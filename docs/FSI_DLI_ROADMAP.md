# FSI / DLI methods — feature checklist

What the US government's language schools do that this app can borrow, as a list to work down.
The Foreign Service Institute (FSI) trains diplomats; the Defense Language Institute (DLI) trains
military linguists. Both teach adults full time and have published what works.

Every item carries a **source mark** (key below) so the claim behind it can be checked, and so
the right citation reaches Settings ▸ Sources when the item ships.

## Source key

| Mark | Source | Read? |
|---|---|---|
| `FSI-n` | Jackson & Kaplan, "Lessons learned from fifty years of theory and practice in government language teaching", GURT 1999 (Georgetown UP 2001), pp. 71–87. `n` is the lesson number, 1–10. | Full text |
| `DLI-FLO` | DLIFLC Student Handbook, "Final Learning Objectives" (pp. 23–24), and Appendix A of the DLI-Washington Student Handbook (22 June 2012), which lists the sub-skills word for word. | Full text |
| `DLI-STRAT` | DLIFLC Student Handbook, "Language Learning Strategies" (pp. 19–22). | Full text |
| `DLI-TI` | DLIFLC Student Handbook, "Academic Standards, Feedback and Assistance" (pp. 16–18): feedback and tailored instruction. | Full text |
| `DLI-RESP` | DLIFLC Student Handbook, "Student Responsibilities" (p. 12). `n` is the numbered point. | Full text |
| `ODA` | DLIFLC Online Diagnostic Assessment (oda.dliflc.edu). | Search summary only |
| `CASL` | Bloomfield et al., "What makes listening difficult?", Univ. of Maryland CASL, 2010 (DTIC ADA550176). | Search summary only |
| `DTIC-SSF` | "Student Success Factors at DLIFLC" (DTIC AD1114144). | Search summary only |

Links: [DLIFLC Student Handbook](https://www.dliflc.edu/dliflc_student_handbook_20170104) ·
[DLI-Washington handbook](https://www.dliflc.edu/student_handbook_06_2012-2) ·
[FSI paper, mirror copy](https://csclub.uwaterloo.ca/~rfburger/fsi-gurt-1999-07.pdf) ·
[CASL report](https://apps.dtic.mil/sti/pdfs/ADA550176.pdf) ·
[Student Success Factors](https://apps.dtic.mil/sti/html/tr/AD1114144/index.html)

**Rule:** a "search summary only" source is not cited in the app until someone has read it.
The FSI link is a personal mirror, so the app cites that paper as text without a link.

## When an item ships

- [ ] Tick it here with the date.
- [ ] Add its clause to the "Wie Erwachsene lernen" section of
      `Features/Settings/SourcesView.swift`, plus its citation if the source is not listed yet.
- [ ] Add a What's New bullet (rules in the root `CLAUDE.md`).
- [ ] Write or extend the feature doc and point to it from `CLAUDE.md`.
- [ ] Add a debug launch argument that opens it.

## Already in the app (do not rebuild)

| Practice | Source | Where |
|---|---|---|
| Explicit grammar early, attention on word endings | `FSI-3` `FSI-8` | Kasus path, ending blocks, Verstehen lessons |
| Pattern drills for automatic answers | `FSI-7` | Grammar drill framework, Blitzrunde, SRS decks |
| Grammar concepts named in plain words | `FSI-5` | Verstehen lessons, Nachschlagen |
| Feedback that makes the learner repair the slip | `FSI-9` `DLI-TI` | Nudge me, correction cards |
| Diagnose, then pick the practice | `ODA` `DLI-TI` | Placement quiz, `LearnerProfile`, Today |
| Listen without the text, then answer questions | `DLI-FLO` | Stories ▸ Hören (`StoryDetailView.StudyMode.listen`) |

---

## A. Hören: listening as a tested skill

A new Home room beside Spiele, Zeichnen and Schreiben (tiles in `HomeHubView`). DLI's performance
tests are mostly listening tasks, and this is the app's widest gap. Items 1 and 2 need no tutor
model.

### 1. Zahlen-Diktat (numbers heard once) · effort S
- [x] **Shipped** 2026-11-20 (branch `hoeren-room`; `docs/HOEREN.md`)

Source: `DLI-FLO` "Transcribe (single pass) decontextualized numbers" and "Transcribe (single
pass) numbers in context". German says the units before the tens (vierundzwanzig), so this is
worth more here than in most languages.

- [x] Generator by level: 0–100, hundreds and thousands, prices, clock times, dates, years, phone numbers.
- [x] Two modes, one per objective: the bare number, and the number inside a carrier sentence.
- [x] Single pass is the default. A replay is allowed and counted.
- [x] The learner types digits. Normalise spaces, `,` vs `.`, leading zeros, "Uhr".
- [x] Stats per kind, plus confusion pairs (24 typed as 42).
- [x] Credit the day (`StudyDay`) and XP (`docs/GAMIFICATION.md`).
- [ ] Listen to the speller A/B (`-hoeren.debugOpen speller`) on a device's premium voice.

Traps (checked): `NumberFormatter` `.spellOut` for `de_DE` puts soft hyphens (U+00AD) inside
words and spells 1987 as "eintausendneunhundert…", not "neunzehnhundert…". Listen to how the
chosen voice reads years, times and prices, and hand it spelled-out text where it is wrong.

### 2. Diktat (write what you hear) · effort S–M
- [x] **Shipped** 2026-11-20 (branch `hoeren-room`; `docs/HOEREN.md`)

Source: `DLI-FLO` "Transcribe text in native script". `DLI-STRAT` 1c: write down everything you
do understand, use pause, fill the gaps from grammar. `FSI-8`: in an inflected language the
meaning sits at the ends of words, so ending misses are the ones to catch.

- [x] Sentences come from bundled data, never generated: `example` in `a1/a2/b1_vocabulary.json`,
      the Tatoeba Perfekt examples in `past_tense_verbs.json`, sentences in `kasus_stories.json`.
- [x] A course as a source: sentences from its handouts and its deck's examples, so the ear
      practises this week's class words.
- [x] Player on `SpeechService.speak(_:slow:)`. Study mode (replay, slow) and single pass.
- [x] Word-by-word diff. Umlaut and ß follow the rule in `docs/SPIELE.md`. A missed noun capital
      counts as heard and is listed apart.
- [x] Split misses into "ending only" (stem right) and "word". Ending misses go to the learner
      profile as tagged slips (`noteSlips`, never `applyDrillResult`).
- [x] Missed words can be saved to a deck through the one `CardKind` path (`docs/PHRASES.md`).
- [ ] Later: answer with the Pencil, reusing "Read my handwriting" from Schreiben.
- [ ] Before citing `CASL` in the app for this, read the report.

### 3. Worum geht's? (the gist in your own words) · effort M
- [x] **Shipped** 2026-11-20, self-checked (branch `hoeren-room`; `docs/HOEREN.md`). The tutor
      judge stays DEBUG-only until `training/GIST_PROBE.md` has been read.

Source: `DLI-FLO` "Produce an English summary of a conversation" and "… of a news broadcast".
Stories ▸ Hören already hides the text and asks content questions. The missing part is the
learner's own summary.

- [x] After listening and before the questions: one or two sentences in English.
- [x] Story generation also writes 3–4 key points. The learner ticks each point; the app computes
      the score. The tutor's yes/no per point exists in DEBUG only.
- [x] Measure first: probe how well each tutor judges a summary (`training/GIST_PROBE.md`).
- [ ] Decide from the probe whether a tutor judge ships, and on which tutors.
- [x] Add a short news-style text type, so both DLI text types exist (conversation, broadcast).

### 4. Erst raten, dann hören (predict, then listen) · effort S
- [x] **Shipped** 2026-11-20 (branch `hoeren-room`; `docs/HOEREN.md`)

Source: `DLI-STRAT` 1a and 1d: "Don't listen to an audio cold", predict the words, then "see how
many of the words you predict are actually used".

- [x] Before a Hören story, show the title and topic and let the learner name words they expect.
- [x] After it, show which of those words came up.

## B. Automaticity: right and fast

### 5. Answer time · effort M
- [ ] **Shipped**. Measurement shipped 2026-11-20; the "sicher" mark waits for the numbers.

Source: `FSI-7`: automaticity "is more important than has been recognized". A practised routine
needs less effort, which frees attention for the rest. The app records right or wrong today, not
how long an answer took.

- [x] Record time to answer on drill items (`GrammarDrillShell` → `KasusRoundItem.answerMs`) and on
      card flips (`AnswerTimeLog`, per device).
- [x] Measure first: Settings ▸ Developer ▸ Messungen shows the spread. No thresholds until the
      numbers have been looked at.
- [ ] A "sicher" mark for right and fast, shown in stats. Keep it out of SRS scheduling at first.
- [x] Sync: drill times travel inside `KasusRound`'s items blob; card flip times stay on the device
      (a measurement, not progress).

### 6. Easy rounds in Today · effort S, after item 5
- [x] **Shipped** 2026-11-20. "Known" is the SRS's verdict (Leitner box 4+ or a 3-week interval,
      last answered right) until item 5's "sicher" exists.

Source: `FSI-7`: vary the pace and give learners "some tasks that they can perform easily".

- [x] A `TodayIntent` case for a quick round on material the learner already knows (plain cards,
      nothing rescheduled). `-today.debugEasyRound 1` forces the hard-session trigger.
- [x] Offer it after a hard session (under 60% right first time), or when the day's plan is all
      weak spots (two or more).

### 7. Leicht lesen (easy reading in volume) · effort S–M
- [x] **Shipped** 2026-11-20 (`docs/SHORT_STORIES.md` ▸ Leicht lesen)

Source: `FSI-7`: adults need "considerable amounts of 'easy' material" to build stamina.
`FSI-4`: time spent reading and listening tracks closely with what a learner can do.

- [x] A story option one level below the declared level: longer, with few new words.
- [x] Count words read next to the reading time already logged (`StoryReadingSession.wordsRead`,
      an estimate capped at 150 words a minute).

## C. Conversation under pressure

### 8. Stammtisch mode · effort M
- [ ] **Shipped**

Source: `FSI-10`: conversation is the hardest skill. Learners must practise "following rapid and
unpredictable turns in topic", "producing unplanned speech", "coping with the speed of the
turn-taking" and "coping with background noise".

- [ ] Topic changes driven by the app: every few turns the engine injects one. Do not rely on
      the tutor to do it. All prompts still go through `ChatTurnNormalizer`.
- [ ] Optional reply timer. When it runs out, the tutor moves on.
- [ ] Optional café noise under the voice, off by default.
- [ ] Short listener phrases (Ach so, Genau, Echt?) as phrase cards: `FSI-10` "displaying
      understanding and involvement".
- [ ] A new `ConversationConfig` field is copied at four sites: `ConversationSetupView.start()`,
      `ConversationListView.makeConfig`, `PaperDetailView`, `WeekInReviewSection`.
- [ ] Later: two tutor voices in one chat. Stories already have dialogue voices.

## D. Diagnose and tailor

### 9. Förderplan (ten days on one weak spot) · effort M
- [ ] **Shipped**

Source: `DLI-TI`: a weak skill gets a written list of "deficiencies" and "specific actions",
followed by "a minimum of 10 days of tailored instruction". `FSI-9`: frequent formative feedback.

- [ ] Trigger: a grammar tag that stays weak across sessions. Measure first, then set the rule.
      (History started 2026-11-20: `ProgressSnapshot.grammarStruggle`, shown in Messungen.)
- [ ] The plan names the weak spot in plain words and sets ten short daily tasks from existing
      drills, shown in Today.
- [ ] A short re-check at the end, with the outcome written to the profile. It never fills the
      pyramid by itself (estimated is not earned).

### 10. Monthly written feedback · effort S
- [ ] **Shipped**

Source: `DLI-TI`: "At least once a month, this feedback will be in writing."

- [ ] A monthly note beside `WeekInReviewSection`: what got better, what to do next. Built from
      the weekly snapshots, with no tutor needed.

### 11. Listening in the diagnosis · effort M, after items 1–2
- [ ] **Shipped**

Source: `ODA`: an adaptive check that finds a floor and a ceiling, profiles strengths and
weaknesses, and points to matching lessons. Read the source before building.

- [ ] A listening level in the learner profile, fed by Hören results.
- [ ] A short periodic re-check that Today can offer.

## E. With a class or a tutor (Deutschkurs)

The app already keeps what a class produces: entries, handouts, slide decks as vocabulary decks,
exercise slides as homework, her slides filled in and sent back. What is missing is the loop
around each session: prepare, review the same day, and tell the teacher what the app saw.

**Do first, already planned elsewhere:**
- [ ] Tutors read the class, and Today plans from it (`docs/CLASS_NOTES.md` ▸ Later). Items 13
      and 16 below need both.
- [ ] Mistakes into the matching drill, and her review plan on Today (`docs/WORKSHEETS.md` ▸ Later).

### 12. Vor der Stunde (prepare the next session) · effort S–M
- [ ] **Shipped**

Source: `DLI-RESP` 3: "Preview the next day's lesson in advance whenever possible."

- [ ] A course knows its next session: a weekly slot for a course, a date for a tutor.
- [ ] The day before, Today offers the lesson's words as a short round, from slides or a handout
      imported ahead.
- [ ] A read-through of the lesson's explanation slides in the reader.

### 13. Nach der Stunde (same-day review) · effort S
- [ ] **Shipped**

Source: `DLI-RESP` 5: "At the end of the day, review what you learned in class."

- [ ] On a class day, Today asks for free recall first (three things class covered), then quizzes
      the entry's words and grammar.
- [ ] If a scheduled class day has no entry, offer to log it.

### 14. Fragen für die Stunde (questions for the teacher) · effort S
- [ ] **Shipped**

Source: `FSI-6`: "If an adult tells you that he needs something in order to learn, the chances
are very good that he's right." `FSI-9`: student and teacher share responsibility for the learning.

- [ ] An "Ask my teacher" action where the learner gets stuck: the word inspector, a correction
      card, a drill miss, a worksheet check.
- [ ] Questions park on the course and show before the next session.
- [ ] Ticking one off writes the answer into that session's class entry.

### 15. Bericht für die Lehrerin (a progress page to send) · effort M
- [ ] **Shipped**

Source: `DLI-TI`: feedback in writing that names the "deficiencies" and the "specific actions".
Here the learner hands that page to the teacher, so her lesson can start from what the app saw.

- [ ] One page per course since the last session: time practised, words learned, words that keep
      failing, weak grammar with two real example errors each, homework status, the open questions.
- [ ] The learner reads and edits it before sharing. Nothing is sent automatically.
- [ ] Shares the export path of the filled-in slides (`docs/WORKSHEETS.md`).

### 16. Sprechen vorbereiten (rehearse before a session) · effort S–M
- [ ] **Shipped**

Source: `DLI-STRAT` 3b: "Prepare an outline of what you want to say in conversation practice."

- [ ] Pick the session's topic from the course goal or the last entry, and jot an outline.
- [ ] Rehearse it with the on-device tutor. Useful phrases go to the course deck.

### 17. Korrekturen der Lehrerin (keep what she corrected) · effort M
- [ ] **Shipped**

Source: `DLI-STRAT` 3f: ask a teacher "to help you listen for and correct mistakes".

- [ ] Quick capture on a class entry: what I said, what she said instead.
- [ ] Each pair becomes a phrase or gap card (`docs/PHRASES.md`) and a slip in the learner
      profile, marked as confirmed by a teacher.
- [ ] No recording of the lesson itself. That needs her consent and is out of scope.

## F. Interview practice (Job prep)

### 18. Lebenslauf (your résumé in the interview) · effort M
- [ ] **Shipped**

Source: `DLI-FLO` lists "Bio data interview" as a speaking objective: talking about your own
background is a tested skill. `FSI-6`: adults learn faster when they have "things to talk about".

**The limit.** The posting already fills the tutor's reading window: 6,000 characters on the
largest tutor, 4,500 on the mid one, 3,000 on the small ones and Apple Intelligence, and 1,500
under Memory Saver (`JobContextBudget`). A one-page résumé is about 2,500–4,000 characters by
itself (an estimate, not measured). So the résumé never goes into the prompt whole.

- [ ] Import through the handout path: PDF, scan, photo, paste. Keep the full text on the
      device, uncapped, as `JobPosting.text` is.
- [ ] **Kurzprofil:** a digest of about 500 characters in German, written once at import:
      current role, years, main skills, two achievements, education, languages. The learner
      reads and edits it. What they see is what the tutor gets.
- [ ] **Facts:** the résumé split into short single facts (one role, one project, one degree).
- [ ] One budget, two parts: `JobContextBudget` gives the Kurzprofil a fixed slice (about 500
      characters, 300 under Memory Saver) and the posting the rest. The setup meter shows both.
- [ ] A fact per turn, not all up front: `ConversationPrompts.interviewProgressNote` already
      adds one line each turn naming the next plan point. The app adds the one fact that best
      matches that point, so the recruiter can ask about it by name.
- [ ] Without a posting: a short "tell me about yourself" interview that needs only the
      Kurzprofil (Werdegang, Stärken, a gap in the CV). It fits the small tutors.
- [ ] The words for your own career go to a deck through `CardKind` (`docs/PHRASES.md`).
- [ ] Measure first: on each tutor, check that the recruiter uses the fact and does not invent
      career details.
- [ ] Privacy: on the device only. Decide whether it syncs (a synced model needs its codec,
      `docs/ICLOUD_SYNC.md`). Never part of cloud pictures or the coach hand-off unless opted in.
- [ ] New `ConversationConfig` fields are copied at the four sites listed under item 8.
- [ ] Later: posting against résumé. Which requirements you cover, and which gaps need a
      prepared answer.

## G. Later, maybe

- [ ] **Übersetzen.** English to German sentences on the learner's weak tag, checked by the
      tutor. `DLI-FLO` "Translate an English text into the target language". Check what the
      Aufsatz check can share first.
- [ ] **Handschrift lesen.** Reading German handwriting. `DLI-FLO` "Read reasonably legible
      native handwriting".

## Not copying

- **The dose.** `FSI-4`: at least four class hours a day plus three of self-study, and FSI could
  not shorten its courses. An app borrows the task design, not the hours.
- **Immersion.** `FSI-4` says it pays off most at higher levels. `DTIC-SSF` found no significant
  test gain once selection was accounted for.
- **Aptitude testing.** `FSI-2`. It sorts students for a school and tells one learner little.
- **Learning styles.** The handbook's "visual learner / auditory learner" advice is dated.

## Sources to read next

Other well-regarded sources that could feed this list. None has been read yet, so none backs an
item or a citation. Reading one means: read the full text, add it to the source key, then write
its items. In rough order of payoff for this app:

- [ ] **Paul Nation, "What do you need to know to learn a foreign language?"** (Victoria
      University of Wellington, 2014, 56 pages,
      [archived PDF](https://web.archive.org/web/20191006020058/https://www.victoria.ac.nz/lals/about/staff/publications/paul-nation/foreign-language_1125.pdf);
      the university's own link refuses downloads).
      Look for: the four equal strands (input, output, deliberate study, fluency) as an audit of
      where study time goes, and his fluency activities. A class usually covers some strands, so
      Today could steer to the others.
- [ ] **Peace Corps, "Volunteer On-going Language Learning Manual" (M0064)**
      (106 pages,
      [PDF](https://files.peacecorps.gov/multimedia/pdf/library/M0064_ongoinglanguage.pdf)).
      Look for: learning plans, assessing your own progress, working with a language helper.
      The closest fit for tutor use (section E).
- [ ] **BAMF / Goethe-Institut, "Rahmencurriculum für Integrationskurse Deutsch als Zweitsprache"**
      ([2017 PDF](https://www.goethe.de/resources/files/pdf209/rahmencurriculum-integrationskurs_20171.pdf)).
      Austria's Integrationsfonds publishes its own for A1–B2. Look for: the Handlungsfelder
      (work, offices, housing, health) and their can-do goals, as conversation scenarios and as
      tags on class entries.
- [ ] **Council of Europe: CEFR Companion Volume (2020) and the European Language Portfolio**
      ([descriptors](https://www.coe.int/web/common-european-framework-reference-languages/cefr-descriptors),
      [portfolio](https://www.coe.int/web/portfolio/introduction)). Look for: mediation tasks
      (pass on in German what an English text says), and the passport, biography and dossier as
      a model for item 15.
- [ ] **Education Endowment Foundation, Teaching and Learning Toolkit: one-to-one tuition**
      ([page](https://educationendowmentfoundation.org.uk/education-evidence/teaching-learning-toolkit/one-to-one-tuition)).
      Look for: tuition "additional to, but explicitly linked with, normal teaching", and short
      regular sessions. Evidence for section E.
- [ ] **Dunlosky et al. 2013, "Improving Students' Learning With Effective Learning Techniques"**
      (Psychological Science in the Public Interest). Ranks study techniques: practice testing
      and spaced practice high, rereading and highlighting low. Use it to audit where the app
      still lets the learner reread.
- [ ] **Goethe-Zertifikat model papers, A1–B2.** The task formats for Hören, Lesen, Schreiben
      and Sprechen. Link not checked yet.
- [ ] **ACTFL core practices and the Integrated Performance Assessment.** One text carried
      through reading, talking and presenting. Named from memory; link not checked yet.
- [ ] **Missionary Training Center, "Preach My Gospel" chapter 7**
      ([text](https://www.churchofjesuschrist.org/study/manual/preach-my-gospel-2023/15-chapter-7)).
      A language study plan with a weekly self-check. No outcome data found.
- [ ] **Middlebury Language Schools, the Language Pledge.** A German-only mode. Low priority:
      `FSI-4` says immersion pays most at higher levels. Named from memory.
- [ ] The three "search summary only" rows in the source key: `ODA`, `CASL`, `DTIC-SSF`.
