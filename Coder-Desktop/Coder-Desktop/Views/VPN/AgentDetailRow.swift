import CoderSDK
import SwiftUI

/// Renders a single agent inside an expanded WorkspaceGroupView: status dot,
/// agent name + latency, optional ports menu / parent-apps toggle / copy
/// button, and the agent's apps inline below.
///
/// Sub-agent rows don't carry any extra glyph here — the surrounding
/// `GroupBox` (wired up in WorkspaceGroupView) handles the "Container"
/// labelling. `appsToggle`, when set, exposes the show/hide control for
/// parent apps (mirrors the dashboard's "Show parent apps" affordance).
struct AgentDetailRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL

    let agent: Agent
    let apps: [WorkspaceApp]
    var ports: [WorkspaceAgentListeningPort] = []
    var appsToggle: AppsToggle?

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
                if !ports.isEmpty {
                    portsMenu
                }
                if let appsToggle {
                    Button(action: appsToggle.action) {
                        Image(systemName: appsToggle.isShown ? "square.grid.2x2.fill" : "square.grid.2x2")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 11))
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(appsToggle.isShown ? "Hide parent apps" : "Show parent apps")
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
            HStack(spacing: 1) {
                Image(systemName: "dot.radiowaves.right")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 9))
                    .imageScale(.small)
                Text("\(ports.count)")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(3)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
