//
//  KasusLesson.swift
//  german-ai-flashcards
//
//  Verstehen · Lektion: the lesson each unit opens with, as paged cards, and the Merkhilfen (the
//  memory aids) a unit's last card and the hub's Merkhilfen sheet draw on. One idea per card, at
//  most one example, no charts. Every German example has an English twin under it with the same
//  phrases in the same case colors, so the learner sees the role in a language they already read.
//
//  Written for an English speaker: English keeps its cases in its pronouns (I / me, he / him,
//  who / whom / whose), so the lesson starts there. English can't tell the Akkusativ from the
//  Dativ by form (both are „him“); it uses word order or „to“, which is exactly the gap German
//  fills with endings. The Kasus-Check, not the question test, stays the way to decide; wer, wen,
//  wem and wessen appear only as handles on the roles.
//
//  Some examples come with a scene (`KasusLessonScene`): die Figur acting the sentence out, from
//  tools/blender/kasus_szenen.py. The cast wears the sentence's colors: the doer the plain
//  charcoal Figur (Nominativ, nothing changed), the Dativ partner a teal torso, the thing an
//  Akkusativ orange or Dativ teal, so the picture and the colored sentence under it agree.
//
//  Every string is `KasusRich` markup, like `KasusUnit.ruleLines`: forms in their gender color
//  ({m:den}), case words in their case color ({dat:Dativ}), whole phrases in a case color for
//  the role ({dat:dem Kind}), **bold** key terms, *italic* German.
//

import Foundation

// MARK: - Cards

/// One page of a lesson.
nonisolated struct KasusLessonCard: Identifiable, Hashable {
    /// The German heading, e.g. „Wer tut es?“.
    let title: String
    /// Its English, e.g. "The doer".
    let english: String
    /// The idea, a few lines.
    let lines: [String]
    /// One example, German with its English twin, and (for the worked example) the Kasus-Check
    /// steps it runs through.
    var example: KasusLessonExample? = nil
    /// A memory aid, on the last cards.
    var mnemonic: KasusMnemonic? = nil
    /// The color key (the cases in play) is shown on this card.
    var showsColorKey = false

    var id: String { title }
}

/// A German sentence and its English twin, both in the markup with the phrases in their case
/// colors, and optionally the phrases decided one by one in Kasus-Check order.
nonisolated struct KasusLessonExample: Hashable {
    let de: String
    let en: String
    /// The worked example's steps: the phrase, its case, and the line that decides it.
    var steps: [Step] = []
    /// Die Figur acting the sentence out, above it.
    var scene: KasusLessonScene? = nil

    nonisolated struct Step: Hashable {
        let phrase: String
        let kasus: GrammarCase
        /// Which Kasus-Check question decided it (1 to 6).
        let checkStep: Int
        let line: String
    }
}

/// A shipped `kasus3d-*` scene: its asset name (a `PrepositionScene` key) and the case of the
/// thing the app tints (the ball is Akkusativ, the homework Dativ).
nonisolated struct KasusLessonScene: Hashable {
    let asset: String
    let tint: GrammarCase

    /// „Der Mann gibt dem Kind einen Ball.“ The ball leaves his hand and lands in the child's.
    static let geben = KasusLessonScene(asset: "kasus3d-geben", tint: .akkusativ)
    /// „Die Nachbarin hilft dem Kind mit der Hausaufgabe.“ She bends over the desk and taps the sheet.
    static let helfen = KasusLessonScene(asset: "kasus3d-helfen", tint: .dativ)
    /// „Der Hund jagt die Katze.“ A lap of a circle, the dog behind; the cat (done-to) is tinted.
    static let jagenHund = KasusLessonScene(asset: "kasus3d-jagen-hund", tint: .akkusativ)
    /// „Die Katze jagt den Hund.“ The same chase the other way round; the dog is tinted.
    static let jagenKatze = KasusLessonScene(asset: "kasus3d-jagen-katze", tint: .akkusativ)
    /// „Der Hund des Kindes spielt.“ The child (Genitiv torso) holds the dog on a leash; the leash,
    /// the „belongs to“, is tinted.
    static let leine = KasusLessonScene(asset: "kasus3d-leine", tint: .genitiv)

    static let all: [KasusLessonScene] = [geben, helfen, jagenHund, jagenKatze, leine]

    static func named(_ asset: String) -> KasusLessonScene? { all.first { $0.asset == asset } }
}

