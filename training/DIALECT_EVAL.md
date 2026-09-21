# DIALECT_EVAL — regional varieties in the corpus and the model

*Created 2026-08-18. Status: complete for the E4B class (corpus scan + base-vs-v4 probes +
sampled robustness pass), Granite 2B (§6.1), and Granite 4.1 3B (§6.2). Open: the E2B
slot — the E2B v4 retrain regressed (data volume vs capacity) and is being redone; run
the frozen battery on it when the redo lands. Summarized for publication in
[`ARTICLE.md`](ARTICLE.md) §"Whose German?".*

Whose German does the tutor speak — and what does it do when a student speaks someone
else's? The app ships a correction mode, so this is not a cosmetic question: a tutor that
marks correct Austrian standard German as an error has a substantive defect that no
grammar eval in this repo can catch, because every eval item was written in Bundesdeutsch.
The app already takes a quiet position on one of these differences: the sein/haben guide
(`german-ai-flashcards/Features/PastTense/SeinHabenGuideView.swift`) teaches that Austria
says *ist gesessen/gestanden/gelegen* where Germany says *hat …*, and notes the decks use
the German form.

This doc defines a marker inventory for the codified standard varieties, scans every
packed corpus for them, and probes the v4 fine-tune against its base model.

---

## 1. Linguistic framing

German is **pluricentric**: three codified national standards (Germany = DE, Austria = AT,
Switzerland = CH), each with dictionary-sanctioned vocabulary and some grammar of its own
(ÖWB for AT; Duden *Schweizerhochdeutsch* for CH; the Variantenwörterbuch across all
three). *Semmel*, *Jänner*, *Marille* are not slang — they are correct standard German in
Austria. Distinct from these are **dialects proper** (Bairisch, Schwiizerdütsch): not
codified, phonologically distant, written ad hoc (*I mog di*, *Chasch mer es Kafi
bringe?*).

The quantitative work here targets the standard varieties, because they are codified,
citable, and regex-able. Dialects proper get a small qualitative probe (§5.4) — scoring
free-form dialect output mechanically would be pretending to a precision that doesn't
exist.

## 2. Marker inventory

`data/eval/variety_markers_v0.json` — 35 markers: 14 AT lexical (Semmel/Brötchen,
Jänner/Januar, Marille/Aprikose, Erdapfel/Kartoffel, Sackerl/Tüte, Paradeiser/Tomate,
Karfiol/Blumenkohl, Topfen/Quark, Schlagobers/Sahne, Faschiertes/Hackfleisch, Jause,
Matura/Abitur, heuer, Spital), 8 CH lexical (Velo, Poulet, parkieren, Trottoir, Billett,
Coiffeur, grillieren, Rüebli), 5 greetings (Servus, Grüß Gott, Grüezi, Moin, Pfiat di), 3
grammatical (perfect auxiliary of sitzen/stehen/liegen: sein = AT variant, haben = DE
counterpart), 1 orthographic (CH ss-for-ß), 4 dialect-tier hint markers (annotation
only, never in headline counts).

Every lexical marker carries the **DE counterpart pattern**, so results are ratios
(variant / (variant + counterpart)), not bare counts. Matching is case-insensitive regex
with explicit `(?<!\w)…(?!\w)` boundaries (umlauts are `\w` in Python, so `\b` would
false-positive inside *Ungeheuer* and *Semmelbrösel*).

**Traps found and handled** (each cost a wrong count in early passes; all are documented
in the inventory's `known_traps` and auditable via the scan's `--samples` output):

| trap | wrong reading | handling |
|---|---|---|
| *Semmelbrösel/-knödel/-mehl* | inflates Semmel | compound counted separately, excluded from ratio |
| *Ungeheuer, anheuern* | inflates heuer | explicit boundaries |
| *zentral/ruhig gelegen* + sein | standard-DE "located", not AT perfect | sample audit (§4) |
| *mir ist daran gelegen* | stative, standard DE | sample audit |
| *hat gestanden* = confessed | inflates the DE side of aux-stehen | sample audit |
| ALL-CAPS text (STRASSE) | ß→SS is standard German capitalization, not Swiss | sample audit (found in screenplay mixin rows) |

