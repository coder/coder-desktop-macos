public func spawn(executable: String, args: [String]) throws(TunnelDaemonError) -> pid_t {
    var pid: pid_t = 0

    // argv = [executable, args..., nil]
    var argv: [UnsafeMutablePointer<CChar>?] = []
    argv.append(strdup(executable))
    for a in args {
        argv.append(strdup(a))
    }
    argv.append(nil)
    defer { for p in argv where p != nil {
        free(p)
    } }

    let rc: Int32 = argv.withUnsafeMutableBufferPointer { argvBuf in
        posix_spawn(&pid, executable, nil, nil, argvBuf.baseAddress, nil)
    }
    if rc != 0 {
        throw .spawn(POSIXError(POSIXErrorCode(rawValue: rc) ?? .EPERM))
    }
    return pid
}

public func unsetCloseOnExec(fd: Int32) throws(POSIXError) {
    let cur = fcntl(fd, F_GETFD)
    guard cur != -1 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
    }
    let newFlags: Int32 = (cur & ~FD_CLOEXEC)
    guard fcntl(fd, F_SETFD, newFlags) != -1 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
    }
}

public func chmodX(at url: URL) throws(POSIXError) {
    var st = stat()
    guard stat(url.path, &st) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
    }

    let newMode: mode_t = st.st_mode | mode_t(S_IXUSR | S_IXGRP | S_IXOTH)

    guard chmod(url.path, newMode) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
    }
}

// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
//
// Derived from swiftlang/swift-subprocess
// Original: https://github.com/swiftlang/swift-subprocess/blob/7fb7ee86df8ca4f172697bfbafa89cdc583ac016/Sources/Subprocess/Platforms/Subprocess%2BDarwin.swift#L487-L525
// Copyright (c) 2025 Apple Inc. and the Swift project authors
@Sendable public func monitorProcessTermination(pid: pid_t) async throws -> Termination {
    try await withCheckedThrowingContinuation { continuation in
        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: [.exit],
            queue: .global()
        )
        source.setEventHandler {
            source.cancel()
            var siginfo = siginfo_t()
            let rc = waitid(P_PID, id_t(pid), &siginfo, WEXITED)
            guard rc == 0 else {
                let err = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINTR)
                continuation.resume(throwing: err)
                return
            }
            switch siginfo.si_code {
            case .init(CLD_EXITED):
                continuation.resume(returning: .exited(siginfo.si_status))
            case .init(CLD_KILLED), .init(CLD_DUMPED):
                continuation.resume(returning: .unhandledException(siginfo.si_status))
            default:
                continuation.resume(returning: .unhandledException(siginfo.si_status))
            }
        }
        source.resume()
    }
}
