# Genitiv round (2026-10-07)

88 items for the Genitiv unit, each with a Genitiv attribute right behind its noun: 30 Rollen
(„Der Vogel des Opas schläft“), 30 Wer macht was? („Den Vater des Kindes fragt die Oma“), 28 Die
Probe („Der Chef trägt die Tasche der Tante“, asked with „des Mannes“). They replace the main
batch's 42 Genitiv Wer items, which held no Genitiv. All 88 pass the gate and
`audit-concepts candidates.json` (88/88).

Same files as the main batch (`review.csv`, `review.md`, `candidates.json`, ids `kc-sg-…`);
`BRIEF.md` adds the attribute rules to `../BRIEF.md`.

**Claude's read (first pass):** all 88 read; German correct, every attribute directly behind its
noun, no wrong case or role. Thin but grammatical: adults who „spielen“ („Der Freund der Kollegin
spielt nach der Arbeit“), many horses, and one heavy double Genitiv-looking pair („Der Opa
antwortet der Schülerin der Lehrerin“: Dativ partner, then the Genitiv; correct, but a hard read).

**How the planner picks a possessor:** a table of plausible relations (`possessors` in
`KasusConceptPlanner`): a pet can be anyone's, a child an adult's, a teacher a pupil's, a doctor a
patient's; a thing („den Schlüssel“) can be anyone's. Without it the first draft had „das Mädchen
der Kollegin“ and „die Mutter des Bruders“.

**Research behind it:** the attribute follows its noun (the reverse of English „the man's car“),
is found by asking „Wessen?“, takes -s/-es on masculine and neuter nouns and „der“ on feminine and
plural, and mostly shows possession or belonging; spoken German often uses „von“ + Dativ instead,
which is why reading it matters more than producing it. Sources: Quillbot, „Genitivattribut“
(https://quillbot.com/de/blog/satzbau/genitivattribut/); Happy German, „The German Genitive Case,
von + Dative Instead of Genitive“
(https://blog.happygerman.com/the-german-genitive-case-von-dative-instead-of-genitive-with-exercises/);
Dartmouth German grammar, „Genitive“ (https://www.dartmouth.edu/~german/Grammatik/Nouns/genitive.html).
