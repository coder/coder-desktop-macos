import GRPCCore

extension MutagenDaemon {
    /// Hosts a prompter on the daemon for the duration of `body`, which is
    /// passed the prompter identifier to include in requests that may prompt.
    func withPrompter<T>(
        allowPrompts: Bool = true,
        promptCallback: (@MainActor (String) -> Void)? = nil,
        _ body: (_ promptID: String) async throws(DaemonError) -> T
    ) async throws(DaemonError) -> T {
        let (replies, replyContinuation) = AsyncStream.makeStream(of: Prompting_HostRequest.self)
        let (identifier, identifierContinuation) = AsyncThrowingStream.makeStream(of: String.self)
        let prompt = client!.prompt
        let logger = logger

        let hostTask = Task.detached(priority: .background) {
            do {
                try await prompt.host { writer in
                    try await writer.write(.with { req in req.allowPrompts = allowPrompts })
                    for await reply in replies {
                        try await writer.write(reply)
                    }
                } onResponse: { response in
                    var first = true
                    for try await msg in response.messages {
                        try msg.ensureValid(first: first, allowPrompts: allowPrompts)
                        if first {
                            first = false
                            identifierContinuation.yield(msg.identifier)
                            continue
                        }
                        replyContinuation.yield(reply(to: msg, promptCallback: promptCallback))
                    }
                }
                identifierContinuation.finish()
            } catch {
                identifierContinuation.finish(throwing: error)
                // The stream is cancelled once `body` returns
                if !Task.isCancelled {
                    logger.critical("Prompt stream failed: \(error)")
                }
            }
        }
        defer {
            replyContinuation.finish()
            hostTask.cancel()
        }

        let promptID: String?
        do {
            var iter = identifier.makeAsyncIterator()
            promptID = try await iter.next()
        } catch let error as DaemonError {
            throw error
        } catch {
            throw .grpcFailure(error)
        }
        guard let promptID else {
            throw .unexpectedStreamClosure
        }
        return try await body(promptID)
    }
}

private func reply(
    to msg: Prompting_HostResponse,
    promptCallback: (@MainActor (String) -> Void)?
) -> Prompting_HostRequest {
    var reply: Prompting_HostRequest = .init()
    if msg.isPrompt {
        // Handle SSH key prompts
        if msg.message.contains("yes/no/[fingerprint]") {
            reply.response = "yes"
        }
        // Any other messages that require a non-empty response will
        // cause the create op to fail, showing an error. This is ok for now.
    } else {
        Task { @MainActor in promptCallback?(msg.message) }
    }
    return reply
}
