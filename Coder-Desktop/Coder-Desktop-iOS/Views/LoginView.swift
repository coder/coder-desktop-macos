import CoderSDK
import SwiftUI
import VPNLib

struct LoginView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var baseAccessURL: String = ""
    @State private var sessionToken: String = ""
    @State private var loginError: LoginError?
    @State private var loading: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server URL") {
                    TextField(
                        "Server URL",
                        text: $baseAccessURL,
                        prompt: Text("https://coder.example.com")
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
                Section("Session Token") {
                    SecureField("Session Token", text: $sessionToken)
                        .autocorrectionDisabled()
                        .privacySensitive()
                    if let cliAuthURL {
                        Link("Generate a session token", destination: cliAuthURL)
                            .font(.subheadline)
                    }
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if loading {
                            ProgressView()
                        } else {
                            Text("Sign In")
                        }
                    }
                }
            }
            .navigationTitle("Coder Desktop")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
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
            }
            .disabled(loading)
            .onAppear {
                baseAccessURL = state.baseAccessURL?.absoluteString ?? baseAccessURL
                sessionToken = state.sessionToken ?? sessionToken
            }
        }
    }

    private var cliAuthURL: URL? {
        guard let url = try? validateURL(
            baseAccessURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else {
            return nil
        }
        return url.appendingPathComponent("cli-auth")
    }

    func submit() async {
        loginError = nil
        sessionToken = sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sessionToken != "" else {
            return
        }
        let url: URL
        do {
            url = try validateURL(baseAccessURL.trimmingCharacters(in: .whitespacesAndNewlines))
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
        guard CoderVersion.minimum.compare(semver, options: .numeric) != .orderedDescending else {
            loginError = .outdatedCoderVersion
            return
        }
        state.login(baseAccessURL: url, sessionToken: sessionToken)
        dismiss()
    }
}

@discardableResult
func validateURL(_ url: String) throws(LoginError) -> URL {
    guard let url = URL(string: url) else {
        throw .invalidURL
    }
    guard url.scheme == "https" || url.scheme == "http" else {
        throw .invalidScheme
    }
    guard url.host != nil else {
        throw .noHost
    }
    return url
}

enum LoginError: Error {
    case invalidScheme
    case noHost
    case invalidURL
    case outdatedCoderVersion
    case missingServerVersion
    case failedAuth(SDKError)

    var description: String {
        switch self {
        case .invalidScheme:
            "Coder URL must use HTTPS or HTTP"
        case .noHost:
            "Coder URL must have a host"
        case .invalidURL:
            "Invalid Coder URL"
        case .outdatedCoderVersion:
            """
            The Coder deployment must be version \(CoderVersion.minimum)
            or higher to use this version of Coder Desktop.
            """
        case let .failedAuth(err):
            "Could not authenticate with Coder deployment:\n\(err.localizedDescription)"
        case .missingServerVersion:
            "Coder deployment did not provide a server version"
        }
    }

    var localizedDescription: String { description }
}
