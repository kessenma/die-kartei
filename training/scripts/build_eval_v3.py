#!/usr/bin/env python3
"""Build data/eval/grammar_eval_v3.json — the RL round's decision suite.

Why this suite exists (REINFORCEMENT_LEARNING.md Part A §5): the 203 existing items cannot
certify a +6-item win, and 12 of E4B v4's 16 correction failures are *misses* (bare OK on a
real error). So v3 is built to see verdict calibration specifically:

  * 300 correction items, exactly 150 expect_ok / 150 error, no cloze
  * all 14 phenomena the app teaches, 10–12 error + the same number of OK items each
  * the OK half is dominated by HARD NEGATIVES: correct sentences that *look* like the
    classic error a learner makes (dative reflexives, inseparable verbs that look separable,
    persons with prep+pronoun instead of a da-compound, transitive `fahren` with haben, ...).
    A model that buys a low miss rate by correcting everything will show up here as FC.
  * every error item carries `gold_fix` — a minimal-edit correction — so the RL reward's
    unit tests can use the suite as a fixture (gold fix must score max, echo must be a miss)

Scoring is identical to v0/v1/v2 and runs through scripts/run_baseline_eval.py unchanged
(`expect_ok` / `require_any` / `require_all` / `forbid_any`; extra keys are ignored).

Self-checks, all hard failures:
  * every error item: no `require` phrase may already match the input (an echo must fail),
    and at least one `forbid` phrase must match the input (an echo must fail twice over);
    the gold_fix must PASS the item's own criteria
  * every item: no exact or near-duplicate (Jaccard >= 0.6) overlap with v0/v1/v2 or with any
    `student`/`fix` in the validated corpus files — this suite must be unseen by every model
    measured on it and must never enter the RL prompt pool
  * counts: 300 / 150 / 150 / 14 phenomena

Usage (from training/):
  .venv/bin/python scripts/build_eval_v3.py            # build + check + write
  .venv/bin/python scripts/build_eval_v3.py --check    # check only, no write
"""

from __future__ import annotations

import argparse
import glob
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "eval" / "grammar_eval_v3.json"

sys.path.insert(0, str(ROOT / "scripts"))
from run_baseline_eval import matches, score  # the exact scorer, so the checks mean something

# --------------------------------------------------------------------------- items
# Error rows:  (input, gold_fix, require, forbid)   require: list -> require_any; ("all", [...]) -> require_all
# OK rows:     (input, trap)   trap: short reason this is a hard negative, or None for a plain OK

E, O = "e", "o"

