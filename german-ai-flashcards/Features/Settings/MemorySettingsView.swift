import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Speicher. What the app is holding right now and who holds it, the toggle for the
/// finer logging, and the log itself — crashes, memory warnings, model moves — with Copy, Share
/// and Clear. The place to look when the app closed by itself, and the place to copy from when
/// reporting it.
struct MemorySettingsView: View {
    @Environment(\.appTheme) private var appTheme

    @AppStorage(MemoryDiagnostics.verboseDefaultsKey) private var verbose: Bool = MemoryDiagnostics.verboseDefault
    @AppStorage(MemoryReadoutOverlay.defaultsKey) private var showOverlay = false

    @State private var reading = MemoryReading.now()
    @State private var breakdown: [MemoryEvent.Contributor] = []
    @State private var events: [MemoryEvent] = MemoryDiagnostics.events
    @State private var selected: MemoryEvent?
    @State private var didCopy = false
    @State private var confirmingClear = false

    var body: some View {
        List {
            SettingsHeader(icon: "memorychip", title: "Speicher")

            nowSection
            loggingSection
            eventsSection
        }
        .themedListScreen()
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 120)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    copyLog()
                } label: {
                    Label(didCopy ? "Copied!" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(events.isEmpty)
                .accessibilityLabel(didCopy ? "Copied" : "Copy the log")

                if let document = MemoryLogExport.document(events: events) {
                    ShareLink(item: document,
                              preview: SharePreview("Memory log", image: Image(systemName: "memorychip"))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(events.isEmpty)
                }

                Menu {
                    Button(role: .destructive) {
                        confirmingClear = true
                    } label: {
                        Label("Clear the log", systemImage: "trash")
                    }
                    .disabled(events.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .animation(.spring(duration: 0.3), value: didCopy)
        .alert("Clear the memory log?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) {
                MemoryDiagnostics.clearLog()
                events = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every recorded event goes, including crash records. Logging carries on afterwards.")
        }
        .sheet(item: $selected) { event in
            MemoryEventDetailView(event: event)
        }
        .onChange(of: verbose) { _, _ in MemoryDiagnostics.verboseDidChange() }
        // Live rows: cheap kernel reads, refreshed while the screen is up and dropped with it.
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: - Right now

    private var nowSection: some View {
        Section {
            valueRow("Used by the app", mb: reading.footprintMB, symbol: "memorychip")
            valueRow("Free before iOS closes it", mb: reading.availableMB, symbol: "arrow.down.to.line")
            valueRow("Budget on this device", mb: reading.totalMB, symbol: "gauge.with.dots.needle.33percent")

            ForEach(breakdown, id: \.name) { row in
                HStack {
                    Text(row.name)
                    Spacer()
                    Text("\(row.mb) MB")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }

            if ScreenshotSeeding.isAvailable {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show a live readout", isOn: $showOverlay)
                    Text("A small line in the corner of every screen with the numbers above, for watching a screen while you use it. Testing builds only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Jetzt · Right now").themedSectionHeader()
        } footer: {
            Text("iOS gives an app only part of the device's memory, and closes it when it goes over. The tutor is nearly all of what this app holds; the rows above show what else is sharing the space. MLX active \(reading.mlxActiveMB) MB, peak \(reading.mlxPeakMB) MB.")
                .font(.caption2)
        }
        .themedListRow()
    }

    private func valueRow(_ title: String, mb: Int, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(mb >= 0 ? MemoryBudget.formattedGB(mb) : "—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Logging

    private var loggingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Log when memory runs short", isOn: $verbose)
                Text("Records what was using memory whenever the app gets close to its limit, and each time a tutor or the drawing model is loaded or unloaded, plus a routine reading every minute while the app is open. Crashes are always recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Protokoll · Logging").themedSectionHeader()
        }
        .themedListRow()
    }

    // MARK: - Events

    @ViewBuilder
    private var eventsSection: some View {
        Section {
            if events.isEmpty {
                Text("Nothing recorded yet. A crash, a memory warning, or — with logging on — the next model load will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(events) { event in
                    Button {
                        selected = event
                    } label: {
                        eventRow(event)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Abstürze & Ereignisse · Crashes & events").themedSectionHeader()
        } footer: {
            if !events.isEmpty {
                Text("Newest first. Tap a row for the full breakdown. Copy puts the whole log on the clipboard as text; Share sends it as a file.")
                    .font(.caption2)
            }
        }
        .themedListRow()
    }

    private func eventRow(_ event: MemoryEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.body)
                .foregroundStyle(color(for: event.kind))
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(caption(for: event))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func caption(for event: MemoryEvent) -> String {
        var parts = ["\(event.reading.footprintMB) MB used", "\(event.reading.availableMB) MB free"]
        if let context = event.context { parts.append(context) }
        if event.appState != "active" { parts.append(event.appState) }
        return parts.joined(separator: " · ")
    }

    private func color(for kind: MemoryEvent.Kind) -> Color {
        switch kind {
        case .unexpectedTermination, .crashReport: .red
        case .memoryWarning, .pressureCritical, .pressureElevated, .interruptedLoad: .orange
        case .heartbeat: .secondary
        default: appTheme.accent(model: nil)
        }
    }

    // MARK: - Actions

    private func refresh() {
        reading = MemoryReading.now()
        breakdown = MemoryDiagnostics.breakdown(for: reading)
        events = MemoryDiagnostics.events
    }

    private func copyLog() {
        UIPasteboard.general.string = MemoryDiagnostics.exportText(events: events)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}

// MARK: - Detail

private struct MemoryEventDetailView: View {
    let event: MemoryEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var appTheme
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(event.title, systemImage: event.kind.symbol)
                            .font(.headline)
                        Text(event.date.formatted(date: .long, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let context = event.context {
                            Label(context, systemImage: "location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("App was \(event.appState) · version \(event.appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    if let detail = event.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                .themedListRow()

                Section {
                    readingRow("Used by the app", event.reading.footprintMB)
                    readingRow("Free", event.reading.availableMB)
                    readingRow("Budget", event.reading.totalMB)
                    readingRow("MLX active", event.reading.mlxActiveMB)
                    readingRow("MLX cache", event.reading.mlxCacheMB)
                    readingRow("MLX peak since launch", event.reading.mlxPeakMB)
                } header: {
                    Text("Reading").themedSectionHeader()
                }
                .themedListRow()

                if !event.breakdown.isEmpty {
                    Section {
                        ForEach(event.breakdown, id: \.name) { row in
                            readingRow(row.name, row.mb)
                        }
                    } header: {
                        Text("What was holding it").themedSectionHeader()
                    }
                    .themedListRow()
                }
            }
            .themedListScreen()
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        UIPasteboard.general.string = MemoryDiagnostics.line(for: event)
                            + (event.detail.map { "\n" + $0 } ?? "")
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            didCopy = false
                        }
                    } label: {
                        Label(didCopy ? "Copied!" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .animation(.spring(duration: 0.3), value: didCopy)
        }
    }

    private func readingRow(_ title: String, _ mb: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(mb >= 0 ? "\(mb) MB" : "—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

// MARK: - Export

/// The log as a JSON attachment, the way the placement review exports: `Transferable` so the
/// system materializes the file itself and nothing on disk races the share sheet.
struct MemoryLogDocument: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.fileName }
    }
}

enum MemoryLogExport {
    private struct Envelope: Encodable {
        struct App: Encodable {
            var name: String
            var version: String
            var build: String
        }
        struct Device: Encodable {
            var model: String
            var os: String
            var ramGB: Int
        }
        var schema = "die-kartei.memory-log"
        var schemaVersion = 1
        var exportedAt: Date
        var app: App
        var device: Device
        var now: MemoryReading
        var loggingWhenShort: Bool
        var events: [MemoryEvent]
    }

    static func document(events: [MemoryEvent]) -> MemoryLogDocument? {
        let envelope = Envelope(
            exportedAt: Date(),
            app: .init(name: "Die Kartei", version: DeviceInfo.version, build: DeviceInfo.build),
            device: .init(model: DeviceInfo.deviceModel, os: DeviceInfo.osVersion, ramGB: DeviceCapability.ramGB),
            now: MemoryReading.now(),
            loggingWhenShort: MemoryDiagnostics.isVerbose,
            events: events
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(envelope) else { return nil }
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return MemoryLogDocument(data: data, fileName: "memory-log-\(stamp).json")
    }
}

// MARK: - Live readout

/// A one-line footprint / free / MLX readout pinned to the bottom of every screen, for watching a
/// screen's cost while using it. Testing builds only; switched on from Settings ▸ Speicher.
struct MemoryReadoutOverlay: ViewModifier {
    static let defaultsKey = "memoryLog.overlay"

    @AppStorage(MemoryReadoutOverlay.defaultsKey) private var enabled = false
    @State private var reading = MemoryReading.now()

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            if enabled && ScreenshotSeeding.isAvailable {
                Text("\(reading.footprintMB) MB · free \(reading.availableMB) · MLX \(reading.mlxActiveMB)+\(reading.mlxCacheMB)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.trailing, 10)
                    .padding(.bottom, 62)
                    .allowsHitTesting(false)
                    .task {
                        while !Task.isCancelled {
                            reading = MemoryReading.now()
                            try? await Task.sleep(for: .seconds(1))
                        }
                    }
            }
        }
    }
}

extension View {
    func memoryReadoutOverlay() -> some View {
        modifier(MemoryReadoutOverlay())
    }
}

#Preview("Speicher") {
    NavigationStack {
        MemorySettingsView()
    }
}
