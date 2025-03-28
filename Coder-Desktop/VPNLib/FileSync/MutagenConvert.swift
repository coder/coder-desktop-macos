// swiftlint:disable:next cyclomatic_complexity
func convertSessionStatus(status: Synchronization_Status) -> FileSyncStatus {
    switch status {
    case .disconnected:
        .error(.disconnected)
    case .haltedOnRootEmptied:
        .error(.haltedOnRootEmptied)
    case .haltedOnRootDeletion:
        .error(.haltedOnRootDeletion)
    case .haltedOnRootTypeChange:
        .error(.haltedOnRootTypeChange)
    case .waitingForRescan:
        .error(.waitingForRescan)
    case .connectingAlpha:
        .working(.connectingAlpha)
    case .connectingBeta:
        .working(.connectingBeta)
    case .scanning:
        .working(.scanning)
    case .reconciling:
        .working(.reconciling)
    case .stagingAlpha:
        .working(.stagingAlpha)
    case .stagingBeta:
        .working(.stagingBeta)
    case .transitioning:
        .working(.transitioning)
    case .saving:
        .working(.saving)
    case .watching:
        .ok
    case .UNRECOGNIZED:
        .unknown
    }
}

func accumulateErrors(from state: Synchronization_State) -> [FileSyncError] {
    var errors: [FileSyncError] = []
    if !state.lastError.isEmpty {
        errors.append(.generic(state.lastError))
    }
    for problem in state.alphaState.scanProblems {
        errors.append(.problem(.local, .scan, path: problem.path, error: problem.error))
    }
    for problem in state.alphaState.transitionProblems {
        errors.append(.problem(.local, .transition, path: problem.path, error: problem.error))
    }
    for problem in state.betaState.scanProblems {
        errors.append(.problem(.remote, .scan, path: problem.path, error: problem.error))
    }
    for problem in state.betaState.transitionProblems {
        errors.append(.problem(.remote, .transition, path: problem.path, error: problem.error))
    }
    return errors
}

func humanReadableBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter().string(fromByteCount: Int64(bytes))
}

extension Prompting_HostResponse {
    func ensureValid(first: Bool, allowPrompts: Bool) throws(DaemonError) {
        if first {
            if identifier.isEmpty {
                throw .invalidGrpcResponse("empty prompter identifier")
            }
            if isPrompt {
                throw .invalidGrpcResponse("unexpected message type specification")
            }
            if !message.isEmpty {
                throw .invalidGrpcResponse("unexpected message")
            }
        } else {
            if !identifier.isEmpty {
                throw .invalidGrpcResponse("unexpected prompter identifier")
            }
            if isPrompt, !allowPrompts {
                throw .invalidGrpcResponse("disallowed prompt message type")
            }
        }
    }
}
