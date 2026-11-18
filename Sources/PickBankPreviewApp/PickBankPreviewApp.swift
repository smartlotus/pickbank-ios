import PickBankCore
import PickBankUI
import SwiftUI

@main
struct PickBankPreviewApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("PickBank 拾念记账") {
            AdaptiveRootShell(viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 760)
        }
    }
}
