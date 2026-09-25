//
//  CaseEndingsView.swift
//  german-ai-flashcards
//
//  Kasus · the case-endings table (Nom/Akk/Dat/Gen × m/f/n/pl) and the classroom code that goes
//  with it: the last letters of the definite articles spell rese / nese / mrmn / srsr, and
//  ein-words take the same letters. Ending letters wear their gender color, row labels wear
//  their case color and symbol (both from GrammarPalette). The drill is generated from the
//  same `GrammarCase` table, so the two can never disagree. It is every Kasus unit's
//  Schnellrunde, limited to that unit's cases and presented through `ActivityRouter`
//  (`.caseEndings`); this screen is the reference only. The drill's right/wrong signal is
//  `KasusFeedback`, shared with the story player, and its explanations are `KasusRich` markup.
//

import SwiftUI
import SwiftData

/// A word with its ending in the gender color and bold, e.g. de**r**, mein**em**.
private func ending(_ stem: String, _ ending: String, _ gender: Gender) -> AttributedString {
    var tail = AttributedString(ending)
    tail.foregroundColor = gender.color
    tail.inlinePresentationIntent = .stronglyEmphasized
    return AttributedString(stem) + tail
}

private func plain(_ s: String) -> AttributedString { AttributedString(s) }

/// The code word with each letter in its column's gender color.
private func codeText(_ kasus: GrammarCase) -> Text {
    var out = AttributedString()
    for (letter, gender) in zip(kasus.code, Gender.allCases) {
        var run = AttributedString(String(letter))
        run.foregroundColor = gender.color
        out += run
    }
    return Text(out)
}

// MARK: - Case label

/// A case's symbol and name in its color: the chip every case lesson uses.
struct CaseLabel: View {
    let kasus: GrammarCase
    var style: Style = .short

    enum Style { case short, name }

    var body: some View {
        Label(style == .short ? kasus.short : kasus.name, systemImage: kasus.symbol)
            .foregroundStyle(kasus.color)
    }
}

// MARK: - Gender tag

/// A noun's gender as a teacher's table writes it (m, f, n, pl) on its gender color. Stands in
/// for the article wherever „der Hund“ would give the answer away.
struct GenderTag: View {
    let gender: Gender

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: gender.symbol)
                .font(.caption2)
            Text(gender.columnLabel)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(gender.color, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gender.genderName)
    }
}

// MARK: - The table

/// The endings table on its own, so the reference screen and the quick lesson share one layout.
/// With `highlight`, the other rows fade back so one case stands out.
struct CaseEndingsTable: View {
    var cases: [GrammarCase] = GrammarCase.allCases
    var highlight: GrammarCase?

    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 6, verticalSpacing: 14) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(Gender.allCases) { gender in
                    HStack(spacing: 3) {
                        Image(systemName: gender.symbol)
                            .font(.caption2)
                        Text(gender.columnLabel)
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(gender.color, in: RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous))
                    .accessibilityLabel(gender.genderName)
                }
            }
            ForEach(cases) { kasus in
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        // Not `CaseLabel`: inside a List a Label takes the row's wide icon slot,
                        // and „Nom“ truncated to „N…“ in this 62-point column.
                        HStack(spacing: 3) {
                            Image(systemName: kasus.symbol)
                            Text(kasus.short)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kasus.color)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(kasus.name)
                        codeText(kasus)
                            .font(.title3.weight(.heavy))
                    }
                    .frame(width: 62, alignment: .leading)
                    ForEach(Gender.allCases) { gender in
                        cell(kasus, gender)
                    }
                }
                .opacity(highlight == nil || highlight == kasus ? 1 : 0.3)
            }
        }
    }

    private func cell(_ kasus: GrammarCase, _ gender: Gender) -> some View {
        let article = kasus.article(gender)
        let einEnding = kasus.einEnding(gender)
        let nounEnding: String? = switch (kasus, gender) {
        case (.dativ, .plural):                 "+ n"
        case (.genitiv, .der), (.genitiv, .das): "+ s"
        default:                                nil
        }
        return VStack(spacing: 3) {
            Text(ending(String(article.dropLast()), String(article.suffix(1)), gender))
                .font(.subheadline)
            Text(ending(gender == .plural ? "mein" : "(m)ein", einEnding, gender))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let nounEnding {
                Text(nounEnding)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(gender.color)
            }
        }
        .frame(maxWidth: .infinity)
        .minimumScaleFactor(0.8)
        .lineLimit(1)
    }
}

// MARK: - Reference view

struct CaseEndingsView: View {
    @State private var showKasusCheck = false

