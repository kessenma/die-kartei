//
//  WorksheetView.swift
//  german-ai-flashcards
//
//  Working a handout's homework. A strip of the picked pages along the top; under it the page,
//  either as controls (`WorksheetItemsView`) beside a live preview of the slide as the teacher will
//  get it, or as the slide itself to write on with the Pencil (`WorksheetCanvas`). Share sends her
//  slides with everything filled in (`WorksheetExport`); "Mark as sent" ticks the homework off.
//  The optional check (`WorksheetCheckView`) never changes what is sent.
//

import SwiftUI
import SwiftData

struct WorksheetView: View {
    @Bindable var material: ClassMaterial
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appTheme) private var appTheme

    @State private var session: WorksheetSession?
    @State private var failed = false
    @State private var showsSlide = false
    @State private var showSetup = false
    @State private var showCheck = false
    /// "Check this page": the check sheet scoped to one page.
    @State private var checkingPage: CheckScope?
    /// The Pencil over the whole screen, and the hand-off that keeps two canvases off one page's
    /// ink (`PencilFullScreen`).
    @State private var fullScreen = PencilHandOff()
    /// The Pencil rail's state for the embedded canvas; full screen has its own.
    @State private var pencil = PencilBoard()
    @FocusState private var typing: String?

    struct CheckScope: Identifiable {
        let page: Int
        var id: Int { page }
    }

    private var accent: Color { ClassNotesTile.tint }

    var body: some View {
        Group {
            if let session {
                content(session)
            } else if failed {
                ContentUnavailableView("Can't open the homework", systemImage: "doc.questionmark",
                                       description: Text("The handout's PDF isn't on this device yet. If it was added on another device, wait for iCloud to bring it over."))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(material.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard session == nil else { return }
            guard let made = WorksheetSession(material: material, context: modelContext) else {
                failed = true
                return
            }
            session = made
            await made.load()
        }
        .onDisappear { session?.flush() }
        .sheet(isPresented: $showSetup, onDismiss: reload) {
            NavigationStack {
                WorksheetSetupView(material: material) { _ in showSetup = false }
            }
        }
        .sheet(isPresented: $showCheck) {
            if let session {
                WorksheetCheckView(session: session, modelManager: modelManager, mlxService: mlxService)
            }
        }
        .sheet(item: $checkingPage) { scope in
            if let session {
                WorksheetCheckView(session: session, modelManager: modelManager, mlxService: mlxService, page: scope.page)
            }
        }
        // The embedded canvas reads the page's file in its own init, so only the preview needs
        // bringing up to date.
        .pencilFullScreen($fullScreen, onReturn: { session?.refreshPreview() }) {
            if let session {
                WorksheetPencilFullScreen(session: session, modelManager: modelManager, mlxService: mlxService)
            }
        }
        .memoryContext("worksheet")
    }

    private func reload() {
        session?.flush()
        session = nil
        Task {
            guard let made = WorksheetSession(material: material, context: modelContext) else { return }
            session = made
            await made.load()
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(_ session: WorksheetSession) -> some View {
        VStack(spacing: 0) {
            pageStrip(session)
            Divider()
            if let plan = session.plan {
                if plan.mode == .pencil || session.exercise == nil {
                    pencilPage(session, plan: plan)
                } else if let exercise = session.exercise {
                    answerPage(session, exercise: exercise)
                }
            }
        }
        .toolbar { toolbar(session) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                ForEach(["ä", "ö", "ü", "ß", "Ä", "Ö", "Ü"], id: \.self) { letter in
                    Button(letter) { insert(letter, session: session) }
                }
                Spacer()
                Button("Done") { typing = nil }
            }
        }
    }

    private func pageStrip(_ session: WorksheetSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(session.setup.pages.enumerated()), id: \.element.page) { index, plan in
                        let progress = session.progress(page: plan.page)
                        let isCurrent = index == session.index
                        let done = progress.total > 0 && progress.done == progress.total
                        Button {
                            session.index = index
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: plan.mode == .pencil ? "pencil.tip" : (done ? "checkmark.circle.fill" : "circle.dotted"))
                                    .font(.caption)
                                Text(shortTitle(plan.title))
                                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                                    .lineLimit(1)
                                if plan.mode == .answer, progress.total > 1 {
                                    Text("\(progress.done)/\(progress.total)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isCurrent ? accent.opacity(0.18) : Color.secondary.opacity(0.08), in: appTheme.pillShape)
                            .foregroundStyle(isCurrent ? accent : .primary)
                        }
                        .buttonStyle(.plain)
                        .id(plan.page)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onChange(of: session.index) { _, new in
                guard session.setup.pages.indices.contains(new) else { return }
                withAnimation { proxy.scrollTo(session.setup.pages[new].page, anchor: .center) }
            }
        }
    }

    /// "Dativ D1: Artikel ergänzen" → "Dativ D1" in the strip; the full title heads the page.
    private func shortTitle(_ title: String) -> String {
        if let colon = title.firstIndex(of: ":") { return String(title[..<colon]) }
        if let dot = title.range(of: " · ") { return String(title[..<dot.lowerBound]) }
        return title
    }

    // MARK: - Answering

    @ViewBuilder
    private func answerPage(_ session: WorksheetSession, exercise: WorksheetExercise) -> some View {
        let items = ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                WorksheetItemsView(session: session, exercise: exercise, typing: $typing)
                checkPageButton(session)
            }
            .padding()
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WorksheetChipTray(session: session, exercise: exercise)
        }

        if sizeClass == .regular {
            HStack(spacing: 0) {
                items.frame(maxWidth: .infinity)
                Divider()
                slidePreview(session)
                    .frame(maxWidth: .infinity)
            }
        } else {
            ZStack {
                if showsSlide {
                    slidePreview(session)
                } else {
                    items
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation { showsSlide.toggle() }
                } label: {
                    Label(showsSlide ? "Answers" : "Slide", systemImage: showsSlide ? "list.bullet" : "rectangle.on.rectangle")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    /// The slide as it will be sent, the focused blank ringed; tapping a blank focuses it.
    private func slidePreview(_ session: WorksheetSession) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wie sie es bekommt · What she'll get")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let image = session.preview, let part = session.part {
                        let width = proxy.size.width - 32
                        let height = width * part.bounds.height / max(part.bounds.width, 1)
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: width, height: height)
                            .overlay { focusRing(session, part: part, size: CGSize(width: width, height: height)) }
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                focusGap(at: location, session: session, part: part,
                                         size: CGSize(width: width, height: height))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.secondary.opacity(0.06))
    }

    @ViewBuilder
    private func focusRing(_ session: WorksheetSession, part: WorksheetPagePart, size: CGSize) -> some View {
        if let key = session.focusedKey ?? typing, let rect = part.geometry?.gaps[key] {
            let frame = viewRect(rect, part: part, size: size)
            RoundedRectangle(cornerRadius: 4)
                .stroke(accent, lineWidth: 2)
                .frame(width: frame.width + 8, height: frame.height + 6)
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(false)
        }
    }

    /// Page space (points, y-up) to the preview's frame (y-down).
    private func viewRect(_ rect: CGRect, part: WorksheetPagePart, size: CGSize) -> CGRect {
        let sx = size.width / part.bounds.width
        let sy = size.height / part.bounds.height
        return CGRect(x: (rect.minX - part.bounds.minX) * sx,
                      y: (part.bounds.maxY - rect.maxY) * sy,
                      width: rect.width * sx, height: rect.height * sy)
    }

    private func focusGap(at point: CGPoint, session: WorksheetSession, part: WorksheetPagePart, size: CGSize) {
        guard let gaps = part.geometry?.gaps else { return }
        let hit = gaps.min { a, b in
            distance(point, viewRect(a.value, part: part, size: size)) < distance(point, viewRect(b.value, part: part, size: size))
        }
        guard let hit, distance(point, viewRect(hit.value, part: part, size: size)) < 30 else { return }
        let options = session.exercise?.sections.first { $0.items.contains { $0.gaps.contains { $0.key == hit.key } } }?.options
        let isLong = session.exercise?.items.flatMap(\.gaps).first { $0.key == hit.key }?.isLong ?? false
        if options != nil, !isLong {
            session.focusedKey = hit.key
        } else {
            typing = hit.key
        }
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func insert(_ letter: String, session: WorksheetSession) {
        guard let key = typing else { return }
        session.setText((session.answer(key)?.text ?? "") + letter, for: key)
    }

    // MARK: - Pencil

    @ViewBuilder
    private func pencilPage(_ session: WorksheetSession, plan: WorksheetPagePlan) -> some View {
        if let part = session.part {
            ZStack(alignment: .topTrailing) {
                if !fullScreen.inlineShown {
                    // The full-screen canvas owns this page's ink while it is up; two canvases on
                    // one file would each save over the other.
                    Color.clear
                } else {
                    WorksheetCanvas(
                        materialID: material.id,
                        page: plan.page,
                        pdfData: session.pdfData,
                        part: part,
                        answers: session.answers,
                        herAnswers: session.shownKey(page: plan.page),
                        notes: plan.notes ?? WorksheetNotesMargins(),
                        pencil: pencil,
                        onSaved: { session.inkSaved() }
                    )
                    .id("\(plan.page)-\(fullScreen.token)")
                    .pencilRail(pencil, accent: accent,
                                canvasSettings: { WorksheetNotesSettings(session: session) },
                                tips: { WorksheetTips() })
                }
                pencilButtons(session, page: plan.page)
                    .padding(12)
            }
            .ignoresSafeArea(edges: .bottom)
        } else {
            ProgressView()
        }
    }

    /// Floating over the slide: check this page, and (on iPad) the whole screen to write in.
    private func pencilButtons(_ session: WorksheetSession, page: Int) -> some View {
        HStack(spacing: 10) {
            WorksheetKeyToggle(session: session, page: page, accent: accent)
            if session.part?.exercise.verdict == .interactive {
                Button {
                    checkingPage = CheckScope(page: page)
                } label: {
                    Label("Check", systemImage: "checkmark.seal")
                }
            }
            #if os(iOS)
            Button {
                $fullScreen.open()
            } label: {
                Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            #endif
        }
        .font(.subheadline.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .controlSize(.regular)
    }

    private func checkPageButton(_ session: WorksheetSession) -> some View {
        Button {
            typing = nil
            session.flush()
            if let page = session.plan?.page { checkingPage = CheckScope(page: page) }
        } label: {
            Label("Check this page", systemImage: "checkmark.seal")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(accent)
    }

    // MARK: - Toolbar

    /// The export with the optional check drawn in: ✓, ? and ✗ beside the answers, and the right
    /// form after a wrong one.
    private func checkedSnapshot(_ session: WorksheetSession) -> WorksheetExport.Snapshot {
        var snapshot = session.exportSnapshot
        snapshot.showsChecks = true
        return snapshot
    }

    @ToolbarContentBuilder
    private func toolbar(_ session: WorksheetSession) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if session.exercise != nil, let plan = session.plan {
                Button {
                    typing = nil
                    session.setMode(plan.mode == .pencil ? .answer : .pencil)
                } label: {
                    Image(systemName: plan.mode == .pencil ? "list.bullet.rectangle" : "pencil.tip.crop.circle")
                }
                .accessibilityLabel(plan.mode == .pencil ? "Answer in the app" : "Write on the slide")
            }
            Menu {
                ShareLink(item: WorksheetDocument(snapshot: session.exportSnapshot),
                          preview: SharePreview(WorksheetExport.fileName(for: material.title))) {
                    Label("My answers", systemImage: "doc.richtext")
                }
                ShareLink(item: WorksheetDocument(snapshot: checkedSnapshot(session)),
                          preview: SharePreview(WorksheetExport.fileName(for: material.title, checked: true))) {
                    Label("With the check marks", systemImage: "checkmark.seal")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share the finished slides")
            Menu {
                if let page = session.plan?.page, session.part?.exercise.verdict == .interactive {
                    Button {
                        session.flush()
                        checkingPage = CheckScope(page: page)
                    } label: {
                        Label("Check this page", systemImage: "checkmark.seal")
                    }
                }
                Button {
                    session.flush()
                    showCheck = true
                } label: {
                    Label("Check every page", systemImage: "checklist")
                }
                Button {
                    session.markSent(!session.isSent)
                } label: {
                    Label(session.isSent ? "Not sent yet" : "Mark as sent",
                          systemImage: session.isSent ? "arrow.uturn.backward" : "paperplane")
                }
                Button {
                    session.flush()
                    showSetup = true
                } label: {
                    Label("Change the pages", systemImage: "rectangle.stack.badge.plus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - The Pencil, full screen

/// The slide over the whole screen to write on, page after page: no page strip, no tab bar, the
/// page fitted to the screen and zoomable. Any picked page can be written on here, including one
/// answered in the app (the typed answers show under the ink).
struct WorksheetPencilFullScreen: View {
    @Bindable var session: WorksheetSession
    @Bindable var modelManager: MLXModelManager
    var mlxService: MLXGenerationService

    @State private var checkingPage: WorksheetView.CheckScope?
    @State private var pencil = PencilBoard()

    private var accent: Color { ClassNotesTile.tint }

    var body: some View {
        PencilFullScreenPage {
            HStack(spacing: 12) {
                Button {
                    session.index -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(session.index == 0)
                .accessibilityLabel("Previous page")

                Text(session.plan?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: 420)

                Button {
                    session.index += 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(session.index >= session.setup.pages.count - 1)
                .accessibilityLabel("Next page")
            }
        } end: {
            if let page = session.plan?.page {
                WorksheetKeyToggle(session: session, page: page, accent: accent)
            }
            if let page = session.plan?.page, session.part?.exercise.verdict == .interactive {
                Button {
                    checkingPage = WorksheetView.CheckScope(page: page)
                } label: {
                    Label("Check", systemImage: "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        } canvas: {
            if let plan = session.plan, let part = session.part {
                WorksheetCanvas(
                    materialID: session.material.id,
                    page: plan.page,
                    pdfData: session.pdfData,
                    part: part,
                    answers: session.answers,
                    herAnswers: session.shownKey(page: plan.page),
                    notes: plan.notes ?? WorksheetNotesMargins(),
                    pencil: pencil,
                    onSaved: { session.inkSaved() }
                )
                .id(plan.page)
                .pencilRail(pencil, accent: accent,
                            canvasSettings: { WorksheetNotesSettings(session: session) },
                            tips: { WorksheetTips() })
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .sheet(item: $checkingPage) { scope in
            WorksheetCheckView(session: session, modelManager: modelManager, mlxService: mlxService, page: scope.page)
        }
    }
}

/// The worksheet's own rows in the Pencil tips.
struct WorksheetTips: View {
    var body: some View {
        PencilTipRow(symbol: "doc.richtext", title: "Notizrand · Notes margin",
                     detail: "The gear adds paper on any side of the slide for your own notes and questions. It stays in the app: the PDF you send is her slide with your answers.",
                     accent: ClassNotesTile.tint)
    }
}

// MARK: - Notes paper, in the rail's gear

/// Extra paper on any side of this page's slide, for the learner's own notes and questions.
struct WorksheetNotesSettings: View {
    @Bindable var session: WorksheetSession

    private var notes: WorksheetNotesMargins { session.plan?.notes ?? WorksheetNotesMargins() }

    var body: some View {
        PencilSettingsRow("Notizrand · Notes margin") {
            HStack(spacing: 8) {
                side("Links", systemImage: "arrow.left", isOn: \.left)
                side("Rechts", systemImage: "arrow.right", isOn: \.right)
                side("Oben", systemImage: "arrow.up", isOn: \.top)
                side("Unten", systemImage: "arrow.down", isOn: \.bottom)
            }
        }
        Text("Extra paper beside this slide for your own notes and questions. It stays in the app: "
             + "the PDF you send is her slide with your answers.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func side(_ title: String, systemImage: String,
                      isOn side: WritableKeyPath<WorksheetNotesMargins, Bool>) -> some View {
        Toggle(isOn: Binding(get: { notes[keyPath: side] }, set: { on in
            var next = notes
            next[keyPath: side] = on
            session.setNotes(next)
        })) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity)
        }
        .toggleStyle(.button)
        .accessibilityLabel("Notes paper \(title)")
    }
}

/// "Lösungen": her answer key on the slide, on and off, for marking your own work when the
/// check can't read it or you'd rather. Only on a page her Lösungen pages answer.
struct WorksheetKeyToggle: View {
    @Bindable var session: WorksheetSession
    let page: Int
    let accent: Color

    var body: some View {
        if !session.herAnswers(page: page).isEmpty {
            Button {
                session.showsKey.toggle()
            } label: {
                Label("Lösungen", systemImage: session.showsKey ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderedProminent)
            .tint(session.showsKey ? WorksheetKeyToggle.keyGreen : accent)
            .accessibilityLabel(session.showsKey ? "Hide her answers" : "Show her answers")
        }
    }

    /// `WorksheetRenderer.keyColor`, the green her answers are drawn in.
    static let keyGreen = Color(red: 0.10, green: 0.48, blue: 0.20)
}
