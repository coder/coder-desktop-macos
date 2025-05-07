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

    func primaryHost(hostnameSuffix: String) -> String {
        switch self {
        case let .agent(agent): agent.primaryHost
        case .offlineWorkspace: "\(wsName).\(hostnameSuffix)"
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
    @Environment(\.openURL) private var openURL

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "VPNMenu")

    let item: VPNMenuItem
    let baseAccessURL: URL
    @Binding var expandedItem: VPNMenuItem.ID?
    @Binding var userInteracted: Bool

    @State private var nameIsSelected: Bool = false

    @State private var apps: [WorkspaceApp] = []

    var hasApps: Bool { !apps.isEmpty }

    private var itemName: AttributedString {
        let name = item.primaryHost(hostnameSuffix: state.hostnameSuffix)

        var formattedName = AttributedString(name)
        formattedName.foregroundColor = .primary

        if let range = formattedName.range(of: ".\(state.hostnameSuffix)", options: .backwards) {
            formattedName[range].foregroundColor = .secondary
        }
        return formattedName
    }

    private var isExpanded: Bool {
        expandedItem == item.id
    }

    private var wsURL: URL {
        // TODO: CoderVPN currently only supports owned workspaces
        baseAccessURL.appending(path: "@me").appending(path: item.wsName)
    }

    private func toggleExpanded() {
        userInteracted = true
        if isExpanded {
            withAnimation(.snappy(duration: Theme.Animation.collapsibleDuration)) {
                expandedItem = nil
            }
        } else {
            withAnimation(.snappy(duration: Theme.Animation.collapsibleDuration)) {
                expandedItem = item.id
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Button(action: toggleExpanded) {
                    HStack(spacing: Theme.Size.trayPadding) {
                        AnimatedChevron(isExpanded: isExpanded, color: .secondary)
                        Text(itemName).lineLimit(1).truncationMode(.tail)
                        Spacer()
                    }.padding(.horizontal, Theme.Size.trayPadding)
                        .frame(minHeight: 22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(nameIsSelected ? .white : .primary)
                        .background(nameIsSelected ? Color.accentColor.opacity(0.8) : .clear)
                        .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
                        .onHover { hovering in
                            nameIsSelected = hovering
                        }
                }.buttonStyle(.plain).padding(.trailing, 3)
                MenuItemIcons(item: item, wsURL: wsURL)
            }
            if isExpanded {
                if hasApps {
                    MenuItemCollapsibleView(apps: apps)
                } else {
                    HStack {
                        Text(item.status == .off ? "Workspace is offline." : "No apps available.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, Theme.Size.trayInset)
                            .padding(.top, 7)
                    }
                }
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

struct MenuItemCollapsibleView: View {
    private let defaultVisibleApps = 6
    let apps: [WorkspaceApp]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(apps.prefix(defaultVisibleApps), id: \.id) { app in
                WorkspaceAppIcon(app: app)
                    .frame(width: Theme.Size.appIconWidth, height: Theme.Size.appIconHeight)
            }
            Spacer()
        }
        .padding(.leading, 32)
        .padding(.bottom, 5)
        .padding(.top, 10)
    }
}

struct MenuItemIcons: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL

    let item: VPNMenuItem
    let wsURL: URL

    @State private var copyIsSelected: Bool = false
    @State private var webIsSelected: Bool = false

    func copyToClipboard() {
        let primaryHost = item.primaryHost(hostnameSuffix: state.hostnameSuffix)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(primaryHost, forType: .string)
    }

    var body: some View {
        StatusDot(color: item.status.color)
            .padding(.trailing, 3)
            .padding(.top, 1)
        MenuItemIconButton(systemName: "doc.on.doc", action: copyToClipboard)
            .font(.system(size: 9))
            .symbolVariant(.fill)
        MenuItemIconButton(systemName: "globe", action: { openURL(wsURL) })
            .contentShape(Rectangle())
            .font(.system(size: 12))
            .padding(.trailing, Theme.Size.trayMargin)
    }
}

struct MenuItemIconButton: View {
    let systemName: String
    @State var isSelected: Bool = false
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .padding(3)
                .contentShape(Rectangle())
        }.foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.accentColor.opacity(0.8) : .clear)
            .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
            .onHover { hovering in isSelected = hovering }
            .buttonStyle(.plain)
    }
}

struct AnimatedChevron: View {
    let isExpanded: Bool
    let color: Color

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
    }
}
