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

    func createSession(arg: CreateSyncSessionRequest) async throws(DaemonError) {
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
                spec.alpha = arg.alpha.mutagenURL
                spec.beta = arg.beta.mutagenURL
                // TODO: Ingest configs from somewhere
                spec.configuration = .with {
                    // ALWAYS ignore VCS directories for now
                    // https://mutagen.io/documentation/synchronization/version-control-systems/
                    $0.ignoreVcsmode = .ignore
                }
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
        do {
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
        }
        await refreshSessions()
        if sessionState.isEmpty {
            // Last session was deleted, stop the daemon
            await stop()
        }
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
        // Resuming sessions does use prompting, as it may start a new SSH connection
        let (stream, promptID) = try await host(allowPrompts: true)
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

    func resetSessions(ids: [String]) async throws(DaemonError) {
        // Resetting a session involves pausing & resuming, so it does use prompting
        let (stream, promptID) = try await host(allowPrompts: true)
        defer { stream.cancel() }
        guard case .running = state else { return }
        do {
            _ = try await client!.sync.reset(Synchronization_ResetRequest.with { req in
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

public struct CreateSyncSessionRequest {
    public let alpha: Endpoint
    public let beta: Endpoint

    public init(alpha: Endpoint, beta: Endpoint) {
        self.alpha = alpha
        self.beta = beta
    }
}

public struct Endpoint {
    public let path: String
    public let protocolKind: ProtocolKind

    public init(path: String, protocolKind: ProtocolKind) {
        self.path = path
        self.protocolKind = protocolKind
    }

    public enum ProtocolKind {
        case local
        case ssh(host: String)
    }

    var mutagenURL: Url_URL {
        switch protocolKind {
        case .local:
            .with { url in
                url.path = path
                url.protocol = .local
            }
        case let .ssh(host):
            .with { url in
                url.path = path
                url.protocol = .ssh
                url.host = host
            }
        }
    }
}
