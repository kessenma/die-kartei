#!/usr/bin/env python3
"""Build the Phase 1 generation manifest — what the teacher is asked to write, and how much.

Runs locally, needs no GPU. Emits `data/gen_v2/jobs.jsonl`, one teacher prompt per line, which
`runpod/gen_v2/generate.py` then batches through vLLM on the pod.

Design notes:

* **Seeded, not free-form.** Correction jobs are pinned to a specific verb/preposition drawn from
  `data/verb_praep_table.json` (268 curated entries) and a specific phenomenon, because the
  validator can only structurally check what it was told to expect. Asking a teacher for "some
  grammar mistakes" produces items nothing can verify.
* **Targets the measured defects.** Phase 0's naturalness baseline found the shipped models thin
  on modal particles (~2.8/100 tokens), repeating a top-5 4-gram in ~30% of replies, and leaning on
  one question opener (E4B: `Woran…` for 23% of its questions). The conversation prompt below
  demands the opposite, explicitly.
* **Covers the gaps v1 missed** — nudgeMe HINT lines, the 12 GrammarFocus steering variants and the
  23 typed scenario roles. See DATA_V2_DISTILL_PLAN.md and training-v2.md §Phase 1.

Usage:
    .venv/bin/python scripts/build_gen_jobs.py --target 40000
    .venv/bin/python scripts/build_gen_jobs.py --target 200 --out data/gen_v2/jobs_smoke.jsonl
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import app_prompts as ap

LEVELS = ["A1", "A2", "B1", "B2", "C1"]
LEVEL_W = [8, 26, 34, 24, 8]
FORMALITY = ["du", "Sie"]
FORMALITY_W = [72, 28]

# Share of the corpus per slice — the mix chosen in DATA_V2_DISTILL_PLAN.md Phase 1.
SLICE_MIX = {
    "correction": 0.40,
    "conversation": 0.30,
    "flashcards": 0.15,
    "recovery": 0.10,
    "native_instruction": 0.05,
}

# Items the teacher produces per call. Bigger batches are cheaper but degrade in quality and
# raise the chance one malformed line costs the whole response.
# recovery dropped 6 -> 3 on 2026-07-28: conversation_recovery items became 5-message dialogues
# (validate_conversation's floor), so asking for 6 per job meant 30 turns of output and the teacher
# delivered ~1.2. Asking for less reliably returns more.
PER_JOB = {"correction": 8, "conversation": 2, "flashcards": 3,
           "recovery": 3, "native_instruction": 5}

# VALID items per job actually observed, after the validator. Measured on the 2026-07-28 smoke
# runs (40 stratified jobs), NOT assumed from PER_JOB — the teacher under-delivers on count for
# the slices with long outputs, and some of what it does deliver is rejected. Sizing the manifest
# off PER_JOB would have produced ~28k valid items where 40k was asked for.
#
# Pooled over the smoke runs, counting only runs that had the fix each slice depended on:
#   correction  114 valid / 28 jobs  = 4.07
#   conversation 20 valid / 16 jobs  = 1.25   (post-trim only; pre-trim was 0.83)
#   flashcards   23 valid /  9 jobs  = 2.56
#   native       18 valid /  6 jobs  = 3.00
#   recovery      — measured 0.80 at PER_JOB=6; estimated 1.50 at PER_JOB=3, the least certain
#                   number here. Over-provisioned deliberately; a surplus is subsampled at pack
#                   time, a shortfall means renting the GPU again.
# Re-measure and update whenever the prompts, PER_JOB, or validator change.
MEASURED_VALID_PER_JOB = {
    "correction": 4.07,
    "conversation": 1.25,
    "flashcards": 2.56,
    "recovery": 1.50,
    "native_instruction": 3.00,
}

CARD_TOPICS = [
    "Küche und Kochen", "Reisen mit dem Zug", "im Büro", "Wetter und Jahreszeiten", "Gesundheit",
    "Einkaufen im Supermarkt", "Wohnung und Möbel", "Sport und Fitness", "Musik und Konzerte",
    "Schule und Studium", "Tiere", "Kleidung", "Familie und Verwandte", "Verkehr in der Stadt",
    "Werkzeug und Reparaturen", "Garten und Pflanzen", "Feste und Feiertage", "Beim Arzt",
    "Bank und Geld", "Handwerk", "Natur und Wandern", "Restaurant und Bestellen", "Technik",
    "Umwelt und Klima", "Nachrichten und Politik", "Kunst und Museum", "Bahnhof und Flughafen",
    "Post und Behörden", "Freizeit am Wochenende", "Berufe",
]

CONV_TOPICS = [
    "Wochenendpläne", "ein stressiger Arbeitstag", "Heimweh", "Umzug in eine neue Wohnung",
    "Kochen und Rezepte", "eine Reiseerinnerung", "Sport und Bewegung", "Musik und Konzerte",
    "die Familie", "Kindheitserinnerungen", "ein Missgeschick", "Pläne für den Urlaub",
    "das Wetter und die Jahreszeit", "Nachbarn", "Haustiere", "Bücher und Filme",
    "die Arbeit wechseln", "Deutsch lernen", "Freunde treffen", "ein Fest feiern",
    "Geld und Sparen", "Gesundheit und Schlaf", "Technik im Alltag", "Ehrenamt",
]

NATIVE_TASKS = [
    "eine kurze E-Mail schreiben", "einen Sachverhalt einfach erklären",
    "eine Liste mit Vorschlägen machen", "einen kurzen Text zusammenfassen",
    "Vor- und Nachteile abwägen", "eine höfliche Absage formulieren",
    "eine Wegbeschreibung geben", "ein Rezept in Schritten beschreiben",
    "eine Beschwerde sachlich formulieren", "einen Termin verschieben",
]

# --------------------------------------------------------------------------- prompt templates

CORRECTION_SYS = """Du bist eine erfahrene Deutschlehrerin und erstellst Trainingsdaten für einen \
Sprachlern-Assistenten. Du schreibst realistische Lernerfehler und ihre Korrekturen.

