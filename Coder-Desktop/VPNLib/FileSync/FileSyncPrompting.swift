import GRPC

extension MutagenDaemon {
    typealias PromptStream = GRPCAsyncBidirectionalStreamingCall<Prompting_HostRequest, Prompting_HostResponse>

    func host(allowPrompts: Bool = true) async throws(DaemonError) -> (PromptStream, identifier: String) {
        let stream = client!.prompt.makeHostCall()

        do {
            try await stream.requestStream.send(.with { req in req.allowPrompts = allowPrompts })
        } catch {
            throw .grpcFailure(error)
        }

        // We can't make call `makeAsyncIterator` more than once
        // (as a for-loop would do implicitly)
        var iter = stream.responseStream.makeAsyncIterator()

        let initResp: Prompting_HostResponse?
        do {
            initResp = try await iter.next()
        } catch {
            throw .grpcFailure(error)
        }
        guard let initResp else {
            throw .unexpectedStreamClosure
        }
        try initResp.ensureValid(first: true, allowPrompts: allowPrompts)

        Task.detached(priority: .background) {
            defer { Task { @MainActor in self.lastPromptMessage = nil } }
            do {
                while let msg = try await iter.next() {
                    try msg.ensureValid(first: false, allowPrompts: allowPrompts)
                    var reply: Prompting_HostRequest = .init()
                    if msg.isPrompt {
                        // Handle SSH key prompts
                        if msg.message.contains("yes/no/[fingerprint]") {
                            reply.response = "yes"
                        }
                        // Any other messages that require a non-empty response will
                        // cause the create op to fail, showing an error. This is ok for now.
                    } else {
                        Task { @MainActor in self.lastPromptMessage = msg.message }
                    }
                    try await stream.requestStream.send(reply)
                }
            } catch let error as GRPCStatus where error.code == .cancelled {
                return
            } catch {
                self.logger.critical("Prompt stream failed: \(error)")
            }
        }
        return (stream, identifier: initResp.identifier)
    }
}