ITEMS: dict[str, dict[str, list]] = {
    # ---------------------------------------------------------------- vmp (12 / 12)
    "vmp": {
        E: [
            ("Ich kümmere mich über meine Oma.", "Ich kümmere mich um meine Oma.", ["um meine oma"], ["über meine oma"]),
            ("Auf dem Ausflug kannst du dich an unseren Bergführer verlassen.", "Auf dem Ausflug kannst du dich auf unseren Bergführer verlassen.", ["auf unseren bergführer"], ["an unseren bergführer"]),
            ("Ich nehme bei dem Kurs teil.", "Ich nehme an dem Kurs teil.", ["an dem kurs", "am kurs"], ["bei dem kurs", "beim kurs"]),
            ("Ich erinnere mich von meiner Kindheit.", "Ich erinnere mich an meine Kindheit.", ["an meine kindheit"], ["von meiner kindheit"]),
            ("Er beschwert sich auf den Lärm.", "Er beschwert sich über den Lärm.", ["über den lärm"], ["auf den lärm"]),
            ("Nach drei Monaten habe ich mich endlich auf den Lärm der Baustelle gewöhnt.", "Nach drei Monaten habe ich mich endlich an den Lärm der Baustelle gewöhnt.", ["an den lärm"], ["auf den lärm"]),
            ("Bitte konzentriere dich an deine Arbeit.", "Bitte konzentriere dich auf deine Arbeit.", ["auf deine arbeit"], ["an deine arbeit"]),
            ("Ob wir grillen, hängt an der Wettervorhersage ab.", "Ob wir grillen, hängt von der Wettervorhersage ab.", ["von der wettervorhersage"], ["an der wettervorhersage"]),
            ("Er leidet von Kopfschmerzen.", "Er leidet an Kopfschmerzen.", ["an kopfschmerzen", "unter kopfschmerzen"], ["von kopfschmerzen"]),
            ("Der Tisch besteht von Holz.", "Der Tisch besteht aus Holz.", ["aus holz"], ["von holz"]),
            ("Trotz aller Zweifel glaube ich in deinen Plan.", "Trotz aller Zweifel glaube ich an deinen Plan.", ["an deinen plan"], ["in deinen plan"]),
            ("Wir hoffen für besseres Wetter.", "Wir hoffen auf besseres Wetter.", ["auf besseres wetter"], ["für besseres wetter"]),
        ],
        O: [
            ("Sie besteht auf ihrem Recht.", "bestehen auf + Dativ looks like a case error"),
            ("Beim Kochen denke ich oft an meine Großmutter aus Bremen.", "denken an, easily 'fixed' to über"),
            ("Er ärgert sich über seinen Chef.", None),
            ("Wir freuen uns schon auf das Dorffest im August.", "auf vs über — both exist, auf is right here"),
            ("Sie leidet unter dem Stress.", "leiden unter is as valid as leiden an"),
            ("Ich habe mich bei der Nachbarin für die geliehene Leiter bedankt.", "two prepositions in one clause"),
            ("Das erinnert mich an meine Schulzeit.", "non-reflexive erinnern + an"),
            ("Mein Cousin hat sich in seine Tanzpartnerin aus Leipzig verliebt.", "sich verlieben in + Akk"),
            ("Im Seminar diskutieren wir über die Reform des Mietrechts.", "diskutieren über and diskutieren + Akk both valid"),
            ("Ehrlich gesagt halte ich nichts von diesem Umzugsplan.", "halten von"),
            ("Seit dem Unfall kümmert sich ihre Tante um den Haushalt.", None),
            ("Ob der Ausflug klappt, kommt auf den Busfahrplan an.", "ankommen auf"),
        ],
    },
    # ---------------------------------------------------------------- sep (12 / 12)
    "sep": {
        E: [
            ("Ich anrufe dich heute Abend.", "Ich rufe dich heute Abend an.", ("all", ["rufe", "an"]), ["anrufe"]),
            ("Wir einkaufen freitags auf dem Wochenmarkt frisches Gemüse.", "Wir kaufen freitags auf dem Wochenmarkt frisches Gemüse ein.", ("all", ["kaufen", "ein"]), ["wir einkaufen"]),
            ("Der Handwerker hat den Wasserhahn geabdreht.", "Der Handwerker hat den Wasserhahn abgedreht.", ["abgedreht"], ["geabdreht"]),
            ("Nach dem Abendessen haben wir zwei Stunden gefernsehen.", "Nach dem Abendessen haben wir zwei Stunden ferngesehen.", ["ferngesehen"], ["gefernsehen", "fern gesehen"]),
            ("Sie ausgeht jeden Freitag mit Freunden.", "Sie geht jeden Freitag mit Freunden aus.", ("all", ["geht", "aus"]), ["ausgeht"]),
            ("Die Fähre nach Rügen ablegt um Viertel nach neun.", "Die Fähre nach Rügen legt um Viertel nach neun ab.", ("all", ["legt", "ab"]), ["ablegt"]),
            ("Ich habe keine Lust, zu aufräumen.", "Ich habe keine Lust aufzuräumen.", ["aufzuräumen"], ["zu aufräumen"]),
            ("Es ist wichtig, früh zu aufstehen.", "Es ist wichtig, früh aufzustehen.", ["aufzustehen"], ["zu aufstehen"]),
            ("Ich weiß, dass er morgen kommt an.", "Ich weiß, dass er morgen ankommt.", ["ankommt"], ["kommt an"]),
            ("Wenn ich stehe auf, trinke ich Kaffee.", "Wenn ich aufstehe, trinke ich Kaffee.", ["aufstehe"], ["stehe auf"]),
            ("Sie setzt den Text über.", "Sie übersetzt den Text.", ["übersetzt"], ["setzt den text über"]),
            ("Kannst du im Flur bitte die Heizung drehen auf?", "Kannst du im Flur bitte die Heizung aufdrehen?", ["aufdrehen"], ["drehen auf"]),
        ],
        O: [
            ("Er wiederholt den Satz noch einmal.", "wiederholen is inseparable (looks like wieder|holen)"),
            ("Sie hat den Brief unterschrieben.", "unter- inseparable here: no ge-"),
            ("Ich weiß, dass die Chefin erst am Donnerstag zurückkommt.", "separable verb correctly unseparated in a subordinate clause"),
            ("Wir haben das Konzert sehr genossen.", None),
            ("Darf ich das Radio ausmachen?", None),
            ("Die Versicherung hat mich wegen des Schadens zurückgerufen.", None),
            ("Mein Mitbewohner steht werktags schon um halb sechs auf.", None),
            ("Ich versuche, das Problem zu verstehen.", "inseparable: zu stands in front"),
            ("Der Bus fährt gleich ab.", None),
            ("Es ist schwer, damit aufzuhören.", "zu inside the separable verb"),
            ("Er umarmt seine Mutter.", "um- inseparable in umarmen"),
            ("Wann kommst du heute Abend zurück?", None),
        ],
    },
    # ---------------------------------------------------------------- refl (12 / 12)
    "refl": {
        E: [
            ("Ich putze mich die Zähne.", "Ich putze mir die Zähne.", ["putze mir"], ["putze mich"]),
            ("Kannst du dich vorstellen, ohne Handy zu verreisen?", "Kannst du dir vorstellen, ohne Handy zu verreisen?", ["kannst du dir"], ["kannst du dich"]),
            ("Beim Klettern habe ich mich gestern den Knöchel verstaucht.", "Beim Klettern habe ich mir gestern den Knöchel verstaucht.", ["mir gestern den knöchel"], ["mich gestern den knöchel"]),
            ("Ich ziehe mich die Schuhe an.", "Ich ziehe mir die Schuhe an.", ["mir die schuhe"], ["mich die schuhe"]),
            ("Ich freue schon auf den Besuch meiner Tante aus Kanada.", "Ich freue mich schon auf den Besuch meiner Tante aus Kanada.", ["freue mich"], ["ich freue schon"]),
            ("Seit der langen Zugfahrt fühle ich ziemlich erschöpft.", "Seit der langen Zugfahrt fühle ich mich ziemlich erschöpft.", ["fühle ich mich"], ["fühle ich ziemlich"]),
            ("Beeil sich, wir sind spät dran!", "Beeil dich, wir sind spät dran!", ["beeil dich"], ["beeil sich"]),
            ("Ich erinnere sich noch gut an unseren Ausflug zum Leuchtturm.", "Ich erinnere mich noch gut an unseren Ausflug zum Leuchtturm.", ["erinnere mich"], ["erinnere sich"]),
            ("Wir haben sich sehr gefreut.", "Wir haben uns sehr gefreut.", ["haben uns"], ["haben sich"]),
            ("Habt ihr sich schon vorgestellt?", "Habt ihr euch schon vorgestellt?", ["euch"], ["ihr sich"]),
            ("Ich habe erkältet.", "Ich habe mich erkältet.", ["mich erkältet"], ["ich habe erkältet"]),
            ("Setzen Sie bitte!", "Setzen Sie sich bitte!", ["setzen sie sich"], ["setzen sie bitte"]),
        ],
        O: [
            ("Ich wasche mir das Gesicht.", "dative reflexive with a body part"),
            ("Sie kämmt sich die Haare.", "sich is the dative form here"),
            ("Wir haben uns lange nicht gesehen.", "reciprocal uns"),
            ("Ich kann mir gut vorstellen, in einer Kleinstadt zu leben.", "dative mir with vorstellen"),
            ("Er hat sich den Fuß verstaucht.", "dative sich + body part"),
            ("Ich merke mir deine Nummer.", "sich (Dat) etwas merken"),
            ("Die Kinder freuen sich über die Geschenke.", None),
            ("Ich habe mich riesig über die Einladung zur Hochzeit gefreut.", None),
            ("Sie erinnert ihn an den Termin.", "non-reflexive erinnern with an object"),
            ("Vor dem Spaziergang ziehe ich mir noch einen dickeren Pullover an.", "dative mir with anziehen + object"),
            ("Setz dich doch!", None),
            ("Nach dem Urlaub an der Nordsee fühle ich mich wieder richtig fit.", None),
        ],
    },
    # ---------------------------------------------------------------- dawo (12 / 12)
    "dawo": {
        E: [
            ("Über was reden die Nachbarn eigentlich jeden Morgen am Zaun?", "Worüber reden die Nachbarn eigentlich jeden Morgen am Zaun?", ["worüber"], ["über was"]),
            ("Auf was wartet der Fahrer an der Ecke?", "Worauf wartet der Fahrer an der Ecke?", ["worauf"], ["auf was"]),
            ("Mit was schneidest du das Brot?", "Womit schneidest du das Brot?", ["womit"], ["mit was"]),
            ("Für was gibst du dein Taschengeld normalerweise aus?", "Wofür gibst du dein Taschengeld normalerweise aus?", ["wofür"], ["für was"]),
            ("Das Konzert war toll. Ich denke oft an es.", "Das Konzert war toll. Ich denke oft daran.", ["daran"], ["an es"]),
            ("Das Angebot ist gut. Ich bin sehr zufrieden mit ihm.", "Das Angebot ist gut. Ich bin sehr zufrieden damit.", ["damit"], ["mit ihm"]),
            ("Das Wetter ist schlecht. Wir müssen uns auf es einstellen.", "Das Wetter ist schlecht. Wir müssen uns darauf einstellen.", ["darauf"], ["auf es"]),
            ("Kennst du meinen Bruder? Ich warte gerade darauf.", "Kennst du meinen Bruder? Ich warte gerade auf ihn.", ["auf ihn"], ["darauf"]),
            ("Wo ist deine Lehrerin? Ich möchte damit sprechen.", "Wo ist deine Lehrerin? Ich möchte mit ihr sprechen.", ["mit ihr"], ["damit"]),
            ("Wovon hast du das Geschenk bekommen?", "Von wem hast du das Geschenk bekommen?", ["von wem"], ["wovon"]),
            ("Wo warten Sie auf?", "Worauf warten Sie?", ["worauf"], ["wo warten"]),
            ("Das Buch ist spannend. Ich habe lange daüber nachgedacht.", "Das Buch ist spannend. Ich habe lange darüber nachgedacht.", ["darüber"], ["daüber"]),
        ],
        O: [
            ("Mit wem fährst du in den Urlaub?", "person: mit wem, not womit"),
            ("Meine Schwester kommt später; ich warte am Eingang auf sie.", "person: auf sie, not darauf"),
            ("Woran erkennt man eigentlich frischen Fisch?", None),
            ("Das ist alles, wovon ich geträumt habe.", "wo-compound as relative after alles"),
            ("Ich habe keine Ahnung, worum es in dem Vortrag ging.", "worum in an indirect question"),
            ("Sie erzählt gern von ihm.", "person: von ihm"),
            ("Wir haben uns darauf geeinigt, früher zu gehen.", "darauf as correlate of a zu-clause"),
            ("Ich bin damit einverstanden.", None),
            ("An wen hast du den Brief geschickt?", "person: an wen, not woran"),
            ("Danke, dass du daran gedacht hast!", None),
            ("Er kümmert sich um sie, seit sie krank ist.", "person: um sie, not darum"),
            ("Wofür brauchst du eigentlich diese vielen Schrauben?", None),
        ],
    },
    # ---------------------------------------------------------------- wo (10 / 10)
    "wo": {
        E: [
            ("Ich glaube, dass er hat Recht.", "Ich glaube, dass er Recht hat.", ["recht hat"], ["hat recht"]),
            ("Gestern ich habe meinen Onkel besucht.", "Gestern habe ich meinen Onkel besucht.", ["gestern habe ich"], ["gestern ich habe"]),
            ("Ich weiß nicht, wann öffnet die Apotheke am Samstag.", "Ich weiß nicht, wann die Apotheke am Samstag öffnet.", ["apotheke am samstag öffnet"], ["öffnet die apotheke"]),
            ("Obwohl der Wind bläst heftig, segeln wir heute raus.", "Obwohl der Wind heftig bläst, segeln wir heute raus.", ["heftig bläst"], ["bläst heftig"]),
            ("Wenn ich habe Urlaub, besuche ich meine Cousine in Bern.", "Wenn ich Urlaub habe, besuche ich meine Cousine in Bern.", ["urlaub habe"], ["habe urlaub"]),
            ("Ich muss heute gehen zum Arzt.", "Ich muss heute zum Arzt gehen.", ["zum arzt gehen"], ["gehen zum arzt"]),
            ("Wir haben gefrühstückt auf der Terrasse.", "Wir haben auf der Terrasse gefrühstückt.", ["auf der terrasse gefrühstückt"], ["gefrühstückt auf der terrasse"]),
            ("Am Wochenende wir fahren nach Hamburg.", "Am Wochenende fahren wir nach Hamburg.", ["am wochenende fahren wir"], ["wochenende wir fahren"]),
            ("Ich frage mich, ob sie kommt heute.", "Ich frage mich, ob sie heute kommt.", ["heute kommt"], ["kommt heute"]),
            ("Warum du bist so müde?", "Warum bist du so müde?", ["warum bist du"], ["warum du bist"]),
        ],
        O: [
            ("Er sagt, er hat keine Zeit.", "V2 after sagt without dass is correct"),
            ("Weil es spät ist, gehe ich jetzt nach Hause.", None),
            ("Ich hoffe, dass der Elektriker vor dem Wochenende noch vorbeikommt.", None),
            ("Übermorgen fliege ich mit meiner Kollegin nach Kopenhagen.", "fronted time adverb + inversion"),
            ("Können Sie mir sagen, wann der letzte Bus nach Trier fährt?", None),
            ("Sie kommt nicht, denn sie ist krank.", "denn keeps V2 — looks like a weil error"),
            ("Ich habe ihn gefragt, aber er hat nicht geantwortet.", "aber keeps V2"),
            ("Dass er lügt, weiß jeder.", "fronted dass-clause, then the verb"),
            ("Ich habe leider keine Zeit, weil ich die Bewerbung noch fertig schreiben muss.", "modal last after weil"),
            ("Wenn du willst, kannst du mitkommen.", None),
        ],
    },
    # ---------------------------------------------------------------- aux (10 / 10)
    "aux": {
        E: [
            ("Wir haben am Freitag mit dem Nachtzug nach Prag gefahren.", "Wir sind am Freitag mit dem Nachtzug nach Prag gefahren.", ["sind am freitag"], ["haben am freitag"]),
            ("Mein Bruder hat gestern schon vor den Nachrichten eingeschlafen.", "Mein Bruder ist gestern schon vor den Nachrichten eingeschlafen.", ["ist gestern"], ["hat gestern"]),
            ("Meine Eltern sind den halben Sommer an der Gartenmauer gearbeitet.", "Meine Eltern haben den halben Sommer an der Gartenmauer gearbeitet.", ["haben den halben sommer"], ["sind den halben sommer"]),
            ("Er ist das Essen gekocht.", "Er hat das Essen gekocht.", ["hat das essen"], ["ist das essen"]),
            ("Ich habe heute wegen des Lärms schon um fünf aufgewacht.", "Ich bin heute wegen des Lärms schon um fünf aufgewacht.", ["bin heute"], ["habe heute"]),
            ("Was hat passiert?", "Was ist passiert?", ["ist passiert"], ["hat passiert"]),
            ("Meine Tante ist ein gebrauchtes Klavier gekauft.", "Meine Tante hat ein gebrauchtes Klavier gekauft.", ["hat ein gebrauchtes klavier"], ["ist ein gebrauchtes klavier"]),
            ("Meine Oma hat vor zwei Jahren gestorben.", "Meine Oma ist vor zwei Jahren gestorben.", ["ist vor zwei jahren"], ["hat vor zwei jahren"]),
            ("Der Preis hat gestiegen.", "Der Preis ist gestiegen.", ["ist gestiegen"], ["hat gestiegen"]),
            ("Ich bin im Zug meinen Regenschirm vergessen.", "Ich habe im Zug meinen Regenschirm vergessen.", ["habe im zug"], ["bin im zug"]),
        ],
        O: [
            ("Mein Vater hat den Anhänger rückwärts in die Einfahrt gefahren.", "transitive fahren takes haben"),
            ("Ich bin ihm gestern in der Stadt begegnet.", "begegnen takes sein"),
            ("Wegen des Sturms sind wir den ganzen Sonntag in der Hütte geblieben.", "bleiben takes sein despite no motion"),
            ("Sie hat zwei Stunden auf dem Sofa gelegen.", "liegen takes haben in the standard"),
            ("Ich bin noch nie in Wien gewesen.", None),
            ("Das Kind ist schnell gewachsen.", "wachsen = change of state, sein"),
            ("Der Hund hat die ganze Nacht vor der Tür gewinselt.", None),
            ("Der Hund ist mir bis nach Hause gefolgt.", "folgen takes sein"),
            ("Bei der Abschlussfeier haben die Lehrer bis nach Mitternacht getanzt.", "tanzen takes haben without a goal"),
            ("Sie ist letztes Jahr nach Spanien gezogen.", "ziehen = move house, sein"),
        ],
    },
    # ---------------------------------------------------------------- ndekl (10 / 10)
    "ndekl": {
        E: [
            ("Ich habe den neuen Student aus Ghana nach dem Weg gefragt.", "Ich habe den neuen Studenten aus Ghana nach dem Weg gefragt.", ["studenten"], ["student"]),
            ("Der Rasenmäher des Nachbar ist schon wieder kaputt.", "Der Rasenmäher des Nachbarn ist schon wieder kaputt.", ["nachbarn"], ["nachbar"]),
            ("Die Trainerin gibt dem Junge einen zweiten Versuch.", "Die Trainerin gibt dem Jungen einen zweiten Versuch.", ["jungen"], ["junge"]),
            ("Kennst du diesen Herr mit dem grauen Hut?", "Kennst du diesen Herrn mit dem grauen Hut?", ["herrn"], ["herr"]),
            ("Beim Betriebsausflug saß ich neben einem Kollege aus der Buchhaltung.", "Beim Betriebsausflug saß ich neben einem Kollegen aus der Buchhaltung.", ["kollegen"], ["kollege"]),
            ("Im Film rettet der Junge einen verletzten Elefant.", "Im Film rettet der Junge einen verletzten Elefanten.", ["elefanten"], ["elefant"]),
            ("Die Beamtin erklärt dem Tourist den Weg zum Rathaus.", "Die Beamtin erklärt dem Touristen den Weg zum Rathaus.", ["touristen"], ["tourist"]),
            ("Im Wildpark haben wir einen schlafenden Bär fotografiert.", "Im Wildpark haben wir einen schlafenden Bären fotografiert.", ["bären"], ["bär"]),
            ("Die Rechnung trägt den Namen des Kunde aus Ulm.", "Die Rechnung trägt den Namen des Kunden aus Ulm.", ["kunden"], ["kunde"]),
            ("Der Studenten aus dem dritten Stock übt jeden Abend Cello.", "Der Student aus dem dritten Stock übt jeden Abend Cello.", ["der student aus"], ["der studenten"]),
        ],
        O: [
            ("Der Student lernt für die Prüfung.", "nominative weak noun: no -en"),
            ("Ich habe den Präsidenten im Fernsehen gesehen.", None),
            ("Der Junge spielt im Park.", "nominative weak noun"),
            ("Beim Umzug haben wir unserem Nachbarn aus dem Erdgeschoss geholfen.", None),
            ("Der Name meines Kollegen ist Peter.", None),
            ("Ich habe den Zahnarzt nach einem Termin gefragt.", "Zahnarzt is not a weak noun"),
            ("Sie liebt den Sommer.", "looks like a weak noun, is not"),
            ("Er spricht mit dem Polizisten.", None),
            ("Der Doktor kommt gleich.", "Doktor is not weak (Doktoren only in the plural)"),
            ("Kennst du den Herrn am Fenster mit der Zeitung?", None),
        ],
    },
    # ---------------------------------------------------------------- relpron (11 / 11)
    "relpron": {
        E: [
            ("Der Mann, der ich gestern getroffen habe, ist Arzt.", "Der Mann, den ich gestern getroffen habe, ist Arzt.", ["der mann, den"], ["der mann, der ich"]),
            ("Die Frau, die Auto kaputt ist, wartet.", "Die Frau, deren Auto kaputt ist, wartet.", ["deren"], ["die auto"]),
            ("Das Kind, den auf der Schaukel sitzt, ist mein Patenkind.", "Das Kind, das auf der Schaukel sitzt, ist mein Patenkind.", ["das kind, das"], ["das kind, den"]),
            ("Die Kollegen, mit die ich das Projekt leite, sitzen in Bremen.", "Die Kollegen, mit denen ich das Projekt leite, sitzen in Bremen.", ["mit denen"], ["mit die"]),
            ("Der Nachbar, den ich beim Umzug geholfen habe, hat mir Kuchen gebracht.", "Der Nachbar, dem ich beim Umzug geholfen habe, hat mir Kuchen gebracht.", ["der nachbar, dem"], ["der nachbar, den"]),
            ("Der Roman, den ich ihn im Urlaub gelesen habe, war enttäuschend.", "Der Roman, den ich im Urlaub gelesen habe, war enttäuschend.", ["den ich im urlaub gelesen habe"], ["ich ihn im urlaub"]),
            ("Der Lehrer, deren Tochter ich kenne, ist streng.", "Der Lehrer, dessen Tochter ich kenne, ist streng.", ["dessen"], ["deren"]),
            ("Der Mann, welche dort steht, ist mein Vater.", "Der Mann, der dort steht, ist mein Vater.", ["der mann, der", "welcher"], ["welche dort"]),
            ("Die Katzen, das auf dem Dach schlafen, gehören der Wirtin.", "Die Katzen, die auf dem Dach schlafen, gehören der Wirtin.", ["die katzen, die"], ["katzen, das"]),
            ("Das ist die Ärztin, mit dem ich wegen der Allergie gesprochen habe.", "Das ist die Ärztin, mit der ich wegen der Allergie gesprochen habe.", ["mit der"], ["mit dem"]),
            ("Der Hund, der Besitzer verreist ist, bleibt bei uns.", "Der Hund, dessen Besitzer verreist ist, bleibt bei uns.", ["dessen"], ["der besitzer"]),
        ],
        O: [
            ("Die Nachbarin, deren Katze ständig in unserem Garten sitzt, hat sich entschuldigt.", "deren"),
            ("Das ist alles, was mir zu dem Thema einfällt.", "was after alles, not das"),
            ("Der Mann, dem das Auto gehört, ist verreist.", "dative relative"),
            ("Die Freunde, denen ich vertraue, wohnen weit weg.", "denen"),
            ("Das Dorf, in dem ich aufgewachsen bin, ist winzig.", None),
            ("Die Lehrerin, der ich geschrieben habe, hat geantwortet.", "feminine dative der looks masculine"),
            ("Der Dokumentarfilm, den wir im Kurs gesehen haben, war ziemlich zäh.", None),
            ("Das Mädchen, das dort wartet, ist meine Cousine.", "das for Mädchen"),
            ("Es gibt nichts, worüber wir streiten müssten.", "worüber after nichts"),
            ("Der Kollege, dessen Büro nebenan liegt, ist im Urlaub.", None),
            ("Die Stadt, die ich am liebsten mag, ist Lissabon.", None),
        ],
    },
    # ---------------------------------------------------------------- adjend (10 / 10)
    "adjend": {
        E: [
            ("Ich habe ein schönes Garten.", "Ich habe einen schönen Garten.", ["schönen garten"], ["schönes garten"]),
            ("Im Sommer trinkt er am liebsten eiskalter Apfelsaft.", "Im Sommer trinkt er am liebsten eiskalten Apfelsaft.", ["eiskalten apfelsaft"], ["eiskalter apfelsaft"]),
            ("Wir wohnen in einem klein Dorf.", "Wir wohnen in einem kleinen Dorf.", ["kleinen dorf"], ["klein dorf"]),
            ("Das ist ein spannende Roman über die Nordsee.", "Das ist ein spannender Roman über die Nordsee.", ["spannender roman"], ["spannende roman"]),
            ("Ich mag die gelbe Blumen.", "Ich mag die gelben Blumen.", ["gelben blumen"], ["gelbe blumen"]),
            ("Mit meinem alte Auto fahre ich nicht mehr.", "Mit meinem alten Auto fahre ich nicht mehr.", ["alten auto"], ["alte auto"]),
            ("Sie hat einen neue Job.", "Sie hat einen neuen Job.", ["neuen job"], ["neue job"]),
            ("Der kleiner Hund bellt laut.", "Der kleine Hund bellt laut.", ["kleine hund"], ["kleiner hund"]),
            ("Ich brauche frische Brot.", "Ich brauche frisches Brot.", ["frisches brot"], ["frische brot"]),
            ("Er hilft dem alter Mann.", "Er hilft dem alten Mann.", ["alten mann"], ["alter mann"]),
        ],
        O: [
            ("Die Suppe ist noch viel zu heiß.", "predicative adjective: no ending"),
            ("Zum Frühstück trinke ich am liebsten schwarzen Kaffee.", "strong masculine accusative without article"),
            ("Sie hat schöne Augen.", "strong plural -e, often 'fixed' to -en"),
            ("Wir brauchen frisches Obst.", "strong neuter"),
            ("Ein guter Freund hilft immer.", "mixed declension -er after ein"),
            ("Mit großer Freude nehme ich die Einladung an.", "strong feminine dative"),
            ("Das kleine Kind schläft.", None),
            ("Meine Großeltern wohnen in einem winzigen Dorf bei Kassel.", None),
            ("Ich habe viele interessante Bücher gelesen.", "viele + strong plural"),
            ("Die neuen Mieter im Erdgeschoss haben zwei kleine Kinder.", None),
        ],
    },
    # ---------------------------------------------------------------- wechsel (10 / 10)
    "wechsel": {
        E: [
            ("Ich lege die frischen Handtücher auf dem Badewannenrand.", "Ich lege die frischen Handtücher auf den Badewannenrand.", ["auf den badewannenrand"], ["auf dem badewannenrand"]),
            ("Die Laterne hängt über den Hofeingang.", "Die Laterne hängt über dem Hofeingang.", ["über dem hofeingang"], ["über den hofeingang"]),
            ("Wir gehen am Samstag im Freibad.", "Wir gehen am Samstag ins Freibad.", ["ins freibad", "in das freibad"], ["im freibad"]),
            ("Er sitzt auf den Sessel.", "Er sitzt auf dem Sessel.", ["auf dem sessel"], ["auf den sessel"]),
            ("Ich stelle den Koffer in dem Abstellraum.", "Ich stelle den Koffer in den Abstellraum.", ["in den abstellraum"], ["in dem abstellraum", "im abstellraum"]),
            ("Der Spiegel hängt an die Wand neben der Garderobe.", "Der Spiegel hängt an der Wand neben der Garderobe.", ["an der wand"], ["an die wand"]),
            ("Wir sind gestern in einem Restaurant gegangen.", "Wir sind gestern in ein Restaurant gegangen.", ["in ein restaurant"], ["in einem restaurant"]),
            ("Setz dich doch auf dem freien Platz neben Opa!", "Setz dich doch auf den freien Platz neben Opa!", ["auf den freien platz"], ["auf dem freien platz"]),
            ("Die Schlüssel sind in die Tasche.", "Die Schlüssel sind in der Tasche.", ["in der tasche"], ["in die tasche"]),
            ("Wir treffen uns um acht vor das alte Rathaus.", "Wir treffen uns um acht vor dem alten Rathaus.", ["vor dem alten rathaus"], ["vor das alte rathaus"]),
        ],
        O: [
            ("Wir sind spät im Hotel angekommen.", "ankommen takes the dative despite the motion verb"),
            ("Ich steige in den Bus ein.", "einsteigen in + Akk"),
            ("Sie stellt sich hinter mich.", "reflexive + accusative direction"),
            ("Der Lieferwagen steht seit Stunden vor der Bäckerei.", None),
            ("Er hängt die Jacke an den Haken.", None),
            ("Wir fahren übers Wochenende ans Meer.", "temporal übers + directional ans"),
            ("Die Kinder bauen hinter der Scheune eine Hütte.", None),
            ("Ich habe den Brief in die Schublade gelegt.", None),
            ("Die Schlüssel liegen neben der Tür.", None),
            ("Sie ist ins Wasser gesprungen.", "springen + direction, accusative"),
        ],
    },
    # ---------------------------------------------------------------- k2 (11 / 11)
    "k2": {
        E: [
            ("Wenn ich mehr Geld habe, würde ich ein Haus kaufen.", "Wenn ich mehr Geld hätte, würde ich ein Haus kaufen.", ["hätte"], ["geld habe"]),
            ("Wenn ich an deiner Stelle wäre, ich würde den Vertrag nicht unterschreiben.", "Wenn ich an deiner Stelle wäre, würde ich den Vertrag nicht unterschreiben.", ["würde ich"], ["ich würde den"]),
            ("Ich wünschte, ich bin schon mit der Steuererklärung fertig.", "Ich wünschte, ich wäre schon mit der Steuererklärung fertig.", ["wäre"], ["ich bin schon"]),
            ("Wenn er Zeit hat, würde er kommen.", "Wenn er Zeit hätte, würde er kommen.", ["hätte"], ["zeit hat"]),
            ("Ich würde das Buch gelesen, wenn ich Zeit hätte.", "Ich hätte das Buch gelesen, wenn ich Zeit gehabt hätte.", ["hätte das buch gelesen", "würde das buch lesen"], ["würde das buch gelesen"]),
            ("Könnte Sie mir vielleicht kurz beim Ausfüllen des Formulars helfen?", "Könnten Sie mir vielleicht kurz beim Ausfüllen des Formulars helfen?", ["könnten sie"], ["könnte sie"]),
            ("Wenn ich gestern Zeit gehabt hätte, würde ich gekommen.", "Wenn ich gestern Zeit gehabt hätte, wäre ich gekommen.", ["wäre ich gekommen"], ["würde ich gekommen"]),
            ("Ich möchtete gern einen Tisch für vier Personen reservieren.", "Ich möchte gern einen Tisch für vier Personen reservieren.", ["möchte"], ["möchtete"]),
            ("Wir hätten früher gehen sollten.", "Wir hätten früher gehen sollen.", ["gehen sollen"], ["gehen sollten"]),
            ("Ich würde lieber zu Hause geblieben.", "Ich wäre lieber zu Hause geblieben.", ["wäre lieber"], ["würde lieber"]),
            ("Wenn ich mehr Zeit hätte, ich lerne Spanisch.", "Wenn ich mehr Zeit hätte, würde ich Spanisch lernen.", ["würde ich spanisch lernen", "lernte ich spanisch"], ["ich lerne spanisch"]),
        ],
        O: [
            ("Wenn ich reich wäre, reiste ich um die Welt.", "reiste is Konjunktiv II (same form as Präteritum)"),
            ("Ich wünschte, er käme endlich.", "käme instead of würde kommen"),
            ("Wenn es morgen regnet, bleiben wir zu Hause.", "real condition: indicative is correct"),
            ("Ich hätte gern einen Tee mit Zitrone.", None),
            ("Könnten Sie mir sagen, ob die Bibliothek sonntags geöffnet ist?", None),
            ("An deiner Stelle würde ich früher losfahren.", None),
            ("Er tut so, als ob er nichts wüsste.", "wüsste after als ob"),
            ("Wäre ich doch nur früher aufgestanden!", "verb-first wish without wenn"),
            ("Es wäre besser gewesen, wenn wir gefragt hätten.", None),
            ("Ich ginge gern mit, aber ich muss arbeiten.", "ginge"),
            ("Wenn ich von dem Stau gewusst hätte, wäre ich mit dem Rad gefahren.", None),
        ],
    },
    # ---------------------------------------------------------------- artikel (10 / 10)
    "artikel": {
        E: [
            ("Die Mädchen aus dem Nachbarhaus übt jeden Nachmittag Geige.", "Das Mädchen aus dem Nachbarhaus übt jeden Nachmittag Geige.", ["das mädchen"], ["die mädchen"]),
            ("Der Auto meiner Schwester steht in der Werkstatt.", "Das Auto meiner Schwester steht in der Werkstatt.", ["das auto"], ["der auto"]),
            ("Ich habe die Buch über Island in zwei Tagen gelesen.", "Ich habe das Buch über Island in zwei Tagen gelesen.", ["das buch"], ["die buch"]),
            ("Das Tisch ist aus Holz.", "Der Tisch ist aus Holz.", ["der tisch"], ["das tisch"]),
            ("Ich kaufe ein Tasche für den Laptop meiner Mutter.", "Ich kaufe eine Tasche für den Laptop meiner Mutter.", ["eine tasche"], ["ein tasche"]),
            ("Die Käse aus dem Allgäu schmeckt besonders kräftig.", "Der Käse aus dem Allgäu schmeckt besonders kräftig.", ["der käse"], ["die käse"]),
            ("Der Messer ist scharf.", "Das Messer ist scharf.", ["das messer"], ["der messer"]),
            ("Das Schlüssel liegt auf dem Tisch.", "Der Schlüssel liegt auf dem Tisch.", ["der schlüssel"], ["das schlüssel"]),
            ("Ich habe einen Bier bestellt.", "Ich habe ein Bier bestellt.", ["ein bier"], ["einen bier"]),
            ("Die Hund schläft.", "Der Hund schläft.", ["der hund"], ["die hund"]),
        ],
        O: [
            ("Das Mädchen ist sehr klug.", "-chen is neuter even for a girl"),
            ("Der Käse liegt im Kühlschrank.", "often guessed die/das"),
            ("Die Butter ist im Kühlschrank.", "often guessed der"),
            ("Das Bett ist zu weich.", None),
            ("Der Junge hat Hunger.", "-e ending but masculine"),
            ("Die Milch ist sauer.", None),
            ("Das Brötchen ist frisch.", "-chen neuter"),
            ("Der Löffel liegt neben dem Teller.", None),
            ("Die Gabel ist schmutzig.", None),
            ("Das Fahrrad steht im Keller.", None),
        ],
    },
    # ---------------------------------------------------------------- imperativ (10 / 10)
    "imperativ": {
        E: [
            ("Lese das Buch!", "Lies das Buch!", ["lies"], ["lese"]),
            ("Nehme den Apfel!", "Nimm den Apfel!", ["nimm"], ["nehme"]),
            ("Spreche bitte lauter!", "Sprich bitte lauter!", ["sprich"], ["spreche"]),
            ("Vergesse nicht deine Jacke!", "Vergiss nicht deine Jacke!", ["vergiss"], ["vergesse"]),
            ("Fährst langsam!", "Fahr langsam!", ["fahr langsam", "fahre langsam"], ["fährst"]),
            ("Gebe mir bitte den Schraubenzieher aus der Kiste!", "Gib mir bitte den Schraubenzieher aus der Kiste!", ["gib"], ["gebe"]),
            ("Helfe mir bitte!", "Hilf mir bitte!", ["hilf"], ["helfe"]),
            ("Bist ruhig!", "Sei ruhig!", ["sei ruhig"], ["bist ruhig"]),
            ("Esse endlich deine Suppe, bevor sie kalt wird!", "Iss endlich deine Suppe, bevor sie kalt wird!", ["iss"], ["esse"]),
            ("Läuf schneller!", "Lauf schneller!", ["lauf schneller", "laufe schneller"], ["läuf"]),
        ],
        O: [
            ("Fahr vorsichtig!", "a-verbs take no umlaut in the imperative"),
            ("Schlaf gut!", "no umlaut"),
            ("Lies mir bitte die Zutatenliste vor!", None),
            ("Hab keine Angst!", "Hab is the standard du-imperative of haben"),
            ("Kommen Sie bitte herein!", "Sie-imperative keeps the pronoun"),
            ("Geht nach Hause, Kinder!", "ihr-imperative looks like a statement"),
            ("Warte hier auf mich!", None),
            ("Nimm dir ruhig eine zweite Decke aus dem Schrank!", None),
            ("Lauf nicht so schnell!", "no umlaut"),
            ("Seid leise!", "ihr-form of sein"),
        ],
    },
    # ---------------------------------------------------------------- negation (10 / 10)
    "negation": {
        E: [
            ("Ich habe leider nicht Auto und fahre mit dem Rad zur Arbeit.", "Ich habe leider kein Auto und fahre mit dem Rad zur Arbeit.", ["kein auto"], ["nicht auto"]),
            ("Ich habe diese Woche nicht Zeit für das Training.", "Ich habe diese Woche keine Zeit für das Training.", ["keine zeit"], ["nicht zeit"]),
            ("Er trinkt nicht Kaffee.", "Er trinkt keinen Kaffee.", ["keinen kaffee"], ["nicht kaffee"]),
            ("Das ist kein mein Buch.", "Das ist nicht mein Buch.", ["nicht mein buch"], ["kein mein"]),
            ("Ich kenne ihn kein.", "Ich kenne ihn nicht.", ["ihn nicht"], ["ihn kein"]),
            ("Meine Schwester ist kein müde, obwohl sie früh aufgestanden ist.", "Meine Schwester ist nicht müde, obwohl sie früh aufgestanden ist.", ["nicht müde"], ["kein müde"]),
            ("Wir haben nicht Kinder.", "Wir haben keine Kinder.", ["keine kinder"], ["nicht kinder"]),
            ("Ich mag nicht Katzen.", "Ich mag keine Katzen.", ["keine katzen"], ["nicht katzen"]),
            ("Ich nicht verstehe die Aufgabe auf Seite zwölf.", "Ich verstehe die Aufgabe auf Seite zwölf nicht.", ["seite zwölf nicht"], ["nicht verstehe"]),
            ("Er hat den Vertrag gelesen nicht, bevor er unterschrieb.", "Er hat den Vertrag nicht gelesen, bevor er unterschrieb.", ["nicht gelesen"], ["gelesen nicht"]),
        ],
        O: [
            ("Das ist nicht mein Schlüssel.", "nicht before a possessive, not kein"),
            ("Ich habe nicht das Buch gelesen, sondern den Artikel.", "contrastive nicht before a definite noun"),
            ("Er hat keine Geschwister.", None),
            ("Ich bin noch nicht fertig.", "noch nicht"),
            ("Sie trinkt keinen Alkohol.", None),
            ("Ich habe ihn nicht gesehen.", None),
            ("Wir haben kein Brot mehr.", "kein ... mehr"),
            ("Das war nicht meine Idee.", "nicht + possessive"),
            ("Er ist nicht zu Hause.", None),
            ("Ich habe keine Lust, heute auszugehen.", None),
        ],
    },
}