Regeln:
- Der Lernersatz muss klingen, als hätte ihn ein echter Deutschlerner GESPROCHEN: Alltagsthemen, \
natürliche Satzlänge, keine Lehrbuchsätze.
- Bei verdict "fix" darf GENAU EIN klarer Fehler im Satz sein, und zwar der geforderte Fehlertyp.
- Bei verdict "ok" ist der Satz vollständig korrekt und natürlich. Diese Sätze sind genauso wichtig: \
sie bringen dem Modell bei, korrektes Deutsch NICHT zu "korrigieren".
- Beide Sorten enthalten die Zielstruktur: bei "fix" falsch verwendet, bei "ok" richtig verwendet.
- "fix" ist immer der VOLLSTÄNDIGE korrigierte Satz, nicht nur das geänderte Wort.
- "why" ist eine kurze Erklärung AUF ENGLISCH, höchstens 18 Wörter, mit deutschen Begriffen in \
Anführungszeichen.
- Wiederhole keine Sätze und variiere Personen, Zeitformen und Themen stark.

Antworte AUSSCHLIESSLICH mit JSON-Zeilen (JSONL), eine pro Zeile, ohne Einleitung und ohne \
Markdown-Codeblock."""

CORRECTION_USER = """Schreibe {n} Trainingsbeispiele.

Fehlertyp: {phen_desc}
{target}
Niveau: {level}   Anrede: {formality}

WICHTIG — die Mischung: GENAU {n_fix} Zeilen mit verdict "fix" (Satz enthält den Fehler) und \
GENAU {n_ok} Zeilen mit verdict "ok" (Satz ist fehlerfrei). Schreibe zuerst die {n_fix} \
"fix"-Zeilen, danach die {n_ok} "ok"-Zeilen. Eine Antwort ohne "fix"-Zeilen ist unbrauchbar.
{hint_rule}
Schema pro Zeile:
{{"task":"correction","phenomenon":"{phen}","level":"{level}","formality":"{formality}",\
"partner":null,"student":"...","verdict":"fix"|"ok","fix":"..."|null,"why":"..."|null,\
"hint":"..."|null,"meta":{meta}}}"""

HINT_RULE = """Bei {n_hint} der "fix"-Zeilen setze zusätzlich "hint": eine KURZE deutsche \
Rückfrage, die den Lerner auf seinen Fehler stößt, OHNE die Lösung zu verraten. Nenne die \
Grammatik-Kategorie, z. B. "Welcher Fall kommt nach 'mit'?" oder "Wo steht das Verb im \
Nebensatz?". Das korrigierte Wort darf NICHT im Hint vorkommen. Bei allen anderen Zeilen \
"hint":null."""

# The `refl` and `sep` entries carry worked examples and an explicit self-check. That is not
# decoration: the terse one-line versions (kept below in the comments) named the right error type
# and still produced 12% hard-case reflexives and 26% word-order rows mislabelled as separable
# verbs — see TEACHER_GENERATION_FIX.md §2-3. Those two phenomena are the ones where a teacher has
# to decide *which* subtle thing is wrong, and the terse description let it default to the easy
# reading. The expanded versions were measured at 100% correct shape on gemma-4-31B.
#
# Previous terse versions, for reference:
#   "sep":  "trennbares Verb falsch getrennt (Präfix nicht abgetrennt im Hauptsatz, oder
#            fälschlich getrennt im Nebensatz)"
#   "refl": "fehlendes oder falsches Reflexivpronomen (auch Akkusativ statt Dativ)"
PHEN_DESC = {
    "vmp": "falsche Präposition bei einem Verb mit fester Präposition",

    "sep": """Fehler in der VERBFORM eines trennbaren oder untrennbaren Verbs.

