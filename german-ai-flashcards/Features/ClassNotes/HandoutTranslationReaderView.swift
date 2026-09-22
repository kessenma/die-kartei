//
//  HandoutTranslationReaderView.swift
//  german-ai-flashcards
//
//  A handout in German, in English, or both at once: side by side where the screen is wide (an
//  iPad, especially in landscape), English above German where it is narrow (a phone). The two
//  panes scroll together, sentence for sentence, because the translation is stored sentence for
//  sentence; a toggle lights up the sentence at the top of the screen in both languages, and a
//  tap on any sentence brings both panes to it. Without a translation yet, the screen is where
//  one is made.
//

import SwiftUI
import SwiftData

struct HandoutTranslationReaderView: View {
    @Bindable var material: ClassMaterial
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum ReadingMode: String, CaseIterable, Identifiable {
        case german, both, english
        var id: String { rawValue }
        var label: String {
            switch self {
            case .german:  "Deutsch"
            case .both:    "Beide"
            case .english: "English"
            }
        }
    }

    private enum Language { case german, english }

    /// One reading preference for every handout, like the inline glosses.
    @AppStorage("handout.translation.mode") private var modeRaw = ReadingMode.both.rawValue
    @AppStorage("handout.translation.highlightTop") private var highlightTop = false
    /// The sentence at the top of the screen, shared by both panes: scrolling one moves the other.
    @State private var topID: String?
    @State private var service: HandoutTranslationService?
    @State private var showRetranslateConfirm = false

    private let accent = ClassNotesTile.tint

    private var mode: ReadingMode { ReadingMode(rawValue: modeRaw) ?? .both }
    private var translation: HandoutTranslation? { material.translation }
    private var isRunning: Bool { service?.isRunning == true }

    /// The same picker and choice as the flashcard builder (`DocumentTutorChoice`).
    private var downloadedTutors: [MLXModel] { DocumentTutorChoice.downloaded }
    private var tutor: MLXModel { DocumentTutorChoice.current(modelManager) }

