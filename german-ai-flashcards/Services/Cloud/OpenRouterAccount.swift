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

    /// Set by "Disconnect this device only": the synced key stays in the Keychain for the
    /// learner's other devices, and this one acts as if there were none until they connect here
    /// again. Per device on purpose; UserDefaults never syncs.
    nonisolated static let signedOutHereDefaultsKey = "openrouter.signedOutHere"
    nonisolated private static var signedOutHere: Bool {
        UserDefaults.standard.bool(forKey: signedOutHereDefaultsKey)
    }

    /// The key, shared with the learner's other devices (iPhone, iPad, Mac) through iCloud
    /// Keychain, so one sign-in covers all of them.
    nonisolated private static let keychain = KeychainItem(
        service: "kyle-essenmacher.german-ai-flashcards.openrouter", account: "api-key",
        synchronizable: true
    )
    /// Where older builds kept the key, on this device only. `reconcile()` moves it across.
    nonisolated private static let localKeychain = KeychainItem(
        service: "kyle-essenmacher.german-ai-flashcards.openrouter", account: "api-key"
    )

    private(set) var isConnected = false
    /// `sk-or-v1-…abcd`, for the Settings row.
    private(set) var maskedKey: String?
    /// The masked synced key while this device is disconnected on its own, so Settings can offer
    /// it back without a fresh sign-in.
    private(set) var savedKeyMask: String?
    private(set) var keyInfo: OpenRouterClient.KeyInfo?
    /// A sign-in or key check is in flight.
    private(set) var isWorking = false
    var lastError: String?

    private init() {
        reconcile()
    }

    /// The key this device draws with, read fresh: none while it's disconnected on its own.
    /// Nonisolated so a drawing task can fetch it off the main actor.
    nonisolated static func apiKey() -> String? {
        signedOutHere ? nil : storedKey()
    }

    /// Whatever key is in the Keychain, whether or not this device uses it.
    nonisolated private static func storedKey() -> String? {
        keychain.read() ?? localKeychain.read()
    }

    /// Copy an older build's device-only key into the synced item, then drop it. A synced key
    /// already there (another device updated first) wins; the local one is left valid on
    /// OpenRouter like any other old key. If the save fails the local key stays, still readable.
    nonisolated private static func moveLocalKeyToSync() {
        guard let local = localKeychain.read() else { return }
        if keychain.read() == nil, !keychain.save(local) { return }
        localKeychain.delete()
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
    /// UserDefaults, so the mirror flag is rebuilt here rather than trusted. Run at launch and
    /// on every return to the foreground: a key can arrive from, or be removed by, another device
    /// at any time, and the Keychain doesn't say when.
    func reconcile() {
        Self.moveLocalKeyToSync()
        let stored = Self.storedKey()
        let key = Self.signedOutHere ? nil : stored
        isConnected = key != nil
        maskedKey = key.map(Self.mask)
        savedKeyMask = Self.signedOutHere ? stored.map(Self.mask) : nil
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
            // Into the synced item, so it replaces the key on the learner's other devices too.
            guard Self.keychain.save(key) else {
                lastError = "Couldn't save the key to the Keychain."
                return false
            }
            Self.localKeychain.delete()
            UserDefaults.standard.removeObject(forKey: Self.signedOutHereDefaultsKey)
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

    /// Stop using the key. `everywhere` deletes it from iCloud Keychain, so every device that
    /// syncs it signs out; otherwise only this device stops and the others keep drawing. Either
    /// way it stays valid on OpenRouter until the learner deletes it at openrouter.ai/keys, which
    /// Settings links to.
    func disconnect(everywhere: Bool) {
        if everywhere {
            Self.keychain.delete()
            UserDefaults.standard.removeObject(forKey: Self.signedOutHereDefaultsKey)
        } else {
            UserDefaults.standard.set(true, forKey: Self.signedOutHereDefaultsKey)
        }
        Self.localKeychain.delete()
        keyInfo = nil
        lastError = nil
        reconcile()
    }

    /// Undo "Disconnect this device only" while the synced key is still there: no sign-in, then
    /// a key check, which disconnects again if the key has stopped working.
    func useSavedKey() async {
        UserDefaults.standard.removeObject(forKey: Self.signedOutHereDefaultsKey)
        await refresh()
    }

    /// Called when OpenRouter answers 401: the key is dead on every device, so it's deleted from
    /// the synced item too and cloud pictures stop until the learner reconnects. `failedKey` is
    /// the key that got the 401; if another device has put a new one in meanwhile, that one stays.
    func handleUnauthorized(failedKey: String? = nil) {
        if let failedKey, let stored = Self.storedKey(), stored != failedKey {
            reconcile()
            return
        }
        disconnect(everywhere: true)
        lastError = OpenRouterError.unauthorized.errorDescription
    }

    /// Refresh spend and limit for the Settings row.
    func refresh() async {
        reconcile()
        guard let key = Self.apiKey() else { return }
        do {
            keyInfo = try await OpenRouterClient(apiKey: key).keyInfo()
        } catch OpenRouterError.unauthorized {
            handleUnauthorized(failedKey: key)
        } catch {
            // Offline or a hiccup: keep showing the last numbers rather than an error.
        }
    }

    nonisolated static func mask(_ key: String) -> String {
        guard key.count > 12 else { return "••••" }
        return "\(key.prefix(9))…\(key.suffix(4))"
    }
}
