import Foundation

/// What the job-posting clipper hands back to the setup screen: the posting text the recruiter
/// will interview from, plus the details that end up on the library row.
struct JobPostingCapture: Equatable {
    var title: String
    var text: String
    var company: String
    var location: String
    var url: String
    /// The page rendered to PDF at capture time, so the posting stays readable once the link
    /// dies. Nil for pasted postings and when WebKit could not render the page.
    var snapshotPDF: Data? = nil
}

/// One heading-delimited block of a job page, as found by `JobPostingScripts.analyze`.
struct SuggestedSection: Codable, Identifiable, Equatable, Hashable {
    var heading: String
    var text: String
    /// Keyword tier: 5 for tasks and profile, 4 for benefits and the description, 2 for about-us,
    /// 1 for the application process, 0 for anything else the page has a heading for.
    var score: Int
    /// Position on the page, so selected sections compose in reading order.
    var order: Int

    var id: String { "\(order)|\(heading)" }
}

/// What the page says about itself: the document title, its first `h1`, and the employer and
/// location when the page states them. Empty strings mean "not found", never a guess.
struct JobPageMeta: Codable, Equatable {
    var title: String
    var h1: String
    var company: String
    var location: String
}

struct JobPageAnalysis: Codable {
    var sections: [SuggestedSection]
    var meta: JobPageMeta
}

/// Job-posting URLs as compared between chats: the same posting pasted with or without "www.",
/// a trailing slash, a fragment, or tracking parameters is the same posting.
enum JobURL {
    static func normalized(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http") { text = "https://" + text }
        guard var comps = URLComponents(string: text), comps.host != nil else { return text.lowercased() }
        comps.scheme = "https"
        comps.fragment = nil
        if let host = comps.host?.lowercased() {
            comps.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        var path = comps.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        comps.path = path
        let tracking: Set<String> = ["ref", "source", "src", "gclid", "fbclid"]
        let kept = comps.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !tracking.contains($0.name.lowercased()) }
        comps.queryItems = (kept?.isEmpty ?? true) ? nil : kept
        return comps.string
    }

    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a = normalized(a), let b = normalized(b) else { return false }
        return a == b
    }
}
