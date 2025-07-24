import os
import ServiceManagement

extension CoderVPNService {
    var plistName: String { "com.coder.Coder-Desktop.Helper.plist" }

    func refreshHelperState() {
        let daemon = SMAppService.daemon(plistName: plistName)
        helperState = HelperState(status: daemon.status)
    }

    func setupHelper() async {
        refreshHelperState()
        switch helperState {
        case .uninstalled, .failed, .installed:
            await uninstallHelper()
            await installHelper()
        case .requiresApproval, .installing:
            break
        }
    }

    private func installHelper() async {
        // Worst case, this setup takes a few seconds. We'll show a loading
        // indicator in the meantime.
        helperState = .installing
        var lastUnknownError: Error?
        // Registration may fail with a permissions error if it was
        // just unregistered, so we retry a few times.
        for _ in 0 ... 10 {
            let daemon = SMAppService.daemon(plistName: plistName)
            do {
                try daemon.register()
                helperState = HelperState(status: daemon.status)
                return
            } catch {
                if daemon.status == .requiresApproval {
                    helperState = .requiresApproval
                    return
                }
                let helperError = HelperError(error: error as NSError)
                switch helperError {
                case .alreadyRegistered:
                    helperState = .installed
                    return
                case .launchDeniedByUser, .invalidSignature:
                    // Something weird happened, we should update the UI
                    helperState = .failed(helperError)
                    return
                case .unknown:
                    // Likely intermittent permissions error, we'll retry
                    lastUnknownError = error
                    logger.warning("failed to register helper: \(helperError.localizedDescription)")
                }

                // Short delay before retrying
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        // Give up, update the UI with the error
        helperState = .failed(.unknown(lastUnknownError?.localizedDescription ?? "Unknown"))
    }

    private func uninstallHelper() async {
        let daemon = SMAppService.daemon(plistName: plistName)
        do {
            try await daemon.unregister()
        } catch let error as NSError {
            helperState = .failed(.init(error: error))
        } catch {
            helperState = .failed(.unknown(error.localizedDescription))
        }
        helperState = HelperState(status: daemon.status)
    }
}

enum HelperState: Equatable {
    case uninstalled
    case installing
    case installed
    case requiresApproval
    case failed(HelperError)

    var description: String {
        switch self {
        case .uninstalled:
            "Uninstalled"
        case .installing:
            "Installing"
        case .installed:
            "Installed"
        case .requiresApproval:
            "Requires Approval"
        case let .failed(error):
            "Failed: \(error.localizedDescription)"
        }
    }

    init(status: SMAppService.Status) {
        self = switch status {
        case .notRegistered:
            .uninstalled
        case .enabled:
            .installed
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            // `Not found`` is the initial state, if `register` has never been called
            .uninstalled
        @unknown default:
            .failed(.unknown("Unknown status: \(status)"))
        }
    }
}

enum HelperError: Error, Equatable {
    case alreadyRegistered
    case launchDeniedByUser
    case invalidSignature
    case unknown(String)

    init(error: NSError) {
        self = switch error.code {
        case kSMErrorAlreadyRegistered:
            .alreadyRegistered
        case kSMErrorLaunchDeniedByUser:
            .launchDeniedByUser
        case kSMErrorInvalidSignature:
            .invalidSignature
        default:
            .unknown(error.localizedDescription)
        }
    }

    var localizedDescription: String {
        switch self {
        case .alreadyRegistered:
            "Already registered"
        case .launchDeniedByUser:
            "Launch denied by user"
        case .invalidSignature:
            "Invalid signature"
        case let .unknown(message):
            message
        }
    }
}
