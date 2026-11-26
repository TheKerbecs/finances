import AppKit

/// FINANCES_SNAPSHOT=/path.png [FINANCES_SNAPSHOT_SECTION=overview]: render the window to a PNG and quit.
/// Lets the UI be checked from a terminal without screen-recording permission.
@MainActor
func snapshotIfRequested(_ model: AppModel) {
    let env = ProcessInfo.processInfo.environment
    guard let path = env["FINANCES_SNAPSHOT"] else { return }
    switch env["FINANCES_SNAPSHOT_SECTION"] {
    case "transactions": model.section = .transactions
    case "investments": model.section = .investments
    case "analytics", "trends": model.section = .analytics
    case "settings": model.section = .settings
    case "quickadd": model.showQuickAdd = true
    case "trade": model.showQuickAdd = true; model.snapshotTab = 1
    case "transfer": model.showQuickAdd = true; model.snapshotTab = 3
    case "addholding": model.section = .investments; model.snapshotAddHolding = env["FINANCES_SNAPSHOT_QUERY"] ?? ""
    default: model.section = .overview
    }
    if let h = env["FINANCES_SNAPSHOT_HEIGHT"].flatMap(Double.init) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApp.windows.first { $0.isVisible }?.setContentSize(NSSize(width: Double(env["FINANCES_SNAPSHOT_WIDTH"] ?? "") ?? 1000, height: h))
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + (env["FINANCES_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 4)) {
        let sheet = NSApp.windows.first { $0.isSheet && $0.isVisible }
        guard let window = sheet ?? NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        exit(0)
    }
}
