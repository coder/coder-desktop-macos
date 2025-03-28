import SwiftUI

public struct FileSyncSession: Identifiable {
    public let id: String
    public let alphaPath: String
    public let name: String

    public let agentHost: String
    public let betaPath: String
    public let status: FileSyncStatus

    public let localSize: FileSyncSessionEndpointSize
    public let remoteSize: FileSyncSessionEndpointSize

    public let errors: [FileSyncError]

    init(state: Synchronization_State) {
        id = state.session.identifier
        name = state.session.name

        // If the protocol isn't what we expect for alpha or beta, show unknown
        alphaPath = if state.session.alpha.protocol == Url_Protocol.local, !state.session.alpha.path.isEmpty {
            state.session.alpha.path
        } else {
            "Unknown"
        }
        agentHost = if state.session.beta.protocol == Url_Protocol.ssh, !state.session.beta.host.isEmpty {
            // TOOD: We need to either:
            // - make this compatible with custom suffixes
            // - always strip the tld
            // - always keep the tld
            state.session.beta.host
        } else {
            "Unknown"
        }
        betaPath = if !state.session.beta.path.isEmpty {
            state.session.beta.path
        } else {
            "Unknown"
        }

        var status: FileSyncStatus = if state.session.paused {
            .paused
        } else {
            convertSessionStatus(status: state.status)
        }
        if case .error = status {} else {
            if state.conflicts.count > 0 {
                status = .conflicts(
                    formatConflicts(
                        conflicts: state.conflicts,
                        excludedConflicts: state.excludedConflicts
                    )
                )
            }
        }
        self.status = status

        localSize = .init(
            sizeBytes: state.alphaState.totalFileSize,
            fileCount: state.alphaState.files,
            dirCount: state.alphaState.directories,
            symLinkCount: state.alphaState.symbolicLinks
        )
        remoteSize = .init(
            sizeBytes: state.betaState.totalFileSize,
            fileCount: state.betaState.files,
            dirCount: state.betaState.directories,
            symLinkCount: state.betaState.symbolicLinks
        )

        errors = accumulateErrors(from: state)
    }

    public var statusAndErrors: String {
        var out = "\(status.type)\n\n\(status.description)"
        errors.forEach { out += "\n\t\($0)" }
        return out
    }

    public var sizeDescription: String {
        var out = ""
        out += "Local:\n\(localSize.description(linePrefix: " "))\n\n"
        out += "Remote:\n\(remoteSize.description(linePrefix: " "))"
        return out
    }
}

public struct FileSyncSessionEndpointSize: Equatable {
    public let sizeBytes: UInt64
    public let fileCount: UInt64
    public let dirCount: UInt64
    public let symLinkCount: UInt64

    public init(sizeBytes: UInt64, fileCount: UInt64, dirCount: UInt64, symLinkCount: UInt64) {
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
        self.dirCount = dirCount
        self.symLinkCount = symLinkCount
    }

    public var humanSizeBytes: String {
        humanReadableBytes(sizeBytes)
    }

    public func description(linePrefix: String = "") -> String {
        var result = ""
        result += linePrefix + humanReadableBytes(sizeBytes) + "\n"
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        if let formattedFileCount = numberFormatter.string(from: NSNumber(value: fileCount)) {
            result += "\(linePrefix)\(formattedFileCount) file\(fileCount == 1 ? "" : "s")\n"
        }
        if let formattedDirCount = numberFormatter.string(from: NSNumber(value: dirCount)) {
            result += "\(linePrefix)\(formattedDirCount) director\(dirCount == 1 ? "y" : "ies")"
        }
        if symLinkCount > 0, let formattedSymLinkCount = numberFormatter.string(from: NSNumber(value: symLinkCount)) {
            result += "\n\(linePrefix)\(formattedSymLinkCount) symlink\(symLinkCount == 1 ? "" : "s")"
        }
        return result
    }
}

public enum FileSyncStatus {
    case unknown
    case error(FileSyncErrorStatus)
    case ok
    case paused
    case conflicts(String)
    case working(FileSyncWorkingStatus)

    public var color: Color {
        switch self {
        case .ok:
            .white
        case .paused:
            .secondary
        case .unknown:
            .red
        case .error:
            .red
        case .conflicts:
            .orange
        case .working:
            .purple
        }
    }

