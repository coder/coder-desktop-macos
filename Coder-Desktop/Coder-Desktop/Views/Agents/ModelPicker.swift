import CoderSDK
import SwiftUI

/// "xhigh" renders as "Xhigh", matching the web's `formatReasoningEffort`.
func effortLabel(_ value: String) -> String {
    value.isEmpty ? value : value.prefix(1).uppercased() + value.dropFirst()
}

/// Per-model reasoning-effort memory, so picking a model restores the effort last used with it
/// (web keeps the same per-model map in localStorage under the same key shape).
enum EffortMemory {
    private static func key(_ modelConfigID: UUID) -> String {
        "agents.reasoning-effort.\(modelConfigID.uuidString)"
    }

    static func stored(for modelConfigID: UUID) -> String? {
        UserDefaults.standard.string(forKey: key(modelConfigID))
    }

    static func save(_ effort: String, for modelConfigID: UUID) {
        UserDefaults.standard.set(effort, forKey: key(modelConfigID))
    }
}

/// A model picker showing the selected model's name. Opens a popover listing the models with a
/// checkmark on the current one, and — for models that expose reasoning effort — an effort
/// slider pinned below the list, mirroring the web's ModelSelector.
///
/// A popover rather than a native `Menu` because an `NSMenu` can't host a working slider. The
/// list stays keyboard-reachable (buttons via Tab, the slider via arrow keys once focused).
struct ModelPicker<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @Binding var selectedID: UUID?
    /// The chat's reasoning effort. Nil when the selected model has no reasoning control.
    @Binding var effort: String?

    @State private var show = false

    private var selected: ChatModelConfig? {
        agents.modelConfigs.first { $0.id == selectedID }
    }

    private var label: String { selected?.label ?? "Model" }

    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 4) {
                Text(label).lineLimit(1).foregroundStyle(.primary)
                if let effort, selected?.selectableEfforts.isEmpty == false {
                    Text(effortLabel(effort))
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Model")
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $show, arrowEdge: .top) { picker }
    }

    private var accessibilityLabel: String {
        guard let effort, selected?.selectableEfforts.isEmpty == false else { return "Model: \(label)" }
        return "Model: \(label), effort \(effortLabel(effort))"
    }

    private var picker: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(agents.modelConfigs) { config in
                        Button {
                            selectedID = config.id
                            show = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .opacity(config.id == selectedID ? 1 : 0)
                                Text(config.label).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(config.id == selectedID ? "\(config.label), selected" : config.label)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 240)
            if let selected, !selected.selectableEfforts.isEmpty {
                Divider()
                EffortSlider(efforts: selected.selectableEfforts, effort: $effort, modelConfigID: selected.id)
            }
        }
        .frame(width: 260)
    }
}

/// The effort row pinned below the model list: a slider stepping through the model's selectable
/// efforts (ordered low to high), with the current value shown as a chip.
private struct EffortSlider: View {
    let efforts: [String]
    @Binding var effort: String?
    /// Persisting happens here rather than on every `effort` change, so a value the user never
    /// touched isn't pinned — otherwise raising a model's default server-side would never reach
    /// anyone who had merely opened the picker once.
    let modelConfigID: UUID

    @State private var showInfo = false

    /// The slider works in indices; an unknown/absent effort shows the lowest.
    private var index: Double {
        Double(effort.flatMap { efforts.firstIndex(of: $0) } ?? 0)
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text("Effort").font(.caption).foregroundStyle(.secondary)
                Button { showInfo.toggle() } label: {
                    Image(systemName: "info.circle").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Controls how much reasoning the model performs before responding. "
                    + "Higher effort can improve quality but is slower and costs more.")
                .accessibilityLabel("About reasoning effort")
                .popover(isPresented: $showInfo, arrowEdge: .top) {
                    Text("Controls how much reasoning the model performs before responding. "
                        + "Higher effort can improve quality but is slower and costs more.")
                        .font(.caption)
                        .padding(10)
                        .frame(width: 220)
                }
            }
            .fixedSize()
            // A single-model range would make Slider's bounds invalid, so show just the chip.
            if efforts.count > 1 {
                Slider(
                    value: Binding(
                        get: { index },
                        set: { newValue in
                            let clamped = min(max(Int(newValue.rounded()), 0), efforts.count - 1)
                            guard efforts[clamped] != effort else { return }
                            effort = efforts[clamped]
                            EffortMemory.save(efforts[clamped], for: modelConfigID)
                        }
                    ),
                    in: 0 ... Double(efforts.count - 1),
                    step: 1
                )
                .accessibilityLabel("Reasoning effort")
                .accessibilityValue(effortLabel(effort ?? ""))
            }
            Text(effortLabel(effort ?? efforts[0]))
                .font(.caption)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
