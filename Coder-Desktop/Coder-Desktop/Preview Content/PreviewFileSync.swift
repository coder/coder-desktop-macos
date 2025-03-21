import VPNLib

@MainActor
final class PreviewFileSync: FileSyncDaemon {
    var state: DaemonState = .running

    init() {}

    func start() async throws(DaemonError) {
        state = .running
    }

    func stop() async {
        state = .stopped
    }

    func listSessions() async throws -> [FileSyncSession] {
        []
    }

    func createSession(with _: FileSyncSession) async throws {}
}