PHENOMENA = {
    "vmp": "Verben mit Präpositionen", "sep": "trennbare Verben", "refl": "reflexive Verben",
    "dawo": "Da-/Wo-Komposita", "wo": "Wortstellung", "aux": "Perfekt auxiliary haben vs sein",
    "ndekl": "N-Deklination (weak nouns)", "relpron": "Relativpronomen", "adjend": "Adjektivendungen",
    "wechsel": "Wechselpräpositionen", "k2": "Konjunktiv II", "artikel": "noun gender (der/die/das)",
    "imperativ": "du-imperative of strong verbs", "negation": "nicht vs kein",
}


# --------------------------------------------------------------------------- build

def build_items() -> list[dict]:
    items = []
    for phen, groups in ITEMS.items():
        for i, (inp, gold, req, forbid) in enumerate(groups[E], 1):
            it = {"id": f"v3-{phen}-e{i}", "phenomenon": phen, "mode": "correction",
                  "input": inp, "expect_ok": False, "gold_fix": gold}
            if isinstance(req, tuple) and req[0] == "all":
                it["require_all"] = req[1]
            else:
                it["require_any"] = req
            it["forbid_any"] = forbid
            items.append(it)
        for i, (inp, trap) in enumerate(groups[O], 1):
            it = {"id": f"v3-{phen}-o{i}", "phenomenon": phen, "mode": "correction",
                  "input": inp, "expect_ok": True}
            if trap:
                it["hard_negative"] = True
                it["trap"] = trap
            items.append(it)
    return items


