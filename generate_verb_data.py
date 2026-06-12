#!/usr/bin/env python3
"""
Generate past_tense_verbs.json entries for all verbs in Goethe A1/A2/B1 vocabulary lists.
Uses DeepL to generate Perfekt example sentences.
"""
import json, requests, sys, re, time
from pathlib import Path

DEEPL_KEY = "677d113c-5a51-47b3-84fa-f6edb23e188a:fx"
DEEPL_URL = "https://api-free.deepl.com/v2/translate"
RESOURCES = Path("german-ai-flashcards/Resources")

# ---------- Non-verb entries to skip (adjectives/participles in Goethe lists) ----------
SKIP = {
    "bekannt", "besetzt", "geboren", "gestorben", "verboten", "verheiratet",
    "beantwortet", "bedankt", "beeilt", "beschwert", "bestätigt", "bewirbt",
    "bleibt", "brät", "erinnert", "informiert", "interessiert", "kontrolliert",
    "organisiert", "passiert", "probiert", "spielt", "trifft", "unterhält",
    "verletzte", "verletzt", "verreist", "versucht", "untersucht",
    "ab", "auf", "ein", "heraus", "herunter", "nach", "sich", "sind", "wer",
    "zwang", "gesprochen", "glaube", "verbot", "besichtigt", "besucht",
    "erreicht", "vergisst", "gern", "groß", "gut", "kein", "rot", "viel",
    "siezen", "ab", "ein", "nach",
}

# ---------- Verbs that take SEIN ----------
SEIN_VERBS = {
    # Movement / change of location
    "abfahren", "abbiegen", "abhauen", "abreisen",
    "ankommen", "aufsteigen", "aufstehen", "ausgehen",
    "ausreißen", "aussteigen", "einbrechen", "einfallen",
    "einsteigen", "eintreten", "einziehen",
    "entstehen", "erscheinen", "fahren", "fallen",
    "fliegen", "fließen", "gehen", "joggen", "klettern",
    "kommen", "laufen", "losfahren", "losgehen",
    "mitkommen", "mitfahren", "reisen", "reiten",
    "rennen", "schwimmen", "segeln", "sinken",
    "springen", "steigen", "stolpern",
    "umsteigen", "umziehen", "umdrehen",
    "vorkommen", "wandern", "wegfahren", "weggehen",
    "zugehen", "zurückkehren", "zurückfahren", "zurückgehen",
    # Change of state
    "aufwachen", "aufwachsen", "einschlafen", "erkranken",
    "sterben", "wachsen", "werden",
    # Fixed exceptions
    "bleiben", "sein", "passieren", "gelingen", "misslingen",
    "erscheinen", "verschwinden",
    # Separable movement verbs
    "abfahren", "abfliegen", "ankommen", "aufsteigen",
    "fortfahren", "heimkehren", "hochsteigen",
    "spazieren",
}