ENTSCHEIDEND: Der Fehler MUSS in der Verbform liegen — Präfix falsch angehängt, falsch abgetrennt, \
oder Partizip falsch gebildet. NIEMALS eine reine Umstellung anderer Satzglieder.
SELBSTPRÜFUNG: sortiert(Wörter von "student") darf NICHT gleich sortiert(Wörter von "fix") sein.
RICHTIG:  "Ich aufstehe jeden Tag um sieben."  -> "Ich stehe jeden Tag um sieben auf."
RICHTIG:  "Er hat das Licht ausmachen."        -> "Er hat das Licht ausgemacht."
RICHTIG:  "Wir haben den Stau gevermieden."    -> "Wir haben den Stau vermieden."
VERBOTEN: "Du machst das Licht aus im Zimmer." -> "Du machst das Licht im Zimmer aus."  (nur verschoben)
VERBOTEN: "Warum du rufst mich an?"            -> "Warum rufst du mich an?"  (V2-Inversion, falsches Phänomen)""",

    "refl": """Fehler beim REFLEXIVPRONOMEN.

ENTSCHEIDEND: Der Satz des Lerners MUSS BEREITS ein Reflexivpronomen enthalten, und die Korrektur \
MUSS dieses Pronomen ÄNDERN (Kasus oder Person). Niemals nur ein fehlendes Pronomen EINFÜGEN.
SELBSTPRÜFUNG: die Menge aus {mich, mir, dich, dir, sich, uns, euch} in "student" und in "fix" \
muss BEIDE nicht leer und VERSCHIEDEN sein.
RICHTIG:  "Ich wasche mich die Hände."      -> "Ich wasche mir die Hände."   (Kasus)
RICHTIG:  "Wir treffen sich morgen."        -> "Wir treffen uns morgen."     (Person)
VERBOTEN: "Ich interessiere für Musik."     -> "Ich interessiere mich für Musik."  (nur eingefügt)
Hinweis: uns/euch/sich sind in Akkusativ und Dativ gleich — Kasusfehler brauchen ich/du als Subjekt.""",

    "dawo": "Präposition + Pronomen statt Da-Kompositum, oder 'Präposition + was' statt Wo-Kompositum. Der Bezug muss eine SACHE sein — bei Personen ist 'Präposition + Pronomen' korrekt und darf nicht 'korrigiert' werden",
    "aux": "falsches Perfekt-Hilfsverb (haben statt sein oder umgekehrt)",
    "adjend": "falsche Adjektivendung",
    "artikel": "falscher Artikel (Genus)",
    "relpron": "falsches Relativpronomen — falscher Kasus (der Kasus richtet sich nach der Rolle IM Relativsatz) oder falsches Genus/Numerus",
    "wo": "'Präposition + was' statt Wo-Kompositum in einer FRAGE (Mit was -> Womit). Bei Personen ist 'Präposition + wen/wem' korrekt und darf nicht 'korrigiert' werden",
    "ndekl": "N-Deklination: maskulines Nomen der schwachen Klasse ohne -n/-en in Akkusativ, Dativ oder Genitiv (der Student -> den Studenten). Im Nominativ Singular steht KEINE Endung",
    "wechsel": "Wechselpräposition mit falschem Kasus — Akkusativ bei Bewegung zu einem Ziel, Dativ bei Position",
    "k2": "Konjunktiv II falsch gebildet oder fehlend (Indikativ statt hätte/wäre/könnte/würde)",
    "imperativ": "falsche Imperativform (du-Form behält kein -st, starke Verben mit e->i behalten den Wechsel, Sie-Form behält das Pronomen)",
    "negation": "falsche Negation — 'nicht ein' statt 'kein', falsche Stellung von 'nicht', oder falsche kein-Endung",
    "verdict": "KEIN Fehler — alle Sätze sind korrekt und natürlich",
}

CONVERSATION_SYS = """Du erstellst Trainingsdialoge für einen deutschen Sprachlern-Assistenten. \
Du schreibst BEIDE Seiten: den Lerner und den Gesprächspartner.

