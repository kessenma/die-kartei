import SwiftUI
import WebKit

/// The interview mode's in-app browser. The learner opens the posting (dismissing cookie banners
/// or logging in as needed), and a panel floating over the page collects what to bring: suggested
/// sections found from the page's headings, text highlighted on the page, and the job details.
///
/// The browser chrome mirrors `WebClipperView`, except the navigation buttons sit in the top bar
/// because the panel would cover a bottom bar.
///
/// The setup screen owns the model (and with it the web view) and tears it down when the cover
/// closes. That way nothing SwiftUI does to this view's identity can recreate the browser or
/// reload the page; the view only starts the page once, guarded by `model.hasStarted`.
struct JobPostingClipperView: View {
    @Bindable var model: JobPostingClipperModel
    var initialURL: String?
    /// The tutor that will read the posting; sets the character budget.
    let tutor: MLXModel
    /// Details already typed on the setup screen. They seed the panel's fields, so what the panel
    /// hands back is always the newest version of all three.
    var initialTitle = ""
    var initialCompany = ""
    var initialLocation = ""
    var accent: Color = .accentColor
    /// Job prep's study reader has no tutor context window to fit into, so it lifts the character
    /// cap (`studyCap`) and hides the budget meter; the Use button says what happens next.
    var capOverride: Int? = nil
    var useButtonTitle = "Use this posting"
    var showsBudget = true
    var onCapture: (JobPostingCapture) -> Void

    /// The cap for a posting captured to read rather than to prompt with: generous, still bounded.
    static let studyCap = 60_000

    /// Height of the collapsed panel, and the bottom inset the page scrolls above.
    static let compactHeight: CGFloat = 120

    /// The panel's three stops. The top one is deliberately short of `.large`: a sheet that
    /// covers its presenter dims it, SwiftUI then treats the browser as gone and rebuilds it, and
    /// the rebuilt view re-applies the sheet, which is the loop that bounced the panel and
    /// reloaded the page. A sliver of page always showing keeps the sheet non-modal throughout.
    static let compactDetent: PresentationDetent = .height(compactHeight)
    static let midDetent: PresentationDetent = .fraction(0.45)
    static let fullDetent: PresentationDetent = .fraction(0.9)

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var address = ""
    @State private var pasteSuggestion: String?
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                addressRow

                if address.isEmpty, let pasteSuggestion {
                    Button {
                        address = pasteSuggestion
                        self.pasteSuggestion = nil
                        load()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste copied link").font(.caption).foregroundStyle(.secondary)
                            Text(pasteSuggestion).font(.caption).lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                    }
                    .padding(.top, 6)
                }

                Group {
                    if model.web.isLoading && model.web.progress < 1 {
                        ProgressView(value: model.web.progress).progressViewStyle(.linear).tint(accent)
                    } else {
                        Color.clear.frame(height: 2)
                    }
                }
                .frame(height: 2)
                .padding(.top, 6)

                // Only once the panel has a reason to be missing; before the first presentation
                // there is nothing to announce.
                if !model.panelShown, model.panelAutoHidden || model.panelHiddenManually {
                    hiddenPanelStrip
                }

