// Sparkle: checks the feed on open and daily, and installs updates (`SUFeedURL` and `SUPublicEDKey` in Info.plist).
#if os(macOS)
import Sparkle

final class Updater {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    init() {
        controller.updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
