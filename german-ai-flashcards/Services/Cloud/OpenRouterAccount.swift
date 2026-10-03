import CryptoKit
import Foundation
import Observation

/// The learner's OpenRouter connection: the key in the Keychain, whether there is one, and what
/// OpenRouter says about it. Cloud pictures are billed to this account, never to the app.
@Observable
@MainActor
final class OpenRouterAccount {
    static let shared = OpenRouterAccount()

    /// Mirrors "a key is stored" so `PictureEngine.isReady` can be read from view bodies and
    /// background services without a Keychain query each time.
    nonisolated static let hasKeyDefaultsKey = "openrouter.hasKey"
    nonisolated static var hasKey: Bool { UserDefaults.standard.bool(forKey: hasKeyDefaultsKey) }

    nonisolated private static let keychain = KeychainItem(
        service: "kyle-essenmacher.german-ai-flashcards.openrouter", account: "api-key"
    )

    private(set) var isConnected = false
    /// `sk-or-v1-…abcd`, for the Settings row.
    private(set) var maskedKey: String?
    private(set) var keyInfo: OpenRouterClient.KeyInfo?
    /// A sign-in or key check is in flight.
    private(set) var isWorking = false
    var lastError: String?

    private init() {
        reconcile()
    }

    /// The stored key, read fresh. Nonisolated so a drawing task can fetch it off the main actor.
    nonisolated static func apiKey() -> String? {
        keychain.read()
    }

    /// A stable, anonymous tag for this install, sent as OpenRouter's `user` field (Muse's
    /// provider requires one). A hash of a random id: it identifies nothing about the learner.
    nonisolated static var userTag: String {
        let defaultsKey = "openrouter.installID"
        let id = UserDefaults.standard.string(forKey: defaultsKey) ?? {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: defaultsKey)
            return new
        }()
        return SHA256.hash(data: Data(id.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Re-derive the state from the Keychain. A reinstall keeps Keychain items but clears
    /// UserDefaults, so the mirror flag is rebuilt here rather than trusted.
    func reconcile() {
        let key = Self.apiKey()
        isConnected = key != nil
        maskedKey = key.map(Self.mask)
        UserDefaults.standard.set(isConnected, forKey: Self.hasKeyDefaultsKey)
        if key == nil { keyInfo = nil }
    }

    /// Save a key after OpenRouter confirms it works. Used by both sign-in and "paste a key".
    @discardableResult
    func connect(apiKey raw: String) async -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            let info = try await OpenRouterClient(apiKey: key).keyInfo()
            guard Self.keychain.save(key) else {
                lastError = "Couldn't save the key to this phone's Keychain."
                return false
            }
            keyInfo = info
            reconcile()
            return true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// The full PKCE round trip. `authenticate` opens OpenRouter's page and returns the URL the
    /// callback page forwarded to (SwiftUI's `WebAuthenticationSession` in practice); passing it
    /// in keeps this type free of UI.
    @discardableResult
    func signIn(authenticate: (URL) async throws -> URL) async -> Bool {
        let verifier = OpenRouterPKCE.makeVerifier()
        let url = OpenRouterPKCE.authURL(challenge: OpenRouterPKCE.challenge(for: verifier))
        lastError = nil
        do {
            let callback = try await authenticate(url)
            guard let code = OpenRouterPKCE.code(from: callback) else {
                lastError = "OpenRouter didn't send a sign-in code back. Try again, or paste a key instead."
                return false
            }
            isWorking = true
            let key = try await OpenRouterPKCE.exchange(code: code, verifier: verifier)
            isWorking = false
            return await connect(apiKey: key)
        } catch is CancellationError {
            isWorking = false
            return false
        } catch {
            isWorking = false
            // Closing the sign-in sheet is a choice, not an error worth a red line.
            if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
               (error as NSError).code == 1 {
                return false
            }
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    /// Forget the key on this phone. It stays valid on OpenRouter until the learner deletes it
    /// at openrouter.ai/keys, which Settings links to.
    func disconnect() {
        Self.keychain.delete()
        keyInfo = nil
        lastError = nil
        reconcile()
    }

    /// Called when a drawing run gets a 401: the key is dead, so stop offering cloud pictures
    /// until the learner reconnects.
    func handleUnauthorized() {
        disconnect()
        lastError = OpenRouterError.unauthorized.errorDescription
    }

    /// Refresh spend and limit for the Settings row.
    func refresh() async {
        guard let key = Self.apiKey() else { reconcile(); return }
        do {
            keyInfo = try await OpenRouterClient(apiKey: key).keyInfo()
        } catch OpenRouterError.unauthorized {
            handleUnauthorized()
        } catch {
            // Offline or a hiccup: keep showing the last numbers rather than an error.
        }
    }

    nonisolated static func mask(_ key: String) -> String {
        guard key.count > 12 else { return "••••" }
        return "\(key.prefix(9))…\(key.suffix(4))"
    }
}
