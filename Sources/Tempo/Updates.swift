import SwiftUI
import Combine
import Sparkle

/// Sparkle owns update checks, signature verification, download, installation, and relaunch.
@MainActor final class UpdateManager: ObservableObject {
    @Published private(set) var canCheck = false
    let controller: SPUStandardUpdaterController?
    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        guard Bundle.main.bundleURL.pathExtension == "app",
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = info["SUFeedURL"] as? String,
              URL(string: feed)?.scheme == "https" else { controller = nil; return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }
    func check() { controller?.checkForUpdates(nil) }
}
struct UpdateCommands: Commands {
    @ObservedObject var manager: UpdateManager
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { manager.check() }.disabled(!manager.canCheck)
        }
    }
}
