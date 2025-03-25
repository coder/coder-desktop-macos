import CoderSDK
import SwiftUI
import VPNLib

struct LoginForm: View {
    @EnvironmentObject var state: AppState
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
            baseAccessURL = state.baseAccessURL?.absoluteString ?? baseAccessURL
            sessionToken = state.sessionToken ?? sessionToken
        }
        .alert("Error", isPresented: Binding(
            get: { loginError != nil },
            set: { isPresented in
                if !isPresented {
                    loginError = nil
                }
            }
        )) {} message: {
            Text(loginError?.description ?? "An unknown error occurred.")
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
        let url: URL
        do {
            url = try validateURL(baseAccessURL)
        } catch {
            loginError = error
            return
        }
        loading = true
        defer { loading = false }
        let client = Client(url: url, token: sessionToken, headers: state.literalHeaders.map { $0.toSDKHeader() })
        do {
            _ = try await client.user("me")
        } catch {
            loginError = .failedAuth(error)
            return
        }
        let buildInfo: BuildInfoResponse
        do {
            buildInfo = try await client.buildInfo()
        } catch {
            loginError = .failedAuth(error)
            return
        }
        guard let semver = buildInfo.semver else {
            loginError = .missingServerVersion
            return
        }
        // x.compare(y) is .orderedDescending if x > y
        guard SignatureValidator.minimumCoderVersion.compare(semver, options: .numeric) != .orderedDescending else {
            loginError = .outdatedCoderVersion
            return
        }
        state.login(baseAccessURL: url, sessionToken: sessionToken)
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
                    SecureField("Session Token", text: $sessionToken)
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
        do {
            try validateURL(baseAccessURL)
        } catch {
            loginError = error
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

@discardableResult
func validateURL(_ url: String) throws(LoginError) -> URL {
    guard let url = URL(string: url) else {
        throw LoginError.invalidURL
    }
    guard url.scheme == "https" else {
        throw LoginError.httpsRequired
    }
    guard url.host != nil else {
        throw LoginError.noHost
    }
    return url
}

enum LoginError: Error {
    case httpsRequired
    case noHost
    case invalidURL
    case outdatedCoderVersion
    case missingServerVersion
    case failedAuth(ClientError)

    var description: String {
        switch self {
        case .httpsRequired:
            "URL must use HTTPS"
        case .noHost:
            "URL must have a host"
        case .invalidURL:
            "Invalid URL"
        case .outdatedCoderVersion:
            """
            The Coder deployment must be version \(SignatureValidator.minimumCoderVersion)
            or higher to use Coder Desktop.
            """
        case let .failedAuth(err):
            "Could not authenticate with Coder deployment:\n\(err.localizedDescription)"
        case .missingServerVersion:
            "Coder deployment did not provide a server version"
        }
    }

    var localizedDescription: String { description }
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
        LoginForm()
            .environmentObject(AppState(persistent: false))
    }
#endif