# ---------- Irregular past participles (base verb → participle) ----------
IRREGULAR_PARTICIPLE = {
    "abbiegen": "abgebogen",
    "abfahren": "abgefahren",
    "abgeben": "abgegeben",
    "abheben": "abgehoben",
    "abhängen": "abgehangen",
    "ablehnen": "abgelehnt",   # regular actually
    "abschließen": "abgeschlossen",
    "abschreiben": "abgeschrieben",
    "abstimmen": "abgestimmt",
    "abwaschen": "abgewaschen",
    "anbieten": "angeboten",
    "anfangen": "angefangen",
    "angeben": "angegeben",
    "anerkennen": "anerkannt",
    "ankommen": "angekommen",
    "ankündigen": "angekündigt",
    "annehmen": "angenommen",
    "anrufen": "angerufen",
    "ansehen": "angesehen",
    "ansprechen": "angesprochen",
    "anstellen": "angestellt",
    "anwenden": "angewendet",
    "anziehen": "angezogen",
    "auffahren": "aufgefahren",
    "auffallen": "aufgefallen",
    "aufführen": "aufgeführt",
    "aufgeben": "aufgegeben",
    "aufhalten": "aufgehalten",
    "aufheben": "aufgehoben",
    "aufnehmen": "aufgenommen",
    "aufrufen": "aufgerufen",
    "aufstehen": "aufgestanden",
    "aufsteigen": "aufgestiegen",
    "auftreten": "aufgetreten",
    "aufwachen": "aufgewacht",
    "ausgeben": "ausgegeben",
    "ausgehen": "ausgegangen",
    "ausreichen": "ausgereicht",
    "ausruhen": "ausgeruht",
    "ausschließen": "ausgeschlossen",
    "aussehen": "ausgesehen",
    "aussprechen": "ausgesprochen",
    "aussteigen": "ausgestiegen",
    "ausziehen": "ausgezogen",
    "backen": "gebacken",
    "beginnen": "begonnen",
    "bekommen": "bekommen",
    "beschreiben": "beschrieben",
    "bestehen": "bestanden",
    "bieten": "geboten",
    "bitten": "gebeten",
    "bleiben": "geblieben",
    "braten": "gebraten",
    "bringen": "gebracht",
    "denken": "gedacht",
    "dürfen": "gedurft",
    "einfallen": "eingefallen",
    "einladen": "eingeladen",
    "einnehmen": "eingenommen",
    "einrichten": "eingerichtet",
    "einschlafen": "eingeschlafen",
    "einschalten": "eingeschaltet",
    "einsetzen": "eingesetzt",
    "einsteigen": "eingestiegen",
    "einstellen": "eingestellt",
    "eintreten": "eingetreten",
    "einziehen": "eingezogen",
    "empfehlen": "empfohlen",
    "entscheiden": "entschieden",
    "entstehen": "entstanden",
    "erkennen": "erkannt",
    "essen": "gegessen",
    "fahren": "gefahren",
    "fallen": "gefallen",
    "finden": "gefunden",
    "fliegen": "geflogen",
    "fortsetzen": "fortgesetzt",
    "geben": "gegeben",
    "gefallen": "gefallen",
    "gehen": "gegangen",
    "gelingen": "gelungen",
    "gewinnen": "gewonnen",
    "greifen": "gegriffen",
    "haben": "gehabt",
    "halten": "gehalten",
    "hängen": "gehangen",
    "heben": "gehoben",
    "heißen": "geheißen",
    "helfen": "geholfen",
    "herunterladen": "heruntergeladen",
    "hochladen": "hochgeladen",
    "kennen": "gekannt",
    "kommen": "gekommen",
    "können": "gekonnt",
    "laden": "geladen",
    "lassen": "gelassen",
    "laufen": "gelaufen",
    "leihen": "geliehen",
    "lesen": "gelesen",
    "liegen": "gelegen",
    "losfahren": "losgefahren",
    "lügen": "gelogen",
    "mitbringen": "mitgebracht",
    "mitkommen": "mitgekommen",
    "mitnehmen": "mitgenommen",
    "mögen": "gemocht",
    "möchten": "gemocht",
    "müssen": "gemusst",
    "nachdenken": "nachgedacht",
    "nehmen": "genommen",
    "nennen": "genannt",
    "reiten": "geritten",
    "rennen": "gerannt",
    "riechen": "gerochen",
    "rufen": "gerufen",
    "schaffen": "geschaffen",
    "scheinen": "geschienen",
    "schlafen": "geschlafen",
    "schließen": "geschlossen",
    "schneiden": "geschnitten",
    "schreiben": "geschrieben",
    "schwimmen": "geschwommen",
    "sehen": "gesehen",
    "sein": "gewesen",
    "singen": "gesungen",
    "sinken": "gesunken",
    "sitzen": "gesessen",
    "sollen": "gesollt",
    "sprechen": "gesprochen",
    "springen": "gesprungen",
    "stattfinden": "stattgefunden",
    "stehen": "gestanden",
    "sterben": "gestorben",
    "stoßen": "gestoßen",
    "streiten": "gestritten",
    "tragen": "getragen",
    "treffen": "getroffen",
    "trinken": "getrunken",
    "tun": "getan",
    "umsteigen": "umgestiegen",
    "unternehmen": "unternommen",
    "unterschreiben": "unterschrieben",
    "untersuchen": "untersucht",
    "verbrennen": "verbrannt",
    "vergessen": "vergessen",
    "vergleichen": "verglichen",
    "verlieren": "verloren",
    "verschieben": "verschoben",
    "verstehen": "verstanden",
    "vorhaben": "vorgehabt",
    "vorkommen": "vorgekommen",
    "vorlesen": "vorgelesen",
    "vorschlagen": "vorgeschlagen",
    "vorstellen": "vorgestellt",
    "wachsen": "gewachsen",
    "waschen": "gewaschen",
    "werden": "geworden",
    "wissen": "gewusst",
    "wollen": "gewollt",
    "zugehen": "zugegangen",
    "zunehmen": "zugenommen",
    "zustimmen": "zugestimmt",
    "zwingen": "gezwungen",
    "überweisen": "überwiesen",
}