    var body: some View {
        List {
            Section {
                CaseEndingsTable()
                    .padding(.vertical, 6)
            } footer: {
                Text(kasusRich: "The last letter of each article spells the code on the left. The noun itself changes in two places: **+ n** in the {dat:Dativ} plural, **+ s** on masculine and neuter in the {gen:Genitiv}.")
            }
            .themedListRow()

            kasusCheckSection
                .themedListRow()
            einWordSection
                .themedListRow()
            pluralSection
                .themedListRow()
            genitivSection
                .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Kasus · Case Endings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showKasusCheck) {
            KasusCheckSheet()
        }
    }

    /// Which row of the table: the Kasus-Check's six questions in short, then one sentence run
    /// through them. The full card, with examples and traps, is a tap away.
    private var kasusCheckSection: some View {
        Section {
            ForEach(KasusCheckSheet.steps) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(step.id)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .trailing)
                    Text(kasusRich: step.short)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    HStack(spacing: 8) {
                        // Not `CaseLabel`: inside a List a Label takes the row's wide icon slot.
                        ForEach(step.answers, id: \.kasus) { answer in
                            HStack(spacing: 2) {
                                Image(systemName: answer.kasus.symbol)
                                Text(answer.kasus.short)
                            }
                            .foregroundStyle(answer.kasus.color)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(answer.kasus.name)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .fixedSize()
                }
                .padding(.vertical, 1)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(ending("De", "r", .der) + plain(" Mann gibt ") + ending("de", "m", .das)
                     + plain(" Kind ") + ending("ein", "en", .der) + plain(" Ball."))
                    .font(.body)
                HStack(spacing: 14) {
                    caseChip(.nominativ, "der Mann")
                    caseChip(.dativ, "dem Kind")
                    caseChip(.akkusativ, "einen Ball")
                }
                Text(kasusRich: "No preposition, nothing hangs on another noun. *Der Mann* is the **subject** → {nom:Nominativ}. *dem Kind* is the **receiver** → {dat:Dativ}. *einen Ball* is none of these → {akk:Akkusativ}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            Button {
                showKasusCheck = true
            } label: {
                Label("Der Kasus-Check · with examples", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.medium))
            }
        } header: {
            Text("Welcher Fall? · Which case?")
                .themedSectionHeader()
        } footer: {
            Text("Ask in order; the first question that fits decides the case.")
        }
    }

    private func caseChip(_ kasus: GrammarCase, _ phrase: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // Not `CaseLabel`: inside a List a Label takes the row's wide icon slot.
            HStack(spacing: 3) {
                Image(systemName: kasus.symbol)
                Text(kasus.short)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kasus.color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kasus.name)
            Text(phrase)
                .font(.caption)
        }
    }

    private var einWordSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(kasusRich: "*ein, mein, dein, kein* and friends take the **same code letters** as the article: {m:den} → {m:einen}, {m:dem} → {m:einem}, {f:der} → {f:einer}.")
                    .font(.subheadline)
                Text(kasusRich: "Three spots have **no ending** at all: masculine {nom:Nominativ} and neuter {nom:Nominativ} and {akk:Akkusativ}.")
                    .font(.subheadline)
                Text(ending("De", "r", .der) + plain(" Hund → ein Hund   ·   ") + ending("da", "s", .das) + plain(" Kind → ein Kind"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("ein-Wörter · ein-words")
                .themedSectionHeader()
        }
    }

    private var pluralSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(plain("die Kinder → mit ") + ending("de", "n", .plural) + plain(" ") + ending("Kinder", "n", .plural))
                    .font(.subheadline)
                Text(kasusRich: "Plurals that already end in **-n** or **-s** stay as they are: *mit* {pl:den} *Frauen*, *mit* {pl:den} *Autos*.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            HStack(spacing: 6) {
                Image(systemName: GrammarCase.dativ.symbol)
                    .foregroundStyle(GrammarCase.dativ.color)
                Text("Dativ Plural · + n")
                    .themedSectionHeader()
            }
        }
    }

    private var genitivSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(plain("das Auto ") + ending("de", "s", .der) + plain(" ") + ending("Mann", "es", .der)
                     + plain("  ·  die Tasche ") + ending("de", "r", .die) + plain(" Frau"))
                    .font(.subheadline)
                Text(kasusRich: "**Masculine** and **neuter** nouns add **-s** (short words often **-es**). **Feminine** and **plural** nouns don't change. In everyday speech „*von* {m:dem} *Mann*“ often replaces it; writing and exams expect the {gen:Genitiv}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            HStack(spacing: 6) {
                Image(systemName: GrammarCase.genitiv.symbol)
                    .foregroundStyle(GrammarCase.genitiv.color)
                Text("Genitiv · B1")
                    .themedSectionHeader()
            }
        }
    }
}

// MARK: - Drill

/// A noun to hang an article on. People and animals only, so every sentence frame makes sense.
struct EndingsNoun {
    let singular: String
    let plural: String
    /// Genitive singular. Masculine and neuter add -(e)s, feminine nouns don't change.
    let genitive: String
    let gender: Gender   // .der / .die / .das

