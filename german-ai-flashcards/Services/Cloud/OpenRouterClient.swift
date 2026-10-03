import CryptoKit
import Foundation

/// Everything that can go wrong drawing a cloud picture, in the learner's words.
///
/// `stopsRun` is the split that matters to every illustration loop: a missing key, a revoked key,
/// an empty account or a missing age confirmation will fail every remaining picture the same way,
/// so the run stops and says why. A refused prompt or a provider hiccup only costs that one
/// picture.
nonisolated enum OpenRouterError: LocalizedError, Equatable {
    case notConnected
    case unauthorized
    /// `keyLimit` is true when the key's own spending limit ran out, rather than the account.
    case outOfCredit(keyLimit: Bool)
    case needsAgeConfirmation
    case refused(String?)
    case rateLimited(retryAfter: TimeInterval?)
    case provider(code: Int, message: String)
    case noImage
    case badResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Cloud pictures need your OpenRouter account. Connect it in Settings ▸ Model."
        case .unauthorized:
            "OpenRouter didn't accept the saved key. It may have been revoked. Connect your account again in Settings ▸ Model."
        case .outOfCredit(let keyLimit):
            keyLimit
                ? "This key has reached its spending limit on OpenRouter. Raise it at openrouter.ai/keys."
                : "Your OpenRouter credit has run out. Add credit at openrouter.ai/settings/credits, or from Settings ▸ Model."
        case .needsAgeConfirmation:
            "Muse Image needs a one-time step on OpenRouter: open openrouter.ai/meta/muse-image, tick \u{201C}I confirm that I am 18 years of age or older\u{201D}, and tap Confirm. Or switch to Nano Banana."
        case .refused(let reason):
            "The picture model declined this one" + (reason.map { ": \($0)" } ?? ".")
        case .rateLimited:
            "OpenRouter is busy right now. Try again in a minute."
        case .provider(let code, let message):
            "The picture service had a problem (\(code)): \(message)"
        case .noImage:
            "The picture model answered without a picture."
        case .badResponse:
            "OpenRouter sent back something unexpected."
        case .network(let message):
            "Couldn't reach OpenRouter: \(message)"
        }
    }

    var stopsRun: Bool {
        switch self {
        case .notConnected, .unauthorized, .outOfCredit, .needsAgeConfirmation: true
        default: false
        }
    }

    /// Worth one more try after a pause.
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .network: true
        case .provider(let code, _): [500, 502, 503, 524, 529].contains(code)
        default: false
        }
    }
}

