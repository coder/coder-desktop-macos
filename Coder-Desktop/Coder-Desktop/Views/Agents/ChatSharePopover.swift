import CoderSDK
import SwiftUI

/// The chat-sharing popover (web parity): grant teammates read access to this chat by
/// username, see who it's shared with, and revoke. Sharing is ACL-based — there's no public
/// link. Group entries are shown read-only (granted by an admin elsewhere).
struct ChatSharePopover<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let chatID: UUID

    @State private var acl: ChatACL?
    @State private var loading = true
    @State private var username = ""
    @State private var adding = false
    @State private var error: String?

    private var isEmpty: Bool { (acl?.users.isEmpty ?? true) && (acl?.groups.isEmpty ?? true) }

    private func groupTitle(_ group: ChatACLGroup) -> String {
        group.display_name?.isEmpty == false ? group.display_name! : (group.name ?? "Group")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chat sharing").font(.headline)

            HStack(spacing: 6) {
                TextField("Share with a username…", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(adding || username.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Divider()

            if loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if isEmpty {
                Text("Not shared with anyone yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(acl?.users ?? []) { user in
                            memberRow(
                                title: user.name?.isEmpty == false ? user.name! : user.username,
                                subtitle: "@\(user.username)", icon: "person.crop.circle"
                            ) { Task { await agents.unshareUser(chatID, userID: user.id); await load() } }
                        }
                        ForEach(acl?.groups ?? []) { group in
                            memberRow(
                                title: groupTitle(group), subtitle: "Group",
                                icon: "person.3", removable: false, onRemove: {}
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(14)
        .frame(width: 340)
        .task(id: chatID) { await load() }
    }

    @ViewBuilder
    private func memberRow(
        title: String, subtitle: String, icon: String, removable: Bool = true, onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Read").font(.caption2).foregroundStyle(.secondary)
            if removable {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
    }

    private func load() async {
        loading = true
        acl = await agents.chatACL(chatID)
        loading = false
    }

    private func add() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        adding = true
        error = nil
        Task {
            error = await agents.shareChat(chatID, username: name)
            adding = false
            if error == nil { username = ""; await load() }
        }
    }
}