    /// Dative plural: + n unless the plural already ends in -n or -s.
    var dativePlural: String {
        plural.hasSuffix("n") || plural.hasSuffix("s") ? plural : plural + "n"
    }

    /// Genitive plural: the plural as it is. Only the article changes (der).
    var genitivePlural: String { plural }

    /// The noun as it stands after the article in this case and number.
    func form(_ kasus: GrammarCase, isPlural: Bool) -> String {
        switch (kasus, isPlural) {
        case (.dativ, true):    dativePlural
        case (.genitiv, true):  genitivePlural
        case (.genitiv, false): genitive
        case (_, true):         plural
        case (_, false):        singular
        }
    }

    static let all: [EndingsNoun] = [
        .init(singular: "Mann", plural: "Männer", genitive: "Mannes", gender: .der),
        .init(singular: "Hund", plural: "Hunde", genitive: "Hundes", gender: .der),
        .init(singular: "Lehrer", plural: "Lehrer", genitive: "Lehrers", gender: .der),
        .init(singular: "Vater", plural: "Väter", genitive: "Vaters", gender: .der),
        .init(singular: "Frau", plural: "Frauen", genitive: "Frau", gender: .die),
        .init(singular: "Katze", plural: "Katzen", genitive: "Katze", gender: .die),
        .init(singular: "Lehrerin", plural: "Lehrerinnen", genitive: "Lehrerin", gender: .die),
        .init(singular: "Freundin", plural: "Freundinnen", genitive: "Freundin", gender: .die),
        .init(singular: "Kind", plural: "Kinder", genitive: "Kindes", gender: .das),
        .init(singular: "Mädchen", plural: "Mädchen", genitive: "Mädchens", gender: .das),
        .init(singular: "Baby", plural: "Babys", genitive: "Babys", gender: .das),
        .init(singular: "Pferd", plural: "Pferde", genitive: "Pferdes", gender: .das),
    ]
}

/// Which article family fills the blank.
enum EndingsDeterminer: CaseIterable {
    case definite, ein, mein, kein

    func form(_ kasus: GrammarCase, _ gender: Gender) -> String {
        switch self {
        case .definite: kasus.article(gender)
        case .ein:      "ein" + kasus.einEnding(gender)
        case .mein:     "mein" + kasus.einEnding(gender)
        case .kein:     "kein" + kasus.einEnding(gender)
        }
    }

    /// The forms engine's family and stem, so a pick is graded by the same rules as a story blank.
    var kasusFamily: (family: KasusFamily, stem: String) {
        switch self {
        case .definite: (.definite, "")
        case .ein:      (.ein, "ein")
        case .mein:     (.possessive, "mein")
        case .kein:     (.kein, "kein")
        }
    }

    /// The family's forms to pick from. The Genitiv form (des, eines…) joins only when the round
    /// has Genitiv in play; before that it is a form the learner hasn't met.
    func options(includesGenitiv: Bool) -> [String] {
        var forms: [String] = switch self {
        case .definite: ["der", "die", "das", "den", "dem"]
        case .ein:      ["ein", "eine", "einen", "einem", "einer"]
        case .mein:     ["mein", "meine", "meinen", "meinem", "meiner"]
        case .kein:     ["kein", "keine", "keinen", "keinem", "keiner"]
        }
        if includesGenitiv { forms.append(form(.genitiv, .der)) }
        return forms
    }
}

/// A sentence with a blank; `{N}` is the noun. `why` names the case trigger in Kasus-Check terms
/// (preposition, another noun, subject, sein, receiver or Dativ verb, otherwise Akkusativ), in the
/// `KasusRich` markup.
struct EndingsFrame {
    let kasus: GrammarCase
    let singular: String
    let plural: String
    let why: String