/// Stateless calls to OpenRouter with a key the learner owns. No URLSession delegate anywhere
/// (async delegate overrides crash this compiler; see `ResumableModelDownloader`).
nonisolated struct OpenRouterClient: Sendable {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    /// Attribution headers. The referer is the app's public page, which is also what the
    /// learner sees listed as the app on their OpenRouter activity.
    static let referer = "https://kessenma.github.io/kartei-privacy"
    static let title = "Die Kartei"
    /// Neither model streams, and Muse plans before it draws; OpenRouter's p99 is under a minute.
    static let imageTimeout: TimeInterval = 180

    let apiKey: String

    /// A finished picture as OpenRouter sent it: encoded bytes (PNG, JPEG or WebP) or, in
    /// principle, an https link to them.
    struct ParsedImage: Equatable, Sendable {
        var bytes: Data?
        var remoteURL: URL?
        var mediaType: String?
        var cost: Double?
    }

    struct Picture: Sendable {
        let bytes: Data
        let cost: Double?
    }

    // MARK: - Pictures

    /// Draw one picture. A rate limit or a provider hiccup is retried up to twice, after
    /// `Retry-After` when OpenRouter sends one; every other failure throws straight away.
    /// Cancellation of the calling task cancels the request.
    func generateImage(
        model: CloudImageModel,
        prompt: String,
        references: [Data] = [],
        user: String
    ) async throws -> Picture {
        let body = try Self.imageRequestBody(model: model, prompt: prompt, references: references, user: user)
        var attempt = 0
        while true {
            attempt += 1
            do {
                let parsed = try await send(path: "images", body: body, timeout: Self.imageTimeout)
                if let bytes = parsed.bytes { return Picture(bytes: bytes, cost: parsed.cost) }
                if let url = parsed.remoteURL {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    return Picture(bytes: data, cost: parsed.cost)
                }
                throw OpenRouterError.noImage
            } catch let error as OpenRouterError where error.isRetryable && attempt < 3 {
                // A full deck in flight can briefly outrun a model's per-minute limit; backing off
                // beats dropping the picture.
                var pause: TimeInterval = attempt == 1 ? 3 : 8
                if case .rateLimited(let after?) = error { pause = min(max(after, 1), 30) }
                try await Task.sleep(for: .seconds(pause))
            }
        }
    }

    private func send(path: String, body: Data, timeout: TimeInterval) async throws -> ParsedImage {
        var request = Self.request(path: path, apiKey: apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await Self.perform(request)
        return try Self.parseImageResponse(
            data, status: response.statusCode,
            retryAfter: response.value(forHTTPHeaderField: "Retry-After")
        )
    }

    // MARK: - The key

    /// What OpenRouter reports about the key in use. Works with an ordinary user key, unlike
    /// `/credits`, which needs a management key.
    struct KeyInfo: Decodable, Equatable, Sendable {
        let label: String?
        /// Dollars spent on this key so far.
        let usage: Double?
        /// The key's spending cap in dollars, or nil for none.
        let limit: Double?
        let limitRemaining: Double?

        enum CodingKeys: String, CodingKey {
            case label, usage, limit
            case limitRemaining = "limit_remaining"
        }
    }

    func keyInfo() async throws -> KeyInfo {
        var request = Self.request(path: "key", apiKey: apiKey)
        request.timeoutInterval = 20
        let (data, response) = try await Self.perform(request)
        guard response.statusCode == 200 else {
            throw Self.error(from: data, status: response.statusCode, retryAfter: nil)
        }
        struct Envelope: Decodable { let data: KeyInfo }
        guard let info = try? JSONDecoder().decode(Envelope.self, from: data).data else {
            throw OpenRouterError.badResponse
        }
        return info
    }

    // MARK: - Requests

    private static func request(path: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(title, forHTTPHeaderField: "X-OpenRouter-Title")
        return request
    }

    private static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OpenRouterError.badResponse }
            return (data, http)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw OpenRouterError.network(error.localizedDescription)
        }
    }

    /// The JSON body for `POST /images`. References travel as data URLs, labelled with the type
    /// their bytes actually are.
    static func imageRequestBody(
        model: CloudImageModel, prompt: String, references: [Data], user: String
    ) throws -> Data {
        var body: [String: Any] = ["model": model.rawValue, "prompt": prompt, "user": user]
        if let ratio = model.aspectRatio { body["aspect_ratio"] = ratio }
        let refs = references.prefix(model.maxReferences)
        if !refs.isEmpty {
            body["input_references"] = refs.map { data in
                ["type": "image_url", "image_url": ["url": dataURL(for: data)]]
            }
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    static func dataURL(for data: Data) -> String {
        "data:\(mediaType(of: data));base64,\(data.base64EncodedString())"
    }

    /// Sniffed from the magic bytes. Gemini has been seen answering JPEG when asked for PNG, so
    /// nothing downstream trusts a declared type.
    static func mediaType(of data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.count >= 12, bytes[0...3] == [0x52, 0x49, 0x46, 0x46], bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }
        return "image/png"
    }

    // MARK: - Responses

    /// `{"data":[{"b64_json": …, "media_type": …}], "usage": {"cost": …}}` on success; anything
    /// else becomes an `OpenRouterError`.
    static func parseImageResponse(_ data: Data, status: Int, retryAfter: String?) throws -> ParsedImage {
        guard status == 200 else { throw error(from: data, status: status, retryAfter: retryAfter) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenRouterError.badResponse
        }
        if json["error"] != nil { throw error(from: data, status: status, retryAfter: retryAfter) }
        let cost = (json["usage"] as? [String: Any])?["cost"] as? Double
        guard let first = (json["data"] as? [[String: Any]])?.first else { throw OpenRouterError.noImage }
        let mediaType = first["media_type"] as? String
        if let b64 = first["b64_json"] as? String, let bytes = Data(base64Encoded: b64) {
            return ParsedImage(bytes: bytes, mediaType: mediaType, cost: cost)
        }
        if let urlString = first["url"] as? String {
            if urlString.hasPrefix("data:"), let comma = urlString.firstIndex(of: ","),
               let bytes = Data(base64Encoded: String(urlString[urlString.index(after: comma)...])) {
                return ParsedImage(bytes: bytes, mediaType: mediaType, cost: cost)
            }
            if let url = URL(string: urlString), url.scheme == "https" {
                return ParsedImage(remoteURL: url, mediaType: mediaType, cost: cost)
            }
        }
        throw OpenRouterError.noImage
    }

    /// Map an error body (`{"error":{"code","message","metadata"}}`) and status to a case.
    static func error(from data: Data, status: Int, retryAfter: String?) -> OpenRouterError {
        let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
        let code = (error?["code"] as? Int) ?? status
        let message = (error?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: code)
        let metadata = error?["metadata"] as? [String: Any] ?? [:]
        switch code {
        case 401:
            return .unauthorized
        case 402:
            return .outOfCredit(keyLimit: (metadata["limit_source"] as? String) == "openrouter_key_limit")
        case 403:
            if let missing = metadata["missing_attestation_types"] as? [String], missing.contains("age_18plus") {
                return .needsAgeConfirmation
            }
            return .refused(metadata["reasons"].flatMap { ($0 as? [String])?.joined(separator: ", ") })
        case 400 where isSafetyBlock(metadata: metadata, message: message):
            return .refused(nil)
        case 429:
            return .rateLimited(retryAfter: retryAfter.flatMap(TimeInterval.init))
        default:
            return .provider(code: code, message: message)
        }
    }

    private static func isSafetyBlock(metadata: [String: Any], message: String) -> Bool {
        let reasons = [metadata["finish_reason"], metadata["block_reason"], metadata["error_type"]]
            .compactMap { $0 as? String }
        let markers = ["PROHIBITED", "SAFETY", "content_policy", "refusal"]
        return reasons.contains { reason in markers.contains { reason.localizedCaseInsensitiveContains($0) } }
            || message.localizedCaseInsensitiveContains("moderation")
    }
}

