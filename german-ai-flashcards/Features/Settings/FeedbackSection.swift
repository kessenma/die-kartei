import SwiftUI

// MARK: - Feedback

/// Lets users file a bug report or feature request as a GitHub issue. v1
/// requires a free GitHub account: each button opens one of the repo's GitHub
/// issue-form templates (`.github/ISSUE_TEMPLATE/`) in the browser, so the app
/// needs no backend, API token, or auth handling — GitHub's own login covers it.
///
/// Linking to a template (rather than passing `&labels=`) is what makes the
/// label stick for every reporter: the `labels` URL parameter is honored only
/// for users with write access, but a template's own `labels:` applies to
/// anyone. The template also supplies the structured fields; the app only
/// pre-fills the template's `diagnostics` field with device info.
///
/// Shared by both the Settings model tab and the extracted `ModelSettingsView`,
/// so it lives in its own file with internal (non-private) access.
struct FeedbackSection: View {
    /// Name of the currently loaded MLX model, included in diagnostics so bug
    /// reports show which model was active when the problem occurred.
    let loadedModelName: String?

    private let repo = "https://github.com/kessenma/die-kartei"

    private enum IssueKind {
        case bug, feature

        /// Filename of the matching GitHub issue-form template. The template
        /// owns the title prefix and label, so both apply for every reporter.
        var template: String {
            switch self {
            case .bug:     return "bug_report.yml"
            case .feature: return "feature_request.yml"
            }
        }
    }

    var body: some View {
        Section {
            Link(destination: issueURL(.bug)) {
                Label("Report a bug", systemImage: "ladybug")
            }
            Link(destination: issueURL(.feature)) {
                Label("Request a feature", systemImage: "lightbulb")
            }
            Link(destination: URL(string: "\(repo)/issues")!) {
                Label("Browse existing issues", systemImage: "list.bullet.rectangle")
            }
        } header: {
            Label {
                Text("Feedback")
            } icon: {
                // Single adaptive asset — the black mark in light mode, the
                // generated white mark in dark mode (the imageset carries both
                // as appearance variants, so SwiftUI swaps them automatically).
                Image("github-mark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }
            .themedSectionHeader()
        } footer: {
            Text("Opens GitHub in your browser to file a bug or feature request — a free GitHub account is required. Some device info is added to help with debugging; you can edit or remove it before posting.")
                .font(.caption2)
        }
        .themedListRow()
    }

    // MARK: URL building

    /// Builds a GitHub "new issue" URL that opens the matching issue-form
    /// template and pre-fills its `diagnostics` field. Falls back to the plain
    /// issues page if the URL can't be formed.
    private func issueURL(_ kind: IssueKind) -> URL {
        var components = URLComponents(string: "\(repo)/issues/new")
        // `template` selects the form (which carries the title + label);
        // `diagnostics` matches the template's field id so GitHub pre-fills it.
        components?.queryItems = [
            URLQueryItem(name: "template", value: kind.template),
            URLQueryItem(name: "diagnostics", value: diagnostics)
        ]
        return components?.url ?? URL(string: "\(repo)/issues")!
    }

    // MARK: Diagnostics

    /// Device/app info used to pre-fill the template's "App diagnostics" field.
    /// Kept as a plain bullet list — the template field supplies its own label
    /// and "please keep this" guidance.
    private var diagnostics: String {
        """
        - App version: \(appVersion)
        - Device: \(deviceModel) · \(osVersion)
        - RAM: \(ramGB) GB
        - Loaded model: \(loadedModelName ?? "None")
        """
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// The hardware identifier (e.g. "iPhone15,2"), more useful for debugging
    /// than UIDevice's generic "iPhone". Falls back to UIDevice if unavailable.
    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, element in
            if let value = element.value as? Int8, value != 0 {
                result.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
        return machine.isEmpty ? UIDevice.current.model : machine
    }

    private var osVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    private var ramGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
    }
}