                webContent
            }
            .background {
                if appTheme != .klar { ThemedBackground().ignoresSafeArea() }
            }
            .navigationTitle("Job posting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { model.web.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!model.web.canGoBack)
                        .accessibilityLabel("Back")
                    Button { model.web.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!model.web.canGoForward)
                        .accessibilityLabel("Forward")
                    Button { model.web.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Reload")
                    Button { model.togglePanel() } label: {
                        Image(systemName: "rectangle.bottomhalf.inset.filled")
                            .foregroundStyle(model.panelShown ? accent : Color.secondary)
                    }
                    .accessibilityLabel(model.panelShown ? "Hide the capture panel" : "Show the capture panel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { addressFocused = false }
                }
            }
            .sheet(isPresented: $model.panelShown) {
                JobPostingPanel(
                    model: model, detent: $model.detent, tutor: tutor, accent: accent,
                    useButtonTitle: useButtonTitle, showsBudget: showsBudget
                ) {
                    Task { onCapture(await model.capture()) }
                }
                .presentationDetents([Self.compactDetent, Self.midDetent, Self.fullDetent], selection: $model.detent)
                // Interactive at every stop, so the sheet never dims (and never "covers") the page.
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
            }
            .onChange(of: model.web.currentURL) { _, newValue in
                if !newValue.isEmpty { address = newValue }
            }
            .onChange(of: model.panelShown) { _, shown in
                // The page only needs room to scroll above the panel while there is one.
                setBottomInset(shown ? Self.compactHeight : 0)
            }
            .task { await start() }
        }
    }

    /// Sits at the top, under the address bar, so it can never cover what the panel was hiding.
    /// Named for the reason when the model hid the panel itself.
    private var hiddenPanelStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: model.panelAutoHidden ? "hand.raised" : "rectangle.bottomhalf.inset.filled")
                .foregroundStyle(.secondary)
            Text(model.panelAutoHidden
                 ? "Panel hidden so you can answer the cookie notice. It comes back when the notice is gone."
                 : "Capture panel hidden.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Show") { model.togglePanel() }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    private func setBottomInset(_ inset: CGFloat) {
        #if canImport(UIKit)
        model.web.webView.scrollView.contentInset.bottom = inset
        model.web.webView.scrollView.verticalScrollIndicatorInsets.bottom = inset
        #endif
    }

    private var addressRow: some View {
        HStack(spacing: 8) {
            TextField("Link to the job posting…", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit { load() }
                .textFieldStyle(.roundedBorder)
            if !address.isEmpty {
                Button { address = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("Go") { load() }
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    @ViewBuilder private var webContent: some View {
        #if canImport(UIKit)
        WebViewContainer(webView: model.web.webView)
        #else
        Text("In-app browser is only available on iOS.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private func start() async {
        // The view can be re-created (or its task restarted) while the cover is up; the page must
        // load exactly once per model.
        if model.hasStarted {
            address = model.web.currentURL
            return
        }
        model.hasStarted = true
        model.cap = capOverride ?? JobContextBudget.characters(for: tutor)
        model.title = initialTitle
        model.company = initialCompany
        model.location = initialLocation
        #if canImport(UIKit)
        // The page tints selected sections in the same accent as the pills.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(accent).getRed(&r, green: &g, blue: &b, alpha: &a) {
            model.highlightRGB = "\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255))"
        }
        // Let the page scroll its last lines above the collapsed panel.
        model.web.webView.scrollView.contentInset.bottom = Self.compactHeight
        model.web.webView.scrollView.verticalScrollIndicatorInsets.bottom = Self.compactHeight
        #endif
        if let initialURL, !initialURL.isEmpty {
            address = initialURL
            model.web.load(initialURL)
        } else {
            pasteSuggestion = ClipboardLink.suggestion()
            addressFocused = true
        }
        // A sheet presented while the cover is still animating in can be dropped.
        try? await Task.sleep(for: .milliseconds(500))
        model.presentPanelInitially()
    }

    private func load() {
        addressFocused = false
        model.web.load(address)
    }
}

// MARK: - Panel

/// The sheet over the page. Collapsed, it is one row of section pills and the meter; expanded, it
/// is the full list of sections, highlights, the composed posting, and the details fields.
private struct JobPostingPanel: View {
    @Bindable var model: JobPostingClipperModel
    @Binding var detent: PresentationDetent
    let tutor: MLXModel
    let accent: Color
    var useButtonTitle = "Use this posting"
    var showsBudget = true
    let onUse: () -> Void

    @Environment(\.appTheme) private var appTheme
    @State private var showBudgetInfo = false
    @State private var previewedSectionID: String?
    @State private var wholePageTooShort = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, company, location }

    private var isCompact: Bool { detent == JobPostingClipperView.compactDetent }

    /// The full list is always there; the compact strip lays over its top while the sheet is at
    /// its lowest detent. Swapping whole view trees at a detent change made the sheet jump.
    var body: some View {
        ZStack(alignment: .top) {
            expanded
                .allowsHitTesting(!isCompact)
                .accessibilityHidden(isCompact)
            if isCompact {
                compact
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isCompact)
    }

    // MARK: Compact

    private var compact: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.sections.isEmpty {
                        Text(model.hasAnalyzed ? "No job sections found yet" : "Reading the page…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.sections.prefix(6)) { section in
                        FilterPill(
                            label: String(section.heading.prefix(28)),
                            tint: accent,
                            isOn: model.selectedSectionIDs.contains(section.id)
                        ) {
                            model.toggle(section)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                if model.pendingSelection.isEmpty {
                    Text("Highlight text on the page, or tap a section")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Button {
                        model.addSelection()
                    } label: {
                        Label("Add highlight (\(model.pendingSelection.count.formatted()))", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(accent)
                }
                Spacer(minLength: 4)
                if showsBudget { meterLabel }
                Button("Use", action: onUse)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.small)
                    .disabled(!model.canCapture || model.isCapturing)
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 18)
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: JobPostingClipperView.compactHeight, alignment: .top)
        .background {
            // Opaque, so the list underneath never shows through the strip.
            if appTheme != .klar {
                ThemedBackground().ignoresSafeArea()
            } else {
                Rectangle().fill(.background).ignoresSafeArea()
            }
        }
    }

    private var meterLabel: some View {
        Text(JobContextBudget.label(used: model.charCount, cap: model.cap))
            .font(.caption.monospacedDigit())
            .foregroundStyle(model.isOverCap ? Color.orange : Color.secondary)
    }

    // MARK: Expanded

    private var expanded: some View {
        NavigationStack {
            List {
                sectionsSection.themedListRow()
                highlightSection.themedListRow()
                postingSection.themedListRow()
                detailsSection.themedListRow()
            }
            .themedListScreen()
            .navigationTitle("What to bring over")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { useButton }
            .toolbar {
                if detent == JobPostingClipperView.fullDetent {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Show page") { detent = JobPostingClipperView.midDetent }
                            .font(.callout)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .sheet(isPresented: $showBudgetInfo) {
                JobContextInfoSheet(model: tutor)
            }
            .onChange(of: focusedField) { _, newValue in
                if newValue != nil { detent = JobPostingClipperView.fullDetent }
            }
        }
    }

    private var sectionsSection: some View {
        Section {
            if model.sections.isEmpty {
                Text(model.hasAnalyzed
                     ? "No job sections found yet. The page may still be loading, or highlight text on the page instead."
                     : "Reading the page…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.sections) { section in
                let selected = model.selectedSectionIDs.contains(section.id)
                HStack(spacing: 10) {
                    Button {
                        model.toggle(section)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? accent : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.heading).font(.callout.weight(.medium)).lineLimit(1)
                                Text("\(section.text.count.formatted()) characters")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        previewedSectionID = previewedSectionID == section.id ? nil : section.id
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(previewedSectionID == section.id ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Preview")
                }
                if previewedSectionID == section.id {
                    Text(section.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }
            }
            Button {
                Task { await model.analyze() }
            } label: {
                Label("Refresh suggestions", systemImage: "arrow.clockwise")
            }
            .disabled(model.isAnalyzing)
        } header: {
            Text("Suggested sections").themedSectionHeader()
        } footer: {
            Text("Found from the page's headings. Tap one to include it; the page tints what it covers and scrolls there.")
        }
    }

    private var highlightSection: some View {
        Section {
            if model.pendingSelection.isEmpty {
                Text("Select text on the page and it shows up here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await model.readSelection() }
                } label: {
                    Label("Read selection", systemImage: "text.cursor")
                }
            } else {
                Text(model.pendingSelection)
                    .font(.caption)
                    .lineLimit(3)
                HStack {
                    Button {
                        model.addSelection()
                    } label: {
                        Label("Add highlight", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .tint(accent)
                    Spacer()
                    Button("Clear", role: .destructive) { model.clearSelection() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        } header: {
            Text("Highlighted on the page").themedSectionHeader()
        }
    }

    private var postingSection: some View {
        Section {
            if model.selectedSections.isEmpty && model.snippets.isEmpty {
                Text("Nothing yet. Tap a section or add a highlight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.selectedSections) { section in
                HStack {
                    Text(section.heading).font(.callout).lineLimit(1)
                    Spacer()
                    Text(section.text.count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { model.deselectSections(at: $0) }
            ForEach(Array(model.snippets.enumerated()), id: \.offset) { _, snippet in
                HStack {
                    Text(snippet).font(.caption).lineLimit(2)
                    Spacer()
                    Text(snippet.count.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { model.removeSnippets(at: $0) }

            if showsBudget {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Budget").font(.caption)
                        Spacer()
                        meterLabel
                        Button {
                            showBudgetInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("About the posting budget")
                    }
                    ProgressView(value: Double(min(model.charCount, model.cap)), total: Double(model.cap))
                        .tint(model.isOverCap ? .orange : accent)
                }
            } else {
                HStack {
                    Text("\(model.charCount.formatted()) characters")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Button {
                Task {
                    wholePageTooShort = !(await model.useWholePage())
                }
            } label: {
                Label("Use entire page text", systemImage: "doc.text")
            }
            .disabled(model.isAnalyzing)
            if wholePageTooShort {
                Text("That page had very little text. Navigate to the actual posting and try again.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Posting text").themedSectionHeader()
        } footer: {
            if !showsBudget {
                Text("Swipe a row to remove it. You'll read these in this order. A PDF copy of the whole page is saved with the posting, in case it goes offline.")
            } else if model.isOverCap {
                Text("Over budget: the recruiter reads the first \(model.cap.formatted()) characters. Remove a section or a highlight.")
            } else {
                Text("Swipe a row to remove it. The recruiter reads these in this order. A PDF copy of the whole page is saved with the chat, in case the posting goes offline.")
            }
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Job title", text: $model.title)
                .focused($focusedField, equals: .title)
            TextField("Company", text: $model.company)
                .focused($focusedField, equals: .company)
            TextField("Location", text: $model.location)
                .focused($focusedField, equals: .location)
        } header: {
            Text("Details").themedSectionHeader()
        } footer: {
            Text("Filled in from the page when it says so. Edit anything that is off; the title becomes the chat name.")
        }
    }

    private var useButton: some View {
        Button(action: onUse) {
            Group {
                if model.isCapturing {
                    Label("Saving a copy of the page…", systemImage: "doc.richtext")
                } else if model.isOverCap, showsBudget {
                    Text("Use the first \(model.cap.formatted()) characters")
                } else {
                    Text(useButtonTitle)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .controlSize(.large)
        .disabled(!model.canCapture || model.isCapturing)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
