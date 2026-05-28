import CoderSDK
import SwiftUI

/// Renders a single agent inside an expanded WorkspaceGroupView: status dot,
/// agent name + latency, optional ports menu / parent-apps toggle / copy
/// button, and the agent's apps inline below.
///
/// `leadingIcon` is rendered ahead of the status dot and is used to mark
/// sub-agent rows with a cube glyph so they're recognizable as containers
/// without a dedicated header. `appsToggle`, when set, exposes the show/hide
/// control for parent apps (mirrors the dashboard's "Show parent apps"
/// affordance).
struct AgentDetailRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL

    let agent: Agent
    let apps: [WorkspaceApp]
    var ports: [WorkspaceAgentListeningPort] = []
    var appsToggle: AppsToggle?
    var leadingIcon: String?
    var leadingIconHelp: String?

    @State private var nameIsSelected: Bool = false
    /// Bumped on each copy so SwiftUI can drive the bounce symbol effect.
    @State private var copyTick: Int = 0

    struct AppsToggle {
        let isShown: Bool
        let action: () -> Void
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                HStack(spacing: Theme.Size.trayPadding) {
                    if let leadingIcon {
                        Image(systemName: leadingIcon)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .help(leadingIconHelp ?? "")
                    }
                    StatusDot(color: agent.status.color)
                        .help(agent.statusString)
                    Text(agent.name).lineLimit(1).truncationMode(.tail)
                    if let latency = agent.lastPing?.latency {
                        Text(formatLatency(latency))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, Theme.Size.trayPadding)
                .frame(minHeight: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(nameIsSelected ? .white : .primary)
                .background(nameIsSelected ? Color.accentColor.opacity(0.8) : .clear)
                .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
                .onHover { hovering in nameIsSelected = hovering }
                .padding(.trailing, 3)
                .draggable(agent.primaryHost)
                if !ports.isEmpty {
                    portsMenu
                }
                if let appsToggle {
                    Button(action: appsToggle.action) {
                        Image(systemName: appsToggle.isShown ? "square.grid.2x2.fill" : "square.grid.2x2")
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: 11))
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .help(appsToggle.isShown ? "Hide apps" : "Show apps")
                }
                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc.fill")
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: copyTick)
                        .font(.system(size: 9))
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .padding(.trailing, Theme.Size.trayMargin)
                .help("Copy hostname")
            }
            if !apps.isEmpty {
                MenuItemCollapsibleView(apps: apps)
            }
        }
    }

    private var portsMenu: some View {
        Menu {
            ForEach(ports) { port in
                Button(label(for: port)) {
                    if let url = URL(string: "http://\(agent.primaryHost):\(port.port)") {
                        openURL(url)
                    }
                }
            }
        } label: {
            Label("Listening ports", systemImage: "dot.radiowaves.right")
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(3)
        }
        .badge(ports.count)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .help("Listening ports")
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(agent.primaryHost, forType: .string)
        copyTick &+= 1
    }

    /// Compact "18ms" formatting for inline display. The dot's tooltip still
    /// carries the full status string with P2P/DERP detail.
    private func formatLatency(_ seconds: TimeInterval) -> String {
        let ms = Int((seconds * 1000).rounded())
        return "\(ms)ms"
    }

    private func label(for port: WorkspaceAgentListeningPort) -> String {
        let processName = port.process_name.isEmpty ? nil : port.process_name
        if let processName {
            return "\(port.port) - \(processName)"
        }
        return "\(port.port)"
    }
}
