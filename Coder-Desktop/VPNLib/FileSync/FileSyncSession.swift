import SwiftUI

public struct FileSyncSession: Identifiable {
    public let id: String
    public let alphaPath: String
    public let agentHost: String
    public let betaPath: String
    public let status: FileSyncStatus
    public let size: String
}

public enum FileSyncStatus {
    case unknown
    case error(String)
    case ok
    case paused
    case needsAttention(String)
    case working(String)

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
            .white
        }
    }

    public var description: String {
        switch self {
        case .unknown:
            "Unknown"
        case let .error(msg):
            msg
        case .ok:
            "Watching"
        case .paused:
            "Paused"
        case let .needsAttention(msg):
            msg
        case let .working(msg):
            msg
        }
    }

    public var body: some View {
        Text(description).foregroundColor(color)
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
