import os
import ServiceManagement

// Whilst the GUI app installs the helper, the System Extension communicates
// with it over XPC
@MainActor
class HelperService: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HelperService")
    let plistName = "com.coder.Coder-Desktop.Helper.plist"
    @Published var state: HelperState = .uninstalled {
        didSet {
            logger.info("helper daemon state set: \(self.state.description, privacy: .public)")
        }
    }

    init() {
        update()
    }

    func update() {
        let daemon = SMAppService.daemon(plistName: plistName)
        state = HelperState(status: daemon.status)
    }

    func install() {
        let daemon = SMAppService.daemon(plistName: plistName)
        do {
            try daemon.register()
        } catch let error as NSError {
            self.state = .failed(.init(error: error))
        } catch {
            state = .failed(.unknown(error.localizedDescription))
        }
        state = HelperState(status: daemon.status)
    }

    func uninstall() {
        let daemon = SMAppService.daemon(plistName: plistName)
        do {
            try daemon.unregister()
        } catch let error as NSError {
            self.state = .failed(.init(error: error))
        } catch {
            state = .failed(.unknown(error.localizedDescription))
        }
        state = HelperState(status: daemon.status)
    }
}

enum HelperState: Equatable {
    case uninstalled
    case installed
    case requiresApproval
    case failed(HelperError)

    var description: String {
        switch self {
        case .uninstalled:
            "Uninstalled"
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
