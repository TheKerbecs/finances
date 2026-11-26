import SwiftUI
import FinanceCore

/// Shown until Touch ID or the Mac password unlocks the app.
struct LockView: View {
    @Environment(AppModel.self) private var model
    @Local private var asking = false

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            Text("Finances is locked").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
            Text("Use Touch ID or your Mac password to open it.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            Button { Task { await ask() } } label: {
                Label("Unlock", systemImage: "touchid")
            }
            .buttonStyle(PrimaryButton())
            .keyboardShortcut(.defaultAction)
            .disabled(asking)
            if let msg = model.lockMessage {
                Text(msg).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .task { if ProcessInfo.processInfo.environment["FINANCES_SNAPSHOT"] == nil { await ask() } }
    }

    private func ask() async {
        guard !asking else { return }
        asking = true
        await model.unlock()
        asking = false
    }
}

/// Watches for sleep and screen lock, and locks the app.
@MainActor
final class AutoLock {
    private var tokens: [NSObjectProtocol] = []

    init(_ model: AppModel) {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            tokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { model.lock() } })
        }
        tokens.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { model.lock() }
        })
    }
}
