import Foundation
import Observation
import FinanceCore

enum Section: Hashable { case overview, transactions, investments, analytics, settings }

/// What the Transactions list should show when opened from elsewhere (e.g. a category row in Overview).
struct TransactionFilter: Equatable {
    var categoryId: UUID?
}

@MainActor @Observable
final class AppModel {
    var data = FinanceData.defaults()
    var loadError: String?
    var saveError: String?
    var month = Day.today().yearMonth
    var closes: [UUID: [Day: Decimal]] = [:]
    var refreshing = false
    var priceError: String?
    var section: Section = .overview
    var filter = TransactionFilter()
    var showQuickAdd = false
    var locked = true
    var lockMessage: String?
    var needsRecovery = false
    var snapshotTab: Int?                // snapshot hook only: ⌘N tab to open
    var snapshotAddHolding: String?      // snapshot hook only: open Add holding with this query

    let store: Store
    let cache: PriceCache
    private var started = false

    init(store: Store = Store(directory: Store.defaultDirectory, key: nil)) {
        self.store = store
        self.cache = PriceCache(directory: store.directory.appendingPathComponent("prices"))
        let env = ProcessInfo.processInfo.environment
        // Test mode only: a throwaway data folder may skip the lock screen.
        if env["FINANCES_DATA_DIR"] != nil && env["FINANCES_NO_LOCK"] == "1" { locked = false }
    }

    /// Writes are allowed only while unlocked, with a key, and with a readable data file.
    private var canWrite: Bool { !locked && loadError == nil && store.key != nil }

    func unlock() async {
        guard locked else { return }
        if let err = await Auth.verify("unlock your finances") { lockMessage = err; return }
        lockMessage = nil
        locked = false
        await start()
    }

    /// Forgets everything in memory; the next unlock reads the file again.
    func lock() {
        guard !locked else { return }
        locked = true
        started = false
        showQuickAdd = false
        data = .defaults()
        closes = [:]
        store.key = nil
        loadError = nil
        needsRecovery = false
    }

    func start() async {
        guard !started, !locked else { return }
        started = true
        do {
            if let key = try KeyStore.load() {
                store.key = key
            } else if store.isEncrypted {
                needsRecovery = true
                loadError = "This Mac's keychain has no key for your data. Enter your recovery key to open it."
                return
            } else {
                store.key = try KeyStore.create()
            }
        } catch {
            loadError = "The data key couldn't be read from the keychain: \(error)"
            return
        }
        do { data = try store.load() } catch {
            if case StoreError.unreadable(_, let why) = error, why.contains("decrypted") { needsRecovery = true }
            loadError = "\(store.dataURL.path) could not be read. Nothing has been changed or saved.\n\n\(error)"
            return
        }
        if generateRecurring(&data, today: .today()) > 0 { save() }
        for h in data.holdings { closes[h.id] = cache.load(h.ticker) }
        if fillEstimatedUnits(&data, closes: closes) > 0 { save() }
        // Not awaited: start() runs inside the lock screen's task, which SwiftUI cancels as soon as
        // the screen disappears, and that cancellation would abort the downloads (NSURLError -999).
        Task { await refreshPrices() }
    }

    /// Every change goes through here. Does nothing while the data file is unreadable.
    func update(_ change: (inout FinanceData) -> Void) {
        guard canWrite else { return }
        change(&data)
        generateRecurring(&data, today: .today())
        fillEstimatedUnits(&data, closes: closes)
        save()
    }

    private func save() {
        guard canWrite else { return }
        do { try store.save(data) } catch { saveError = "Could not save \(store.dataURL.path): \(error.localizedDescription)" }
    }

    func refreshPrices() async {
        guard canWrite, !refreshing, !data.holdings.isEmpty else { return }
        refreshing = true
        defer { refreshing = false }
        var failures: [String] = []
        for h in data.holdings {
            var c = cache.load(h.ticker)
            let firstTrade = data.trades.filter { $0.holdingId == h.id }.map(\.date).min()
            let from: Day?
            if let ft = firstTrade, c.keys.min().map({ $0 > ft }) ?? true {
                from = ft.adding(days: -7)   // a few days before, so a weekend/holiday plan date finds a close
            } else {
                from = c.keys.max()?.adding(days: -7)
            }
            do {
                let q = try await Yahoo.chart(h.ticker, from: from)
                c.merge(q.closes) { _, new in new }
                cache.save(h.ticker, c)
                closes[h.id] = c
                if let i = data.holdings.firstIndex(where: { $0.id == h.id }) {
                    data.holdings[i].lastPrice = q.price
                    data.holdings[i].lastPriceDate = q.closes.keys.max() ?? .today()
                }
            } catch is CancellationError {
                continue
            } catch let e as URLError where e.code == .cancelled {
                continue
            } catch let e as PriceError {
                failures.append("\(h.ticker): \(e.description)")
            } catch {
                failures.append("\(h.ticker): \(error.localizedDescription)")
            }
        }
        guard canWrite else { return }   // locked while prices were loading
        fillEstimatedUnits(&data, closes: closes)
        save()
        priceError = failures.isEmpty ? nil : "Couldn't update prices (\(failures.joined(separator: "; "))). Showing the last known prices."
    }

    /// Opens the data with a recovery key and stores that key in the keychain.
    func useRecovery(_ text: String) -> String? {
        guard let key = parseRecovery(text) else { return "That isn't a recovery key. It has 64 characters in groups of four." }
        let probe = Store(directory: store.directory, key: key)
        do { _ = try probe.load() } catch { return "This recovery key doesn't open the data." }
        do { try KeyStore.store(key) } catch { return "Couldn't save the key to the keychain: \(error)" }
        loadError = nil
        needsRecovery = false
        started = false
        Task { await start() }
        return nil
    }

    /// The recovery key, after asking for Touch ID or the password again.
    func revealRecoveryKey() async -> String? {
        guard let key = store.key, await Auth.verify("show your recovery key") == nil else { return nil }
        return recoveryText(key)
    }

    func useBackup() {
        do {
            data = try store.loadBackup()
            loadError = nil
            save()
            started = false
            Task { await start() }
        } catch {
            loadError = (loadError ?? "") + "\n\nThe backup could not be read either: \(error)"
        }
    }

    // Small lookups the views share.
    func categories(_ kind: Kind) -> [TxCategory] { data.categories.filter { $0.kind == kind } }
    func positions() -> [Position] { data.holdings.map { position(of: $0, trades: data.trades) } }
}