    var body: some View {
        Group {
            if let translation, translation.translatedCount > 0, !isRunning {
                reader(translation)
            } else {
                setupScreen
            }
        }
        .navigationTitle(material.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let translation, translation.translatedCount > 0, !isRunning {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle(isOn: $highlightTop) {
                            Label("Highlight the top sentence", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        if !translation.isComplete {
                            Button {
                                startTranslation()
                            } label: {
                                Label("Finish translating", systemImage: "arrow.clockwise")
                            }
                        }
                        Button {
                            showRetranslateConfirm = true
                        } label: {
                            Label("Translate again", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Translate the whole text again?", isPresented: $showRetranslateConfirm, titleVisibility: .visible) {
            Button("Translate again", role: .destructive) {
                material.setTranslation(nil)
                try? modelContext.save()
                startTranslation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current English is replaced. Takes a few minutes for a long text.")
        }
        .onAppear {
            // The highlight and the sync need a current sentence before the first scroll.
            if topID == nil, let first = translation?.paragraphs.first, !first.german.isEmpty {
                topID = "p\(first.id)-s0"
            }
        }
        .onDisappear { service?.cancel() }
    }

    // MARK: - Reader

    @ViewBuilder
    private func reader(_ translation: HandoutTranslation) -> some View {
        VStack(spacing: 0) {
            Picker("Language", selection: $modeRaw) {
                ForEach(ReadingMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch mode {
            case .german:
                pane(.german, translation)
            case .english:
                pane(.english, translation)
            case .both:
                if sizeClass == .regular {
                    HStack(spacing: 0) {
                        pane(.german, translation, header: "Deutsch")
                        Divider()
                        pane(.english, translation, header: "English")
                    }
                } else {
                    VStack(spacing: 0) {
                        pane(.english, translation, header: "English")
                        Divider()
                        pane(.german, translation, header: "Deutsch")
                    }
                }
            }
        }
        .background {
            if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
        }
    }

    /// One language, one scroll view. Both panes bind the same `topID`, which is what keeps them
    /// together: the pane being scrolled reports the sentence at its top, the other jumps to it.
    private func pane(_ language: Language, _ translation: HandoutTranslation, header: String? = nil) -> some View {
        VStack(spacing: 0) {
            if let header {
                Text(header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(translation.paragraphs) { paragraph in
                        let sentences = language == .german ? paragraph.german : paragraph.english
                        ForEach(sentences.indices, id: \.self) { index in
                            let id = "p\(paragraph.id)-s\(index)"
                            sentenceRow(sentences[index], id: id, language: language)
                        }
                        Color.clear.frame(height: 14)
                    }
                    Color.clear.frame(height: 120)
                }
                .scrollTargetLayout()
                .padding(.horizontal, 10)
            }
            .scrollPosition(id: $topID, anchor: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sentenceRow(_ text: String, id: String, language: Language) -> some View {
        let isTop = highlightTop && topID == id
        return Group {
            if text.isEmpty {
                Text("· · ·")
                    .foregroundStyle(.tertiary)
            } else {
                Text(text)
                    .foregroundStyle(language == .english ? .primary : .primary)
            }
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isTop ? accent.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: appTheme.innerRadius(6), style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.3)) { topID = id }
        }
        .id(id)
    }

    // MARK: - Setup

    private var setupScreen: some View {
        List {
            Section {
                if let service, service.isRunning {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: service.progress)
                            .tint(accent)
                        Text(service.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Stop") { service.cancel() }
                    }
                    .padding(.vertical, 4)
                } else {
                    let count = translation?.sentenceCount ?? HandoutTranslation.skeleton(for: material.text).sentenceCount
                    let done = translation?.translatedCount ?? 0
                    DocumentTutorPicker(modelManager: modelManager, title: "Translate with")
                    Button {
                        startTranslation()
                    } label: {
                        Label(done > 0 ? "Continue translating (\(done) of \(count) done)" : "Translate \(count) sentences",
                              systemImage: "text.book.closed")
                    }
                    .disabled(downloadedTutors.isEmpty)
                    if let service, case .failed(let message) = service.phase {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Übersetzung · Translation").themedSectionHeader()
            } footer: {
                Text(downloadedTutors.isEmpty
                     ? "Download a tutor in Settings ▸ Model to translate a text. Everything stays on this device."
                     : "The tutor translates the text sentence by sentence, on this device, so you can read German and English side by side. A long handout takes a few minutes; you can stop and continue later.")
                    .font(.caption2)
            }
            .themedListRow()
        }
        .themedListScreen()
    }

    private func startTranslation() {
        let svc = HandoutTranslationService(mlxService: mlxService, modelContext: modelContext)
        service = svc
        Task {
            await svc.translate(material, model: tutor)
        }
    }
}

// MARK: - Preview

@MainActor
private func translationReaderPreview(_ theme: AppTheme) -> some View {
    let material = ClassMaterial(
        title: "Hänsel und Gretel",
        text: "Vor einem großen Walde wohnte ein armer Holzhacker mit seiner Frau und seinen zwei Kindern. Er hatte wenig zu beißen und zu brechen.\n\nDie zwei Kinder hatten vor Hunger auch nicht einschlafen können.",
        sourceKind: .pdf
    )
    var translation = HandoutTranslation.skeleton(for: material.text)
    translation.paragraphs[0].english = ["At the edge of a great forest lived a poor woodcutter with his wife and his two children.", "He had little to bite and to break."]
    translation.paragraphs[1].english = ["The two children had not been able to fall asleep for hunger either."]
    material.setTranslation(translation)
    return NavigationStack {
        HandoutTranslationReaderView(material: material, modelManager: MLXModelManager(), mlxService: MLXGenerationService())
    }
    .environment(\.appTheme, theme)
    .modelContainer(for: [ClassCourse.self, ClassEntry.self, ClassMaterial.self], inMemory: true)
}

#Preview("Translation · System")  { translationReaderPreview(.klar) }
#Preview("Translation · Bauhaus") { translationReaderPreview(.grundform) }
