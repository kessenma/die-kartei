import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Fetches readable text from a URL so it can be studied like a PDF.
/// Reddit posts use the clean `.json` endpoint; other sites fall back to HTML→text.
enum WebTextExtractor {

    nonisolated enum WebError: LocalizedError {
        case badURL
        case network(String)
        case blocked
        case empty

        var errorDescription: String? {
            switch self {
            case .badURL:           return "That doesn’t look like a valid web address."
            case .network(let m):   return "Couldn’t load the page: \(m)"
            case .blocked:          return "Reddit blocked the request (their anti-bot / rate limit). Wait a minute and try again, or try a different source — an ai-at.eu article works reliably."
            case .empty:            return "No readable German text was found at that link."
            }
        }
    }

    struct Extracted { let title: String; let text: String }

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) DieKartei/1.0"
    /// Reddit blocks generic browser UAs; their guidelines ask for a unique descriptive one.
    private static let redditUserAgent = "ios:de.diekartei.studyapp:1.0 (German study app)"

    static func fetch(_ raw: String) async -> Result<Extracted, WebError> {
        var input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return .failure(.badURL) }
        if !input.lowercased().hasPrefix("http") { input = "https://" + input }
        guard let url = URL(string: input), let host = url.host else { return .failure(.badURL) }

        if host.contains("reddit.com") {
            return await fetchReddit(url)
        }
        return await fetchGeneric(url)
    }

    // MARK: - Reddit

    private static func fetchReddit(_ url: URL) async -> Result<Extracted, WebError> {
        // Share links (/r/x/s/abc…) redirect to the canonical /comments/ post — resolve first.
        let resolved = await resolveShareLink(url)

        var blocked = false
        // Try www then old.reddit for the .json endpoint (one is sometimes less restricted).
        for host in ["www.reddit.com", "old.reddit.com"] {
            guard let jsonURL = redditJSONURL(from: resolved, host: host) else { continue }
            do {
                let data = try await get(jsonURL, agent: redditUserAgent)
                if let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
                   let parsed = parseReddit(root) {
                    return .success(parsed)
                }
            } catch WebError.blocked {
                blocked = true
                continue
            } catch {
                continue
            }
        }

        // Last resort: extract the resolved page's HTML.
        if case .success(let extracted) = await fetchGeneric(resolved) {
            return .success(extracted)
        }
        return .failure(blocked ? .blocked : .empty)
    }

    private static func redditJSONURL(from url: URL, host: String) -> URL? {
        var path = url.path
        if path.hasSuffix("/") { path.removeLast() }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = path + "/.json"
        comps.query = "limit=30&raw_json=1"
        return comps.url
    }

    /// Follow a Reddit share link to its canonical /comments/ URL (no-op if already canonical).
    private static func resolveShareLink(_ url: URL) async -> URL {
        guard !url.path.contains("/comments/") else { return url }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(redditUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("de,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let final = response.url, final.path.contains("/comments/") {
            return final
        }
        return url
    }

    private static func parseReddit(_ root: [Any]) -> Extracted? {
        var title = "Reddit-Beitrag"
        var parts: [String] = []

        // root[0] = the post, root[1] = comments
        if let postListing = root.first as? [String: Any],
           let children = (postListing["data"] as? [String: Any])?["children"] as? [[String: Any]],
           let post = children.first?["data"] as? [String: Any] {
            if let t = post["title"] as? String { title = t; parts.append(t) }
            if let body = post["selftext"] as? String, !body.isEmpty { parts.append(body) }
        }
        if root.count > 1, let commentListing = root[1] as? [String: Any],
           let children = (commentListing["data"] as? [String: Any])?["children"] as? [[String: Any]] {
            for child in children.prefix(25) {
                if let cdata = child["data"] as? [String: Any],
                   let body = cdata["body"] as? String, !body.isEmpty {
                    parts.append(body)
                }
            }
        }

        let text = parts.joined(separator: "\n\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 { return nil }
        return Extracted(title: String(title.prefix(90)), text: text)
    }

    // MARK: - Generic HTML

    private static func fetchGeneric(_ url: URL) async -> Result<Extracted, WebError> {
        do {
            let data = try await get(url)
            let (title, text) = htmlToText(data, fallbackTitle: url.host ?? "Seite")
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 60 { return .failure(.empty) }
            return .success(Extracted(title: title, text: text))
        } catch let error as WebError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private static func htmlToText(_ data: Data, fallbackTitle: String) -> (String, String) {
        #if canImport(UIKit)
        if let attr = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            let cleaned = attr.string
                .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = extractHTMLTitle(data) ?? fallbackTitle
            return (String(title.prefix(90)), cleaned)
        }
        #endif
        return (fallbackTitle, String(data: data, encoding: .utf8) ?? "")
    }

    private static func extractHTMLTitle(_ data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8),
              let range = html.range(of: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let inner = String(html[range])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }

    // MARK: - Networking

    private static func get(_ url: URL, agent: String = userAgent) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("de,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 403 || http.statusCode == 429 { throw WebError.blocked }
            throw WebError.network("HTTP \(http.statusCode)")
        }
        return data
    }
}
