import SwiftUI
import SwiftData

/// "Reading progress" — what story study has actually added up to. Read-only, computed straight
/// from the `StoryReadingSession` / `StoryQuizAttempt` rows via `StoryProgressService`, so it
/// stays in step with the streak calendar (both read the same events).
struct StoryProgressView: View {
    @Query(sort: \StoryReadingSession.date, order: .reverse) private var sessions: [StoryReadingSession]
    @Query(sort: \StoryQuizAttempt.date, order: .reverse) private var attempts: [StoryQuizAttempt]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private var summary: StoryProgressService.Summary {
        StoryProgressService.summary(sessions: sessions, attempts: attempts)
    }

    private var levels: [StoryProgressService.LevelSlice] {
        StoryProgressService.levelSlices(sessions: sessions, attempts: attempts)
    }

    var body: some View {
        Group {
            if summary.hasAnything {
                List {
                    timeSection
                    comprehensionSection
                    levelSection
                    recentSection
                }
            } else {
                ContentUnavailableView(
                    "No story study yet",
                    systemImage: "book.pages",
                    description: Text("Read or listen to a story and your time, questions, and accuracy show up here.")
                )
            }
        }
        .navigationTitle("Reading Progress")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var timeSection: some View {
        let s = summary
        return Section {
            statRow("Time with stories", StoryProgressService.formatShort(s.totalSeconds), icon: "timer")
            statRow("Stories read", "\(s.storiesRead)", icon: "book.pages")
            statRow("Sessions", "\(s.sessionCount)", icon: "clock.arrow.circlepath")
            statRow("Longest sitting", StoryProgressService.formatShort(s.longestSessionSeconds), icon: "hourglass")
            if s.totalSeconds > 0 {
                statRow("Listening", "\(Int((s.listeningShare * 100).rounded()))% of your time", icon: "ear")
            }
            if s.dayStreak > 0 {
                statRow("Story streak", "\(s.dayStreak) day\(s.dayStreak == 1 ? "" : "s")", icon: "flame.fill", tint: .orange)
            }
        } header: {
            Text("Time")
        } footer: {
            Text("Days with any story activity: \(s.activeDays). Reading time is measured only while a story is open and the app is in front.")
                .font(.caption2)
        }
    }

    private var comprehensionSection: some View {
        let s = summary
        return Section {
            if s.quizCount == 0 {
                Text("No questions answered yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                statRow("Questions answered", "\(s.questionsAnswered)", icon: "checklist")
                statRow("Correct", "\(s.questionsCorrect) · \(s.accuracy)%", icon: "checkmark.seal")
                statRow("Quizzes finished", "\(s.quizCount)", icon: "flag.checkered")
                if s.perfectQuizzes > 0 {
                    statRow("Perfect runs", "\(s.perfectQuizzes)", icon: "star.fill", tint: .yellow)
                }
                if s.listeningQuizCount > 0 {
                    statRow("Answered from listening", "\(s.listeningQuizCount)", icon: "ear")
                }
            }
            if s.lookups > 0 || s.wordsSaved > 0 {
                statRow("Words looked up", "\(s.lookups)", icon: "character.book.closed")
                statRow("Words saved", "\(s.wordsSaved)", icon: "tray.and.arrow.down")
            }
        } header: {
            Text("Comprehension")
        } footer: {
            Text("Words you save while reading — and the fixes on written answers — flow into the coach's memory when that hand-off is on.")
                .font(.caption2)
        }
    }

    @ViewBuilder
    private var levelSection: some View {
        if levels.count > 1 || (levels.first?.questionsAnswered ?? 0) > 0 {
            Section("By level") {
                ForEach(levels) { slice in
                    HStack(spacing: 12) {
                        CEFRLevelChip(level: slice.level)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(StoryProgressService.formatShort(slice.seconds))
                                .font(.subheadline)
                            if slice.questionsAnswered > 0 {
                                Text("\(slice.questionsAnswered) questions · \(slice.accuracy)% correct")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !sessions.isEmpty {
            Section("Recent sessions") {
                ForEach(sessions.prefix(15)) { session in
                    HStack(spacing: 12) {
                        Image(systemName: session.wasListening ? "ear" : "book.pages")
                            .foregroundStyle(.pink)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.storyTitle)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(Self.dateFormatter.string(from: session.date) + " · " + session.formattedDuration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        CEFRLevelChip(level: session.level)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func statRow(_ title: String, _ value: String, icon: String, tint: Color = .pink) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
