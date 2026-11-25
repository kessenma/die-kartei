import Foundation

/// Unscored, curated explanations. Separate from lesson completion and the generated item bank.
nonisolated struct KasusExplainer: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let group: Group
    let units: [KasusUnit]
    let idea: String
    let examples: [Example]
    let takeaway: String
    let prompt: String
    let reveal: String
    let source: String

    enum Group: String, CaseIterable {
        case foundations = "Grundlagen · Read the sentence"
        case contrasts = "Unterschiede · Spot the difference"
        case deeper = "Weiterdenken · Beyond the shortcuts"
    }

    struct Example {
        let de: String
        let en: String
        let why: String
    }

    static let all: [KasusExplainer] = [
        .init(id: "gender-case", title: "Genus ≠ Kasus", subtitle: "Gender picks the column. Case picks the row.",
              group: .foundations, units: [.nominativ, .akkusativ, .dativ, .genitiv],
              idea: "Learn a noun with its dictionary article: *die Frau*. Its gender stays feminine when its job in a sentence changes. The article form can change without changing that gender.",
              examples: [
                .init(de: "{nom:Die Frau} lacht.", en: "{nom:The woman} laughs.", why: "The subject is feminine + Nominativ: **die**."),
                .init(de: "Ich spreche mit {dat:der Frau}.", en: "I speak with {dat:the woman}.", why: "*mit* requires Dativ. Feminine + Dativ gives **der**. She has not become masculine.")
              ],
              takeaway: "First decide the case from the sentence. Then combine it with the noun's gender or plural to find the form in the table.",
              prompt: "In „mit der Frau“, does der tell you the noun is masculine?",
              reveal: "No. *Frau* is feminine. **der** is also the feminine Dativ form here; *mit* tells you which case to read.",
              source: "https://grammis.ids-mannheim.de/sgt/2218"),
        .init(id: "word-order", title: "Vorne heißt nicht Subjekt", subtitle: "The first phrase is not always the subject.",
              group: .foundations, units: [.nominativ, .akkusativ],
              idea: "German can put an object first to make it the topic. Follow the case clues before assuming that the first noun does the action.",
              examples: [
                .init(de: "{nom:Der Hund} sieht {akk:den Mann}.", en: "{nom:The dog} sees {akk:the man}.", why: "**der Hund** is the subject; **den Mann** is the object."),
                .init(de: "{akk:Den Mann} sieht {nom:der Hund}.", en: "{nom:The dog} sees {akk:the man}.", why: "The man is mentioned first, but **den** still marks the object. The event has not changed.")
              ],
              takeaway: "Moving a phrase can change emphasis without changing its case. Swapping der and den changes who sees whom.",
              prompt: "Who sees whom in „Den Hund sieht der Mann“?",
              reveal: "The man sees the dog. **der Mann** is Nominativ; **den Hund** is Akkusativ. Read the endings before the order.",
              source: "https://grammis.ids-mannheim.de/systematische-grammatik/1063"),
        .init(id: "same-form", title: "Gleiche Form, anderer Fall", subtitle: "An unchanged article can hide a changed job.",
              group: .foundations, units: [.akkusativ, .dativ, .genitiv],
              idea: "Several cells of the article table look identical. A form narrows the possibilities; the sentence tells you which one applies.",
              examples: [
                .init(de: "{nom:Die Katze} schläft.", en: "{nom:The cat} sleeps.", why: "**die Katze** is the subject: Nominativ."),
                .init(de: "Der Mann sieht {akk:die Katze}.", en: "The man sees {akk:the cat}.", why: "**die Katze** is the object of *sehen*: Akkusativ. The article happens to look the same.")
              ],
              takeaway: "Die Probe swaps in a masculine phrase to make the contrast visible: der Hund sleeps; someone sees den Hund. It reveals a case you establish from the sentence.",
              prompt: "Does an unchanged die prove that the phrase is Nominativ?",
              reveal: "No. Feminine singular and plural use **die** in both Nominativ and Akkusativ. Check the phrase's relationship to the verb or preposition.",
              source: "https://grammis.ids-mannheim.de/sgt/2218"),
        .init(id: "verb-partners", title: "Das Verb bringt seine Partner mit", subtitle: "Learn helfen + Dativ, fragen + Akkusativ.",
              group: .contrasts, units: [.akkusativ, .dativ],
              idea: "The person you interact with is not automatically a Dativ receiver. A verb comes with a pattern for its objects. Learn that pattern along with its meaning.",
              examples: [
                .init(de: "Die Frau hilft {dat:dem Mann}.", en: "The woman helps {dat:the man}.", why: "*helfen* takes a Dativ object. Nothing has to be handed over."),
                .init(de: "Die Frau fragt {akk:den Mann}.", en: "The woman asks {akk:the man}.", why: "*fragen* takes an Akkusativ object, even though the man receives a question.")
              ],
              takeaway: "Store a useful chunk: jemandem helfen, jemanden fragen. English him does not distinguish the two German cases.",
              prompt: "Why does „Ich danke dem Lehrer“ use dem?",
              reveal: "*danken* takes Dativ. The verb's pattern is stronger evidence than an English translation or the idea that a person is affected.",
              source: "https://grammis.ids-mannheim.de/sgt/2279"),
        .init(id: "dativ-verbs", title: "Die Dativ-Verben", subtitle: "helfen, danken, gefallen … and the verbs that only feel like them.",
              group: .contrasts, units: [.dativ],
              idea: "A small set of verbs always puts its person in the {dat:Dativ}, with no „to“ anywhere in the English: *helfen, danken, gefallen, gehören, folgen, antworten, gratulieren, schmecken, passen, fehlen, zuhören, glauben, vertrauen, begegnen*. Three verbs feel just like them and take the {akk:Akkusativ}: *fragen, anrufen, besuchen*.",
              examples: [
                .init(de: "Ich danke {dat:dem Lehrer}.", en: "I thank {dat:the teacher}.", why: "*danken* takes the Dativ. English „thank *him*“ hides it."),
                .init(de: "Das Essen gefällt {dat:dem Kind}.", en: "{dat:The child} likes the food.", why: "With *gefallen* the thing liked is the subject; the one who likes it is the Dativ receiver."),
                .init(de: "Ich frage {akk:den Lehrer}.", en: "I ask {akk:the teacher}.", why: "*fragen* takes the Akkusativ, although the teacher gets the question.")
              ],
              takeaway: "Learn the verb with its case, the way you learn a noun with its article: jemandem helfen, jemanden fragen. Dativ ▸ Üben ▸ Dativ-Verben asks exactly these.",
              prompt: "„Ich rufe ___ Freund an.“ Which form?",
              reveal: "**den**: *anrufen* takes the Akkusativ, even though the call reaches someone. It is a false friend, with *fragen* and *besuchen*.",
              source: "https://grammis.ids-mannheim.de/sgt/2279"),
        .init(id: "place-goal", title: "Bewegung reicht nicht", subtitle: "Movement within a place versus movement into it.",
              group: .contrasts, units: [.akkusativ, .dativ],
              idea: "With spatial two-way prepositions such as *in*, ask what the prepositional phrase describes: the place where the activity happens, or its destination? Both can involve movement.",
              examples: [
                .init(de: "Das Kind läuft in {dat:dem Park}.", en: "The child runs in {dat:the park}.", why: "The running happens inside the park. *in dem* (usually **im**) locates the activity: Dativ."),
                .init(de: "Das Kind läuft in {akk:den Park}.", en: "The child runs into {akk:the park}.", why: "The park is the destination reached by going into it: Akkusativ.")
              ],
              takeaway: "This contrast belongs to spatial two-way prepositions. *zu* still takes Dativ for a destination; fixed combinations such as *warten auf* have their own case pattern.",
              prompt: "A swimmer is already in the pool: „Sie schwimmt im Becken.“ Why Dativ despite movement?",
              reveal: "The phrase says where the swimming happens. It does not describe entering the pool. **im** = **in dem**.",
              source: "https://grammis.ids-mannheim.de/progr@mm/6858"),
        .init(id: "receiver-beneficiary", title: "Dem Kind oder für das Kind?", subtitle: "The same person, two different constructions.",
              group: .contrasts, units: [.akkusativ, .dativ],
              idea: "Meaning helps you understand a sentence, but its construction decides the case. Someone can benefit from an action in more than one grammatical pattern.",
              examples: [
                .init(de: "Ich gebe {dat:dem Kind} {akk:den Ball}.", en: "I give {akk:the ball} to {dat:the child}.", why: "*geben* has a Dativ recipient and an Akkusativ thing given."),
                .init(de: "Ich kaufe {akk:den Ball} für {akk:das Kind}.", en: "I buy {akk:the ball} for {akk:the child}.", why: "Inside **für das Kind**, *für* requires Akkusativ. Being the beneficiary does not override the preposition.")
              ],
              takeaway: "Find the boundaries of the phrase. A preposition controls its own noun phrase; it does not change every other noun in the sentence.",
              prompt: "In „Ich gebe dem Kind einen Ball für den Hund“, why is the dog Akkusativ?",
              reveal: "**für den Hund** is its own prepositional phrase. *für* takes Akkusativ; **dem Kind** remains the Dativ recipient of *geben*.",
              source: "https://grammis.ids-mannheim.de/progr@mm/6727"),
        .init(id: "nested-genitive", title: "Ein Fall im anderen", subtitle: "A Genitiv phrase can sit inside an object.",
              group: .deeper, units: [.genitiv],
              idea: "A phrase can contain another phrase with its own case. In *der Hund der Frau*, the Genitiv tells you whose dog it is. The larger dog phrase can do different jobs.",
              examples: [
                .init(de: "{nom:Der Hund} {gen:der Frau} schläft.", en: "{nom:The dog} {gen:of the woman} sleeps.", why: "The whole dog phrase is the subject. **der Frau** describes its relation to *Hund*: Genitiv."),
                .init(de: "Ich sehe {akk:den Hund} {gen:der Frau}.", en: "I see {akk:the dog} {gen:of the woman}.", why: "The whole dog phrase is now the object of *sehen*. **den Hund** changes; the embedded **der Frau** stays Genitiv.")
              ],
              takeaway: "Do not assign one case to every noun in a long phrase. Ask what each smaller phrase connects to: the verb, a preposition, or another noun.",
              prompt: "In „mit dem Hund der Frau“, which part does mit control?",
              reveal: "*mit* makes the outer dog phrase Dativ: **dem Hund**. The embedded **der Frau** still identifies whose dog: Genitiv.",
              source: "https://grammis.ids-mannheim.de/sgt/2218"),
        .init(id: "subject-not-doer", title: "Subjekt heißt nicht immer Täter", subtitle: "A grammatical subject need not perform an action.",
              group: .deeper, units: [.nominativ, .dativ],
              idea: "“Doer” is a starting memory aid, not a definition of Nominativ. The subject is a grammatical job. Look at the German verb and its agreement instead of copying the English subject.",
              examples: [
                .init(de: "{dat:Dem Kind} gefällt {nom:der Ball}.", en: "{nom:The ball} is pleasing to {dat:the child}.", why: "*der Ball* is the singular subject, so the verb is **gefällt**. The child experiences the liking in Dativ."),
                .init(de: "{dat:Dem Kind} gefallen {nom:die Bälle}.", en: "{nom:The balls} are pleasing to {dat:the child}.", why: "Change the balls to plural and the verb becomes **gefallen**. The child stays singular and Dativ.")
              ],
              takeaway: "In a passive sentence the subject can even receive the action: *Der Mann wird gesehen.* Nominativ identifies the subject, not necessarily the person acting.",
              prompt: "English says “The child likes the ball.” Must the German subject also be the child?",
              reveal: "No. With *gefallen*, German presents the ball as pleasing to the child. **der Ball** is the subject; **dem Kind** is Dativ.",
              source: "https://grammis.ids-mannheim.de/progr@mm/6727")
    ]

    static func forUnit(_ unit: KasusUnit?) -> [KasusExplainer] {
        guard let unit, unit != .alleFaelle else { return all }
        return all.filter { $0.units.contains(unit) }
    }
}
