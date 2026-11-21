//
//  TeacherReportView.swift
//  german-ai-flashcards
//
//  Bericht für die Lehrerin (roadmap item 15, DLI-TI: feedback in writing that names the
//  deficiencies and the actions). One page per course since the last session: time practised, words
//  learned, words that keep failing, weak grammar with two real examples each, homework, the open
//  questions. The learner reads and edits it before sharing; nothing is sent automatically.
//

import CoreText
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum TeacherReportBuilder {

    /// The last session before today: by the schedule, else the newest entry before today, else a week.
    static func since(for course: ClassCourse, now: Date = .now) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        if let scheduled = ClassSchedule.previousSessionDay(weekdaysRaw: course.meetingWeekdaysRaw, from: now) {
            return scheduled
        }
        if let last = course.entries.map(\.date).filter({ $0 < today }).max() { return last }
        return cal.date(byAdding: .day, value: -7, to: today) ?? today
    }

    static func build(course: ClassCourse, context: ModelContext, now: Date = .now) -> String {
        let since = since(for: course, now: now)
        // German dates: the report is written for a German teacher.
        let sinceLabel = since.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_DE")))
        var lines: [String] = []
        let teacher = course.teacher?.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("Bericht\(teacher.map { $0.isEmpty ? "" : " für \($0)" } ?? "") · \(course.name)")
        lines.append("Seit dem \(sinceLabel)")
        lines.append("")

        // Time practised.
        let days = ((try? context.fetch(FetchDescriptor<StudyDay>(predicate: #Predicate { $0.dayStart >= since }))) ?? [])
            .filter(\.hasActivity)
        let seconds = days.reduce(0) { $0 + $1.totalSeconds }
        lines.append("Geübt: \(seconds / 3600) Std. \(seconds % 3600 / 60) Min. an \(days.count) Tag\(days.count == 1 ? "" : "en")")

        // The course deck.
        let deckID = course.deckID
        let cards: [SavedCard] = deckID.flatMap { id in
            var d = FetchDescriptor<SavedDeck>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            return (try? context.fetch(d))?.first?.cards
        } ?? []
        let learned = cards.filter { ($0.firstReviewedAt ?? .distantPast) >= since }.count
        lines.append("Neue Wörter aus dem Kurs geübt: \(learned)")
        let failing = cards.filter { $0.lapses >= 2 || $0.lastReviewWasCorrect == false }
            .sorted { $0.lapses > $1.lapses }
            .prefix(8)
            .map { card in [card.article, card.germanWord].compactMap { $0 }.joined(separator: " ") }
        if !failing.isEmpty {
            lines.append("Wörter, die immer wieder falsch sind: " + failing.joined(separator: ", "))
        }
        lines.append("")

        // Weak grammar with real examples from the coach's memory.
        let profile = (try? context.fetch(FetchDescriptor<LearnerProfile>()))?.first
        let weak = (profile?.grammar ?? [:])
            .compactMap { key, skill -> (GrammarFocus, GrammarSkill)? in
                guard skill.struggle >= GrammarSkill.shakyThreshold, let f = GrammarFocus(rawValue: key) else { return nil }
                return (f, skill)
            }
            .sorted { $0.1.struggle > $1.1.struggle }
            .prefix(3)
        if !weak.isEmpty {
            lines.append("Grammatik, die noch wackelt:")
            for (focus, skill) in weak {
                lines.append("• \(focus.germanLabel)")
                for sample in skill.samples.prefix(2) { lines.append("   \(sample)") }
            }
            lines.append("")
        }

        // Teacher-confirmed corrections since the last session.
        let corrections = course.entries.filter { $0.date >= since }.flatMap(\.teacherCorrections)
        if !corrections.isEmpty {
            lines.append("Ihre Korrekturen, die ich übe: " + corrections.prefix(5).map { "„\($0.better)“" }.joined(separator: ", "))
            lines.append("")
        }

        // Homework.
        let homework = course.entries.filter { $0.hasHomework && ($0.date >= since || !$0.homeworkDone) }
        if !homework.isEmpty {
            lines.append("Hausaufgaben:")
            for entry in homework.sorted(by: { $0.date < $1.date }) {
                lines.append("• \(entry.homework.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) · \(entry.homeworkDone ? "erledigt" : "offen")")
            }
            lines.append("")
        }

        // Open questions.
        let questions = course.openQuestions
        if !questions.isEmpty {
            lines.append("Meine Fragen:")
            for (i, q) in questions.enumerated() { lines.append("\(i + 1). \(q.text)") }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A plain A4 PDF of the report text, drawn with Core Text so it renders the same on iOS and Mac.
nonisolated enum TeacherReportPDF {
    static func data(_ text: String) -> Data? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 56
        let out = NSMutableData()
        var box = page
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        let font = CTFontCreateWithName("Helvetica" as CFString, 11.5, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var start = 0
        let length = attributed.length
        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: page.insetBy(dx: margin, dy: margin), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            guard visible.length > 0 else { break }
            start += visible.length
        } while start < length
        ctx.closePDF()
        return out as Data
    }
}

/// The report as a shareable PDF file.
struct TeacherReportDocument: Transferable {
    let text: String
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { doc in
            TeacherReportPDF.data(doc.text) ?? Data()
        }
        .suggestedFileName { $0.fileName }
    }
}

struct TeacherReportView: View {
    @Bindable var course: ClassCourse

    @Environment(\.modelContext) private var modelContext
    @State private var text = ""

    var body: some View {
        List {
            Section {
                TextEditor(text: $text)
                    .font(.callout)
                    .frame(minHeight: 360)
            } header: {
                Text("Bericht · Your report").themedSectionHeader()
            } footer: {
                Text("Built from what the app saw since your last session. Read it, change anything, then share it. Nothing is sent for you.")
            }
            .themedListRow()

            Section {
                ShareLink(item: TeacherReportDocument(text: text, fileName: "Bericht \(course.name).pdf"),
                          preview: SharePreview("Bericht · \(course.name)")) {
                    Label("Share as PDF", systemImage: "doc.richtext")
                }
                ShareLink(item: text) {
                    Label("Share as text", systemImage: "square.and.arrow.up")
                }
                Button {
                    text = TeacherReportBuilder.build(course: course, context: modelContext)
                } label: {
                    Label("Start over from the data", systemImage: "arrow.counterclockwise")
                }
            }
            .themedListRow()
        }
        .themedListScreen()
        .navigationTitle("Bericht für die Lehrerin")
        .onAppear {
            if text.isEmpty { text = TeacherReportBuilder.build(course: course, context: modelContext) }
        }
    }
}