# Separable prefixes in priority order (longest first to avoid mis-matching)
SEPARABLE_PREFIXES = [
    "zurück", "zusammen", "weiter", "heraus", "herunter", "herauf",
    "hinaus", "hinein", "hinauf", "hinunter", "hoch",
    "ab", "an", "auf", "aus", "bei", "durch", "ein", "fest", "fort",
    "her", "hin", "los", "mit", "nach", "nieder", "um", "vor", "weg", "zu",
]

# Inseparable prefixes (verb gets no ge- in participle)
INSEPARABLE_PREFIXES = ["be", "emp", "ent", "er", "ge", "miss", "ver", "zer"]


def get_separable_prefix(verb):
    for p in SEPARABLE_PREFIXES:
        if verb.startswith(p) and len(verb) > len(p) + 2:
            # Make sure the base is plausible (not just a prefix collision)
            return p
    return None


def has_inseparable_prefix(verb):
    for p in INSEPARABLE_PREFIXES:
        if verb.startswith(p) and len(verb) > len(p) + 2:
            return True
    return False


def is_ieren_verb(verb: str) -> bool:
    return verb.endswith("ieren")


def build_participle(verb: str, prefix) -> str:
    """Build a regular past participle."""
    if is_ieren_verb(verb):
        return verb[:-2] + "t"  # reservieren → reserviert
    if has_inseparable_prefix(verb):
        # No ge-: beschreiben → beschrieben (but we'd catch that in irregular)
        stem = verb
        if stem.endswith("en"):
            stem = stem[:-2]
        elif stem.endswith("n"):
            stem = stem[:-1]
        # For regular inseparable: verdienen → verdient
        if stem.endswith("t") or stem.endswith("d"):
            return stem + "et"
        return stem + "t"
    if prefix:
        base = verb[len(prefix):]  # abfahren → fahren
        base_part = build_participle_base(base)
        return prefix + "ge" + base_part
    return "ge" + build_participle_base(verb)


def build_participle_base(verb: str) -> str:
    """Build participle for a simple verb without separable prefix."""
    if is_ieren_verb(verb):
        return verb[:-2] + "t"
    stem = verb
    if stem.endswith("eln"):
        return stem[:-3] + "elt"
    if stem.endswith("ern"):
        return stem[:-3] + "ert"
    if stem.endswith("en"):
        stem = stem[:-2]
    elif stem.endswith("n"):
        stem = stem[:-1]
    if stem.endswith("t") or stem.endswith("d"):
        return stem + "et"
    return stem + "t"


def get_grammar(verb: str) -> dict:
    """Determine grammar data for a verb."""
    # Check irregular participle first
    if verb in IRREGULAR_PARTICIPLE:
        participle = IRREGULAR_PARTICIPLE[verb]
        is_regular = False
    else:
        prefix = get_separable_prefix(verb)
        participle = build_participle(verb, prefix)
        is_regular = True

    prefix = get_separable_prefix(verb)
    is_separable = prefix is not None and not has_inseparable_prefix(verb)

    # Determine auxiliary
    auxiliary = "sein" if verb in SEIN_VERBS else "haben"

    return {
        "auxiliary": auxiliary,
        "pastParticiple": participle,
        "isSeparable": is_separable,
        "prefix": prefix if is_separable else None,
        "isRegular": is_regular,
    }


