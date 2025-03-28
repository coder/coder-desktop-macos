import NIOCore

public extension MutagenDaemon {
    func refreshSessions() async {
        guard case .running = state else { return }
        let sessions: Synchronization_ListResponse
        do {
            sessions = try await client!.sync.list(Synchronization_ListRequest.with { req in
                req.selection = .with { selection in
                    selection.all = true
                }
            })
        } catch {
            state = .failed(.grpcFailure(error))
            return
        }
        sessionState = sessions.sessionStates.map { FileSyncSession(state: $0) }
    }

    func createSession(
        localPath: String,
        agentHost: String,
        remotePath: String
    ) async throws(DaemonError) {
        if case .stopped = state {
            do throws(DaemonError) {
                try await start()
            } catch {
                state = .failed(error)
                throw error
            }
        }
        let (stream, promptID) = try await host()
        defer { stream.cancel() }
        let req = Synchronization_CreateRequest.with { req in
            req.prompter = promptID
            req.specification = .with { spec in
                spec.alpha = .with { alpha in
                    alpha.protocol = .local
                    alpha.path = localPath
                }
                spec.beta = .with { beta in
                    beta.protocol = .ssh
                    beta.host = agentHost
                    beta.path = remotePath
                }
                // TODO: Ingest a config from somewhere
                spec.configuration = Synchronization_Configuration()
                spec.configurationAlpha = Synchronization_Configuration()
                spec.configurationBeta = Synchronization_Configuration()
            }
        }
        do {
            // The first creation will need to transfer the agent binary
            // TODO: Because this is pretty long, we should show progress updates
            // using the prompter messages
            _ = try await client!.sync.create(req, callOptions: .init(timeLimit: .timeout(sessionMgmtReqTimeout * 4)))
        } catch {
            throw .grpcFailure(error)
        }
        await refreshSessions()
    }

    func deleteSessions(ids: [String]) async throws(DaemonError) {
        // Terminating sessions does not require prompting, according to the
        // Mutagen CLI
        let (stream, promptID) = try await host(allowPrompts: false)
        defer { stream.cancel() }
        guard case .running = state else { return }
        do {
            _ = try await client!.sync.terminate(Synchronization_TerminateRequest.with { req in
                req.prompter = promptID
                req.selection = .with { selection in
                    selection.specifications = ids
                }
            }, callOptions: .init(timeLimit: .timeout(sessionMgmtReqTimeout)))
        } catch {
            throw .grpcFailure(error)
        }
        await refreshSessions()
    }

    func pauseSessions(ids: [String]) async throws(DaemonError) {
        // Pausing sessions does not require prompting, according to the
        // Mutagen CLI
        let (stream, promptID) = try await host(allowPrompts: false)
        defer { stream.cancel() }
        guard case .running = state else { return }
        do {
            _ = try await client!.sync.pause(Synchronization_PauseRequest.with { req in
                req.prompter = promptID
                req.selection = .with { selection in
                    selection.specifications = ids
                }
            }, callOptions: .init(timeLimit: .timeout(sessionMgmtReqTimeout)))
        } catch {
            throw .grpcFailure(error)
        }
        await refreshSessions()
    }

    func resumeSessions(ids: [String]) async throws(DaemonError) {
        // Resuming sessions does not require prompting, according to the
        // Mutagen CLI
        let (stream, promptID) = try await host(allowPrompts: false)
        defer { stream.cancel() }
        guard case .running = state else { return }
        do {
            _ = try await client!.sync.resume(Synchronization_ResumeRequest.with { req in
                req.prompter = promptID
                req.selection = .with { selection in
                    selection.specifications = ids
                }
            }, callOptions: .init(timeLimit: .timeout(sessionMgmtReqTimeout)))
        } catch {
            throw .grpcFailure(error)
        }
        await refreshSessions()
    }
}
