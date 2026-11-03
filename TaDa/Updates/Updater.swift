// Sparkle: checks the feed on open and daily, and installs updates (`SUFeedURL` and `SUPublicEDKey` in Info.plist). Debug builds don't start it.
#if os(macOS)
import Combine
import Observation
import Sparkle

@Observable
final class Updater {
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var subscription: AnyCancellable?

    init() {
        #if DEBUG
        let start = false
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
        subscription = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
        #if !DEBUG
        controller.updater.checkForUpdatesInBackground()
        #endif
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
