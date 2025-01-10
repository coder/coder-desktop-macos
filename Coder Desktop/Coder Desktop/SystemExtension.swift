import Foundation
import os
import SystemExtensions

enum SystemExtensionState: Equatable, Sendable {
    case uninstalled
    case needsUserApproval
    case installed
    case failed(String)

    var description: String {
        switch self {
        case .uninstalled:
            return "VPN SystemExtension is waiting to be activated"
        case .needsUserApproval:
            return "VPN SystemExtension needs user approval to activate"
        case .installed:
            return "VPN SystemExtension is installed"
        case let .failed(error):
            return "VPN SystemExtension failed with error: \(error)"
        }
    }
}

protocol SystemExtensionAsyncRecorder: Sendable {
    func recordSystemExtensionState(_ state: SystemExtensionState) async
}

extension CoderVPNService: SystemExtensionAsyncRecorder {
    func recordSystemExtensionState(_ state: SystemExtensionState) async {
        sysExtnState = state
    }

    var extensionBundle: Bundle {
        let extensionsDirectoryURL = URL(
            fileURLWithPath: "Contents/Library/SystemExtensions",
            relativeTo: Bundle.main.bundleURL
        )
        let extensionURLs: [URL]
        do {
            extensionURLs = try FileManager.default.contentsOfDirectory(at: extensionsDirectoryURL,
                                                                        includingPropertiesForKeys: nil,
                                                                        options: .skipsHiddenFiles)
        } catch {
            fatalError("Failed to get the contents of " +
                "\(extensionsDirectoryURL.absoluteString): \(error.localizedDescription)")
        }

        // here we're just going to assume that there is only ever going to be one SystemExtension
        // packaged up in the application bundle. If we ever need to ship multiple versions or have
        // multiple extensions, we'll need to revisit this assumption.
        guard let extensionURL = extensionURLs.first else {
            fatalError("Failed to find any system extensions")
        }

        guard let extensionBundle = Bundle(url: extensionURL) else {
            fatalError("Failed to create a bundle with URL \(extensionURL.absoluteString)")
        }

        return extensionBundle
    }

    func installSystemExtension() {
        logger.info("activating SystemExtension")
        guard let bundleID = extensionBundle.bundleIdentifier else {
            logger.error("Bundle has no identifier")
            return
        }
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: bundleID,
            queue: .main
        )
        let delegate = SystemExtensionDelegate(asyncDelegate: self)
        request.delegate = delegate
        OSSystemExtensionManager.shared.submitRequest(request)
        logger.info("submitted SystemExtension request with bundleID: \(bundleID)")
    }
}

/// A delegate for the OSSystemExtensionRequest that maps the callbacks to async calls on the
/// AsyncDelegate (CoderVPNService in production).
class SystemExtensionDelegate<AsyncDelegate: SystemExtensionAsyncRecorder>:
    NSObject, OSSystemExtensionRequestDelegate
{
    private var logger = Logger(subsystem: "com.coder.Coder-Desktop", category: "vpn-installer")
    private var asyncDelegate: AsyncDelegate

    init(asyncDelegate: AsyncDelegate) {
        self.asyncDelegate = asyncDelegate
        logger.info("SystemExtensionDelegate initialized")
    }

    func request(
        _: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        guard result == .completed else {
            logger.error("Unexpected result \(result.rawValue) for system extension request")
            let state = SystemExtensionState.failed("system extension not installed: \(result.rawValue)")
            Task { [asyncDelegate] in
                await asyncDelegate.recordSystemExtensionState(state)
            }
            return
        }
        logger.info("SystemExtension activated")
        Task { [asyncDelegate] in
            await asyncDelegate.recordSystemExtensionState(SystemExtensionState.installed)
        }
    }

    func request(_: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error("System extension request failed: \(error.localizedDescription)")
        Task { [asyncDelegate] in
            await asyncDelegate.recordSystemExtensionState(
                SystemExtensionState.failed(error.localizedDescription))
        }
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.error("Extension \(request.identifier) requires user approval")
        Task { [asyncDelegate] in
            await asyncDelegate.recordSystemExtensionState(SystemExtensionState.needsUserApproval)
        }
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension extension: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        // swiftlint: disable line_length
        logger.info("Replacing \(request.identifier) v\(existing.bundleShortVersion) with v\(`extension`.bundleShortVersion)")
        // swiftlint: enable line_length
        return .replace
    }
}
