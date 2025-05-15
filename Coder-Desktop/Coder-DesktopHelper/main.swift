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

    func removeQuarantine(path: String, withReply reply: @escaping (Int32, String) -> Void) {
        guard isCoderDesktopDylib(at: path) else {
            reply(1, "Path is not to a Coder Desktop dylib: \(path)")
            return
        }

        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-d", "com.apple.quarantine", path]
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")

        do {
            try task.run()
        } catch {
            reply(1, "Failed to start command: \(error)")
            return
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        task.waitUntilExit()
        reply(task.terminationStatus, output)
    }
}

func isCoderDesktopDylib(at rawPath: String) -> Bool {
    let url = URL(fileURLWithPath: rawPath)
        .standardizedFileURL
        .resolvingSymlinksInPath()

    // *Must* be within the Coder Desktop System Extension sandbox
    let requiredPrefix = ["/", "var", "root", "Library", "Containers",
                          "com.coder.Coder-Desktop.VPN"]
    guard url.pathComponents.starts(with: requiredPrefix) else { return false }
    guard url.pathExtension.lowercased() == "dylib" else { return false }
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    return true
}

let delegate = HelperToolDelegate()
let listener = NSXPCListener(machServiceName: "4399GN35BJ.com.coder.Coder-Desktop.Helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
