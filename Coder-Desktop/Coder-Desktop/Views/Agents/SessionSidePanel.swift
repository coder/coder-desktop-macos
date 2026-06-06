import CoderSDK
import SwiftUI

enum SidePanelTab: String, CaseIterable, Identifiable {
    case git = "Git"
    case terminal = "Terminal"
    case desktop = "Desktop"
    var id: String {
        rawValue
    }
}

struct SessionSidePanel<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @EnvironmentObject var state: AppState
    let session: Chat
    @Binding var tab: SidePanelTab
    /// Sends selected diff lines (+ a note) into the chat composer as context.
    var onAddToChat: ((String) -> Void)?

    /// The workspace's Coder Connect hostname (e.g. `my-workspace.coder`) for SSH, if the
    /// session is backed by a known workspace.
    private var terminalHost: String? {
        guard let id = session.workspace_id,
              let name = agents.workspaces.first(where: { $0.id == id })?.name
        else { return nil }
        return "\(name).\(state.hostnameSuffix)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SidePanelTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch tab {
            case .git:
                DiffPanel<Agents>(session: session, onAddToChat: onAddToChat)
            case .terminal:
                if let host = terminalHost {
                    TerminalPanel(host: host)
                } else {
                    streamPlaceholder(
                        title: "Terminal",
                        systemImage: "terminal",
                        detail: "Available when the session is attached to a workspace and Coder Connect is on."
                    )
                }
            case .desktop:
                streamPlaceholder(
                    title: "Desktop",
                    systemImage: "display",
                    detail: "The workspace's remote desktop will stream here."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Terminal/Desktop are remote-stream viewers (PTY / VNC) — pending a native emulator.
    private func streamPlaceholder(title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let url = workspaceURL {
                Link("Open in workspace", destination: url).font(.caption)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workspaceURL: URL? {
        // Best-effort deep link to the workspace dashboard while native streaming lands.
        guard let id = session.workspace_id else { return nil }
        return URL(string: "https://dev.coder.com/@me/\(id.uuidString)")
    }
}

struct DiffPanel<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let session: Chat
    var onAddToChat: ((String) -> Void)?

    var body: some View {
        let diff = agents.diff(for: session.id)
        let status = session.diff_status
        VStack(alignment: .leading, spacing: 0) {
            header(diff: diff, status: status)
            Divider()
            if let status, status.hasContent {
                summary(status)
                Divider()
            }
            body(diff: diff, status: status)
        }
        .task(id: session.id) { await agents.loadDiff(session.id) }
    }

    private func header(diff: ChatDiffContents?, status: ChatDiffStatus?) -> some View {
        HStack(spacing: 6) {
            let branch = status?.label ?? (diff?.branch?.isEmpty == false ? diff?.branch : nil)
            if let branch {
                Label(branch, systemImage: "arrow.triangle.branch").font(.caption).lineLimit(1)
            } else {
                Text("Diff").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await agents.loadDiff(session.id) } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh diff")
        }
        .padding(8)
    }

    /// Counts + PR link, like the web's diff header. Only links to a real pull request —
    /// never a `/tree/<branch>` page, which 404s once the ephemeral branch is gone.
    private func summary(_ status: ChatDiffStatus) -> some View {
        HStack(spacing: 10) {
            if let additions = status.additions { Text("+\(additions)").foregroundStyle(.green) }
            if let deletions = status.deletions { Text("−\(deletions)").foregroundStyle(.red) }
            if let files = status.changed_files, files > 0 {
                Text("· \(files) file\(files == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
            Spacer()
            if let url = status.pullRequestURL {
                Link(destination: url) {
                    Label("View PR", systemImage: "arrow.up.right.square")
                }
                .font(.caption)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func body(diff: ChatDiffContents?, status: ChatDiffStatus?) -> some View {
        if let text = diff?.diff, !text.isEmpty {
            // The resolved diff — server-side this is the local working-tree (uncommitted)
            // diff while dirty, or the PR/target-branch diff once pushed.
            DiffView(text: text, onAddToChat: onAddToChat)
        } else if let status, status.isPullRequest, let url = status.pullRequestURL {
            VStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").font(.title2).foregroundStyle(.secondary)
                Text("This chat has an open pull request.").font(.caption).foregroundStyle(.secondary)
                Link("View pull request", destination: url).font(.caption)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(.secondary)
                Text("No changes yet").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