def translate_deepl(text: str, target: str = "DE", source: str = "EN") -> str:
    try:
        r = requests.post(DEEPL_URL,
            headers={"Authorization": f"DeepL-Auth-Key {DEEPL_KEY}"},
            json={"text": [text], "source_lang": source, "target_lang": target},
            timeout=10)
        return r.json()["translations"][0]["text"]
    except Exception as e:
        print(f"  DeepL error: {e}", file=sys.stderr)
        return ""


def make_english_example(infinitive: str, translation: str, auxiliary: str, participle: str) -> str:
    """Construct a natural English sentence in past tense for DeepL to translate."""
    # Clean up translation
    t = translation.split(",")[0].strip().lower()
    t = re.sub(r"^to ", "", t)
    t = re.sub(r"\(.*?\)", "", t).strip()

    aux_en = "have" if auxiliary == "haben" else "have"  # English perfect always uses have
    # Use "Yesterday I ..." pattern which reliably produces Perfekt in German
    return f"Yesterday I {t}."


def load_goethe_vocab(level_name: str) -> dict[str, dict]:
    """Load Goethe vocab and return dict of word → entry."""
    filename = {"A1": "a1_vocabulary", "A2": "a2_vocabulary", "B1": "b1_vocabulary"}[level_name]
    with open(RESOURCES / f"{filename}.json") as f:
        entries = json.load(f)
    return {e["word"]: e for e in entries}


def main():
    # Load existing data
    pt_path = RESOURCES / "past_tense_verbs.json"
    with open(pt_path) as f:
        existing = json.load(f)

    covered = {(x["infinitive"], x["level"]) for x in existing}
    new_entries = []

    for level_name in ["A1", "A2", "B1"]:
        vocab = load_goethe_vocab(level_name)
        verbs = [(w, e) for w, e in vocab.items()
                 if e.get("wordType") == "verb" and w not in SKIP]

        print(f"\n{level_name}: processing {len(verbs)} verbs...")
        added = 0

        for verb, entry in sorted(verbs, key=lambda x: x[0]):
            if (verb, level_name) in covered:
                continue

            translation = entry.get("translation") or ""
            # Strip long definitions
            translation = translation.split(".")[0].split(",")[0].strip()
            if not translation:
                translation = verb

            grammar = get_grammar(verb)
            aux = grammar["auxiliary"]
            participle = grammar["pastParticiple"]

            # Generate German example sentence via DeepL
            en_sentence = make_english_example(verb, translation, aux, participle)
            de_sentence = translate_deepl(en_sentence)
            # Small delay to avoid rate limiting
            time.sleep(0.3)

            new_entry = {
                "infinitive": verb,
                "translation": translation,
                "auxiliary": aux,
                "pastParticiple": participle,
                "isSeparable": grammar["isSeparable"],
                "prefix": grammar["prefix"],
                "isRegular": grammar["isRegular"],
                "example": de_sentence or None,
                "level": level_name,
            }
            new_entries.append(new_entry)
            covered.add((verb, level_name))
            added += 1
            print(f"  + {verb}: {aux} {participle}  →  {de_sentence[:60] if de_sentence else '(no example)'}")

        print(f"  Added {added} new entries for {level_name}")

    all_entries = existing + new_entries
    # Sort: by level then infinitive
    level_order = {"A1": 0, "A2": 1, "B1": 2}
    all_entries.sort(key=lambda x: (level_order.get(x["level"], 9), x["infinitive"]))

    with open(pt_path, "w", encoding="utf-8") as f:
        json.dump(all_entries, f, ensure_ascii=False, indent=2)

    print(f"\nDone. Total entries: {len(all_entries)} ({len(new_entries)} new).")


if __name__ == "__main__":
    main()
