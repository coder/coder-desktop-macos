import CoderSDK
import SwiftUI

struct LoginForm<S: Session>: View {
    @EnvironmentObject var session: S
    @Environment(\.dismiss) private var dismiss

    @State private var baseAccessURL: String = ""
    @State private var sessionToken: String = ""
    @State private var loginError: LoginError?
    @State private var currentPage: LoginPage = .serverURL
    @State private var loading: Bool = false
    @FocusState private var focusedField: LoginField?

    let inspection = Inspection<Self>()

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
                baseAccessURL = session.baseAccessURL?.absoluteString ?? baseAccessURL
                sessionToken = ""
            }.padding(.vertical, 35)
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
            }
        }.padding()
            .frame(width: 450, height: 220)
            .disabled(loading)
            .onReceive(inspection.notice) { self.inspection.visit(self, $0) } // ViewInspector
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
        let client = Client(url: url, token: sessionToken)
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
                Button("Next", action: next)
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
                Button("Back", action: back)
                Button("Sign In") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }.padding(.top, 5)
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
            return "Invalid URL"
        case let .failedAuth(err):
            return "Could not authenticate with Coder deployment:\n\(err.description)"
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
    LoginForm<PreviewSession>()
        .environmentObject(PreviewSession())
}