// MARK: - Memory aids

/// One Merkhilfe: the hook, the line to remember, why it works, and the cases it is for (empty
/// means all of them).
nonisolated struct KasusMnemonic: Identifiable, Hashable {
    let id: String
    let title: String
    let line: String
    let why: String
    var cases: [GrammarCase] = []
    var symbol: String = "lightbulb"
    /// A still of the scene that acts it out, for the model sentence.
    var scene: KasusLessonScene? = nil
}

nonisolated enum KasusMnemonics {
    static let roleHooks = KasusMnemonic(
        id: "roles",
        title: "Vier Jobs · Four jobs",
        line: "{nom:Nominativ} = the **Name** (who does it). {akk:Akkusativ} = the **Accused** (what the action hits). {dat:Dativ} = the **Donation** (who you give *to*). {gen:Genitiv} = the **Genes** (whose it is).",
        why: "The icons tell the same story: the bolt strikes, the target is hit, the gift is received, the key says who owns it.",
        symbol: "person.3.fill"
    )
    static let modelSentence = KasusMnemonic(
        id: "model",
        title: "Der Mustersatz · The model sentence",
        line: "„{nom:Der Mann} *gibt* {dat:dem Kind} {akk:einen Ball}.“ Bolt · gift · target.",
        why: "Say it until it says itself. Every new sentence is this one with other words.",
        symbol: "text.quote",
        scene: .geben
    )
    static let toTest = KasusMnemonic(
        id: "to-test",
        title: "Der to-Test · The “to” test",
        line: "If English can say **to him** or **to her**, it is the receiver → {dat:Dativ}: „She gives the ball *to* him“ = „*Sie gibt* {dat:ihm} *den Ball.*“",
        why: "Learn the exceptions by heart: *helfen, danken, gefallen, gehören, folgen* take the {dat:Dativ} without any „to“; *fragen, anrufen, besuchen* take the {akk:Akkusativ} although English says „ask *him*“.",
        cases: [.dativ],
        symbol: "arrow.right"
    )
    static let onlyDerChanges = KasusMnemonic(
        id: "der-den",
        title: "Nur der wird den · Only der changes",
        line: "{m:der} → {m:den}. The man gets hit. {f:Die}, {n:das} and {pl:die} stay as they are.",
        why: "So the {akk:Akkusativ} is one letter: when a masculine noun is done-to, its *r* turns into an *n*.",
        cases: [.akkusativ],
        symbol: "arrow.right.circle"
    )
    static let masculineChain = KasusMnemonic(
        id: "chain",
        title: "Die Kette · The masculine chain",
        line: "{m:der} → {m:den} → {m:dem} → {m:des}: *r · n · m · s*.",
        why: "The masculine is the one gender that shows all four cases, which is why the Probe swaps in *der Mann*.",
        symbol: "link"
    )
    static let codeWords = KasusMnemonic(
        id: "code",
        title: "Die Codewörter · The code words",
        line: "{nom:rese} · {akk:nese} · {dat:mrmn} · {gen:srsr}: the last letters of the articles, m · f · n · pl.",
        why: "Four nonsense words hold the whole table. „Masculine Dativ in mrmn is m: dem.“",
        symbol: "tablecells"
    )
    static let akkusativPrepositions = KasusMnemonic(
        id: "dogfu",
        title: "DOGFU",
        line: "*durch, ohne, gegen, für, um* always take the {akk:Akkusativ}. „Durch, für, gegen, ohne, um, Deutsch zu lernen ist nicht dumm.“",
        why: "A word you can say is a word you keep. The model: „*Ich laufe durch* {m:den} *Wald und um* {m:einen} *See.*“",
        cases: [.akkusativ],
        symbol: "textformat.abc"
    )
    static let dativPrepositions = KasusMnemonic(
        id: "donau",
        title: "An der schönen blauen Donau",
        line: "*aus, außer, bei, mit, nach, seit, von, zu* always take the {dat:Dativ}. Sing them to the Blue Danube waltz.",
        why: "Eight words on a tune you already know. *gegenüber* tags along.",
        cases: [.dativ],
        symbol: "music.note"
    )
    static let twoWay = KasusMnemonic(
        id: "two-way",
        title: "Wo oder wohin? · Two-way",
        line: "*an, auf, hinter, neben, in, über, unter, vor, zwischen*, to Ode to Joy. {wechsel:Wo?} → {dat:Dativ}, {wechsel:Wohin?} → {akk:Akkusativ}.",
        why: "A place keeps the {dat:Dativ}; a direction takes the {akk:Akkusativ}. Nine words, one tune.",
        cases: [.akkusativ, .dativ],
        symbol: "arrow.left.arrow.right"
    )
    static let genitivPrepositions = KasusMnemonic(
        id: "gen-prep",
        title: "Vier Takte · Four beats",
        line: "*wegen · trotz · während · statt* take the {gen:Genitiv}.",
        why: "Four beats, four words. In speech you will often hear the {dat:Dativ} after them; in writing, the {gen:Genitiv}.",
        cases: [.genitiv],
        symbol: "metronome"
    )
    static let endings = KasusMnemonic(
        id: "endings",
        title: "Die Nomen-Endungen · The noun endings",
        line: "{dat:Dativ} plural adds **-n** („*mit* {pl:den} *Kinder*{pl:n}“). Masculine and neuter {gen:Genitiv} add **-s** („{m:des} *Mann*{m:es}“).",
        why: "Only two spots where the noun itself changes; everywhere else the article does the work.",
        cases: [.dativ, .genitiv],
        symbol: "textformat.subscript"
    )
    static let kasusCheck = KasusMnemonic(
        id: "check",
        title: "Der Kasus-Check",
        line: "Six questions **in order**: preposition? another noun? subject? *sein*? receiver or Dativ verb? None of these → {akk:Akkusativ}.",
        why: "The first Ja decides, so you never weigh two cases against each other. Rollen's „Schritt für Schritt“ is this as a drill.",
        symbol: "questionmark.circle"
    )

    /// Every memory aid, in the order the Merkhilfen sheet lists them: the ones for every case
    /// first, then by case along the path.
    static let all: [KasusMnemonic] = [
        roleHooks, modelSentence, kasusCheck, masculineChain, codeWords,
        onlyDerChanges, akkusativPrepositions,
        toTest, dativPrepositions, twoWay,
        genitivPrepositions, endings,
    ]

    /// The aids for one unit's last card, in order.
    @MainActor
    static func forUnit(_ unit: KasusUnit) -> [KasusMnemonic] {
        switch unit {
        case .nominativ:  [roleHooks]
        case .akkusativ:  [onlyDerChanges, akkusativPrepositions]
        case .dativ:      [toTest, dativPrepositions]
        case .genitiv:    [genitivPrepositions, endings]
        case .alleFaelle: [modelSentence, kasusCheck]
        }
    }
}

