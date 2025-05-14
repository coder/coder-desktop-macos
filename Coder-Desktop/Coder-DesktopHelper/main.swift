import Foundation
import os

class HelperToolDelegate: NSObject, NSXPCListenerDelegate, HelperXPCProtocol {
    private var logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HelperToolDelegate")

    override init() {
        super.init()
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.info("Helper XPC connection invalidated")
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.logger.debug("Helper XPC connection interrupted")
        }
        logger.info("new active connection")
        newConnection.resume()
        return true
    }

    func runCommand(command: String, withReply reply: @escaping (Int32, String) -> Void) {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")

        do {
            try task.run()
        } catch {
            reply(1, "Failed to start command: \(error)")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        task.waitUntilExit()
        reply(task.terminationStatus, output)
    }
}

let delegate = HelperToolDelegate()
let listener = NSXPCListener(machServiceName: "4399GN35BJ.com.coder.Coder-Desktop.Helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
