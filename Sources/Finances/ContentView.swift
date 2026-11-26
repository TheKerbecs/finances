import SwiftUI
import FinanceCore

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if model.locked {
            LockView().preferredColorScheme(.dark)
        } else {
            main
        }
    }

    private var main: some View {
        @Bindable var model = model
        return NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 230, max: 280)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            if let err = model.loadError {
                LoadErrorView(message: err)
            } else {
                switch model.section {
                case .overview: OverviewView()
                case .transactions: TransactionsView()
                case .investments: InvestmentsView()
                case .analytics: AnalyticsView()
                case .settings: SettingsView()
                }
            }
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .tint(SeriesColor.invested)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .sheet(isPresented: $model.showQuickAdd) { NewEntrySheet().environment(model) }
        .alert("Save failed", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
            Button("OK") {}
        } message: { Text(model.saveError ?? "") }
    }
}

struct LoadErrorView: View {
    @Environment(AppModel.self) private var model
    var message: String
    @Local private var recovery = ""
    @Local private var recoveryError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your data can't be opened", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(SeriesColor.spent)
            Text(message).textSelection(.enabled).font(.system(size: 13)).foregroundStyle(Theme.text)
            Text("Nothing has been changed or saved.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            if model.needsRecovery {
                Field(label: "Recovery key") {
                    TextField("", text: $recovery, prompt: Text("xxxx-xxxx-…").foregroundColor(Theme.tertiary))
                        .font(.system(size: 13, design: .monospaced)).inputStyle()
                }
                if let recoveryError { Text(recoveryError).font(.system(size: 12)).foregroundStyle(Theme.loss) }
                Button("Open with recovery key") { recoveryError = model.useRecovery(recovery) }
                    .buttonStyle(PrimaryButton()).disabled(recovery.isEmpty)
            } else {
                HStack {
                    Button("Load backup (data.prev.json)") { model.useBackup() }.buttonStyle(PrimaryButton())
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.dataURL]) }
                        .buttonStyle(SecondaryButton())
                }
            }
        }
        .padding(40)
        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
    }
}