    public var type: String {
        switch self {
        case .unknown:
            "Unknown"
        case let .error(status):
            status.name
        case .ok:
            "Watching"
        case .paused:
            "Paused"
        case .conflicts:
            "Conflicts"
        case let .working(status):
            status.name
        }
    }

    public var description: String {
        switch self {
        case .unknown:
            "Unknown status message."
        case let .error(status):
            status.description
        case .ok:
            "The session is watching for filesystem changes."
        case .paused:
            "The session is paused."
        case let .conflicts(details):
            "The session has conflicts that need to be resolved:\n\n\(details)"
        case let .working(status):
            status.description
        }
    }

    public var column: some View {
        Text(type).foregroundColor(color)
    }

    public var isResumable: Bool {
        switch self {
        case .paused,
             .error(.haltedOnRootEmptied),
             .error(.haltedOnRootDeletion),
             .error(.haltedOnRootTypeChange):
            true
        default:
            false
        }
    }
}

public enum FileSyncWorkingStatus {
    case connectingAlpha
    case connectingBeta
    case scanning
    case reconciling
    case stagingAlpha
    case stagingBeta
    case transitioning
    case saving

    var name: String {
        switch self {
        case .connectingAlpha:
            "Connecting (alpha)"
        case .connectingBeta:
            "Connecting (beta)"
        case .scanning:
            "Scanning"
        case .reconciling:
            "Reconciling"
        case .stagingAlpha:
            "Staging (alpha)"
        case .stagingBeta:
            "Staging (beta)"
        case .transitioning:
            "Transitioning"
        case .saving:
            "Saving"
        }
    }

    var description: String {
        switch self {
        case .connectingAlpha:
            "The session is attempting to connect to the alpha endpoint."
        case .connectingBeta:
            "The session is attempting to connect to the beta endpoint."
        case .scanning:
            "The session is scanning the filesystem on each endpoint."
        case .reconciling:
            "The session is performing reconciliation."
        case .stagingAlpha:
            "The session is staging files on the alpha endpoint"
        case .stagingBeta:
            "The session is staging files on the beta endpoint"
        case .transitioning:
            "The session is performing transition operations on each endpoint."
        case .saving:
            "The session is recording synchronization history to disk."
        }
    }
}

public enum FileSyncErrorStatus {
    case disconnected
    case haltedOnRootEmptied
    case haltedOnRootDeletion
    case haltedOnRootTypeChange
    case waitingForRescan

    var name: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .haltedOnRootEmptied:
            "Halted on root emptied"
        case .haltedOnRootDeletion:
            "Halted on root deletion"
        case .haltedOnRootTypeChange:
            "Halted on root type change"
        case .waitingForRescan:
            "Waiting for rescan"
        }
    }

    var description: String {
        switch self {
        case .disconnected:
            "The session is unpaused but not currently connected or connecting to either endpoint."
        case .haltedOnRootEmptied:
            "The session is halted due to the root emptying safety check."
        case .haltedOnRootDeletion:
            "The session is halted due to the root deletion safety check."
        case .haltedOnRootTypeChange:
            "The session is halted due to the root type change safety check."
        case .waitingForRescan:
            "The session is waiting to retry scanning after an error during the previous scan."
        }
    }
}

public enum FileSyncEndpoint {
    case alpha
    case beta
}

public enum FileSyncProblemType {
    case scan
    case transition
}

public enum FileSyncError {
    case generic(String)
    case problem(FileSyncEndpoint, FileSyncProblemType, path: String, error: String)
    case excludedProblems(FileSyncEndpoint, FileSyncProblemType, UInt64)

    var description: String {
        switch self {
        case let .generic(error):
            error
        case let .problem(endpoint, type, path, error):
            "\(endpoint) \(type) error at \(path): \(error)"
        case let .excludedProblems(endpoint, type, count):
            "+ \(count) \(endpoint) \(type) problems"
        }
    }
}

public func sessionsHaveError(_ sessions: [FileSyncSession]) -> Bool {
    for session in sessions {
        if case .error = session.status {
            return true
        }
    }
    return false
}
