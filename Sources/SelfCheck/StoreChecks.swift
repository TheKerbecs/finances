import Foundation
import FinanceCore
import CryptoKit

func rawKey(_ k: SymmetricKey) -> Data { k.withUnsafeBytes { Data($0) } }

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("finances-check-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func runStoreChecks() {
    let fm = FileManager.default

    // missing file: defaults, nothing created
    let empty = Store(directory: tempDir().appendingPathComponent("sub"), key: SymmetricKey(size: .bits256))
    let d0 = try! empty.load()
    precondition(d0.categories.count == 13 && d0.transactions.isEmpty)
    precondition(!fm.fileExists(atPath: empty.dataURL.path) && !fm.fileExists(atPath: empty.backupURL.path))

    // round trip + backup
    let key = SymmetricKey(size: .bits256)
    let s = Store(directory: tempDir(), key: key)
    var d = FinanceData.defaults()
    d.transactions = [Transaction(date: Day("2026-11-02")!, amount: Decimal(string: "12.5")!, kind: .expense, categoryId: d.categories[1].id, payee: "Rewe")]
    d.trades = [Trade(holdingId: UUID(), date: Day("2026-11-02")!, side: .buy, amount: Decimal(string: "0.1")!, units: Decimal(string: "3.319502")!, pricePerUnit: Decimal(string: "125.825")!)]
    try! s.save(d)
    precondition(try! s.load() == d)
    // encrypted at rest: neither file contains readable JSON
    for url in [s.dataURL, s.backupURL] {
        let raw = try! Data(contentsOf: url)
        precondition(raw.starts(with: Data("FINENC1".utf8)) && raw.range(of: Data("Rewe".utf8)) == nil)
    }
    precondition(try! s.loadBackup() == d)

    // wrong key: throws, files untouched
    let before = try! Data(contentsOf: s.dataURL)
    let wrong = Store(directory: s.directory, key: SymmetricKey(size: .bits256))
    if (try? wrong.load()) != nil { preconditionFailure("wrong key must not load") }
    precondition(try! Data(contentsOf: s.dataURL) == before)

    // no key yet: load refuses instead of returning defaults over an existing file
    let nokey = Store(directory: s.directory, key: nil)
    if (try? nokey.load()) != nil { preconditionFailure("load without key must throw") }

    // plaintext file from before encryption: loads and is rewritten encrypted, backup too
    let legacy = Store(directory: tempDir(), key: key)
    try! FileManager.default.createDirectory(at: legacy.directory, withIntermediateDirectories: true)
    try! JSONEncoder().encode(d).write(to: legacy.dataURL)
    precondition(legacy.hasData && !legacy.isEncrypted)   // first launch after the update: make a key, don't ask for recovery
    precondition(try! legacy.load() == d)
    precondition(legacy.isEncrypted)
    precondition(try! Data(contentsOf: legacy.dataURL).starts(with: Data("FINENC1".utf8)))
    precondition(try! Data(contentsOf: legacy.backupURL).starts(with: Data("FINENC1".utf8)))
    precondition(try! legacy.load() == d)

    // recovery key round trip, tolerant of spaces, dashes and case
    let text = recoveryText(key)
    precondition(text.count == 79)   // 16 groups of 4 hex chars joined by "-"
    precondition(parseRecovery(text).map(rawKey) == rawKey(key))
    precondition(parseRecovery(text.uppercased().replacingOccurrences(of: "-", with: " ")).map(rawKey) == rawKey(key))
    precondition(parseRecovery("abcd") == nil)

    // corrupt file: throws, touches neither file
    try! s.save(d)
    _ = try! s.load()
    try! Data("{garbage".utf8).write(to: s.dataURL)
    do { _ = try s.load(); preconditionFailure("corrupt load must throw") }
    catch StoreError.unreadable(let url, _) { precondition(url == s.dataURL) }
    catch { preconditionFailure("wrong error \(error)") }
    precondition(String(data: try! Data(contentsOf: s.dataURL), encoding: .utf8) == "{garbage")
    precondition(try! s.loadBackup() == d)
}
