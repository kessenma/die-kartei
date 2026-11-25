//
//  ClassNotesGuideSection.swift
//  german-ai-flashcards
//
//  "Erste Schritte · Getting started": the checklist at the top of the Deutschkurs hub after the
//  intro. Each step ticks itself off from the learner's data (`ClassNotesGuide.isDone`); an open
//  step is a button that takes them to where it's done. ✕ hides the list, the ? menu's tour brings
//  it back. Done-state arrives as a `Snapshot` the hub fetched, never computed here in `body`.
//

import SwiftUI

struct ClassNotesGuideSection: View {
    let items: [ClassNotesGuide.Item]
    let snapshot: ClassNotesGuide.Snapshot
    let kind: ClassCourse.Kind
    var onShowMe: (ClassNotesGuide.Item) -> Void
    var onHide: () -> Void

    private var doneCount: Int { items.filter { ClassNotesGuide.isDone($0, in: snapshot) }.count }
    private var allDone: Bool { doneCount == items.count }
    /// The first open step: it gets its explanation and the "Show me" label.
    private var next: ClassNotesGuide.Item? { items.first { !ClassNotesGuide.isDone($0, in: snapshot) } }

    var body: some View {
        Section {
            if allDone {
                allDoneRow
            } else {
                ForEach(items) { item in
                    row(item)
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text("Erste Schritte · Getting started").themedSectionHeader()
                Spacer()
                Text("\(doneCount) of \(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                Button(action: onHide) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.secondary)
                }
                // Plain, not borderless: a borderless button tints the glyph with the accent.
                .buttonStyle(.plain)
                .accessibilityLabel("Hide getting started")
            }
        } footer: {
            if !allDone {
                Text("Each step ticks itself off once you've done it, in any order.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    /// A done step is a plain row (a disabled button would fade its tick); an open one is a button
    /// to where it's done.
    @ViewBuilder
    private func row(_ item: ClassNotesGuide.Item) -> some View {
        let done = ClassNotesGuide.isDone(item, in: snapshot)
        let blocked = item == .studyDeck && !snapshot.hasStudyableDeck
        if done {
            rowLabel(item, done: true, blocked: false)
                .accessibilityElement(children: .combine)
                .accessibilityValue("Done")
        } else {
            Button {
                onShowMe(item)
            } label: {
                rowLabel(item, done: false, blocked: blocked)
            }
            .buttonStyle(.plain)
            .disabled(blocked)
            .accessibilityValue("Not done yet")
        }
    }

    private func rowLabel(_ item: ClassNotesGuide.Item, done: Bool, blocked: Bool) -> some View {
        let isNext = item == next
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : item.systemImage)
                .font(.title3)
                .foregroundStyle(done ? AnyShapeStyle(ClassNotesTile.tint) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 28)
                // The row's value says done or not; the glyph alone reads as "Selected".
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title(for: kind))
                    .font(.body.weight(isNext ? .semibold : .regular))
                    .foregroundStyle(done ? .secondary : .primary)
                if isNext || blocked {
                    Text(blocked ? "Save a word first; then your deck has something to study." : item.detail(for: kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if !done, !blocked {
                if isNext {
                    Text("Show me")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(.white)
                        .background(ClassNotesTile.tint, in: Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, isNext ? 4 : 0)
        .contentShape(Rectangle())
    }

    private var allDoneRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(ClassNotesTile.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Alles erledigt · All done")
                    .font(.body.weight(.semibold))
                Text("You've tried every part. The list can go now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Hide", action: onHide)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Getting started · 4 themes") {
    let snapshot = ClassNotesGuide.Snapshot(hasCourse: true, hasEntry: true)
    ForEach(AppTheme.allCases) { theme in
        List {
            ClassNotesGuideSection(
                items: ClassNotesGuide.items(kind: .course, materials: [.handouts, .vocab, .homework]),
                snapshot: snapshot,
                kind: .course,
                onShowMe: { _ in },
                onHide: {}
            )
        }
        .themedListScreen()
        .environment(\.appTheme, theme)
    }
}