# --------------------------------------------------------------------------- checks

def norm_words(s: str) -> set[str]:
    return set(re.findall(r"[a-zäöüß]+", s.lower()))


def jaccard(a: set, b: set) -> float:
    return len(a & b) / len(a | b) if a | b else 0.0


def check_criteria(items: list[dict]) -> list[str]:
    errs = []
    for it in items:
        if it["expect_ok"]:
            continue
        inp = it["input"]
        # an echo (FIX: <input>) must fail the require side AND be caught by the forbid side
        req_all, req_any, forbid = it.get("require_all", []), it.get("require_any", []), it.get("forbid_any", [])
        echo_pass = all(matches(n, inp) for n in req_all) and (not req_any or any(matches(n, inp) for n in req_any))
        if echo_pass:
            errs.append(f"{it['id']}: an echo of the input satisfies the require criteria")
        if not any(matches(n, inp) for n in forbid):
            errs.append(f"{it['id']}: no forbid phrase matches the input (echo not caught by forbid)")
        # the gold fix must pass the item's own criteria through the real scorer
        r = score(it, f"FIX: {it['gold_fix']}\nWHY: test")
        if not r["pass"]:
            errs.append(f"{it['id']}: gold_fix fails its own criteria: {it['gold_fix']!r}")
        if it["gold_fix"].strip().lower() == inp.strip().lower():
            errs.append(f"{it['id']}: gold_fix equals input")
    return errs


