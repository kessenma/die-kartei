#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Two courses with entries and handouts, made without typing. The Deutschkurs screens sit two
/// taps into Home and need a course that has content to show anything, and this simulator can't
/// tap. The scenario is the one the feature was designed around: a semester course at a
/// university (dated, by week, with homework) and a private tutor for HR German (undated, with a
/// goal), so both course shapes are on screen at once.
///
/// `-classNotes.debugSeed 1` creates them, `-classNotes.debugOpen <screen>` creates them (if needed)
/// and opens a screen (`hub` or `1`, `course`, `entry`, `editor`, `handout`; see
/// `ClassNotesDebugScreen`), `-classNotes.debugRemove 1` removes them and their files.
enum ClassNotesDebugSeeder {
    static let uniMarker = "[debug] Deutsch A2 an der Uni"
    static let tutorMarker = "[debug] HR-Deutsch mit Anna"

    /// The seeded courses, in the order they were made.
    @MainActor
    static func existing(in context: ModelContext) -> [ClassCourse] {
        let descriptor = FetchDescriptor<ClassCourse>()
        let all = (try? context.fetch(descriptor)) ?? []
        return all.filter { $0.name == uniMarker || $0.name == tutorMarker }
    }

    @discardableResult
    @MainActor
    static func seed(in context: ModelContext) -> String {
        let found = existing(in: context)
        if !found.isEmpty { return "already seeded (\(found.count) courses)" }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: today) ?? today }

        // A semester course, six weeks in, with three logged classes and one open homework.
        let uni = ClassCourse(name: uniMarker, kind: .course)
        uni.teacher = "Frau Müller"
        uni.levelRaw = CEFRLevel.a2.rawValue
        uni.startDate = calendar.date(byAdding: .weekOfYear, value: -6, to: today)
        uni.endDate = calendar.date(byAdding: .weekOfYear, value: 14, to: today)
        uni.sortOrder = 0
        context.insert(uni)

        let week1 = ClassEntry(date: daysAgo(40), title: "Kapitel 1 · Kennenlernen")
        week1.grammarFoci = [.artikel, .modalverben]
        week1.topics = ["Sich vorstellen", "Familie"]
        week1.setWords([
            ClassWord(german: "der Nachbar", english: "neighbour", addedToDeck: true),
            ClassWord(german: "die Schwiegermutter", english: "mother-in-law", addedToDeck: true),
            ClassWord(german: "sich vorstellen", english: "to introduce oneself")
        ])
        week1.notes = "Modalverben: ich kann, du kannst, er kann. Das Verb steht am Ende."
        week1.homework = "Arbeitsbuch S. 12, Übung 1–3"
        week1.homeworkDone = true

        let week5 = ClassEntry(date: daysAgo(10), title: "Kapitel 4 · Wechselpräpositionen")
        week5.grammarFoci = [.wechselpraepositionen, .dativ, .akkusativ]
        week5.topics = ["Wohnen", "Im Zimmer"]
        week5.setWords([
            ClassWord(german: "der Schrank", english: "wardrobe"),
            ClassWord(german: "das Regal", english: "shelf"),
            ClassWord(german: "der Teppich", english: "carpet"),
            ClassWord(german: "hängen", english: "to hang"),
            ClassWord(german: "stellen", english: "to put (upright)"),
            ClassWord(german: "legen")
        ])
        week5.notes = "Wo? + Dativ, wohin? + Akkusativ.\nIch stelle die Lampe auf den Tisch. Die Lampe steht auf dem Tisch."
        week5.homework = "Arbeitsbuch S. 42, Übung 3 und 4"
        week5.homeworkDue = daysAgo(3)

        let thisWeek = ClassEntry(date: daysAgo(1), title: "Kapitel 5 · Perfekt")
        thisWeek.grammarFoci = [.perfekt]
        thisWeek.topics = ["Mein Wochenende"]
        thisWeek.setWords([
            ClassWord(german: "der Ausflug", english: "outing"),
            ClassWord(german: "verbringen", english: "to spend (time)"),
            ClassWord(german: "das Frühstück", english: "breakfast")
        ])
        thisWeek.homework = "Schreib 8 Sätze über dein Wochenende im Perfekt."
        thisWeek.homeworkDue = calendar.date(byAdding: .day, value: 2, to: today)

        for entry in [week1, week5, thisWeek] {
            context.insert(entry)
            entry.course = uni
        }

        // The Grimm story with the teacher's vocab sheet as a deck: the reader's glossary case.
        let sheetRows = VocabListParser.parse(vocabSheetText).rows.filter(\.isComplete)
        let sheetCards: [VocabCard] = sheetRows.map { row in
            let (word, article) = DocumentDeckService.splitArticle(row.german)
            return VocabCard(germanWord: word, englishTranslation: row.english,
                             wordType: article != nil ? "noun" : nil, article: article,
                             exampleSentence: nil, conjugations: nil)
        }
        let sheetDeck = SavedDeck(topic: "Hänsel und Gretel Vokabelliste", wordCount: sheetCards.count,
                                  includeExamples: false, includeGender: true, vocabCards: sheetCards)
        sheetDeck.generatorRaw = "document"
        sheetDeck.courseID = uni.id
        context.insert(sheetDeck)

        let storyEntry = ClassEntry(date: daysAgo(4), title: "Märchen: Hänsel und Gretel")
        storyEntry.grammarFoci = [.praeteritum]
        storyEntry.topics = ["Märchen"]
        context.insert(storyEntry)
        storyEntry.course = uni
        let story = ClassMaterial(title: storyTitle, text: storyText, sourceKind: .pdf)
        story.glossaryDeckID = sheetDeck.id
        context.insert(story)
        story.entry = storyEntry

        let worksheet = ClassMaterial(
            title: "Arbeitsblatt Wechselpräpositionen",
            text: worksheetText,
            sourceKind: .paste
        )
        worksheet.setLookups([
            GlossaryEntry(german: "die Ecke", english: "corner"),
            GlossaryEntry(german: "zwischen", english: "between")
        ])
        context.insert(worksheet)
        worksheet.entry = week5

        // A private tutor, undated, built around a goal, with two sessions and a photographed page.
        let tutor = ClassCourse(name: tutorMarker, kind: .tutor)
        tutor.teacher = "Anna"
        tutor.goal = "HR-Deutsch für Bewerbungen"
        tutor.levelRaw = CEFRLevel.b1.rawValue
        tutor.sortOrder = 1
        context.insert(tutor)

        let session1 = ClassEntry(date: daysAgo(8), title: "Lebenslauf besprechen")
        session1.grammarFoci = [.adjektivendungen]
        session1.topics = ["Lebenslauf", "Berufserfahrung"]
        session1.setWords([
            ClassWord(german: "die Berufserfahrung", english: "professional experience", addedToDeck: true),
            ClassWord(german: "die Kenntnisse", english: "skills, knowledge", addedToDeck: true),
            ClassWord(german: "verhandlungssicher", english: "business fluent")
        ])
        session1.notes = "Tabellarischer Lebenslauf: Stationen rückwärts. Adjektivendungen nach dem bestimmten Artikel wiederholen."

        let session2 = ClassEntry(date: daysAgo(2), title: "Vorstellungsgespräch: Stärken und Schwächen")
        session2.grammarFoci = [.konjunktiv2]
        session2.topics = ["Vorstellungsgespräch"]
        session2.setWords([
            ClassWord(german: "die Stärke", english: "strength"),
            ClassWord(german: "die Schwäche", english: "weakness"),
            ClassWord(german: "belastbar", english: "resilient, able to work under pressure")
        ])
        session2.homework = "Drei Antworten auf „Was sind Ihre Schwächen?“ vorbereiten."

        for entry in [session1, session2] {
            context.insert(entry)
            entry.course = tutor
        }

        let photo = ClassMaterial(
            title: "Photo · Redemittel Vorstellungsgespräch",
            text: photoText,
            sourceKind: .photo
        )
        photo.snapshotFile = ClassMaterialStore.save(placeholderPage(), ext: "jpg")
        context.insert(photo)
        photo.entry = session2

        try? context.save()
        return "seeded 2 courses, 6 entries, 3 handouts, 1 deck"
    }

    /// The screen a `-classNotes.debugOpen` value names, over the seeded data (seeding first).
    @MainActor
    static func screen(named raw: String, in context: ModelContext) -> ClassNotesDebugScreen? {
        _ = seed(in: context)
        let courses = existing(in: context)
        let uni = courses.first { $0.name == uniMarker }
        let tutor = courses.first { $0.name == tutorMarker }
        switch raw.lowercased() {
        case "1", "hub", "true":
            return .hub
        case "course":
            return uni.map { .course($0) }
        case "entry":
            return uni?.sortedEntries.first { $0.title.hasPrefix("Kapitel 4") }.map { .entry($0) }
        case "editor":
            return uni?.sortedEntries.first { $0.title.hasPrefix("Kapitel 4") }.map { .editor($0) }
        case "handout":
            return tutor?.materials.first.map { .handout($0) }
        case "story":
            return uni?.materials.first { $0.title == storyTitle }.map { .handout($0) }
        case "builder":
            return .builder(DocumentDeckDraft(title: "Hänsel und Gretel Vokabelliste", text: vocabSheetText, sourceLabel: "PDF"))
        default:
            return nil
        }
    }

    /// Remove the seeded courses with everything under them, files first.
    @discardableResult
    @MainActor
    static func remove(in context: ModelContext) -> Bool {
        let found = existing(in: context)
        guard !found.isEmpty else { return false }
        for course in found {
            ClassEntryStore.delete(course, context: context)
        }
        try? context.save()
        return true
    }

    // MARK: - Text

    private static let worksheetText = """
    Wechselpräpositionen: an, auf, hinter, in, neben, über, unter, vor, zwischen

    Wo? (Dativ) – Wohin? (Akkusativ)

    1. Die Lampe steht auf dem Tisch. Ich stelle die Lampe auf den Tisch.
    2. Das Bild hängt an der Wand. Ich hänge das Bild an die Wand.
    3. Der Teppich liegt vor dem Sofa. Ich lege den Teppich vor das Sofa.
    4. Der Stuhl steht in der Ecke. Ich stelle den Stuhl in die Ecke.
    5. Das Regal steht zwischen dem Schrank und der Tür.

    Übung: Ergänzen Sie den Artikel.
    Ich stelle die Vase auf ___ Regal. Die Vase steht auf ___ Regal.
    """

    private static let photoText = """
    Redemittel für das Vorstellungsgespräch

    Zu meinen Stärken gehört, dass ich sehr belastbar bin.
    Ich arbeite gern im Team, kann aber auch selbstständig arbeiten.
    Eine Schwäche von mir ist, dass ich manchmal zu genau bin.
    Ich habe drei Jahre Berufserfahrung im Bereich Personal.
    Ich könnte mir gut vorstellen, in Ihrem Unternehmen zu arbeiten.
    """

    static let storyTitle = "Hänsel und Gretel"

    /// The opening of the Grimm story as PDFKit extracts it (one page), the text the vocab sheet
    /// above belongs to.
    static let storyText = """
    Hänsel und Gretel

    Vor einem großen Walde wohnte ein armer Holzhacker mit seiner Frau und seinen zwei Kindern; das Bübchen hieß Hänsel und das Mädchen Gretel. Er hatte wenig zu beißen und zu brechen, und einmal, als große Teuerung ins Land kam, konnte er das tägliche Brot nicht mehr schaffen. Wie er sich nun abends im Bette Gedanken machte und sich vor Sorgen herumwälzte, seufzte er und sprach zu seiner Frau: "Was soll aus uns werden? Wie können wir unsere armen Kinder ernähren da wir für uns selbst nichts mehr haben?" - "Weißt du was, Mann," antwortete die Frau, "wir wollen morgen in aller Frühe die Kinder hinaus in den Wald führen, wo er am dicksten ist. Da machen wir ihnen ein Feuer an und geben jedem noch ein Stückchen Brot, dann gehen wir an unsere Arbeit und lassen sie allein. Sie finden den Weg nicht wieder nach Haus, und wir sind sie los." - "Nein, Frau," sagte der Mann, "das tue ich nicht; wie sollt ich's übers Herz bringen, meine Kinder im Walde allein zu lassen! Die wilden Tiere würden bald kommen und sie zerreißen." - "Oh, du Narr," sagte sie, "dann müssen wir alle viere Hungers sterben, du kannst nur die Bretter für die Särge hobeln," und ließ ihm keine Ruhe, bis er einwilligte. "Aber die armen Kinder dauern mich doch," sagte der Mann.

    Die zwei Kinder hatten vor Hunger auch nicht einschlafen können und hatten gehört, was die Stiefmutter zum Vater gesagt hatte. Gretel weinte bittere Tränen und sprach zu Hänsel: "Nun ist's um uns geschehen." - "Still, Gretel," sprach Hänsel, "gräme dich nicht, ich will uns schon helfen." Und als die Alten eingeschlafen waren, stand er auf, zog sein Röcklein an, machte die Untertüre auf und schlich sich hinaus. Da schien der Mond ganz hell, und die weißen Kieselsteine, die vor dem Haus lagen, glänzten wie lauter Batzen. Hänsel bückte sich und steckte so viele in sein Rocktäschlein, als nur hinein wollten. Dann ging er wieder zurück, sprach zu Gretel: "Sei getrost, liebes Schwesterchen, und schlaf nur ruhig ein, Gott wird uns nicht verlassen," und legte sich wieder in sein Bett.

    Als der Tag anbrach, noch ehe die Sonne aufgegangen war, kam schon die Frau und weckte die beiden Kinder: "Steht auf, ihr Faulenzer, wir wollen in den Wald gehen und Holz holen." Dann gab sie jedem ein Stückchen Brot und sprach: "Da habt ihr etwas für den Mittag, aber eßt's nicht vorher auf, weiter kriegt ihr nichts." Gretel nahm das Brot unter die Schürze, weil Hänsel die Steine in der Tasche hatte. Danach machten sie sich alle zusammen auf den Weg nach dem Wald.

    Als sie mitten in den Wald gekommen waren, sprach der Vater: "Nun sammelt Holz, ihr Kinder, ich will ein Feuer anmachen, damit ihr nicht friert." Hänsel und Gretel trugen Reisig zusammen, einen kleinen Berg hoch. Das Reisig ward angezündet, und als die Flamme recht hoch brannte, sagte die Frau: "Nun legt euch ans Feuer, ihr Kinder, und ruht euch aus, wir gehen in den Wald und hauen Holz. Wenn wir fertig sind, kommen wir wieder und holen euch ab." Hänsel und Gretel saßen um das Feuer, und als der Mittag kam, aß jedes sein Stücklein Brot. Und als sie so lange gesessen hatten, fielen ihnen die Augen vor Müdigkeit zu, und sie schliefen fest ein. Als sie endlich erwachten, war es schon finstere Nacht. Gretel fing an zu weinen, aber Hänsel tröstete sie: "Wart nur ein Weilchen, bis der Mond aufgegangen ist, dann wollen wir den Weg schon finden."
    """

    /// A teacher's vocabulary sheet exactly as PDFKit extracts it (one row per line, the columns
    /// separated by a space, wrapped cells, ✓ on the quiz words), for the flashcard builder.
    static let vocabSheetText = """
    Vokabelliste für “Hänsel und Gretel”
    Deutsch English Study for
    Quiz?
    der Holzhacker lumberjack ✓
    das Bübchen old expression: young boy
    große Teuerung old expression: price increase
    das tägliche Brot nicht mehr schaffen old expression: not being able to provide bread
    anymore/ not being able to feed the family anymore
    die Sorge/ die Sorgen (pl) worry ✓
    ernähren to feed ✓
    in aller Frühe in the early morning ✓
    zerreißen to rip into pieces ✓
    der Narr old expression: idiot/ naïve person
    “Nun ist’s um uns geschehen” “Now we are finished/ now we will die”
    gräme dich nicht old expression: do not worry
    der Kieselstein/ die Kieselsteine (pl) pebble stone ✓
    die Batzen old expression: pieces of gold
    das Reisig bundle of sticks
    anzünden/ zündete…an/ hat
    angezündet to ignite ✓
    sich ausruhen -> ruht euch aus ruhte
    sich…. aus/ hat sich ausgeruht to rest -> get some rest ✓
    der Vorwurf/ die Vorwürfe (pl) accusation ✓
    trösten to comfort ✓
    das Bröcklein crumble
    “Da wollen wir uns dranmachen” “Let’s get to it!” (in context: let us eat the cabin)
    herausschleichen/ schlich…heraus/ ist
    herausgeschlichen to sneak out ✓
    die Witterung scent
    der Bissen the bite
    einsperren/ sperrte...ein/ hat
    eingesperrt to lock someone up ✓
    bitterlich bitterly ✓
    trüb dull ✓
    jammern to moan ✓
    “Spar nur dein Geplärre” “Safe your annoying crying”
    erlöst redeemed/ saved ✓
    der Käfig/ die Käfige (pl) cage ✓
    der Edelstein/ die Edelsteine (pl) gemstone ✓
    hinüberbringen/ brachte…hinüber/ hat
    hinüber gebracht here: to transport (to help across the water) ✓
    """

    // MARK: - Drawing

    /// A page-shaped stand-in for a photographed handout, so "Open the original" has a file.
    private static func placeholderPage() -> Data {
        let size = CGSize(width: 1240, height: 1754)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 14
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .regular),
                .foregroundColor: UIColor(white: 0.15, alpha: 1),
                .paragraphStyle: paragraph
            ]
            (photoText as NSString).draw(in: CGRect(x: 110, y: 140, width: size.width - 220, height: size.height - 280),
                                         withAttributes: attributes)
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }
}

