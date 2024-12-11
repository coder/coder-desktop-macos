import SwiftUI

struct LoginForm<C: Client, S: Session>: View {
    @EnvironmentObject var session: S
    @EnvironmentObject var client: C
    @Environment(\.dismiss) private var dismiss

    @State private var baseAccessURL: String = ""
    @State private var sessionToken: String = ""
    @State private var loginError: LoginError?
    @State private var currentPage: LoginPage = .serverURL
    @State private var loading: Bool = false
    @FocusState private var focusedField: LoginField?

    var body: some View {
        VStack {
            VStack {
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
                loginError = nil
                baseAccessURL = session.baseAccessURL?.absoluteString ?? baseAccessURL
                sessionToken = ""
            }
            ZStack {
                if let loginError {
                    Text("\(loginError.description)")
                        .font(.headline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                } else if loading {
                    ProgressView()
                }
            }
            .frame(height: 30)
        }.padding()
            .frame(width: 450, height: 220)
            .disabled(loading)
    }

    private var serverURLPage: some View {
        VStack(spacing: 15) {
            Text("Coder Desktop").font(.title).padding(.bottom, 15)
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Server URL")
                    Spacer()
                    TextField("https://coder.example.com", text: $baseAccessURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disableAutocorrection(true)
                        .frame(width: 290, alignment: .leading)
                        .focused($focusedField, equals: .baseAccessURL)
                }
            }
            HStack {
                actionButton(title: "Next", action: next)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 10)
        }.padding(.horizontal, 15)
    }

    private var sessionTokenPage: some View {
        VStack {
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Server URL")
                    Spacer()
                    TextField("https://coder.example.com", text: $baseAccessURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disableAutocorrection(true)
                        .frame(width: 290, alignment: .leading)
                        .disabled(true)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Session Token")
                    Spacer()
                    SecureField("", text: $sessionToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disableAutocorrection(true)
                        .frame(width: 290, alignment: .leading)
                        .privacySensitive()
                        .focused($focusedField, equals: .sessionToken)
                }
                Link(
                    "Generate a token via the Web UI",
                    destination: URL(string: baseAccessURL)!.appendingPathComponent("cli-auth")
                ).font(.callout).foregroundColor(.blue).underline()
            }.padding()
            HStack {
                actionButton(title: "Back", action: back)
                actionButton(title: "Sign In", action: signIn)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }.padding(.top, 5)
        }
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
        }
    }

    private func next() {
        loginError = nil
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
            loginError = nil
            currentPage = .serverURL
            focusedField = .baseAccessURL
        }
    }

    private func signIn() {
        loginError = nil
        guard sessionToken != "" else {
            loginError = .invalidToken
            return
        }
        guard let url = URL(string: baseAccessURL), url.scheme == "https" else {
            loginError = .invalidURL
            return
        }
        loading = true
        client.initialise(url: url, token: sessionToken)
        Task {
            do {
                _ = try await client.user("me")
            } catch {
                loginError = .failedAuth
                loading = false
                return
            }
            session.store(baseAccessURL: url, sessionToken: sessionToken)
            loading = false
            dismiss()
        }
    }
}

enum LoginError {
    case invalidURL
    case invalidToken
    case failedAuth

    var description: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidToken:
            return "Invalid Session Token"
        case .failedAuth:
            return "Could not authenticate with Coder deployment"
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

#Preview {
    LoginForm<PreviewClient, PreviewSession>().environmentObject(PreviewSession())
}