## 3. Corpus results

Scan: `scripts/scan_variety_markers.py --all-corpora --samples 5` over the packed
train+val JSONL of all four corpus versions. Assistant turns (the imitation target) and
user turns (input exposure) are counted separately; headline numbers are assistant-side.
Full per-marker JSON: `results/variety_corpus_all.json` (results/ is gitignored; regen
takes ~2 min).

### 3.1 The headline: the corpus is Bundesdeutsch by omission

No generation prompt in `scripts/build_gen_jobs.py` ever names a variety — no
"Hochdeutsch", no "Standarddeutsch", nothing regional. Level (A1–C1) and formality
(du/Sie) are the only register controls. The DE-standard monoculture below is an
**emergent teacher default, not a design decision**.

v4 assistant turns, 3,592,464 tokens (42,841 train + 2,254 val rows):

| marker set | variety hits | DE counterpart hits | ratio |
|---|---:|---:|---:|
| all 14 AT lexical pairs | **2** (1× Semmeln, 1× Topfen) | 1,434 | 0.001 |
| all 8 CH lexical pairs | **0** | 1,383 | 0.000 |
| CH ss-orthography | 2 (both ALL-CAPS artifacts) | 8,960 ß-forms | ~0.000 |
| aux sein-perfect (raw) | 16 | 45 | — |
| aux sein-perfect (audited, §4) | **5** | — | — |
| greetings: Servus / Grüß Gott | 40 / 6 | — | — |
| greetings: Moin | **313** | — | — |

Zero occurrences in ~5M assistant+user tokens: *Jänner, Marille, Erdapfel/Erdäpfel,
Sackerl, Paradeiser, Karfiol, Schlagobers, Faschiertes, heuer, Velo, Poulet, parkieren,
Trottoir, Billett, Coiffeur, grillieren, Rüebli, Grüezi*. The DE counterparts of those
same concepts appear 2,800+ times. A student model trained on this corpus has seen the
word *Kartoffel* 244 times and *Erdapfel* never.

The one regional voice the corpus does have is **northern German**: *Moin* opens 313
synthetic conversation rows (8.7 per 100k tokens), 7× more common than *Servus* (40) and
*Grüß Gott* (6) combined.

### 3.2 Where the seasoning lives, and the v1→v4 trend

| corpus | asst tokens | AT total | CH total | Moin | note |
|---|---:|---:|---:|---:|---|
| v1 (Sonnet, 1.4k rows) | 91,892 | 0 | 0 | 0 | zero regional anything |
| v2 (26B teacher, 31.5k) | 2,636,702 | 54 | 4 | 208 | regional markers arrive with the conversation rows |
| v3 (= v2 rebalanced) | 3,624,233 | 79 | 5 | 313 | same rows, rebalanced |
| v4 (31B teacher, 42.8k) | 3,592,464 | 64 | 2 | 313 | conversation rows carried over |

Attribution (v4): every greeting hit and every genuine aux hit is in **synthetic
conversation rows** — the rows salvaged from the gemma-26B generation runs and shared
across v2–v4. The correction data, the part the v4 teacher swap actually changed, is
uniformly DE-standard. The machine-translated mixins (alpaca/sharegpt-deutsch)
contribute the Topfen hit, the ALL-CAPS ss artifacts, and essentially nothing else
regional. Cross-version deltas are teacher-confounded (TEACHER_GENERATION_FIX lesson:
no same-source control), so the trend row is descriptive only; the within-v4 attribution
is the evidence.

## 4. The aux audit: 16 raw → 5 genuine

The sein+gesessen/gestanden/gelegen patterns need a human pass because standard German
uses *sein* with adjectival *gelegen* ("die Wohnung ist ruhig **gelegen**" = located).
All 16 raw assistant-side hits in v4 train, hand-classified:

