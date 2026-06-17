import CoderSDK
import SwiftUI

/// A proposed plan (`propose_plan` tool). Fetches the plan markdown by its file id, renders
/// it, and — once proposed — offers Copy and Implement. Implement proceeds the chat (sends
/// "Implement the plan." and clears plan mode), mirroring the web.
struct PlanView<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let chatID: UUID
    let step: ToolStep

    @State private var markdown: String?
    @State private var loading = false
    @State private var loadFailed = false
    @State private var implementing = false

    private var part: ChatMessagePart? { step.result ?? step.call }
    private var isProposed: Bool { step.result != nil }

    private var title: String {
        guard isProposed else { return "Proposing plan…" }
        if let base = step.call?.fileBasename ?? part?.fileBasename { return "Proposed plan · \(base)" }
        return "Proposed plan"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let markdown, !markdown.isEmpty {
                MarkdownText(text: markdown)
            } else if loading {
                ProgressView().controlSize(.small)
            } else if loadFailed {
                HStack(spacing: 6) {
                    Label("Couldn't load plan", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { loadFailed = false; Task { await loadPlan() } }
                        .font(.caption).buttonStyle(.borderless)
                }
            }

            if isProposed, let markdown, !markdown.isEmpty {
                HStack(spacing: 8) {
                    Button { copyToPasteboard(markdown) } label: {
                        Label("Copy plan", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: implement) {
                        if implementing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Implement", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(implementing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: part?.planFileID) { await loadPlan() }
    }

    private func loadPlan() async {
        guard markdown == nil, let fileID = part?.planFileID else { return }
        loading = true
        markdown = await agents.planText(fileID: fileID)
        loading = false
        if markdown == nil { loadFailed = true }
    }

    private func implement() {
        implementing = true
        Task {
            _ = await agents.implementPlan(chatID)
            implementing = false
        }
    }
}