def load_external_sentences() -> dict[str, str]:
    """Every sentence this suite must not overlap with: prior eval inputs + corpus student/fix."""
    out = {}
    for f in sorted(glob.glob(str(ROOT / "data" / "eval" / "*.json"))):
        if Path(f).name == OUT.name:
            continue
        try:
            d = json.loads(Path(f).read_text())
        except Exception:
            continue
        for it in d.get("items", []):
            if it.get("input"):
                out[it["input"]] = f"eval:{Path(f).name}:{it.get('id')}"
    corpus_globs = ["data/generated/*.valid.jsonl", "data/generated_gemma31b/*.valid.jsonl",
                    "data/salvage_gemma26b/*.valid.jsonl", "data/gen_v2/*.valid.jsonl",
                    "data/generated_sonnet_v2/*.jsonl", "data/e2b_pack_sources/*.jsonl"]
    for g in corpus_globs:
        for f in sorted(glob.glob(str(ROOT / g))):
            with open(f, encoding="utf-8") as fh:
                for line in fh:
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    for k in ("student", "fix"):
                        s = d.get(k)
                        if isinstance(s, str) and s.strip():
                            out.setdefault(s, f"corpus:{Path(f).name}")
    return out


def check_overlap(items: list[dict], external: dict[str, str]) -> list[str]:
    errs = []
    ext_norm = {}
    for s, src in external.items():
        ext_norm.setdefault(re.sub(r"[^a-zäöüß ]", "", s.lower()).strip(), (s, src))
    ext_words = [(norm_words(s), s, src) for s, src in external.items()]
    seen_inputs = {}
    for it in items:
        key = re.sub(r"[^a-zäöüß ]", "", it["input"].lower()).strip()
        if key in seen_inputs:
            errs.append(f"{it['id']}: duplicate input of {seen_inputs[key]}")
        seen_inputs[key] = it["id"]
        if key in ext_norm:
            errs.append(f"{it['id']}: EXACT overlap with {ext_norm[key][1]}: {ext_norm[key][0]!r}")
            continue
        w = norm_words(it["input"])
        if len(w) < 4:
            continue  # tiny sentences match everything by Jaccard; exact check above covers them
        for ew, s, src in ext_words:
            if len(ew) >= 4 and jaccard(w, ew) >= 0.6:
                errs.append(f"{it['id']}: near-duplicate (J={jaccard(w, ew):.2f}) of {src}: {s!r}")
                break
    return errs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="run the checks, do not write")
    args = ap.parse_args()

    items = build_items()
    n_ok = sum(it["expect_ok"] for it in items)
    n_err = len(items) - n_ok
    n_hard = sum(bool(it.get("hard_negative")) for it in items)
    phens = sorted({it["phenomenon"] for it in items})
    print(f"{len(items)} items: {n_err} error / {n_ok} ok ({n_hard} hard negatives), {len(phens)} phenomena")

    problems = check_criteria(items)
    external = load_external_sentences()
    print(f"overlap reference: {len(external):,} external sentences (prior evals + corpus)")
    problems += check_overlap(items, external)

    hard = [p for p in problems]
    if hard:
        print("\n".join("  !! " + p for p in hard))
        sys.exit(f"\n{len(hard)} problem(s) — fix the item table before writing")

    counts_ok = len(items) == 300 and n_ok == 150 and n_err == 150 and len(phens) == 14
    if not counts_ok:
        sys.exit(f"counts wrong: {len(items)} items, {n_ok} ok, {n_err} err, {len(phens)} phenomena")

    if args.check:
        print("check only — nothing written")
        return

    per_phen = {p: {"error": sum(1 for it in items if it["phenomenon"] == p and not it["expect_ok"]),
                    "ok": sum(1 for it in items if it["phenomenon"] == p and it["expect_ok"]),
                    "hard_negative": sum(1 for it in items if it["phenomenon"] == p and it.get("hard_negative"))}
                for p in phens}
    payload = {
        "meta": {
            "description": (
                "v3 FROZEN HOLDOUT for the RL round (REINFORCEMENT_LEARNING.md Part A §5). 300 correction "
                "items, exactly 150 expect_ok / 150 error, no cloze, all 14 phenomena. Built to measure VERDICT "
                "CALIBRATION: the OK half is dominated by hard negatives — correct sentences shaped like the "
                "classic learner error — so a model cannot buy a low miss rate by correcting everything. Error "
                "items carry `gold_fix` (a minimal-edit correction) for use as an RL-reward test fixture. "
                "RULES: score each candidate ONCE, never iterate against it, never generate training data or "
                "RL prompts from it. validate_data.py globs data/eval/*.json, so this file auto-protects itself."
            ),
            "phenomena": PHENOMENA,
            "scoring": ("Identical to v0/v1/v2 — run with scripts/run_baseline_eval.py --app-guard. "
                        "expect_ok items must get 'OK'; error items must produce a FIX: line matching "
                        "require_all/require_any and no forbid_any. Report FC over the 150 ok items and miss "
                        "over the 150 error items (scripts/behavior_metrics.py --eval-file data/eval/grammar_eval_v3.json)."),
            "counts": f"{len(items)} items: {n_err} error + {n_ok} ok ({n_hard} hard negatives)",
            "per_phenomenon": per_phen,
            "verified": (f"0 exact and 0 near-duplicate (Jaccard>=0.6) overlaps against v0/v1/v2 and "
                         f"{len(external):,} corpus student/fix sentences; every error item's gold_fix passes its own "
                         f"criteria and no echo of the input can pass (scripts/build_eval_v3.py)."),
            "created": "2026-09-05",
        },
        "items": items,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    for p, c in per_phen.items():
        print(f"  {p:10s} error {c['error']:2d}  ok {c['ok']:2d}  hard-neg {c['hard_negative']:2d}")


if __name__ == "__main__":
    main()
