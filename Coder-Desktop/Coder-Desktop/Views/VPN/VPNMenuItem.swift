import CoderSDK
import os
import SwiftUI

// Each row in the workspaces list is an agent or an offline workspace
enum VPNMenuItem: Equatable, Comparable, Identifiable {
    case agent(Agent)
    case offlineWorkspace(Workspace)

    var wsName: String {
        switch self {
        case let .agent(agent): agent.wsName
        case let .offlineWorkspace(workspace): workspace.name
        }
    }

    var status: AgentStatus {
        switch self {
        case let .agent(agent): agent.status
        case .offlineWorkspace: .off
        }
    }

    var id: UUID {
        switch self {
        case let .agent(agent): agent.id
        case let .offlineWorkspace(workspace): workspace.id
        }
    }

    var workspaceID: UUID {
        switch self {
        case let .agent(agent): agent.wsID
        case let .offlineWorkspace(workspace): workspace.id
        }
    }

    static func < (lhs: VPNMenuItem, rhs: VPNMenuItem) -> Bool {
        switch (lhs, rhs) {
        case let (.agent(lhsAgent), .agent(rhsAgent)):
            lhsAgent < rhsAgent
        case let (.offlineWorkspace(lhsWorkspace), .offlineWorkspace(rhsWorkspace)):
            lhsWorkspace < rhsWorkspace
        // Agents always appear before offline workspaces
        case (.offlineWorkspace, .agent):
            false
        case (.agent, .offlineWorkspace):
            true
        }
    }
}

struct MenuItemView: View {
    @EnvironmentObject var state: AppState

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNMenu")

    let item: VPNMenuItem
    let baseAccessURL: URL

    @State private var nameIsSelected: Bool = false
    @State private var copyIsSelected: Bool = false

    private let defaultVisibleApps = 5
    @State private var apps: [WorkspaceApp] = []

    private var itemName: AttributedString {
        let name = switch item {
        case let .agent(agent): agent.primaryHost
        case .offlineWorkspace: "\(item.wsName).\(state.hostnameSuffix)"
        }

        var formattedName = AttributedString(name)
        formattedName.foregroundColor = .primary

        if let range = formattedName.range(of: ".\(state.hostnameSuffix)", options: .backwards) {
            formattedName[range].foregroundColor = .secondary
        }
        return formattedName
    }

    private var wsURL: URL {
        // TODO: CoderVPN currently only supports owned workspaces
        baseAccessURL.appending(path: "@me").appending(path: item.wsName)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Link(destination: wsURL) {
                    HStack(spacing: Theme.Size.trayPadding) {
                        StatusDot(color: item.status.color)
                        Text(itemName).lineLimit(1).truncationMode(.tail)
                        Spacer()
                    }.padding(.horizontal, Theme.Size.trayPadding)
                        .frame(minHeight: 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(nameIsSelected ? .white : .primary)
                        .background(nameIsSelected ? Color.accentColor.opacity(0.8) : .clear)
                        .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
                        .onHoverWithPointingHand { hovering in
                            nameIsSelected = hovering
                        }
                    Spacer()
                }.buttonStyle(.plain)
                if case let .agent(agent) = item {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(agent.primaryHost, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .symbolVariant(.fill)
                            .padding(3)
                            .contentShape(Rectangle())
                    }.foregroundStyle(copyIsSelected ? .white : .primary)
                        .imageScale(.small)
                        .background(copyIsSelected ? Color.accentColor.opacity(0.8) : .clear)
                        .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
                        .onHoverWithPointingHand { hovering in copyIsSelected = hovering }
                        .buttonStyle(.plain)
                        .padding(.trailing, Theme.Size.trayMargin)
                }
            }
            if !apps.isEmpty {
                HStack(spacing: 17) {
                    ForEach(apps.prefix(defaultVisibleApps), id: \.id) { app in
                        WorkspaceAppIcon(app: app)
                            .frame(width: Theme.Size.appIconWidth, height: Theme.Size.appIconHeight)
                    }
                    if apps.count < defaultVisibleApps {
                        Spacer()
                    }
                }
                .padding(.leading, apps.count < defaultVisibleApps ? 14 : 0)
                .padding(.bottom, 5)
                .padding(.top, 10)
            }
        }
        .task { await loadApps() }
    }

    func loadApps() async {
        // If this menu item is an agent, and the user is logged in
        if case let .agent(agent) = item,
           let client = state.client,
           let baseAccessURL = state.baseAccessURL,
           // Like the CLI, we'll re-use the existing session token to populate the URL
           let sessionToken = state.sessionToken
        {
            let workspace: CoderSDK.Workspace
            do {
                workspace = try await retry(floor: .milliseconds(100), ceil: .seconds(10)) {
                    do {
                        return try await client.workspace(item.workspaceID)
                    } catch {
                        logger.error("Failed to load apps for workspace \(item.wsName): \(error.localizedDescription)")
                        throw error
                    }
                }
            } catch { return } // Task cancelled

            if let wsAgent = workspace
                .latest_build.resources
                .compactMap(\.agents)
                .flatMap(\.self)
                .first(where: { $0.id == agent.id })
            {
                apps = agentToApps(logger, wsAgent, agent.primaryHost, baseAccessURL, sessionToken)
            } else {
                logger.error("Could not find agent '\(agent.id)' in workspace '\(item.wsName)' resources")
            }
        }
    }
}