    static let all: [EndingsFrame] = [
        .init(kasus: .nominativ, singular: "Das ist ___ {N}.", plural: "Das sind ___ {N}.", why: "„*sein*“ links it back to the **subject**, so it stays {nom:Nominativ}"),
        .init(kasus: .nominativ, singular: "Hier kommt ___ {N}.", plural: "Hier kommen ___ {N}.", why: "It's the **subject** of „*kommen*“, so {nom:Nominativ}"),
        .init(kasus: .akkusativ, singular: "Ich sehe ___ {N}.", plural: "Ich sehe ___ {N}.", why: "It's what „*sehen*“ acts on: the **direct object**, so {akk:Akkusativ}"),
        .init(kasus: .akkusativ, singular: "Kennst du ___ {N}?", plural: "Kennst du ___ {N}?", why: "It's what „*kennen*“ acts on: the **direct object**, so {akk:Akkusativ}"),
        .init(kasus: .akkusativ, singular: "Wir besuchen ___ {N}.", plural: "Wir besuchen ___ {N}.", why: "It's what „*besuchen*“ acts on, so {akk:Akkusativ}. „*besuchen*“ can feel like it has a receiver, but it takes the {akk:Akkusativ}"),
        .init(kasus: .dativ, singular: "Ich helfe ___ {N}.", plural: "Ich helfe ___ {N}.", why: "„*helfen*“ is one of the verbs that always take the {dat:Dativ}"),
        .init(kasus: .dativ, singular: "Wir sprechen mit ___ {N}.", plural: "Wir sprechen mit ___ {N}.", why: "„*mit*“ always takes the {dat:Dativ}"),
        .init(kasus: .dativ, singular: "Das Buch gehört ___ {N}.", plural: "Das Buch gehört ___ {N}.", why: "„*gehören*“ takes the {dat:Dativ}: the thing owned is the subject, the **owner** is {dat:Dativ}"),
        .init(kasus: .genitiv, singular: "Das ist der Name ___ {N}.", plural: "Das sind die Namen ___ {N}.", why: "It hangs on **another noun** (*der Name*), so {gen:Genitiv}"),
        .init(kasus: .genitiv, singular: "Wegen ___ {N} bleiben wir zu Hause.", plural: "Wegen ___ {N} bleiben wir zu Hause.", why: "„*wegen*“ takes the {gen:Genitiv}"),
    ]
}

struct EndingsQuestion: Identifiable {
    let id = UUID()
    let frame: EndingsFrame
    let noun: EndingsNoun
    let isPlural: Bool
    let determiner: EndingsDeterminer
    /// The buttons on offer, fixed when the round is built (they depend on the round's cases).
    let options: [String]

    var kasus: GrammarCase { frame.kasus }
    var gender: Gender { isPlural ? .plural : noun.gender }
    var answer: String { determiner.form(kasus, gender) }

    var nounForm: String { noun.form(kasus, isPlural: isPlural) }

    /// Right case, wrong gender („dem“ in „Ich helfe ___ Frau“), by the rule Einsetzen grades
    /// with, so the coach leaves it out here too. The Nominativ left unchanged („der“ for „dem
    /// Hund“) is a case miss.
    func isGenderSlip(_ pick: String) -> Bool {
        let (family, stem) = determiner.kasusFamily
        return KasusForms.isRightCaseWrongGender(pick: pick, answerCase: kasus, genus: gender,
                                                 family: family, stem: stem)
    }

    /// The sentence split around the blank.
    var parts: (before: String, after: String) {
        let template = (isPlural ? frame.plural : frame.singular)
            .replacingOccurrences(of: "{N}", with: nounForm)
        let pieces = template.components(separatedBy: "___")
        return (pieces.first ?? "", pieces.dropFirst().first ?? "")
    }

    /// Why, in the `KasusRich` markup: the frame's Kasus-Check reason, then the code-word line
    /// with the code letters in their gender colors („Masculine Dativ in „mrmn“ is m: dem.“), and
    /// the noun's own ending where it has one.
    var explanation: String {
        let tag = gender.columnLabel
        var text = "\(frame.why). "
        if determiner != .definite && kasus.einEnding(gender).isEmpty {
            text += "*\(gender.genderName.capitalized)* \(Self.caseWord(kasus)) is one of the spots with **no ending**: {\(tag):\(answer)}."
        } else {
            let letter = kasus.article(gender).suffix(1)
            text += "*\(gender.genderName.capitalized)* \(Self.caseWord(kasus)) in „\(Self.codeWord(kasus))“ is {\(tag):\(letter)}: {\(tag):\(answer)}."
        }
        if isPlural && kasus == .dativ && noun.dativePlural != noun.plural {
            text += " The noun adds **-n** too: *\(noun.plural)*{\(tag):n}."
        }
        if !isPlural && kasus == .genitiv && noun.genitive != noun.singular {
            text += " The noun adds **-\(noun.genitive.dropFirst(noun.singular.count))** too: *\(noun.genitive)*."
        }
        return text
    }

    /// A gender slip's own, softer line: the case was right, only the gender wasn't. The pick
    /// wears the color of the gender it belongs to.
    func slipNote(_ pick: String) -> String {
        let (family, stem) = determiner.kasusFamily
        let tag = gender.columnLabel
        let name = "*\(noun.singular)*"
        let others = KasusForms.gendersOfSlip(pick: pick, kasus: kasus, genus: gender, family: family, stem: stem)
        if let other = others.first {
            // „dem“ is masculine and neuter alike: named both ways, and bold rather than one color.
            let picked = others.count == 1 ? "{\(other.columnLabel):\(pick)}" : "**\(pick)**"
            let genders = others.map(\.genderName).joined(separator: " or ")
            return "Right case, wrong gender: \(picked) is \(genders) \(Self.caseWord(kasus)). \(name) is \(gender.genderName), so {\(tag):\(answer)}."
        }
        return "Right case, wrong gender. \(name) is \(gender.genderName), so {\(tag):\(answer)}."
    }

