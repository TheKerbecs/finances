import SwiftUI
import FinanceCore

@main
struct FinancesApp: App {
    @Local private var model = AppModel()
    @Local private var autoLock: AutoLock?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    if autoLock == nil { autoLock = AutoLock(model) }
                    snapshotIfRequested(model)
                    await model.start()   // no-op while locked; LockView asks for Touch ID
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Entry…") { model.showQuickAdd = true }
                    .keyboardShortcut("n")
                    .disabled(model.loadError != nil || model.locked)
            }
            CommandGroup(after: .newItem) {
                Button("Lock") { model.lock() }
                    .keyboardShortcut("l")
                    .disabled(model.locked)
            }
        }
    }
}
