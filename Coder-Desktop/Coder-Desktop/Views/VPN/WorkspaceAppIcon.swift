import CoderSDK
import os
import SDWebImageSwiftUI
import SwiftUI

struct WorkspaceAppIcon: View {
    let app: WorkspaceApp
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State var isHovering: Bool = false
    @State var isPressed = false

    var body: some View {
        WebImage(
            url: app.icon,
            context: [.imageThumbnailPixelSize: Theme.Size.appIconSize]
        ) { $0 }
            placeholder: {
                if app.icon != nil {
                    CircularProgressView(value: nil, strokeWidth: 2, diameter: 10)
                } else {
                    Image(systemName: "questionmark").frame(
                        width: Theme.Size.appIconWidth,
                        height: Theme.Size.appIconHeight
                    )
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
                        if app.confirmBeforeOpening {
                            confirmOpen()
                        } else {
                            openURL(app.url)
                        }
                    }
            )
            .opacity(app.blockedReason == nil ? 1 : 0.4)
            .help(app.blockedReason.map { "\(app.displayName): \($0)" } ?? app.displayName)
    }

    /// `.alert` from SwiftUI doesn't play nice when the calling view is in the
    /// menu bar.
    private func confirmOpen() {
        let alert = NSAlert()
        alert.messageText = "Open \(app.displayName)?"
        alert.informativeText = "This opens a \(app.url.scheme ?? ""): link in another app on your computer."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        dismiss()
        if alert.runModal() == .alertFirstButtonReturn {
            openURL(app.url)
        }
    }
}

struct WorkspaceApp {
    let slug: String
    let displayName: String
    let url: URL
    let icon: URL?
    /// Set when the app's link needs a session token but isn't trusted with
    /// one. Such apps are shown disabled with this message.
    let blockedReason: String?
    /// True when the user must confirm before the app's link is opened.
    let confirmBeforeOpening: Bool

    var id: String { slug }

    init(slug: String, displayName: String, url: URL, icon: URL?) {
        self.slug = slug
        self.displayName = displayName
        self.url = url
        self.icon = icon
        blockedReason = nil
        confirmBeforeOpening = false
    }

    /// `deploymentURL` is the Coder deployment the user is signed in to. It is
    /// the only `url` a link may name to receive `sessionToken`.
    init(
        _ original: CoderSDK.WorkspaceApp,
        deploymentURL: URL,
        sessionToken: String,
        isSubAgentApp: Bool = false
    ) throws(WorkspaceAppError) {
        slug = original.slug
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
        if let newUrlString = SessionTokenLink.substitute(
            originalUrl.absoluteString,
            deploymentURL: deploymentURL,
            token: sessionToken,
            isSubAgentApp: isSubAgentApp
        ) {
            guard let newUrl = URL(string: newUrlString) else {
                throw .invalidURL
            }
            url = newUrl
            blockedReason = nil
        } else {
            url = originalUrl
            blockedReason = SessionTokenLink.blockedMessage + " " + (isSubAgentApp
                ? "Fix the app's url in the dev container's devcontainer.json."
                : "Ask your template administrator to fix the app's url in the template's coder_app configuration.")
        }

        var icon = original.icon
        if let originalIcon = original.icon,
           var components = URLComponents(url: originalIcon, resolvingAgainstBaseURL: false)
        {
            if components.host == nil {
                components.port = deploymentURL.port
                components.scheme = deploymentURL.scheme
                components.host = deploymentURL.host(percentEncoded: false)
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
    _ baseAccessURL: URL,
    _ sessionToken: String
) -> [WorkspaceApp] {
    let workspaceApps = agent.apps.compactMap { app in
        do throws(WorkspaceAppError) {
            return try WorkspaceApp(
                app,
                deploymentURL: baseAccessURL,
                sessionToken: sessionToken,
                isSubAgentApp: agent.parent_id != nil
            )
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
                baseIconURL: baseAccessURL,
                path: agent.expanded_directory
            )
        case .vscode_insiders:
            return vscodeInsidersDisplayApp(
                hostname: host,
                baseIconURL: baseAccessURL,
                path: agent.expanded_directory
            )
        default:
            logger.info("Skipping DisplayApp '\(displayApp.rawValue)' for \(host)")
            return nil
        }
    }

    return displayApps + workspaceApps
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

/// Builds a VS Code Remote SSH link. The path setter percent-encodes the host
/// and directory, so they can't add a query or fragment to the link.
private func vscodeRemoteURL(scheme: String, hostname: String, path: String?) -> URL {
    var components = URLComponents()
    components.scheme = scheme
    components.host = "vscode-remote"
    components.path = "/ssh-remote+\(hostname)/\(path ?? "")"
    return components.url!
}
