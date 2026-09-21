#!/usr/bin/env python3
"""Hard-negative OK rows for the RL prompt pool — REINFORCEMENT_LEARNING.md Part A §4.

Correct German sentences shaped like the classic learner error, so a verdict reward cannot drift
toward "always FIX" (the trust-killer). Same raw row shape as the validated corpus, so
`build_rl_pool.py build` picks the file up as one more source (`hard_negatives`).

These are POOL rows, never eval rows: the checker below refuses any sentence that is an exact or
near-duplicate (Jaccard ≥ 0.6) of an item in data/eval/*.json — the v3 suite's own hard negatives
are the test and must stay unseen.

Usage (from training/):  .venv/bin/python scripts/build_hard_negatives.py
Writes data/rl_pool_v1/hard_negatives.jsonl
"""

from __future__ import annotations

import glob
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "rl_pool_v1" / "hard_negatives.jsonl"

# (phenomenon, sentence) — every sentence is correct standard German.
ROWS = [
    # vmp — verb + preposition combinations learners "fix" to the wrong preposition
    ("vmp", "Die Nachbarn bestehen auf einer schriftlichen Entschuldigung."),
    ("vmp", "Mein Opa denkt jeden Tag an seine verstorbene Frau."),
    ("vmp", "Die Kinder freuen sich schon auf die Ferien an der Ostsee."),
    ("vmp", "Nach der Operation leidet sie noch immer unter starken Schmerzen."),
    ("vmp", "Ich habe mich bei der Verkäuferin für ihre Geduld bedankt."),
    ("vmp", "Dieses Lied erinnert mich an unseren Sommer in Italien."),
    ("vmp", "Meine Nichte hat sich in einen Austauschschüler aus Chile verliebt."),
    ("vmp", "Die Abteilung diskutiert seit Wochen über das neue Schichtmodell."),
    ("vmp", "Von dem Vorschlag der Hausverwaltung halte ich ehrlich gesagt wenig."),
    ("vmp", "Der Termin hängt ganz von der Lieferung der Ersatzteile ab."),
    ("vmp", "Wir haben lange über den Ausgang des Spiels gestritten."),
    ("vmp", "Ich glaube fest an den Erfolg dieses Projekts."),
    ("vmp", "Er hat sich bei seiner Chefin über die Überstunden beschwert."),
    ("vmp", "Die Studentin bewirbt sich um ein Stipendium in Wien."),
    ("vmp", "Achte bitte auf die Kinder, während ich telefoniere."),
    ("vmp", "Ich zweifle nicht an ihrer Ehrlichkeit."),
    ("vmp", "Die Firma verzichtet dieses Jahr auf die Weihnachtsfeier."),
    ("vmp", "Wir rechnen fest mit einer Antwort bis Freitag."),
    ("vmp", "Sie hat sich schnell an den neuen Arbeitsweg gewöhnt."),
    ("vmp", "Der Trainer besteht darauf, dass alle pünktlich erscheinen."),
    # sep — inseparable verbs that look separable, and separable verbs in the right place
    ("sep", "Der Lehrer wiederholt die Regel geduldig ein drittes Mal."),
    ("sep", "Meine Mutter hat den Mietvertrag gestern unterschrieben."),
    ("sep", "Ich glaube, dass der Zug in Fulda umsteigt."),
    ("sep", "Er übersetzt den Vertrag bis Montag ins Englische."),
    ("sep", "Die Kinder umarmen ihre Großmutter am Bahnhof."),
    ("sep", "Wir haben die Regeln des Spiels sofort verstanden."),
    ("sep", "Sie überlegt noch, ob sie das Angebot annimmt."),
    ("sep", "Hast du den Gast schon begrüßt?"),
    ("sep", "Ich versuche, jeden Abend früher einzuschlafen."),
    ("sep", "Der Bürgermeister hat das neue Schwimmbad eröffnet."),
    ("sep", "Wann hast du den Termin beim Zahnarzt vereinbart?"),
    ("sep", "Weil der Bus erst um neun abfährt, frühstücken wir in Ruhe."),
    ("sep", "Er hinterlässt seiner Tochter das kleine Haus am Fluss."),
    ("sep", "Sie hat mir die Vokabeln in zehn Minuten erklärt."),
    ("sep", "Ich habe die Rechnung schon letzte Woche überwiesen."),
    ("sep", "Obwohl er das Fenster zumacht, bleibt es kalt im Zimmer."),
    ("sep", "Die Polizei untersucht den Vorfall noch."),
    ("sep", "Wir umfahren die Baustelle über die Landstraße."),
    # refl — dative reflexives and non-reflexive uses
    ("refl", "Ich wasche mir vor dem Essen gründlich die Hände."),
    ("refl", "Sie putzt sich abends immer sehr lange die Zähne."),
    ("refl", "Ich kann mir nicht erklären, warum der Drucker streikt."),
    ("refl", "Er hat sich beim Fußball den Knöchel verstaucht."),
    ("refl", "Merk dir bitte die neue Telefonnummer der Praxis."),
    ("refl", "Die beiden haben sich zufällig im Zug wiedergetroffen."),
    ("refl", "Ich habe mir gestern ein gebrauchtes Rennrad gekauft."),
    ("refl", "Sie erinnert mich jeden Morgen an meine Tabletten."),
    ("refl", "Zieh dir eine Mütze an, es ist eisig draußen."),
    ("refl", "Wir stellen uns die Reise ganz anders vor."),
    ("refl", "Er kämmt sich nie die Haare, bevor er das Haus verlässt."),
    ("refl", "Ich leiste mir dieses Jahr endlich einen richtigen Urlaub."),
    ("refl", "Die Kinder waschen sich vor dem Schlafengehen das Gesicht."),
    ("refl", "Hast du dir den Film schon angesehen?"),
    ("refl", "Sie hat sich mit ihrer Schwester über die Erbschaft gestritten."),
    ("refl", "Ich habe mir das Bein beim Wandern verletzt."),
    ("refl", "Der Chef entschuldigt sich bei der Kundin für die Verzögerung."),
    ("refl", "Wir haben uns in Rom am Trevi-Brunnen verabredet."),
    # dawo — persons with preposition + pronoun; correct da-/wo-compounds
    ("dawo", "Kennst du meinen Onkel? Ich warte seit einer Stunde auf ihn."),
    ("dawo", "Mit wem hast du gestern so lange telefoniert?"),
    ("dawo", "Meine Chefin ist krank; ich mache mir Sorgen um sie."),
    ("dawo", "An wen soll ich das Paket adressieren?"),
    ("dawo", "Das ist genau das, worüber wir gestern gesprochen haben."),
    ("dawo", "Ich weiß nicht, wovon er lebt."),
    ("dawo", "Wir haben uns darauf verlassen, dass der Zug pünktlich ist."),
    ("dawo", "Von wem hast du diese Geschichte gehört?"),
    ("dawo", "Sie denkt oft an ihn, obwohl sie ihn kaum kennt."),
    ("dawo", "Woran liegt es, dass die Heizung nicht anspringt?"),
    ("dawo", "Ich bin gespannt darauf, wie das Spiel ausgeht."),
    ("dawo", "Für wen ist dieses Geschenk gedacht?"),
    ("dawo", "Es gibt nichts, wofür ich mich schämen müsste."),
    ("dawo", "Der Arzt ist im Urlaub; ich kann erst nächste Woche mit ihm sprechen."),
    ("dawo", "Damit habe ich wirklich nicht gerechnet."),
    ("dawo", "Über wen habt ihr euch so amüsiert?"),
    # wo — V2 after sagt/denn/aber, fronted clauses, correct final position
    ("wo", "Sie meint, das Wetter wird morgen besser."),
    ("wo", "Ich bleibe zu Hause, denn ich habe Fieber."),
    ("wo", "Er wollte kommen, aber sein Auto ist kaputt."),
    ("wo", "Ob sie wirklich umzieht, weiß niemand."),
    ("wo", "Nach dem Konzert sind wir noch lange durch die Stadt gelaufen."),
    ("wo", "Ich weiß nicht, ob ich morgen Zeit haben werde."),
    ("wo", "Seit sie in Graz wohnt, ruft sie seltener an."),
    ("wo", "Er sagt, er habe den Brief nie bekommen."),
    ("wo", "Am liebsten würde ich den ganzen Tag im Garten sitzen."),
    ("wo", "Hoffentlich hat der Elektriker die Rechnung nicht vergessen."),
    ("wo", "Weil ich den Schlüssel verloren hatte, musste ich beim Nachbarn warten."),
    ("wo", "Sie fragt, wann der nächste Zug nach Görlitz fährt."),
    # aux — haben/sein choices that look wrong
    ("aux", "Er hat den Wagen vorsichtig in die enge Garage gefahren."),
    ("aux", "Wir sind bei dem Unwetter im Wirtshaus geblieben."),
    ("aux", "Ich bin meiner alten Lehrerin auf dem Markt begegnet."),
    ("aux", "Das Baby hat die ganze Nacht durchgeschlafen."),
    ("aux", "Der Wasserstand ist über Nacht deutlich gesunken."),
    ("aux", "Sie hat drei Stunden vor dem Bildschirm gesessen."),
    ("aux", "Die Katze ist mir bis zum Bahnhof gefolgt."),
    ("aux", "Wir haben das ganze Wochenende im Regen gearbeitet."),
    ("aux", "Er ist im letzten Jahr um zehn Zentimeter gewachsen."),
    ("aux", "Ich habe den Koffer bis zum Bahnsteig getragen."),
    ("aux", "Meine Eltern sind vor vierzig Jahren nach Deutschland gezogen."),
    ("aux", "Sie hat im Sommer jeden Morgen im See geschwommen."),
    # ndekl — nominative weak nouns and strong nouns that look weak
    ("ndekl", "Der Junge aus dem dritten Stock übt jeden Abend Trompete."),
    ("ndekl", "Der neue Kollege kommt aus Rostock."),
    ("ndekl", "Ich habe den Zahnarzt nach einem früheren Termin gefragt."),
    ("ndekl", "Der Direktor begrüßt die Gäste persönlich."),
    ("ndekl", "Wir haben den Motor des Wagens überprüfen lassen."),
    ("ndekl", "Der Präsident hält heute Abend eine Rede."),
    ("ndekl", "Sie hat den Kater vom Nachbarn gefüttert."),
    ("ndekl", "Der Nachbar hat uns beim Streichen geholfen."),
    ("ndekl", "Ich kenne den Autor dieses Buches persönlich."),
    ("ndekl", "Der Kunde am Schalter wartet schon zwanzig Minuten."),
    # relpron — dessen/deren, denen, was, feminine dative
    ("relpron", "Der Bäcker, dessen Laden nebenan ist, backt das beste Brot der Stadt."),
    ("relpron", "Die Schülerin, der ich Nachhilfe gebe, hat die Prüfung bestanden."),
    ("relpron", "Die Kollegen, denen ich die Unterlagen geschickt habe, haben nicht geantwortet."),
    ("relpron", "Das war das Beste, was mir passieren konnte."),
    ("relpron", "Die Nachbarin, deren Sohn Arzt ist, hat uns geholfen."),
    ("relpron", "Der Weg, den wir genommen haben, war länger als gedacht."),
    ("relpron", "Das Kind, das dort weint, hat seine Mutter verloren."),
    ("relpron", "Es gibt vieles, worüber ich mit dir reden möchte."),
    ("relpron", "Das Haus, in dem meine Großeltern wohnten, wird abgerissen."),
    ("relpron", "Die Frau, mit der ich im Zug gesprochen habe, ist Übersetzerin."),
    # adjend — strong endings, predicative, viele + plural
    ("adjend", "Der Tee ist noch zu heiß zum Trinken."),
    ("adjend", "Ich esse morgens am liebsten frisches Brot mit salziger Butter."),
    ("adjend", "Sie trägt heute rote Schuhe und eine grüne Jacke."),
    ("adjend", "Ein alter Freund hat mich gestern überraschend besucht."),
    ("adjend", "Mit großem Interesse habe ich Ihren Artikel gelesen."),
    ("adjend", "Wir haben viele nette Leute auf der Reise kennengelernt."),
    ("adjend", "Das Wetter war den ganzen Tag schön."),
    ("adjend", "Er trinkt seinen Kaffee immer mit heißer Milch."),
    ("adjend", "Kleine Kinder brauchen viel Schlaf."),
    ("adjend", "Sie hat langes, dunkles Haar."),
    # wechsel — dative after ankommen, accusative after einsteigen, reflexive direction
    ("wechsel", "Der Zug ist pünktlich in Leipzig angekommen."),
    ("wechsel", "Sie steigt jeden Morgen in die Straßenbahn ein."),
    ("wechsel", "Stell dich bitte hinter mich, dann siehst du besser."),
    ("wechsel", "Das Fahrrad lehnt an der Hauswand."),
    ("wechsel", "Wir haben die Kisten in den Keller getragen."),
    ("wechsel", "Über das Wochenende fahren wir in die Berge."),
    ("wechsel", "Die Katze liegt auf dem warmen Fensterbrett."),
    ("wechsel", "Er hat die Lampe über den Esstisch gehängt."),
    ("wechsel", "Die Kinder sind in den See gesprungen."),
    ("wechsel", "Der Vertrag liegt seit gestern auf deinem Schreibtisch."),
    # k2 — Präteritum-form Konjunktiv, real conditions, als ob
    ("k2", "Wenn ich mehr Zeit hätte, läse ich viel mehr Romane."),
    ("k2", "Ich wünschte, du kämst öfter zu Besuch."),
    ("k2", "Wenn der Zug Verspätung hat, nehmen wir den Bus."),
    ("k2", "Er tut so, als wüsste er von nichts."),
    ("k2", "Hätte ich das gewusst, wäre ich früher losgefahren."),
    ("k2", "An ihrer Stelle würde ich das Angebot annehmen."),
    ("k2", "Es wäre schön, wenn du mir kurz helfen könntest."),
    ("k2", "Ich hätte gern ein Kilo Äpfel und zwei Birnen."),
    ("k2", "Wenn es nicht regnete, gingen wir jetzt spazieren."),
    ("k2", "Könnten Sie mir bitte die Speisekarte bringen?"),
    # artikel — genders learners guess wrong
    ("artikel", "Das Mädchen aus der dritten Klasse singt im Chor."),
    ("artikel", "Der Käse aus dem Kühlschrank riecht schon streng."),
    ("artikel", "Die Butter muss noch weich werden."),
    ("artikel", "Der Junge hat seinen Regenschirm im Bus vergessen."),
    ("artikel", "Das Brötchen vom Bäcker ist noch warm."),
    ("artikel", "Die Nase des Hundes ist ganz kalt."),
    ("artikel", "Der Löffel liegt links neben dem Teller."),
    ("artikel", "Das Ende des Films war überraschend."),
    ("artikel", "Die Schokolade schmilzt in der Sonne."),
    ("artikel", "Der Schnee auf dem Dach ist geschmolzen."),
    # imperativ — no umlaut, Hab/Sei, Sie- and ihr-forms
    ("imperativ", "Fahr bitte langsamer, die Straße ist glatt."),
    ("imperativ", "Schlaf gut und träum was Schönes!"),
    ("imperativ", "Hab keine Angst vor dem Hund, er ist ganz lieb."),
    ("imperativ", "Kommen Sie doch bitte am Montag noch einmal vorbei."),
    ("imperativ", "Räumt bitte eure Zimmer auf, bevor die Gäste kommen!"),
    ("imperativ", "Lauf nicht so schnell, ich komme nicht hinterher."),
    ("imperativ", "Sei bitte pünktlich, der Zug wartet nicht."),
    ("imperativ", "Wartet hier auf mich, ich hole nur die Tickets."),
    ("imperativ", "Halt dich bitte am Geländer fest."),
    ("imperativ", "Trag die Kisten bitte in den Keller."),
    # negation — nicht before possessives/definites, contrastive nicht, kein ... mehr
    ("negation", "Das ist nicht meine Jacke, meine ist blau."),
    ("negation", "Ich habe nicht den Roman gelesen, sondern nur die Zusammenfassung."),
    ("negation", "Wir haben leider keinen Zucker mehr im Haus."),
    ("negation", "Das war nicht seine Schuld."),
    ("negation", "Sie ist noch nicht aus dem Urlaub zurück."),
    ("negation", "Er hat nicht das Auto genommen, sondern das Fahrrad."),
    ("negation", "Ich bin heute nicht in der Stimmung für Besuch."),
    ("negation", "Das ist nicht die richtige Antwort."),
    ("negation", "Ich kenne niemanden, der so gut kocht wie er."),
    ("negation", "Wir wohnen nicht mehr in Bonn."),
]