// MARK: - Lessons

nonisolated enum KasusLesson {

    /// The label of the last card's button.
    static let practiceLabel = "Üben · Practice: Rollen"

    /// Where the sources are, for the last card.
    static let sourcesLine = "Quellen · Sources: Einstellungen ▸ About ▸ Sources."

    @MainActor
    static func cards(for unit: KasusUnit) -> [KasusLessonCard] {
        switch unit {
        case .nominativ:  nominativ
        case .akkusativ:  akkusativ
        case .dativ:      dativ
        case .genitiv:    genitiv
        case .alleFaelle: alleFaelle
        }
    }

    // MARK: Nominativ

    static let nominativ: [KasusLessonCard] = [
        KasusLessonCard(
            title: "Was ist ein Fall?",
            english: "What a case is",
            lines: [
                "A case is the **job** a noun does in its sentence: who does it, what gets done to, who receives, whose it is.",
                "English shows the job by **where** a word stands. German shows it on the **article**: {m:der}, {m:den}, {m:dem}, {m:des}.",
                "Four jobs, four cases, each with its own color in this app.",
            ],
            showsColorKey: true
        ),
        KasusLessonCard(
            title: "Englisch zuerst",
            english: "English first",
            lines: [
                "You already use cases. You say **he** when he does something and **him** when something is done to him.",
                "**He** sees **him**. The doer is *he*, never *him*. That doer form is the {nom:Nominativ}.",
                "*Who?* asks for the doer: *who* sees? **He** does.",
            ],
            example: KasusLessonExample(
                de: "{nom:Der Hund} *schläft*.",
                en: "{nom:The dog} is sleeping."
            )
        ),
        KasusLessonCard(
            title: "Das Subjekt",
            english: "The doer",
            lines: [
                "The {nom:Nominativ} marks the **subject**: whoever or whatever does the verb. Every sentence has one, and the verb agrees with it.",
                "It is the **dictionary form**: {m:der}, {f:die}, {n:das} and {m:ein}, {f:eine}, {n:ein} stay just as you learned them.",
                "Ask *wer?* (who?) or *was?* (what?) together with the verb: *Wer schläft?* → {nom:der Hund}.",
            ],
            example: KasusLessonExample(
                de: "{nom:Die Kinder} *spielen draußen*.",
                en: "{nom:The children} are playing outside."
            )
        ),
        KasusLessonCard(
            title: "Nach sein bleibt es gleich",
            english: "After sein, nothing changes",
            lines: [
                "*sein, werden, bleiben* and *heißen* don't act on anything. They put an **equals sign** between the subject and the other noun.",
                "So the noun after them is {nom:Nominativ} too: „*Das ist* {nom:der Hund}“, not *den Hund*.",
                "In English you feel it: „It is **he**“ (not *him*) is the same rule, just old-fashioned.",
            ],
            example: KasusLessonExample(
                de: "{nom:Die Katze} *ist* {nom:ein Tier}.",
                en: "{nom:The cat} is {nom:an animal}."
            )
        ),
        KasusLessonCard(
            title: "Merkhilfe",
            english: "Memory aid",
            lines: [
                "The {nom:Nominativ} **names** who does it. One more thing before the drills: in German the doer can stand **anywhere** in the sentence. „*Den Hund jagt die Katze*“ still means the cat chases, because {m:den} can't be a doer. That is what the next units are about.",
            ],
            mnemonic: KasusMnemonics.roleHooks
        ),
    ]

    // MARK: Akkusativ

    static let akkusativ: [KasusLessonCard] = [
        KasusLessonCard(
            title: "Das direkte Objekt",
            english: "The done-to",
            lines: [
                "The {akk:Akkusativ} marks the **direct object**: what the verb acts on, hits, takes, sees or makes.",
                "The doer does something **to** it. In „*Ich sehe* {akk:den Hund}“ the dog is what the seeing lands on.",
                "Ask *wen?* (whom?) or *was?* (what?) with the verb: *Wen sehe ich?* → {akk:den Hund}.",
            ],
            example: KasusLessonExample(
                de: "{nom:Der Hund} *sieht* {akk:den Ball}.",
                en: "{nom:The dog} sees {akk:the ball}."
            ),
            showsColorKey: true
        ),
        KasusLessonCard(
            title: "Englisch zuerst",
            english: "English first",
            lines: [
                "**He** sees **him**: *him* is the done-to. English only shows it on pronouns (*me, him, her, us, them, whom*); on nouns it shows nothing at all.",
                "German shows it on the article, but only for **masculine** nouns: {m:der} → {m:den}, {m:ein} → {m:einen}.",
                "A way to hold it: the {akk:Akkusativ} is the **Accused**, the one the action is aimed at.",
            ],
            example: KasusLessonExample(
                de: "{nom:Die Lehrerin} *fragt* {akk:den Schüler}.",
                en: "{nom:The teacher} asks {akk:the pupil}."
            )
        ),
        KasusLessonCard(
            title: "Warum überhaupt?",
            english: "Why German bothers",
            lines: [
                "In English, order is meaning: *the dog bites the man* and *the man bites the dog* are two different afternoons.",
                "German can put the done-to **first** and still mean the same, because {m:den} says „done-to“ wherever it stands.",
                "So read the **ending** before the order. The first noun isn't always the doer.",
            ],
            example: KasusLessonExample(
                de: "{akk:Den Hund} *jagt* {nom:die Katze}.",
                en: "{nom:The cat} is chasing {akk:the dog}.",
                scene: .jagenKatze
            )
        ),
        KasusLessonCard(
            title: "Die Präposition entscheidet",
            english: "A preposition decides first",
            lines: [
                "Before you ask who does what, look for a **preposition** in front of the phrase. If there is one, it decides the case, and the role no longer matters.",
                "*durch, für, gegen, ohne, um* always take the {akk:Akkusativ}: „*für* {akk:den Hund}“, „*ohne* {akk:den Schlüssel}“.",
                "That is why the Kasus-Check asks about the preposition **first**.",
            ],
            example: KasusLessonExample(
                de: "{nom:Die Mutter} *kauft* {akk:einen Kuchen} *für* {akk:das Kind}.",
                en: "{nom:The mother} buys {akk:a cake} for {akk:the child}."
            )
        ),
        KasusLessonCard(
            title: "Der Kasus-Check",
            english: "A worked example",
            lines: [
                "Run the questions **in order** for each phrase; the first Ja decides.",
            ],
            example: KasusLessonExample(
                de: "{nom:Der Mann} *kauft* {akk:einen Ball} *für* {akk:den Hund}.",
                en: "{nom:The man} buys {akk:a ball} for {akk:the dog}.",
                steps: [
                    .init(phrase: "den Hund", kasus: .akkusativ, checkStep: 1, line: "A preposition in front: *für* → {akk:Akkusativ}."),
                    .init(phrase: "Der Mann", kasus: .nominativ, checkStep: 3, line: "No preposition, hangs on nothing, and he does the buying: the **subject** → {nom:Nominativ}."),
                    .init(phrase: "einen Ball", kasus: .akkusativ, checkStep: 6, line: "No preposition, not the subject, no *sein*, no receiver: **none of these** → {akk:Akkusativ}."),
                ]
            )
        ),
        KasusLessonCard(
            title: "Die Falle",
            english: "The trap",
            lines: [
                "*fragen, anrufen* and *besuchen* feel like they have a receiver („ask **him**“), but German treats the person as the **done-to**: „*Ich frage* {akk:den Lehrer}“, „*Ich besuche* {akk:den Opa}“.",
                "And the first noun isn't always the doer: „*Den Mann sieht das Kind*“ means the child sees. Trust {m:den}.",
            ],
            mnemonic: KasusMnemonics.onlyDerChanges
        ),
    ]

    // MARK: Dativ

    static let dativ: [KasusLessonCard] = [
        KasusLessonCard(
            title: "Der Empfänger",
            english: "The receiver",
            lines: [
                "The {dat:Dativ} marks the **receiver**: to whom something is given, shown, told or sent.",
                "A giving sentence has three jobs: the giver ({nom:Nominativ}), the thing given ({akk:Akkusativ}) and the one it goes to ({dat:Dativ}).",
                "Ask *wem?* (to whom?): *Wem gibt der Mann den Ball?* → {dat:dem Kind}.",
            ],
            example: KasusLessonExample(
                de: "{nom:Der Mann} *gibt* {dat:dem Kind} {akk:den Ball}.",
                en: "{nom:The man} gives {dat:the child} {akk:the ball}.",
                scene: .geben
            ),
            showsColorKey: true
        ),
        KasusLessonCard(
            title: "Englisch zuerst",
            english: "English first",
            lines: [
                "English says „She gives **him** the ball“ or „She gives the ball **to him**“. Both are the same sentence; *to* is English's {dat:Dativ}.",
                "The test: if you can put **to** (or **for**) in front of it in English, it is the receiver → {dat:Dativ}.",
                "English can't tell *him* the done-to from *him* the receiver by its form. German can: {akk:den} versus {dat:dem}.",
            ],
            example: KasusLessonExample(
                de: "{nom:Mein Bruder} *zeigt* {dat:dem Gast} {akk:die Wohnung}.",
                en: "{nom:My brother} shows {dat:the guest} {akk:the flat}."
            )
        ),
        KasusLessonCard(
            title: "Die Dativ-Verben",
            english: "Verbs that always take it",
            lines: [
                "Some verbs give their one partner the {dat:Dativ} with no „to“ in sight: *helfen, danken, gefallen, gehören, folgen, antworten, gratulieren*.",
                "Three of them turn the English roles around: with *gefallen, gehören* and *schmecken* the **thing** is the subject and the **person** is {dat:Dativ}: „{nom:Der Film} *gefällt* {dat:meiner Mutter}“ = my mother likes the film.",
                "Learn these verbs as a list; the „to“ test can't see them.",
            ],
            example: KasusLessonExample(
                de: "{nom:Die Nachbarin} *hilft* {dat:dem Kind}.",
                en: "{nom:The neighbour} helps {dat:the child}.",
                scene: .helfen
            )
        ),
        KasusLessonCard(
            title: "Die Formen",
            english: "The forms",
            lines: [
                "{m:der} → {m:dem}, {f:die} → {f:der}, {n:das} → {n:dem}, and the plural {pl:die} → {pl:den} with an **-n** on the noun: „*mit* {pl:den} *Kinder*{pl:n}“.",
                "The code word is {dat:mrmn}. Watch the feminine: {f:der} in the {dat:Dativ} looks like the masculine {m:der} of the {nom:Nominativ}. The noun's gender tells them apart.",
                "*aus, bei, mit, nach, seit, von, zu* always take the {dat:Dativ}; *in, an, auf* and the other two-way prepositions take it for a **place** ({wechsel:Wo?}).",
            ],
            example: KasusLessonExample(
                de: "{nom:Der Schlüssel} *liegt auf* {dat:dem Tisch}.",
                en: "{nom:The key} is lying on {dat:the table}."
            )
        ),
        KasusLessonCard(
            title: "Der Kasus-Check",
            english: "A worked example",
            lines: [
                "Run the questions **in order** for each phrase; the first Ja decides.",
            ],
            example: KasusLessonExample(
                de: "{nom:Der Mann} *gibt* {dat:dem Kind} {akk:den Ball}.",
                en: "{nom:The man} gives {dat:the child} {akk:the ball}.",
                steps: [
                    .init(phrase: "Der Mann", kasus: .nominativ, checkStep: 3, line: "No preposition, hangs on nothing, he does the giving: the **subject** → {nom:Nominativ}."),
                    .init(phrase: "dem Kind", kasus: .dativ, checkStep: 5, line: "Not the subject, no *sein*, but the ball goes **to** the child: the **receiver** → {dat:Dativ}."),
                    .init(phrase: "den Ball", kasus: .akkusativ, checkStep: 6, line: "Not the subject, not the receiver: **none of these** → {akk:Akkusativ}."),
                ]
            )
        ),
        KasusLessonCard(
            title: "Die Falle",
            english: "The trap",
            lines: [
                "„*Der Hund gefällt* {dat:dem Kind}“: the dog is the **subject** (it pleases), the child is {dat:Dativ}. English says „the child likes the dog“ and hides it.",
                "*fragen, anrufen, besuchen* take the {akk:Akkusativ} although you'd expect a receiver. *helfen* takes the {dat:Dativ} although English says „help **him**“. Lists beat feelings here.",
            ],
            mnemonic: KasusMnemonics.toTest
        ),
    ]

    // MARK: Genitiv

    static let genitiv: [KasusLessonCard] = [
        KasusLessonCard(
            title: "Wessen?",
            english: "Whose",
            lines: [
                "The {gen:Genitiv} says **whose** something is, or what it belongs to: „*das Auto* {gen:des Mannes}“, „*das Ende* {gen:der Woche}“.",
                "It hangs on **another noun**, right behind it, and never on the verb. That is Kasus-Check question two.",
                "Ask *wessen?* (whose?): *Wessen Auto?* → {gen:des Mannes}.",
            ],
            example: KasusLessonExample(
                de: "{nom:Der Hund} {gen:des Kindes} *spielt*.",
                en: "{gen:The child's} {nom:dog} is playing.",
                scene: .leine
            ),
            showsColorKey: true
        ),
        KasusLessonCard(
            title: "Englisch zuerst",
            english: "English first",
            lines: [
                "English has this case twice: „**the man's** car“ and „the car **of** the man“. Both are the {gen:Genitiv}; German uses the second shape, noun first and owner after.",
                "*Whose* is the one English question word that still carries a case ending. A way to hold it: the {gen:Genitiv} is in the **genes**, it says where something comes from.",
            ],
            example: KasusLessonExample(
                de: "{nom:Die Tasche} {gen:der Lehrerin} *liegt auf* {dat:dem Stuhl}.",
                en: "{gen:The teacher's} {nom:bag} is lying on {dat:the chair}."
            )
        ),
        KasusLessonCard(
            title: "Die Formen",
            english: "The forms",
            lines: [
                "**Masculine** and **neuter** take {m:des} and the noun adds **-s** or **-es**: {m:des} *Vater*{m:s}, {n:des} *Kind*{n:es}.",
                "**Feminine** and **plural** take {f:der} and the noun stays: {f:der} *Frau*, {pl:der} *Kinder*. The code word is {gen:srsr}.",
                "*wegen, trotz, während* and *statt* take the {gen:Genitiv} in writing: „*wegen* {gen:des Regens}“. In speech you will often hear the {dat:Dativ}, and „*das Auto von* {dat:dem Mann}“ instead of the {gen:Genitiv}.",
            ],
            example: KasusLessonExample(
                de: "*Wegen* {gen:des Regens} *bleiben* {nom:die Kinder} *zu Hause*.",
                en: "Because of {gen:the rain} {nom:the children} stay at home."
            )
        ),
        KasusLessonCard(
            title: "Der Kasus-Check",
            english: "A worked example",
            lines: [
                "Run the questions **in order** for each phrase; the first Ja decides.",
            ],
            example: KasusLessonExample(
                de: "{nom:Das Auto} {gen:des Mannes} *steht vor* {dat:dem Haus}.",
                en: "{gen:The man's} {nom:car} is standing in front of {dat:the house}.",
                steps: [
                    .init(phrase: "dem Haus", kasus: .dativ, checkStep: 1, line: "A preposition in front: *vor* with a place ({wechsel:Wo?}) → {dat:Dativ}."),
                    .init(phrase: "des Mannes", kasus: .genitiv, checkStep: 2, line: "No preposition, but it hangs on *Auto* and says whose → {gen:Genitiv}."),
                    .init(phrase: "Das Auto", kasus: .nominativ, checkStep: 3, line: "No preposition, hangs on nothing, it does the standing: the **subject** → {nom:Nominativ}."),
                ]
            )
        ),
        KasusLessonCard(
            title: "Die Falle",
            english: "The trap",
            lines: [
                "{f:der} is the feminine {dat:Dativ} **and** the feminine {gen:Genitiv}: „*Ich helfe* {dat:der Frau}“, „*das Auto* {gen:der Frau}“. The form can't tell you; the Kasus-Check can: a verb like *helfen* means {dat:Dativ}, hanging on a noun means {gen:Genitiv}.",
                "When a form could be two cases, swap in *der Mann*: {m:dem} or {m:des} shows which. That is Die Probe.",
            ],
            mnemonic: KasusMnemonics.genitivPrepositions
        ),
    ]

    // MARK: Alle Fälle

    static let alleFaelle: [KasusLessonCard] = [
        KasusLessonCard(
            title: "Der Kasus-Check als Routine",
            english: "The Check as a habit",
            lines: [
                "For every phrase, the same six questions in the same order: a **preposition** in front? hangs on **another noun**? the **subject**? after **sein**? the **receiver** or a **Dativ verb**? None of these → {akk:Akkusativ}.",
                "The first Ja decides, so a preposition always beats a role, and „subject“ always beats „receiver“. You never weigh two cases against each other.",
            ],
            example: KasusLessonExample(
                de: "{nom:Der Mann} *gibt* {dat:dem Kind} {akk:einen Ball}.",
                en: "{nom:The man} gives {dat:the child} {akk:a ball}.",
                scene: .geben
            ),
            showsColorKey: true
        ),
        KasusLessonCard(
            title: "Das Verb öffnet Plätze",
            english: "The verb opens slots",
            lines: [
                "Each verb opens a fixed set of slots, and each slot has its case. *geben*: **wer · wem · was** ({nom:Nominativ} · {dat:Dativ} · {akk:Akkusativ}). *helfen*: **wer · wem**. *sehen*: **wer · wen**. *gehören*: **was · wem**.",
                "Learn a verb with its slots and the cases come with it. A preposition opens its own slot with its own case.",
            ],
            example: KasusLessonExample(
                de: "{nom:Die Nachbarin} *hilft* {dat:dem Kind} *mit* {dat:der Hausaufgabe}.",
                en: "{nom:The neighbour} helps {dat:the child} with {dat:the homework}.",
                scene: .helfen
            )
        ),
        KasusLessonCard(
            title: "Die Umstellprobe",
            english: "Move a block",
            lines: [
                "A phrase moves through the sentence as one **block**, and its case travels with it. „*Der Mann gibt dem Kind den Ball*“, „*Dem Kind gibt der Mann den Ball*“, „*Den Ball gibt der Mann dem Kind*“: three orders, one meaning.",
                "That is why German can start a sentence with whatever it wants to stress. Read the endings, then the order.",
            ],
            example: KasusLessonExample(
                de: "{akk:Den Ball} *gibt* {nom:der Mann} {dat:dem Kind}.",
                en: "{nom:The man} gives {dat:the child} {akk:the ball}."
            )
        ),
        KasusLessonCard(
            title: "Die Probe",
            english: "Swap in der Mann",
            lines: [
                "{f:die}, {n:das} and {pl:die} look the same in the {nom:Nominativ} and the {akk:Akkusativ}; {f:der} is {dat:Dativ} or {gen:Genitiv}. When a form could be two cases, swap in *der Mann*: it is the one gender whose article shows every case.",
                "„*Ich helfe der Frau*“ → „*Ich helfe* {m:dem} *Mann*“ → {dat:Dativ}. „*Das Auto der Frau*“ → „*das Auto* {m:des} *Mannes*“ → {gen:Genitiv}.",
            ],
            example: KasusLessonExample(
                de: "{nom:Der Sohn} *hilft* {dat:der Mutter} *mit* {dat:dem Koffer}.",
                en: "{nom:The son} helps {dat:the mother} with {dat:the suitcase}."
            )
        ),
        KasusLessonCard(
            title: "Merkhilfen",
            english: "Memory aids",
            lines: [
                "Two to keep: the model sentence, and the Check as a routine. The rest are under Nachschlagen ▸ Warum dieser Fall? ▸ Merkhilfen.",
            ],
            mnemonic: KasusMnemonics.modelSentence
        ),
    ]
}