Der Gesprächspartner muss wie ein echter Mensch klingen, nicht wie ein Lehrbuch. Konkret:
- Benutze Modalpartikeln ganz selbstverständlich: doch, mal, eigentlich, ja, eben, halt, denn, wohl.
- Beginne JEDE Antwort anders. Keine wiederkehrenden Floskeln wie "Das ist interessant!" oder \
"Wie schön!".
- Stelle abwechslungsreiche Fragen. Variiere die Fragewörter (was, wie, warum, wieso, woran, \
worauf, seit wann, wer, wohin) und stelle NICHT ständig Ja/Nein-Fragen.
- Reagiere inhaltlich auf das, was der Lerner gerade gesagt hat — greife ein Detail auf.
- 1 bis 3 Sätze pro Antwort. Nur Deutsch, keine Übersetzungen, keine Erklärungen.
- Korrigiere den Lerner NIEMALS.
- Der Lerner macht gelegentlich kleine Fehler, so wie echte Lerner. Der Partner geht darüber hinweg.

Antworte AUSSCHLIESSLICH mit JSON-Zeilen (JSONL), eine pro Zeile, ohne Markdown-Codeblock."""

CONVERSATION_USER = """Schreibe {n} verschiedene Dialoge.

{role_line}
{topic_line}Niveau: {level}   Anrede: {formality}
{focus_line}
Jeder Dialog hat {turns} Nachrichten und BEGINNT mit dem Gesprächspartner (role "assistant"), \
dann abwechselnd "user" (der Lerner) und "assistant".

Schema pro Zeile:
{{"task":"conversation","level":"{level}","formality":"{formality}",{scenario_field}\
"topic":"{topic}","focus_areas":{focus_json},"messages":[{{"role":"assistant","content":"..."}},\
{{"role":"user","content":"..."}},...]}}"""

RECOVERY_SYS = """Du erstellst Trainingsdaten für einen Sprachlern-Assistenten, der \
GESPROCHENE Lernersprache verarbeitet. Die Eingaben kommen aus Spracherkennung und sind deshalb \
oft unsauber.

Erzeuge realistische kaputte Lerner-Eingaben:
- ein englisches Wort mitten im deutschen Satz, weil das deutsche fehlte
- fehlende Groß-/Kleinschreibung und fehlende Satzzeichen (typische Transkription)
- Verschreiber und lautliche Fehler ("vieleicht", "ich weis nich")
- abgebrochene oder sehr kurze Äußerungen
- zwei Sätze ohne Trennung aneinandergehängt

Antworte AUSSCHLIESSLICH mit JSON-Zeilen (JSONL), eine pro Zeile, ohne Markdown-Codeblock."""

RECOVERY_USER = """Schreibe {n} Beispiele vom Typ "{kind}".

Niveau: {level}   Anrede: {formality}

{instruction}

Schema pro Zeile:
{schema}"""

NATIVE_SYS = """Du schreibst deutschsprachige Instruktions-Trainingsdaten. WICHTIG: Der Text muss \
ORIGINAL auf Deutsch verfasst sein und wie von einem Muttersprachler geschrieben klingen — keine \
aus dem Englischen übersetzten Formulierungen, keine Anglizismen wie "Funktionieren Sie als ...". \
Themen aus dem deutschsprachigen Alltag, gern mit deutschen Realien (Behörden, Verkehrsmittel, \
Feiertage).

Antworte AUSSCHLIESSLICH mit JSON-Zeilen (JSONL), eine pro Zeile, ohne Markdown-Codeblock."""

NATIVE_USER = """Schreibe {n} Instruktions-Beispiele zum Aufgabentyp "{task_kind}".

