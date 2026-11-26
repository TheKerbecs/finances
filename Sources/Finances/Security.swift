import Foundation
import CryptoKit
import LocalAuthentication
import Security

/// The data key lives in the login keychain. In test mode (FINANCES_DATA_DIR set) it's a file in
/// that folder instead, so tests never touch the real keychain item.
enum KeyStore {
    private static let service = "local.finances.app"
    private static let account = "data-key"

    private static var testKeyURL: URL? {
        guard let dir = ProcessInfo.processInfo.environment["FINANCES_DATA_DIR"], !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: dir).appendingPathComponent("test.key")
    }

    struct KeychainError: Error, CustomStringConvertible {
        var status: OSStatus
        var description: String { (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)" }
    }

    static func load() throws -> SymmetricKey? {
        if let url = testKeyURL { return (try? Data(contentsOf: url)).map { SymmetricKey(data: $0) } }
        var out: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                          kSecAttrAccount: account, kSecReturnData: true] as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError(status: status) }
        return SymmetricKey(data: data)
    }

    static func create() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        try store(key)
        return key
    }

    /// Saves (or replaces) the key, e.g. after entering a recovery key.
    static func store(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        if let url = testKeyURL {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return
        }
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary
        SecItemDelete(query)
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                                 kSecAttrLabel: "Finances data key", kSecValueData: data] as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

/// Touch ID, or the Mac password when Touch ID isn't available or fails.
enum Auth {
    static func verify(_ reason: String) async -> String? {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            return err?.localizedDescription ?? "This Mac can't verify you."
        }
        do {
            try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