    /// What the drill says after a first pick: the slip note for a gender slip, the explanation
    /// for everything else.
    func feedback(pick: String) -> String {
        pick != answer && isGenderSlip(pick) ? slipNote(pick) : explanation
    }

    /// The case's name in its case color: `{dat:Dativ}`.
    static func caseWord(_ kasus: GrammarCase) -> String {
        "{\(kasus.short.lowercased()):\(kasus.name)}"
    }

    /// The code word with each letter in its column's gender color, as the table prints it.
    static func codeWord(_ kasus: GrammarCase) -> String {
        zip(kasus.code, Gender.allCases).map { "{\($1.columnLabel):\($0)}" }.joined()
    }

    /// How many of `count` questions each case gets. Nominativ is the easy baseline, so it weighs
    /// half as much as the others; `emphasis` (the unit's own case) weighs double on top. Every
    /// case in play gets at least one question, so a mixed round never turns single-case.
    static func quota(cases: [GrammarCase], emphasis: GrammarCase?, count: Int) -> [GrammarCase: Int] {
        let inPlay = GrammarCase.allCases.filter(cases.contains)
        guard !inPlay.isEmpty, count > 0 else { return [:] }
        let weights = inPlay.map { kasus -> Double in
            (kasus == .nominativ ? 1 : 2) + (kasus == emphasis ? 2 : 0)
        }
        let total = weights.reduce(0, +)
        let exact = weights.map { $0 / total * Double(count) }
        var counts = exact.map { max(1, Int($0)) }
        // Largest remainder fills the round; ties go to the later case on the path.
        let byRemainder = inPlay.indices.sorted {
            let a = exact[$0] - exact[$0].rounded(.down), b = exact[$1] - exact[$1].rounded(.down)
            return a == b ? $0 > $1 : a > b
        }
        var next = 0
        while counts.reduce(0, +) < count {
            counts[byRemainder[next % byRemainder.count]] += 1
            next += 1
        }
        // A very short round can overshoot on the one-each floor: trim the biggest share.
        while counts.reduce(0, +) > count,
              let biggest = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[biggest] > 1 {
            counts[biggest] -= 1
        }
        return Dictionary(uniqueKeysWithValues: zip(inPlay, counts))
    }

    /// A round over `cases`, weighted toward `emphasis`, no repeats. One case in, one case out:
    /// only the Nominativ unit asks a single case, since the others always keep earlier ones in.
    static func round(cases: [GrammarCase], emphasis: GrammarCase? = nil, count: Int = 10) -> [EndingsQuestion] {
        let includesGenitiv = cases.contains(.genitiv)
        var seen = Set<String>()
        var out: [EndingsQuestion] = []
        for (kasus, share) in quota(cases: cases, emphasis: emphasis, count: count) {
            let frames = EndingsFrame.all.filter { $0.kasus == kasus }
            guard !frames.isEmpty else { continue }
            for _ in 0..<share {
                for _ in 0..<50 {
                    let noun = EndingsNoun.all.randomElement()!
                    let isPlural = Int.random(in: 0..<4) == 0
                    let key = "\(kasus)|\(noun.singular)|\(isPlural)"
                    guard seen.insert(key).inserted else { continue }
                    // ein has no plural, and kein stays out of the Genitiv frames
                    // („wegen keines Hundes“ is German nobody says).
                    let determiner = EndingsDeterminer.allCases.filter {
                        !(isPlural && $0 == .ein) && !(kasus == .genitiv && $0 == .kein)
                    }.randomElement()!
                    out.append(.init(
                        frame: frames.randomElement()!, noun: noun, isPlural: isPlural,
                        determiner: determiner,
                        options: determiner.options(includesGenitiv: includesGenitiv)
                    ))
                    break
                }
            }
        }
        return out.shuffled()
    }
}

/// One Schnellrunde: which cases it asks, and which one it leans on. Launched through
/// `ActivityRouter` as `.caseEndings`; its round is filed under the unit
/// (`KasusService.quickRoundID(for:)`).
struct CaseEndingsSession: Identifiable {
    let id = UUID()
    let unit: KasusUnit
    let cases: [GrammarCase]
    /// The unit's own case, which gets the biggest share. Nil spreads the round evenly.
    let emphasis: GrammarCase?
    let title: String
    /// Set only by the DEBUG `-kasus.debugOpen quick:<unit>` argument, so a simulator that can't
    /// tap can still show an answered question. Nil in every real session.
    var prefill: KasusPrefill? = nil