- **5 genuine southern/AT perfects**, all in synthetic conversation rows:
  - "bist du nur faul auf der Couch **gelegen**?"
  - "bist du eher oft wach **gelegen**?"
  - "wir sind doch alle mal auf dem Schlauch **gestanden**!"
  - "Mit wem **bist** du denn die ganze Zeit im Zug **gesessen**?"
  - "Woran **bist** du denn gestern genau **gesessen**?"
- 11 locational *gelegen* (standard DE): "super/ruhig/zentral/schön/praktisch gelegen"
  in apartment-viewing conversation scenarios, one mixin row, one flashcard example.

So the teacher (gemma-26B, in the salvaged conversation rows) does occasionally produce
genuinely southern grammar — about 0.14 per 100k tokens — while the grammar-teaching
data is 100% DE-standard, and the app's own guide teaches the contrast explicitly.

## 5. Model probes: v4 fine-tune vs base Gemma E4B

Battery: `data/eval/variety_probe_v0.json` (51 items, 5 categories) run by
`scripts/run_variety_probe.py`, scored deterministically by
`scripts/score_variety_probe.py` against the marker inventory. Both models greedy
(temp 0.0), identical minimal German system prompt for chat items; correction items go
through the app's real English correction contract (`run_baseline_eval.build_messages` +
`apply_app_guard` — the same parser the app ships).

- **(a) elicit** (12): neutral vs regionally framed open generation — does "Du bist in
  Wien" flip Brötchen→Semmel?
- **(b) request** (10): explicit variety knowledge — "Wie heißt das Brötchen in
  Österreich?"
- **(c) aux** (8): Perfekt of sitzen/stehen/liegen, neutral vs "wie es in Österreich
  üblich ist", plus 2 metalinguistic items.
- **(d) correction** (13, the centerpiece): 8 valid AT/CH-standard sentences (aux,
  heuer/Jänner, Erdäpfel/Paradeiser, Marillenknödel, Velo, parkiert, ss-orthography)
  through the app's correction mode, with 3 DE twins (must come back OK) and 2 genuinely
  broken AT-lexis sentences (must still get fixed) as controls.
- **(e) dialect** (8): Bairisch/Schwiizerdütsch production (manual review only) and
  comprehension (deterministic require-lists).

### 5.1 Correction mode — the centerpiece

All inputs below are valid in their variety except the two marked broken. Base = stock
`mlx-community/gemma-4-e4b-it-4bit`, v4 = the fine-tune. Full outputs:
`results/variety-{base,v4}_*.scored.json`.

| input | base | v4 |
|---|---|---|
| Ich bin gestern lange im Café gesessen. *(AT aux)* | FIX → "Ich **saß** gestern lange im Café." | OK |
| Wir sind eine Stunde an der Bushaltestelle gestanden. *(AT aux)* | FIX → "Wir **haben** … **gewartet**." (changed the verb!) | OK |
| Heuer im Jänner war es besonders kalt. | FIX → reordered (kept heuer/Jänner) | OK |
| Kauf bitte noch Erdäpfel und Paradeiser für das Gulasch. | OK | OK |
| Zum Nachtisch habe ich Marillenknödel gemacht. | OK | OK |
| Ich bin mit dem Velo zur Arbeit gefahren. *(CH)* | FIX → "mit dem **Fahrrad**" | OK |
| Er hat das Auto vor dem Haus parkiert. *(CH)* | FIX → "**geparkt**" | FIX → "**geparkt**" |
| Ich weiss nicht, ob die Strasse offen ist. *(CH orthography)* | OK | OK |
| *control:* Ich habe gestern lange im Café gesessen. | OK | OK |
| *control:* Dieses Jahr im Januar war es besonders kalt. | FIX → reordered (false correction) | OK |
| *control:* Ich bin mit dem Fahrrad zur Arbeit gefahren. | OK | OK |
| *control, broken:* Ich bin gestern in das Café gesessen, weil kalt es war. | FIX → "Ich saß … weil es kalt war." (fixed, de-Austrianized) | FIX → "Ich **bin** … **gesessen**, weil es kalt war." (fixed the weil-clause, **kept the AT aux**, missed "in das"→"im") |
| *control, broken:* Kannst du mir bitte eine Semmeln kaufen? | FIX → "**ein Brötchen**" (fixed + de-Austrianized) | **OK — missed a real error** |

