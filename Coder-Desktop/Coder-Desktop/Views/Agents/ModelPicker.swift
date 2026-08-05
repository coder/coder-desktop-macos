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

/// One provider's models in the picker. Keyed by the provider's display label, so models whose
/// provider metadata is missing still group together under "Other".
private struct ProviderGroup: Identifiable {
    let label: String
    let icon: URL?
    let models: [ChatModelConfig]
    var id: String { label }
}

/// The composer's model picker: a searchable, provider-grouped list in a popover, with an
/// effort slider pinned below it for models that expose reasoning effort. Mirrors the web's
/// ModelSelector.
///
/// A popover rather than a native `Menu` because an `NSMenu` can host neither a search field
/// nor a working slider. Keyboard handling is therefore hand-rolled: arrows move the highlight,
/// return picks, escape closes, and the highlight is kept scrolled into view.
struct ModelPicker<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @EnvironmentObject var state: AppState
    @Binding var selectedID: UUID?
    /// The chat's reasoning effort. Nil when the selected model has no reasoning control.
    @Binding var effort: String?

    @State private var show = false
    @State private var search = ""
    /// Keyboard highlight, distinct from the chosen model.
    @State private var highlighted: UUID?
    @State private var hoveredID: UUID?
    @FocusState private var searchFocused: Bool

    private var selected: ChatModelConfig? {
        agents.modelConfigs.first { $0.id == selectedID }
    }

    private var label: String { selected?.label ?? "Model" }

    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 4) {
                Text(label).lineLimit(1).foregroundStyle(.primary)
                if let effort, let efforts = selected?.selectableEfforts, !efforts.isEmpty {
                    // Sized to the longest label so changing effort doesn't shift the controls
                    // either side of the picker.
                    ZStack {
                        ForEach(efforts, id: \.self) { Text(effortLabel($0)).hidden() }
                        Text(effortLabel(effort))
                    }
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
        .onHoverWithPointingHand { _ in }
        .help("Model")
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $show, arrowEdge: .top) { picker }
        .task(id: show) {
            guard show else { return }
            await agents.loadAIProviders()
            // Reuses the URL-keyed icon cache the workspace-app icons use.
            agents.loadWorkspaceAppIcons(groups.compactMap(\.icon))
            // Open on the current model so arrow keys start from something meaningful.
            highlighted = selectedID
            search = ""
            searchFocused = true
        }
    }

    private var accessibilityLabel: String {
        guard let effort, selected?.selectableEfforts.isEmpty == false else { return "Model: \(label)" }
        return "Model: \(label), effort \(effortLabel(effort))"
    }

    /// Models grouped by provider, in provider-label order, filtered by the search query.
    /// Models whose provider is unknown group under "Other" rather than vanishing.
    private var groups: [ProviderGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var byProvider: [String: [ChatModelConfig]] = [:]
        for config in agents.modelConfigs {
            let provider = config.ai_provider_id.flatMap { agents.aiProviders[$0] }
            let providerLabel = provider?.label ?? config.provider ?? "Other"
            if !query.isEmpty {
                let haystack = [providerLabel, provider?.type ?? "", config.label, config.model]
                    .joined(separator: " ").lowercased()
                guard haystack.contains(query) else { continue }
            }
            byProvider[providerLabel, default: []].append(config)
        }
        return byProvider
            .map { providerLabel, models in
                let provider = models.first?.ai_provider_id.flatMap { agents.aiProviders[$0] }
                return ProviderGroup(
                    label: providerLabel,
                    icon: providerIconURL(provider),
                    models: models.sorted { $0.label.lowercased() < $1.label.lowercased() }
                )
            }
            .sorted { $0.label.lowercased() < $1.label.lowercased() }
    }

    /// Flat order of the visible models — what the arrow keys walk.
    private var visibleModelIDs: [UUID] { groups.flatMap { $0.models.map(\.id) } }

    private func providerIconURL(_ provider: AIProvider?) -> URL? {
        guard let icon = provider?.icon, !icon.isEmpty, let base = state.baseAccessURL else { return nil }
        return resolvedWorkspaceIconURL(URL(string: icon), base: base)
    }

    private var picker: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if visibleModelIDs.isEmpty {
                            Text("No models match that search.")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                        ForEach(groups, id: \.id) { group in
                            providerHeader(group.label, icon: group.icon)
                            ForEach(group.models) { config in
                                modelRow(config)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 240)
                .onChange(of: highlighted) { _, new in
                    guard let new else { return }
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(new, anchor: .center) }
                }
            }
            if let selected, !selected.selectableEfforts.isEmpty {
                Divider()
                EffortSlider(efforts: selected.selectableEfforts, effort: $effort, modelConfigID: selected.id)
            }
        }
        .frame(width: 280)
        // Attached to the container so the search field's own key handling comes first.
        .onKeyPress(.upArrow) { moveHighlight(-1) }
        .onKeyPress(.downArrow) { moveHighlight(1) }
        .onKeyPress(.return) { chooseHighlighted() }
        .onKeyPress(.escape) { show = false; return .handled }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Search…", text: $search)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($searchFocused)
                .accessibilityLabel("Search models")
                .onChange(of: search) {
                    // Keep the highlight on something visible as the list narrows.
                    if highlighted == nil || !visibleModelIDs.contains(highlighted!) {
                        highlighted = visibleModelIDs.first
                    }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func providerHeader(_ label: String, icon: URL?) -> some View {
        HStack(spacing: 5) {
            if let icon, let image = agents.workspaceAppIcon(icon) {
                Image(nsImage: image).resizable().frame(width: 13, height: 13)
            }
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }

    private func modelRow(_ config: ChatModelConfig) -> some View {
        Button { choose(config) } label: {
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
        .id(config.id)
        .onHoverWithPointingHand { hovering in
            hoveredID = hovering ? config.id : nil
            if hovering { highlighted = config.id }
        }
        .background(rowTint(config.id), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityLabel(config.id == selectedID ? "\(config.label), selected" : config.label)
    }

    private func rowTint(_ id: UUID) -> Color {
        if highlighted == id || hoveredID == id { return .secondary.opacity(0.15) }
        return .clear
    }

    /// Selecting a model keeps the popover open when that model has an effort slider, so the
    /// effort can be adjusted in the same visit (web parity).
    private func choose(_ config: ChatModelConfig) {
        selectedID = config.id
        highlighted = config.id
        search = ""
        if config.selectableEfforts.isEmpty { show = false }
    }

    private func moveHighlight(_ delta: Int) -> KeyPress.Result {
        let ids = visibleModelIDs
        guard !ids.isEmpty else { return .ignored }
        let current = highlighted.flatMap { ids.firstIndex(of: $0) }
        // From nothing, down enters at the top and up at the bottom.
        let next = current.map { min(max($0 + delta, 0), ids.count - 1) } ?? (delta > 0 ? 0 : ids.count - 1)
        highlighted = ids[next]
        return .handled
    }

    private func chooseHighlighted() -> KeyPress.Result {
        guard let highlighted, let config = agents.modelConfigs.first(where: { $0.id == highlighted })
        else { return .ignored }
        choose(config)
        return .handled
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
                .onHoverWithPointingHand { _ in }
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
            // Every possible label is laid out invisibly underneath, so the chip keeps the width
            // of the longest one and dragging the slider can't resize the track under the cursor.
            ZStack {
                ForEach(efforts, id: \.self) { Text(effortLabel($0)).hidden() }
                Text(effortLabel(effort ?? efforts[0]))
            }
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
