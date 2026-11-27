//
//  JobAdGlossary.swift
//  german-ai-flashcards
//
//  Die Formeln: the set phrases German job ads are written in. Every posting says „ab sofort“,
//  „unbefristet“, „in Wort und Schrift“, „aussagekräftige Bewerbungsunterlagen“, and none of them
//  means quite what a word-by-word reading suggests. Bundled, so the reader can mark them (the
//  dotted glossary underline the class handouts use) and answer a tap without the tutor, the save
//  sheet can fill their English, and the posting can list them.
//
//  `german` is the headword as a card would hold it; a text is matched word by word on stems
//  (`GermanStem`), so „unbefristeten“ finds „unbefristet“ and „abgeschlossenen Berufsausbildung“
//  finds its formula. `note` says what the phrase signals, when the English alone would mislead.
//

import Foundation

nonisolated struct JobAdFormula: Hashable, Sendable, Identifiable {
    let german: String
    let english: String
    let note: String?

    var id: String { german.lowercased() }

    init(_ german: String, _ english: String, _ note: String? = nil) {
        self.german = german
        self.english = english
        self.note = note
    }
}

/// One place a formula stands in a text, as the text spells it.
nonisolated struct JobAdFormulaMatch: Hashable, Sendable {
    let formula: JobAdFormula
    /// The words as they stand („abgeschlossenen Berufsausbildung“).
    let span: String
    /// UTF-16 offset of the first word.
    let location: Int
}

