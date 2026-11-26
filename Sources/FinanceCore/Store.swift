import Foundation
import CryptoKit

public enum StoreError: Error { case unreadable(URL, String), noKey }

private let magic = Data("FINENC1".utf8)

/// The whole model as one AES-GCM encrypted JSON file. Load copies a good file to data.prev.json;
/// a file that fails to decrypt or decode is never overwritten or copied. A plaintext file from
/// before encryption is read once and rewritten encrypted.
public final class Store {
    public let directory: URL
    public var key: SymmetricKey?
    public var dataURL: URL { directory.appendingPathComponent("data.json") }
    public var backupURL: URL { directory.appendingPathComponent("data.prev.json") }

    public init(directory: URL, key: SymmetricKey?) { self.directory = directory; self.key = key }

    /// ~/Library/Application Support/Finances, or $FINANCES_DATA_DIR when set (for testing).
    public static var defaultDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["FINANCES_DATA_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Finances")
    }

    public var hasData: Bool { FileManager.default.fileExists(atPath: dataURL.path) }

    /// True when data.json is in the encrypted format (so it needs the existing key).
    public var isEncrypted: Bool {
        guard let h = FileHandle(forReadingAtPath: dataURL.path) else { return false }
        defer { try? h.close() }
        return (try? h.read(upToCount: magic.count)) == magic
    }

    public func load() throws -> FinanceData {
        guard let key else { throw StoreError.noKey }
        guard hasData else { return .defaults() }
        let (data, wasPlain) = try read(dataURL, key)
        if wasPlain { try write(data, to: dataURL, key) }
        try write(data, to: backupURL, key)
        return data
    }

    public func loadBackup() throws -> FinanceData {
        guard let key else { throw StoreError.noKey }
        return try read(backupURL, key).0
    }

    public func save(_ d: FinanceData) throws {
        guard let key else { throw StoreError.noKey }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(d, to: dataURL, key)
    }

    private func read(_ url: URL, _ key: SymmetricKey) throws -> (FinanceData, Bool) {
        do {
            let raw = try Data(contentsOf: url)
            if raw.starts(with: magic) {
                let box = try AES.GCM.SealedBox(combined: raw.dropFirst(magic.count))
                return (try JSONDecoder().decode(FinanceData.self, from: AES.GCM.open(box, using: key)), false)
            }
            return (try JSONDecoder().decode(FinanceData.self, from: raw), true)
        } catch let e as CryptoKitError {
            throw StoreError.unreadable(url, "It could not be decrypted with this Mac's key (\(e)).")
        } catch {
            throw StoreError.unreadable(url, "\(error)")
        }
    }

    private func write(_ d: FinanceData, to url: URL, _ key: SymmetricKey) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let sealed = try AES.GCM.seal(enc.encode(d), using: key)
        try (magic + sealed.combined!).write(to: url, options: .atomic)
    }
}

/// The key as 16 groups of 4 hex characters, for a password manager.
public func recoveryText(_ key: SymmetricKey) -> String {
    let hex = key.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
    return stride(from: 0, to: hex.count, by: 4).map { i in
        String(hex[hex.index(hex.startIndex, offsetBy: i)..<hex.index(hex.startIndex, offsetBy: i + 4)])
    }.joined(separator: "-")
}

/// Reads a recovery key back; ignores spaces, dashes and case.
public func parseRecovery(_ s: String) -> SymmetricKey? {
    let hex = s.lowercased().filter { $0.isHexDigit }
    guard hex.count == 64, s.filter({ !$0.isHexDigit && $0 != "-" && !$0.isWhitespace }).isEmpty else { return nil }
    var bytes = [UInt8]()
    var i = hex.startIndex
    while i < hex.endIndex {
        let j = hex.index(i, offsetBy: 2)
        bytes.append(UInt8(hex[i..<j], radix: 16)!)
        i = j
    }
    return SymmetricKey(data: bytes)
}
