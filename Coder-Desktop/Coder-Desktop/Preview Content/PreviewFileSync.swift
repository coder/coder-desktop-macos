import VPNLib

@MainActor
final class PreviewFileSync: FileSyncDaemon {
    var logFile: URL = .init(filePath: "~/log.txt")!

    var sessionState: [VPNLib.FileSyncSession] = []

    var state: DaemonState = .running

    init() {}

    func refreshSessions() async {}

    func tryStart() async {
        state = .running
    }

    func stop() async {
        state = .stopped
    }

    func createSession(localPath _: String, agentHost _: String, remotePath _: String) async throws(DaemonError) {}

    func deleteSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}

    func pauseSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}

    func resumeSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}

    func resetSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}
}
