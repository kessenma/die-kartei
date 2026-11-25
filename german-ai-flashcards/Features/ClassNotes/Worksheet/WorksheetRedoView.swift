//
//  WorksheetRedoView.swift
//  german-ai-flashcards
//
//  Wiederholen (docs/WORKSHEETS.md): her review plan, a worksheet again a day and a week after it
//  was sent, with the answers hidden. Typed answers in the same item views, checked by the same
//  check (her key, the article rules, the tutor). Nothing is written to the handout: the answers
//  she will see stay as they were. "Fertig" records the step.
//

import SwiftData
import SwiftUI

struct WorksheetRedoView: View {
    @Bindable var material: ClassMaterial
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var session: WorksheetSession?
    @State private var failed = false
    @State private var checking = false
    @FocusState private var typing: String?

    private var step: Int? {
        WorksheetReviewPlan.dueStep(sentAt: material.worksheet?.sentAt, redone: material.redoDates)
    }

    var body: some View {
        Group {
            if let session {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Label("Answers hidden. Fill it in again from memory, then check.", systemImage: "eye.slash")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(session.setup.answerPages) { plan in
                            if let exercise = session.parts[plan.page]?.exercise, exercise.verdict == .interactive {
                                WorksheetItemsView(session: session, exercise: exercise, typing: $typing)
                            }
                        }
                        HStack(spacing: 12) {
                            Button {
                                checking = true
                            } label: {
                                Label("Prüfen · Check", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button {
                                finish()
                            } label: {
                                Text("Fertig · Done").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .sheet(isPresented: $checking) {
                    NavigationStack {
                        WorksheetCheckView(session: session, modelManager: modelManager, mlxService: mlxService)
                    }
                }
            } else if failed {
                ContentUnavailableView("Can't open the worksheet", systemImage: "doc.questionmark",
                                       description: Text("Its PDF is missing on this device."))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Wiederholen · \(material.title.isEmpty ? "Übung" : material.title)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard session == nil, !failed else { return }
            guard let made = WorksheetSession(material: material, context: modelContext, redo: true) else {
                failed = true
                return
            }
            await made.load()
            session = made
        }
    }

    private func finish() {
        // One redo per step, however often the screen is opened before the next is due.
        if step != nil {
            material.redoDates = material.redoDates + [.now]
            try? modelContext.save()
        }
        dismiss()
    }
}
