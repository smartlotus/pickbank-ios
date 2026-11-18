import PickBankCore
import PickBankUI
import SwiftUI
#if os(iOS)
import BackgroundTasks
#endif

@main
struct PickBankApp: App {
    @StateObject private var viewModel = AppViewModel()
    @Environment(\.scenePhase) private var scenePhase

    private let backupTaskId = "com.smartlotus.pickbank.autobackup"

    init() {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backupTaskId, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let baseDir = docs.appendingPathComponent("PickBank", isDirectory: true)
                if let store = try? PickBankStore(baseDirectory: baseDir) {
                    let scheduler = AutoBackupScheduler(store: store)
                    let pwd = KeychainHelper().loadSecret(account: "auto_backup_pwd")
                    _ = try? await scheduler.runScheduledCheckIfDue(password: pwd)
                }
                refreshTask.setTaskCompleted(success: true)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AdaptiveRootShell(viewModel: viewModel)
                .onOpenURL { url in
                    Task { await viewModel.handlePickedImportURL(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await viewModel.bootstrap() }
            case .background:
                Task {
                    await viewModel.triggerScheduledBackupIfDue(onBackground: true)
                    scheduleNextBackgroundBackup()
                }
            default:
                break
            }
        }
        .commands {
            CommandMenu("PickBank") {
                Button("记一笔") {
                    viewModel.editingTransaction = nil
                    viewModel.showManualSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("快速自然语言记账") {
                    viewModel.selectedTab = .home
                    viewModel.shouldFocusNlpBar = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("立即本地备份") {
                    Task { await viewModel.createBackupNow(pin: false) }
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("切换主题 (Warm Dark / Hermes)") {
                    Task { await viewModel.toggleTheme() }
                }
                .keyboardShortcut("t", modifiers: .command)
            }
        }
    }

    private func scheduleNextBackgroundBackup() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: backupTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
}
