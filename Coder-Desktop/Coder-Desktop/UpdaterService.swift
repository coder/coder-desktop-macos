import Sparkle
import SwiftUI

final class UpdaterService: NSObject, ObservableObject {
    // The auto-updater can be entirely disabled by setting the
    // `disableUpdater` UserDefaults key to `true`. This is designed for use in
    // MDM configurations, where the value can be set to `true` permanently.
    let disabled: Bool = UserDefaults.standard.bool(forKey: Keys.disableUpdater)

    @Published var canCheckForUpdates = true

    @Published var autoCheckForUpdates: Bool! {
        didSet {
            if let autoCheckForUpdates, autoCheckForUpdates != oldValue {
                inner?.updater.automaticallyChecksForUpdates = autoCheckForUpdates
            }
        }
    }

    @Published var updateChannel: UpdateChannel {
        didSet {
            UserDefaults.standard.set(updateChannel.rawValue, forKey: Keys.updateChannel)
        }
    }

    private var inner: (controller: SPUStandardUpdaterController, updater: SPUUpdater)?

    override init() {
        updateChannel = UserDefaults.standard.string(forKey: Keys.updateChannel)
            .flatMap { UpdateChannel(rawValue: $0) } ?? .stable
        super.init()

        guard !disabled else {
            return
        }

        let inner = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )

        let updater = inner.updater
        self.inner = (inner, updater)

        autoCheckForUpdates = updater.automaticallyChecksForUpdates
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        guard let inner, canCheckForUpdates else { return }
        inner.updater.checkForUpdates()
    }

    enum Keys {
        static let disableUpdater = "disableUpdater"
        static let updateChannel = "updateChannel"
    }
}

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case preview

    var name: String {
        switch self {
        case .stable:
            "Stable"
        case .preview:
            "Preview"
        }
    }

    var id: String { rawValue }
}

extension UpdaterService: SPUUpdaterDelegate {
    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        // There's currently no point in subscribing to both channels, as
        // preview >= stable
        [updateChannel.rawValue]
    }

    func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
        Task { @MainActor in appActivate() }
    }
}

extension UpdaterService: SUVersionDisplay {
    func formatUpdateVersion(
        fromUpdate update: SUAppcastItem,
        andBundleDisplayVersion inOutBundleDisplayVersion: AutoreleasingUnsafeMutablePointer<NSString>,
        withBundleVersion bundleVersion: String
    ) -> String {
        // Replace CFBundleShortVersionString with CFBundleVersion, as the
        // latter shows build numbers.
        inOutBundleDisplayVersion.pointee = bundleVersion as NSString
        // This is already CFBundleVersion, as that's the only version in the
        // appcast.
        return update.displayVersionString
    }
}

extension UpdaterService: SPUStandardUserDriverDelegate {
    func standardUserDriverRequestsVersionDisplayer() -> (any SUVersionDisplay)? {
        self
    }
}
