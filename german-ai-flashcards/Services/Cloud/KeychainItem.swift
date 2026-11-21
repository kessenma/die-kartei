import Foundation
import Security

/// One generic-password item in this app's Keychain, read and written as a UTF-8 string.
///
/// `synchronizable` items travel to the learner's other devices through iCloud Keychain (end to
/// end encrypted, and only when they have it turned on) and are stored `AfterFirstUnlock`. Local
/// items are `AfterFirstUnlockThisDeviceOnly`. Either way a background illustration run can read
/// it with the phone locked.
///
/// The two kinds are separate items even under the same service and account: a query only ever
/// matches its own kind, so a local item from an older build stays invisible to a synced one
/// until it's moved across.
nonisolated struct KeychainItem: Sendable {
    let service: String
    let account: String
    var synchronizable = false

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
        ]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replace the stored value, or add it if there isn't one yet.
    @discardableResult
    func save(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = synchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