    /// The unit's cases in play, weighted toward its own case (Alle Fälle spreads evenly).
    init(unit: KasusUnit, prefill: KasusPrefill? = nil) {
        self.unit = unit
        cases = unit.casesInPlay
        emphasis = unit.focusCase
        title = "Schnellrunde · \(unit.germanTitle)"
        self.prefill = prefill
    }
}

/// The Schnellrunde. The sentence is the hero, centered in the free space; the answer buttons sit
/// in the thumb zone at the bottom, and the verdict with its explanation slides in between them,
/// so nothing is ever pushed off screen. A strip of dots at the top keeps the round's score.
struct CaseEndingsDrillView: View {
    let session: CaseEndingsSession
    var hapticMode: HapticFeedbackMode
    /// Called once per finished round; `ContentView` hands it to `KasusService.recordRound`.
    var onComplete: (KasusRoundResult) -> Void
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The sentence's size: Large Title on a phone, and it follows Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 34

    @State private var questions: [EndingsQuestion]
    @State private var index = 0
    @State private var picked: String?
    @State private var results: [KasusItemResult] = []
    /// Each question's first pick, in order, for the misses under the summary.
    @State private var picks: [String] = []
    @State private var startedAt = Date()
    @State private var didSetUp = false
    /// DEBUG prefill: the answers weren't the learner's, so the round is never recorded.
    @State private var prefilled = false

    // Haptics
    @State private var correctCount = 0
    @State private var wrongCount = 0
    @State private var slipCount = 0
    /// The question screen's height, which caps the feedback card.
    @State private var playHeight: CGFloat = 0

    /// Wide enough for a sentence in large type; iPad centers it.
    private let contentWidth: CGFloat = 640

    init(session: CaseEndingsSession, hapticMode: HapticFeedbackMode = .all,
         onComplete: @escaping (KasusRoundResult) -> Void, onDismiss: @escaping () -> Void) {
        self.session = session
        self.hapticMode = hapticMode
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        _questions = State(initialValue: EndingsQuestion.round(cases: session.cases, emphasis: session.emphasis))
    }

    private var isFinished: Bool { index >= questions.count }

