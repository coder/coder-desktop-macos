import SwiftUI

class PreviewSession: Session {
    @Published var hasSession: Bool
    @Published var sessionToken: String?
    @Published var baseAccessURL: URL?

    init() {
        hasSession = false
        sessionToken = nil
        baseAccessURL = nil
    }

    func store(baseAccessURL: URL, sessionToken: String) {
        hasSession = true
        self.baseAccessURL = baseAccessURL
        self.sessionToken = sessionToken
    }

    func clear() {
        hasSession = false
        sessionToken = nil
    }
}
