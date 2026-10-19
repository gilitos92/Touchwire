import Foundation
import Sparkle

/// Sparkle auto-updates. Sparkle checks the appcast in Info.plist (`SUFeedURL`, attached to the latest GitHub
/// release) and only installs downloads signed with the EdDSA key whose public half is `SUPublicEDKey`.
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        // Unbundled runs (`swift run`) have no feed, so the updater stays off.
        controller = SPUStandardUpdaterController(startingUpdater: Bundle.main.bundleIdentifier != nil,
                                                  updaterDelegate: self, userDriverDelegate: nil)
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        // Tells the protection service the app is stopping on purpose. The relaunched app clears the marker.
        FileManager.default.createFile(atPath: Config.quitMarkerURL.path, contents: Data())
        EventLog.shared.write("update.installing", ["version": item.displayVersionString])
    }
}