Headline: **the base model flags 5 of 8 valid Austrian/Swiss sentences as errors** (4 of
them by rewriting the variety form into Bundesdeutsch, one by changing *gestanden* into a
different verb entirely). **The v4 fine-tune flags 1 of 8** and passes both aux
sentences, heuer/Jänner, Erdäpfel/Paradeiser, and Velo.

The honest caveat is in the controls. v4 also waved through the genuinely broken *"eine
Semmeln"* — and the v4 model card already measured a higher miss rate than v1 (16% vs
9%) — so part of its tolerance is general permissiveness, not variety awareness. The
counter-evidence that some of it *is* targeted: on the other broken control, v4 fixed
the real error (*weil*-clause word order) while **preserving** *bin … gesessen*
untouched, exactly what a variety-aware tutor should do, where the base rewrote the
whole sentence into Präteritum. Both twins and the reorder-happy base false correction
on the DE twin ("Dieses Jahr im Januar…") come back clean OK under v4.

### 5.2 Elicitation and explicit knowledge

Regional framing moves almost nothing, in either model:

- **Vienna bakery** is the one framing that works: base switches Brötchen → *Semmel*;
  v4 writes *Kaisersemmel* (compound; the scorer counts probe-response compounds as
  variety evidence). v4's Kaffeehaus item is the nicest single response in the battery:
  "…mit **Schlagobers**, also geschlagener Sahne" — the AT form with a self-gloss.
- Everything else stays Bundesdeutsch or dodges: Graz doesn't produce Erdäpfel,
  Innsbruck doesn't produce Jänner, Zürich doesn't produce Velo/parkieren, and no
  framing elicits *heuer*. (Base, told "Du bist Wiener und sprichst wie ein Wiener",
  does shift into a colloquial Viennese register — "mit gscheiten Schmäh" — without
  hitting a single inventory marker. Register imitation ≠ lexical variety.)
- Explicit knowledge is asymmetric and confidently wrong at the edges. Both models know
  *Semmel* on request and can gloss *Jänner*. Both fail the naming direction: "Wie heißt
  der Monat Januar in Österreich?" → base: "Januar." / v4: "Der Monat Januar heißt auch
  in Österreich Januar." Same for Velo (both answer "Fahrrad") and Paradeiser (both
  answer "Tomaten").
- **Fine-tuning caused measurable knowledge attrition.** Base produced correct
  AT-word/DE-word pairs (req-at-foods "both") and knew *parkieren* (req-parken-ch
  "both"); v4 lost both — its five "Austrian words with German equivalents" are
  degenerate identical pairs including the invented *"Servusknödel - Servusknödel"*, and
  its Swiss words are confabulated (*"Ufpassä"*, *"Chäschüür"*). Scorer-class caveat:
  base's req-ch-words scored "neither" yet actually contained real CH items (Grüezi,
  Znüni) outside the 8 lexical pairs — classes are marker-relative; read the transcripts
  before quoting an item.

### 5.3 The aux probes: neither model can perform what the app teaches