Jedes Beispiel besteht aus GENAU ZWEI Nachrichten: zuerst die Bitte des Nutzers (role "user"), \
dann die Antwort (role "assistant"). Lass die "user"-Nachricht NIEMALS weg.
Die Antwort soll hilfreich, natürlich und höflich sein, 3 bis 10 Sätze lang.

Beispiel für eine Zeile:
{{"task":"native_instruction","topic":"eine Absage schreiben","messages":[\
{{"role":"user","content":"Kannst du mir helfen, einen Termin beim Zahnarzt höflich abzusagen?"}},\
{{"role":"assistant","content":"Klar. Ruf am besten früh genug an und sag kurz Bescheid ..."}}]}}

Schema pro Zeile:
{{"task":"native_instruction","topic":"{task_kind}","messages":[\
{{"role":"user","content":"..."}},{{"role":"assistant","content":"..."}}]}}"""

FLASHCARD_SYS = """Du erstellst deutsche Vokabelkarten als JSON für eine Lern-App. Nur echte, \
gebräuchliche Wörter. Jede Karte hat ein anderes Wort UND eine andere englische Übersetzung. \
Benutze die präziseste englische Übersetzung.

Antworte AUSSCHLIESSLICH mit JSON-Zeilen (JSONL), eine pro Zeile, ohne Markdown-Codeblock."""

FLASHCARD_USER = """Schreibe {n} Kartensätze zum Thema "{topic}".

