import CoderSDK
import SwiftUI

/// How "thinking" (reasoning) blocks are shown by default. The renderer reads this; it is
/// kept in sync with the server's `thinking_display_mode` preference by the General section.
enum ThinkingDisplay: String, CaseIterable, Identifiable {
    case auto
    case alwaysExpanded
    case alwaysCollapsed
    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .alwaysExpanded: "Always expanded"
        case .alwaysCollapsed: "Always collapsed"
        }
    }

    var startsExpanded: Bool {
        self == .alwaysExpanded
    }
}

/// The sections of the in-window Agents settings, navigated via the left sidebar — mirroring
/// the Coder web settings.
enum AgentsSettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case agents = "Agents"
    case skills = "Personal skills"
    case compaction = "Compaction"
    case secrets = "Secrets (API keys)" // the web's exact nav label

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .general: "person"
        case .agents: "cpu"
        case .skills: "wand.and.stars"
        case .compaction: "arrow.down.right.and.arrow.up.left"
        case .secrets: "key"
        }
    }
}

/// In-window Agents settings, separate from the app-level Coder Desktop settings. A left
/// sidebar navigates between sections. Values are entered here and stored server-side
/// (API keys are write-only — never read back or stored on this Mac).
struct AgentsSettingsView<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @Environment(\.dismiss) private var dismiss

    @State private var selection: AgentsSettingsSection? = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agents Settings").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Size.trayInset)
            Divider()
            NavigationSplitView {
                List(AgentsSettingsSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.systemImage).tag(section)
                }
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            } detail: {
                detail
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(width: 760, height: 600)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            GeneralSettingsSection<Agents>()
        case .secrets:
            SecretsSettingsSection<Agents>()
        case .agents:
            AgentsModelSettingsSection<Agents>()
        case .skills:
            SkillsSettingsSection<Agents>()
        case .compaction:
            CompactionSettingsSection<Agents>()
        }
    }
}