nonisolated enum JobAdGlossary {

    /// The formulas a posting uses, in the order they first appear, each once. A formula inside a
    /// longer one found at the same place („Berufserfahrung“ in „mehrjährige Berufserfahrung“) is
    /// left to the longer one.
    static func formulas(in text: String) -> [JobAdFormula] {
        var seen = Set<String>()
        return matches(in: text).compactMap { seen.insert($0.formula.id).inserted ? $0.formula : nil }
    }

    /// Every use of every formula. Words are compared by stem, so an inflected use counts
    /// („unbefristeten“, „abgeschlossenen Berufsausbildung“) while a compound never does
    /// („befristet“ is not found in „unbefristet“).
    static func matches(in text: String) -> [JobAdFormulaMatch] {
        let ns = text as NSString
        let tokens = JobVocabAnalyzer.tokens(in: text)
        let stems = tokens.map { GermanStem.stem($0.text) }
        var index: [String: [Int]] = [:]
        for (position, stem) in stems.enumerated() { index[stem, default: []].append(position) }

        var found: [(start: Int, end: Int, match: JobAdFormulaMatch)] = []
        for formula in all {
            let wanted = JobVocabAnalyzer.tokens(in: searchKey(formula.german)).map { GermanStem.stem($0.text) }
            guard let first = wanted.first else { continue }
            for start in index[first] ?? [] where start + wanted.count <= stems.count {
                guard Array(stems[start ..< start + wanted.count]) == wanted else { continue }
                let end = start + wanted.count - 1
                let from = tokens[start].range.location
                let to = NSMaxRange(tokens[end].range)
                var span = ns.substring(with: NSRange(location: from, length: to - from))
                // „(m/w/d)“ is matched by its letters; the span keeps the brackets out.
                span = span.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                found.append((start, end, JobAdFormulaMatch(formula: formula, span: span, location: from)))
            }
        }
        // The longest formula wins where two overlap.
        let kept = found.filter { candidate in
            !found.contains { other in
                other.end - other.start > candidate.end - candidate.start
                    && other.start <= candidate.start && other.end >= candidate.end
            }
        }
        return kept.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }.map(\.match)
    }

    /// The headword without its article and brackets, lowercased: what a text is searched for.
    static func searchKey(_ german: String) -> String {
        var lower = german.lowercased()
        for article in ["der ", "die ", "das "] where lower.hasPrefix(article) {
            lower = String(lower.dropFirst(article.count))
        }
        return lower
    }

    /// The text's formulas as the reader's dotted glossary marking: single words by the form the
    /// text uses, phrases by their span.
    @MainActor
    static func highlight(in text: String) -> GlossaryHighlight {
        var highlight = GlossaryHighlight()
        for match in matches(in: text) {
            let entry = GlossaryEntry(german: match.formula.german, english: match.formula.english)
            if JobVocabAnalyzer.tokens(in: match.span).count > 1 || !match.span.allSatisfy({ $0.isLetter }) {
                if highlight.phraseEntries[match.span.lowercased()] == nil {
                    highlight.phrases.append(match.span)
                    highlight.phraseEntries[match.span.lowercased()] = entry
                }
            } else {
                highlight.words[match.span.lowercased()] = entry
            }
        }
        return highlight
    }

    /// Answers for the word inspector: each word and phrase as the text spells it.
    @MainActor
    static func knownTranslations(in text: String) -> [String: KnownTranslation] {
        var known: [String: KnownTranslation] = [:]
        for match in matches(in: text) {
            known[match.span.lowercased()] = KnownTranslation(german: match.formula.german, english: match.formula.english)
        }
        return known
    }

    static let all: [JobAdFormula] = [
        // Who, when, how long
        JobAdFormula("(m/w/d)", "(m/f/d): male, female, diverse",
                     "The legally required note that any gender may apply. Not part of the job title."),
        JobAdFormula("(w/m/d)", "(f/m/d): female, male, diverse",
                     "The legally required note that any gender may apply. Not part of the job title."),
        JobAdFormula("ab sofort", "starting immediately"),
        JobAdFormula("zum nächstmöglichen Zeitpunkt", "as soon as possible",
                     "The start date is open: say in your letter when you could start."),
        JobAdFormula("zum frühestmöglichen Zeitpunkt", "at the earliest possible date"),
        JobAdFormula("frühestmöglicher Eintrittstermin", "earliest possible start date",
                     "They want this date in your application."),
        JobAdFormula("unbefristet", "permanent (no end date)"),
        JobAdFormula("befristet", "fixed-term", "Ads usually say for how long: „befristet auf zwei Jahre“."),
        JobAdFormula("Vollzeit", "full-time"),
        JobAdFormula("Teilzeit", "part-time"),
        JobAdFormula("die Probezeit", "probation period", "Usually six months; either side may end it on short notice."),
        JobAdFormula("die Kündigungsfrist", "notice period"),
        JobAdFormula("der Quereinsteiger", "career changer", "„Quereinsteiger willkommen“: no formal training in the field needed."),
        JobAdFormula("der Berufseinsteiger", "entry-level candidate, graduate"),
        JobAdFormula("die Werkstudentin", "working student (female)", "A student working up to 20 hours a week during the semester."),
        JobAdFormula("der Werkstudent", "working student", "A student working up to 20 hours a week during the semester."),
        JobAdFormula("die Festanstellung", "permanent position"),
        JobAdFormula("die Arbeitnehmerüberlassung", "temporary agency work",
                     "You are employed by an agency and lent to the company."),

        // What they ask for
        JobAdFormula("in Wort und Schrift", "spoken and written"),
        JobAdFormula("verhandlungssicher", "business fluent", "Good enough to negotiate in: about C1."),
        JobAdFormula("fließend", "fluent"),
        JobAdFormula("die Muttersprache", "native language", "„Deutsch auf Muttersprachniveau“: near-native German."),
        JobAdFormula("setzen wir voraus", "we require", "A must, not a wish."),
        JobAdFormula("wünschenswert", "desirable, a plus", "Nice to have: apply without it."),
        JobAdFormula("von Vorteil", "an advantage", "Nice to have: apply without it."),
        JobAdFormula("idealerweise", "ideally", "Nice to have: apply without it."),
        JobAdFormula("erforderlich", "required"),
        JobAdFormula("zwingend erforderlich", "strictly required"),
        JobAdFormula("eine vergleichbare Qualifikation", "an equivalent qualification",
                     "Another degree or training that fits counts too."),
        JobAdFormula("abgeschlossene Berufsausbildung", "completed vocational training",
                     "Germany's two- to three-year apprenticeship, with a certificate."),
        JobAdFormula("abgeschlossenes Studium", "completed university degree"),
        JobAdFormula("die Berufserfahrung", "work experience"),
        JobAdFormula("mehrjährige Berufserfahrung", "several years of work experience", "Usually means three years or more."),
        JobAdFormula("erste Berufserfahrung", "some work experience", "Internships and student jobs often count."),
        JobAdFormula("fundierte Kenntnisse", "solid knowledge"),
        JobAdFormula("sicherer Umgang mit", "confident use of"),
        JobAdFormula("die Teamfähigkeit", "ability to work in a team"),
        JobAdFormula("die Belastbarkeit", "ability to work under pressure"),
        JobAdFormula("die Eigeninitiative", "initiative, self-motivation"),
        JobAdFormula("selbstständige Arbeitsweise", "working independently"),
        JobAdFormula("eigenverantwortlich", "on your own responsibility, independently"),
        JobAdFormula("die Reisebereitschaft", "willingness to travel"),
        JobAdFormula("der Führerschein Klasse B", "car driving licence (class B)"),
        JobAdFormula("die Zuverlässigkeit", "reliability"),

        // What they offer
        JobAdFormula("Wir bieten", "We offer", "The benefits section starts here."),
        JobAdFormula("flexible Arbeitszeiten", "flexible working hours"),
        JobAdFormula("die Gleitzeit", "flexitime", "You choose when to start and stop, within core hours."),
        JobAdFormula("die Vertrauensarbeitszeit", "trust-based working hours", "No time clock: the work counts, not the hours."),
        JobAdFormula("mobiles Arbeiten", "remote work"),
        JobAdFormula("das Homeoffice", "working from home"),
        JobAdFormula("flache Hierarchien", "flat hierarchies"),
        JobAdFormula("die Weiterbildungsmöglichkeiten", "training opportunities"),
        JobAdFormula("betriebliche Altersvorsorge", "company pension scheme"),
        JobAdFormula("vermögenswirksame Leistungen", "employer savings contributions",
                     "A small monthly amount the employer pays into a savings plan for you."),
        JobAdFormula("das Jobrad", "company bike leasing"),
        JobAdFormula("das Jobticket", "subsidised public transport pass"),
        JobAdFormula("das Deutschlandticket", "Germany-wide public transport pass"),
        JobAdFormula("Tarifvertrag", "collective wage agreement", "Pay follows a union-negotiated scale (e.g. „TVöD“, „IG Metall“)."),
        JobAdFormula("tarifliche Vergütung", "pay according to the collective agreement"),
        JobAdFormula("leistungsgerechte Vergütung", "performance-based pay", "Says nothing about the amount."),
        JobAdFormula("attraktive Vergütung", "attractive pay", "Says nothing about the amount."),
        JobAdFormula("das Weihnachtsgeld", "Christmas bonus"),
        JobAdFormula("das Urlaubsgeld", "holiday pay"),
        JobAdFormula("Tage Urlaub", "days of holiday", "The legal minimum is 20 days on a five-day week; 30 is common."),
        JobAdFormula("die Einarbeitung", "onboarding, training-in period"),
        JobAdFormula("ein unbefristetes Arbeitsverhältnis", "a permanent employment contract"),

        // How to apply
        JobAdFormula("die Bewerbungsunterlagen", "application documents",
                     "Usually cover letter, CV and references (Zeugnisse)."),
        JobAdFormula("aussagekräftige Bewerbungsunterlagen", "complete application documents",
                     "Cover letter, CV and references that show why you fit."),
        JobAdFormula("das Anschreiben", "cover letter"),
        JobAdFormula("der Lebenslauf", "CV, résumé"),
        JobAdFormula("die Zeugnisse", "references and certificates",
                     "School and university certificates, and the reference letters past employers must write."),
        JobAdFormula("das Arbeitszeugnis", "employer's reference letter"),
        JobAdFormula("die Gehaltsvorstellung", "salary expectation", "Give a yearly gross figure in your letter."),
        JobAdFormula("unter Angabe", "stating, including"),
        JobAdFormula("der Ansprechpartner", "contact person"),
        JobAdFormula("die Ansprechpartnerin", "contact person (female)"),
        JobAdFormula("die Kennziffer", "reference number", "Quote it in your application."),
        JobAdFormula("Wir freuen uns auf Ihre Bewerbung", "We look forward to your application"),
        JobAdFormula("bei gleicher Eignung", "with equal qualifications",
                     "Part of the note that disabled applicants are preferred when equally suited."),
        JobAdFormula("Schwerbehinderte", "people with severe disabilities"),
    ]
}
