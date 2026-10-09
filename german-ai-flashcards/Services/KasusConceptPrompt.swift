//
//  KasusConceptPrompt.swift
//  german-ai-flashcards
//
//  The prompt for one tutor-written Verstehen item: write exactly one sentence with these phrases,
//  exactly as given. The plan says who does what (the tutor never decides a case); for a Wer plan
//  it also says which phrase opens the sentence. The answer comes back on one `SATZ:` line, which
//  `KasusConceptCheck` parses. No MLX here, so `training/kasus_cli` compiles it.
//

import Foundation

nonisolated enum KasusConceptPrompt {

    /// Sampled like the tutor-written stories.
    static let temperature: Float = 0.75
    /// One sentence and its label; generous, so a stop is never the model running out.
    static let maxTokens = 96

    static let system = "Du bist eine Deutschlehrerin. Du schreibst einfache, natürliche deutsche Sätze für Deutschlernende und hältst dich genau an die Vorgaben."

    static func build(_ plan: KasusConceptPlan) -> (system: String, user: String) {
        var lines = ["Schreibe genau einen deutschen Satz auf Niveau \(plan.level)."]
        let forms = plan.verbForms.map { "„\($0)“" }.joined(separator: " oder ")
        lines.append("Verb: „\(plan.verbLemma)“, in der Form \(forms).")
        lines.append("Verwende diese Ausdrücke genau so, wie sie hier stehen. Ändere keinen Artikel und keine Endung:")
        for (index, phrase) in plan.phrases.enumerated() where !phrase.isAttribute {
            var line = "- \(plan.fullExpression(index)) (\(role(phrase))"
            for attribute in plan.phrases where attribute.head == index {
                let head = phrase.phrase.split(separator: " ").last.map(String.init) ?? phrase.phrase
                line += "; „\(attribute.phrase)“ sagt, wessen \(head)"
            }
            lines.append(line + ")")
        }
        if let first = plan.firstPhrase, plan.phrases.indices.contains(first) {
            let opener = plan.fullExpression(first)
            lines.append("Beginne den Satz mit „\(opener.prefix(1).uppercased() + opener.dropFirst())“.")
        }
        lines.append("Ersetze keinen Artikel durch mein, sein, ihr …")
        lines.append("Du darfst eine Orts- oder Zeitangabe oder eine Ergänzung mit Präposition hinzufügen, aber keine weiteren Personen oder Tiere, keinen Nebensatz und kein „und“.")
        lines.append("Antworte nur in dieser Form:")
        lines.append("SATZ: <dein Satz>")
        return (system, lines.joined(separator: "\n"))
    }

    /// Who the phrase is in the sentence, in the plain words a teacher would use.
    static func role(_ phrase: KasusConceptPlannedPhrase) -> String {
        switch phrase.reason {
        case .subject:    "wer handelt"
        case .predicate:  "was das Subjekt ist"
        case .object:     "wen oder was"
        case .recipient:  "wem"
        case .dativeVerb: "wem"
        case .preposition: "mit Präposition"
        case .attribute:  "wessen"
        default:          "Ergänzung"
        }
    }
}
