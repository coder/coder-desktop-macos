import CoderSDK
import SwiftUI

/// Recency buckets for the sidebar, matching the web UI's grouping.
struct SessionGroup {
    let title: String
    let sessions: [Chat]

    static func grouped(_ sessions: [Chat]) -> [SessionGroup] {
        // Pinned chats float to the top in their own section (matches the web UI).
        let pinned = sessions.filter(\.isPinned).sorted { ($0.pin_order ?? 0) > ($1.pin_order ?? 0) }
        let rest = sessions.filter { !$0.isPinned }

        let calendar = Calendar.current
        let now = Date()
        var buckets: [(String, [Chat])] = [("Today", []), ("Yesterday", []), ("This Week", []), ("Older", [])]
        for session in rest {
            let days = calendar.dateComponents([.day], from: session.updated_at, to: now).day ?? 0
            if calendar.isDateInToday(session.updated_at) {
                buckets[0].1.append(session)
            } else if calendar.isDateInYesterday(session.updated_at) {
                buckets[1].1.append(session)
            } else if days < 7 {
                buckets[2].1.append(session)
            } else {
                buckets[3].1.append(session)
            }
        }
        var groups: [SessionGroup] = []
        if !pinned.isEmpty { groups.append(SessionGroup(title: "Pinned", sessions: pinned)) }
        groups += buckets.filter { !$0.1.isEmpty }.map { SessionGroup(title: $0.0, sessions: $0.1) }
        return groups
    }
}

struct SessionRow: View {
    let session: Chat
    let workspaceName: String?
    /// Sub-agent row: indented by the caller; pin/rename/workspace actions don't apply.
    var isChild = false
    var childCount = 0
    var isExpanded = false
    var onToggleExpand: () -> Void = {}
    var onOpen: () -> Void = {}
    var onRename: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onArchive: () -> Void = {}
    var onDeleteWorkspace: () -> Void = {}

    @State private var hovering = false

    private var isPR: Bool { session.diff_status?.isPullRequest == true }

    var body: some View {
        HStack(spacing: 8) {
            if childCount > 0 {
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(minWidth: 16, minHeight: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse sub-agents" : "Expand \(childCount) sub-agents")
            }
            Image(systemName: isPR ? "arrow.triangle.branch" : session.status.systemImage)
                .font(.caption)
                .foregroundStyle(isPR ? .secondary : session.status.color)
                .accessibilityLabel(session.status.accessibilityLabel)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if session.isPinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }
                    Text(session.title?.isEmpty == false ? session.title! : "Untitled session")
                        .lineLimit(1)
                    if session.has_unread == true {
                        Circle().fill(.blue).frame(width: 6, height: 6)
                            .accessibilityLabel("Unread")
                    }
                    Spacer()
                    // Swapped via opacity, not removal, so the kebab stays reachable by
                    // keyboard/VoiceOver; hit-testing gated so the invisible menu can't
                    // swallow row-selection clicks.
                    ZStack(alignment: .trailing) {
                        TimelineView(.everyMinute) { _ in
                            Text(Self.relativeShort(session.updated_at))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .opacity(hovering ? 0 : 1)
                        .accessibilityHidden(hovering)
                        Menu { rowMenu } label: {
                            Image(systemName: "ellipsis").foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .opacity(hovering ? 1 : 0)
                        .allowsHitTesting(hovering)
                        .accessibilityLabel("Chat actions")
                    }
                }
                subtitle
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering = $0 }
        .contextMenu { rowMenu }
    }

    /// Diff summary (+adds −dels) when a PR/branch is attached, then workspace/status text,
    /// with the shared marker at the trailing edge.
    private var subtitle: some View {
        HStack(spacing: 4) {
            if let diff = session.diff_status {
                if let adds = diff.additions, adds > 0 { Text("+\(adds)").foregroundStyle(.green) }
                if let dels = diff.deletions, dels > 0 { Text("−\(dels)").foregroundStyle(.red) }
            }
            if let workspaceName {
                Text(workspaceName)
                Text("·")
            }
            // An errored chat shows WHY (web parity) — bare "Error" is undebuggable.
            if session.status == .error, let message = session.last_error?.message, !message.isEmpty {
                Text(message).foregroundStyle(.red)
            } else if let summary = session.last_turn_summary, !summary.isEmpty, !session.status.isActive {
                // The server's one-line turn summary (the web sidebar's subtitle).
                Text(summary)
            } else {
                Text(session.status.label)
            }
            if session.shared == true {
                Spacer(minLength: 4)
                // .help() is only a tooltip on macOS — VoiceOver needs the explicit label.
                Image(systemName: "person.2.fill").help("Shared").accessibilityLabel("Shared")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var rowMenu: some View {
        Button(action: onOpen) { Label("Open in browser", systemImage: "safari") }
        if !isChild {
            Button(action: onRename) { Label("Rename", systemImage: "pencil") }
            Button(action: onTogglePin) {
                Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
            }
        }
        Divider()
        Button(role: .destructive) { onArchive() } label: { Label("Archive chat", systemImage: "archivebox") }
            .disabled(!session.status.canArchive)
        if !isChild, session.workspace_id != nil {
            Button(role: .destructive) { onDeleteWorkspace() } label: {
                Label("Archive chat & delete workspace", systemImage: "trash")
            }
            .disabled(!session.status.canArchive)
        }
    }

    /// Compact relative time like the web UI ("5m", "3h", "2d", "1w", "3mo").
    nonisolated static func relativeShort(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        case ..<604_800: return "\(seconds / 86400)d"
        case ..<2_592_000: return "\(seconds / 604_800)w"
        default: return "\(seconds / 2_592_000)mo"
        }
    }
}
