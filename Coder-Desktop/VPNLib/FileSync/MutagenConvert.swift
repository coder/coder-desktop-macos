// swiftlint:disable:next cyclomatic_complexity
func convertSessionStatus(status: Synchronization_Status) -> FileSyncStatus {
    switch status {
    case .disconnected:
        .error(name: "Disconnected",
               desc: "The session is unpaused but not currently connected or connecting to either endpoint.")
    case .haltedOnRootEmptied:
        .error(name: "Halted on root emptied", desc: "The session is halted due to the root emptying safety check.")
    case .haltedOnRootDeletion:
        .error(name: "Halted on root deletion", desc: "The session is halted due to the root deletion safety check.")
    case .haltedOnRootTypeChange:
        .error(
            name: "Halted on root type change",
            desc: "The session is halted due to the root type change safety check."
        )
    case .waitingForRescan:
        .error(name: "Waiting for rescan",
               desc: "The session is waiting to retry scanning after an error during the previous scan.")
    case .connectingAlpha:
        // Alpha -> Local
        .working(name: "Connecting (local)", desc: "The session is attempting to connect to the local endpoint.")
    case .connectingBeta:
        // Beta -> Remote
        .working(name: "Connecting (remote)", desc: "The session is attempting to connect to the remote endpoint.")
    case .scanning:
        .working(name: "Scanning", desc: "The session is scanning the filesystem on each endpoint.")
    case .reconciling:
        .working(name: "Reconciling", desc: "The session is performing reconciliation.")
    case .stagingAlpha:
        // Alpha -> Local
        .working(name: "Staging (local)", desc: "The session is staging files locally")
    case .stagingBeta:
        // Beta -> Remote
        .working(name: "Staging (remote)", desc: "The session is staging files on the remote")
    case .transitioning:
        .working(name: "Transitioning", desc: "The session is performing transition operations on each endpoint.")
    case .saving:
        .working(name: "Saving", desc: "The session is recording synchronization history to disk.")
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
