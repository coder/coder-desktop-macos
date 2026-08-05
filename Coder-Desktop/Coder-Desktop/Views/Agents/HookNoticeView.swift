import SwiftUI

/// A lifecycle hook's user-facing notice — a deployment policy explaining that a hook changed
/// or blocked something about the turn. Labelled so it doesn't read as the agent talking,
/// mirroring the web's LifecycleHookNotice row.
struct HookNoticeView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lifecycle hook")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                // Markdown so a hook can link out to its policy, like the web's notice.
                MarkdownText(text: text)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lifecycle hook notice: \(text)")
    }
}
