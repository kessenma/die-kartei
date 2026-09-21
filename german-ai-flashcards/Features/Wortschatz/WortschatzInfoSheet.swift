//
//  WortschatzInfoSheet.swift
//  german-ai-flashcards
//
//  Where the words come from: the three official Goethe-Institut lists, each with its PDF.
//

import SwiftUI

struct WortschatzInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image("logo-goethe")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)

                VStack(spacing: 8) {
                    Text("Official Word Lists")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Goethe-Zertifikat A1 · A2 · B1")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Every word in the box comes from the vocabulary lists the Goethe-Institut publishes for its exams. The lists build on each other, so one word can appear at several levels; the box tracks it once.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                VStack(spacing: 10) {
                    ForEach(GoetheLevel.allCases) { level in
                        Link(destination: level.pdfURL) {
                            Label("\(level.rawValue) · \(level.examName)", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: 300)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("About the Word Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .background { if appTheme != .klar { ThemedBackground().ignoresSafeArea() } }
        .presentationDetents([.medium])
    }
}