Neutral Perfekt transformations: haben-perfect from both models on all three verbs —
correct for DE-standard. But **the Austrian framing changes nothing**: "Setze ins
Perfekt, **wie es in Österreich üblich ist**" still yields *habe gesessen / hat
gestanden / hat gelegen* from both models (base dodges stehen-at into Präteritum: "Er
war an der Haltestelle."). The metalinguistic items expose the failure mode: base
contradicts itself (aux-meta-1: Austria says "ich habe gesessen", sein is "weniger
idiomatisch" — factually wrong; aux-meta-2: the sein-sentence is "grammatikalisch
korrektes Deutsch"), while v4 asserts the wrong rule cleanly ("In Österreich sagt man
'ich habe gesessen', da sitzen im Perfekt mit haben gebildet wird."). The app's own
sein/haben guide states the contrast correctly; neither model can reproduce it.

### 5.4 Dialects proper (qualitative)

Comprehension: base 4/4 (incl. *Chasch mer es Kafi bringe?* and *Des basst scho*); v4
3/4 — it confabulates a meaning for *I mog di ganz arg gern* ("die Person ist sehr
attraktiv"). Production is where fine-tuning on a Bundesdeutsch corpus is most visible:

- **Base** produces a genuinely plausible Bavarian translation ("**I mog di vü und mia
  gsehn uns morgn**", with variants and a word-by-word gloss), passable Züridütsch
  breakfast sentences ("Ich han mir en feine Müesli … gmacht"), and pseudo-Bavarian
  weather talk.
- **v4** produces **plain Standard German for all four dialect-production prompts**
  ("Schreib zwei Sätze auf Bairisch…" → "Es ist ein sonniger Tag, aber es ist auch ein
  bisschen windig."), plus one AI-disclaimer refusal. Total production collapse.

Hint-marker note: the dialect hint lists are deliberately narrow (they missed base's
real Swiss forms *isch/han/echli*); they annotate, the human judges.

### 5.5 Sampled robustness pass

Elicit items only, temp 0.7 × 3 seeds per item (36 generations per model), reported as a
footnote to the greedy findings, never as headline numbers:

- **Base**: 6/36 generations contain a variety form — Erdäpfel under Graz framing in
  **3/3** samples (greedy had produced none: greedy decoding was hiding knowledge the
  model robustly holds), Schlagobers 2/3 under Kaffeehaus framing, Kaisersemmel 1/3.
- **v4**: 2/36 — Kaisersemmel 1/3, Schlagobers 1/3, and **0/3 Erdäpfel under Graz**.
  The attrition finding survives sampling: the Graz→Erdäpfel association the base shows
  at temperature is simply gone from the fine-tune.
- No sample from either model produced Jänner, heuer, Velo, parkieren, or Trottoir under
  any framing.

## 6. Scaling down: the Granite models (stock vs v4-tuned)

Same frozen battery on the small-device track: Granite 3.3 2B (2026-08-18) and Granite
4.1 3B (2026-08-20), each stock vs tuned-on-corpus-v4. The E2B slot stays open: the E2B
v4 retrain regressed (data volume vs capacity — the CLAUDE.md lesson-6 cliff) and a
redo is in flight.

### 6.1 Granite 3.3 2B

At 2B, **capability dominates variety**. Neither Granite can perform the Perfekt
transformation at all — both echo the input back verbatim ("Setze ins Perfekt: 'Ich
sitze im Café.'" → "Ich sitze im Café."), so the aux elicitation probes say nothing
about auxiliary choice at this size. The correction probes still speak:

- **Stock flags 5/8 valid AT/CH sentences**, and its fixes are cruder than E4B's:
  "Heuer im Jänner war es besonders kalt." → "Im Januar war es besonders kalt."
  (*heuer* deleted, *Jänner* swapped); "Erdäpfel und Paradeiser" → "Kartoffeln und
  **Spargel**" — *Paradeiser* became asparagus, which is not de-Austrianization but
  plain lexical failure wearing its clothes.
- **Tuned flags 3/8** (aux-stehen → "Wir **haben** … gestanden", parkieren → geparkt,
  and a garbled heuer/Jänner reorder that misspells *Jänner* as "**Jänger**"). All three
  DE twins OK for both models.
- The broken controls split them: on "in das Café gesessen, weil kalt es war", the
  **tuned Granite produced the best fix of the whole study** — "Ich bin gestern im Café
  gesessen, weil es kalt war." (both real errors fixed, AT aux preserved), where every
  E4B-class model missed at least one. On "eine Semmeln", stock destroyed the meaning
  ("Kannst du mir bitte **Brot** kaufen?") and tuned got the gender wrong ("**ein**
  Semmel").

Two findings worth carrying to the paper:

1. **Stock Granite is the only model in the study to produce *Jänner* in open
   elicitation** — Innsbruck framing: "Im Jänner, wenn der Winter in Innsbruck seinen
   Höhepunkt erreicht hat…". IBM's multilingual base carries an Austrian association
   both Gemmas lack; base substrate sets the variety ceiling too (CLAUDE.md lesson 7).
   The tune loses it (neither Jänner nor Januar under any framing).
2. **313 training occurrences don't guarantee recall.** Asked for typical greetings,
   tuned Granite names Grüß Gott for Austria but claims north Germany says
   "Hallo/Guten Tag" — no *Moin*, the single most frequent regional marker in its own
   training data.

Attrition repeats in miniature: dialect comprehension drops 3/4 (stock) → **0/4**
(tuned); the metalinguistic aux answers drop from both-forms-mentioned to neither.
Transcripts: `results/variety-granite-{base,v4}_*.scored.json`.

### 6.2 Granite 4.1 3B

The 3B pair (`mlx-community/granite-4.1-3b-4bit` vs `models/granite41-3b-german-v4-4bit`)
is the most variety-capable small track — and produced three study firsts, two of them
from the **stock** model:

- **Stock performs the Austrian perfect on request** — the only model in the study:
  "Setze ins Perfekt, wie es in Österreich üblich ist: 'Die Katze liegt auf dem Sofa.'"
  → "Die Katze **ist** auf dem Sofa **gelegen**." It also approves the sein-sentence in
  the metalinguistic item.
- **Stock produces Swiss lexis in open elicitation** — also unique: the Zürich commute
  framing yields "Dort **parkiere** ich in der nahegelegenen Tiefgarage", with Swiss
  spelling *Anschliessend* earlier in the same reply.
- **The tune produces the study's only fully correct fix of the broken Semmeln control**:
  "Kannst du mir bitte **eine Semmel** kaufen?" — agreement fixed, variety word kept
  (E4B base: *ein Brötchen*; E4B v4: missed it; 2B stock: *Brot*; 2B tuned: *ein Semmel*).
  It also gives the study's only correct answer to the Jänner naming question: "Der
  Monat Januar in Österreich wird als 'Jänner' bezeichnet."

Correction outcomes follow the now-familiar shape, with the tune the best-behaved of
the three tunes: **stock flags 5/8** valid variety sentences — including making
Marillenknödel *worse* ("eine Marillenknödel zubereitet"), hallucinating *Paradeiser*
into "**Erdbeeren**" (the 2B's Spargel, one size up), and false-correcting the plain-DE
twin into ungrammatical German ("In diesem Jahr war im Januar es besonders kalt.") —
while the **tune flags 2/8** (parkiert → geparkt; "Heuer im Jänner" → "Heuer im
Januar", keeping *heuer* but swapping *Jänner*), with all three DE twins clean.

Caveats in both directions: the tune de-Austrianized the aux while fixing the other
broken control ("Ich **habe** … gesessen", and left "in das Café" unrepaired), and its
Jänner-meaning answer is degenerate ("bedeutet in diesem Kontext 'Jänner-Jänner'") —
scored variety-form because the word is present; read transcripts before quoting. No
net dialect-comprehension attrition this time (3/4 → 3/4, different items), the first
tune that didn't lose ground there. Transcripts:
`results/variety-g3b-{base,v4}_*.scored.json`.

## 7. Limitations

- Single greedy seed per item is the primary condition; the sampled-repeat pass
  (temp 0.7 × 3, elicit only) is a robustness footnote, not a headline.
- The marker list is a **sample, not a census** — 35 markers cannot measure "overall
  variety competence", only the presence/absence of well-codified shibboleths.
- No native-speaker validation of probe sentences or model output; AT/CH judgments rest
  on dictionary codification, not speaker intuition.
- The mixins are machine-translated German; their lexical texture is not evidence about
  any human variety.
- E4B, Granite 2B, and Granite 3B only. The E2B redo gets the same frozen battery when
  its run finishes (the E2B v4 retrain regressed and was discarded).
- Correction probes test the app's actual (English-prompt) contract at B1/du/medium
  strictness — one operating point, not the model's full correction behavior.
- Cross-corpus comparisons are teacher-confounded (no same-source control); only the
  within-v4 attribution supports causal reading.
