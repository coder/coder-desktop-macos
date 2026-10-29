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

struct WorkspaceApp {
    let slug: String
    let displayName: String
    let url: URL
    let icon: URL?
    /// Set when the link needs a session token but isn't trusted with one.
    let blockedReason: SessionTokenBlockReason?
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

    init(
        _ original: CoderSDK.WorkspaceApp,
        deploymentURL: URL,
        dashboardURL: URL?,
        sessionToken: String
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
        blockedReason = SessionTokenLink.blockReason(
            originalUrl.absoluteString,
            signedInURL: deploymentURL,
            dashboardURL: dashboardURL
        )
        if blockedReason == nil {
            let newUrlString = originalUrl.absoluteString.replacingOccurrences(
                of: SessionTokenLink.placeholder,
                with: sessionToken
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

// swiftlint:disable:next function_parameter_count
func agentToApps(
    _ logger: Logger,
    _ agent: CoderSDK.WorkspaceAgent,
    _ host: String,
    _ baseAccessURL: URL,
    _ dashboardURL: URL?,
    _ sessionToken: String
) -> [WorkspaceApp] {
    let workspaceApps = agent.apps.compactMap { app in
        var app = app
        // Dev container apps never get a token. coderd removes the placeholder
        // since coder/coder#31262, but older servers still send it.
        if agent.parent_id != nil, let url = app.url {
            app.url = URL(string: url.absoluteString.replacingOccurrences(of: SessionTokenLink.placeholder, with: ""))
        }
        do throws(WorkspaceAppError) {
            return try WorkspaceApp(
                app,
                deploymentURL: baseAccessURL,
                dashboardURL: dashboardURL,
                sessionToken: sessionToken
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

/// The path setter percent-encodes the host and directory, so they can't add a
/// query or fragment.
private func vscodeRemoteURL(scheme: String, hostname: String, path: String?) -> URL {
    var components = URLComponents()
    components.scheme = scheme
    components.host = "vscode-remote"
    components.path = "/ssh-remote+\(hostname)/\(path ?? "")"
    return components.url!
}
