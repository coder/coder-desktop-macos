import SwiftUI

public struct FileSyncSession: Identifiable {
    public let id: String
    public let name: String

    public let localPath: String
    public let agentHost: String
    public let remotePath: String
    public let status: FileSyncStatus

    public let maxSize: FileSyncSessionEndpointSize
    public let localSize: FileSyncSessionEndpointSize
    public let remoteSize: FileSyncSessionEndpointSize

    public let errors: [FileSyncError]

    init(state: Synchronization_State) {
        id = state.session.identifier
        name = state.session.name

        // If the protocol isn't what we expect for alpha or beta, show unknown
        localPath = if state.session.alpha.protocol == Url_Protocol.local, !state.session.alpha.path.isEmpty {
            state.session.alpha.path
        } else {
            "Unknown"
        }
        if state.session.beta.protocol == Url_Protocol.ssh, !state.session.beta.host.isEmpty {
            let host = state.session.beta.host
            // TOOD: We need to either:
            // - make this compatible with custom suffixes
            // - always strip the tld
            // - always keep the tld
            agentHost = host.hasSuffix(".coder") ? String(host.dropLast(6)) : host
        } else {
            agentHost = "Unknown"
        }
        remotePath = if !state.session.beta.path.isEmpty {
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
                status = .needsAttention(name: "Conflicts", desc: "The session has conflicts that need to be resolved")
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
        maxSize = localSize.maxOf(other: remoteSize)

        errors = accumulateErrors(from: state)
    }

    public var statusAndErrors: String {
        var out = "\(status.type)\n\n\(status.description)"
        errors.forEach { out += "\n\t\($0)" }
        return out
    }

    public var sizeDescription: String {
        var out = ""
        if localSize != remoteSize {
            out += "Maximum:\n\(maxSize.description(linePrefix: " "))\n\n"
        }
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

    func maxOf(other: FileSyncSessionEndpointSize) -> FileSyncSessionEndpointSize {
        FileSyncSessionEndpointSize(
            sizeBytes: max(sizeBytes, other.sizeBytes),
            fileCount: max(fileCount, other.fileCount),
            dirCount: max(dirCount, other.dirCount),
            symLinkCount: max(symLinkCount, other.symLinkCount)
        )
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
    case error(name: String, desc: String)
    case ok
    case paused
    case needsAttention(name: String, desc: String)
    case working(name: String, desc: String)

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
        case .needsAttention:
            .orange
        case .working:
            .purple
        }
    }

    public var type: String {
        switch self {
        case .unknown:
            "Unknown"
        case let .error(name, _):
            "\(name)"
        case .ok:
            "Watching"
        case .paused:
            "Paused"
        case let .needsAttention(name, _):
            name
        case let .working(name, _):
            name
        }
    }

    public var description: String {
        switch self {
        case .unknown:
            "Unknown status message."
        case let .error(_, desc):
            desc
        case .ok:
            "The session is watching for filesystem changes."
        case .paused:
            "The session is paused."
        case let .needsAttention(_, desc):
            desc
        case let .working(_, desc):
            desc
        }
    }

    public var column: some View {
        Text(type).foregroundColor(color)
    }
}

public enum FileSyncEndpoint {
    case local
    case remote
}

public enum FileSyncProblemType {
    case scan
    case transition
}

public enum FileSyncError {
    case generic(String)
    case problem(FileSyncEndpoint, FileSyncProblemType, path: String, error: String)

    var description: String {
        switch self {
        case let .generic(error):
            error
        case let .problem(endpoint, type, path, error):
            "\(endpoint) \(type) error at \(path): \(error)"
        }
    }
}
