import CoderSDK
import SwiftUI

struct LoginForm<S: Session>: View {
    @EnvironmentObject var session: S
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss

    @State private var baseAccessURL: String = ""
    @State private var sessionToken: String = ""
    @State private var loginError: LoginError?
    @State private var currentPage: LoginPage = .serverURL
    @State private var loading: Bool = false
    @FocusState private var focusedField: LoginField?

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            switch currentPage {
            case .serverURL:
                serverURLPage
                    .transition(.move(edge: .leading))
                    .onAppear {
                        DispatchQueue.main.async {
                            focusedField = .baseAccessURL
                        }
                    }
            case .sessionToken:
                sessionTokenPage
                    .transition(.move(edge: .trailing))
                    .onAppear {
                        DispatchQueue.main.async {
                            focusedField = .sessionToken
                        }
                    }
            }
        }
        .animation(.easeInOut, value: currentPage)
        .onAppear {
            baseAccessURL = session.baseAccessURL?.absoluteString ?? baseAccessURL
            sessionToken = ""
        }
        .alert("Error", isPresented: Binding(
            get: { loginError != nil },
            set: { isPresented in
                if !isPresented {
                    loginError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: {
            Text(loginError?.description ?? "")
        }.disabled(loading)
        .frame(width: 550)
        .fixedSize()
        .onReceive(inspection.notice) { inspection.visit(self, $0) } // ViewInspector
    }

    func submit() async {
        loginError = nil
        guard sessionToken != "" else {
            return
        }
        guard let url = URL(string: baseAccessURL), url.scheme == "https" else {
            loginError = .invalidURL
            return
        }
        loading = true
        defer { loading = false }
        let client = Client(url: url, token: sessionToken, headers: settings.literalHeaders.map { $0.toSDKHeader() })
        do {
            _ = try await client.user("me")
        } catch {
            loginError = .failedAuth(error)
            return
        }
        session.store(baseAccessURL: url, sessionToken: sessionToken)
        dismiss()
    }

    private var serverURLPage: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Coder Desktop").font(.title).padding(.top, 10)
            Form {
                Section {
                    TextField(
                        "Server URL",
                        text: $baseAccessURL,
                        prompt: Text("https://coder.example.com")
                    ).autocorrectionDisabled()
                        .focused($focusedField, equals: .baseAccessURL)
                }
            }.formStyle(.grouped).scrollDisabled(true).padding(.horizontal)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: { dismiss() }).keyboardShortcut(.cancelAction)
                Button("Next", action: next)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
    }

    private var cliAuthURL: URL {
        URL(string: baseAccessURL)!.appendingPathComponent("cli-auth")
    }

    private var sessionTokenPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField(
                        "Server URL",
                        text: $baseAccessURL,
                        prompt: Text("https://coder.example.com")
                    ).disabled(true)
                }
                Section {
                    SecureField("Session Token", text: $sessionToken, prompt: Text("●●●●●●●●"))
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .focused($focusedField, equals: .sessionToken)
                    HStack(spacing: 0) {
                        Text("Generate a session token at ")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ResponsiveLink(title: cliAuthURL.absoluteString, destination: cliAuthURL)
                    }
                }
            }.formStyle(.grouped).scrollDisabled(true).padding(.horizontal)
            Divider()
            HStack {
                Spacer()
                Button("Back", action: back).keyboardShortcut(.cancelAction)
                Button("Sign In") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
    }

    private func next() {
        guard baseAccessURL != "" else {
            return
        }
        guard let url = URL(string: baseAccessURL), url.scheme == "https" else {
            loginError = .invalidURL
            return
        }
        withAnimation {
            currentPage = .sessionToken
            focusedField = .sessionToken
        }
    }

    private func back() {
        withAnimation {
            currentPage = .serverURL
            focusedField = .baseAccessURL
        }
    }
}

enum LoginError {
    case invalidURL
    case failedAuth(ClientError)

    var description: String {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case let .failedAuth(err):
            "Could not authenticate with Coder deployment:\n\(err.description)"
        }
    }
}

enum LoginPage {
    case serverURL
    case sessionToken
}

enum LoginField: Hashable {
    case baseAccessURL
    case sessionToken
}

#if DEBUG
    #Preview {
        LoginForm<PreviewSession>()
            .environmentObject(PreviewSession())
    }
#endif