// MARK: - Sign-in (OAuth PKCE)

/// OpenRouter's PKCE sign-in: the learner approves on openrouter.ai, and the app swaps the code
/// it gets back for a key that belongs to their account. No client id, no secret, no server.
///
/// OpenRouter only redirects to https or localhost, so the callback is a static page on the
/// app's site that forwards the query to `kartei-openrouter://callback`, which the web
/// authentication session catches. The code is useless without this run's verifier.
nonisolated enum OpenRouterPKCE {
    /// The https page OpenRouter redirects to. DEBUG builds take `-openrouter.debugCallback <url>`
    /// so the sign-in can be tried against a copy of the page served from the Mac
    /// (`http://localhost:…`, which OpenRouter also accepts) before the real one is published.
    static var callbackPage: URL {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "openrouter.debugCallback"), let url = URL(string: raw) {
            return url
        }
        #endif
        return URL(string: "https://kessenma.github.io/kartei-openrouter-callback")!
    }
    static let callbackScheme = "kartei-openrouter"
    static let keyLabel = "Die Kartei"

    /// 32 random bytes, base64url: a 43-character verifier (RFC 7636 §4.1).
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func authURL(challenge: String, callback: URL = callbackPage) -> URL {
        var components = URLComponents(string: "https://openrouter.ai/auth")!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: callback.absoluteString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "key_label", value: keyLabel),
        ]
        return components.url!
    }

    /// The `code` from whatever URL the callback page handed back.
    static func code(from callback: URL) -> String? {
        URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code" }?.value
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static func exchangeBody(code: String, verifier: String) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["code": code, "code_verifier": verifier, "code_challenge_method": "S256"],
            options: [.sortedKeys]
        )
    }

    /// Trade the one-time code for the learner's key.
    static func exchange(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: OpenRouterClient.baseURL.appendingPathComponent("auth/keys"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try exchangeBody(code: code, verifier: verifier)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw OpenRouterError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OpenRouterClient.error(from: data, status: status, retryAfter: nil)
        }
        guard let key = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["key"] as? String,
              !key.isEmpty
        else { throw OpenRouterError.badResponse }
        return key
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