    var body: some View {
        NavigationStack {
            Group {
                if isFinished {
                    ScrollView {
                        summary
                            .padding()
                            .frame(maxWidth: contentWidth)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    play(questions[index])
                }
            }
            // The article game's ground: the grouped grey on Klar, so the white answer buttons
            // stand off it, and each identity theme's own paper elsewhere.
            .background(ThemedBackground().ignoresSafeArea())
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .onAppear(perform: setUp)
        .sensoryFeedback(.success, trigger: correctCount) { old, new in
            new > old && hapticMode.playsSuccess
        }
        .sensoryFeedback(.error, trigger: wrongCount) { old, new in
            new > old && hapticMode.playsError
        }
        .sensoryFeedback(.impact(weight: .light), trigger: slipCount) { old, new in
            new > old && hapticMode.playsError
        }
        // Presented from the root cover, outside any themed stack, so it sets its own tint.
        .tint(appTheme.accent(model: nil))
    }

    // MARK: Question

    private func play(_ q: EndingsQuestion) -> some View {
        VStack(spacing: 0) {
            KasusProgressStrip(marks: marks)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxWidth: contentWidth)

            // The sentence, centered in whatever the answer panel leaves; it scrolls rather than
            // clip when a long explanation meets a small phone.
            GeometryReader { geo in
                ScrollView {
                    prompt(q)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: contentWidth)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            answerPanel(q)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .frame(maxWidth: contentWidth)
                // Sized first, so at the largest text sizes the sentence scrolls instead of
                // Weiter being squeezed onto the buttons.
                .layoutPriority(1)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { playHeight = $0 }
        .animation(.snappy(duration: 0.3), value: picked)
    }

    private func prompt(_ q: EndingsQuestion) -> some View {
        VStack(spacing: 22) {
            nounHeader(q)
                .font(.headline)
            sentence(q, picked: picked)
                // Bigger on an iPad, where Large Title looks lost in the middle of the screen.
                .font(.system(size: sizeClass == .regular ? heroSize * 1.4 : heroSize, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The verdict and its why (once picked), the answer buttons, then Weiter. The buttons never
    /// move: the slot under them holds a hint until Weiter takes its place. The card scrolls past
    /// about a third of the screen, so at the largest text sizes Weiter stays reachable.
    private func answerPanel(_ q: EndingsQuestion) -> some View {
        VStack(spacing: 12) {
            if let picked {
                feedbackCard(q, picked: picked)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottom)))
            }
            KasusOptionGrid(options: q.options, answer: q.answer, kasus: q.kasus, picked: picked,
                            columns: 3, rowHeight: 58) { option in
                choose(option, for: q)
            }
            .id(q.id)
            Group {
                if picked != nil {
                    Button(action: next) {
                        Text(index + 1 == questions.count ? "Ergebnis · Results" : "Weiter")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("Tap the article that fits.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 50)
        }
    }

    /// The card keeps its frame and shadow; only what's inside scrolls once it passes the cap.
    private func feedbackCard(_ q: EndingsQuestion, picked: String) -> some View {
        let verdict: KasusVerdict = picked == q.answer ? .right : q.isGenderSlip(picked) ? .slip : .miss
        return KasusCappedScroll(maxHeight: playHeight > 0 ? max(110, playHeight * 0.32) : .infinity) {
            KasusFeedbackHeader(verdict: verdict, kasus: q.kasus)
            Text(kasusRich: q.feedback(pick: picked))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    /// Which noun the blank belongs to. A Nominativ blank shows the gender tag instead of
    /// „der Hund“, since the dictionary form *is* the Nominativ answer.
    @ViewBuilder
    private func nounHeader(_ q: EndingsQuestion) -> some View {
        if q.kasus == .nominativ {
            HStack(spacing: 8) {
                GenderTag(gender: q.gender)
                Text(q.isPlural ? "Plural of \(q.noun.singular)" : q.noun.singular)
                    .fontWeight(.medium)
            }
        } else {
            HStack(spacing: 6) {
                Text(q.isPlural ? "Plural of" : "Noun:")
                    .foregroundStyle(.secondary)
                Text.gendered(q.noun.singular, article: q.noun.gender.article)
                    .fontWeight(.medium)
            }
        }
    }

    /// The sentence with its gap. Answered: the answer in its gender color, bold, and a wrong
    /// pick struck through in grey in front of it.
    private func sentence(_ q: EndingsQuestion, picked: String?) -> Text {
        let (before, after) = q.parts
        var blank: AttributedString
        if let picked {
            blank = AttributedString(q.answer)
            blank.foregroundColor = q.gender.color
            blank.inlinePresentationIntent = .stronglyEmphasized
            if picked != q.answer {
                var wrong = AttributedString(picked)
                wrong.strikethroughStyle = .single
                wrong.foregroundColor = .secondary
                blank = wrong + AttributedString(" ") + blank
            }
        } else {
            blank = AttributedString("_____")
            blank.foregroundColor = .secondary
        }
        return Text(AttributedString(before) + blank + AttributedString(after))
    }

    /// One dot per question: its case color once right, a hollow ring once not, the ring for
    /// the question being asked.
    private var marks: [KasusProgressStrip.Mark] {
        questions.indices.map { i in
            if i < results.count {
                let result = results[i]
                return result.firstTry ? .right(result.kasus) : result.slip ? .slip : .miss
            }
            return i == index ? .current : .upcoming
        }
    }

    /// The first pick counts; the buttons lock after it.
    private func choose(_ option: String, for q: EndingsQuestion, haptics: Bool = true) {
        guard picked == nil else { return }
        let isAnswer = option == q.answer
        picked = option
        picks.append(option)
        results.append(KasusItemResult(kasus: q.kasus, genus: q.gender, firstTry: isAnswer,
                                       slip: !isAnswer && q.isGenderSlip(option),
                                       record: q.roundItem(pick: option)))
        guard haptics else { return }
        // A slip only gets a light tap: it was close, and the header says „Fast“, not wrong.
        if isAnswer { correctCount += 1 } else if q.isGenderSlip(option) { slipCount += 1 } else { wrongCount += 1 }
    }

    /// Once per answered question: a fast double tap on Weiter while it fades out must not skip a
    /// question or record the round twice.
    private func next() {
        guard picked != nil, !isFinished else { return }
        picked = nil
        index += 1
        if isFinished { record() }
    }

    // MARK: Summary

    private var summary: some View {
        let correct = results.filter(\.firstTry).count
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ergebnis · Result")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(correct) of \(results.count)")
                    .font(.largeTitle.weight(.bold))
                Text("right on the first try")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            KasusProgressStrip(marks: marks, showsScore: false)
            ForEach(GrammarCase.allCases) { kasus in
                let rows = results.filter { $0.kasus == kasus }
                if !rows.isEmpty {
                    HStack {
                        CaseLabel(kasus: kasus, style: .name)
                            .frame(width: 130, alignment: .leading)
                        codeText(kasus)
                            .font(.headline.weight(.heavy))
                        Spacer()
                        Text("\(rows.filter(\.firstTry).count) / \(rows.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            if !misses.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Die Fehler · Your misses")
                        .font(.subheadline.weight(.semibold))
                    ForEach(misses, id: \.question.id) { miss in
                        VStack(alignment: .leading, spacing: 6) {
                            sentence(miss.question, picked: miss.pick)
                                .font(.body)
                            Text(kasusRich: miss.question.feedback(pick: miss.pick))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
            Button {
                questions = EndingsQuestion.round(cases: session.cases, emphasis: session.emphasis)
                results = []
                picks = []
                picked = nil
                index = 0
                startedAt = Date()
                prefilled = false
            } label: {
                Text("Noch eine Runde · Again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Fertig", action: onDismiss)
                .frame(maxWidth: .infinity)
        }
    }

    /// The questions missed on the first pick, with that pick.
    private var misses: [(question: EndingsQuestion, pick: String)] {
        zip(questions, picks).filter { $0.1 != $0.0.answer }.map { ($0.0, $0.1) }
    }

    /// Hands the round up for `KasusService.recordRound`: the streak, a `KasusRound` for the
    /// calendar, and the coach's per-case skills (a case needs three answers; Nominativ has none).
    private func record() {
        guard !prefilled else { return }
        onComplete(KasusService.quickResult(
            unit: session.unit,
            items: results,
            durationSeconds: Int(Date().timeIntervalSince(startedAt))
        ))
    }

    // MARK: Setup

    private func setUp() {
        guard !didSetUp else { return }
        didSetUp = true
        #if DEBUG
        applyDebugPrefill()
        #endif
    }

    #if DEBUG
    /// `-kasus.debugAnswers right|mixed` plays the first four questions (mixed gets one in three
    /// wrong), and `-kasus.debugQuickState right|wrong|slip|done` answers the next one that way,
    /// or the whole round for the summary. Never recorded, and no haptics.
    private func applyDebugPrefill() {
        guard let prefill = session.prefill else { return }
        let state = EndingsDebugState.fromLaunchArguments()
        guard prefill.answers != nil || state != nil else { return }
        let answers = prefill.answers ?? .mixed
        prefilled = true
        let played = state == .done ? questions.count : min(4, questions.count - 1)
        // A slip needs a singular question whose family has one; bring one forward.
        if state == .slip,
           let slippable = questions.indices.dropFirst(played).first(where: { Self.debugWrong(questions[$0], slip: true) != nil }) {
            questions.swapAt(played, slippable)
        }
        for i in 0..<played {
            let q = questions[i]
            let wrong = answers == .mixed && i % 3 == 1
            index = i
            choose(wrong ? Self.debugWrong(q, slip: i % 2 == 0) ?? Self.debugWrong(q, slip: false) ?? q.answer : q.answer,
                   for: q, haptics: false)
            picked = nil
        }
        index = played
        guard !isFinished, let state else { return }
        let q = questions[index]
        switch state {
        case .right: choose(q.answer, for: q, haptics: false)
        case .wrong: choose(Self.debugWrong(q, slip: false) ?? q.answer, for: q, haptics: false)
        case .slip:  choose(Self.debugWrong(q, slip: true) ?? Self.debugWrong(q, slip: false) ?? q.answer, for: q, haptics: false)
        case .done:  break
        }
    }

    /// A wrong option: a gender slip, or a case miss.
    private static func debugWrong(_ q: EndingsQuestion, slip: Bool) -> String? {
        q.options.first { $0 != q.answer && q.isGenderSlip($0) == slip }
    }
    #endif
}

#if DEBUG
/// `-kasus.debugQuickState right|wrong|slip|done`, with `-kasus.debugOpen quick:<unit>`: the
/// question the Schnellrunde opens on, answered right, with a case miss or with a gender slip, or
/// the round played through to its summary.
enum EndingsDebugState: String {
    case right, wrong, slip, done

    static func fromLaunchArguments(_ defaults: UserDefaults = .standard) -> EndingsDebugState? {
        defaults.string(forKey: "kasus.debugQuickState").flatMap { EndingsDebugState(rawValue: $0.lowercased()) }
    }
}
#endif

// MARK: - Previews

#Preview("Case endings") {
    NavigationStack { CaseEndingsView() }
        .modelContainer(for: [LearnerProfile.self, StudyDay.self], inMemory: true)
}

#Preview("Case endings · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            NavigationStack { CaseEndingsView() }
                .environment(\.appTheme, theme)
                .tabItem { Text(theme.label) }
        }
    }
    .modelContainer(for: [LearnerProfile.self, StudyDay.self], inMemory: true)
}

#Preview("Schnellrunde · 4 themes") {
    TabView {
        ForEach(AppTheme.allCases) { theme in
            CaseEndingsDrillView(
                session: CaseEndingsSession(unit: .genitiv),
                onComplete: { _ in },
                onDismiss: {}
            )
            .environment(\.appTheme, theme)
            .tabItem { Text(theme.label) }
        }
    }
    .modelContainer(for: [LearnerProfile.self, StudyDay.self], inMemory: true)
}
