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
            "VPN SystemExtension is waiting to be activated"
        case .needsUserApproval:
            "VPN SystemExtension needs user approval to activate"
        case .installed:
            "VPN SystemExtension is installed"
        case let .failed(error):
            "VPN SystemExtension failed with error: \(error)"
        }
    }
}

protocol SystemExtensionAsyncRecorder: Sendable {
    func recordSystemExtensionState(_ state: SystemExtensionState) async
}

extension CoderVPNService: SystemExtensionAsyncRecorder {
    func recordSystemExtensionState(_ state: SystemExtensionState) async {
        sysExtnState = state
        logger.info("system extension state: \(state.description)")
        if state == .installed {
            // system extension was successfully installed, so we don't need the delegate any more
            systemExtnDelegate = nil
        }
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
        systemExtnDelegate = delegate
        request.delegate = delegate
        OSSystemExtensionManager.shared.submitRequest(request)
        logger.info("submitted SystemExtension request with bundleID: \(bundleID)")
    }

    func deregisterSystemExtension() async -> Bool {
        logger.info("Starting network extension deregistration...")

        // Use the existing delegate pattern
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // Extension bundle identifier - must match what's used in the app
            guard let bundleID = extensionBundle.bundleIdentifier else {
                logger.error("Bundle has no identifier")
                continuation.resume(returning: false)
                return
            }

            // Set a temporary state for deregistration
            sysExtnState = .uninstalled

            // Create a special delegate that will handle the deregistration and resolve the continuation
            let delegate = SystemExtensionDelegate(asyncDelegate: self)
            systemExtnDelegate = delegate

            // Create the deactivation request
            let request = OSSystemExtensionRequest.deactivationRequest(
                forExtensionWithIdentifier: bundleID,
                queue: .main
            )
            request.delegate = delegate

            // Start a timeout task
            Task {
                // Allow up to 30 seconds for deregistration
                try? await Task.sleep(for: .seconds(30))

                // If we're still waiting after timeout, consider it failed
                if case .uninstalled = self.sysExtnState {
                    // Only update if still in uninstalled state (meaning callback never updated it)
                    self.sysExtnState = .failed("Deregistration timed out")
                    continuation.resume(returning: false)
                }
            }

            // Submit the request and wait for the delegate to handle completion
            OSSystemExtensionManager.shared.submitRequest(request)
            logger.info("Submitted system extension deregistration request for \(bundleID)")

            // The SystemExtensionDelegate will update our state via recordSystemExtensionState
            // We'll monitor this in another task to resolve the continuation
            Task {
                // Check every 100ms for state changes
                for _ in 0 ..< 300 { // 30 seconds max
                    // If state changed from uninstalled, the delegate has processed the result
                    if case .installed = self.sysExtnState {
                        // This should never happen during deregistration
                        continuation.resume(returning: false)
                        break
                    } else if case .failed = self.sysExtnState {
                        // Failed state was set by delegate
                        continuation.resume(returning: false)
                        break
                    } else if case .uninstalled = self.sysExtnState, self.systemExtnDelegate == nil {
                        // Uninstalled AND delegate is nil means success (delegate cleared itself)
                        continuation.resume(returning: true)
                        break
                    }

                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        return result
    }
}

/// A delegate for the OSSystemExtensionRequest that maps the callbacks to async calls on the
/// AsyncDelegate (CoderVPNService in production).
class SystemExtensionDelegate<AsyncDelegate: SystemExtensionAsyncRecorder>:
    NSObject, OSSystemExtensionRequestDelegate
{
    private var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "vpn-installer")
    private var asyncDelegate: AsyncDelegate

    init(asyncDelegate: AsyncDelegate) {
        self.asyncDelegate = asyncDelegate
        super.init()
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
        // swiftlint:disable:next line_length
        logger.info("Replacing \(request.identifier) v\(existing.bundleShortVersion) with v\(`extension`.bundleShortVersion)")
        return .replace
    }
}
