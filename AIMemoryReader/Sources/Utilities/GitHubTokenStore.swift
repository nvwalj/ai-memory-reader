import Foundation
import Security

/// Keychain storage for the optional GitHub personal access token.
///
/// A token is only needed for private repositories and for lifting the API rate
/// limit; public browsing works with nothing stored. It deliberately does *not*
/// go through `SettingsStore`, which syncs to iCloud key-value storage — a
/// credential shouldn't ride along with window preferences.
enum GitHubTokenStore {
    private static let service = "com.aitools.ai-memory-reader.github"
    private static let account = "personal-access-token"

    static var token: String? {
        get { read() }
        set {
            if let newValue, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                write(newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                delete()
            }
        }
    }

    static var hasToken: Bool { read() != nil }

    /// Enough of the token to recognize which one is stored, without showing it.
    static var redacted: String? {
        guard let token = read(), token.count > 8 else { return read().map { _ in "••••" } }
        return "\(token.prefix(4))…\(token.suffix(4))"
    }

    // MARK: - Keychain

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }

    private static func write(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            // The token is only read while the user is in the app, and it must
            // never leave this device.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    private static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
