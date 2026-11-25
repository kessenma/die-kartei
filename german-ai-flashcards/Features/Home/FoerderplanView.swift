//
//  FoerderplanView.swift
//  german-ai-flashcards
//
//  The Förderplan screen (roadmap item 9, `FoerderplanService`): the written plan, ten days, today's
//  task, and past plans with how far each weak spot moved. Started from Coach's Notes; Today shows
//  the day's task while a plan runs.
//

import SwiftData
import SwiftUI

struct FoerderplanView: View {
    @Bindable var modelManager: MLXModelManager

    @Environment(\.modelContext) private var modelContext
    @Environment(ActivityRouter.self) private var router

    @State private var record = FoerderplanRecord()
    @State private var lessonFocus: GrammarFocus?

    var body: some View {
        List {
            if let plan = record.current, let focus = plan.focus {
                let written = FoerderplanService.writtenPlan(for: focus)
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(focus.germanLabel).font(.title2.weight(.bold))
                        Text(written.deficiency).font(.callout)
                        ForEach(written.actions, id: \.self) { Label($0, systemImage: "checkmark.circle").font(.callout) }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Förderplan · Your ten days").themedSectionHeader()
                }
                .themedListRow()

                Section {
                    HStack(spacing: 6) {
                        ForEach(1...Foerderplan.length, id: \.self) { day in
                            Circle()
                                .fill(day <= plan.doneDays.count ? Color.accentColor : Color.primary.opacity(0.1))
                                .frame(width: 22, height: 22)
                                .overlay(Text("\(day)").font(.caption2.weight(.semibold))
                                    .foregroundStyle(day <= plan.doneDays.count ? .white : .secondary))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(plan.doneDays.count) of \(Foerderplan.length) days done")

                    let task = Foerderplan.task(day: plan.dayNumber)
                    if plan.doneToday() {
                        Label("Today's task is done. See you tomorrow.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            runToday(focus: focus, withLesson: task.withLesson)
                        } label: {
                            Label("Tag \(plan.dayNumber): \(task.title)", systemImage: "play.fill")
                        }
                    }
                } header: {
                    Text("Heute · Today").themedSectionHeader()
                } footer: {
                    Text("A day counts when you start its task. The rounds count toward your grammar like any other practice; the re-check on day 10 only reads the coach's score.")
                }
                .themedListRow()

                Section {
                    Button("Stop this plan", role: .destructive) {
                        FoerderplanService.stop(in: modelContext)
                        reload()
                    }
                }
                .themedListRow()
            } else {
                Section {
                    Text("No plan running. Start one from Coach's Notes on a grammar point that keeps slipping.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .themedListRow()
            }

            if !record.history.isEmpty {
                Section {
                    ForEach(record.history.reversed()) { outcome in
                        HStack {
                            Text(outcome.focus?.germanLabel ?? outcome.focusRaw)
                            Spacer()
                            Text(String(format: "%.2f → %.2f", outcome.startStruggle, outcome.endStruggle))
                                .monospacedDigit()
                                .foregroundStyle(outcome.moved > 0 ? .green : .secondary)
                        }
                    }
                } header: {
                    Text("Frühere Pläne · Past plans").themedSectionHeader()
                } footer: {
                    Text("The coach's struggle score at the start and at the end (0 solid, 1 shaky).")
                }
                .themedListRow()
            }
        }
        .themedListScreen()
        .navigationTitle("Förderplan")
        .onAppear(perform: reload)
        .sheet(item: $lessonFocus, onDismiss: reload) { focus in
            GrammarLessonSheet(focus: focus)
        }
    }

    private func reload() { record = FoerderplanService.record(in: modelContext) }

    private func runToday(focus: GrammarFocus, withLesson: Bool) {
        FoerderplanService.markTodayDone(in: modelContext)
        reload()
        if withLesson {
            lessonFocus = focus
            return
        }
        switch GrammarRoute(focus).resolve(in: modelContext, level: modelManager.germanLevel) {
        case .launch(let activity): router.launch(activity)
        case .lesson(let f): lessonFocus = f
        case .prepositionHub: lessonFocus = focus
        }
    }
}

/// "Ten-day plan" on a shaky grammar row in Coach's Notes.
struct StartFoerderplanButton: View {
    let focus: GrammarFocus
    @Environment(\.modelContext) private var modelContext
    @State private var confirm = false

    var body: some View {
        Button {
            confirm = true
        } label: {
            Label("Ten-day plan", systemImage: "calendar.badge.plus")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .confirmationDialog("Ten days on \(focus.germanLabel)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Start the Förderplan") { FoerderplanService.start(focus, in: modelContext) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("One short task a day, on Today. A plan already running is replaced.")
        }
    }
}
