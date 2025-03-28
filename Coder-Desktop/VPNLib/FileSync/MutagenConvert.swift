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
        errors.append(.problem(.alpha, .scan, path: problem.path, error: problem.error))
    }
    for problem in state.alphaState.transitionProblems {
        errors.append(.problem(.alpha, .transition, path: problem.path, error: problem.error))
    }
    for problem in state.betaState.scanProblems {
        errors.append(.problem(.beta, .scan, path: problem.path, error: problem.error))
    }
    for problem in state.betaState.transitionProblems {
        errors.append(.problem(.beta, .transition, path: problem.path, error: problem.error))
    }
    if state.alphaState.excludedScanProblems > 0 {
        errors.append(.excludedProblems(.alpha, .scan, state.alphaState.excludedScanProblems))
    }
    if state.alphaState.excludedTransitionProblems > 0 {
        errors.append(.excludedProblems(.alpha, .transition, state.alphaState.excludedTransitionProblems))
    }
    if state.betaState.excludedScanProblems > 0 {
        errors.append(.excludedProblems(.beta, .scan, state.betaState.excludedScanProblems))
    }
    if state.betaState.excludedTransitionProblems > 0 {
        errors.append(.excludedProblems(.beta, .transition, state.betaState.excludedTransitionProblems))
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

// Translated from `cmd/mutagen/sync/list_monitor_common.go`
func formatConflicts(conflicts: [Core_Conflict], excludedConflicts: UInt64) -> String {
    var result = ""
    for (i, conflict) in conflicts.enumerated() {
        var changesByPath: [String: (alpha: [Core_Change], beta: [Core_Change])] = [:]

        // Group alpha changes by path
        for alphaChange in conflict.alphaChanges {
            let path = alphaChange.path
            if changesByPath[path] == nil {
                changesByPath[path] = (alpha: [], beta: [])
            }
            changesByPath[path]!.alpha.append(alphaChange)
        }

        // Group beta changes by path
        for betaChange in conflict.betaChanges {
            let path = betaChange.path
            if changesByPath[path] == nil {
                changesByPath[path] = (alpha: [], beta: [])
            }
            changesByPath[path]!.beta.append(betaChange)
        }

        result += formatChanges(changesByPath)

        if i < conflicts.count - 1 || excludedConflicts > 0 {
            result += "\n"
        }
    }

    if excludedConflicts > 0 {
        result += "...+\(excludedConflicts) more conflicts...\n"
    }

    return result
}

func formatChanges(_ changesByPath: [String: (alpha: [Core_Change], beta: [Core_Change])]) -> String {
    var result = ""

    for (path, changes) in changesByPath {
        if changes.alpha.count == 1, changes.beta.count == 1 {
            // Simple message for basic file conflicts
            if changes.alpha[0].hasNew,
               changes.beta[0].hasNew,
               changes.alpha[0].new.kind == .file,
               changes.beta[0].new.kind == .file
            {
                result += "File: '\(formatPath(path))'\n"
                continue
            }
            // Friendly message for `<non-existent -> !<non-existent>` conflicts
            if !changes.alpha[0].hasOld,
               !changes.beta[0].hasOld,
               changes.alpha[0].hasNew,
               changes.beta[0].hasNew
            {
                result += """
                An entry, '\(formatPath(path))', was created on both endpoints that does not match.
                You can resolve this conflict by deleting one of the entries.\n
                """
                continue
            }
        }

        let formattedPath = formatPath(path)
        result += "Path: '\(formattedPath)'\n"

        // TODO: Local & Remote should be replaced with Alpha & Beta, once it's possible to configure which is which

        if !changes.alpha.isEmpty {
            result += " Local changes:\n"
            for change in changes.alpha {
                let old = formatEntry(change.hasOld ? change.old : nil)
                let new = formatEntry(change.hasNew ? change.new : nil)
                result += "  \(old) → \(new)\n"
            }
        }

        if !changes.beta.isEmpty {
            result += " Remote changes:\n"
            for change in changes.beta {
                let old = formatEntry(change.hasOld ? change.old : nil)
                let new = formatEntry(change.hasNew ? change.new : nil)
                result += "  \(old) → \(new)\n"
            }
        }
    }

    return result
}

func formatPath(_ path: String) -> String {
    path.isEmpty ? "<root>" : path
}

func formatEntry(_ entry: Core_Entry?) -> String {
    guard let entry else {
        return "<non-existent>"
    }

    switch entry.kind {
    case .directory:
        return "Directory"
    case .file:
        return entry.executable ? "Executable File" : "File"
    case .symbolicLink:
        return "Symbolic Link (\(entry.target))"
    case .untracked:
        return "Untracked content"
    case .problematic:
        return "Problematic content (\(entry.problem))"
    case .UNRECOGNIZED:
        return "<unknown>"
    case .phantomDirectory:
        return "Phantom Directory"
    }
}
