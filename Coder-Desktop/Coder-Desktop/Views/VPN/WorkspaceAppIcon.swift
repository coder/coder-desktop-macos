import CoderSDK
import os
import SDWebImageSwiftUI
import SwiftUI

struct WorkspaceAppIcon: View {
    let app: WorkspaceApp
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    @State var isHovering: Bool = false
    @State var isPressed = false

    var body: some View {
        Group {
            if let systemImage = app.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
            } else {
                WebImage(
                    url: app.icon,
                    context: [.imageThumbnailPixelSize: Theme.Size.appIconSize]
                ) { $0 }
                    placeholder: {
                        if app.icon != nil {
                            CircularProgressView(value: nil, strokeWidth: 2, diameter: 10)
                        } else {
                            Image(systemName: "questionmark")
                        }
                    }
            }
        }.frame(
            width: Theme.Size.appIconWidth,
            height: Theme.Size.appIconHeight
        ).padding(6)
            .background(isHovering ? Color.accentColor.opacity(0.8) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovering in isHovering = hovering && app.blockedReason == nil }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = false
                        }
                        guard app.blockedReason == nil else { return }
                        if let command = app.terminalCommand {
                            openTerminal(command: command)
                            return
                        }
                        let scheme = app.url.scheme?.lowercased() ?? ""
                        if app.confirmBeforeOpening, !state.trustedAppSchemes.contains(scheme) {
                            confirmOpen(scheme: scheme)
                        } else {
                            openURL(app.url)
                        }
                    }
            )
            .opacity(app.blockedReason == nil ? 1 : 0.4)
            .help(app.blockedReason.map { reason in "\(app.displayName): \(reason.description)" } ?? app.displayName)
    }

    private func openTerminal(command: String) {
        Task {
            do {
                try await Task.detached {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    process.arguments = [
                        "-e",
                        """
                        on run argv
                            tell application "Terminal"
                                activate
                                do script (item 1 of argv)
                            end tell
                        end run
                        """,
                        command,
                    ]
                    let errors = Pipe()
                    process.standardError = errors
                    try process.run()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus != 0 {
                        let message = String(data: errorData, encoding: .utf8) ?? "Could not open Terminal."
                        throw TerminalLaunchError(message: message)
                    }
                }.value
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not open Terminal"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                dismiss()
                alert.runModal()
            }
        }
    }

    /// `.alert` from SwiftUI doesn't play nice when the calling view is in the
    /// menu bar.
    private func confirmOpen(scheme: String) {
        let alert = NSAlert()
        alert.messageText = "Open \(app.displayName)?"
        alert.informativeText = "This opens a \(scheme): link in another app on your computer."
        alert.alertStyle = .informational
        let dontAskAgain = NSButton(checkboxWithTitle: "Don't ask again for \(scheme): links", target: nil, action: nil)
        alert.accessoryView = dontAskAgain
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        dismiss()
        if alert.runModal() == .alertFirstButtonReturn {
            if dontAskAgain.state == .on {
                state.trustedAppSchemes.insert(scheme)
            }
            openURL(app.url)
        }
    }
}

private struct TerminalLaunchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The signed-in deployment that app links are built for.
struct CoderSession {
    let baseAccessURL: URL
    /// The deployment's access URL from build info, if it has loaded.
    let dashboardURL: URL?
    let sessionToken: String
}

struct WorkspaceApp {
    let slug: String
    let displayName: String
    let url: URL
    let icon: URL?
    let systemImage: String?
    let terminalCommand: String?
    /// Set when the link needs a session token but isn't trusted with one.
    let blockedReason: SessionTokenBlockReason?
    let confirmBeforeOpening: Bool

    var id: String { slug }

    init(
        slug: String, displayName: String, url: URL, icon: URL?,
        systemImage: String? = nil, terminalCommand: String? = nil
    ) {
        self.slug = slug
        self.displayName = displayName
        self.url = url
        self.icon = icon
        self.systemImage = systemImage
        self.terminalCommand = terminalCommand
        blockedReason = nil
        confirmBeforeOpening = false
    }

    init(
        _ original: CoderSDK.WorkspaceApp,
        session: CoderSession
    ) throws(WorkspaceAppError) {
        slug = original.slug
        systemImage = nil
        terminalCommand = nil
        // Same behaviour as the web UI
        displayName = original.display_name ?? original.slug

        guard original.external else {
            throw .isWebApp
        }

        guard let originalUrl = original.url else {
            throw .missingURL
        }

        if let command = original.command, !command.isEmpty {
            throw .isCommandApp
        }

        // We don't want to show buttons for any websites, like internal wikis
        // or portals. Those *should* have 'external' set, but if they don't:
        guard originalUrl.scheme != "https", originalUrl.scheme != "http" else {
            throw .isWebApp
        }

        confirmBeforeOpening = !SessionTokenLink.isKnownHandler(originalUrl.absoluteString)
        blockedReason = SessionTokenLink.blockReason(
            originalUrl.absoluteString,
            signedInURL: session.baseAccessURL,
            dashboardURL: session.dashboardURL
        )
        if blockedReason == nil {
            let newUrlString = originalUrl.absoluteString.replacingOccurrences(
                of: SessionTokenLink.placeholder,
                with: session.sessionToken
            )
            guard let newUrl = URL(string: newUrlString) else {
                throw .invalidURL
            }
            url = newUrl
        } else {
            url = originalUrl
        }

        var icon = original.icon
        if let originalIcon = original.icon,
           var components = URLComponents(url: originalIcon, resolvingAgainstBaseURL: false)
        {
            if components.host == nil {
                components.port = session.baseAccessURL.port
                components.scheme = session.baseAccessURL.scheme
                components.host = session.baseAccessURL.host(percentEncoded: false)
            }

            if let newIconURL = components.url {
                icon = newIconURL
            }
        }
        self.icon = icon
    }
}

