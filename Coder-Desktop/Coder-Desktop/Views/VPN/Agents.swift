import SwiftUI

struct Agents<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState
    @State private var viewAll = false
    @State private var expandedItem: VPNMenuItem.ID?
    @State private var hasToggledExpansion: Bool = false
    @State private var scrollState = ScrollAffordanceState()
    private let defaultVisibleRows = Theme.defaultVisibleAgents

    let inspection = Inspection<Self>()

    var body: some View {
        Group {
            // Agents List
            if vpn.state == .connected {
                let items = vpn.menuState.sorted
                let visibleItems = viewAll ? items[...] : items.prefix(defaultVisibleRows)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(visibleItems, id: \.id) { agent in
                            MenuItemView(
                                item: agent,
                                baseAccessURL: state.baseAccessURL!,
                                expandedItem: $expandedItem,
                                userInteracted: $hasToggledExpansion
                            )
                            .padding(.horizontal, Theme.Size.trayMargin)
                        }
                    }
                    .background {
                        GeometryReader { contentProxy in
                            Color.clear.preference(
                                key: ScrollMetricsPreferenceKey.self,
                                value: ScrollMetrics(
                                    contentMinY: contentProxy.frame(in: .named("agentsScroll")).minY,
                                    contentHeight: contentProxy.size.height
                                )
                            )
                        }
                    }
                    .onChange(of: visibleItems) {
                        // If no workspaces are online, we should expand the first one to come online
                        if visibleItems.filter({ $0.status != .off }).isEmpty {
                            hasToggledExpansion = false
                            return
                        }
                        if hasToggledExpansion {
                            return
                        }
                        withAnimation(.snappy(duration: Theme.Animation.collapsibleDuration)) {
                            expandedItem = visibleItems.first?.id
                        }
                        hasToggledExpansion = true
                    }
                }
                .background {
                    GeometryReader { containerProxy in
                        Color.clear.preference(
                            key: ScrollMetricsPreferenceKey.self,
                            value: ScrollMetrics(containerHeight: containerProxy.size.height)
                        )
                    }
                }
                .coordinateSpace(name: "agentsScroll")
                .mask {
                    if viewAll {
                        ScrollAffordanceMask(state: scrollState)
                    } else {
                        Color.white
                    }
                }
                .overlay {
                    if viewAll, scrollState.showsTopAffordance || scrollState.showsBottomAffordance {
                        ScrollAffordanceChevronOverlay(state: scrollState)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(ScrollMetricsPreferenceKey.self) { metrics in
                    scrollState = ScrollAffordanceState(metrics: metrics)
                }
                .frame(maxHeight: 400)
                if items.count == 0 {
                    Text("No workspaces!")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, Theme.Size.trayInset)
                        .padding(.top, 2)
                }
                if items.count > defaultVisibleRows {
                    Button {
                        viewAll.toggle()
                    } label: {
                        ButtonRowView {
                            HStack(spacing: Theme.Size.trayPadding) {
                                Text(viewAll ? "Show less" : "Show all")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Spacer()
                                Image(systemName: viewAll ? "chevron.up" : "chevron.right")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, Theme.Size.trayMargin)
                    .buttonStyle(.plain)
                }
            }
        }.onReceive(inspection.notice) { inspection.visit(self, $0) } // ViewInspector
    }
}

private struct ScrollAffordanceState: Equatable {
    var showsTopAffordance = false
    var showsBottomAffordance = false

    init() {}

    init(metrics: ScrollMetrics) {
        let contentHeight = metrics.contentHeight
        let containerHeight = metrics.containerHeight
        let offsetY = max(-metrics.contentMinY, 0)
        let canScroll = contentHeight > containerHeight + 1

        guard canScroll else { return }

        showsTopAffordance = offsetY > 1
        showsBottomAffordance = offsetY + containerHeight < contentHeight - 1
    }
}

private struct ScrollMetrics: Equatable {
    var contentMinY: CGFloat = 0
    var contentHeight: CGFloat = 0
    var containerHeight: CGFloat = 0
}

private struct ScrollMetricsPreferenceKey: PreferenceKey {
    static let defaultValue = ScrollMetrics()

    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        let next = nextValue()
        if next.contentHeight != 0 {
            value.contentMinY = next.contentMinY
            value.contentHeight = next.contentHeight
        }
        if next.containerHeight != 0 {
            value.containerHeight = next.containerHeight
        }
    }
}

private struct ScrollAffordanceMask: View {
    let state: ScrollAffordanceState

    var body: some View {
        VStack(spacing: 0) {
            ScrollAffordanceMaskEdge(direction: .top, isVisible: state.showsTopAffordance)
            Color.white
            ScrollAffordanceMaskEdge(direction: .bottom, isVisible: state.showsBottomAffordance)
        }
        .allowsHitTesting(false)
    }
}

private struct ScrollAffordanceChevronOverlay: View {
    let state: ScrollAffordanceState

    var body: some View {
        VStack(spacing: 0) {
            if state.showsTopAffordance {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if state.showsBottomAffordance {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ScrollAffordanceMaskEdge: View {
    enum Direction {
        case top
        case bottom
    }

    let direction: Direction
    let isVisible: Bool

    var body: some View {
        Group {
            if isVisible {
                LinearGradient(
                    colors: direction == .top ? [.clear, .white] : [.white, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color.white
            }
        }
        .frame(height: 16)
    }
}
