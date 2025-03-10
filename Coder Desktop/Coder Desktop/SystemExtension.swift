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

        // Extension bundle identifier - must match what's used in the app
        let extensionBundleIdentifier = "com.coder.Coder-Desktop.VPN"

        return await withCheckedContinuation { continuation in
            // Create a task to handle the deregistration with timeout
            let timeoutTask = Task {
                // Set a timeout for the operation
                let timeoutInterval: TimeInterval = 30.0 // 30 seconds

                // Use a custom holder for the delegate to keep it alive
                // and store the result from the callback
                final class DelegateHolder {
                    var delegate: DeregistrationDelegate?
                    var result: Bool?
                }

                let holder = DelegateHolder()

                // Create the delegate with a completion handler
                let delegate = DeregistrationDelegate(completionHandler: { result in
                    holder.result = result
                })
                holder.delegate = delegate

                // Create and submit the deactivation request
                let request = OSSystemExtensionRequest.deactivationRequest(
                    forExtensionWithIdentifier: extensionBundleIdentifier,
                    queue: .main
                )
                request.delegate = delegate

                // Submit the request on the main thread
                await MainActor.run {
                    OSSystemExtensionManager.shared.submitRequest(request)
                }

                // Set up timeout using a separate task
                let timeoutDate = Date().addingTimeInterval(timeoutInterval)

                // Wait for completion or timeout
                while holder.result == nil, Date() < timeoutDate {
                    // Sleep a bit before checking again (100ms)
                    try? await Task.sleep(nanoseconds: 100_000_000)

                    // Check for cancellation
                    if Task.isCancelled {
                        break
                    }
                }

                // Handle the result
                if let result = holder.result {
                    logger.info("System extension deregistration completed with result: \(result)")
                    return result
                } else {
                    logger.error("System extension deregistration timed out after \(timeoutInterval) seconds")
                    return false
                }
            }

            // Use Task.detached to handle potential continuation issues
            Task.detached {
                let result = await timeoutTask.value
                continuation.resume(returning: result)
            }
        }
    }

    // A dedicated delegate class for system extension deregistration
    private class DeregistrationDelegate: NSObject, OSSystemExtensionRequestDelegate {
        private var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "vpn-deregistrar")
        private var completionHandler: (Bool) -> Void

        init(completionHandler: @escaping (Bool) -> Void) {
            self.completionHandler = completionHandler
            super.init()
        }

        func request(_: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
            switch result {
            case .completed:
                logger.info("System extension was successfully deregistered")
                completionHandler(true)
            case .willCompleteAfterReboot:
                logger.info("System extension will be deregistered after reboot")
                completionHandler(true)
            @unknown default:
                logger.error("System extension deregistration completed with unknown result")
                completionHandler(false)
            }
        }

        func request(_: OSSystemExtensionRequest, didFailWithError error: Error) {
            logger.error("System extension deregistration failed: \(error.localizedDescription)")
            completionHandler(false)
        }

        func requestNeedsUserApproval(_: OSSystemExtensionRequest) {
            logger.info("System extension deregistration needs user approval")
            // We don't complete here, as we'll get another callback when approval is granted or denied
        }

        func request(
            _: OSSystemExtensionRequest,
            actionForReplacingExtension _: OSSystemExtensionProperties,
            withExtension _: OSSystemExtensionProperties
        ) -> OSSystemExtensionRequest.ReplacementAction {
            logger.info("System extension replacement request")
            return .replace
        }
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
