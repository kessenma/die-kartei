//
//  GermanBasicWords.swift
//  german-ai-flashcards
//
//  The words a word count of a job ad should be able to hide: articles, pronouns, prepositions,
//  conjunctions, the forms of sein/haben/werden and the modal verbs, and the small adverbs and
//  particles every sentence carries. Without them the top of a frequency list is „und, der, die,
//  Sie, in“ in every ad ever written, and the words that make the ad an ad sink out of sight.
//
//  Lowercased surface forms. Deliberately not the Goethe A1 list: „Erfahrung“ and „Team“ are A1
//  words and exactly what a learner reading a posting may still want to see. Hiding by level is
//  its own filter (`JobVocabFilter.hideUpTo`).
//

import Foundation

nonisolated enum GermanBasicWords {

    static func contains(_ word: String) -> Bool {
        all.contains(word.lowercased())
    }

    static let all: Set<String> = {
        var words = Set<String>()
        for list in [articles, pronouns, prepositions, conjunctions, verbs, adverbs, questions, numbers, abbreviations] {
            for word in list.split(whereSeparator: \.isWhitespace) {
                words.insert(String(word))
            }
        }
        return words
    }()

    private static let articles = """
    der die das den dem des ein eine einen einem einer eines \
    kein keine keinen keinem keiner keines
    """

    private static let pronouns = """
    ich du er sie es wir ihr mich dich sich uns euch mir dir ihm ihn ihnen \
    mein meine meinen meinem meiner meines dein deine deinen deinem deiner deines \
    sein seine seinen seinem seiner seines ihre ihren ihrem ihrer ihres \
    unser unsere unseren unserem unserer unseres unsern euer eure euren eurem eurer eures \
    dies diese dieser dieses diesen diesem jene jener jenes jenen jenem \
    welche welcher welches welchen welchem solche solcher solches solchen solchem \
    jede jeder jedes jeden jedem alle aller alles allen allem man selbst selber \
    etwas nichts jemand niemand einander derer dessen deren denen
    """

    private static let prepositions = """
    an am ans auf aus bei beim bis durch für gegen hinter in im ins mit nach neben ohne \
    seit über um unter von vom vor während wegen zu zum zur zwischen innerhalb außerhalb \
    trotz statt anstatt laut gemäß ab per pro je via samt inklusive bzgl bezüglich
    """

    private static let conjunctions = """
    und oder aber denn sondern dass ob weil wenn als wie damit sowie bzw sowohl entweder \
    weder noch falls obwohl sodass während bevor nachdem indem
    """

    private static let verbs = """
    sein bin bist ist sind seid war warst waren wart gewesen wäre wären \
    haben habe hast hat habt hatte hattest hatten hattet gehabt hätte hätten \
    werden werde wirst wird werdet wurde wurdest wurden wurdet worden geworden würde würden würdest \
    können kann kannst könnt konnte konnten könnte könnten \
    müssen muss musst müsst musste mussten müsste müssten \
    sollen soll sollst sollt sollte sollten \
    wollen will willst wollt wollte wollten möchte möchten möchtest \
    dürfen darf darfst dürft durfte durften dürfte dürften
    """

    private static let adverbs = """
    nicht auch noch schon nur sehr so dann da dort hier mehr gern gerne ja nein doch mal \
    immer wieder bereits etwa ganz eben also sowie zudem außerdem dabei dafür damit darauf \
    darin davon dazu hierbei hierfür somit sogar bitte gerade ebenfalls jetzt heute \
    viel viele vielen vieler vieles wenig wenige besonders insbesondere bzw usw etc
    """

    private static let questions = """
    was wer wen wem wessen wie wo wann warum wieso weshalb wohin woher womit wofür worauf
    """

    private static let numbers = """
    null eins zwei drei vier fünf sechs sieben acht neun zehn elf zwölf zwanzig hundert tausend \
    erste ersten erster erstes zweite zweiten
    """

    /// What the tokenizer keeps of „z. B.“, „u. a.“, „ggf.“, „inkl.“ and the gender tag „(m/w/d)“.
    private static let abbreviations = """
    ggf inkl ca evtl zb ua uvm mwd
    """
}