enum WorkspaceAppError: Error {
    case invalidURL
    case missingURL
    case isCommandApp
    case isWebApp

    var description: String {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .missingURL:
            "Missing URL"
        case .isCommandApp:
            "is a Command App"
        case .isWebApp:
            "is an External App"
        }
    }

    var localizedDescription: String { description }
}

func agentToApps(
    _ logger: Logger,
    _ agent: CoderSDK.WorkspaceAgent,
    _ host: String,
    _ session: CoderSession,
    workspaceAgentName: String
) -> [WorkspaceApp] {
    let workspaceApps = agent.apps.compactMap { app in
        if app.slug == "chat", !app.external, let command = app.command, !command.isEmpty {
            return chatCommandApp(app, session: session, workspaceAgentName: workspaceAgentName)
        }
        var app = app
        // Dev container apps never get a token. coderd removes the placeholder
        // since coder/coder#31262, but older servers still send it.
        if agent.parent_id != nil, let url = app.url {
            app.url = URL(string: url.absoluteString.replacingOccurrences(of: SessionTokenLink.placeholder, with: ""))
        }
        do throws(WorkspaceAppError) {
            return try WorkspaceApp(app, session: session)
        } catch {
            logger.warning("Skipping WorkspaceApp '\(app.slug)' for \(host): \(error.localizedDescription)")
            return nil
        }
    }

    let displayApps = agent.display_apps.compactMap { displayApp in
        switch displayApp {
        case .vscode:
            return vscodeDisplayApp(
                hostname: host,
                baseIconURL: session.baseAccessURL,
                path: agent.expanded_directory
            )
        case .vscode_insiders:
            return vscodeInsidersDisplayApp(
                hostname: host,
                baseIconURL: session.baseAccessURL,
                path: agent.expanded_directory
            )
        case .ssh_helper:
            guard let terminal = terminalDisplayApp(
                host: host, session: session, workspaceAgentName: workspaceAgentName
            ) else {
                logger.error("Could not create SSH URL for \(host)")
                return nil
            }
            return terminal
        default:
            logger.info("Skipping DisplayApp '\(displayApp.rawValue)' for \(host)")
            return nil
        }
    }

    return displayApps + workspaceApps
}

private func chatCommandApp(
    _ app: CoderSDK.WorkspaceApp, session: CoderSession, workspaceAgentName: String
) -> WorkspaceApp {
    var components = URLComponents(
        url: session.baseAccessURL
            .appending(path: "@me")
            .appending(path: workspaceAgentName)
            .appending(path: "terminal"),
        resolvingAgainstBaseURL: false
    )!
    components.queryItems = [URLQueryItem(name: "app", value: app.slug)]
    return WorkspaceApp(
        slug: app.slug,
        displayName: app.display_name ?? "Chat",
        url: components.url!,
        icon: nil,
        systemImage: "bubble.left.and.bubble.right"
    )
}

private func terminalDisplayApp(host: String, session: CoderSession, workspaceAgentName: String) -> WorkspaceApp? {
    var components = URLComponents()
    components.scheme = "ssh"
    components.host = host
    guard let url = components.url else { return nil }
    return WorkspaceApp(
        slug: "-terminal",
        displayName: "Open terminal",
        url: url,
        icon: nil,
        systemImage: "terminal",
        terminalCommand: coderSSHCommand(deploymentURL: session.baseAccessURL, workspaceAgentName: workspaceAgentName)
    )
}

func coderSSHCommand(deploymentURL: URL, workspaceAgentName: String) -> String {
    func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    return "coder --url \(shellQuote(deploymentURL.absoluteString)) ssh \(shellQuote(workspaceAgentName))"
}

func vscodeDisplayApp(hostname: String, baseIconURL: URL, path: String? = nil) -> WorkspaceApp {
    let icon = baseIconURL.appendingPathComponent("/icon/code.svg")
    return WorkspaceApp(
        // Leading hyphen as to not conflict with a real app slug, since we only use
        // slugs as SwiftUI IDs
        slug: "-vscode",
        displayName: "VS Code Desktop",
        url: vscodeRemoteURL(scheme: "vscode", hostname: hostname, path: path),
        icon: icon
    )
}

func vscodeInsidersDisplayApp(hostname: String, baseIconURL: URL, path: String? = nil) -> WorkspaceApp {
    let icon = baseIconURL.appendingPathComponent("/icon/code-insiders.svg")
    return WorkspaceApp(
        slug: "-vscode-insiders",
        displayName: "VS Code Insiders Desktop",
        url: vscodeRemoteURL(scheme: "vscode-insiders", hostname: hostname, path: path),
        icon: icon
    )
}

/// The path setter percent-encodes the host and directory, so they can't add a
/// query or fragment.
private func vscodeRemoteURL(scheme: String, hostname: String, path: String?) -> URL {
    var components = URLComponents()
    components.scheme = scheme
    components.host = "vscode-remote"
    components.path = "/ssh-remote+\(hostname)/\(path ?? "")"
    return components.url!
}