Jeder Satz enthält {count} Karten, Worttyp: {wordtype}.
{extras}
Schema pro Zeile:
{{"task":"flashcards","topic":"{topic}","request":{request},"response":{{"cards":[\
{{"germanWord":"...","englishTranslation":"...","wordType":"noun|verb|adjective",\
"article":"der|die|das"|null,"exampleSentence":"..."|null,"conjugations":null}}]}}}}"""


# --------------------------------------------------------------------------- job builders

def pick(rng, xs, ws=None):
    return rng.choices(xs, weights=ws)[0] if ws else rng.choice(xs)


def correction_jobs(rng, n_items: int, verbs: list) -> list:
    """Seeded correction jobs. Phenomenon mix mirrors the app's four target areas plus the
    extension areas the v2 holdout showed are weak (wechsel/artikel via adjend/artikel)."""
    # Weighted against what the corpus already HAS, not evenly. As of 2026-08-15:
    #   vmp   3,989 + dawo 1,918 usable rows survive from the v2/gemma-26B run — that teacher is
    #         98%/90% correctly shaped on those two, so they need almost no top-up.
    #   refl / sep  must be REPLACED wholesale (26B managed 12% and 74%).
    #   relpron, wo, ndekl, wechsel, k2, imperativ, negation  had ZERO rows in any corpus until
    #         the Sonnet batch, and between them the eval suites spend 65 items on them.
    # See TEACHER_GENERATION_FIX.md §6c.
    phen_mix = [("refl", 20), ("sep", 20), ("verdict", 12),
                ("relpron", 8), ("wechsel", 8), ("ndekl", 7), ("wo", 6), ("k2", 6),
                ("adjend", 5), ("artikel", 5),
                ("imperativ", 3), ("negation", 3), ("aux", 3),
                ("vmp", 2), ("dawo", 2)]
    phens, weights = zip(*phen_mix)
    per = PER_JOB["correction"]
    jobs = []
    while len(jobs) * per < n_items:
        phen = pick(rng, list(phens), list(weights))
        level, formality = pick(rng, LEVELS, LEVEL_W), pick(rng, FORMALITY, FORMALITY_W)
        meta, target = {}, ""
        if phen == "vmp":
            e = pick(rng, [v for v in verbs if v.get("prep")])
            meta = {"verb": e["verb"], "prep": e["prep"]}
            target = (f'Zielverb: "{e["verb"]}" mit der KORREKTEN Präposition "{e["prep"]}" '
                      f'({e["case"]}). Der Fehler ist eine falsche Präposition.')
        elif phen == "dawo":
            e = pick(rng, [v for v in verbs if v.get("prep") and v.get("da")])
            meta = {"verb": e["verb"], "prep": e["prep"]}
            target = (f'Zielverb: "{e["verb"]}" + "{e["prep"]}". Baue Sätze, in denen ein '
                      f'Da-Kompositum ("da{e["prep"]}"/"dar{e["prep"]}") nötig wäre, oder Fragen, '
                      f'in denen ein Wo-Kompositum nötig wäre.')
        elif phen == "refl":
            e = pick(rng, [v for v in verbs if v.get("refl")])
            meta = {"verb": e["verb"], "subtype": e["refl"]}
            target = f'Zielverb: "{e["verb"]}" (reflexiv, {e["refl"]}).'
        elif phen == "verdict":
            target = ("Alle Sätze sind KORREKT. Baue bewusst Sätze, die auf den ersten Blick "
                      "verdächtig aussehen (Da-Komposita, trennbare Verben, Reflexivpronomen, "
                      "Konjunktiv), aber vollkommen richtig sind.")
        elif phen == "ndekl":
            noun = pick(rng, ["der Student", "der Praktikant", "der Kollege", "der Kunde",
                              "der Junge", "der Herr", "der Nachbar", "der Zeuge",
                              "der Architekt", "der Polizist", "der Journalist", "der Mensch",
                              "der Name", "der Experte", "der Patient", "der Soldat"])
            meta = {"noun": noun}
            target = (f'Zielnomen: "{noun}" (N-Deklination). Zeige die -n/-en-Endung in Akkusativ, '
                      f'Dativ oder Genitiv. KEINE Fehler im Nominativ Singular.')
        elif phen == "wechsel":
            prep = pick(rng, ["an", "auf", "hinter", "in", "neben", "über", "unter", "vor",
                              "zwischen"])
            meta = {"prep": prep}
            target = (f'Zielpräposition: "{prep}". Baue je zur Hälfte Bewegungssätze (Akkusativ '
                      f'nötig) und Positionssätze (Dativ nötig). Nutze Verbpaare wie '
                      f'stellen/stehen, legen/liegen, setzen/sitzen, hängen.')
        elif phen == "relpron":
            case = pick(rng, ["Nominativ", "Akkusativ", "Dativ", "Genitiv",
                              "Präposition + Relativpronomen"])
            meta = {"subtype": case}
            target = (f'Schwerpunkt: {case}. Der Kasus des Relativpronomens richtet sich nach '
                      f'seiner Rolle IM Relativsatz, Genus und Numerus nach dem Bezugswort.')
        elif phen == "wo":
            target = ("Baue FRAGEN, in denen ein Wo-Kompositum nötig ist (Mit was -> Womit). "
                      "Der Bezug muss eine SACHE sein — 'Auf wen wartest du?' ist korrekt "
                      "und darf nicht als Fehler auftauchen.")
        n_fix = 0 if phen == "verdict" else round(per * 0.65)
        n_ok = per - n_fix
        n_hint = round(n_fix * 0.4)
        jobs.append({
            "slice": "correction", "phenomenon": phen, "level": level, "formality": formality,
            "system": CORRECTION_SYS,
            "user": CORRECTION_USER.format(
                n=per, phen=phen, phen_desc=PHEN_DESC[phen], target=target,
                level=level, formality=formality, n_fix=n_fix, n_ok=n_ok,
                hint_rule=HINT_RULE.format(n_hint=n_hint) if n_hint else 'Setze "hint":null.',
                meta=json.dumps(meta, ensure_ascii=False)),
            "expect": per, "meta": meta,
        })
    return jobs


def conversation_jobs(rng, n_items: int) -> list:
    """Half typed-scenario role-plays (the 23 real roleInstructions), half Lena chats. Focus areas
    are attached to ~45% — the app injects them into the system prompt and v1 never covered them."""
    scen_keys = sorted(ap.SCENARIOS)
    per = PER_JOB["conversation"]
    jobs = []
    while len(jobs) * per < n_items:
        level, formality = pick(rng, LEVELS, LEVEL_W), pick(rng, FORMALITY, FORMALITY_W)
        use_scenario = rng.random() < 0.5
        focus = []
        if rng.random() < 0.45:
            focus = rng.sample(ap.FOCUS_AREAS, rng.choice([1, 1, 2]))
        if use_scenario:
            key = pick(rng, scen_keys)
            role_line = (f'Der Gesprächspartner spielt diese Rolle:\n"{ap.SCENARIOS[key]}"\n'
                         f'Bleibe vollständig in dieser Rolle.')
            topic = key
            # No "Thema:" line — the role already sets the scene, and the enum key ("fastCasual")
            # is an internal identifier, not German. It stays in the JSON schema for provenance.
            topic_line = ""
            scenario_field = f'"role_scenario":"{key}",'
        else:
            key = None
            role_line = ('Der Gesprächspartner ist Lena, eine herzliche, geduldige '
                         'Gesprächspartnerin, die beim Deutschüben hilft.')
            topic = pick(rng, CONV_TOPICS)
            topic_line = f"Thema: {topic}\n"
            scenario_field = ""
        focus_line = ""
        if focus:
            hints = "\n".join(f"- {ap.FOCUS_HINTS[f]}" for f in focus)
            names = ", ".join(ap.FOCUS_LABELS[f] for f in focus)
            focus_line = (f"Lenke das Gespräch unaufdringlich so, dass der Lerner diese Strukturen "
                          f"übt: {names}. Zum Beispiel:\n{hints}\n")
        jobs.append({
            "slice": "conversation", "level": level, "formality": formality,
            "role_scenario": key, "focus_areas": focus,
            "system": CONVERSATION_SYS,
            "user": CONVERSATION_USER.format(
                n=per, role_line=role_line, topic=topic, topic_line=topic_line,
                level=level, formality=formality,
                # ODD counts only. A dialogue starts on the assistant and alternates, so an even
                # count ends on the learner — and validate_conversation requires it to start AND
                # end with the assistant. Even counts cost 5 of 12 conversation jobs in the smoke
                # test to "roles must alternate, starting/ending with assistant".
                focus_line=focus_line, turns=rng.choice([7, 9, 9, 11]),
                scenario_field=scenario_field,
                focus_json=json.dumps(focus, ensure_ascii=False)),
            "expect": per, "meta": {},
        })
    return jobs


def flashcard_jobs(rng, n_items: int) -> list:
    per = PER_JOB["flashcards"]
    jobs = []
    while len(jobs) * per < n_items:
        topic = pick(rng, CARD_TOPICS)
        wt = pick(rng, ["all", "nouns", "verbs", "adjectives"], [40, 30, 20, 10])
        count = pick(rng, [5, 8, 10, 12])
        req = {"count": count, "wordTypeFilter": wt,
               "includeGender": wt in ("nouns", "all"), "includeExamples": rng.random() < 0.7,
               "includeConjugations": False, "tenses": []}
        extras = []
        if req["includeGender"]:
            extras.append('Bei Substantiven den Artikel angeben ("article"), sonst article:null.')
        extras.append('exampleSentence: ein kurzer natürlicher Beispielsatz.'
                      if req["includeExamples"] else "exampleSentence:null.")
        jobs.append({
            "slice": "flashcards", "topic": topic,
            "system": FLASHCARD_SYS,
            "user": FLASHCARD_USER.format(n=per, topic=topic, count=count, wordtype=wt,
                                          extras="\n".join(extras) + "\n",
                                          request=json.dumps(req, ensure_ascii=False)),
            "expect": per, "meta": {"wordTypeFilter": wt},
        })
    return jobs


RECOVERY_KINDS = {
    "conversation_recovery": (
        "Der Lerner sagt etwas Unsauberes; der Gesprächspartner versteht es WOHLWOLLEND und führt "
        "das Gespräch einfach auf natürlichem Deutsch weiter — ohne zu korrigieren, ohne die "
        "Panne zu erwähnen. Jeder Dialog hat GENAU 5 Nachrichten und beginnt und endet mit dem "
        "Gesprächspartner (role \"assistant\"). Mindestens eine Lerner-Nachricht ist kaputt.",
        # 5 turns, not 3: validate_conversation rejects anything shorter, which cost every
        # conversation_recovery item in the 2026-07-28 smoke run ("conv: too few messages").
        '{"task":"conversation","level":"{level}","formality":"{formality}","topic":"recovery",'
        '"messages":[{"role":"assistant","content":"..."},{"role":"user","content":"<kaputte '
        'Lerner-Eingabe>"},{"role":"assistant","content":"..."},{"role":"user","content":"..."},'
        '{"role":"assistant","content":"..."}]}'),
    "correction_recovery": (
        "Der Lerner mischt ein englisches Wort ein oder spricht undeutlich. Die Korrektur ersetzt "
        "das englische Wort durch das richtige deutsche und räumt den Satz auf. verdict ist immer "
        '"fix".',
        '{"task":"correction","phenomenon":"recovery","level":"{level}","formality":"{formality}",'
        '"partner":null,"student":"<kaputte Lerner-Eingabe>","verdict":"fix","fix":"<sauberer '
        'deutscher Satz>","why":"<English, max 18 words>","hint":null,"meta":{}}'),
}


def recovery_jobs(rng, n_items: int) -> list:
    per = PER_JOB["recovery"]
    jobs = []
    while len(jobs) * per < n_items:
        kind = pick(rng, list(RECOVERY_KINDS), [55, 45])
        instruction, schema = RECOVERY_KINDS[kind]
        level, formality = pick(rng, LEVELS, LEVEL_W), pick(rng, FORMALITY, FORMALITY_W)
        jobs.append({
            "slice": "recovery", "kind": kind, "level": level, "formality": formality,
            "system": RECOVERY_SYS,
            "user": RECOVERY_USER.format(n=per, kind=kind, level=level, formality=formality,
                                         instruction=instruction,
                                         schema=schema.replace("{level}", level)
                                                      .replace("{formality}", formality)),
            "expect": per, "meta": {},
        })
    return jobs


def native_jobs(rng, n_items: int) -> list:
    per = PER_JOB["native_instruction"]
    jobs = []
    while len(jobs) * per < n_items:
        kind = pick(rng, NATIVE_TASKS)
        jobs.append({
            "slice": "native_instruction", "topic": kind,
            "system": NATIVE_SYS,
            "user": NATIVE_USER.format(n=per, task_kind=kind),
            "expect": per, "meta": {},
        })
    return jobs


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--target", type=int, default=40000,
                   help="target count. With --size-by-measured-yield this is VALIDATED items; "
                        "without it, nominal items the teacher is asked for.")
    p.add_argument("--size-by-measured-yield", action="store_true",
                   help="scale job counts by MEASURED_VALID_PER_JOB so the post-validator corpus "
                        "hits --target and the intended slice mix")
    p.add_argument("--seed", type=int, default=11)
    p.add_argument("--out", default="data/gen_v2/jobs.jsonl")
    args = p.parse_args()
    rng = random.Random(args.seed)

    verbs = json.loads((ROOT / "data" / "verb_praep_table.json").read_text())["entries"]

    builders = {
        "correction": lambda n: correction_jobs(rng, n, verbs),
        "conversation": lambda n: conversation_jobs(rng, n),
        "flashcards": lambda n: flashcard_jobs(rng, n),
        "recovery": lambda n: recovery_jobs(rng, n),
        "native_instruction": lambda n: native_jobs(rng, n),
    }

    jobs, summary = [], {}
    for name, share in SLICE_MIX.items():
        want_valid = int(args.target * share)
        if args.size_by_measured_yield:
            # Ask for enough jobs that the VALIDATED output hits the target mix. `want` here is
            # the nominal item count the builders use to decide how many jobs to emit, so scale
            # it by (nominal per job / measured valid per job).
            factor = PER_JOB[name] / MEASURED_VALID_PER_JOB[name]
            want = int(want_valid * factor)
        else:
            want = want_valid
        got = builders[name](want)
        for i, j in enumerate(got):
            j["job_id"] = f"{name}-{i:06d}"
        jobs.extend(got)
        summary[name] = {
            "jobs": len(got),
            "nominal_items": sum(j["expect"] for j in got),
            "target_valid": want_valid,
            "projected_valid": round(len(got) * MEASURED_VALID_PER_JOB[name]),
        }

    rng.shuffle(jobs)
    out = ROOT / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        for j in jobs:
            fh.write(json.dumps(j, ensure_ascii=False) + "\n")

    nominal = sum(s["nominal_items"] for s in summary.values())
    projected = sum(s["projected_valid"] for s in summary.values())
    print(json.dumps(summary, indent=2))
    print(f"\n{len(jobs):,} jobs -> ~{nominal:,} nominal items -> ~{projected:,} projected VALID")
    print(f"wrote {out}")
    # 40 jobs took ~0.5 min of generation on an A100 80GB (2026-07-28 smoke), model load excluded.
    print(f"est. generation time: ~{len(jobs) * 0.5 / 40 / 60:.1f} h "
          f"(+~5 min model load) -> ~${len(jobs) * 0.5 / 40 / 60 * 1.49:.2f} on an A100 @ $1.49/h")


if __name__ == "__main__":
    main()
