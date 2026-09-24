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
//  (`.caseEndings`); this screen is the reference only.
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
    var body: some View {
        List {
            Section {
                CaseEndingsTable()
                    .padding(.vertical, 6)
            } footer: {
                Text("The last letter of each article spells the code on the left. The noun itself changes in two places: + n in the dative plural, + s on masculine and neuter in the genitive.")
            }
            .themedListRow()

            questionSection
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
    }

    private var questionSection: some View {
        Section {
            ForEach(GrammarCase.allCases) { kasus in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: kasus.symbol)
                        .foregroundStyle(kasus.color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(kasus.name) · \(kasus.role)")
                            .font(.subheadline.weight(.medium))
                        Text(kasus.question)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
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
                Text("Who gives? The man. To whom? The child. Gives what? A ball.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Ask the question")
                .themedSectionHeader()
        }
    }

    private func caseChip(_ kasus: GrammarCase, _ phrase: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            CaseLabel(kasus: kasus)
                .font(.caption2.weight(.semibold))
            Text(phrase)
                .font(.caption)
        }
    }

    private var einWordSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("ein, mein, dein, kein and friends take the same code letters as the article: den → einen, dem → einem, der → einer.")
                    .font(.subheadline)
                Text("Three spots have no ending at all: masculine Nominativ and neuter Nominativ/Akkusativ.")
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
                Text("Plurals that already end in -n or -s stay as they are: mit den Frauen, mit den Autos.")
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
                Text("Masculine and neuter nouns add -s (short words often -es). Feminine and plural nouns don't change. In everyday speech „von dem Mann“ often replaces it; writing and exams expect the Genitiv.")
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
/// (preposition, another noun, subject, sein, receiver or Dativ verb, otherwise Akkusativ).
struct EndingsFrame {
    let kasus: GrammarCase
    let singular: String
    let plural: String
    let why: String

    static let all: [EndingsFrame] = [
        .init(kasus: .nominativ, singular: "Das ist ___ {N}.", plural: "Das sind ___ {N}.", why: "„sein“ links it back to the subject, so it stays Nominativ"),
        .init(kasus: .nominativ, singular: "Hier kommt ___ {N}.", plural: "Hier kommen ___ {N}.", why: "It's the subject of „kommen“, so Nominativ"),
        .init(kasus: .akkusativ, singular: "Ich sehe ___ {N}.", plural: "Ich sehe ___ {N}.", why: "It's what „sehen“ acts on: the direct object, so Akkusativ"),
        .init(kasus: .akkusativ, singular: "Kennst du ___ {N}?", plural: "Kennst du ___ {N}?", why: "It's what „kennen“ acts on: the direct object, so Akkusativ"),
        .init(kasus: .akkusativ, singular: "Wir besuchen ___ {N}.", plural: "Wir besuchen ___ {N}.", why: "It's what „besuchen“ acts on, so Akkusativ. „besuchen“ can feel like it has a receiver, but it takes the Akkusativ"),
        .init(kasus: .dativ, singular: "Ich helfe ___ {N}.", plural: "Ich helfe ___ {N}.", why: "„helfen“ is one of the verbs that always take the Dativ"),
        .init(kasus: .dativ, singular: "Wir sprechen mit ___ {N}.", plural: "Wir sprechen mit ___ {N}.", why: "„mit“ always takes the Dativ"),
        .init(kasus: .dativ, singular: "Das Buch gehört ___ {N}.", plural: "Das Buch gehört ___ {N}.", why: "„gehören“ takes the Dativ: the thing owned is the subject, the owner is Dativ"),
        .init(kasus: .genitiv, singular: "Das ist der Name ___ {N}.", plural: "Das sind die Namen ___ {N}.", why: "It hangs on another noun (der Name), so Genitiv"),
        .init(kasus: .genitiv, singular: "Wegen ___ {N} bleiben wir zu Hause.", plural: "Wegen ___ {N} bleiben wir zu Hause.", why: "„wegen“ takes the Genitiv"),
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

    var explanation: String {
        let ending = kasus.einEnding(gender)
        var text = "\(frame.why). "
        if determiner != .definite && ending.isEmpty {
            text += "\(gender.genderName.capitalized) \(kasus.name) is one of the spots with no ending: \(answer)."
        } else {
            let letter = kasus.article(gender).suffix(1)
            text += "\(gender.genderName.capitalized) in „\(kasus.code)“ is \(letter): \(answer)."
        }
        if isPlural && kasus == .dativ && noun.dativePlural != noun.plural {
            text += " The noun adds -n too: \(noun.dativePlural)."
        }
        if !isPlural && kasus == .genitiv && noun.genitive != noun.singular {
            text += " The noun adds -\(noun.genitive.dropFirst(noun.singular.count)) too: \(noun.genitive)."
        }
        return text
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

    /// The unit's cases in play, weighted toward its own case (Alle Fälle spreads evenly).
    init(unit: KasusUnit) {
        self.unit = unit
        cases = unit.casesInPlay
        emphasis = unit.focusCase
        title = "Schnellrunde · \(unit.germanTitle)"
    }
}

struct CaseEndingsDrillView: View {
    let session: CaseEndingsSession
    /// Called once per finished round; `ContentView` hands it to `KasusService.recordRound`.
    var onComplete: (KasusRoundResult) -> Void
    var onDismiss: () -> Void

    @Environment(\.appTheme) private var appTheme

    @State private var questions: [EndingsQuestion]
    @State private var index = 0
    @State private var picked: String?
    @State private var results: [KasusItemResult] = []
    @State private var startedAt = Date()

    init(session: CaseEndingsSession, onComplete: @escaping (KasusRoundResult) -> Void,
         onDismiss: @escaping () -> Void) {
        self.session = session
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        _questions = State(initialValue: EndingsQuestion.round(cases: session.cases, emphasis: session.emphasis))
    }

    private var isFinished: Bool { index >= questions.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isFinished {
                        summary
                    } else {
                        questionCard(questions[index])
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
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
        // Presented from the root cover, outside any themed stack, so it sets its own tint.
        .tint(appTheme.accent(model: nil))
    }

    // MARK: Question

    private func questionCard(_ q: EndingsQuestion) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView(value: Double(index), total: Double(questions.count))
            Text("\(index + 1) of \(questions.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            nounHeader(q)
                .font(.subheadline)

            sentence(q)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(q.options, id: \.self) { option in
                    optionButton(option, question: q)
                }
            }

            if picked != nil {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        CaseLabel(kasus: q.kasus, style: .name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: picked == q.answer ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(picked == q.answer ? AnyShapeStyle(q.kasus.color) : AnyShapeStyle(.secondary))
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text(q.explanation)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        picked = nil
                        index += 1
                        if isFinished { record() }
                    } label: {
                        Text(index + 1 == questions.count ? "See results" : "Weiter")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .themedCard()
            }
        }
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

    private func sentence(_ q: EndingsQuestion) -> Text {
        let (before, after) = q.parts
        var blank: AttributedString
        if let picked {
            blank = AttributedString(q.answer)
            blank.foregroundColor = q.gender.color
            blank.underlineStyle = .single
            if picked != q.answer {
                var wrong = AttributedString(picked + " ")
                wrong.strikethroughStyle = .single
                wrong.foregroundColor = .secondary
                blank = wrong + blank
            }
        } else {
            blank = AttributedString("____")
            blank.foregroundColor = .secondary
        }
        return Text(AttributedString(before) + blank + AttributedString(after))
    }

    private func optionButton(_ option: String, question q: EndingsQuestion) -> some View {
        let isAnswer = option == q.answer
        let tint: Color? = {
            guard let picked else { return nil }
            if isAnswer { return q.kasus.color }
            if option == picked { return .gray }
            return nil
        }()
        return Button {
            guard picked == nil else { return }
            picked = option
            results.append(KasusItemResult(kasus: q.kasus, genus: q.gender, firstTry: isAnswer,
                                           slip: !isAnswer && q.isGenderSlip(option)))
        } label: {
            Text(option)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .disabled(picked != nil && tint == nil)
    }

    // MARK: Summary

    private var summary: some View {
        let correct = results.filter(\.firstTry).count
        return VStack(alignment: .leading, spacing: 18) {
            Text("\(correct) of \(results.count)")
                .font(.largeTitle.weight(.bold))
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
            Button {
                questions = EndingsQuestion.round(cases: session.cases, emphasis: session.emphasis)
                results = []
                index = 0
                startedAt = Date()
            } label: {
                Text("Noch eine Runde · Again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button("Done", action: onDismiss)
                .frame(maxWidth: .infinity)
        }
    }

    /// Hands the round up for `KasusService.recordRound`: the streak, a `KasusRound` for the
    /// calendar, and the coach's per-case skills (a case needs three answers; Nominativ has none).
    private func record() {
        onComplete(KasusService.quickResult(
            unit: session.unit,
            items: results,
            durationSeconds: Int(Date().timeIntervalSince(startedAt))
        ))
    }
}

// MARK: - Previews

#Preview("Case endings") {
    NavigationStack { CaseEndingsView() }
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
