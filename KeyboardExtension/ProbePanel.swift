import SwiftUI

/// The probe's whole interface: a grid of measurements and a log you can read on the spot.
///
/// Deliberately not a keyboard. Nothing here needs the user to type — the text under test already
/// exists in the host app, and the English drafts are canned. Building a QWERTY is the large,
/// expensive path this build is trying to find out whether we can avoid.
struct ProbePanel: View {

    @ObservedObject var log: ProbeLog
    @ObservedObject var runner: ProbeRunner

    /// Only shown when the system says this keyboard isn't the only one installed.
    let showsGlobe: Bool
    let onGlobe: () -> Void

    @State private var tone: ProbeRunner.Tone = .sie

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)

    var body: some View {
        VStack(spacing: 6) {
            header
            buttons
            logView
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Tastatur-Probe")
                .font(.system(size: 13, weight: .semibold))

            Picker("Anrede", selection: $tone) {
                ForEach(ProbeRunner.Tone.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 96)

            if runner.isRunning {
                ProgressView().controlSize(.mini)
            }

            Spacer()

            if showsGlobe {
                Button(action: onGlobe) {
                    Image(systemName: "globe").font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Probes

    private var buttons: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            probe("Auswahl", "Read the host's selected text") { runner.readSelection() }
            probe("Kontext", "Read the text around the cursor") { runner.readContext() }
            probe("Feld", "Describe the focused field") { runner.describeHostField() }
            probe("Einfügen", "Write a German test line") { runner.insertTest() }

            probe("Ersetzen", "Insert over a live selection") { runner.replaceSelection() }
            probe("Löschen+", "Delete backwards, then retype") { runner.deleteAndReplace() }
            probe("Verfügbar", "Foundation Models availability") { runner.checkAvailability() }
            probe("Speicher", "Memory footprint right now") { runner.memorySnapshot() }

            asyncProbe("Rundlauf", "Full English → German round trip") {
                await runner.roundTrip(tone: tone)
            }
            ForEach(Array(ProbeRunner.shortDrafts.enumerated()), id: \.offset) { index, draft in
                asyncProbe("Entwurf \(index + 1)", "Generate and insert a canned draft") {
                    await runner.cannedDraft(draft, tone: tone)
                }
            }

            probe("Log → Feld", "Type the whole log into the host") { runner.dumpLog() }
            probe("Log leeren", "Clear the log", destructive: true) { log.clear() }
        }
    }

    private func probe(
        _ title: String,
        _ hint: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(.secondarySystemBackground))
                .foregroundStyle(destructive ? Color.red : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private func asyncProbe(
        _ title: String,
        _ hint: String,
        action: @escaping () async -> Void
    ) -> some View {
        probe(title, hint) { Task { await action() } }
            .opacity(runner.isRunning ? 0.4 : 1)
            .disabled(runner.isRunning)
    }

    // MARK: - Log

    private var logView: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if log.lines.isEmpty {
                        Text("Select text in the host app, then run a probe.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                    ForEach(log.lines) { line in
                        Text(line.text)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
                .padding(6)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onChange(of: log.lines.count) {
                if let last = log.lines.last { scroll.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: ProbeLog.Line.Kind) -> Color {
        switch kind {
        case .info: return .primary
        case .good: return .green
        case .bad:  return .red
        }
    }
}
