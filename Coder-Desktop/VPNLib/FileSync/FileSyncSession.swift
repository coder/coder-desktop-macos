import SwiftUI

public struct FileSyncSession: Identifiable {
    public let id: String
    public let localPath: URL
    public let workspace: String
    // This is a string as to be host-OS agnostic
    public let remotePath: String
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
