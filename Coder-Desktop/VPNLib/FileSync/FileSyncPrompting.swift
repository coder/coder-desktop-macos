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

        // "Receive the initialization response, validate it, and extract the prompt identifier"
        let initResp: Prompting_HostResponse?
        do {
            initResp = try await iter.next()
        } catch {
            throw .grpcFailure(error)
        }
        guard let initResp else {
            throw .unexpectedStreamClosure
        }
        // TODO: we'll always accept prompts for now
        try initResp.ensureValid(first: true, allowPrompts: allowPrompts)

        Task.detached(priority: .background) {
            do {
                while let resp = try await iter.next() {
                    debugPrint(resp)
                    try resp.ensureValid(first: false, allowPrompts: allowPrompts)
                    switch resp.isPrompt {
                    case true:
                        // TODO: Handle prompt
                        break
                    case false:
                        // TODO: Handle message
                        break
                    }
                }
            } catch {
                // TODO: Log prompter stream error
            }
        }
        return (stream, identifier: initResp.identifier)
    }
}