// MARK: - Screens

/// What `-classNotes.debugOpen <screen>` presents, in a sheet with a Close button.
enum ClassNotesDebugScreen: Identifiable {
    case hub
    case course(ClassCourse)
    case entry(ClassEntry)
    case editor(ClassEntry)
    case handout(ClassMaterial)
    case builder(DocumentDeckDraft)

    var id: String {
        switch self {
        case .hub: "hub"
        case .course(let course): "course-\(course.id)"
        case .entry(let entry): "entry-\(entry.id)"
        case .editor(let entry): "editor-\(entry.id)"
        case .handout(let material): "handout-\(material.id)"
        case .builder(let draft): "builder-\(draft.id)"
        }
    }
}

struct ClassNotesDebugScreenView: View {
    let screen: ClassNotesDebugScreen
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    var body: some View {
        switch screen {
        case .hub:
            ClassNotesHubView(modelManager: modelManager, mlxService: mlxService)
        case .course(let course):
            ClassCourseDetailView(course: course, modelManager: modelManager, mlxService: mlxService)
        case .entry(let entry):
            ClassEntryDetailView(entry: entry, modelManager: modelManager, mlxService: mlxService)
        case .editor(let entry):
            ClassEntryEditorView(entry: entry, course: entry.course)
        case .handout(let material):
            ClassMaterialDetailView(material: material, modelManager: modelManager, mlxService: mlxService)
        case .builder(let draft):
            DocumentDeckBuilderView(draft: draft, modelManager: modelManager, mlxService: mlxService) { _ in }
        }
    }
}
#endif
