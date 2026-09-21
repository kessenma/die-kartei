import Foundation

/// The probe's only output channel.
///
/// A keyboard extension without Allow Full Access cannot reach the pasteboard, an App Group, or
/// the network, so there is no way to get results off the device except to *show* them and to
/// type them into whatever field is focused. `ProbeLog` holds the lines for the panel and
/// `rendered` produces the text that the "Dump log" probe inserts into the host document.
///
/// Lines also go to a file in the extension's own container (no App Group needed) so that a
/// restart — which the lifecycle probe is specifically trying to provoke — doesn't erase the run.
@MainActor
final class ProbeLog: ObservableObject {

    struct Line: Identifiable {
        let id = UUID()
        let at: Date
        let text: String
        let kind: Kind

        enum Kind { case info, good, bad }
    }

    @Published private(set) var lines: [Line] = []

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// `Application Support` inside the *extension's* container — reachable without Full Access,
    /// and invisible to the containing app (which is fine; the panel is the reader).
    private static var fileURL: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("probe-log.txt")
    }

    init() {
        restore()
    }

    // MARK: - Writing

    func info(_ text: String) { append(text, .info) }
    func good(_ text: String) { append(text, .good) }
    func bad(_ text: String)  { append(text, .bad) }

    private func append(_ text: String, _ kind: Line.Kind) {
        let line = Line(at: Date(), text: text, kind: kind)
        lines.append(line)
        // Keep the panel (and the dump) bounded — a runaway probe shouldn't make the log
        // unreadable or the inserted dump enormous.
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
        persist(line)
    }

    func clear() {
        lines.removeAll()
        if let url = Self.fileURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Reading

    /// The whole log as plain text — what "Dump log" types into the focused field.
    var rendered: String {
        let body = lines.map { "\(Self.formatter.string(from: $0.at))  \(marker(for: $0.kind))\($0.text)" }
            .joined(separator: "\n")
        return "--- Die Kartei keyboard probe ---\n\(body)\n--- end ---\n"
    }

    private func marker(for kind: Line.Kind) -> String {
        switch kind {
        case .info: return ""
        case .good: return "OK  "
        case .bad:  return "!!  "
        }
    }

    // MARK: - Persistence

    private func persist(_ line: Line) {
        guard let url = Self.fileURL else { return }
        let text = "\(Self.formatter.string(from: line.at))\t\(kindTag(line.kind))\t\(line.text)\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private func restore() {
        guard let url = Self.fileURL,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for row in text.split(separator: "\n") {
            let parts = row.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let at = Self.formatter.date(from: String(parts[0])) else { continue }
            lines.append(Line(at: at, text: String(parts[2]), kind: kind(fromTag: String(parts[1]))))
        }
        if !lines.isEmpty {
            append("— restored \(lines.count) line(s) from a previous run —", .info)
        }
    }

    private func kindTag(_ kind: Line.Kind) -> String {
        switch kind {
        case .info: return "i"
        case .good: return "g"
        case .bad:  return "b"
        }
    }

    private func kind(fromTag tag: String) -> Line.Kind {
        switch tag {
        case "g": return .good
        case "b": return .bad
        default:  return .info
        }
    }
}