def norm_words(s: str) -> set[str]:
    return set(re.findall(r"[a-zäöüß]+", s.lower()))


def main() -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    from build_eval_v3 import jaccard  # same near-duplicate rule the eval suite used

    evals = []
    for f in glob.glob(str(ROOT / "data" / "eval" / "*.json")):
        try:
            d = json.loads(Path(f).read_text())
        except Exception:
            continue
        for it in d.get("items", []):
            if it.get("input"):
                evals.append((it["input"], f"{Path(f).name}:{it.get('id')}"))
    ev_norm = {re.sub(r"[^a-zäöüß ]", "", s.lower()).strip(): src for s, src in evals}
    ev_words = [(norm_words(s), s, src) for s, src in evals]

    kept, dropped, seen = [], [], set()
    for phen, sent in ROWS:
        key = re.sub(r"[^a-zäöüß ]", "", sent.lower()).strip()
        if key in seen:
            dropped.append((sent, "duplicate")); continue
        seen.add(key)
        if key in ev_norm:
            dropped.append((sent, f"exact eval {ev_norm[key]}")); continue
        w = norm_words(sent)
        hit = next(((s, src) for ew, s, src in ev_words if len(ew) >= 4 and jaccard(w, ew) >= 0.6), None)
        if hit:
            dropped.append((sent, f"near eval {hit[1]}: {hit[0]!r}")); continue
        kept.append({"task": "correction", "phenomenon": phen, "level": "B1", "formality": "du",
                     "partner": None, "student": sent, "verdict": "ok", "fix": None, "why": None,
                     "hint": None, "meta": {"hard_negative": True}})
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        for r in kept:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"kept {len(kept)} / {len(ROWS)} hard negatives -> {OUT.relative_to(ROOT)}")
    for s, why in dropped:
        print(f"  dropped: {s!r}  ({why})")


if __name__ == "__main__":
    main()
