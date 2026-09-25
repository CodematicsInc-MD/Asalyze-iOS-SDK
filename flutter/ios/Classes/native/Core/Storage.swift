import Foundation
import Security

/// Persists the first-party install id in the Keychain so it survives app reinstalls-in-place and
/// backups, giving a stable IDFA-free identity. Falls back to a fresh UUID if the Keychain is empty.
enum Storage {
    private static let service = "com.asalyze.tracker"
    private static let account = "install_id"

    private static let firstRunKey = "com.asalyze.installed"

    /// Resolve the install identity and whether THIS launch is a reinstall. The install id lives in the
    /// Keychain (survives app deletion); a first-run marker lives in UserDefaults (wiped on deletion). So
    /// if the Keychain id already existed but the marker was gone, the app was deleted & reinstalled → a
    /// redownload. A brand-new install (no Keychain id) is NOT a reinstall. Sets the marker so later
    /// launches report false. Call once at startup.
    static func loadIdentity() -> (installId: String, isReinstall: Bool) {
        let hadMarker = UserDefaults.standard.bool(forKey: firstRunKey)
        let existing = readKeychain()
        let id: String
        if let e = existing { id = e } else { id = UUID().uuidString; writeKeychain(id) }
        UserDefaults.standard.set(true, forKey: firstRunKey)
        return (id, existing != nil && !hadMarker)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    // --- Local dedup for StoreKit transactions (so on-launch history backfill isn't re-sent every run;
    //     the backend also dedups on transactionId, this just avoids redundant network calls). ---
    private static let sentTxnsKey = "com.asalyze.sentTransactionIds"

    /// `markTransactionSent` is a read-modify-write over UserDefaults, and concurrent reporting is normal
    /// here, so the sequence needs a lock or one thread's id is lost.
    private static let sentTxnsLock = NSLock()

    static func hasSentTransaction(_ id: String) -> Bool {
        sentTxnsLock.lock(); defer { sentTxnsLock.unlock() }
        return (UserDefaults.standard.stringArray(forKey: sentTxnsKey) ?? []).contains(id)
    }

    static func markTransactionSent(_ id: String) {
        sentTxnsLock.lock(); defer { sentTxnsLock.unlock() }
        var ids = UserDefaults.standard.stringArray(forKey: sentTxnsKey) ?? []
        guard !ids.contains(id) else { return }
        ids.append(id)
        if ids.count > 2000 { ids.removeFirst(ids.count - 2000) } // cap the cache
        UserDefaults.standard.set(ids, forKey: sentTxnsKey)
    }

    // MARK: - Session heartbeat

    private static let lastPingKey = "com.asalyze.lastPingAt"

    /// When we last told the backend this device is still here. UserDefaults, not the keychain: it is a
    /// throttle, not an identity, and it SHOULD reset when the app is deleted — a returning device
    /// pinging immediately is the correct behaviour.
    static func lastPingAt() -> Date? {
        let t = UserDefaults.standard.double(forKey: lastPingKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func markPinged(_ when: Date = Date()) {
        UserDefaults.standard.set(when.timeIntervalSince1970, forKey: lastPingKey)
    }
}
