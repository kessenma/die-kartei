//
//  ReflexivLesson.swift
//  german-ai-flashcards
//
//  Reflexive Verben · Lektion: the topic's lesson as paged cards, in the same shape as the units'
//  (`KasusLesson`), and its Regel lines and memory aid. Written for an English speaker, who
//  already says *myself* and *yourself*: the new thing is that German keeps the person in the
//  sentence when a second object follows (*I wash my hands* → „Ich wasche mir die Hände“), and
//  that only *ich* and *du* show the case. Swift literals, so the markup test reads them.
//

import Foundation

nonisolated enum ReflexivLesson {

    /// The Regel card's lines on the topic screen.
    static let ruleLines: [String] = [
        "Only the person? → {akk:Akkusativ}: *Ich wasche* {akk:mich}.",
        "A second object follows? → the person takes the {dat:Dativ}: *Ich wasche* {dat:mir} *die Hände*.",
        "Only *ich* and *du* change: {akk:mich} / {dat:mir}, {akk:dich} / {dat:dir}. *sich*, *uns* and *euch* stay as they are.",
    ]

    /// The last card's memory aid.
    static let mnemonic = KasusMnemonic(
        id: "reflexiv",
        title: "mich / mir · dich / dir",
        line: "Only the first two persons change: {akk:mich} → {dat:mir}, {akk:dich} → {dat:dir}. Everyone else keeps one form: {akk:sich}, {akk:uns}, {akk:euch}, {akk:sich}.",
        why: "A second object pushes the person into the Dativ; with nothing after the verb, the person is the Akkusativ object itself.",
        cases: [.akkusativ, .dativ],
        symbol: "arrow.uturn.backward.circle"
    )

    static let cards: [KasusLessonCard] = [
        KasusLessonCard(
            title: "Was heißt reflexiv?",
            english: "What reflexive means",
            lines: [
                "A **reflexive** verb points back at its subject: *I wash myself*. German does it with one small pronoun, *sich*, which changes with the person.",
                "{akk:mich} · {akk:dich} · {akk:sich} · {akk:uns} · {akk:euch} · {akk:sich}: me, you, him or her, us, you, them.",
                "Some verbs are always reflexive (*sich beeilen*, to hurry); others only when the action lands on the doer (*sich waschen*).",
            ],
            example: KasusLessonExample(
                de: "{nom:Ich} *wasche* {akk:mich}.",
                en: "{nom:I} wash {akk:myself}."
            ),
            showsColorKey: true
        ),
        KasusLessonCard(
            title: "Englisch zuerst",
            english: "English first",
            lines: [
                "You already use the forms: *myself, yourself, himself*. The difference is what happens when a **thing** joins in.",
                "English says *I wash my hands* and drops the person. German keeps the person and says *I wash myself the hands*.",
                "That kept person is the **receiver** of the washing, and a receiver is {dat:Dativ}.",
            ],
            example: KasusLessonExample(
                de: "{nom:Ich} *wasche* {dat:mir} {akk:die Hände}.",
                en: "{nom:I} wash {dat:myself} {akk:the hands}: my hands."
            )
        ),
        KasusLessonCard(
            title: "Akkusativ oder Dativ?",
            english: "mich or mir?",
            lines: [
                "The Kasus-Check's receiver question decides. Only the person after the verb? → the person is the object → {akk:Akkusativ}: {akk:mich}, {akk:dich}.",
                "A **second object** follows (the hands, the teeth, a book)? → that object takes the {akk:Akkusativ}, and the person becomes the receiver → {dat:Dativ}: {dat:mir}, {dat:dir}.",
                "Only *ich* and *du* show the difference. *sich*, *uns* and *euch* look the same in both cases, so the drill asks them for the **person**, not the case.",
            ],
            example: KasusLessonExample(
                de: "{nom:Du} *putzt* {dat:dir} {akk:die Zähne}.",
                en: "{nom:You} brush {dat:yourself} {akk:the teeth}: your teeth."
            )
        ),
        KasusLessonCard(
            title: "Immer Akkusativ, immer Dativ",
            english: "Always one, always the other",
            lines: [
                "Some verbs never take a second object: *sich beeilen, sich erholen, sich freuen, sich setzen, sich fühlen* → always {akk:Akkusativ}.",
                "Some always carry one: *sich etwas merken, sich etwas kaufen, sich etwas ansehen, sich etwas leisten* → the person is always {dat:Dativ}.",
                "Learn these with their case, the way you learn a noun with its article.",
            ],
            example: KasusLessonExample(
                de: "{nom:Ich} *merke* {dat:mir} {akk:die Nummer}.",
                en: "{nom:I} remember {akk:the number}: literally, I note it to {dat:myself}."
            )
        ),
        KasusLessonCard(
            title: "Die Falle: sich vorstellen",
            english: "The trap",
            lines: [
                "*Ich stelle* {akk:mich} *vor* = I introduce myself. *Ich stelle* {dat:mir} *die Stadt vor* = I imagine the city.",
                "The same verb, and the case carries the meaning: no second object, the person is the object; a second object, the person is the receiver.",
                "When in doubt, look for the thing after the verb. If there is one, the person is {dat:Dativ}.",
            ],
            example: KasusLessonExample(
                de: "{nom:Er} *stellt* {dat:sich} {akk:das Haus} *vor*.",
                en: "{nom:He} imagines {akk:the house}."
            ),
            mnemonic: mnemonic
        ),
    ]
}
