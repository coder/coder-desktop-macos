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
            "NE SystemExtension is waiting to be activated"
        case .needsUserApproval:
            "NE SystemExtension needs user approval to activate"
        case .installed:
            "NE SystemExtension is installed"
        case let .failed(error):
            "NE SystemExtension failed with error: \(error)"
        }
    }
}

let extensionBundle: Bundle = {
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
}()

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

    func installSystemExtension() {
        systemExtnDelegate = SystemExtensionDelegate(asyncDelegate: self)
        systemExtnDelegate!.installSystemExtension()
    }
}

/// A delegate for the OSSystemExtensionRequest that maps the callbacks to async calls on the
/// AsyncDelegate (CoderVPNService in production).
class SystemExtensionDelegate<AsyncDelegate: SystemExtensionAsyncRecorder>:
    NSObject, OSSystemExtensionRequestDelegate
{
    private var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "vpn-installer")
    private var asyncDelegate: AsyncDelegate
    // The `didFinishWithResult` function is called for both activation,
    // deactivation, and replacement requests. The API provides no way to
    // differentiate them. https://developer.apple.com/forums/thread/684021
    // This tracks the last request type made, to handle them accordingly.
    private var action: SystemExtensionDelegateAction = .none

    init(asyncDelegate: AsyncDelegate) {
        self.asyncDelegate = asyncDelegate
        super.init()
        logger.info("SystemExtensionDelegate initialized")
    }

    func installSystemExtension() {
        logger.info("activating SystemExtension")
        let bundleID = extensionBundle.bundleIdentifier!
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: bundleID,
            queue: .main
        )
        request.delegate = self
        action = .installing
        OSSystemExtensionManager.shared.submitRequest(request)
        logger.info("submitted SystemExtension request with bundleID: \(bundleID)")
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
        switch action {
        case .installing:
            logger.info("SystemExtension installed")
            Task { [asyncDelegate] in
                await asyncDelegate.recordSystemExtensionState(.installed)
            }
            action = .none
        case .deleting:
            logger.info("SystemExtension deleted")
            Task { [asyncDelegate] in
                await asyncDelegate.recordSystemExtensionState(.uninstalled)
            }
            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: extensionBundle.bundleIdentifier!,
                queue: .main
            )
            request.delegate = self
            action = .installing
            OSSystemExtensionManager.shared.submitRequest(request)
        case .replacing:
            logger.info("SystemExtension replaced")
            // The installed extension now has the same version strings as this
            // bundle, so sending the deactivationRequest will work.
            let request = OSSystemExtensionRequest.deactivationRequest(
                forExtensionWithIdentifier: extensionBundle.bundleIdentifier!,
                queue: .main
            )
            request.delegate = self
            action = .deleting
            OSSystemExtensionManager.shared.submitRequest(request)
        case .none:
            logger.warning("Received an unexpected request result")
            break
        }
    }

    func request(_: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error("System extension request failed: \(error.localizedDescription)")
        Task { [asyncDelegate] in
            await asyncDelegate.recordSystemExtensionState(
                .failed(error.localizedDescription))
        }
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.error("Extension \(request.identifier) requires user approval")
        Task { [asyncDelegate] in
            await asyncDelegate.recordSystemExtensionState(.needsUserApproval)
        }
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension extension: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        logger.info("Replacing \(request.identifier) v\(existing.bundleVersion) with v\(`extension`.bundleVersion)")
        // This is counterintuitive, but this function is only called if the
        // versions are the same in a dev environment.
        // In a release build, this only gets called when the version string is
        // different. We don't want to manually reinstall the extension in a dev
        // environment, because the bug doesn't happen.
        if existing.bundleVersion == `extension`.bundleVersion {
            return .replace
        }
        // To work around the bug described in
        // https://github.com/coder/coder-desktop-macos/issues/121,
        // we're going to manually reinstall after the replacement is done.
        // If we returned `.cancel` here the deactivation request will fail as
        // it looks for an extension with the *current* version string.
        // There's no way to modify the deactivate request to use a different
        // version string (i.e. `existing.bundleVersion`).
        logger.info("App upgrade detected, replacing and then reinstalling")
        action = .replacing
        return .replace
    }
}

enum SystemExtensionDelegateAction {
    case none
    case installing
    case replacing
    case deleting
}
