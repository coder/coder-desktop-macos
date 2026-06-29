import CoderSDK
import SwiftUI

struct DiffPanel<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let session: Chat
    var onAddToChat: (([ChatInputPart], String) -> Void)?

    /// Selected local repo root, or nil for the remote/branch diff. Auto-falls-back to the
    /// first dirty local repo when the remote source has nothing (web behavior).
    @State private var selectedRepo: String?

    var body: some View {
        let diff = agents.diff(for: session.id)
        let status = session.diff_status
        let repos = agents.localRepos(for: session.id)
        let activeRepo = activeLocalRepo(repos: repos, diff: diff, status: status)
        VStack(alignment: .leading, spacing: 0) {
            header(diff: diff, status: status, repos: repos, activeRepo: activeRepo)
            Divider()
            if activeRepo == nil, let status, status.hasContent {
                summary(status)
                Divider()
            }
            if let activeRepo {
                // Live uncommitted changes streamed from the workspace agent.
                if let text = activeRepo.unified_diff, !text.isEmpty {
                    DiffView(text: text, onAddToChat: onAddToChat)
                } else {
                    placeholder(icon: "checkmark.circle", text: "No file changes.")
                }
            } else {
                body(diff: diff, status: status)
            }
        }
        .task(id: session.id) {
            agents.startGitWatch(session.id)
            await agents.loadDiff(session.id)
        }
        .onDisappear { agents.stopGitWatch(session.id) }
    }

    /// The local repo to show: the explicit pick, else the first dirty repo when the remote
    /// source is empty (mirrors the web's default-to-local gate).
    private func activeLocalRepo(
        repos: [WorkspaceAgentRepoChanges], diff: ChatDiffContents?, status: ChatDiffStatus?
    ) -> WorkspaceAgentRepoChanges? {
        if let selectedRepo {
            return repos.first { $0.repo_root == selectedRepo }
        }
        let remoteHasContent = diff?.diff?.isEmpty == false || status?.hasContent == true
        return remoteHasContent ? nil : repos.first { $0.unified_diff?.isEmpty == false }
    }

    private func header(
        diff: ChatDiffContents?, status: ChatDiffStatus?,
        repos: [WorkspaceAgentRepoChanges], activeRepo: WorkspaceAgentRepoChanges?
    ) -> some View {
        HStack(spacing: 6) {
            let branch = activeRepo.map { $0.branch?.isEmpty == false ? $0.branch! : repoName($0) }
                ?? status?.label ?? (diff?.branch?.isEmpty == false ? diff?.branch : nil)
            if repos.isEmpty {
                if let branch {
                    Label(branch, systemImage: "arrow.triangle.branch").font(.caption).lineLimit(1)
                } else {
                    Text("Diff").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                // Source picker, like the web's Remote/local tabs.
                Menu {
                    Button { selectedRepo = "" } label: {
                        sourceLabel("Remote branch", checked: activeRepo == nil)
                    }
                    ForEach(repos) { repo in
                        Button { selectedRepo = repo.repo_root } label: {
                            sourceLabel(repoName(repo), checked: activeRepo?.id == repo.id)
                        }
                    }
                } label: {
                    Label(branch ?? "Diff", systemImage: "arrow.triangle.branch").font(.caption).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Diff source")
            }
            Spacer()
            Button { Task { await agents.loadDiff(session.id) } } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(minWidth: 24, minHeight: 24) // WCAG 2.5.8 minimum target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Refresh diff")
            .accessibilityLabel("Refresh diff")
        }
        .padding(8)
    }

    private func repoName(_ repo: WorkspaceAgentRepoChanges) -> String {
        (repo.repo_root as NSString).lastPathComponent
    }

    @ViewBuilder
    private func sourceLabel(_ title: String, checked: Bool) -> some View {
        if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
