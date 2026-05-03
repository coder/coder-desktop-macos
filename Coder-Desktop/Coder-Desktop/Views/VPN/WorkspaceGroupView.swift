import SwiftUI

/// WorkspaceGroupView renders one workspace's agents. Single-agent and offline
/// workspaces fall through to the existing flat MenuItemView; workspaces with
/// multiple agents get a collapsible header with their agents nested below,
/// and child agents (those with a parent_id) are nested under their parent.
struct WorkspaceGroupView: View {
    let group: WorkspaceGroup
    let baseAccessURL: URL
    @Binding var expandedItem: UUID?
    @Binding var userInteracted: Bool

    /// Apps-section expansion for nested agent rows is local to the group so it
    /// doesn't fight the outer expandedItem (which controls workspace-level
    /// expansion for multi-agent groups).
    @State private var nestedExpandedAgent: UUID?

    var body: some View {
        if group.agents.count <= 1 {
            // Single-agent or offline: the row represents the workspace, so
            // display the workspace name. Copy-to-clipboard and the tooltip
            // still use the full FQDN.
            let item: VPNMenuItem = group.agents.first.map { .agent($0) }
                ?? .offlineWorkspace(group.workspace)
            MenuItemView(
                item: item,
                baseAccessURL: baseAccessURL,
                expandedItem: $expandedItem,
                userInteracted: $userInteracted,
                displayLabel: group.workspace.name
            )
        } else {
            VStack(spacing: 0) {
                WorkspaceHeaderRow(
                    group: group,
                    baseAccessURL: baseAccessURL,
                    isExpanded: expandedItem == group.id,
                    onToggle: toggleGroupExpansion
                )
                if expandedItem == group.id {
                    ForEach(group.indentedAgents, id: \.agent.id) { entry in
                        nestedRow(agent: entry.agent, indent: entry.indent)
                    }
                }
            }
        }
    }

    private func toggleGroupExpansion() {
        userInteracted = true
        withAnimation(.snappy(duration: Theme.Animation.collapsibleDuration)) {
            expandedItem = expandedItem == group.id ? nil : group.id
        }
    }

    private func nestedRow(agent: Agent, indent: Int) -> some View {
        // Show only the agent's own name in nested rows — the workspace is
        // already in the header. Copy-to-clipboard and the hover tooltip
        // still use the full FQDN so the user has a usable shell hostname.
        MenuItemView(
            item: .agent(agent),
            baseAccessURL: baseAccessURL,
            expandedItem: $nestedExpandedAgent,
            userInteracted: $userInteracted,
            displayLabel: agent.name
        )
        .padding(.leading, CGFloat(indent) * Theme.Size.trayPadding)
    }
}

struct WorkspaceHeaderRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL

    let group: WorkspaceGroup
    let baseAccessURL: URL
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var nameIsSelected: Bool = false

    private var plainName: String {
        "\(group.workspace.name).\(state.hostnameSuffix)"
    }

    private var styledName: AttributedString {
        // Display only the workspace name; the row already represents the
        // workspace in the menu hierarchy. Copy/tooltip retain the full FQDN.
        var name = AttributedString(group.workspace.name)
        name.foregroundColor = .primary
        return name
    }

    private var wsURL: URL {
        // TODO: CoderVPN currently only supports owned workspaces.
        baseAccessURL.appending(path: "@me").appending(path: group.workspace.name)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainName, forType: .string)
    }

    var body: some View {
        HStack(spacing: 3) {
            Button(action: onToggle) {
                HStack(spacing: Theme.Size.trayPadding) {
                    AnimatedChevron(isExpanded: isExpanded, color: .secondary)
                    Text(styledName).lineLimit(1).truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, Theme.Size.trayPadding)
                .frame(minHeight: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(nameIsSelected ? .white : .primary)
                .background(nameIsSelected ? Color.accentColor.opacity(0.8) : .clear)
                .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
                .onHover { hovering in nameIsSelected = hovering }
                .help(plainName)
            }.buttonStyle(.plain).padding(.trailing, 3)
            StatusDot(color: group.status.color)
                .padding(.trailing, 3)
                .padding(.top, 1)
                .help(group.status.description)
            MenuItemIconButton(systemName: "doc.on.doc", action: copyToClipboard)
                .font(.system(size: 9))
                .symbolVariant(.fill)
                .help("Copy hostname")
            MenuItemIconButton(systemName: "globe", action: { openURL(wsURL) })
                .contentShape(Rectangle())
                .font(.system(size: 12))
                .padding(.trailing, Theme.Size.trayMargin)
                .help("Open in browser")
        }
    }
}
