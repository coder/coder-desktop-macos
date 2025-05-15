import Foundation
import os

final class HelperXPCSpeaker: @unchecked Sendable {
    private var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HelperXPCSpeaker")
    private var connection: NSXPCConnection?

    func tryRemoveQuarantine(path: String) async -> Bool {
        let conn = connect()
        return await withCheckedContinuation { continuation in
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
                self.logger.error("Failed to connect to HelperXPC \(err)")
                continuation.resume(returning: false)
            }) as? HelperXPCProtocol else {
                self.logger.error("Failed to get proxy for HelperXPC")
                continuation.resume(returning: false)
                return
            }
            proxy.removeQuarantine(path: path) { status, output in
                if status == 0 {
                    self.logger.info("Successfully removed quarantine for \(path)")
                    continuation.resume(returning: true)
                } else {
                    self.logger.error("Failed to remove quarantine for \(path): \(output)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func connect() -> NSXPCConnection {
        if let connection = self.connection {
            return connection
        }

        // Though basically undocumented, System Extensions can communicate with
        // LaunchDaemons over XPC if the machServiceName used is prefixed with
        // the team identifier.
        // https://developer.apple.com/forums/thread/654466
        let connection = NSXPCConnection(
            machServiceName: "4399GN35BJ.com.coder.Coder-Desktop.Helper",
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        connection.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        connection.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}
