import CoderSDK
import SwiftUI

/// The chat-sharing popover (web parity): search org users/groups to grant read access, see
/// who it's shared with, and revoke. Sharing is ACL-based — there's no public link.
struct ChatSharePopover<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let session: Chat

    @State private var acl: ChatACL?
    @State private var members: [OrgMember] = []
    @State private var groups: [OrgGroup] = []
    @State private var query = ""
    @State private var loading = true

    private enum Candidate: Identifiable {
        case user(OrgMember)
        case group(OrgGroup)

        var id: UUID {
            switch self {
            case let .user(member): member.id
            case let .group(group): group.id
            }
        }
        var title: String {
            switch self {
            case let .user(m): m.name?.isEmpty == false ? m.name! : m.username
            case let .group(g): g.display_name?.isEmpty == false ? g.display_name! : (g.name ?? "Group")
            }
        }

        var subtitle: String { if case let .user(m) = self { "@\(m.username)" } else { "Group" } }
        var icon: String { if case .group = self { "person.3" } else { "person.crop.circle" } }
    }

    private var results: [Candidate] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }
        let sharedUsers = Set(acl?.users.map(\.id) ?? [])
        let sharedGroups = Set(acl?.groups.map(\.id) ?? [])
        let users = members
            .filter { !sharedUsers.contains($0.id) }
            .filter { $0.username.lowercased().contains(trimmed) || ($0.name ?? "").lowercased().contains(trimmed) }
            .map(Candidate.user)
        let grps = groups
            .filter { !sharedGroups.contains($0.id) }
            .filter { ($0.display_name ?? $0.name ?? "").lowercased().contains(trimmed) }
            .map(Candidate.group)
        return Array((users + grps).prefix(8))
    }

    private var isEmpty: Bool { (acl?.users.isEmpty ?? true) && (acl?.groups.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chat sharing").font(.headline)

            TextField("Search people or groups…", text: $query)
                .textFieldStyle(.roundedBorder)

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { candidate in
                        Button { add(candidate) } label: {
                            principalRow(candidate.title, candidate.subtitle, icon: candidate.icon)
                                .padding(.horizontal, 6).padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
            }

            Divider()
            Text("Shared with").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            if loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if isEmpty {
                Text("Not shared with anyone yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(acl?.users ?? []) { user in
                            sharedRow(
                                user.name?.isEmpty == false ? user.name! : user.username,
                                "@\(user.username)", icon: "person.crop.circle"
                            ) { Task { await agents.unshareUser(session.id, userID: user.id); await load() } }
                        }
                        ForEach(acl?.groups ?? []) { group in
                            sharedRow(groupTitle(group), "Group", icon: "person.3", onRemove: nil)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(14)
        .frame(width: 340)
        .task(id: session.id) { await load() }
    }

    @ViewBuilder
    private func principalRow(_ title: String, _ subtitle: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func sharedRow(_ title: String, _ subtitle: String, icon: String, onRemove: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            principalRow(title, subtitle, icon: icon)
            Text("Read").font(.caption2).foregroundStyle(.secondary)
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
    }

    private func groupTitle(_ group: ChatACLGroup) -> String {
        group.display_name?.isEmpty == false ? group.display_name! : (group.name ?? "Group")
    }

    private func load() async {
        loading = true
        acl = await agents.chatACL(session.id)
        if members.isEmpty, groups.isEmpty, let orgID = session.organization_id {
            (members, groups) = await agents.shareCandidates(orgID: orgID)
        }
        loading = false
    }

    private func add(_ candidate: Candidate) {
        Task {
            switch candidate {
            case let .user(member): await agents.shareWithUser(session.id, userID: member.user_id)
            case let .group(group): await agents.shareWithGroup(session.id, groupID: group.id)
            }
            query = ""
            await load()
        }
    }
}
