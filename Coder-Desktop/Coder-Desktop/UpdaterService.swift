import Sparkle
import SwiftUI

final class UpdaterService: NSObject, ObservableObject {
    private lazy var inner: SPUStandardUpdaterController = .init(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: self
    )
    private var updater: SPUUpdater!
    @Published var canCheckForUpdates = true

    @Published var autoCheckForUpdates: Bool! {
        didSet {
            if let autoCheckForUpdates, autoCheckForUpdates != oldValue {
                updater.automaticallyChecksForUpdates = autoCheckForUpdates
            }
        }
    }

    @Published var updateChannel: UpdateChannel {
        didSet {
            UserDefaults.standard.set(updateChannel.rawValue, forKey: Self.updateChannelKey)
        }
    }

    static let updateChannelKey = "updateChannel"

    override init() {
        updateChannel = UserDefaults.standard.string(forKey: Self.updateChannelKey)
            .flatMap { UpdateChannel(rawValue: $0) } ?? .stable
        super.init()
        updater = inner.updater
        autoCheckForUpdates = updater.automaticallyChecksForUpdates
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updater.checkForUpdates()
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
