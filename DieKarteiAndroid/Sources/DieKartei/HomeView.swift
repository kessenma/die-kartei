@testable import DieKarteiCore
import SwiftUI

/// The Home tab: what's due today, then the activities, the way the iOS Home hub lists its
/// categories. Only the categories Android has today are here; names, blurbs and colours follow
/// iOS's `ActivityCategory` and `HoerenTile`.
struct HomeView: View {
    /// Grammar has its own tab, so its row brings that tab forward instead of pushing a copy
    /// (what the iOS Home tile does too).
    let openGrammar: () -> Void

    @AppStorage("level") var levelRaw = GoetheLevel.a1.rawValue
    @State var store = StudyStore.shared
    @State var log = StudyLog.shared

    var level: GoetheLevel { GoetheLevel(rawValue: levelRaw) ?? .a1 }

    var body: some View {
        List {
            Section {
                NavigationLink { KartenView() } label: {
                    todayRow
                }
            } header: {
                HStack {
                    Text("Today")
                    Spacer()
                    if log.streak > 0 {
                        Label("\(log.streak)", systemImage: "flame.fill")
                            .foregroundStyle(Color.orange)
                    }
                }
            }
            Section("Activities") {
                NavigationLink { VocabularyView() } label: {
                    ActivityRow(title: "Vocabulary", subtitle: "Flashcards, Wortschatz",
                                systemImage: "rectangle.stack.fill", tint: Color.blue)
                }
                Button(action: openGrammar) {
                    ActivityRow(title: "Grammar", subtitle: "Die vier Fälle · der · die · das · Präpositionen",
                                systemImage: "checklist", tint: Color.purple)
                }
                .buttonStyle(.plain)
                NavigationLink { HoerenView() } label: {
                    ActivityRow(title: "Hören", subtitle: "Zahlen-Diktat with the German voice",
                                systemImage: "ear.badge.waveform", tint: Color.orange)
                }
                NavigationLink { SpieleView() } label: {
                    ActivityRow(title: "Spiele", subtitle: "Galgenmännchen · Wortsuche",
                                systemImage: "gamecontroller.fill", tint: Color.teal)
                }
            }
            Section("Tutor") {
                NavigationLink { GespraechView() } label: {
                    ActivityRow(title: "Gespräch", subtitle: "Talk with the tutor; every line gets corrected",
                                systemImage: "bubble.left.and.bubble.right.fill", tint: Color.green)
                }
                NavigationLink { SatzPruefenView() } label: {
                    ActivityRow(title: "Satz prüfen", subtitle: "One sentence, checked by the tutor",
                                systemImage: "checkmark.bubble", tint: Color.green)
                }
            }
        }
        .navigationTitle("Home")
    }

    var todayRow: some View {
        // What the next session would hold, so the numbers match what Karteikarten opens with.
        let plan = store.plan(for: level)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Karteikarten · Goethe \(level.rawValue)")
                .font(.headline)
            Text("\(plan.due.count) fällig · \(plan.fresh.count) neu")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// One activity: its icon on a tinted tile, title and a line on what's inside.
struct ActivityRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// Home ▸ Vocabulary: the category page with its tools, as on iOS.
struct VocabularyView: View {
    var body: some View {
        List {
            NavigationLink { KartenView() } label: {
                ActivityRow(title: "Karteikarten", subtitle: "The Goethe deck with spaced repetition",
                            systemImage: "rectangle.stack", tint: Color.blue)
            }
            NavigationLink { WortschatzView() } label: {
                ActivityRow(title: "Wortschatz", subtitle: "The A1–B1 word lists, searchable",
                            systemImage: "archivebox", tint: Color.blue)
            }
        }
        .navigationTitle("Vocabulary")
    }
}
