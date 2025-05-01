import CoderSDK
import os
import SDWebImageSwiftUI
import SwiftUI

struct WorkspaceAppIcon: View {
    let app: WorkspaceApp
    @Environment(\.openURL) private var openURL

    @State var isHovering: Bool = false
    @State var isPressed = false

    var body: some View {
        Group {
            Group {
                WebImage(
                    url: app.icon,
                    context: [.imageThumbnailPixelSize: Theme.Size.appIconSize]
                ) { $0 }
                    placeholder: {
                        if app.icon != nil {
                            ProgressView()
                        } else {
                            Text(app.displayName).frame(
                                width: Theme.Size.appIconWidth,
                                height: Theme.Size.appIconHeight
                            )
                        }
                    }.frame(
                        width: Theme.Size.appIconWidth,
                        height: Theme.Size.appIconHeight
                    )
            }.padding(4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2)
                .stroke(.secondary, lineWidth: 1)
                .opacity(isHovering && !isPressed ? 0.6 : 0.3)
        ).onHoverWithPointingHand { hovering in isHovering = hovering }
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
                    openURL(app.url)
                }
        ).help(app.displayName)
    }
}

struct WorkspaceApp {
    let slug: String
    let displayName: String
    let url: URL
    let icon: URL?

    var id: String { slug }

    private static let magicTokenString = "$SESSION_TOKEN"

    init(slug: String, displayName: String, url: URL, icon: URL?) {
        self.slug = slug
        self.displayName = displayName
        self.url = url
        self.icon = icon
    }

    init(
        _ original: CoderSDK.WorkspaceApp,
        iconBaseURL: URL,
        sessionToken: String
    ) throws(WorkspaceAppError) {
        slug = original.slug
        displayName = original.display_name

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

        let newUrlString = originalUrl.absoluteString.replacingOccurrences(
            of: Self.magicTokenString,
            with: sessionToken
        )
        guard let newUrl = URL(string: newUrlString) else {
            throw .invalidURL
        }
        url = newUrl

        var icon = original.icon
        if let originalIcon = original.icon,
           var components = URLComponents(url: originalIcon, resolvingAgainstBaseURL: false)
        {
            if components.host == nil {
                components.port = iconBaseURL.port
                components.scheme = iconBaseURL.scheme
                components.host = iconBaseURL.host(percentEncoded: false)
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
            return try WorkspaceApp(app, iconBaseURL: baseAccessURL, sessionToken: sessionToken)
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
        url: URL(string: "vscode://vscode-remote/ssh-remote+\(hostname)/\(path ?? "")")!,
        icon: icon
    )
}

func vscodeInsidersDisplayApp(hostname: String, baseIconURL: URL, path: String? = nil) -> WorkspaceApp {
    let icon = baseIconURL.appendingPathComponent("/icon/code.svg")
    return WorkspaceApp(
        slug: "-vscode-insiders",
        displayName: "VS Code Insiders Desktop",
        url: URL(string: "vscode-insiders://vscode-remote/ssh-remote+\(hostname)/\(path ?? "")")!,
        icon: icon
    )
}
